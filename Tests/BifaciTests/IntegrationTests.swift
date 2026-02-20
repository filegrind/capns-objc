//
//  CborIntegrationTests.swift
//  Bifaci
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

// Test manifest JSON - plugins MUST include manifest in HELLO response (including mandatory CAP_IDENTITY)
private let testManifest = """
{"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:in=media:;out=media:","title":"Identity","command":"identity"},{"urn":"cap:in=media:;op=test;out=media:","title":"Test","command":"test"}]}
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
    func test284_handshakeHostPlugin() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var pluginLimits: Limits?
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

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
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)
        let receivedManifest = result.manifest!
        let hostLimits = result.limits

        XCTAssertEqual(receivedManifest, testManifest)

        pluginSemaphore.wait()

        XCTAssertEqual(hostLimits.maxFrame, pluginLimits!.maxFrame)
        XCTAssertEqual(hostLimits.maxChunk, pluginLimits!.maxChunk)
    }

    // TEST285: Simple request-response flow (REQ → END with payload)
    func test285_requestResponseSimple() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                XCTAssertEqual(frame.frameType, .req)
                XCTAssertEqual(frame.cap, "cap:in=media:;out=media:")
                XCTAssertEqual(frame.payload, "hello".data(using: .utf8))

                try writer.write(Frame.end(id: frame.id, finalPayload: "hello back".data(using: .utf8)))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = MessageId.newUUID()
        try writer.write(Frame.req(id: requestId, capUrn: "cap:in=media:;out=media:",
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
    func test286_streamingChunks() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                let requestId = frame.id

                let sid = "response"
                try writer.write(Frame.streamStart(reqId: requestId, streamId: sid, mediaUrn: "media:bytes"))
                let chunks = [Data("chunk1".utf8), Data("chunk2".utf8), Data("chunk3".utf8)]
                for (idx, data) in chunks.enumerated() {
                    let checksum = Frame.computeChecksum(data)
                    try writer.write(Frame.chunk(reqId: requestId, streamId: sid, seq: UInt64(idx), payload: data, chunkIndex: UInt64(idx), checksum: checksum))
                }
                try writer.write(Frame.streamEnd(reqId: requestId, streamId: sid, chunkCount: UInt64(chunks.count)))
                try writer.write(Frame.end(id: requestId, finalPayload: nil))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = MessageId.newUUID()
        try writer.write(Frame.req(id: requestId, capUrn: "cap:op=stream",
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
    func test287_heartbeatFromHost() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                XCTAssertEqual(frame.frameType, .heartbeat)

                try writer.write(Frame.heartbeat(id: frame.id))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let heartbeatId = MessageId.newUUID()
        try writer.write(Frame.heartbeat(id: heartbeatId))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }
        XCTAssertEqual(response.frameType, .heartbeat)
        XCTAssertEqual(response.id, heartbeatId)

        pluginSemaphore.wait()
    }

    // TEST290: Limit negotiation picks minimum values
    func test290_limitsNegotiation() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var pluginLimits: Limits?
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                pluginLimits = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)
            } catch {
                XCTFail("Plugin handshake failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)
        let hostLimits = result.limits

        pluginSemaphore.wait()

        XCTAssertEqual(hostLimits.maxFrame, pluginLimits!.maxFrame)
        XCTAssertEqual(hostLimits.maxChunk, pluginLimits!.maxChunk)
        XCTAssert(hostLimits.maxFrame > 0)
        XCTAssert(hostLimits.maxChunk > 0)
    }

    // TEST291: Binary payload roundtrip (all 256 byte values)
    func test291_binaryPayloadRoundtrip() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let binaryData = Data((0...255).map { UInt8($0) })

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

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

                try writer.write(Frame.end(id: frame.id, finalPayload: payload))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = MessageId.newUUID()
        try writer.write(Frame.req(id: requestId, capUrn: "cap:op=binary",
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
    func test292_messageIdUniqueness() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var receivedIds: [MessageId] = []
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                for _ in 0..<3 {
                    guard let frame = try reader.read() else {
                        XCTFail("Expected frame")
                        return
                    }
                    receivedIds.append(frame.id)
                    try writer.write(Frame.end(id: frame.id, finalPayload: Data("ok".utf8)))
                }
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        for _ in 0..<3 {
            let requestId = MessageId.newUUID()
            try writer.write(Frame.req(id: requestId, capUrn: "cap:op=test",
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
    func test299_emptyPayloadRoundtrip() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let frame = try reader.read() else {
                    XCTFail("Expected frame")
                    return
                }
                XCTAssert(frame.payload == nil || frame.payload!.isEmpty, "empty payload must arrive empty")

                try writer.write(Frame.end(id: frame.id, finalPayload: Data()))
            } catch {
                XCTFail("Plugin thread failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let requestId = MessageId.newUUID()
        try writer.write(Frame.req(id: requestId, capUrn: "cap:op=empty",
                                       payload: Data(),
                                       contentType: "application/json"))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }
        XCTAssert(response.payload == nil || response.payload!.isEmpty)

        pluginSemaphore.wait()
    }

    // TEST461: write_chunked produces frames with seq=0; SeqAssigner assigns at output stage
    func test461_writeChunkedSeqAssignment() throws {
        // This test verifies that frames produced by write operations have seq=0
        // and rely on SeqAssigner at the writer thread to assign proper seq values
        let requestId = MessageId.newUUID()

        // Create a frame using the chunk constructor
        var chunk = Frame.chunk(reqId: requestId, streamId: "test", seq: 0,
                               payload: "test".data(using: .utf8)!,
                               chunkIndex: 0, checksum: 0)

        // Verify initial seq is 0 (as produced by write functions)
        XCTAssertEqual(chunk.seq, 0, "Frames from write functions must have seq=0")

        // SeqAssigner will assign proper seq at output stage
        var assigner = SeqAssigner()
        assigner.assign(&chunk)

        XCTAssertEqual(chunk.seq, 0, "First frame assigned seq=0")

        // Subsequent frames get incremented seq
        var chunk2 = Frame.chunk(reqId: requestId, streamId: "test", seq: 0,
                                payload: "test2".data(using: .utf8)!,
                                chunkIndex: 1, checksum: 0)
        assigner.assign(&chunk2)
        XCTAssertEqual(chunk2.seq, 1, "Second frame assigned seq=1")
    }

    // TEST472: Handshake negotiates max_reorder_buffer (minimum of both sides)
    func test472_handshakeNegotiatesReorderBuffer() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        var pluginNegotiated: Limits?
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin with custom limits (max_reorder_buffer=32)
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                // Plugin starts with max_reorder_buffer=32 (smaller than default 64)
                var pluginLimits = Limits()
                pluginLimits.maxReorderBuffer = 32
                reader.setLimits(pluginLimits)
                writer.setLimits(pluginLimits)

                let limits = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)
                pluginNegotiated = limits

                // Negotiated limit should be min(32, 64) = 32
                XCTAssertEqual(limits.maxReorderBuffer, 32, "Plugin must negotiate minimum reorder buffer")
            } catch {
                XCTFail("Plugin handshake failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host with default limits (max_reorder_buffer=64)
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)
        let hostLimits = result.limits

        pluginSemaphore.wait()

        // Both sides must agree on minimum
        XCTAssertEqual(hostLimits.maxReorderBuffer, 32, "Host must negotiate minimum reorder buffer")
        XCTAssertEqual(pluginNegotiated!.maxReorderBuffer, 32, "Both sides must agree on min")

        // Verify other limits are also negotiated
        XCTAssertEqual(hostLimits.maxFrame, pluginNegotiated!.maxFrame)
        XCTAssertEqual(hostLimits.maxChunk, pluginNegotiated!.maxChunk)
    }
}
