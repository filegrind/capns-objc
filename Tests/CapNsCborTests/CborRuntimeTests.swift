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

    // MARK: - Handshake Tests

    func testHandshakeSuccess() async throws {
        let pipes = createPipePair()

        // Create host
        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

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
                throw CborPluginHostError.protocolError("Expected HELLO, got \(hostHello.frameType)")
            }

            // Send plugin's HELLO
            let pluginHello = CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK)
            try pluginWriter.write(pluginHello)
        }

        // Perform handshake
        try host.performHandshake()
        XCTAssertTrue(host.isHandshakeComplete)

        // Wait for plugin task to complete
        try await pluginTask.value
    }

    func testHandshakeLimitsNegotiation() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        // Plugin has smaller limits
        let pluginMaxFrame = 500_000
        let pluginMaxChunk = 100_000

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            let pluginHello = CborFrame.hello(maxFrame: pluginMaxFrame, maxChunk: pluginMaxChunk)
            try pluginWriter.write(pluginHello)
        }

        try host.performHandshake()

        // Negotiated limits should be minimum of both
        XCTAssertEqual(host.negotiatedLimits.maxFrame, pluginMaxFrame)
        XCTAssertEqual(host.negotiatedLimits.maxChunk, pluginMaxChunk)

        try await pluginTask.value
    }

    func testHandshakeFailsOnWrongFrameType() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

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
            try host.performHandshake()
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

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let expectedResponse = "Hello, World!".data(using: .utf8)!

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }
            guard req.frameType == .req else {
                throw CborPluginHostError.protocolError("Expected REQ, got \(req.frameType)")
            }
            guard req.cap == "cap:op=test" else {
                throw CborPluginHostError.protocolError("Wrong cap: \(req.cap ?? "nil")")
            }

            // Send response
            let res = CborFrame.res(id: req.id, payload: expectedResponse, contentType: "text/plain")
            try pluginWriter.write(res)
        }

        try host.performHandshake()

        let response = try host.call(capUrn: "cap:op=test", payload: "request".data(using: .utf8)!)
        XCTAssertEqual(response, expectedResponse)

        try await pluginTask.value
    }

    func testSendRequestReceiveStreamingResponse() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let chunks = ["chunk1", "chunk2", "chunk3"]

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

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

        try host.performHandshake()

        let response = try host.call(capUrn: "cap:op=stream", payload: Data())

        // Response should be all chunks concatenated
        let expectedResponse = chunks.joined()
        XCTAssertEqual(String(data: response, encoding: .utf8), expectedResponse)

        try await pluginTask.value
    }

    func testSendRequestReceiveEndFrame() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let finalPayload = "final".data(using: .utf8)!

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send END frame
            let end = CborFrame.end(id: req.id, finalPayload: finalPayload)
            try pluginWriter.write(end)
        }

        try host.performHandshake()

        let response = try host.call(capUrn: "cap:op=test", payload: Data())
        XCTAssertEqual(response, finalPayload)

        try await pluginTask.value
    }

    func testChunksWithLogFramesInterleaved() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

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

        try host.performHandshake()

        let response = try host.call(capUrn: "cap:op=test", payload: Data())
        XCTAssertEqual(String(data: response, encoding: .utf8), "AB")

        try await pluginTask.value
    }

    // MARK: - Error Handling Tests

    func testPluginErrorResponse() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

            // Wait for request
            guard let req = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No request")
            }

            // Send error response
            let err = CborFrame.err(id: req.id, code: "NOT_FOUND", message: "Cap not found")
            try pluginWriter.write(err)
        }

        try host.performHandshake()

        do {
            _ = try host.call(capUrn: "cap:op=missing", payload: Data())
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

    func testRequestBeforeHandshakeFails() throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        // Try to send request without handshake
        do {
            _ = try host.sendRequest(capUrn: "cap:op=test", payload: Data())
            XCTFail("Should have thrown error")
        } catch let error as CborPluginHostError {
            if case .handshakeNotComplete = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Heartbeat Tests

    func testHeartbeatExchange() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

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
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

            // Wait for heartbeat from host
            guard let heartbeat = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No heartbeat")
            }
            guard heartbeat.frameType == .heartbeat else {
                throw CborPluginHostError.protocolError("Expected HEARTBEAT, got \(heartbeat.frameType)")
            }
            await tracker.setId(heartbeat.id)

            // Respond with heartbeat (same ID)
            let response = CborFrame.heartbeat(id: heartbeat.id)
            try pluginWriter.write(response)
        }

        try host.performHandshake()

        let sentId = try host.sendHeartbeat()

        // Wait for plugin to process
        try await pluginTask.value

        let receivedId = await tracker.getId()
        XCTAssertEqual(sentId, receivedId)
    }

    func testHeartbeatDuringRequest() async throws {
        let pipes = createPipePair()

        let host = CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            // Handshake
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

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
                throw CborPluginHostError.protocolError("Expected heartbeat response")
            }

            // Send actual request response
            let res = CborFrame.res(id: req.id, payload: "done".data(using: .utf8)!, contentType: "text/plain")
            try pluginWriter.write(res)
        }

        try host.performHandshake()

        // This should work even though plugin sends heartbeat mid-request
        let response = try host.call(capUrn: "cap:op=test", payload: Data())
        XCTAssertEqual(String(data: response, encoding: .utf8), "done")

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

        // Host writes to hostToPlugin, reads from pluginToHost
        let host = CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

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
                throw CborPluginHostError.protocolError("Expected HELLO")
            }

            // 2. Send HELLO response
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

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
        try host.performHandshake()

        // Send requests and verify responses
        let testData1 = "Hello, Plugin!".data(using: .utf8)!
        let response1 = try host.call(capUrn: "cap:op=echo", payload: testData1)
        XCTAssertEqual(response1, testData1)

        let testData2 = "Second request".data(using: .utf8)!
        let response2 = try host.call(capUrn: "cap:op=echo", payload: testData2)
        XCTAssertEqual(response2, testData2)

        // Send heartbeat
        _ = try host.sendHeartbeat()

        // Wait for plugin to complete
        try await pluginTask.value
    }

    /// Tests that the protocol handles binary data correctly
    func testBinaryDataTransfer() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let host = CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Create binary test data with all byte values
        var binaryData = Data()
        for i: UInt8 in 0...255 {
            binaryData.append(i)
        }

        let pluginTask = Task.detached { @Sendable [binaryData] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

            guard let req = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }

            // Verify we received the binary data correctly
            guard req.payload == binaryData else {
                throw CborPluginHostError.protocolError("Binary data mismatch")
            }

            // Echo it back
            try pluginWriter.write(CborFrame.res(id: req.id, payload: binaryData, contentType: "application/octet-stream"))
        }

        try host.performHandshake()

        let response = try host.call(capUrn: "cap:op=binary", payload: binaryData)
        XCTAssertEqual(response, binaryData)

        try await pluginTask.value
    }

    /// Tests large payload chunking
    func testLargePayloadChunking() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let host = CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Create large payload that will need chunking
        let largePayload = Data(repeating: 0x42, count: 100_000)

        let pluginTask = Task.detached { @Sendable [largePayload] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))

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

        try host.performHandshake()

        let response = try host.call(capUrn: "cap:op=large", payload: Data())
        XCTAssertEqual(response.count, largePayload.count)
        XCTAssertEqual(response, largePayload)

        try await pluginTask.value
    }
}
