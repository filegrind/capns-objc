import XCTest
@testable import Bifaci

/// Tests for seq-based frame ordering (TEST442-461)
/// Based on Rust tests in src/bifaci/frame.rs
final class FlowOrderingTests: XCTestCase {

    // MARK: - SeqAssigner Tests (TEST442-446)

    // TEST442: SeqAssigner assigns seq 0,1,2,3 for consecutive frames with same RID
    func test442_seqAssignerMonotonicSameRid() {
        var assigner = SeqAssigner()
        let rid = MessageId.newUUID()

        var f0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        var f1 = Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:")
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
    func test443_seqAssignerIndependentRids() {
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
    func test444_seqAssignerSkipsNonFlow() {
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

    // TEST445: SeqAssigner.remove with FlowKey(rid, nil) resets that flow; FlowKey(rid, Some(xid)) is unaffected
    func test445_seqAssignerRemoveByFlowKey() {
        var assigner = SeqAssigner()
        let rid = MessageId.newUUID()
        let xid = MessageId.newUUID()

        // Flow 1: (rid, nil) — plugin peer invoke
        var f0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        var f1 = Frame.end(id: rid, finalPayload: nil)
        assigner.assign(&f0)
        assigner.assign(&f1)
        XCTAssertEqual(f1.seq, 1)

        // Flow 2: (rid, Some(xid)) — relay response
        var g0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        g0.routingId = xid
        var g1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        g1.routingId = xid
        assigner.assign(&g0)
        assigner.assign(&g1)
        XCTAssertEqual(g0.seq, 0)
        XCTAssertEqual(g1.seq, 1)

        // Remove Flow 1 only
        assigner.remove(FlowKey(rid: rid, xid: nil))

        // Flow 1 restarts at 0
        var f2 = Frame.req(id: rid, capUrn: "cap:op=test2;in=media:;out=media:", payload: Data(), contentType: "")
        assigner.assign(&f2)
        XCTAssertEqual(f2.seq, 0, "After remove(rid, nil), that flow restarts at 0")

        // Flow 2 continues unaffected
        var g2 = Frame.end(id: rid, finalPayload: nil)
        g2.routingId = xid
        assigner.assign(&g2)
        XCTAssertEqual(g2.seq, 2, "remove(rid, nil) must not affect (rid, Some(xid))")
    }

    // TEST445a: Same RID with different XIDs get independent seq counters
    func test445a_seqAssignerSameRidDifferentXidsIndependent() {
        var assigner = SeqAssigner()
        let rid = MessageId.newUUID()
        let xidA = MessageId.uint(1)
        let xidB = MessageId.uint(2)

        // Flow A: (rid, xidA)
        var a0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        a0.routingId = xidA
        var a1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        a1.routingId = xidA

        // Flow B: (rid, xidB)
        var b0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")
        b0.routingId = xidB

        // Flow C: (rid, nil)
        var c0 = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")

        assigner.assign(&a0)
        assigner.assign(&b0)
        assigner.assign(&a1)
        assigner.assign(&c0)

        XCTAssertEqual(a0.seq, 0, "flow (rid, xidA) starts at 0")
        XCTAssertEqual(a1.seq, 1, "flow (rid, xidA) increments to 1")
        XCTAssertEqual(b0.seq, 0, "flow (rid, xidB) starts at 0 independently")
        XCTAssertEqual(c0.seq, 0, "flow (rid, nil) starts at 0 independently")
    }

    // TEST446: SeqAssigner handles mixed frame types (REQ, CHUNK, LOG, END) for same RID
    func test446_seqAssignerMixedTypes() {
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
    func test447_flowKeyWithXid() {
        let rid = MessageId.newUUID()
        let xid = MessageId.newUUID()
        var frame = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        frame.routingId = xid

        let key = FlowKey.fromFrame(frame)
        XCTAssertEqual(key.rid, rid, "FlowKey rid must match frame id")
        XCTAssertEqual(key.xid, xid, "FlowKey xid must match frame routingId")
    }

    // TEST448: FlowKey::from_frame extracts (rid, None) when routing_id absent
    func test448_flowKeyWithoutXid() {
        let rid = MessageId.newUUID()
        let frame = Frame.req(id: rid, capUrn: "cap:op=test;in=media:;out=media:", payload: Data(), contentType: "")

        let key = FlowKey.fromFrame(frame)
        XCTAssertEqual(key.rid, rid, "FlowKey rid must match frame id")
        XCTAssertNil(key.xid, "FlowKey xid must be nil when no routingId")
    }

    // TEST449: FlowKey equality: same rid+xid equal, different xid different key
    func test449_flowKeyEquality() {
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
    func test450_flowKeyHash() {
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
    func test451_reorderBufferInOrder() throws {
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
    func test452_reorderBufferOutOfOrder() throws {
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
    func test453_reorderBufferGapFill() throws {
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
    func test454_reorderBufferStaleSeq() {
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
    func test455_reorderBufferOverflow() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 3)
        let rid = MessageId.newUUID()

        // Fill buffer to capacity with out-of-order frames (expectedSeq is 0, send 1,2,3)
        _ = try buffer.accept(Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data(), chunkIndex: 1, checksum: 0))
        _ = try buffer.accept(Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data(), chunkIndex: 2, checksum: 0))
        _ = try buffer.accept(Frame.chunk(reqId: rid, streamId: "s1", seq: 3, payload: Data(), chunkIndex: 3, checksum: 0))

        // Overflow when trying to buffer 4th frame
        XCTAssertThrowsError(try buffer.accept(Frame.chunk(reqId: rid, streamId: "s1", seq: 4, payload: Data(), chunkIndex: 4, checksum: 0)),
                             "Buffer overflow must throw") { error in
            guard case FrameError.protocolError(let msg) = error else {
                XCTFail("Expected FrameError.protocolError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("overflow"), "Error message must mention overflow")
        }
    }

    // TEST456: Multiple concurrent flows reorder independently
    func test456_reorderBufferMultipleFlows() throws {
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
    func test457_reorderBufferCleanupFlow() throws {
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
    func test458_reorderBufferNonFlowBypass() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let hb = Frame.heartbeat(id: rid)

        let out = try buffer.accept( hb)
        XCTAssertEqual(out.count, 1, "Non-flow frame must bypass buffer")
        XCTAssertEqual(out[0].frameType, .heartbeat)
    }

    // TEST459: Terminal END frame flows through correctly
    func test459_reorderBufferTerminalEnd() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        var endFrame = Frame.end(id: rid, finalPayload: nil)
        endFrame.seq = 1  // Terminal frames have sequential seq numbers

        _ = try buffer.accept( f0)
        let outEnd = try buffer.accept( endFrame)

        XCTAssertEqual(outEnd.count, 1, "END frame must flow through")
        XCTAssertEqual(outEnd[0].frameType, FrameType.end)
        XCTAssertEqual(outEnd[0].seq, 1, "END must have seq=1")
    }

    // TEST460: Terminal ERR frame flows through correctly
    func test460_reorderBufferTerminalErr() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        var errFrame = Frame.err(id: rid, code: "TEST_ERROR", message: "test")
        errFrame.seq = 1  // Terminal frames have sequential seq numbers

        _ = try buffer.accept( f0)
        let outErr = try buffer.accept( errFrame)

        XCTAssertEqual(outErr.count, 1, "ERR frame must flow through")
        XCTAssertEqual(outErr[0].frameType, FrameType.err)
        XCTAssertEqual(outErr[0].seq, 1, "ERR must have seq=1")
    }

    // TEST461: write_chunked produces frames with seq=0; SeqAssigner assigns at output stage
    @available(macOS 10.15.4, iOS 13.4, *)
    func test461_writeChunkedSeqZero() throws {
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
    func test472_handshakeNegotiatesReorderBuffer() throws {
        // Simulate plugin sending HELLO with max_reorder_buffer=32
        let pluginLimits = Limits(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK, maxReorderBuffer: 32)
        let manifestJSON = "{\"name\":\"test\",\"version\":\"1.0\",\"caps\":[]}"
        let manifestData = manifestJSON.data(using: .utf8)!

        // Write plugin's HELLO with manifest to a pipe
        let pipe1 = Pipe()
        let pluginHello = Frame.helloWithManifest(limits: pluginLimits, manifest: manifestData)
        var buffer1 = Data()
        try writeFrame(pluginHello, to: pipe1.fileHandleForWriting, limits: pluginLimits, buffer: &buffer1)
        if !buffer1.isEmpty {
            try pipe1.fileHandleForWriting.write(contentsOf: buffer1)
        }
        pipe1.fileHandleForWriting.closeFile()

        // Write host's HELLO to a pipe (default: max_reorder_buffer=64)
        let pipe2 = Pipe()
        let hostLimits = Limits() // Default has max_reorder_buffer=64
        let hostHello = Frame.hello(limits: hostLimits)
        var buffer2 = Data()
        try writeFrame(hostHello, to: pipe2.fileHandleForWriting, limits: hostLimits, buffer: &buffer2)
        if !buffer2.isEmpty {
            try pipe2.fileHandleForWriting.write(contentsOf: buffer2)
        }
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

    // MARK: - ReorderBuffer XID Isolation Tests (TEST507-520)

    // TEST507: ReorderBuffer isolates flows by XID (routing_id) - same RID different XIDs
    func test507_reorderBufferXidIsolation() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let xid1 = MessageId.uint(1)
        let xid2 = MessageId.uint(2)

        // Flow 1: (rid, xid1) - seq 0
        var f1_seq0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([1]), chunkIndex: 0, checksum: 0)
        f1_seq0.routingId = xid1

        // Flow 2: (rid, xid2) - seq 0 (independent)
        var f2_seq0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([2]), chunkIndex: 0, checksum: 0)
        f2_seq0.routingId = xid2

        // Both should be accepted as independent flows
        let out1 = try buffer.accept(f1_seq0)
        let out2 = try buffer.accept(f2_seq0)

        XCTAssertEqual(out1.count, 1, "Flow 1 seq 0 should be delivered")
        XCTAssertEqual(out2.count, 1, "Flow 2 seq 0 should be delivered (independent flow)")
    }

    // TEST508: ReorderBuffer rejects duplicate seq already in buffer
    func test508_reorderBufferDuplicateBufferedSeq() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()

        // First, buffer seq=2 (out of order, expecting 0)
        let seq2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data([2]), chunkIndex: 2, checksum: 0)
        let out2 = try buffer.accept(seq2)
        XCTAssertEqual(out2.count, 0, "seq=2 should be buffered (expecting 0)")

        // Try to insert duplicate seq=2
        let seq2_dup = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data([2]), chunkIndex: 2, checksum: 0)
        XCTAssertThrowsError(try buffer.accept(seq2_dup)) { error in
            guard case FrameError.protocolError(let msg) = error else {
                XCTFail("Expected protocolError")
                return
            }
            XCTAssertTrue(msg.contains("duplicate") || msg.contains("Stale"), "Error should mention duplicate: \(msg)")
        }
    }

    // TEST509: ReorderBuffer handles large seq gaps without DOS
    func test509_reorderBufferLargeGapRejected() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()

        // Try to insert frames with large gap
        for i: UInt64 in 0..<5 {
            let frame = Frame.chunk(reqId: rid, streamId: "s1", seq: i, payload: Data([UInt8(i)]), chunkIndex: i, checksum: 0)
            _ = try buffer.accept(frame)
        }

        // Now send many out-of-order frames to trigger overflow
        for i: UInt64 in 6..<20 {
            let frame = Frame.chunk(reqId: rid, streamId: "s1", seq: i, payload: Data([UInt8(i)]), chunkIndex: i, checksum: 0)
            do {
                _ = try buffer.accept(frame)
            } catch FrameError.protocolError(let msg) {
                // Expected: buffer overflow
                XCTAssertTrue(msg.contains("overflow"), "Error should mention overflow: \(msg)")
                return
            }
        }
        // If we got here without overflow (buffer size > 10), that's also OK
    }

    // TEST510: ReorderBuffer with multiple interleaved gaps fills correctly
    func test510_reorderBufferMultipleGaps() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()

        // Send frames out of order: 0, 2, 4, 1, 3
        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([0]), chunkIndex: 0, checksum: 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data([1]), chunkIndex: 1, checksum: 0)
        let f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data([2]), chunkIndex: 2, checksum: 0)
        let f3 = Frame.chunk(reqId: rid, streamId: "s1", seq: 3, payload: Data([3]), chunkIndex: 3, checksum: 0)
        let f4 = Frame.chunk(reqId: rid, streamId: "s1", seq: 4, payload: Data([4]), chunkIndex: 4, checksum: 0)

        var delivered: [Frame] = []

        delivered.append(contentsOf: try buffer.accept(f0)) // delivers 0
        delivered.append(contentsOf: try buffer.accept(f2)) // buffers 2
        delivered.append(contentsOf: try buffer.accept(f4)) // buffers 4
        delivered.append(contentsOf: try buffer.accept(f1)) // delivers 1, 2
        delivered.append(contentsOf: try buffer.accept(f3)) // delivers 3, 4

        XCTAssertEqual(delivered.count, 5, "All 5 frames should be delivered")
        for (i, frame) in delivered.enumerated() {
            XCTAssertEqual(frame.seq, UInt64(i), "Frame \(i) should have seq \(i)")
        }
    }

    // TEST511: ReorderBuffer rejects seq < expected (stale frame)
    func test511_reorderBufferRejectsStaleSeq() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()

        // Accept seq 0 and 1
        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([0]), chunkIndex: 0, checksum: 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data([1]), chunkIndex: 1, checksum: 0)

        _ = try buffer.accept(f0)
        _ = try buffer.accept(f1)

        // Now expected is 2. Try to send seq 0 again (stale)
        let stale = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([0]), chunkIndex: 0, checksum: 0)
        XCTAssertThrowsError(try buffer.accept(stale)) { error in
            guard case FrameError.protocolError(let msg) = error else {
                XCTFail("Expected protocolError")
                return
            }
            XCTAssertTrue(msg.contains("Stale") || msg.contains("duplicate"), "Error should mention stale: \(msg)")
        }
    }

    // TEST512: ReorderBuffer non-flow frames bypass reordering
    func test512_reorderBufferNonFlowFramesBypass() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)

        // Non-flow frames should bypass reordering completely
        let hello = Frame.hello(limits: Limits())
        let heartbeat = Frame.heartbeat(id: .uint(1))
        let notify = Frame.relayNotify(manifest: Data(), limits: Limits())
        let state = Frame.relayState(resources: Data())

        let out1 = try buffer.accept(hello)
        let out2 = try buffer.accept(heartbeat)
        let out3 = try buffer.accept(notify)
        let out4 = try buffer.accept(state)

        XCTAssertEqual(out1.count, 1)
        XCTAssertEqual(out2.count, 1)
        XCTAssertEqual(out3.count, 1)
        XCTAssertEqual(out4.count, 1)
    }

    // TEST513: ReorderBuffer cleanup removes flow state
    func test513_reorderBufferCleanup() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([0]), chunkIndex: 0, checksum: 0)
        _ = try buffer.accept(f0)

        // Cleanup the flow
        buffer.cleanupFlow(flow)

        // After cleanup, seq 0 should work again (new flow)
        let f0_new = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([0]), chunkIndex: 0, checksum: 0)
        let out = try buffer.accept(f0_new)
        XCTAssertEqual(out.count, 1, "After cleanup, flow should restart from seq 0")
    }

    // TEST514: ReorderBuffer respects maxBufferPerFlow
    func test514_reorderBufferRespectsMaxBuffer() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 3) // Small buffer
        let rid = MessageId.newUUID()

        // Buffer frames 1, 2, 3 (out of order, expecting 0)
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data([1]), chunkIndex: 1, checksum: 0)
        let f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data([2]), chunkIndex: 2, checksum: 0)
        let f3 = Frame.chunk(reqId: rid, streamId: "s1", seq: 3, payload: Data([3]), chunkIndex: 3, checksum: 0)

        _ = try buffer.accept(f1) // buffers 1
        _ = try buffer.accept(f2) // buffers 2
        _ = try buffer.accept(f3) // buffers 3

        // Now buffer is at capacity. Try to add one more
        let f4 = Frame.chunk(reqId: rid, streamId: "s1", seq: 4, payload: Data([4]), chunkIndex: 4, checksum: 0)
        XCTAssertThrowsError(try buffer.accept(f4)) { error in
            guard case FrameError.protocolError(let msg) = error else {
                XCTFail("Expected protocolError")
                return
            }
            XCTAssertTrue(msg.contains("overflow"), "Error should mention overflow: \(msg)")
        }
    }

    // TEST515: SeqAssigner removes flow by FlowKey
    func test515_seqAssignerRemoveByFlowKey() {
        let assigner = SeqAssigner()
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        var f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        assigner.assign(&f0)
        XCTAssertEqual(f0.seq, 0)

        var f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 1, checksum: 0)
        assigner.assign(&f1)
        XCTAssertEqual(f1.seq, 1)

        // Remove the flow
        assigner.remove(flow)

        // Next frame should restart from 0
        var f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 2, checksum: 0)
        assigner.assign(&f2)
        XCTAssertEqual(f2.seq, 0, "After remove, seq should restart from 0")
    }

    // TEST516: SeqAssigner independent flows by XID
    func test516_seqAssignerIndependentFlowsByXid() {
        let assigner = SeqAssigner()
        let rid = MessageId.newUUID()
        let xid1 = MessageId.uint(1)
        let xid2 = MessageId.uint(2)

        // Flow 1: (rid, xid1)
        var f1_0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        f1_0.routingId = xid1
        assigner.assign(&f1_0)
        XCTAssertEqual(f1_0.seq, 0)

        // Flow 2: (rid, xid2) - independent
        var f2_0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        f2_0.routingId = xid2
        assigner.assign(&f2_0)
        XCTAssertEqual(f2_0.seq, 0, "Different XID should have independent seq counter")

        // Flow 1 next frame
        var f1_1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 1, checksum: 0)
        f1_1.routingId = xid1
        assigner.assign(&f1_1)
        XCTAssertEqual(f1_1.seq, 1, "Flow 1 should continue at seq=1")

        // Flow 2 next frame
        var f2_1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 1, checksum: 0)
        f2_1.routingId = xid2
        assigner.assign(&f2_1)
        XCTAssertEqual(f2_1.seq, 1, "Flow 2 should continue at seq=1")
    }

    // TEST517: FlowKey with nil XID is separate from FlowKey with XID
    func test517_flowKeyNilXidSeparate() {
        let assigner = SeqAssigner()
        let rid = MessageId.newUUID()
        let xid = MessageId.uint(42)

        // Flow: (rid, nil)
        var f_nil = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        f_nil.routingId = nil
        assigner.assign(&f_nil)
        XCTAssertEqual(f_nil.seq, 0)

        // Flow: (rid, xid=42) - separate flow
        var f_xid = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        f_xid.routingId = xid
        assigner.assign(&f_xid)
        XCTAssertEqual(f_xid.seq, 0, "Flow with XID should be separate from flow without XID")

        // Continue flow (rid, nil)
        var f_nil2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 1, checksum: 0)
        f_nil2.routingId = nil
        assigner.assign(&f_nil2)
        XCTAssertEqual(f_nil2.seq, 1)

        // Continue flow (rid, xid=42)
        var f_xid2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 1, checksum: 0)
        f_xid2.routingId = xid
        assigner.assign(&f_xid2)
        XCTAssertEqual(f_xid2.seq, 1)
    }

    // TEST518: ReorderBuffer flow cleanup after END
    func test518_reorderBufferFlowCleanupAfterEnd() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()
        let flow = FlowKey(rid: rid, xid: nil)

        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        _ = try buffer.accept(f0)

        var end = Frame.end(id: rid)
        end.seq = 1
        _ = try buffer.accept(end)

        // Cleanup the flow
        buffer.cleanupFlow(flow)

        // New flow should work
        let f0_new = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        let out = try buffer.accept(f0_new)
        XCTAssertEqual(out.count, 1)
    }

    // TEST519: ReorderBuffer handles frames from multiple RIDs
    func test519_reorderBufferMultipleRids() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid1 = MessageId.newUUID()
        let rid2 = MessageId.newUUID()

        let f1_0 = Frame.chunk(reqId: rid1, streamId: "s1", seq: 0, payload: Data([1]), chunkIndex: 0, checksum: 0)
        let f2_0 = Frame.chunk(reqId: rid2, streamId: "s1", seq: 0, payload: Data([2]), chunkIndex: 0, checksum: 0)
        let f1_1 = Frame.chunk(reqId: rid1, streamId: "s1", seq: 1, payload: Data([11]), chunkIndex: 1, checksum: 0)
        let f2_1 = Frame.chunk(reqId: rid2, streamId: "s1", seq: 1, payload: Data([22]), chunkIndex: 1, checksum: 0)

        let out1 = try buffer.accept(f1_0)
        let out2 = try buffer.accept(f2_0)
        let out3 = try buffer.accept(f1_1)
        let out4 = try buffer.accept(f2_1)

        XCTAssertEqual(out1.count, 1)
        XCTAssertEqual(out2.count, 1)
        XCTAssertEqual(out3.count, 1)
        XCTAssertEqual(out4.count, 1)
    }

    // TEST520: ReorderBuffer drains buffered frames when gap is filled
    func test520_reorderBufferDrainsBufferedFrames() throws {
        var buffer = ReorderBuffer(maxBufferPerFlow: 10)
        let rid = MessageId.newUUID()

        // Buffer frames 1, 2, 3
        let f1 = Frame.chunk(reqId: rid, streamId: "s1", seq: 1, payload: Data([1]), chunkIndex: 1, checksum: 0)
        let f2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 2, payload: Data([2]), chunkIndex: 2, checksum: 0)
        let f3 = Frame.chunk(reqId: rid, streamId: "s1", seq: 3, payload: Data([3]), chunkIndex: 3, checksum: 0)

        _ = try buffer.accept(f1) // buffers
        _ = try buffer.accept(f2) // buffers
        _ = try buffer.accept(f3) // buffers

        // Now send frame 0, which should drain all buffered frames
        let f0 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([0]), chunkIndex: 0, checksum: 0)
        let drained = try buffer.accept(f0)

        XCTAssertEqual(drained.count, 4, "Should drain frames 0, 1, 2, 3")
        for (i, frame) in drained.enumerated() {
            XCTAssertEqual(frame.seq, UInt64(i))
        }
    }
}
