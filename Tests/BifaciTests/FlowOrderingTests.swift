import XCTest
@testable import Bifaci

/// Tests for seq-based frame ordering (TEST442-461)
/// Based on Rust tests in src/bifaci/frame.rs
final class FlowOrderingTests: XCTestCase {

    // MARK: - SeqAssigner Tests (TEST442-446)

    // TEST442: SeqAssigner assigns seq 0,1,2,3 for consecutive frames with same RID
    func testSeqAssignerMonotonicSameRid() {
        var assigner = SeqAssigner()
        let rid = MessageId.newUUID()

        var f0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        var f1 = Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:bytes")
        var f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        var f3 = Frame.end(id: rid, finalPayload: nil)

        assigner.assign(&f0)
        assigner.assign(&f1)
        assigner.assign(&f2)
        assigner.assign(&f3)

        XCTAssertEqual(f0.seq, 0, "First frame must have seq=0")
        XCTAssertEqual(f1.seq, 1, "Second frame must have seq=1")
        XCTAssertEqual(f2.seq, 2, "Third frame must have seq=2")
        XCTAssertEqual(f3.seq, 3, "Fourth frame must have seq=3")
    }

    // TEST443: SeqAssigner maintains independent counters for different RIDs
    func testSeqAssignerIndependentRids() {
        var assigner = SeqAssigner()
        let ridA = MessageId.newUUID()
        let ridB = MessageId.newUUID()

        var a0 = Frame.req(id: ridA, capUrn: "cap:op=a;in=media:;out=media:", payload: Data(), contentType: "")
        var b0 = Frame.req(id: ridB, capUrn: "cap:op=b;in=media:;out=media:", payload: Data(), contentType: "")
        var a1 = Frame.chunk(reqId: ridA, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        var b1 = Frame.chunk(reqId: ridB, streamId: "s2", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        var a2 = Frame.end(id: ridA, finalPayload: nil)

        assigner.assign(&a0)
        assigner.assign(&b0)
        assigner.assign(&a1)
        assigner.assign(&b1)
        assigner.assign(&a2)

        XCTAssertEqual(a0.seq, 0, "RID A first frame seq=0")
        XCTAssertEqual(a1.seq, 1, "RID A second frame seq=1")
        XCTAssertEqual(a2.seq, 2, "RID A third frame seq=2")
        XCTAssertEqual(b0.seq, 0, "RID B first frame seq=0")
        XCTAssertEqual(b1.seq, 1, "RID B second frame seq=1")
    }

    // TEST444: SeqAssigner skips non-flow frames (Heartbeat, RelayNotify, RelayState, Hello)
    func testSeqAssignerSkipsNonFlow() {
        var assigner = SeqAssigner()

        var hello = Frame.hello(limits: Limits())
        var hb = Frame.heartbeat(id: MessageId.newUUID())
        var notify = Frame.relayNotify(manifest: Data(), limits: Limits())
        var state = Frame.relayState(resources: Data())

        assigner.assign(&hello)
        assigner.assign(&hb)
        assigner.assign(&notify)
        assigner.assign(&state)

        XCTAssertEqual(hello.seq, 0, "Hello seq must stay 0 (non-flow frame)")
        XCTAssertEqual(hb.seq, 0, "Heartbeat seq must stay 0 (non-flow frame)")
        XCTAssertEqual(notify.seq, 0, "RelayNotify seq must stay 0 (non-flow frame)")
        XCTAssertEqual(state.seq, 0, "RelayState seq must stay 0 (non-flow frame)")
    }

    // TEST445: SeqAssigner.remove resets flow; next frame for that RID starts at seq 0
    func testSeqAssignerRemoveResets() {
        var assigner = SeqAssigner()
        let rid = MessageId.newUUID()

        var f0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        var f1 = Frame.end(id: rid, finalPayload: nil)
        assigner.assign(&f0)
        assigner.assign(&f1)
        XCTAssertEqual(f1.seq, 1, "Second frame before remove seq=1")

        assigner.remove(rid)

        var f2 = Frame.req(id: rid, capUrn: "cap:op=test2;in=media:;out=media:", payload: Data(), contentType: "")
        assigner.assign(&f2)
        XCTAssertEqual(f2.seq, 0, "After remove, seq must restart at 0")
    }

    // TEST446: SeqAssigner handles mixed frame types (REQ, CHUNK, LOG, END) for same RID
    func testSeqAssignerMixedTypes() {
        var assigner = SeqAssigner()
        let rid = MessageId.newUUID()

        var req = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        var log = Frame.log(id: rid, level: "info", message: "progress")
        var chunk = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        var end = Frame.end(id: rid, finalPayload: nil)

        assigner.assign(&req)
        assigner.assign(&log)
        assigner.assign(&chunk)
        assigner.assign(&end)

        XCTAssertEqual(req.seq, 0, "REQ seq=0")
        XCTAssertEqual(log.seq, 1, "LOG seq=1")
        XCTAssertEqual(chunk.seq, 2, "CHUNK seq=2")
        XCTAssertEqual(end.seq, 3, "END seq=3")
    }

    // MARK: - FlowKey Tests (TEST447-450)

    // TEST447: FlowKey::from_frame extracts (rid, Some(xid)) when routing_id present
    func testFlowKeyWithXid() {
        let rid = MessageId.newUUID()
        let xid = MessageId.newUUID()
        var frame = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        frame.routingId = xid

        let key = FlowKey.fromFrame(frame)
        XCTAssertEqual(key.rid, rid, "FlowKey rid must match frame id")
        XCTAssertEqual(key.xid, xid, "FlowKey xid must match frame routingId")
    }

    // TEST448: FlowKey::from_frame extracts (rid, None) when routing_id absent
    func testFlowKeyWithoutXid() {
        let rid = MessageId.newUUID()
        let frame = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")

        let key = FlowKey.fromFrame(frame)
        XCTAssertEqual(key.rid, rid, "FlowKey rid must match frame id")
        XCTAssertNil(key.xid, "FlowKey xid must be nil when no routingId")
    }

    // TEST449: FlowKey equality: same rid+xid equal, different xid different key
    func testFlowKeyEquality() {
        let rid = MessageId.newUUID()
        let xid1 = MessageId.newUUID()
        let xid2 = MessageId.newUUID()

        let keyWithXid1 = FlowKey(rid: rid, xid: xid1)
        let keyWithXid1Dup = FlowKey(rid: rid, xid: xid1)
        let keyWithXid2 = FlowKey(rid: rid, xid: xid2)
        let keyNoXid = FlowKey(rid: rid, xid: nil)

        XCTAssertEqual(keyWithXid1, keyWithXid1Dup, "Same rid+xid must be equal")
        XCTAssertNotEqual(keyWithXid1, keyWithXid2, "Different xid must not be equal")
        XCTAssertNotEqual(keyWithXid1, keyNoXid, "xid vs no-xid must not be equal")
    }

    // TEST450: FlowKey hash: same keys hash equal (HashMap lookup)
    func testFlowKeyHash() {
        let rid = MessageId.newUUID()
        let xid = MessageId.newUUID()

        let key1 = FlowKey(rid: rid, xid: xid)
        let key2 = FlowKey(rid: rid, xid: xid)

        var set: Set<FlowKey> = []
        set.insert(key1)
        set.insert(key2)

        XCTAssertEqual(set.count, 1, "Same keys must hash equal (single entry in Set)")
        XCTAssertTrue(set.contains(key1), "Set must contain key1")
        XCTAssertTrue(set.contains(key2), "Set must contain key2")
    }

    // MARK: - ReorderBuffer Tests (TEST451-460)

    // TEST451: ReorderBuffer in-order delivery: seq 0,1,2 delivered immediately
    func testReorderBufferInOrder() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)
        let f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data(), chunkIndex: 2, checksum: 0)

        let out0 = try buffer.accept( f0)
        let out1 = try buffer.accept( f1)
        let out2 = try buffer.accept( f2)

        XCTAssertEqual(out0.count, 1, "In-order frame 0 delivers immediately")
        XCTAssertEqual(out0[0].seq, 0)
        XCTAssertEqual(out1.count, 1, "In-order frame 1 delivers immediately")
        XCTAssertEqual(out1[0].seq, 1)
        XCTAssertEqual(out2.count, 1, "In-order frame 2 delivers immediately")
        XCTAssertEqual(out2[0].seq, 2)
    }

    // TEST452: ReorderBuffer out-of-order: seq 1 then 0 delivers both in order
    func testReorderBufferOutOfOrder() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)
        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)

        let out1 = try buffer.accept( f1)
        XCTAssertEqual(out1.count, 0, "Out-of-order frame 1 must be buffered")

        let out0 = try buffer.accept( f0)
        XCTAssertEqual(out0.count, 2, "Frame 0 must trigger delivery of 0+1")
        XCTAssertEqual(out0[0].seq, 0)
        XCTAssertEqual(out0[1].seq, 1)
    }

    // TEST453: ReorderBuffer gap fill: seq 0,2,1 delivers 0, buffers 2, then delivers 1+2
    func testReorderBufferGapFill() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data(), chunkIndex: 2, checksum: 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)

        let out0 = try buffer.accept( f0)
        XCTAssertEqual(out0.count, 1, "Frame 0 delivers immediately")
        XCTAssertEqual(out0[0].seq, 0)

        let out2 = try buffer.accept( f2)
        XCTAssertEqual(out2.count, 0, "Frame 2 (gap) must be buffered")

        let out1 = try buffer.accept( f1)
        XCTAssertEqual(out1.count, 2, "Frame 1 fills gap, delivers 1+2")
        XCTAssertEqual(out1[0].seq, 1)
        XCTAssertEqual(out1[1].seq, 2)
    }

    // TEST454: ReorderBuffer stale seq is hard error
    func testReorderBufferStaleSeq() {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)
        let f0_dup = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)

        _ = try? buffer.accept( f0)
        _ = try? buffer.accept( f1)

        XCTAssertThrowsError(try buffer.accept( f0_dup), "Stale/duplicate seq must throw") { error in
            XCTAssertTrue(error is FrameError, "Must throw FrameError")
        }
    }

    // TEST455: ReorderBuffer overflow triggers protocol error
    func testReorderBufferOverflow() {
        var buffer = ReorderBuffer(maxBufferPerFlow: 2)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        // Send seq 0, then skip to seq 10 (exceeds buffer capacity)
        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let f10 = Frame.chunk(reqId: rid, streamId: "s1", seq: 10, payload: Data(), chunkIndex: 10, checksum: 0)

        _ = try? buffer.accept( f0)

        XCTAssertThrowsError(try buffer.accept( f10), "Buffer overflow must throw") { error in
            XCTAssertTrue(error is FrameError, "Must throw FrameError")
        }
    }

    // TEST456: Multiple concurrent flows reorder independently
    func testReorderBufferMultipleFlows() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let ridA = MessageId.newUUID()
        let ridB = MessageId.newUUID()
        let flowA = FlowKey(rid: ridA, xid: nil)
        let flowB = FlowKey(rid: ridB, xid: nil)

        // Flow A: seq 1 then 0
        let a1 = Frame.chunk(reqId: ridA, streamId: "a", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)
        let a0 = Frame.chunk(reqId: ridA, streamId: "a", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)

        // Flow B: seq 0 then 1 (in-order)
        let b0 = Frame.chunk(reqId: ridB, streamId: "b", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let b1 = Frame.chunk(reqId: ridB, streamId: "b", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)

        let outA1 = try buffer.accept(a1)
        XCTAssertEqual(outA1.count, 0, "Flow A seq 1 buffered")

        let outB0 = try buffer.accept(b0)
        XCTAssertEqual(outB0.count, 1, "Flow B seq 0 delivers immediately")

        let outA0 = try buffer.accept(a0)
        XCTAssertEqual(outA0.count, 2, "Flow A seq 0 delivers 0+1")

        let outB1 = try buffer.accept(b1)
        XCTAssertEqual(outB1.count, 1, "Flow B seq 1 delivers immediately")
    }

    // TEST457: cleanup_flow removes state; new frames start at seq 0
    func testReorderBufferCleanupFlow() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0)

        _ = try buffer.accept( f0)
        _ = try buffer.accept( f1)

        buffer.cleanupFlow(flow)

        // After cleanup, new seq 0 should be accepted
        let f0_new = Frame.chunk(reqId: rid, streamId: "s2", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let out = try buffer.accept( f0_new)
        XCTAssertEqual(out.count, 1, "After cleanup, seq 0 must be accepted again")
    }

    // TEST458: Non-flow frames bypass reorder entirely
    func testReorderBufferNonFlowBypass() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let hb = Frame.heartbeat(id: rid)

        let out = try buffer.accept( hb)
        XCTAssertEqual(out.count, 1, "Non-flow frame must bypass buffer")
        XCTAssertEqual(out[0].frameType, .heartbeat)
    }

    // TEST459: Terminal END frame flows through correctly
    func testReorderBufferTerminalEnd() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let endFrame = Frame.end(id: rid, finalPayload: nil)

        _ = try buffer.accept( f0)
        let outEnd = try buffer.accept( endFrame)

        XCTAssertEqual(outEnd.count, 1, "END frame must flow through")
        XCTAssertEqual(outEnd[0].frameType, FrameType.end)
    }

    // TEST460: Terminal ERR frame flows through correctly
    func testReorderBufferTerminalErr() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let errFrame = Frame.err(id: rid, code: "TEST_ERROR", message: "test")

        _ = try buffer.accept( f0)
        let outErr = try buffer.accept( errFrame)

        XCTAssertEqual(outErr.count, 1, "ERR frame must flow through")
        XCTAssertEqual(outErr[0].frameType, FrameType.err)
    }

    // TEST461: write_chunked produces frames with seq=0; SeqAssigner assigns at output stage
    @available(macOS 10.15.4, iOS 13.4, *)
    func testWriteChunkedSeqZero() throws {
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 5, maxReorderBuffer: 64)
        let pipe = Pipe()
        let writer = FrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = MessageId.newUUID()
        let streamId = "s"
        let data = "abcdefghij".data(using: .utf8)! // 10 bytes

        try writer.writeChunked(id: id, streamId: streamId, contentType: "application/octet-stream", data: data)
        pipe.fileHandleForWriting.closeFile()

        // Read all frames back
        let reader = FrameReader(handle: pipe.fileHandleForReading, limits: limits)
        var frames: [Frame] = []
        while let frame = try reader.read() {
            frames.append(frame)
            if frame.isEof { break }
        }

        // 10 bytes / 5 max_chunk = 2 chunks
        XCTAssertEqual(frames.count, 2, "Must produce 2 chunks")
        for (i, frame) in frames.enumerated() {
            XCTAssertEqual(frame.seq, 0, "chunk \(i) must have seq=0 (SeqAssigner assigns at output stage)")
            XCTAssertEqual(frame.chunkIndex, UInt64(i), "chunk \(i) must have chunk_index=\(i)")
        }
    }

    // TEST472: Handshake negotiates max_reorder_buffer (minimum of both sides)
    @available(macOS 10.15.4, iOS 13.4, *)
    func testHandshakeNegotiatesReorderBuffer() throws {
        // Simulate plugin sending HELLO with max_reorder_buffer=32
        let pluginLimits = Limits(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK, maxReorderBuffer: 32)
        let manifestJSON = "{\"name\":\"test\",\"version\":\"1.0\",\"caps\":[]}"
        let manifestData = manifestJSON.data(using: .utf8)!

        // Write plugin's HELLO with manifest to a pipe
        let pipe1 = Pipe()
        let pluginHello = Frame.helloWithManifest(limits: pluginLimits, manifest: manifestData)
        try writeFrame(pluginHello, to: pipe1.fileHandleForWriting, limits: pluginLimits)
        pipe1.fileHandleForWriting.closeFile()

        // Write host's HELLO to a pipe (default: max_reorder_buffer=64)
        let pipe2 = Pipe()
        let hostLimits = Limits() // Default has max_reorder_buffer=64
        let hostHello = Frame.hello(limits: hostLimits)
        try writeFrame(hostHello, to: pipe2.fileHandleForWriting, limits: hostLimits)
        pipe2.fileHandleForWriting.closeFile()

        // Host reads plugin's HELLO
        let theirFrame = try readFrame(from: pipe1.fileHandleForReading, limits: Limits())
        XCTAssertNotNil(theirFrame)
        let theirReorder = theirFrame!.helloMaxReorderBuffer!
        XCTAssertEqual(theirReorder, 32)
        let negotiated = min(DEFAULT_MAX_REORDER_BUFFER, theirReorder)
        XCTAssertEqual(negotiated, 32, "Must pick minimum (32 < 64)")

        // Plugin reads host's HELLO
        let hostFrame = try readFrame(from: pipe2.fileHandleForReading, limits: Limits())
        XCTAssertNotNil(hostFrame)
        let hostReorder = hostFrame!.helloMaxReorderBuffer!
        XCTAssertEqual(hostReorder, DEFAULT_MAX_REORDER_BUFFER)
    }
}
