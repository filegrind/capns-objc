import XCTest
import Foundation
@testable import CapNsCbor

/// Comprehensive tests for the CBOR plugin communication protocol.
/// These tests verify the complete host-plugin communication flow
/// using in-memory pipes to simulate stdin/stdout.
@available(macOS 10.15.4, iOS 13.4, *)
@MainActor
final class CborRuntimeTests: XCTestCase, @unchecked Sendable {

    // MARK: - Test Infrastructure

    /// Creates a pipe pair for bidirectional communication
    private func createPipePair() -> (hostToPlugin: Pipe, pluginToHost: Pipe) {
        let hostToPlugin = Pipe()  // Host writes to plugin's stdin
        let pluginToHost = Pipe()  // Plugin writes to host via stdout
        return (hostToPlugin, pluginToHost)
    }

    /// Test manifest JSON - plugins MUST include manifest in HELLO response
    nonisolated static let testManifestJSON = """
    {"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:op=test","title":"Test","command":"test"}]}
    """
    nonisolated static let testManifestData = testManifestJSON.data(using: .utf8)!

    /// Create a HELLO frame with required test manifest
    nonisolated static func helloWithManifest(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) -> CborFrame {
        return CborFrame.hello(maxFrame: maxFrame, maxChunk: maxChunk, manifest: testManifestData)
    }

    // MARK: - Handshake Tests

    func testHandshakeSuccess() async throws {
        let pipes = createPipePair()

        // Simulate plugin sending HELLO response in background
        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        // Run plugin simulation in a Task
        let pluginTask = Task.detached { @Sendable in
            // Wait for host's HELLO
            guard let hostHello = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO from host")
            }
            guard hostHello.frameType == .hello else {
                throw CborPluginHostError.handshakeFailed("Expected HELLO, got \(hostHello.frameType)")
            }

            // Send plugin's HELLO with manifest (required)
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
        }

        // Create host (this performs handshake)
        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )
        XCTAssertFalse(host.isClosed)

        // Verify manifest was received
        XCTAssertNotNil(host.pluginManifest, "Host should have received plugin manifest")
        let manifest = try JSONSerialization.jsonObject(with: host.pluginManifest!) as! [String: Any]
        XCTAssertEqual(manifest["name"] as? String, "TestPlugin")

        // Wait for plugin task to complete
        try await pluginTask.value
    }

    func testHandshakeLimitsNegotiation() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        // Plugin has smaller limits
        let pluginMaxFrame = 500_000
        let pluginMaxChunk = 100_000

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            // Use custom limits but still include manifest
            let pluginHello = CborFrame.hello(maxFrame: pluginMaxFrame, maxChunk: pluginMaxChunk, manifest: CborRuntimeTests.testManifestData)
            try pluginWriter.write(pluginHello)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        // Negotiated limits should be minimum of both
        XCTAssertEqual(host.negotiatedLimits.maxFrame, pluginMaxFrame)
        XCTAssertEqual(host.negotiatedLimits.maxChunk, pluginMaxChunk)

        try await pluginTask.value
    }

    func testHandshakeFailsOnMissingManifest() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            // Send HELLO without manifest - this should fail
            let pluginHello = CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK)
            try pluginWriter.write(pluginHello)
        }

        do {
            _ = try CborPluginHost(
                stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
                stdoutHandle: pipes.pluginToHost.fileHandleForReading
            )
            XCTFail("Should have thrown handshake error due to missing manifest")
        } catch let error as CborPluginHostError {
            if case .handshakeFailed(let msg) = error {
                XCTAssertTrue(msg.contains("missing required manifest"), "Error should mention missing manifest: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try? await pluginTask.value
    }

    func testHandshakeFailsOnWrongFrameType() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            // Send wrong frame type instead of HELLO
            let wrongFrame = CborFrame.err(id: .uint(0), code: "WRONG", message: "Not a HELLO")
            try pluginWriter.write(wrongFrame)
        }

        do {
            _ = try CborPluginHost(
                stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
                stdoutHandle: pipes.pluginToHost.fileHandleForReading
            )
            XCTFail("Should have thrown handshake error")
        } catch let error as CborPluginHostError {
            if case .handshakeFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Expected HELLO"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try? await pluginTask.value
    }

    // MARK: - Request/Response Tests

    func testSendRequestReceiveSingleResponse() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let expectedResponse = "Hello, World!".data(using: .utf8)!

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }
            guard req.frameType == .req else {
                throw CborPluginHostError.handshakeFailed("Expected REQ, got \(req.frameType)")
            }
            guard req.cap == "cap:op=test" else {
                throw CborPluginHostError.handshakeFailed("Wrong cap: \(req.cap ?? "nil")")
            }

            // Send response
            let res = CborFrame.res(id: req.id, payload: expectedResponse, contentType: "text/plain")
            try pluginWriter.write(res)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.call(capUrn: "cap:op=test", payload: "request".data(using: .utf8)!)
        XCTAssertEqual(response.concatenated(), expectedResponse)

        try await pluginTask.value
    }

    func testSendRequestReceiveStreamingResponse() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let chunks = ["chunk1", "chunk2", "chunk3"]

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send streaming chunks
            for (i, chunk) in chunks.enumerated() {
                var frame = CborFrame.chunk(id: req.id, seq: UInt64(i), payload: chunk.data(using: .utf8)!)
                if i == chunks.count - 1 {
                    frame.eof = true
                }
                try pluginWriter.write(frame)
            }
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.call(capUrn: "cap:op=stream", payload: Data())

        // Response should be all chunks concatenated
        let expectedResponse = chunks.joined()
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), expectedResponse)

        try await pluginTask.value
    }

    func testSendRequestReceiveEndFrame() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let finalPayload = "final".data(using: .utf8)!

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send END frame
            let end = CborFrame.end(id: req.id, finalPayload: finalPayload)
            try pluginWriter.write(end)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.call(capUrn: "cap:op=test", payload: Data())
        XCTAssertEqual(response.concatenated(), finalPayload)

        try await pluginTask.value
    }

    func testChunksWithLogFramesInterleaved() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send interleaved chunks and logs
            try pluginWriter.write(CborFrame.log(id: req.id, level: "info", message: "Starting..."))
            try pluginWriter.write(CborFrame.chunk(id: req.id, seq: 0, payload: "A".data(using: .utf8)!))
            try pluginWriter.write(CborFrame.log(id: req.id, level: "debug", message: "Progress..."))
            var lastChunk = CborFrame.chunk(id: req.id, seq: 1, payload: "B".data(using: .utf8)!)
            lastChunk.eof = true
            try pluginWriter.write(lastChunk)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.call(capUrn: "cap:op=test", payload: Data())
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "AB")

        try await pluginTask.value
    }

    // MARK: - Error Handling Tests

    func testPluginErrorResponse() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send error response
            let err = CborFrame.err(id: req.id, code: "NOT_FOUND", message: "Cap not found")
            try pluginWriter.write(err)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        do {
            _ = try await host.call(capUrn: "cap:op=missing", payload: Data())
            XCTFail("Should have thrown error")
        } catch let error as CborPluginHostError {
            if case .pluginError(let code, let message) = error {
                XCTAssertEqual(code, "NOT_FOUND")
                XCTAssertEqual(message, "Cap not found")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try await pluginTask.value
    }

    func testRequestAfterCloseFails() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        // Close the host
        host.close()

        // Try to send request after close
        do {
            _ = try host.request(capUrn: "cap:op=test", payload: Data())
            XCTFail("Should have thrown error")
        } catch let error as CborPluginHostError {
            if case .closed = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }

        try? await pluginTask.value
    }

    // MARK: - Heartbeat Tests

    func testHeartbeatExchange() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        // Use actor to track heartbeat ID safely across tasks
        actor HeartbeatTracker {
            var receivedId: CborMessageId?
            func setId(_ id: CborMessageId) { receivedId = id }
            func getId() -> CborMessageId? { receivedId }
        }
        let tracker = HeartbeatTracker()

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for heartbeat from host
            guard let heartbeat = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No heartbeat")
            }
            guard heartbeat.frameType == .heartbeat else {
                throw CborPluginHostError.handshakeFailed("Expected HEARTBEAT, got \(heartbeat.frameType)")
            }
            await tracker.setId(heartbeat.id)

            // Respond with heartbeat (same ID)
            let response = CborFrame.heartbeat(id: heartbeat.id)
            try pluginWriter.write(response)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        try host.sendHeartbeat()

        // Wait for plugin to process
        try await pluginTask.value

        let receivedId = await tracker.getId()
        XCTAssertNotNil(receivedId)
    }

    func testHeartbeatDuringRequest() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send a heartbeat BEFORE responding (simulates plugin health check)
            let heartbeat = CborFrame.heartbeat(id: .newUUID())
            try pluginWriter.write(heartbeat)

            // Now wait for heartbeat response from host, then send actual response
            guard let heartbeatResp = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No heartbeat response")
            }
            guard heartbeatResp.frameType == .heartbeat else {
                throw CborPluginHostError.handshakeFailed("Expected heartbeat response")
            }

            // Send actual request response
            let res = CborFrame.res(id: req.id, payload: "done".data(using: .utf8)!, contentType: "text/plain")
            try pluginWriter.write(res)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        // This should work even though plugin sends heartbeat mid-request
        let response = try await host.call(capUrn: "cap:op=test", payload: Data())
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "done")

        try await pluginTask.value
    }

    // MARK: - Frame Encoding/Decoding Tests

    func testAllFrameTypesRoundtrip() throws {
        let testCases: [(CborFrame, String)] = [
            (CborFrame.hello(maxFrame: 1_000_000, maxChunk: 100_000), "HELLO"),
            (CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: "data".data(using: .utf8)!, contentType: "text/plain"), "REQ"),
            (CborFrame.res(id: .newUUID(), payload: "result".data(using: .utf8)!, contentType: "text/plain"), "RES"),
            (CborFrame.chunk(id: .newUUID(), seq: 5, payload: "chunk".data(using: .utf8)!), "CHUNK"),
            (CborFrame.end(id: .newUUID(), finalPayload: "final".data(using: .utf8)), "END"),
            (CborFrame.log(id: .newUUID(), level: "info", message: "test log"), "LOG"),
            (CborFrame.err(id: .newUUID(), code: "ERROR", message: "test error"), "ERR"),
            (CborFrame.heartbeat(id: .newUUID()), "HEARTBEAT"),
        ]

        for (original, name) in testCases {
            let encoded = try encodeFrame(original)
            let decoded = try decodeFrame(encoded)

            XCTAssertEqual(decoded.frameType, original.frameType, "\(name) frame type mismatch")
            XCTAssertEqual(decoded.id, original.id, "\(name) ID mismatch")
            XCTAssertEqual(decoded.seq, original.seq, "\(name) seq mismatch")
            XCTAssertEqual(decoded.payload, original.payload, "\(name) payload mismatch")
            XCTAssertEqual(decoded.cap, original.cap, "\(name) cap mismatch")
            XCTAssertEqual(decoded.contentType, original.contentType, "\(name) contentType mismatch")
        }
    }

    func testHelloFrameMetadataRoundtrip() throws {
        let original = CborFrame.hello(maxFrame: 123456, maxChunk: 7890)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.helloMaxFrame, 123456)
        XCTAssertEqual(decoded.helloMaxChunk, 7890)
    }

    func testErrFrameMetadataRoundtrip() throws {
        let original = CborFrame.err(id: .newUUID(), code: "TEST_CODE", message: "Test message")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.errorCode, "TEST_CODE")
        XCTAssertEqual(decoded.errorMessage, "Test message")
    }

    func testLogFrameMetadataRoundtrip() throws {
        let original = CborFrame.log(id: .newUUID(), level: "warn", message: "Warning message")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.logLevel, "warn")
        XCTAssertEqual(decoded.logMessage, "Warning message")
    }

    func testChunkWithOffsetRoundtrip() throws {
        // Test first chunk (seq=0) - should have len set
        let firstChunk = CborFrame.chunkWithOffset(
            id: .newUUID(),
            seq: 0,
            payload: "first".data(using: .utf8)!,
            offset: 0,
            totalLen: 5000,
            isLast: false
        )
        let encodedFirst = try encodeFrame(firstChunk)
        let decodedFirst = try decodeFrame(encodedFirst)

        XCTAssertEqual(decodedFirst.seq, 0)
        XCTAssertEqual(decodedFirst.offset, 0)
        XCTAssertEqual(decodedFirst.len, 5000)  // len is set on first chunk
        XCTAssertFalse(decodedFirst.isEof)

        // Test subsequent chunk (seq > 0) - should NOT have len set
        let laterChunk = CborFrame.chunkWithOffset(
            id: .newUUID(),
            seq: 3,
            payload: "later".data(using: .utf8)!,
            offset: 1000,
            totalLen: 5000,  // totalLen provided but should be ignored for seq > 0
            isLast: false
        )
        let encodedLater = try encodeFrame(laterChunk)
        let decodedLater = try decodeFrame(encodedLater)

        XCTAssertEqual(decodedLater.seq, 3)
        XCTAssertEqual(decodedLater.offset, 1000)
        XCTAssertNil(decodedLater.len)  // len is only on first chunk
        XCTAssertFalse(decodedLater.isEof)

        // Test final chunk
        let lastChunk = CborFrame.chunkWithOffset(
            id: .newUUID(),
            seq: 5,
            payload: "last".data(using: .utf8)!,
            offset: 4000,
            totalLen: nil,
            isLast: true
        )
        let encodedLast = try encodeFrame(lastChunk)
        let decodedLast = try decodeFrame(encodedLast)

        XCTAssertEqual(decodedLast.seq, 5)
        XCTAssertEqual(decodedLast.offset, 4000)
        XCTAssertNil(decodedLast.len)
        XCTAssertTrue(decodedLast.isEof)
    }

    // MARK: - Message ID Tests

    func testMessageIdUUIDEquality() {
        let uuid = UUID()
        let id1 = CborMessageId(uuid: uuid)
        let id2 = CborMessageId(uuid: uuid)

        XCTAssertEqual(id1, id2)
    }

    func testMessageIdUIntEquality() {
        let id1 = CborMessageId.uint(12345)
        let id2 = CborMessageId.uint(12345)
        let id3 = CborMessageId.uint(67890)

        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }

    func testMessageIdHashable() {
        var set: Set<CborMessageId> = []

        let id1 = CborMessageId.newUUID()
        let id2 = CborMessageId.newUUID()
        let id3 = id1

        set.insert(id1)
        set.insert(id2)
        set.insert(id3)

        XCTAssertEqual(set.count, 2)  // id3 is same as id1
    }

    func testMessageIdUUIDString() {
        let uuidStr = "550e8400-e29b-41d4-a716-446655440000"
        let id = CborMessageId(uuidString: uuidStr)
        XCTAssertNotNil(id)
        XCTAssertEqual(id?.uuidString?.lowercased(), uuidStr.lowercased())
    }

    // MARK: - Limits Tests

    func testLimitsNegotiationTakesMinimum() {
        let local = CborLimits(maxFrame: 1_000_000, maxChunk: 100_000)
        let remote = CborLimits(maxFrame: 500_000, maxChunk: 200_000)
        let negotiated = local.negotiate(with: remote)

        XCTAssertEqual(negotiated.maxFrame, 500_000)   // min(1_000_000, 500_000)
        XCTAssertEqual(negotiated.maxChunk, 100_000)   // min(100_000, 200_000)
    }

    func testDefaultLimits() {
        let limits = CborLimits()
        XCTAssertEqual(limits.maxFrame, DEFAULT_MAX_FRAME)
        XCTAssertEqual(limits.maxChunk, DEFAULT_MAX_CHUNK)
    }
}

// MARK: - Integration Tests

@available(macOS 10.15.4, iOS 13.4, *)
@MainActor
final class CborProtocolIntegrationTests: XCTestCase, @unchecked Sendable {

    /// Tests full bidirectional communication simulating a complete plugin interaction
    func testFullProtocolExchange() async throws {
        // Create pipes for host <-> plugin communication
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        // Plugin reads from hostToPlugin, writes to pluginToHost
        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Simulate plugin behavior
        let pluginTask = Task.detached { @Sendable in
            // 1. Receive HELLO from host
            guard let hello = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            guard hello.frameType == .hello else {
                throw CborPluginHostError.handshakeFailed("Expected HELLO")
            }

            // 2. Send HELLO response
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // 3. Process requests (handle 3 requests then exit)
            for _ in 0..<3 {
                guard let frame = try pluginReader.read() else {
                    break
                }

                switch frame.frameType {
                case .req:
                    // Echo request payload back as response
                    let response = CborFrame.res(id: frame.id, payload: frame.payload ?? Data(), contentType: "application/octet-stream")
                    try pluginWriter.write(response)

                case .heartbeat:
                    // Respond to heartbeat
                    try pluginWriter.write(CborFrame.heartbeat(id: frame.id))

                default:
                    break
                }
            }
        }

        // Host behavior
        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        // Send requests and verify responses
        let testData1 = "Hello, Plugin!".data(using: .utf8)!
        let response1 = try await host.call(capUrn: "cap:op=echo", payload: testData1)
        XCTAssertEqual(response1.concatenated(), testData1)

        let testData2 = "Second request".data(using: .utf8)!
        let response2 = try await host.call(capUrn: "cap:op=echo", payload: testData2)
        XCTAssertEqual(response2.concatenated(), testData2)

        // Send heartbeat
        try host.sendHeartbeat()

        // Wait for plugin to complete
        try await pluginTask.value
    }

    /// Tests that the protocol handles binary data correctly
    func testBinaryDataTransfer() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Create binary test data with all byte values
        var binaryData = Data()
        for i: UInt8 in 0...255 {
            binaryData.append(i)
        }

        let pluginTask = Task.detached { @Sendable [binaryData] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            guard let req = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }

            // Verify we received the binary data correctly
            guard req.payload == binaryData else {
                throw CborPluginHostError.handshakeFailed("Binary data mismatch")
            }

            // Echo it back
            try pluginWriter.write(CborFrame.res(id: req.id, payload: binaryData, contentType: "application/octet-stream"))
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.call(capUrn: "cap:op=binary", payload: binaryData)
        XCTAssertEqual(response.concatenated(), binaryData)

        try await pluginTask.value
    }

    /// Tests large payload chunking
    func testLargePayloadChunking() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Create large payload that will need chunking
        let largePayload = Data(repeating: 0x42, count: 100_000)

        let pluginTask = Task.detached { @Sendable [largePayload] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            guard let req = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }

            // Send response in chunks
            let chunkSize = 10_000
            var offset = 0
            var seq: UInt64 = 0

            while offset < largePayload.count {
                let end = min(offset + chunkSize, largePayload.count)
                let chunkData = largePayload.subdata(in: offset..<end)
                let isLast = end >= largePayload.count

                var frame = CborFrame.chunk(id: req.id, seq: seq, payload: chunkData)
                if isLast {
                    frame.eof = true
                }
                try pluginWriter.write(frame)

                offset = end
                seq += 1
            }
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.call(capUrn: "cap:op=large", payload: Data())
        XCTAssertEqual(response.concatenated().count, largePayload.count)
        XCTAssertEqual(response.concatenated(), largePayload)

        try await pluginTask.value
    }

    /// Tests concurrent requests are properly multiplexed
    func testConcurrentRequests() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Process 3 requests (may arrive in any order)
            var receivedRequests: [CborMessageId] = []
            for _ in 0..<3 {
                guard let req = try pluginReader.read() else {
                    throw CborPluginHostError.receiveFailed("No request")
                }
                receivedRequests.append(req.id)
            }

            // Respond in reverse order to test multiplexing
            for reqId in receivedRequests.reversed() {
                try pluginWriter.write(CborFrame.res(id: reqId, payload: "response".data(using: .utf8)!, contentType: "text/plain"))
            }
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        // Send 3 requests concurrently
        async let r1 = host.call(capUrn: "cap:op=test1", payload: Data())
        async let r2 = host.call(capUrn: "cap:op=test2", payload: Data())
        async let r3 = host.call(capUrn: "cap:op=test3", payload: Data())

        let responses = try await [r1, r2, r3]

        // All should succeed despite out-of-order responses
        for response in responses {
            XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "response")
        }

        try await pluginTask.value
    }

    /// Tests the wire protocol for bidirectional communication (plugin invoking host caps).
    ///
    /// This test manually exercises the protocol:
    /// 1. Host sends REQ to plugin
    /// 2. Plugin sends REQ back to host (plugin invoking host cap)
    /// 3. Host receives the plugin's REQ and sends RES back
    /// 4. Plugin receives response and completes original request
    ///
    /// This uses raw frame reader/writer to test the protocol without CborPluginHost,
    /// since CborPluginHost's call() API doesn't expose cap_request handling.
    func testBidirectionalProtocolWireFormat() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        // Host-side frame reader/writer (manual protocol handling)
        let hostReader = CborFrameReader(handle: pluginToHost.fileHandleForReading)
        let hostWriter = CborFrameWriter(handle: hostToPlugin.fileHandleForWriting)

        // Plugin-side frame reader/writer
        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Track the request IDs for verification
        actor RequestTracker {
            var hostRequestId: CborMessageId?
            var pluginPeerRequestId: CborMessageId?
            var pluginPeerCapUrn: String?
            var pluginPeerPayload: Data?
            var hostPeerResponsePayload: Data?
            var pluginFinalResponse: Data?

            func setHostRequest(_ id: CborMessageId) { hostRequestId = id }
            func setPluginPeerRequest(id: CborMessageId, capUrn: String, payload: Data) {
                pluginPeerRequestId = id
                pluginPeerCapUrn = capUrn
                pluginPeerPayload = payload
            }
            func setHostPeerResponse(_ payload: Data) { hostPeerResponsePayload = payload }
            func setPluginFinalResponse(_ payload: Data) { pluginFinalResponse = payload }

            func getHostRequestId() -> CborMessageId? { hostRequestId }
            func getPluginPeerCapUrn() -> String? { pluginPeerCapUrn }
            func getPluginFinalResponse() -> Data? { pluginFinalResponse }
        }
        let tracker = RequestTracker()

        // Plugin task - simulates a plugin that invokes a host cap during request handling
        let pluginTask = Task.detached { @Sendable [tracker] in
            // 1. Receive HELLO from host
            guard let hello = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO from host")
            }
            guard hello.frameType == .hello else {
                throw CborPluginHostError.handshakeFailed("Expected HELLO, got \(hello.frameType)")
            }

            // 2. Send HELLO response with manifest
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // 3. Receive REQ from host
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No REQ from host")
            }
            guard req.frameType == .req else {
                throw CborPluginHostError.handshakeFailed("Expected REQ, got \(req.frameType)")
            }
            let hostRequestId = req.id

            // 4. Plugin sends its own REQ to host (bidirectional: plugin -> host)
            let peerRequestId = CborMessageId.newUUID()
            let peerCapUrn = "cap:op=host_download"
            let peerPayload = "model-id:llama-3".data(using: .utf8)!
            let peerReq = CborFrame.req(id: peerRequestId, capUrn: peerCapUrn, payload: peerPayload, contentType: "text/plain")
            try pluginWriter.write(peerReq)

            // 5. Wait for response from host to our peer request
            guard let peerRes = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No response to peer request")
            }
            guard peerRes.id == peerRequestId else {
                throw CborPluginHostError.handshakeFailed("Response ID mismatch")
            }
            guard peerRes.frameType == .res || peerRes.frameType == .end else {
                throw CborPluginHostError.handshakeFailed("Expected RES/END, got \(peerRes.frameType)")
            }

            // Use what we received from host
            let hostResponsePayload = peerRes.payload ?? Data()

            // 6. Send response to original host request
            let finalResponse = "processed_with:\(String(data: hostResponsePayload, encoding: .utf8) ?? "")".data(using: .utf8)!
            let res = CborFrame.res(id: hostRequestId, payload: finalResponse, contentType: "text/plain")
            try pluginWriter.write(res)

            await tracker.setPluginFinalResponse(finalResponse)
        }

        // Host task - manually handles the protocol
        let hostTask = Task.detached { @Sendable [tracker] in
            // 1. Send HELLO to plugin
            let hostHello = CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK)
            try hostWriter.write(hostHello)

            // 2. Receive HELLO from plugin
            guard let pluginHello = try hostReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO from plugin")
            }
            guard pluginHello.frameType == .hello else {
                throw CborPluginHostError.handshakeFailed("Expected HELLO, got \(pluginHello.frameType)")
            }

            // 3. Send REQ to plugin
            let hostRequestId = CborMessageId.newUUID()
            let hostReq = CborFrame.req(id: hostRequestId, capUrn: "cap:op=plugin_inference", payload: "input_text".data(using: .utf8)!, contentType: "text/plain")
            try hostWriter.write(hostReq)
            await tracker.setHostRequest(hostRequestId)

            // 4. Read next frame - could be plugin's REQ (peer invocation) or final response
            guard let frame1 = try hostReader.read() else {
                throw CborPluginHostError.receiveFailed("No response from plugin")
            }

            // 5. If it's a REQ from plugin (bidirectional), respond to it
            if frame1.frameType == .req {
                let pluginPeerRequestId = frame1.id
                let pluginPeerCapUrn = frame1.cap ?? ""
                let pluginPeerPayload = frame1.payload ?? Data()

                await tracker.setPluginPeerRequest(id: pluginPeerRequestId, capUrn: pluginPeerCapUrn, payload: pluginPeerPayload)

                // Host responds to plugin's peer request
                let hostPeerResponse = "downloaded_model_path".data(using: .utf8)!
                let peerRes = CborFrame.res(id: pluginPeerRequestId, payload: hostPeerResponse, contentType: "text/plain")
                try hostWriter.write(peerRes)
                await tracker.setHostPeerResponse(hostPeerResponse)

                // 6. Now read the final response to our original request
                guard let finalRes = try hostReader.read() else {
                    throw CborPluginHostError.receiveFailed("No final response from plugin")
                }
                guard finalRes.frameType == .res || finalRes.frameType == .end else {
                    throw CborPluginHostError.handshakeFailed("Expected final RES/END, got \(finalRes.frameType)")
                }
                guard finalRes.id == hostRequestId else {
                    throw CborPluginHostError.handshakeFailed("Final response ID mismatch")
                }

                return finalRes.payload
            } else if frame1.frameType == .res || frame1.frameType == .end {
                // Direct response without peer invocation
                return frame1.payload
            } else {
                throw CborPluginHostError.handshakeFailed("Unexpected frame type: \(frame1.frameType)")
            }
        }

        // Wait for both tasks
        let hostResponse = try await hostTask.value
        try await pluginTask.value

        // Verify the bidirectional communication worked
        let pluginPeerCapUrn = await tracker.getPluginPeerCapUrn()
        XCTAssertEqual(pluginPeerCapUrn, "cap:op=host_download", "Plugin should have invoked host cap")

        let finalResponse = await tracker.getPluginFinalResponse()
        XCTAssertNotNil(finalResponse, "Should have final response")

        let responseString = String(data: hostResponse ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(responseString.contains("processed_with:downloaded_model_path"),
            "Response should contain host's peer response: \(responseString)")
    }
}
