import XCTest
import Foundation
import SwiftCBOR
@testable import CapNsCbor

// =============================================================================
// CBOR Runtime Integration Tests
//
// Covers TEST284-303 from cbor_integration_tests.rs in the reference Rust
// implementation, plus TEST230-232 for handshake tests from cbor_io.rs.
//
// Additional Swift-specific integration tests that go beyond the Rust test
// suite are included at the end (testFullProtocolExchange, testConcurrentRequests,
// testBidirectionalProtocolWireFormat).
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
@MainActor
final class CborRuntimeTests: XCTestCase, @unchecked Sendable {

    // MARK: - Test Infrastructure

    private func createPipePair() -> (hostToPlugin: Pipe, pluginToHost: Pipe) {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        return (hostToPlugin, pluginToHost)
    }

    nonisolated static let testManifestJSON = """
    {"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:op=test","title":"Test","command":"test"}]}
    """
    nonisolated static let testManifestData = testManifestJSON.data(using: .utf8)!

    nonisolated static func helloWithManifest(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) -> CborFrame {
        return CborFrame.hello(maxFrame: maxFrame, maxChunk: maxChunk, manifest: testManifestData)
    }

    /// Read a complete request from the stream protocol:
    /// REQ(empty) + STREAM_START + CHUNK(s) + STREAM_END + END
    /// Returns the REQ frame's metadata plus the accumulated payload from CHUNK frames.
    nonisolated static func readCompleteRequest(
        reader: CborFrameReader
    ) throws -> (reqId: CborMessageId, cap: String, contentType: String, payload: Data) {
        guard let req = try reader.read() else {
            throw CborPluginHostError.receiveFailed("No REQ frame")
        }
        guard req.frameType == .req else {
            throw CborPluginHostError.handshakeFailed("Expected REQ, got \(req.frameType)")
        }

        let reqId = req.id
        let cap = req.cap ?? ""
        let contentType = req.contentType ?? ""

        // Read stream frames until END
        var payload = Data()
        while true {
            guard let frame = try reader.read() else {
                throw CborPluginHostError.receiveFailed("Unexpected EOF reading request stream")
            }
            switch frame.frameType {
            case .streamStart:
                continue
            case .chunk:
                payload.append(frame.payload ?? Data())
            case .streamEnd:
                continue
            case .end:
                return (reqId, cap, contentType, payload)
            default:
                throw CborPluginHostError.handshakeFailed("Unexpected frame type in request stream: \(frame.frameType)")
            }
        }
    }

    /// Write a complete single-value response using the stream protocol:
    /// STREAM_START + CHUNK + STREAM_END + END
    nonisolated static func writeResponse(
        writer: CborFrameWriter,
        reqId: CborMessageId,
        payload: Data,
        streamId: String = "response-stream",
        mediaUrn: String = "media:bytes"
    ) throws {
        try writer.write(CborFrame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn))
        try writer.write(CborFrame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: payload))
        try writer.write(CborFrame.streamEnd(reqId: reqId, streamId: streamId))
        try writer.write(CborFrame.end(id: reqId, finalPayload: nil))
    }

    /// Write a multi-chunk response using the stream protocol:
    /// STREAM_START + CHUNK(0) + CHUNK(1) + ... + STREAM_END + END
    nonisolated static func writeStreamingResponse(
        writer: CborFrameWriter,
        reqId: CborMessageId,
        chunks: [Data],
        streamId: String = "response-stream",
        mediaUrn: String = "media:bytes"
    ) throws {
        try writer.write(CborFrame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn))
        for (i, chunk) in chunks.enumerated() {
            try writer.write(CborFrame.chunk(reqId: reqId, streamId: streamId, seq: UInt64(i), payload: chunk))
        }
        try writer.write(CborFrame.streamEnd(reqId: reqId, streamId: streamId))
        try writer.write(CborFrame.end(id: reqId, finalPayload: nil))
    }

    /// Write a chunked response for large data using the stream protocol:
    /// STREAM_START + CHUNK(s) + STREAM_END + END
    nonisolated static func writeChunkedResponse(
        writer: CborFrameWriter,
        reqId: CborMessageId,
        data: Data,
        maxChunk: Int,
        streamId: String = "response-stream",
        mediaUrn: String = "media:bytes"
    ) throws {
        try writer.write(CborFrame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn))
        var offset = 0
        var seq: UInt64 = 0
        while offset < data.count {
            let chunkSize = min(data.count - offset, maxChunk)
            let chunkData = data.subdata(in: offset..<offset + chunkSize)
            try writer.write(CborFrame.chunk(reqId: reqId, streamId: streamId, seq: seq, payload: chunkData))
            offset += chunkSize
            seq += 1
        }
        try writer.write(CborFrame.streamEnd(reqId: reqId, streamId: streamId))
        try writer.write(CborFrame.end(id: reqId, finalPayload: nil))
    }

    // MARK: - Handshake Tests (TEST230-232, TEST284, TEST290)

    // TEST230: Sync handshake exchanges HELLO frames and negotiates minimum limits
    // TEST284: Host-plugin handshake exchanges HELLO frames, negotiates limits, and transfers manifest
    func testHandshakeSuccess() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let hostHello = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO from host")
            }
            guard hostHello.frameType == .hello else {
                throw CborPluginHostError.handshakeFailed("Expected HELLO, got \(hostHello.frameType)")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )
        XCTAssertFalse(host.isClosed)

        XCTAssertNotNil(host.pluginManifest, "Host should have received plugin manifest")
        let manifest = try JSONSerialization.jsonObject(with: host.pluginManifest!) as! [String: Any]
        XCTAssertEqual(manifest["name"] as? String, "TestPlugin")

        try await pluginTask.value
    }

    // TEST290: Limit negotiation picks minimum of host and plugin max_frame and max_chunk
    func testHandshakeLimitsNegotiation() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginMaxFrame = 500_000
        let pluginMaxChunk = 100_000

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
            let pluginHello = CborFrame.hello(maxFrame: pluginMaxFrame, maxChunk: pluginMaxChunk, manifest: CborRuntimeTests.testManifestData)
            try pluginWriter.write(pluginHello)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        XCTAssertEqual(host.negotiatedLimits.maxFrame, pluginMaxFrame)
        XCTAssertEqual(host.negotiatedLimits.maxChunk, pluginMaxChunk)

        try await pluginTask.value
    }

    // TEST232: Handshake fails when plugin HELLO is missing required manifest
    func testHandshakeFailsOnMissingManifest() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
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

    // TEST231: Handshake fails when peer sends non-HELLO frame
    func testHandshakeFailsOnWrongFrameType() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw CborPluginHostError.receiveFailed("No HELLO")
            }
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

    // MARK: - Request/Response Tests (TEST285-286, TEST289, TEST295)

    // TEST295: Single complete response using END frame
    func testSendRequestReceiveSingleResponse() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let expectedResponse = "Hello, World!".data(using: .utf8)!

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            guard cap == "cap:op=test" else { throw CborPluginHostError.handshakeFailed("Wrong cap") }

            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: expectedResponse)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: "request".data(using: .utf8)!)])
        XCTAssertEqual(response.concatenated(), expectedResponse)

        try await pluginTask.value
    }

    // TEST286: Streaming response with multiple CHUNK frames collected by host
    func testSendRequestReceiveStreamingResponse() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let chunks = ["chunk1", "chunk2", "chunk3"]

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            try CborRuntimeTests.writeStreamingResponse(
                writer: pluginWriter,
                reqId: reqId,
                chunks: chunks.map { $0.data(using: .utf8)! }
            )
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=stream", arguments: [(mediaUrn: "media:bytes", value: Data())])
        let expectedResponse = chunks.joined()
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), expectedResponse)

        try await pluginTask.value
    }

    // TEST285: Simple request-response flow: host sends REQ, plugin sends END with payload
    func testSendRequestReceiveEndFrame() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let finalPayload = "final".data(using: .utf8)!

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: finalPayload)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        XCTAssertEqual(response.concatenated(), finalPayload)

        try await pluginTask.value
    }

    // TEST289: LOG frames sent during a request are transparently skipped by host
    func testChunksWithLogFramesInterleaved() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            try pluginWriter.write(CborFrame.log(id: reqId, level: "info", message: "Starting..."))
            try pluginWriter.write(CborFrame.streamStart(reqId: reqId, streamId: "response-stream", mediaUrn: "media:bytes"))
            try pluginWriter.write(CborFrame.chunk(reqId: reqId, streamId: "response-stream", seq: 0, payload: "A".data(using: .utf8)!))
            try pluginWriter.write(CborFrame.log(id: reqId, level: "debug", message: "Progress..."))
            try pluginWriter.write(CborFrame.chunk(reqId: reqId, streamId: "response-stream", seq: 1, payload: "B".data(using: .utf8)!))
            try pluginWriter.write(CborFrame.streamEnd(reqId: reqId, streamId: "response-stream"))
            try pluginWriter.write(CborFrame.end(id: reqId, finalPayload: nil))
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "AB")

        try await pluginTask.value
    }

    // MARK: - Error Handling Tests (TEST288, TEST302)

    // TEST288: Plugin ERR frame is received by host as CborPluginHostError.pluginError
    func testPluginErrorResponse() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            let err = CborFrame.err(id: reqId, code: "NOT_FOUND", message: "Cap not found")
            try pluginWriter.write(err)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        do {
            _ = try await host.callWithArguments(capUrn: "cap:op=missing", arguments: [(mediaUrn: "media:bytes", value: Data())])
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

    // TEST302: Host request on a closed host returns CborPluginHostError.closed
    func testRequestAfterCloseFails() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        host.close()

        do {
            _ = try host.requestWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
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

    // MARK: - Heartbeat Tests (TEST287, TEST294)

    // TEST287: Host-initiated heartbeat is received and responded to by plugin
    func testHeartbeatExchange() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        actor HeartbeatTracker {
            var receivedId: CborMessageId?
            func setId(_ id: CborMessageId) { receivedId = id }
            func getId() -> CborMessageId? { receivedId }
        }
        let tracker = HeartbeatTracker()

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            guard let heartbeat = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No heartbeat") }
            guard heartbeat.frameType == .heartbeat else { throw CborPluginHostError.handshakeFailed("Expected HEARTBEAT") }
            await tracker.setId(heartbeat.id)

            let response = CborFrame.heartbeat(id: heartbeat.id)
            try pluginWriter.write(response)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        try host.sendHeartbeat()
        try await pluginTask.value

        let receivedId = await tracker.getId()
        XCTAssertNotNil(receivedId)
    }

    // TEST294: Plugin-initiated heartbeat mid-stream is handled transparently by host
    func testHeartbeatDuringRequest() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Send a heartbeat BEFORE responding
            let heartbeat = CborFrame.heartbeat(id: .newUUID())
            try pluginWriter.write(heartbeat)

            // Wait for heartbeat response from host
            guard let heartbeatResp = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No heartbeat response") }
            guard heartbeatResp.frameType == .heartbeat else { throw CborPluginHostError.handshakeFailed("Expected heartbeat response") }

            // Send actual response
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "done".data(using: .utf8)!)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "done")

        try await pluginTask.value
    }

    // MARK: - Handler Registration (TEST293)

    // TEST293: PluginRuntime handler registration and lookup by exact and non-existent cap URN
    func testPluginRuntimeHandlerRegistration() throws {
        let runtime = CborPluginRuntime(manifest: CborRuntimeTests.testManifestData)

        runtime.registerRaw(capUrn: "cap:op=echo") { (stream: AsyncStream<CborStreamChunk>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await chunk in stream {
                data.append(chunk.data)
            }
            emitter.emitCbor(.byteString([UInt8](data)))
        }

        runtime.registerRaw(capUrn: "cap:op=transform") { (stream: AsyncStream<CborStreamChunk>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            emitter.emitCbor(.byteString([UInt8]("transformed".utf8)))
        }

        // Exact match
        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:op=echo"), "echo handler must be found")
        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:op=transform"), "transform handler must be found")

        // Non-existent
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=unknown"), "unknown handler must be nil")
    }

    // MARK: - Heartbeat No-Ping-Pong (TEST296)

    // TEST296: Host does not echo back plugin's heartbeat response (no infinite ping-pong)
    func testHostInitiatedHeartbeatNoPingPong() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Read complete request (REQ + STREAM_START + CHUNK(s) + STREAM_END + END)
            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Read heartbeat from host
            guard let heartbeat = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No heartbeat") }
            guard heartbeat.frameType == .heartbeat else { throw CborPluginHostError.handshakeFailed("Expected heartbeat") }

            // Respond to heartbeat
            try pluginWriter.write(CborFrame.heartbeat(id: heartbeat.id))

            // Send actual response - key: no additional frames should arrive from host (no ping-pong)
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "done".data(using: .utf8)!)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        // Start request
        let stream = try host.requestWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])

        // Send heartbeat while request is in flight
        try host.sendHeartbeat()

        // Collect response chunks
        var chunks: [CborResponseChunk] = []
        for await result in stream {
            switch result {
            case .success(let chunk):
                chunks.append(chunk)
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }

        // Should have received just the response, no echo loops
        XCTAssertFalse(chunks.isEmpty, "Should have received at least one chunk")
        let concatenated = chunks.reduce(Data()) { $0 + $1.payload }
        XCTAssertEqual(String(data: concatenated, encoding: .utf8), "done")

        try await pluginTask.value
    }

    // MARK: - Arguments (TEST297, TEST303)

    // TEST297: Host call with unified CBOR arguments sends correct content_type and payload
    func testArgumentsRoundtrip() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, contentType, payload) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Verify content type is CBOR
            guard contentType == "application/cbor" else {
                throw CborPluginHostError.handshakeFailed("Expected application/cbor, got \(contentType)")
            }

            // Parse CBOR payload and extract the value
            guard let decoded = try? CBOR.decode([UInt8](payload)) else {
                throw CborPluginHostError.handshakeFailed("Failed to decode CBOR")
            }
            guard case .array(let args) = decoded else {
                throw CborPluginHostError.handshakeFailed("Expected CBOR array")
            }
            guard args.count == 1 else {
                throw CborPluginHostError.handshakeFailed("Expected 1 argument, got \(args.count)")
            }

            // Extract value bytes from the first argument
            guard case .map(let argMap) = args[0] else {
                throw CborPluginHostError.handshakeFailed("Expected map")
            }
            var foundValue: Data?
            for (k, v) in argMap {
                if case .utf8String(let key) = k, key == "value",
                   case .byteString(let bytes) = v {
                    foundValue = Data(bytes)
                }
            }
            guard let value = foundValue else {
                throw CborPluginHostError.handshakeFailed("No value field found")
            }

            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: value)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        // Use requestWithArguments and collect response
        let stream = try host.requestWithArguments(
            capUrn: "cap:op=test",
            arguments: [(mediaUrn: "media:model-spec;textable", value: "gpt-4".data(using: .utf8)!)]
        )
        var responseData = Data()
        for await result in stream {
            switch result {
            case .success(let chunk):
                responseData.append(chunk.payload)
                if chunk.isEof { break }
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(String(data: responseData, encoding: .utf8), "gpt-4")

        try await pluginTask.value
    }

    // TEST303: Multiple arguments are correctly serialized in CBOR payload
    func testArgumentsMultiple() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, payload) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Parse CBOR and verify 2 arguments
            guard let decoded = try? CBOR.decode([UInt8](payload)),
                  case .array(let args) = decoded else {
                throw CborPluginHostError.handshakeFailed("Expected CBOR array payload")
            }

            let responsePayload = "got \(args.count) args".data(using: .utf8)!
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: responsePayload)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let stream = try host.requestWithArguments(
            capUrn: "cap:op=test",
            arguments: [
                (mediaUrn: "media:model-spec;textable", value: "gpt-4".data(using: .utf8)!),
                (mediaUrn: "media:pdf;bytes", value: Data([0x89, 0x50, 0x4E, 0x47]))
            ]
        )
        var responsePayload = Data()
        for await result in stream {
            switch result {
            case .success(let chunk):
                responsePayload.append(chunk.payload)
                if chunk.isEof { break }
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(String(data: responsePayload, encoding: .utf8), "got 2 args")

        try await pluginTask.value
    }

    // MARK: - Sudden Disconnect (TEST298)

    // TEST298: Host receives error when plugin closes connection unexpectedly
    func testPluginSuddenDisconnect() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Read request but don't respond - just close the connection
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            // Drop/close the writer to simulate sudden disconnect
            pipes.pluginToHost.fileHandleForWriting.closeFile()
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        do {
            _ = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
            XCTFail("Should have thrown error due to sudden disconnect")
        } catch {
            // Any error is expected - plugin disconnected without responding
        }

        try? await pluginTask.value
    }

    // MARK: - Additional Integration Tests (TEST291-303)

    // TEST291: Binary payload with all 256 byte values roundtrips through host-plugin communication
    func testBinaryPayloadRoundtrip() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        var binaryData = Data()
        for i: UInt8 in 0...255 {
            binaryData.append(i)
        }

        let pluginTask = Task.detached { @Sendable [binaryData] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, payload) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            guard payload == binaryData else { throw CborPluginHostError.handshakeFailed("Binary data mismatch") }

            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: binaryData)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=binary", arguments: [(mediaUrn: "media:bytes", value: binaryData)])
        XCTAssertEqual(response.concatenated(), binaryData)

        try await pluginTask.value
    }

    // TEST292: Three sequential requests get distinct MessageIds on the wire
    func testMessageIdUniqueness() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        actor IdCollector {
            var ids: [CborMessageId] = []
            func add(_ id: CborMessageId) { ids.append(id) }
            func getIds() -> [CborMessageId] { ids }
        }
        let collector = IdCollector()

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            for _ in 0..<3 {
                let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
                await collector.add(reqId)
                try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "ok".data(using: .utf8)!)
            }
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        _ = try await host.callWithArguments(capUrn: "cap:op=test1", arguments: [(mediaUrn: "media:bytes", value: Data())])
        _ = try await host.callWithArguments(capUrn: "cap:op=test2", arguments: [(mediaUrn: "media:bytes", value: Data())])
        _ = try await host.callWithArguments(capUrn: "cap:op=test3", arguments: [(mediaUrn: "media:bytes", value: Data())])

        try await pluginTask.value

        let ids = await collector.getIds()
        XCTAssertEqual(ids.count, 3)
        XCTAssertNotEqual(ids[0], ids[1])
        XCTAssertNotEqual(ids[1], ids[2])
        XCTAssertNotEqual(ids[0], ids[2])
    }

    // TEST299: Empty payload request and response roundtrip through host-plugin communication
    func testEmptyPayloadRoundtrip() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, payload) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            XCTAssertEqual(payload, Data())

            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: Data())
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=empty", arguments: [(mediaUrn: "media:bytes", value: Data())])
        XCTAssertEqual(response.concatenated(), Data())

        try await pluginTask.value
    }

    // TEST300: END frame without payload is handled as complete response with empty data
    func testEndFrameNoPayload() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            let end = CborFrame.end(id: reqId)
            try pluginWriter.write(end)
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        XCTAssertEqual(response.concatenated(), Data())

        try await pluginTask.value
    }

    // TEST301: Streaming response sequence numbers are contiguous and start from 0
    func testStreamingSequenceNumbers() async throws {
        let pipes = createPipePair()

        let pluginReader = CborFrameReader(handle: pipes.hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pipes.pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            try CborRuntimeTests.writeStreamingResponse(
                writer: pluginWriter,
                reqId: reqId,
                chunks: (0..<5).map { "seq\($0)".data(using: .utf8)! }
            )
        }

        let host = try CborPluginHost(
            stdinHandle: pipes.hostToPlugin.fileHandleForWriting,
            stdoutHandle: pipes.pluginToHost.fileHandleForReading
        )

        let stream = try host.requestWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        var seqs: [UInt64] = []
        for await result in stream {
            switch result {
            case .success(let chunk):
                seqs.append(chunk.seq)
                if chunk.isEof { break }
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(seqs, [0, 1, 2, 3, 4])

        try await pluginTask.value
    }
}

// MARK: - Protocol Integration Tests

@available(macOS 10.15.4, iOS 13.4, *)
@MainActor
final class CborProtocolIntegrationTests: XCTestCase, @unchecked Sendable {

    // Extra: Full bidirectional communication simulating a complete plugin interaction
    func testFullProtocolExchange() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let hello = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            guard hello.frameType == .hello else { throw CborPluginHostError.handshakeFailed("Expected HELLO") }

            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Handle 2 requests + 1 heartbeat
            for _ in 0..<3 {
                guard let frame = try pluginReader.read() else { break }

                switch frame.frameType {
                case .req:
                    // REQ has empty payload — read the stream protocol frames to get actual data
                    var payload = Data()
                    while true {
                        guard let sf = try pluginReader.read() else { break }
                        switch sf.frameType {
                        case .streamStart: continue
                        case .chunk: payload.append(sf.payload ?? Data())
                        case .streamEnd: continue
                        case .end: break
                        default: break
                        }
                        if sf.frameType == .end { break }
                    }
                    try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: frame.id, payload: payload)
                case .heartbeat:
                    try pluginWriter.write(CborFrame.heartbeat(id: frame.id))
                default:
                    break
                }
            }
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let testData1 = "Hello, Plugin!".data(using: .utf8)!
        let response1 = try await host.callWithArguments(capUrn: "cap:op=echo", arguments: [(mediaUrn: "media:bytes", value: testData1)])
        XCTAssertEqual(response1.concatenated(), testData1)

        let testData2 = "Second request".data(using: .utf8)!
        let response2 = try await host.callWithArguments(capUrn: "cap:op=echo", arguments: [(mediaUrn: "media:bytes", value: testData2)])
        XCTAssertEqual(response2.concatenated(), testData2)

        try host.sendHeartbeat()

        try await pluginTask.value
    }

    // Extra: Binary data transfer with all byte values
    func testBinaryDataTransfer() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        var binaryData = Data()
        for i: UInt8 in 0...255 {
            binaryData.append(i)
        }

        let pluginTask = Task.detached { @Sendable [binaryData] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, payload) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            guard payload == binaryData else { throw CborPluginHostError.handshakeFailed("Binary data mismatch") }

            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: binaryData)
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=binary", arguments: [(mediaUrn: "media:bytes", value: binaryData)])
        XCTAssertEqual(response.concatenated(), binaryData)

        try await pluginTask.value
    }

    // Extra: Large payload chunking
    func testLargePayloadChunking() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let largePayload = Data(repeating: 0x42, count: 100_000)

        let pluginTask = Task.detached { @Sendable [largePayload] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            try CborRuntimeTests.writeChunkedResponse(
                writer: pluginWriter,
                reqId: reqId,
                data: largePayload,
                maxChunk: 10_000
            )
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=large", arguments: [(mediaUrn: "media:bytes", value: Data())])
        XCTAssertEqual(response.concatenated().count, largePayload.count)
        XCTAssertEqual(response.concatenated(), largePayload)

        try await pluginTask.value
    }

    // Extra: Concurrent requests are properly multiplexed
    func testConcurrentRequests() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            var receivedRequests: [CborMessageId] = []
            for _ in 0..<3 {
                let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
                receivedRequests.append(reqId)
            }

            for reqId in receivedRequests.reversed() {
                try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "response".data(using: .utf8)!)
            }
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        async let r1 = host.callWithArguments(capUrn: "cap:op=test1", arguments: [(mediaUrn: "media:bytes", value: Data())])
        async let r2 = host.callWithArguments(capUrn: "cap:op=test2", arguments: [(mediaUrn: "media:bytes", value: Data())])
        async let r3 = host.callWithArguments(capUrn: "cap:op=test3", arguments: [(mediaUrn: "media:bytes", value: Data())])

        let responses = try await [r1, r2, r3]

        for response in responses {
            XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "response")
        }

        try await pluginTask.value
    }

    // Extra: Bidirectional wire format protocol
    func testBidirectionalProtocolWireFormat() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let hostReader = CborFrameReader(handle: pluginToHost.fileHandleForReading)
        let hostWriter = CborFrameWriter(handle: hostToPlugin.fileHandleForWriting)

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        actor RequestTracker {
            var pluginPeerCapUrn: String?
            var pluginFinalResponse: Data?

            func setPluginPeerCapUrn(_ capUrn: String) { pluginPeerCapUrn = capUrn }
            func setPluginFinalResponse(_ payload: Data) { pluginFinalResponse = payload }

            func getPluginPeerCapUrn() -> String? { pluginPeerCapUrn }
            func getPluginFinalResponse() -> Data? { pluginFinalResponse }
        }
        let tracker = RequestTracker()

        let pluginTask = Task.detached { @Sendable [tracker] in
            guard let hello = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            guard hello.frameType == .hello else { throw CborPluginHostError.handshakeFailed("Expected HELLO") }

            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            guard let req = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No REQ") }
            guard req.frameType == .req else { throw CborPluginHostError.handshakeFailed("Expected REQ") }
            let hostRequestId = req.id

            let peerRequestId = CborMessageId.newUUID()
            let peerReq = CborFrame.req(id: peerRequestId, capUrn: "cap:op=host_download", payload: "model-id:llama-3".data(using: .utf8)!, contentType: "text/plain")
            try pluginWriter.write(peerReq)

            // Read stream protocol response: STREAM_START + CHUNK(s) + STREAM_END + END
            var hostResponsePayload = Data()
            while true {
                guard let peerFrame = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No peer response frame") }
                if peerFrame.frameType == .chunk {
                    hostResponsePayload.append(peerFrame.payload ?? Data())
                } else if peerFrame.frameType == .end {
                    break
                }
                // Skip STREAM_START and STREAM_END
            }

            let finalResponse = "processed_with:\(String(data: hostResponsePayload, encoding: .utf8) ?? "")".data(using: .utf8)!
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: hostRequestId, payload: finalResponse)

            await tracker.setPluginFinalResponse(finalResponse)
        }

        let hostTask = Task.detached { @Sendable [tracker] in
            let hostHello = CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK)
            try hostWriter.write(hostHello)

            guard let pluginHello = try hostReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO from plugin") }
            guard pluginHello.frameType == .hello else { throw CborPluginHostError.handshakeFailed("Expected HELLO") }

            let hostRequestId = CborMessageId.newUUID()
            let hostReq = CborFrame.req(id: hostRequestId, capUrn: "cap:op=plugin_inference", payload: "input_text".data(using: .utf8)!, contentType: "text/plain")
            try hostWriter.write(hostReq)

            guard let frame1 = try hostReader.read() else { throw CborPluginHostError.receiveFailed("No response") }

            if frame1.frameType == .req {
                await tracker.setPluginPeerCapUrn(frame1.cap ?? "")

                let hostPeerResponse = "downloaded_model_path".data(using: .utf8)!
                try CborRuntimeTests.writeResponse(writer: hostWriter, reqId: frame1.id, payload: hostPeerResponse)

                // Read stream protocol response: STREAM_START + CHUNK(s) + STREAM_END + END
                var finalPayload = Data()
                while true {
                    guard let resFrame = try hostReader.read() else { throw CborPluginHostError.receiveFailed("No final response frame") }
                    if resFrame.frameType == .chunk {
                        finalPayload.append(resFrame.payload ?? Data())
                    } else if resFrame.frameType == .end {
                        break
                    }
                    // Skip STREAM_START and STREAM_END
                }
                return finalPayload
            } else if frame1.frameType == .streamStart {
                // Plugin responded directly with stream protocol
                var finalPayload = Data()
                while true {
                    guard let resFrame = try hostReader.read() else { throw CborPluginHostError.receiveFailed("No response frame") }
                    if resFrame.frameType == .chunk {
                        finalPayload.append(resFrame.payload ?? Data())
                    } else if resFrame.frameType == .end {
                        break
                    }
                }
                return finalPayload
            } else if frame1.frameType == .end {
                return frame1.payload ?? Data()
            } else {
                throw CborPluginHostError.handshakeFailed("Unexpected frame type: \(frame1.frameType)")
            }
        }

        let hostResponse = try await hostTask.value
        try await pluginTask.value

        let pluginPeerCapUrn = await tracker.getPluginPeerCapUrn()
        XCTAssertEqual(pluginPeerCapUrn, "cap:op=host_download")

        let finalResponse = await tracker.getPluginFinalResponse()
        XCTAssertNotNil(finalResponse)

        let responseString = String(data: hostResponse ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(responseString.contains("processed_with:downloaded_model_path"),
            "Response should contain host's peer response: \(responseString)")
    }

    // MARK: - Chunking/Reassembly Tests (TEST313-317)

    // TEST313: Auto-chunking splits payload larger than max_chunk into CHUNK frames + END frame,
    // and host concatenated() reassembles the full original data
    func testAutoChunkingReassembly() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let maxChunk = 100
        var data = Data(count: 250)
        for i in 0..<250 {
            data[i] = UInt8(i % 256)
        }

        let pluginTask = Task.detached { @Sendable [data] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Simulate auto-chunking: 250 bytes with max_chunk=100 → STREAM_START + CHUNK(100) + CHUNK(100) + CHUNK(50) + STREAM_END + END
            try CborRuntimeTests.writeChunkedResponse(
                writer: pluginWriter,
                reqId: reqId,
                data: data,
                maxChunk: maxChunk
            )
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        let reassembled = response.concatenated()
        XCTAssertEqual(reassembled.count, 250)
        XCTAssertEqual(reassembled, data, "concatenated must reconstruct the original payload exactly")

        try await pluginTask.value
    }

    // TEST314: Payload exactly equal to max_chunk produces single END frame (no CHUNK frames)
    func testExactMaxChunkSingleEnd() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let data = Data(repeating: 0xAB, count: 100)

        let pluginTask = Task.detached { @Sendable [data] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Single-value response for payload exactly at max_chunk
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: data)
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        let result = response.concatenated()
        XCTAssertEqual(result.count, 100)
        XCTAssertEqual(result, data)

        try await pluginTask.value
    }

    // TEST315: Payload of max_chunk + 1 produces exactly one CHUNK frame + one END frame
    func testMaxChunkPlusOneSplitsIntoTwo() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        var data = Data(count: 101)
        for i in 0..<101 {
            data[i] = UInt8(i % 256)
        }

        let pluginTask = Task.detached { @Sendable [data] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // STREAM_START + CHUNK(100) + CHUNK(1) + STREAM_END + END
            try CborRuntimeTests.writeStreamingResponse(
                writer: pluginWriter,
                reqId: reqId,
                chunks: [data.subdata(in: 0..<100), data.subdata(in: 100..<101)]
            )
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        let reassembled = response.concatenated()
        XCTAssertEqual(reassembled.count, 101)
        XCTAssertEqual(reassembled, data, "101-byte payload must reassemble correctly from CHUNK+END")

        try await pluginTask.value
    }

    // TEST316: concatenated() returns full payload while finalPayload returns only last chunk
    func testConcatenatedVsFinalPayloadDivergence() {
        let chunks = [
            CborResponseChunk(payload: "AAAA".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            CborResponseChunk(payload: "BBBB".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: false),
            CborResponseChunk(payload: "CCCC".data(using: .utf8)!, seq: 2, offset: nil, len: nil, isEof: true),
        ]

        let response = CborPluginResponse.streaming(chunks)

        // concatenated() returns ALL chunk data joined
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "AAAABBBBCCCC")

        // finalPayload returns ONLY the last chunk's data
        XCTAssertEqual(String(data: response.finalPayload!, encoding: .utf8), "CCCC")

        // They must NOT be equal
        XCTAssertNotEqual(response.concatenated(), response.finalPayload!,
            "concatenated and finalPayload must diverge for multi-chunk responses")
    }

    // TEST317: Auto-chunking preserves data integrity across chunk boundaries for 3x max_chunk payload
    func testChunkingDataIntegrity3x() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = CborFrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = CborFrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pattern = "ABCDEFGHIJ".data(using: .utf8)!
        var data = Data()
        for _ in 0..<30 {
            data.append(pattern)
        }
        // data is 300 bytes

        let pluginTask = Task.detached { @Sendable [data] in
            guard let _ = try pluginReader.read() else { throw CborPluginHostError.receiveFailed("No HELLO") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // STREAM_START + CHUNK(100) + CHUNK(100) + CHUNK(100) + STREAM_END + END
            try CborRuntimeTests.writeChunkedResponse(
                writer: pluginWriter,
                reqId: reqId,
                data: data,
                maxChunk: 100
            )
        }

        let host = try CborPluginHost(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let response = try await host.callWithArguments(capUrn: "cap:op=test", arguments: [(mediaUrn: "media:bytes", value: Data())])
        let reassembled = response.concatenated()
        XCTAssertEqual(reassembled.count, 300)
        XCTAssertEqual(reassembled, data, "pattern must be preserved across chunk boundaries")

        try await pluginTask.value
    }
}
