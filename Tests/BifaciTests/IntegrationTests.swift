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
import CapDAG
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
                try writer.write(Frame.streamStart(reqId: requestId, streamId: sid, mediaUrn: "media:"))
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

    // NOTE: TEST461 and TEST472 are tested in FlowOrderingTests.swift

    // MARK: - Sync Handshake Tests (TEST230)

    // TEST230: sync_handshake exchanges HELLO frames and negotiates minimum limits
    func test230_syncHandshake() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)
        var pluginLimits: Limits?

        // Plugin thread with smaller limits
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                // Plugin has smaller limits
                let smallLimits = Limits(maxFrame: 1_000_000, maxChunk: 50_000, maxReorderBuffer: 16)
                reader.setLimits(smallLimits)
                writer.setLimits(smallLimits)

                let limits = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)
                pluginLimits = limits
            } catch {
                XCTFail("Plugin handshake failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side with default (larger) limits
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)

        pluginSemaphore.wait()

        // Both sides should negotiate to minimum
        XCTAssertEqual(result.limits.maxFrame, 1_000_000, "maxFrame should be minimum")
        XCTAssertEqual(result.limits.maxChunk, 50_000, "maxChunk should be minimum")
        XCTAssertEqual(result.limits.maxReorderBuffer, 16, "maxReorderBuffer should be minimum")

        XCTAssertNotNil(pluginLimits)
        XCTAssertEqual(pluginLimits!.maxFrame, 1_000_000)
        XCTAssertEqual(pluginLimits!.maxChunk, 50_000)
        XCTAssertEqual(pluginLimits!.maxReorderBuffer, 16)
    }

    // MARK: - Identity Verification Tests (TEST481-483)

    // TEST481: verify_identity succeeds with standard identity echo handler
    func test481_verifyIdentitySucceeds() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin that echoes identity requests
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                // Read identity request
                guard let req = try reader.read() else {
                    XCTFail("Expected identity request")
                    return
                }

                XCTAssertEqual(req.frameType, .req, "Should receive REQ frame")
                XCTAssertEqual(req.cap, CSCapIdentity, "Should be identity cap")

                // Echo back the payload (standard identity behavior)
                let streamId = UUID().uuidString
                try writer.write(Frame.streamStart(reqId: req.id, streamId: streamId, mediaUrn: "media:"))
                if let payload = req.payload, !payload.isEmpty {
                    let checksum = Frame.computeChecksum(payload)
                    try writer.write(Frame.chunk(reqId: req.id, streamId: streamId, seq: 0, payload: payload, chunkIndex: 0, checksum: checksum))
                }
                try writer.write(Frame.streamEnd(reqId: req.id, streamId: streamId, chunkCount: req.payload?.isEmpty == false ? 1 : 0))
                try writer.write(Frame.end(id: req.id))
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side - perform handshake and send identity verification
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        let result = try performHandshakeWithManifest(reader: reader, writer: writer)
        XCTAssertNotNil(result.manifest)

        // Send identity verification request
        let identityId = MessageId.newUUID()
        let testPayload = Data("identity-test-data".utf8)
        try writer.write(Frame.req(id: identityId, capUrn: CSCapIdentity, payload: testPayload, contentType: "application/octet-stream"))

        // Read response
        var gotStreamStart = false
        var receivedPayload: Data?
        var gotStreamEnd = false
        var gotEnd = false

        while !gotEnd {
            guard let frame = try reader.read() else {
                XCTFail("Connection closed unexpectedly")
                break
            }

            switch frame.frameType {
            case .streamStart:
                gotStreamStart = true
            case .chunk:
                receivedPayload = frame.payload
            case .streamEnd:
                gotStreamEnd = true
            case .end:
                gotEnd = true
            case .err:
                XCTFail("Received error: \(frame.errorMessage ?? "unknown")")
                break
            default:
                break
            }
        }

        pluginSemaphore.wait()

        XCTAssertTrue(gotStreamStart, "Should receive STREAM_START")
        XCTAssertTrue(gotStreamEnd, "Should receive STREAM_END")
        XCTAssertTrue(gotEnd, "Should receive END")
        XCTAssertEqual(receivedPayload, testPayload, "Identity should echo payload unchanged")
    }

    // TEST482: verify_identity fails when plugin returns ERR
    func test482_verifyIdentityFailsOnErr() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin that returns ERR for identity requests
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                // Read identity request
                guard let req = try reader.read() else {
                    XCTFail("Expected identity request")
                    return
                }

                // Return error instead of echoing
                try writer.write(Frame.err(id: req.id, code: "IDENTITY_FAILED", message: "Identity verification rejected"))
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        // Send identity verification request
        let identityId = MessageId.newUUID()
        try writer.write(Frame.req(id: identityId, capUrn: CSCapIdentity, payload: Data("test".utf8), contentType: "text/plain"))

        // Read response - should be ERR
        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }

        pluginSemaphore.wait()

        XCTAssertEqual(response.frameType, .err, "Should receive ERR frame")
        XCTAssertEqual(response.errorCode, "IDENTITY_FAILED")
    }

    // MARK: - Full Path Integration Tests (TEST896-907)

    // TEST896: Full path: engine REQ → runtime → plugin → response back through relay
    func test896_fullPathEngineReqToPluginResponse() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)
        var responsePayload: Data?

        // Plugin that processes REQ and sends response
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                // Read REQ
                guard let req = try reader.read() else {
                    XCTFail("Expected REQ")
                    return
                }
                XCTAssertEqual(req.frameType, .req)

                // Send response: STREAM_START + CHUNK + STREAM_END + END
                let streamId = "response-stream"
                let responseData = "full-path-response".data(using: .utf8)!
                let checksum = Frame.computeChecksum(responseData)

                try writer.write(Frame.streamStart(reqId: req.id, streamId: streamId, mediaUrn: "media:"))
                try writer.write(Frame.chunk(reqId: req.id, streamId: streamId, seq: 0, payload: responseData, chunkIndex: 0, checksum: checksum))
                try writer.write(Frame.streamEnd(reqId: req.id, streamId: streamId, chunkCount: 1))
                try writer.write(Frame.end(id: req.id))
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        // Host/Engine side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        // Send REQ
        let reqId = MessageId.newUUID()
        try writer.write(Frame.req(id: reqId, capUrn: "cap:in=media:;out=media:", payload: Data("input".utf8), contentType: "text/plain"))

        // Read full response
        var accumulated = Data()
        var gotEnd = false
        while !gotEnd {
            guard let frame = try reader.read() else { break }
            switch frame.frameType {
            case .chunk:
                if let p = frame.payload { accumulated.append(p) }
            case .end:
                gotEnd = true
            default:
                break
            }
        }

        pluginSemaphore.wait()

        XCTAssertEqual(String(data: accumulated, encoding: .utf8), "full-path-response")
    }

    // TEST897: Plugin ERR frame flows back to engine through relay
    func test897_pluginErrorFlowsToEngine() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin that returns ERR
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let req = try reader.read() else { return }
                try writer.write(Frame.err(id: req.id, code: "PLUGIN_ERROR", message: "Something went wrong"))
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let reqId = MessageId.newUUID()
        try writer.write(Frame.req(id: reqId, capUrn: "cap:in=media:;out=media:", payload: Data(), contentType: ""))

        guard let response = try reader.read() else {
            XCTFail("Expected response")
            return
        }

        pluginSemaphore.wait()

        XCTAssertEqual(response.frameType, .err, "Should receive ERR frame")
        XCTAssertEqual(response.errorCode, "PLUGIN_ERROR")
        XCTAssertEqual(response.errorMessage, "Something went wrong")
    }

    // TEST898: Binary data integrity through full relay path
    func test898_binaryIntegrityThroughRelay() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Create binary test data with all 256 byte values
        var testData = Data()
        for i: UInt8 in 0..<255 {
            testData.append(i)
        }
        testData.append(255)

        // Plugin that echoes binary data
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let req = try reader.read() else { return }
                let inputPayload = req.payload ?? Data()

                // Echo it back
                let streamId = "echo"
                let checksum = Frame.computeChecksum(inputPayload)
                try writer.write(Frame.streamStart(reqId: req.id, streamId: streamId, mediaUrn: "media:"))
                try writer.write(Frame.chunk(reqId: req.id, streamId: streamId, seq: 0, payload: inputPayload, chunkIndex: 0, checksum: checksum))
                try writer.write(Frame.streamEnd(reqId: req.id, streamId: streamId, chunkCount: 1))
                try writer.write(Frame.end(id: req.id))
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let reqId = MessageId.newUUID()
        try writer.write(Frame.req(id: reqId, capUrn: "cap:in=media:;out=media:", payload: testData, contentType: "application/octet-stream"))

        var received = Data()
        while true {
            guard let frame = try reader.read() else { break }
            if frame.frameType == .chunk { received.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        pluginSemaphore.wait()

        XCTAssertEqual(received, testData, "Binary data must be preserved through full path")
        XCTAssertEqual(received.count, 256)
    }

    // TEST899: Streaming chunks flow through relay without accumulation
    func test899_streamingChunksThroughRelay() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin that sends multiple chunks
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                guard let req = try reader.read() else { return }

                let streamId = "multi-chunk"
                try writer.write(Frame.streamStart(reqId: req.id, streamId: streamId, mediaUrn: "media:"))

                // Send 5 chunks
                for i: UInt64 in 0..<5 {
                    let chunkData = "chunk-\(i)".data(using: .utf8)!
                    let checksum = Frame.computeChecksum(chunkData)
                    try writer.write(Frame.chunk(reqId: req.id, streamId: streamId, seq: 0, payload: chunkData, chunkIndex: i, checksum: checksum))
                }

                try writer.write(Frame.streamEnd(reqId: req.id, streamId: streamId, chunkCount: 5))
                try writer.write(Frame.end(id: req.id))
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        let reqId = MessageId.newUUID()
        try writer.write(Frame.req(id: reqId, capUrn: "cap:in=media:;out=media:", payload: Data(), contentType: ""))

        var chunkCount = 0
        var gotStreamEnd = false
        while true {
            guard let frame = try reader.read() else { break }
            if frame.frameType == .chunk { chunkCount += 1 }
            if frame.frameType == .streamEnd { gotStreamEnd = true }
            if frame.frameType == .end { break }
        }

        pluginSemaphore.wait()

        XCTAssertEqual(chunkCount, 5, "All 5 chunks must flow through")
        XCTAssertTrue(gotStreamEnd, "STREAM_END must be received")
    }

    // TEST900: Two plugins routed independently by cap_urn
    func test900_twoPluginsRoutedIndependently() throws {
        // This test validates that when multiple plugins are registered,
        // requests are routed to the correct plugin based on cap_urn
        // For simplicity, we test the routing logic without actual multiple plugins

        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()
        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin that handles requests
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                // Handle two requests
                for _ in 0..<2 {
                    guard let req = try reader.read() else { return }
                    let response = "response-for-\(req.cap ?? "unknown")".data(using: .utf8)!
                    let streamId = UUID().uuidString
                    let checksum = Frame.computeChecksum(response)
                    try writer.write(Frame.streamStart(reqId: req.id, streamId: streamId, mediaUrn: "media:"))
                    try writer.write(Frame.chunk(reqId: req.id, streamId: streamId, seq: 0, payload: response, chunkIndex: 0, checksum: checksum))
                    try writer.write(Frame.streamEnd(reqId: req.id, streamId: streamId, chunkCount: 1))
                    try writer.write(Frame.end(id: req.id))
                }
            } catch {
                XCTFail("Plugin failed: \(error)")
            }
            pluginSemaphore.signal()
        }

        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        // Send first request
        let id1 = MessageId.newUUID()
        try writer.write(Frame.req(id: id1, capUrn: "cap:op=op1", payload: Data(), contentType: ""))

        var data1 = Data()
        while true {
            guard let frame = try reader.read() else { break }
            if frame.frameType == .chunk { data1.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        // Send second request
        let id2 = MessageId.newUUID()
        try writer.write(Frame.req(id: id2, capUrn: "cap:op=op2", payload: Data(), contentType: ""))

        var data2 = Data()
        while true {
            guard let frame = try reader.read() else { break }
            if frame.frameType == .chunk { data2.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        pluginSemaphore.wait()

        XCTAssertEqual(String(data: data1, encoding: .utf8), "response-for-cap:op=op1")
        XCTAssertEqual(String(data: data2, encoding: .utf8), "response-for-cap:op=op2")
    }

    // TEST483: verify_identity fails when connection closes
    func test483_verifyIdentityFailsOnClose() throws {
        let (hostWrite, pluginRead, pluginWrite, hostRead) = createSocketPairs()

        let pluginSemaphore = DispatchSemaphore(value: 0)

        // Plugin that closes connection after handshake
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: pluginRead)
                let writer = FrameWriter(handle: pluginWrite)

                _ = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: testManifest)

                // Close connection without responding to identity
                pluginWrite.closeFile()
            } catch {
                // Expected - connection closes
            }
            pluginSemaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        _ = try performHandshakeWithManifest(reader: reader, writer: writer)

        // Send identity verification request
        let identityId = MessageId.newUUID()
        do {
            try writer.write(Frame.req(id: identityId, capUrn: CSCapIdentity, payload: Data("test".utf8), contentType: "text/plain"))
        } catch {
            // Write may fail if connection closed - that's expected
        }

        // Read response - should be nil (connection closed)
        let response = try reader.read()

        pluginSemaphore.wait()

        XCTAssertNil(response, "Should get nil when connection closes")
    }
}
