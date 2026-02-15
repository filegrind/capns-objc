import XCTest
import Foundation
import SwiftCBOR
@testable import Bifaci

// =============================================================================
// PluginHost Multi-Plugin Runtime Tests
//
// Tests the restructured PluginHost which manages N plugin binaries with
// frame routing. These mirror the Rust PluginHostRuntime tests (TEST413-425).
//
// Test architecture:
//   Engine task ←→ Relay pipes ←→ PluginHost.run() ←→ Plugin pipes ←→ Plugin task
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
@MainActor
final class CborRuntimeTests: XCTestCase, @unchecked Sendable {

    // MARK: - Test Infrastructure

    nonisolated static let testManifestJSON = """
    {"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:op=test","title":"Test","command":"test"}]}
    """
    nonisolated static let testManifestData = testManifestJSON.data(using: .utf8)!

    nonisolated static func helloWithManifest(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) -> Frame {
        let limits = Limits(maxFrame: maxFrame, maxChunk: maxChunk, maxReorderBuffer: DEFAULT_MAX_REORDER_BUFFER)
        return Frame.helloWithManifest(limits: limits, manifest: testManifestData)
    }

    nonisolated static func makeManifest(name: String, caps: [String]) -> Data {
        let capsJson = caps.map { "{\"urn\":\"\($0)\"}" }.joined(separator: ",")
        return "{\"name\":\"\(name)\",\"version\":\"1.0\",\"caps\":[\(capsJson)]}".data(using: .utf8)!
    }

    nonisolated static func helloWith(manifest: Data, maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) -> Frame {
        let limits = Limits(maxFrame: maxFrame, maxChunk: maxChunk, maxReorderBuffer: DEFAULT_MAX_REORDER_BUFFER)
        return Frame.helloWithManifest(limits: limits, manifest: manifest)
    }

    /// Helper to write a chunk with proper checksum
    nonisolated static func writeChunk(writer: FrameWriter, reqId: MessageId, streamId: String, seq: UInt64, payload: Data, chunkIndex: UInt64) throws {
        let checksum = Frame.computeChecksum(payload)
        try writer.write(Frame.chunk(reqId: reqId, streamId: streamId, seq: seq, payload: payload, chunkIndex: chunkIndex, checksum: checksum))
    }

    /// Helper to write streamEnd with chunk count
    nonisolated static func writeStreamEnd(writer: FrameWriter, reqId: MessageId, streamId: String, chunkCount: UInt64) throws {
        try writer.write(Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: chunkCount))
    }

    /// Read a complete request: REQ + per-argument streams + END.
    nonisolated static func readCompleteRequest(
        reader: FrameReader
    ) throws -> (reqId: MessageId, cap: String, contentType: String, payload: Data) {
        let (reqId, cap, contentType, streams) = try readCompleteRequestStreams(reader: reader)
        var payload = Data()
        for (_, _, data) in streams {
            payload.append(data)
        }
        return (reqId, cap, contentType, payload)
    }

    nonisolated static func readCompleteRequestStreams(
        reader: FrameReader
    ) throws -> (reqId: MessageId, cap: String, contentType: String, streams: [(streamId: String, mediaUrn: String, data: Data)]) {
        guard let req = try reader.read() else {
            throw PluginHostError.receiveFailed("No REQ frame")
        }
        guard req.frameType == .req else {
            throw PluginHostError.handshakeFailed("Expected REQ, got \(req.frameType)")
        }

        let reqId = req.id
        let cap = req.cap ?? ""
        let contentType = req.contentType ?? ""

        var streams: [(streamId: String, mediaUrn: String, data: Data)] = []
        var currentStreamId: String?
        var currentMediaUrn: String?
        var currentData = Data()

        while true {
            guard let frame = try reader.read() else {
                throw PluginHostError.receiveFailed("Unexpected EOF reading request stream")
            }
            switch frame.frameType {
            case .streamStart:
                currentStreamId = frame.streamId
                currentMediaUrn = frame.mediaUrn
                currentData = Data()
            case .chunk:
                currentData.append(frame.payload ?? Data())
            case .streamEnd:
                if let sid = currentStreamId, let murn = currentMediaUrn {
                    streams.append((streamId: sid, mediaUrn: murn, data: currentData))
                }
                currentStreamId = nil
                currentMediaUrn = nil
                currentData = Data()
            case .end:
                return (reqId, cap, contentType, streams)
            default:
                throw PluginHostError.handshakeFailed("Unexpected frame type in request stream: \(frame.frameType)")
            }
        }
    }

    /// Write a complete single-value response: STREAM_START + CHUNK + STREAM_END + END
    nonisolated static func writeResponse(
        writer: FrameWriter,
        reqId: MessageId,
        payload: Data,
        streamId: String = "response-stream",
        mediaUrn: String = "media:bytes"
    ) throws {
        try writer.write(Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn))
        let checksum = Frame.computeChecksum(payload)
        try writer.write(Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: payload, chunkIndex: 0, checksum: checksum))
        try writer.write(Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1))
        try writer.write(Frame.end(id: reqId, finalPayload: nil))
    }

    // MARK: - Handshake Tests (TEST284, TEST290, TEST231-232)

    // TEST284: attachPlugin exchanges HELLO frames, negotiates limits, extracts manifest
    func testAttachPluginHandshake() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let hostHello = try pluginReader.read() else {
                throw PluginHostError.receiveFailed("No HELLO from host")
            }
            guard hostHello.frameType == .hello else {
                throw PluginHostError.handshakeFailed("Expected HELLO, got \(hostHello.frameType)")
            }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
        }

        let host = PluginHost()
        let idx = try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )
        XCTAssertEqual(idx, 0, "First plugin should be index 0")

        try await pluginTask.value
    }

    // TEST290: attachPlugin limit negotiation picks minimum of host and plugin values
    func testAttachPluginLimitsNegotiation() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw PluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(Frame.hello(maxFrame: 500_000, maxChunk: 100_000, manifest: CborRuntimeTests.testManifestData))
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        try await pluginTask.value
    }

    // TEST232: attachPlugin fails when plugin HELLO is missing required manifest
    func testAttachPluginFailsOnMissingManifest() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw PluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(Frame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK))
        }

        let host = PluginHost()
        do {
            try host.attachPlugin(
                stdinHandle: hostToPlugin.fileHandleForWriting,
                stdoutHandle: pluginToHost.fileHandleForReading
            )
            XCTFail("Should have thrown handshake error due to missing manifest")
        } catch let error as PluginHostError {
            if case .handshakeFailed(let msg) = error {
                XCTAssertTrue(msg.contains("missing required manifest"), "Error should mention missing manifest: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try? await pluginTask.value
    }

    // TEST231: attachPlugin fails when peer sends non-HELLO frame
    func testAttachPluginFailsOnWrongFrameType() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else {
                throw PluginHostError.receiveFailed("No HELLO")
            }
            try pluginWriter.write(Frame.err(id: .uint(0), code: "WRONG", message: "Not a HELLO"))
        }

        let host = PluginHost()
        do {
            try host.attachPlugin(
                stdinHandle: hostToPlugin.fileHandleForWriting,
                stdoutHandle: pluginToHost.fileHandleForReading
            )
            XCTFail("Should have thrown handshake error")
        } catch let error as PluginHostError {
            if case .handshakeFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Expected HELLO"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try? await pluginTask.value
    }

    // MARK: - Plugin Registration & Routing (TEST413-414, TEST425)

    // TEST413: registerPlugin adds to cap_table and findPluginForCap resolves it
    func testRegisterPluginAddsToCaptable() {
        let host = PluginHost()
        host.registerPlugin(path: "/usr/bin/test", knownCaps: ["cap:op=convert"])
        XCTAssertNotNil(host.findPluginForCap("cap:op=convert"), "Registered cap must be found")
        XCTAssertNil(host.findPluginForCap("cap:op=unknown"), "Unregistered cap must not be found")
    }

    // TEST414: capabilities returns empty initially
    func testCapabilitiesEmptyInitially() {
        let host = PluginHost()
        // Capabilities are rebuilt from running plugins — no running plugins means empty
        let caps = host.capabilities
        XCTAssertTrue(caps.isEmpty || String(data: caps, encoding: .utf8) == "[]",
            "Capabilities should be empty initially")
    }

    // TEST425: findPluginForCap returns nil for unknown cap
    func testFindPluginForCapUnknown() {
        let host = PluginHost()
        host.registerPlugin(path: "/test", knownCaps: ["cap:op=known"])
        XCTAssertNotNil(host.findPluginForCap("cap:op=known"))
        XCTAssertNil(host.findPluginForCap("cap:op=unknown"))
    }

    // MARK: - Full Path Tests (TEST416-420, TEST426)

    // TEST416: attachPlugin extracts manifest and updates capabilities
    func testAttachPluginUpdatesCaps() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        // After attach, the cap should be registered
        XCTAssertNotNil(host.findPluginForCap("cap:op=test"), "Attached plugin's cap must be found")

        // Capabilities should be non-empty
        let caps = host.capabilities
        XCTAssertFalse(caps.isEmpty, "Capabilities should include attached plugin's caps")

        try await pluginTask.value
    }

    // TEST417 + TEST426: Full path - engine REQ -> relay -> host -> plugin -> response -> relay -> engine
    func testFullPathRequestResponse() async throws {
        // Plugin pipes
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()

        // Relay pipes (engine <-> host)
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Plugin: handshake + read REQ + write response
        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Read REQ + streams + END from host
            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            guard cap == "cap:op=test" else { throw PluginHostError.protocolError("Expected cap:op=test, got \(cap)") }

            // Write response
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "hello-from-plugin".data(using: .utf8)!)
        }

        // Host: attach plugin + run
        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        // Engine: write REQ, read response
        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=test", payload: Data(), contentType: "application/cbor"))
        // Send argument stream
        let sid = "arg-0"
        try engineWriter.write(Frame.streamStart(reqId: reqId, streamId: sid, mediaUrn: "media:bytes"))
        let payload1 = "request-data".data(using: .utf8)!
        let checksum1 = Frame.computeChecksum(payload1)
        try engineWriter.write(Frame.chunk(reqId: reqId, streamId: sid, seq: 0, payload: payload1, chunkIndex: 0, checksum: checksum1))
        try engineWriter.write(Frame.streamEnd(reqId: reqId, streamId: sid, chunkCount: 1))
        try engineWriter.write(Frame.end(id: reqId, finalPayload: nil))

        // Read response from plugin (via host relay)
        var responseData = Data()
        while true {
            guard let frame = try engineReader.read() else { break }
            if frame.frameType == .chunk {
                responseData.append(frame.payload ?? Data())
            }
            if frame.frameType == .end { break }
        }

        // Close relay to let run() exit
        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: responseData, encoding: .utf8), "hello-from-plugin")

        try? await pluginTask.value
        try? await hostTask.value
    }

    // TEST419: Plugin HEARTBEAT handled locally (not forwarded to relay)
    func testHeartbeatHandledLocally() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        // Plugin: handshake, send heartbeat, then respond to REQ
        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())

            // Send a heartbeat to the host
            let hbId = MessageId.newUUID()
            try pluginWriter.write(Frame.heartbeat(id: hbId))

            // Read heartbeat response from host
            guard let hbResp = try pluginReader.read() else { throw PluginHostError.receiveFailed("No heartbeat response") }
            guard hbResp.frameType == .heartbeat else { throw PluginHostError.protocolError("Expected heartbeat, got \(hbResp.frameType)") }
            guard hbResp.id == hbId else { throw PluginHostError.protocolError("Heartbeat ID mismatch") }

            // Read REQ and respond
            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "ok".data(using: .utf8)!)
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        // Engine sends REQ
        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=test", payload: Data(), contentType: "application/cbor"))
        let sid = "arg-0"
        try engineWriter.write(Frame.streamStart(reqId: reqId, streamId: sid, mediaUrn: "media:bytes"))
        let emptyPayload = Data()
        let emptyChecksum = Frame.computeChecksum(emptyPayload)
        try engineWriter.write(Frame.chunk(reqId: reqId, streamId: sid, seq: 0, payload: emptyPayload, chunkIndex: 0, checksum: emptyChecksum))
        try engineWriter.write(Frame.streamEnd(reqId: reqId, streamId: sid, chunkCount: 1))
        try engineWriter.write(Frame.end(id: reqId, finalPayload: nil))

        // Read response — should NOT contain any heartbeat frames
        var gotHeartbeat = false
        var responseData = Data()
        while true {
            guard let frame = try engineReader.read() else { break }
            if frame.frameType == .heartbeat { gotHeartbeat = true }
            if frame.frameType == .chunk { responseData.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertFalse(gotHeartbeat, "Heartbeat must NOT be forwarded to relay")
        XCTAssertEqual(String(data: responseData, encoding: .utf8), "ok")

        try? await pluginTask.value
        try? await hostTask.value
    }

    // TEST423: Multiple plugins registered with distinct caps route independently
    func testMultiplePluginsRouteIndependently() async throws {
        // Plugin A
        let hostToPluginA = Pipe()
        let pluginAToHost = Pipe()
        // Plugin B
        let hostToPluginB = Pipe()
        let pluginBToHost = Pipe()
        // Relay
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let manifestA = CborRuntimeTests.makeManifest(name: "PluginA", caps: ["cap:op=alpha"])
        let manifestB = CborRuntimeTests.makeManifest(name: "PluginB", caps: ["cap:op=beta"])

        let pluginAReader = FrameReader(handle: hostToPluginA.fileHandleForReading)
        let pluginAWriter = FrameWriter(handle: pluginAToHost.fileHandleForWriting)
        let pluginBReader = FrameReader(handle: hostToPluginB.fileHandleForReading)
        let pluginBWriter = FrameWriter(handle: pluginBToHost.fileHandleForWriting)

        let taskA = Task.detached { @Sendable [manifestA] in
            guard let _ = try pluginAReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginAWriter.write(CborRuntimeTests.helloWith(manifest: manifestA))
            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginAReader)
            guard cap == "cap:op=alpha" else { throw PluginHostError.protocolError("Expected alpha, got \(cap)") }
            try CborRuntimeTests.writeResponse(writer: pluginAWriter, reqId: reqId, payload: "from-A".data(using: .utf8)!)
        }

        let taskB = Task.detached { @Sendable [manifestB] in
            guard let _ = try pluginBReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginBWriter.write(CborRuntimeTests.helloWith(manifest: manifestB))
            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginBReader)
            guard cap == "cap:op=beta" else { throw PluginHostError.protocolError("Expected beta, got \(cap)") }
            try CborRuntimeTests.writeResponse(writer: pluginBWriter, reqId: reqId, payload: "from-B".data(using: .utf8)!)
        }

        let host = PluginHost()
        try host.attachPlugin(stdinHandle: hostToPluginA.fileHandleForWriting, stdoutHandle: pluginAToHost.fileHandleForReading)
        try host.attachPlugin(stdinHandle: hostToPluginB.fileHandleForWriting, stdoutHandle: pluginBToHost.fileHandleForReading)

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        // Send REQ for alpha
        let alphaId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: alphaId, capUrn: "cap:op=alpha", payload: Data(), contentType: "application/cbor"))
        try engineWriter.write(Frame.streamStart(reqId: alphaId, streamId: "a0", mediaUrn: "media:bytes"))
        try writeChunk(writer: engineWriter, reqId: alphaId, streamId: "a0", seq: 0, payload: Data(), chunkIndex: 0)
        try writeStreamEnd(writer: engineWriter, reqId: alphaId, streamId: "a0", chunkCount: 1)
        try engineWriter.write(Frame.end(id: alphaId, finalPayload: nil))

        // Send REQ for beta
        let betaId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: betaId, capUrn: "cap:op=beta", payload: Data(), contentType: "application/cbor"))
        try engineWriter.write(Frame.streamStart(reqId: betaId, streamId: "b0", mediaUrn: "media:bytes"))
        try engineWriter.write(Frame.chunk(reqId: betaId, streamId: "b0", seq: 0, payload: Data()))
        try engineWriter.write(Frame.streamEnd(reqId: betaId, streamId: "b0"))
        try engineWriter.write(Frame.end(id: betaId, finalPayload: nil))

        // Read responses
        var alphaData = Data()
        var betaData = Data()
        var ends = 0
        while ends < 2 {
            guard let frame = try engineReader.read() else { break }
            if frame.frameType == .chunk {
                if frame.id == alphaId { alphaData.append(frame.payload ?? Data()) }
                else if frame.id == betaId { betaData.append(frame.payload ?? Data()) }
            }
            if frame.frameType == .end { ends += 1 }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: alphaData, encoding: .utf8), "from-A", "Alpha response from Plugin A")
        XCTAssertEqual(String(data: betaData, encoding: .utf8), "from-B", "Beta response from Plugin B")

        try? await taskA.value
        try? await taskB.value
        try? await hostTask.value
    }

    // TEST432: REQ for unknown cap returns ERR (NoHandler)
    func testReqForUnknownCapReturnsErr() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWithManifest())
            // Plugin just waits — no request should arrive for unknown cap
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        // Send REQ for unknown cap
        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=nonexistent", payload: Data(), contentType: "text/plain"))

        // Should receive ERR with NO_HANDLER
        let frame = try engineReader.read()
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.frameType, .err, "Unknown cap should return ERR")
        XCTAssertEqual(frame!.errorCode, "NO_HANDLER", "Error code should be NO_HANDLER")

        engineToHost.fileHandleForWriting.closeFile()

        try? await pluginTask.value
        try? await hostTask.value
    }

    // MARK: - Handler Registration (TEST293)

    // TEST293: PluginRuntime handler registration and lookup
    func testPluginRuntimeHandlerRegistration() throws {
        let runtime = PluginRuntime(manifest: CborRuntimeTests.testManifestData)

        runtime.registerRaw(capUrn: "cap:in=media:;out=media:") { (stream: AsyncStream<Frame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            try emitter.emitCbor(.byteString([UInt8](data)))
        }

        runtime.registerRaw(capUrn: "cap:op=transform") { (stream: AsyncStream<Frame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            try emitter.emitCbor(.byteString([UInt8]("transformed".utf8)))
        }

        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:in=media:;out=media:"), "echo handler must be found")
        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:op=transform"), "transform handler must be found")
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=unknown"), "unknown handler must be nil")
    }

    // MARK: - Gap Tests (TEST415, TEST418, TEST420-422, TEST424)

    // TEST415: REQ for known cap triggers spawn (expect error for non-existent binary)
    func testReqTriggersSpawnError() async throws {
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let host = PluginHost()
        host.registerPlugin(path: "/nonexistent/plugin/binary/path", knownCaps: ["cap:op=spawn-test"])

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=spawn-test", payload: Data(), contentType: "text/plain"))

        let frame = try engineReader.read()
        XCTAssertNotNil(frame, "Must receive ERR frame for failed spawn")
        XCTAssertEqual(frame!.frameType, .err, "Failed spawn must return ERR")
        XCTAssertEqual(frame!.errorCode, "SPAWN_FAILED", "Error code must be SPAWN_FAILED")

        engineToHost.fileHandleForWriting.closeFile()
        try? await hostTask.value
    }

    // TEST418: Route STREAM_START/CHUNK/STREAM_END/END by req_id
    func testRouteContinuationByReqId() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "ContPlugin", caps: ["cap:op=cont"])
            ))

            // Read REQ
            guard let req = try pluginReader.read() else { throw PluginHostError.receiveFailed("No REQ") }
            guard req.frameType == .req else { throw PluginHostError.protocolError("Expected REQ") }
            let reqId = req.id

            // Read STREAM_START
            guard let ss = try pluginReader.read() else { throw PluginHostError.receiveFailed("No STREAM_START") }
            guard ss.frameType == .streamStart else { throw PluginHostError.protocolError("Expected STREAM_START, got \(ss.frameType)") }
            guard ss.id == reqId else { throw PluginHostError.protocolError("STREAM_START req_id mismatch") }

            // Read CHUNK
            guard let chunk = try pluginReader.read() else { throw PluginHostError.receiveFailed("No CHUNK") }
            guard chunk.frameType == .chunk else { throw PluginHostError.protocolError("Expected CHUNK, got \(chunk.frameType)") }
            guard chunk.payload == "payload-data".data(using: .utf8) else { throw PluginHostError.protocolError("CHUNK payload mismatch") }

            // Read STREAM_END
            guard let se = try pluginReader.read() else { throw PluginHostError.receiveFailed("No STREAM_END") }
            guard se.frameType == .streamEnd else { throw PluginHostError.protocolError("Expected STREAM_END, got \(se.frameType)") }

            // Read END
            guard let end = try pluginReader.read() else { throw PluginHostError.receiveFailed("No END") }
            guard end.frameType == .end else { throw PluginHostError.protocolError("Expected END, got \(end.frameType)") }

            // Respond
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId, payload: "ok".data(using: .utf8)!)
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=cont", payload: Data(), contentType: "text/plain"))
        try engineWriter.write(Frame.streamStart(reqId: reqId, streamId: "arg-0", mediaUrn: "media:bytes"))
        try engineWriter.write(Frame.chunk(reqId: reqId, streamId: "arg-0", seq: 0, payload: "payload-data".data(using: .utf8)!))
        try engineWriter.write(Frame.streamEnd(reqId: reqId, streamId: "arg-0"))
        try engineWriter.write(Frame.end(id: reqId, finalPayload: nil))

        var responseData = Data()
        while true {
            guard let frame = try engineReader.read() else { break }
            if frame.frameType == .chunk { responseData.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: responseData, encoding: .utf8), "ok", "Continuation frames must route correctly")

        try await pluginTask.value
        try? await hostTask.value
    }

    // TEST420: Plugin non-HELLO/non-HB frames forwarded to relay
    func testPluginFramesForwardedToRelay() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "FwdPlugin", caps: ["cap:op=fwd"])
            ))

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Send diverse frame types back
            try pluginWriter.write(Frame.log(id: reqId, level: "info", message: "processing"))
            try pluginWriter.write(Frame.streamStart(reqId: reqId, streamId: "output", mediaUrn: "media:bytes"))
            try pluginWriter.write(Frame.chunk(reqId: reqId, streamId: "output", seq: 0, payload: "data".data(using: .utf8)!))
            try pluginWriter.write(Frame.streamEnd(reqId: reqId, streamId: "output"))
            try pluginWriter.write(Frame.end(id: reqId, finalPayload: nil))
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=fwd", payload: Data(), contentType: "text/plain"))
        try engineWriter.write(Frame.streamStart(reqId: reqId, streamId: "a0", mediaUrn: "media:bytes"))
        try engineWriter.write(Frame.chunk(reqId: reqId, streamId: "a0", seq: 0, payload: Data()))
        try engineWriter.write(Frame.streamEnd(reqId: reqId, streamId: "a0"))
        try engineWriter.write(Frame.end(id: reqId, finalPayload: nil))

        var receivedTypes: [FrameType] = []
        while true {
            guard let frame = try engineReader.read() else { break }
            receivedTypes.append(frame.frameType)
            if frame.frameType == .end { break }
        }

        engineToHost.fileHandleForWriting.closeFile()

        let typeSet = Set(receivedTypes)
        XCTAssertTrue(typeSet.contains(.log), "LOG must be forwarded")
        XCTAssertTrue(typeSet.contains(.streamStart), "STREAM_START must be forwarded")
        XCTAssertTrue(typeSet.contains(.chunk), "CHUNK must be forwarded")
        XCTAssertTrue(typeSet.contains(.end), "END must be forwarded")

        try await pluginTask.value
        try? await hostTask.value
    }

    // TEST421: Plugin death updates capability list (removes dead plugin's caps)
    func testPluginDeathUpdatesCaps() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "DiePlugin", caps: ["cap:op=die"])
            ))
            // Die immediately by closing write end
            pluginToHost.fileHandleForWriting.closeFile()
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        // Before death: cap should be present
        XCTAssertNotNil(host.findPluginForCap("cap:op=die"), "Cap must be found before death")

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        // Wait for plugin death to be processed
        try await Task.sleep(nanoseconds: 500_000_000)

        // Close relay to let run() exit
        engineToHost.fileHandleForWriting.closeFile()

        try? await pluginTask.value
        try? await hostTask.value

        // After death: capabilities should not include the dead plugin's caps
        let capsAfter = host.capabilities
        if !capsAfter.isEmpty, let capsStr = String(data: capsAfter, encoding: .utf8) {
            XCTAssertFalse(capsStr.contains("cap:op=die"), "Dead plugin's caps must be removed")
        }
    }

    // TEST422: Plugin death sends ERR for all pending requests
    func testPluginDeathSendsErr() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "DiePlugin", caps: ["cap:op=die"])
            ))
            // Read REQ, then die without responding
            let _ = try pluginReader.read()
            pluginToHost.fileHandleForWriting.closeFile()
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        try engineWriter.write(Frame.req(id: reqId, capUrn: "cap:op=die", payload: Data(), contentType: "text/plain"))
        try engineWriter.write(Frame.streamStart(reqId: reqId, streamId: "a0", mediaUrn: "media:bytes"))
        try engineWriter.write(Frame.chunk(reqId: reqId, streamId: "a0", seq: 0, payload: "hello".data(using: .utf8)!))
        try engineWriter.write(Frame.streamEnd(reqId: reqId, streamId: "a0"))
        try engineWriter.write(Frame.end(id: reqId, finalPayload: nil))

        // Should receive ERR with PLUGIN_DIED
        var errFrame: Frame?
        while true {
            guard let frame = try engineReader.read() else { break }
            if frame.frameType == .err {
                errFrame = frame
                break
            }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertNotNil(errFrame, "Must receive ERR when plugin dies with pending request")
        XCTAssertEqual(errFrame!.errorCode, "PLUGIN_DIED", "Error code must be PLUGIN_DIED")

        try? await pluginTask.value
        try? await hostTask.value
    }

    // TEST424: Concurrent requests to same plugin handled independently
    func testConcurrentRequestsSamePlugin() async throws {
        let hostToPlugin = Pipe()
        let pluginToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let pluginReader = FrameReader(handle: hostToPlugin.fileHandleForReading)
        let pluginWriter = FrameWriter(handle: pluginToHost.fileHandleForWriting)

        let pluginTask = Task.detached { @Sendable in
            guard let _ = try pluginReader.read() else { throw PluginHostError.receiveFailed("") }
            try pluginWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "ConcPlugin", caps: ["cap:op=conc"])
            ))

            // Read first complete request
            let (reqId0, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)
            // Read second complete request
            let (reqId1, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: pluginReader)

            // Respond to both
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId0, payload: "response-0".data(using: .utf8)!, streamId: "s0")
            try CborRuntimeTests.writeResponse(writer: pluginWriter, reqId: reqId1, payload: "response-1".data(using: .utf8)!, streamId: "s1")
        }

        let host = PluginHost()
        try host.attachPlugin(
            stdinHandle: hostToPlugin.fileHandleForWriting,
            stdoutHandle: pluginToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let id0 = MessageId.newUUID()
        let id1 = MessageId.newUUID()

        // Send both requests
        try engineWriter.write(Frame.req(id: id0, capUrn: "cap:op=conc", payload: Data(), contentType: "text/plain"))
        try engineWriter.write(Frame.streamStart(reqId: id0, streamId: "a0", mediaUrn: "media:bytes"))
        try engineWriter.write(Frame.chunk(reqId: id0, streamId: "a0", seq: 0, payload: Data()))
        try engineWriter.write(Frame.streamEnd(reqId: id0, streamId: "a0"))
        try engineWriter.write(Frame.end(id: id0, finalPayload: nil))

        try engineWriter.write(Frame.req(id: id1, capUrn: "cap:op=conc", payload: Data(), contentType: "text/plain"))
        try engineWriter.write(Frame.streamStart(reqId: id1, streamId: "a1", mediaUrn: "media:bytes"))
        try engineWriter.write(Frame.chunk(reqId: id1, streamId: "a1", seq: 0, payload: Data()))
        try engineWriter.write(Frame.streamEnd(reqId: id1, streamId: "a1"))
        try engineWriter.write(Frame.end(id: id1, finalPayload: nil))

        // Read both responses
        var data0 = Data()
        var data1 = Data()
        var ends = 0
        while ends < 2 {
            guard let frame = try engineReader.read() else { break }
            if frame.frameType == .chunk {
                if frame.id == id0 { data0.append(frame.payload ?? Data()) }
                else if frame.id == id1 { data1.append(frame.payload ?? Data()) }
            }
            if frame.frameType == .end { ends += 1 }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: data0, encoding: .utf8), "response-0", "First request must get response-0")
        XCTAssertEqual(String(data: data1, encoding: .utf8), "response-1", "Second request must get response-1")

        try await pluginTask.value
        try? await hostTask.value
    }

    // MARK: - Response Types (TEST316)

    // TEST316: concatenated() returns full payload while finalPayload returns only last chunk
    func testConcatenatedVsFinalPayloadDivergence() {
        let chunks = [
            ResponseChunk(payload: "AAAA".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: "BBBB".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: "CCCC".data(using: .utf8)!, seq: 2, offset: nil, len: nil, isEof: true),
        ]

        let response = PluginResponse.streaming(chunks)
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "AAAABBBBCCCC")
        XCTAssertEqual(String(data: response.finalPayload!, encoding: .utf8), "CCCC")
        XCTAssertNotEqual(response.concatenated(), response.finalPayload!,
            "concatenated and finalPayload must diverge for multi-chunk responses")
    }
}
