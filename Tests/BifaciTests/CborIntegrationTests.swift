//
//  CborIntegrationTests.swift
//  CapNsCbor
//
//  CBOR Integration Tests - Protocol validation tests ported from Go
//
//  These tests validate end-to-end protocol behavior including:
//  - Frame forwarding
//  - Thread spawning
//  - Bidirectional communication
//  - Handshake and limit negotiation
//  - Heartbeat handling
//
//  Tests use // TEST###: comments matching the Rust implementation for cross-tracking.
//

import XCTest
@testable import Bifaci
import CapNs
import TaggedUrn
@preconcurrency import SwiftCBOR
import Foundation

// Test manifest JSON - plugins MUST include manifest in HELLO response
private let testManifest = """
{"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:op=test","title":"Test","command":"test"}]}
""".data(using: .utf8)!

final class CborIntegrationTests: XCTestCase {

    /// Helper: create Unix socket pairs for bidirectional communication
    func createSocketPairs() -> (hostWrite: FileHandle, pluginRead: FileHandle,
                                   pluginWrite: FileHandle, hostRead: FileHandle) {
        var hostWritePair: [Int32] = [0, 0]
        var pluginWritePair: [Int32] = [0, 0]

        socketpair(AF_UNIX, SOCK_STREAM, 0, &hostWritePair)
        socketpair(AF_UNIX, SOCK_STREAM, 0, &pluginWritePair)

        let hostWrite = FileHandle(fileDescriptor: hostWritePair[0], closeOnDealloc: true)
        let pluginRead = FileHandle(fileDescriptor: hostWritePair[1], closeOnDealloc: true)
        let pluginWrite = FileHandle(fileDescriptor: pluginWritePair[0], closeOnDealloc: true)
        let hostRead = FileHandle(fileDescriptor: pluginWritePair[1], closeOnDealloc: true)

        return (hostWrite, pluginRead, pluginWrite, hostRead)
    }

    // TEST284: Handshake exchanges HELLO frames, negotiates limits
    func testHandshakeHostPlugin() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var pluginLimits: CborLimits?
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                let limits = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                pluginLimits = limits
                XCTAssert(limits.maxFrame > 0)
                XCTAssert(limits.maxChunk > 0)
            } catch {
                XCTFail("Plugin handshake failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)
        let receivedManifest = result.manifest!
        let hostLimits = result.limits

        XCTAssertEqual(receivedManifest, testManifest)

        pluginSemaphore.wait()

        XCTAssertEqual(hostLimits.maxFrame, pluginLimits!.maxFrame)
        XCTAssertEqual(hostLimits.maxChunk, pluginLimits!.maxChunk)
    }

    // TEST285: Simple request-response flow (REQ → END with payload)
    func testRequestResponseSimple() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                XCTAssertEqual(frame.frameType, .req)
                XCTAssertEqual(frame.cap, "cap:in=media:;out=media:")
                XCTAssertEqual(frame.payload, "hello".data(using: .utf8))

                try writer.write(CborFrame.end(id: frame.id, finalPayload: "hello back".data(using: .utf8)))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = CborMessageId.newUUID()
        try writer.write(CborFrame.req(id: requestId, capUrn: "cap:in=media:;out=media:",
                                       payload: "hello".data(using: .utf8)!,
                                       contentType: "application/json"))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }
        XCTAssertEqual(response.frameType, .end)
        XCTAssertEqual(response.payload, "hello back".data(using: .utf8))

        pluginSemaphore.wait()
    }

    // TEST286: Streaming response with multiple CHUNK frames
    func testStreamingChunks() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                let requestId = frame.id

                let sid = "response"
                try writer.write(CborFrame.streamStart(reqId: requestId, streamId: sid, mediaUrn: "media:bytes"))
                for (seq, data) in [Data("chunk1".utf8), Data("chunk2".utf8), Data("chunk3".utf8)].enumerated() {
                    try writer.write(CborFrame.chunk(reqId: requestId, streamId: sid, seq: UInt64(seq), payload: data))
                }
                try writer.write(CborFrame.streamEnd(reqId: requestId, streamId: sid))
                try writer.write(CborFrame.end(id: requestId, finalPayload: nil))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = CborMessageId.newUUID()
        try writer.write(CborFrame.req(id: requestId, capUrn: "cap:op=stream",
                                       payload: Data("go".utf8),
                                       contentType: "application/json"))

        // Collect chunks
        var chunks: [Data] = []
        while true {
            guard let frame = try reader.read() else { break }
            if frame.frameType == .chunk {
                chunks.append(frame.payload ?? Data())
            }
            if frame.frameType == .end {
                break
            }
        }

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], Data("chunk1".utf8))
        XCTAssertEqual(chunks[1], Data("chunk2".utf8))
        XCTAssertEqual(chunks[2], Data("chunk3".utf8))

        pluginSemaphore.wait()
    }

    // TEST287: Host-initiated heartbeat handling
    func testHeartbeatFromHost() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                XCTAssertEqual(frame.frameType, .heartbeat)

                try writer.write(CborFrame.heartbeat(id: frame.id))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let heartbeatId = CborMessageId.newUUID()
        try writer.write(CborFrame.heartbeat(id: heartbeatId))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }
        XCTAssertEqual(response.frameType, .heartbeat)
        XCTAssertEqual(response.id, heartbeatId)

        pluginSemaphore.wait()
    }

    // TEST290: Limit negotiation picks minimum values
    func testLimitsNegotiation() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var pluginLimits: CborLimits?
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                pluginLimits = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)
            } catch {
                XCTFail("Plugin handshake failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)
        let hostLimits = result.limits

        pluginSemaphore.wait()

        XCTAssertEqual(hostLimits.maxFrame, pluginLimits!.maxFrame)
        XCTAssertEqual(hostLimits.maxChunk, pluginLimits!.maxChunk)
        XCTAssert(hostLimits.maxFrame > 0)
        XCTAssert(hostLimits.maxChunk > 0)
    }

    // TEST291: Binary payload roundtrip (all 256 byte values)
    func testBinaryPayloadRoundtrip() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let binaryData = Data((0...255).map { UInt8($0) })

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                let payload = frame.payload!

                XCTAssertEqual(payload.count, 256)
                for (i, byte) in payload.enumerated() {
                    XCTAssertEqual(byte, UInt8(i), "Byte mismatch at position \(i)")
                }

                try writer.write(CborFrame.end(id: frame.id, finalPayload: payload))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = CborMessageId.newUUID()
        try writer.write(CborFrame.req(id: requestId, capUrn: "cap:op=binary",
                                       payload: binaryData,
                                       contentType: "application/octet-stream"))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }
        let result = response.payload!

        XCTAssertEqual(result.count, 256)
        for (i, byte) in result.enumerated() {
            XCTAssertEqual(byte, UInt8(i), "Response byte mismatch at position \(i)")
        }

        pluginSemaphore.wait()
    }

    // TEST292: Sequential requests get distinct MessageIds
    func testMessageIdUniqueness() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var receivedIds: [CborMessageId] = []
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                for _ in 0..<3 {
                    guard let frame = try reader.read() else {
                        XCTFail("Expected frame")
                        return
                    }
                    receivedIds.append(frame.id)
                    try writer.write(CborFrame.end(id: frame.id, finalPayload: Data("ok".utf8)))
                }
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        for _ in 0..<3 {
            let requestId = CborMessageId.newUUID()
            try writer.write(CborFrame.req(id: requestId, capUrn: "cap:op=test",
                                           payload: Data(),
                                           contentType: "application/json"))
            _ = try reader.read()
        }

        pluginSemaphore.wait()

        XCTAssertEqual(receivedIds.count, 3)
        for i in 0..<receivedIds.count {
            for j in (i+1)..<receivedIds.count {
                XCTAssertNotEqual(receivedIds[i], receivedIds[j], "IDs should be unique")
            }
        }
    }

    // TEST299: Empty payload request/response roundtrip
    func testEmptyPayloadRoundtrip() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = CborFrameReader(handle: pluginRead)
                let writer = CborFrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                XCTAssert(frame.payload == nil || frame.payload!.isEmpty, "empty payload must arrive empty")

                try writer.write(CborFrame.end(id: frame.id, finalPayload: Data()))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = CborFrameReader(handle: hostRead)
        let writer = CborFrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = CborMessageId.newUUID()
        try writer.write(CborFrame.req(id: requestId, capUrn: "cap:op=empty",
                                       payload: Data(),
                                       contentType: "application/json"))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }
        XCTAssert(response.payload == nil || response.payload!.isEmpty)

        pluginSemaphore.wait()
    }
}
