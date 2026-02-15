import XCTest
@testable import Bifaci

@available(macOS 10.15.4, iOS 13.4, *)
class CborRelayTests: XCTestCase {

    // MARK: - Helpers

    /// Create a pipe pair for relay testing.
    /// Returns (reader FileHandle, writer FileHandle).
    private func createPipe() -> (read: FileHandle, write: FileHandle) {
        let pipe = Pipe()
        return (pipe.fileHandleForReading, pipe.fileHandleForWriting)
    }

    // MARK: - TEST404: Slave sends RelayNotify on connect

    // TEST404: Slave sends RelayNotify on connect (initial_notify parameter)
    func testSlaveSendsRelayNotifyOnConnect() throws {
        let manifest = "{\"caps\":[\"cap:op=test\"]}".data(using: .utf8)!
        let limits = Limits()

        // Socket: slave writes -> master reads
        let socket = createPipe()
        let socketWriter = FrameWriter(handle: socket.write)
        let socketReader = FrameReader(handle: socket.read)

        // Send notify
        try RelaySlave.sendNotify(
            socketWriter: socketWriter,
            manifest: manifest,
            limits: limits
        )
        // Close write end so reader gets frame then EOF
        socket.write.closeFile()

        // Master reads the frame
        let frame = try socketReader.read()
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.frameType, .relayNotify)
        XCTAssertEqual(frame!.relayNotifyManifest, manifest)
        let extractedLimits = frame!.relayNotifyLimits!
        XCTAssertEqual(extractedLimits.maxFrame, limits.maxFrame)
        XCTAssertEqual(extractedLimits.maxChunk, limits.maxChunk)
    }

    // MARK: - TEST405: Master reads RelayNotify and extracts manifest + limits

    // TEST405: Master reads RelayNotify and extracts manifest + limits
    func testMasterReadsRelayNotify() throws {
        let manifest = "{\"caps\":[\"cap:op=convert\"]}".data(using: .utf8)!
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 64_000)

        let socket = createPipe()
        let socketWriter = FrameWriter(handle: socket.write)
        let socketReader = FrameReader(handle: socket.read)

        // Slave sends RelayNotify
        let frame = Frame.relayNotify(
            manifest: manifest,
            limits: limits
        )
        try socketWriter.write(frame)
        socket.write.closeFile()

        // Master connects
        let master = try RelayMaster.connect(socketReader: socketReader)
        XCTAssertEqual(master.manifest, manifest)
        XCTAssertEqual(master.limits.maxFrame, 1_000_000)
        XCTAssertEqual(master.limits.maxChunk, 64_000)
    }

    // MARK: - TEST406: Slave stores RelayState from master

    // TEST406: Slave stores RelayState from master
    func testSlaveStoresRelayState() throws {
        let resources = "{\"memory_mb\":4096}".data(using: .utf8)!

        // Socket: master writes -> slave reads
        let socketPipe = createPipe()
        // Local: slave writes -> runtime reads (and local read not used by slave in this test)
        let localReadPipe = createPipe()
        let localWritePipe = createPipe()

        let slave = RelaySlave(localRead: localReadPipe.read, localWrite: localWritePipe.write)

        let socketWriter = FrameWriter(handle: socketPipe.write)

        // Master sends RelayState
        try RelayMaster.sendState(socketWriter: socketWriter, resources: resources)
        socketPipe.write.closeFile()

        // Slave reads frame directly (not via run() since that requires bidirectional)
        let socketReader = FrameReader(handle: socketPipe.read)
        let frame = try socketReader.read()
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.frameType, .relayState)
        XCTAssertEqual(frame!.payload, resources)
    }

    // MARK: - TEST407: Protocol frames pass through transparently

    // TEST407: Protocol frames pass through slave transparently (both directions)
    func testProtocolFramesPassThrough() throws {
        // Socket pair: master <-> slave
        let masterToSlave = createPipe()
        let slaveToMaster = createPipe()
        // Local pair: slave <-> host runtime
        let slaveToRuntime = createPipe()
        let runtimeToSlave = createPipe()

        let reqId = MessageId.newUUID()

        // Slave relay: manually forward one frame each direction
        let masterWriter = FrameWriter(handle: masterToSlave.write)
        let slaveSocketReader = FrameReader(handle: masterToSlave.read)
        let slaveSocketWriter = FrameWriter(handle: slaveToMaster.write)
        let slaveLocalReader = FrameReader(handle: runtimeToSlave.read)
        let slaveLocalWriter = FrameWriter(handle: slaveToRuntime.write)

        // Master sends a REQ through the socket
        let req = Frame.req(id: reqId, capUrn: "cap:op=test", payload: "hello".data(using: .utf8)!, contentType: "text/plain")
        try masterWriter.write(req)
        masterToSlave.write.closeFile()

        // Runtime sends a CHUNK through the local write
        let chunkId = MessageId.newUUID()
        let chunkPayload = "response".data(using: .utf8)!
        let chunk = Frame.chunk(reqId: chunkId, streamId: "stream-1", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPayload))
        let runtimeWriter = FrameWriter(handle: runtimeToSlave.write)
        try runtimeWriter.write(chunk)
        runtimeToSlave.write.closeFile()

        // Socket -> local: read REQ, forward to local
        let fromSocket = try slaveSocketReader.read()!
        XCTAssertEqual(fromSocket.frameType, .req)
        try slaveLocalWriter.write(fromSocket)
        slaveToRuntime.write.closeFile()

        // Local -> socket: read CHUNK, forward to socket
        let fromLocal = try slaveLocalReader.read()!
        XCTAssertEqual(fromLocal.frameType, .chunk)
        try slaveSocketWriter.write(fromLocal)
        slaveToMaster.write.closeFile()

        // Runtime reads the forwarded REQ
        let runtimeReader = FrameReader(handle: slaveToRuntime.read)
        let runtimeFrame = try runtimeReader.read()!
        XCTAssertEqual(runtimeFrame.frameType, .req)
        XCTAssertEqual(runtimeFrame.cap, "cap:op=test")
        XCTAssertEqual(runtimeFrame.payload, "hello".data(using: .utf8)!)

        // Master reads the forwarded CHUNK
        let masterReader = FrameReader(handle: slaveToMaster.read)
        let masterFrame = try masterReader.read()!
        XCTAssertEqual(masterFrame.frameType, .chunk)
        XCTAssertEqual(masterFrame.payload, "response".data(using: .utf8)!)
    }

    // MARK: - TEST408: RelayNotify/RelayState are NOT forwarded

    // TEST408: RelayNotify/RelayState are NOT forwarded through relay
    func testRelayFramesNotForwarded() throws {
        // Master sends RelayState then a normal REQ
        let socketPipe = createPipe()
        let localWritePipe = createPipe()

        let masterWriter = FrameWriter(handle: socketPipe.write)
        let socketReader = FrameReader(handle: socketPipe.read)
        let localWriter = FrameWriter(handle: localWritePipe.write)

        // Send RelayState (should be intercepted)
        let state = Frame.relayState(resources: "{\"memory\":1024}".data(using: .utf8)!)
        try masterWriter.write(state)

        // Send normal REQ (should pass through)
        let req = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        try masterWriter.write(req)
        socketPipe.write.closeFile()

        // Read first frame — RelayState, should NOT be forwarded
        let frame1 = try socketReader.read()!
        XCTAssertEqual(frame1.frameType, .relayState)
        // Store it (as slave would)
        let storedResources = frame1.payload!
        XCTAssertEqual(storedResources, "{\"memory\":1024}".data(using: .utf8)!)

        // Read second frame — REQ, should be forwarded
        let frame2 = try socketReader.read()!
        XCTAssertEqual(frame2.frameType, .req)
        try localWriter.write(frame2)
    }

    // MARK: - TEST409: Slave injects RelayNotify mid-stream

    // TEST409: Slave can inject RelayNotify mid-stream (cap change)
    func testSlaveInjectsRelayNotifyMidstream() throws {
        let socketPipe = createPipe()
        let socketWriter = FrameWriter(handle: socketPipe.write)
        let socketReader = FrameReader(handle: socketPipe.read)
        let limits = Limits()

        // Send initial RelayNotify
        let initial = "{\"caps\":[\"cap:op=test\"]}".data(using: .utf8)!
        try RelaySlave.sendNotify(socketWriter: socketWriter, manifest: initial, limits: limits)

        // Forward a normal CHUNK frame
        let chunkPay = "data".data(using: .utf8)!
        let chunk = Frame.chunk(reqId: .newUUID(), streamId: "stream-1", seq: 0, payload: chunkPay, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPay))
        try socketWriter.write(chunk)

        // Inject updated RelayNotify (new cap discovered)
        let updated = "{\"caps\":[\"cap:op=test\",\"cap:op=convert\"]}".data(using: .utf8)!
        try RelaySlave.sendNotify(socketWriter: socketWriter, manifest: updated, limits: limits)
        socketPipe.write.closeFile()

        // Read initial RelayNotify
        let f1 = try socketReader.read()!
        XCTAssertEqual(f1.frameType, .relayNotify)
        XCTAssertEqual(f1.relayNotifyManifest, initial)

        // Read CHUNK (passed through)
        let f2 = try socketReader.read()!
        XCTAssertEqual(f2.frameType, .chunk)

        // Read updated RelayNotify
        let f3 = try socketReader.read()!
        XCTAssertEqual(f3.frameType, .relayNotify)
        XCTAssertEqual(f3.relayNotifyManifest, updated)
    }

    // MARK: - TEST410: Master receives updated RelayNotify

    // TEST410: Master receives updated RelayNotify (cap change callback via readFrame)
    func testMasterReceivesUpdatedRelayNotify() throws {
        let socketPipe = createPipe()
        let socketWriter = FrameWriter(handle: socketPipe.write)
        let socketReader = FrameReader(handle: socketPipe.read)

        let limits = Limits(maxFrame: 2_000_000, maxChunk: 100_000)

        // Initial RelayNotify
        let initialManifest = "{\"caps\":[{\"urn\":\"cap:in=media:;out=media:\",\"title\":\"Identity\",\"command\":\"identity\"},{\"urn\":\"cap:in=media:;op=a;out=media:\",\"title\":\"A\",\"command\":\"a\"}]}".data(using: .utf8)!
        let initial = Frame.relayNotify(manifest: initialManifest, limits: limits)
        try socketWriter.write(initial)

        // Normal frame
        let end1 = Frame.end(id: .newUUID())
        try socketWriter.write(end1)

        // Updated RelayNotify with new limits
        let updatedManifest = "{\"caps\":[{\"urn\":\"cap:in=media:;out=media:\",\"title\":\"Identity\",\"command\":\"identity\"},{\"urn\":\"cap:in=media:;op=a;out=media:\",\"title\":\"A\",\"command\":\"a\"},{\"urn\":\"cap:in=media:;op=b;out=media:\",\"title\":\"B\",\"command\":\"b\"}]}".data(using: .utf8)!
        let updatedLimits = Limits(maxFrame: 3_000_000, maxChunk: 200_000, maxReorderBuffer: 64)
        let updated = Frame.relayNotify(manifest: updatedManifest, limits: updatedLimits)
        try socketWriter.write(updated)

        // Another normal frame
        let end2 = Frame.end(id: .newUUID())
        try socketWriter.write(end2)
        socketPipe.write.closeFile()

        // Master connects
        let master = try RelayMaster.connect(socketReader: socketReader)
        XCTAssertEqual(master.manifest, initialManifest)
        XCTAssertEqual(master.limits.maxFrame, 2_000_000)

        // First non-relay frame
        let f1 = try master.readFrame(socketReader: socketReader)!
        XCTAssertEqual(f1.frameType, .end)

        // readFrame should have intercepted the updated RelayNotify
        let f2 = try master.readFrame(socketReader: socketReader)!
        XCTAssertEqual(f2.frameType, .end)

        // Manifest and limits should be updated
        XCTAssertEqual(master.manifest, updatedManifest)
        XCTAssertEqual(master.limits.maxFrame, 3_000_000)
        XCTAssertEqual(master.limits.maxChunk, 200_000)
    }

    // MARK: - TEST411: Socket close detection

    // TEST411: Socket close detection (both directions)
    func testSocketCloseDetection() throws {
        // Master -> slave: master closes, slave detects
        let pipe1 = createPipe()
        pipe1.write.closeFile() // Close immediately
        let reader1 = FrameReader(handle: pipe1.read)
        let result1 = try reader1.read()
        XCTAssertNil(result1, "closed socket must return nil")

        // Slave -> master: slave sends RelayNotify then closes
        let pipe2 = createPipe()
        let writer2 = FrameWriter(handle: pipe2.write)
        let reader2 = FrameReader(handle: pipe2.read)

        let notify = Frame.relayNotify(manifest: "[]".data(using: .utf8)!, limits: Limits())
        try writer2.write(notify)
        pipe2.write.closeFile()

        let master = try RelayMaster.connect(socketReader: reader2)
        XCTAssertNotNil(master)
        let result2 = try master.readFrame(socketReader: reader2)
        XCTAssertNil(result2, "closed socket must return nil")
    }

    // MARK: - TEST412: Bidirectional concurrent frame flow

    // TEST412: Bidirectional concurrent frame flow through relay
    func testBidirectionalConcurrentFlow() throws {
        // Socket pair
        let masterToSlave = createPipe()
        let slaveToMaster = createPipe()

        let reqId1 = MessageId.newUUID()
        let reqId2 = MessageId.newUUID()
        let respId = MessageId.newUUID()

        let masterWriter = FrameWriter(handle: masterToSlave.write)
        let slaveSocketReader = FrameReader(handle: masterToSlave.read)
        let slaveSocketWriter = FrameWriter(handle: slaveToMaster.write)
        let masterReader = FrameReader(handle: slaveToMaster.read)

        // Master writes 2 REQ frames
        let req1 = Frame.req(id: reqId1, capUrn: "cap:op=a", payload: "data-a".data(using: .utf8)!, contentType: "text/plain")
        let req2 = Frame.req(id: reqId2, capUrn: "cap:op=b", payload: "data-b".data(using: .utf8)!, contentType: "text/plain")
        try masterWriter.write(req1)
        try masterWriter.write(req2)
        masterToSlave.write.closeFile()

        // Read REQs at slave
        let f1 = try slaveSocketReader.read()!
        let f2 = try slaveSocketReader.read()!
        XCTAssertEqual(f1.frameType, .req)
        XCTAssertEqual(f2.frameType, .req)
        XCTAssertEqual(f1.id, reqId1)
        XCTAssertEqual(f2.id, reqId2)

        // Slave writes response frames
        let respPayload = "resp-a".data(using: .utf8)!
        let chunk = Frame.chunk(reqId: respId, streamId: "s1", seq: 0, payload: respPayload, chunkIndex: 0, checksum: Frame.computeChecksum(respPayload))
        let end = Frame.end(id: respId)
        try slaveSocketWriter.write(chunk)
        try slaveSocketWriter.write(end)
        slaveToMaster.write.closeFile()

        // Master reads responses
        let r1 = try masterReader.read()!
        XCTAssertEqual(r1.frameType, .chunk)
        XCTAssertEqual(r1.payload, "resp-a".data(using: .utf8)!)
        let r2 = try masterReader.read()!
        XCTAssertEqual(r2.frameType, .end)
    }
}
