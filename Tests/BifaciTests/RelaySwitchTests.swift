/// Tests for RelaySwitch — TEST426-TEST435

import XCTest
import Foundation
@testable import Bifaci
import CapNs

@available(macOS 10.15.4, iOS 13.4, *)
final class CborRelaySwitchTests: XCTestCase {

    // Helper to send RelayNotify (manifest is a JSON array of capability URN strings)
    private func sendNotify(writer: FrameWriter, capabilities: [String], limits: Limits) throws {
        let manifestBytes = try JSONSerialization.data(withJSONObject: capabilities)
        let notify = Frame.relayNotify(
            manifest: manifestBytes,
            limits: limits
        )
        try writer.write(notify)
    }

    // Helper to handle the identity verification protocol that RelaySwitch init performs.
    // RelaySwitch sends: REQ + STREAM_START + CHUNK(nonce) + STREAM_END + END
    // This helper reads those frames and echoes back: STREAM_START + CHUNK(nonce) + STREAM_END + END
    private func handleIdentityVerification(reader: FrameReader, writer: FrameWriter) throws {
        var nonce = Data()
        var reqId: MessageId? = nil
        let streamId = "identity-verify"
        while true {
            guard let frame = try reader.read() else { return }
            switch frame.frameType {
            case .req:
                reqId = frame.id
            case .streamStart:
                break
            case .chunk:
                if let p = frame.payload { nonce.append(p) }
            case .streamEnd:
                break
            case .end:
                guard let id = reqId else { return }
                // Echo nonce back: STREAM_START + CHUNK(nonce) + STREAM_END + END
                try writer.write(Frame.streamStart(reqId: id, streamId: streamId, mediaUrn: "media:"))
                let checksum = Frame.computeChecksum(nonce)
                try writer.write(Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum))
                try writer.write(Frame.streamEnd(reqId: id, streamId: streamId, chunkCount: 1))
                try writer.write(Frame.end(id: id))
                return
            default:
                return
            }
        }
    }

    // TEST426: Single master REQ/response routing
    func test426_single_master_req_response() throws {
        // Create socket pairs for master-slave communication
        // engine_read <-> slave_write (one pair)
        // slave_read <-> engine_write (another pair)
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        // Spawn mock slave that sends RelayNotify, handles identity verification, then echoes frames
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read, limits: Limits())  // slave reads from pair2
            let writer = FrameWriter(handle: pair1.write, limits: Limits())  // slave writes to pair1

            let caps: [String] = ["cap:in=media:;out=media:"]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            // Handle identity verification from RelaySwitch init
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Read one REQ and send response (must copy XID from REQ so RelaySwitch routes as response)
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data([42]))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
        }

        // Wait for RelayNotify
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        // Create RelaySwitch with properly connected sockets
        // engine reads from pair1 (where slave writes)
        // engine writes to pair2 (where slave reads)
        let switch_ = try RelaySwitch(sockets: [SocketPair(read: pair1.read, write: pair2.write)])

        // Send REQ
        let req = Frame.req(
            id: MessageId.uint(1),
            capUrn: "cap:in=media:;out=media:",
            payload: Data([1, 2, 3]),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req)

        // Read response
        let response = try switch_.readFromMasters()
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.frameType, .end)
        XCTAssertEqual(response?.id.toString(), MessageId.uint(1).toString())
        XCTAssertEqual(response?.payload, Data([42]))
    }

    // TEST427: Multi-master cap routing
    func test427_multi_master_cap_routing() throws {
        // Create cross-connected socket pairs for two masters
        // Master 1: engine_read1 <-> slave_write1, slave_read1 <-> engine_write1
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        // Master 2: engine_read2 <-> slave_write2, slave_read2 <-> engine_write2
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        // Spawn slave 1 (echo cap)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read, limits: Limits())  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write, limits: Limits())  // slave1 writes to pair1_1

            let caps: [String] = ["cap:in=media:;out=media:"]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            while let frame = try? reader.read() {
                if frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([1]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
        }

        // Spawn slave 2 (double cap)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read, limits: Limits())  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write, limits: Limits())  // slave2 writes to pair2_1

            let caps: [String] = ["cap:in=media:;out=media:", "cap:in=\"media:void\";op=double;out=\"media:void\""]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            while let frame = try? reader.read() {
                if frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([2]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(read: pair1_1.read, write: pair1_2.write),  // engine1 reads from pair1_1, writes to pair1_2
            SocketPair(read: pair2_1.read, write: pair2_2.write),  // engine2 reads from pair2_1, writes to pair2_2
        ])

        // Send REQ for echo cap → routes to master 1
        let req1 = Frame.req(
            id: MessageId.uint(1),
            capUrn: "cap:in=media:;out=media:",
            payload: Data(),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req1)

        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([1]))

        // Send REQ for double cap → routes to master 2
        let req2 = Frame.req(
            id: MessageId.uint(2),
            capUrn: "cap:in=\"media:void\";op=double;out=\"media:void\"",
            payload: Data(),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req2)

        let resp2 = try switch_.readFromMasters()
        XCTAssertEqual(resp2?.payload, Data([2]))
    }

    // TEST428: Unknown cap returns error
    func test428_unknown_cap_returns_error() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)  // slave reads from pair2
            let writer = FrameWriter(handle: pair1.write)  // slave writes to pair1

            let caps: [String] = ["cap:in=media:;out=media:"]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(read: pair1.read, write: pair2.write)])

        // Send REQ for unknown cap
        let req = Frame.req(
            id: MessageId.uint(1),
            capUrn: "cap:in=\"media:void\";op=unknown;out=\"media:void\"",
            payload: Data(),
            contentType: "text/plain"
        )

        XCTAssertThrowsError(try switch_.sendToMaster(req)) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error")
                return
            }
        }
    }

    // TEST429: Cap routing logic (find_master_for_cap)
    func test429_find_master_for_cap() throws {
        // Create cross-connected socket pairs for two masters
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)  // slave1 writes to pair1_1
            let caps: [String] = ["cap:in=media:;out=media:"]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)  // slave2 writes to pair2_1
            let caps: [String] = ["cap:in=media:;out=media:", "cap:in=\"media:void\";op=double;out=\"media:void\""]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(read: pair1_1.read, write: pair1_2.write),  // engine1 reads from pair1_1, writes to pair1_2
            SocketPair(read: pair2_1.read, write: pair2_2.write),  // engine2 reads from pair2_1, writes to pair2_2
        ])

        // Verify aggregate capabilities (returned as JSON array)
        let capList = try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String]
        XCTAssertEqual(capList.count, 2)
    }

    // TEST430: Tie-breaking (same cap on multiple masters - first match wins, routing is consistent)
    func test430_tie_breaking_same_cap_multiple_masters() throws {
        // Create cross-connected socket pairs for two masters with the SAME cap
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        let sameCap = "cap:in=media:;out=media:"

        // Spawn slave 1
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)  // slave1 writes to pair1_1
            let caps: [String] = [sameCap]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Echo with marker 1
            while let frame = try? reader.read() {
                if frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([1]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
        }

        // Spawn slave 2
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)  // slave2 writes to pair2_1
            let caps: [String] = [sameCap]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Echo with marker 2 (should never be called if routing is consistent)
            while let frame = try? reader.read() {
                if frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([2]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(read: pair1_1.read, write: pair1_2.write),  // engine1 reads from pair1_1, writes to pair1_2
            SocketPair(read: pair2_1.read, write: pair2_2.write),  // engine2 reads from pair2_1, writes to pair2_2
        ])

        // Send first request - should go to master 0 (first match)
        let req1 = Frame.req(id: MessageId.uint(1), capUrn: sameCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req1)

        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([1]))  // From master 0

        // Send second request - should ALSO go to master 0 (consistent routing)
        let req2 = Frame.req(id: MessageId.uint(2), capUrn: sameCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req2)

        let resp2 = try switch_.readFromMasters()
        XCTAssertEqual(resp2?.payload, Data([1]))  // Also from master 0
    }

    // TEST431: Continuation frame routing (CHUNK, END follow REQ)
    func test431_continuation_frame_routing() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)

            let caps: [String] = ["cap:in=media:;out=media:", "cap:in=\"media:void\";op=test;out=\"media:void\""]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Read REQ
            let req = try! reader.read()!
            XCTAssertEqual(req.frameType, .req)

            // Read CHUNK continuation
            let chunk = try! reader.read()!
            XCTAssertEqual(chunk.frameType, .chunk)
            XCTAssertEqual(chunk.id.toString(), req.id.toString())

            // Read END continuation
            let end = try! reader.read()!
            XCTAssertEqual(end.frameType, .end)
            XCTAssertEqual(end.id.toString(), req.id.toString())

            // Send response (copy XID from REQ so RelaySwitch routes as response)
            var response = Frame.end(id: req.id, finalPayload: Data([42]))
            response.routingId = req.routingId
            try! writer.write(response)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(read: pair1.read, write: pair2.write)])

        let reqId = MessageId.uint(1)

        // Send REQ
        let req = Frame.req(id: reqId, capUrn: "cap:in=\"media:void\";op=test;out=\"media:void\"", payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req)

        // Send CHUNK continuation
        let chunkPayload = Data([1, 2, 3])
        let chunk = Frame.chunk(reqId: reqId, streamId: "stream1", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPayload))
        try switch_.sendToMaster(chunk)

        // Send END continuation
        let end = Frame.end(id: reqId)
        try switch_.sendToMaster(end)

        // Read response
        let response = try switch_.readFromMasters()
        XCTAssertEqual(response?.frameType, .end)
        XCTAssertEqual(response?.payload, Data([42]))
    }

    // TEST432: Empty masters list creates empty switch (matching Rust behavior)
    func test432_empty_masters_allowed() throws {
        let sw = try RelaySwitch(sockets: [])

        // Empty switch has no caps
        let capsJson = sw.capabilities()
        XCTAssertEqual(String(data: capsJson, encoding: .utf8), "[]", "empty switch should have empty caps JSON")

        // No handler for any cap — sendToMaster throws noHandler
        XCTAssertThrowsError(try sw.sendToMaster(Frame.req(id: .newUUID(), capUrn: "cap:in=media:;out=media:", payload: Data(), contentType: ""))) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error, got \(error)")
                return
            }
        }
    }

    // TEST433: Capability aggregation deduplicates caps
    func test433_capability_aggregation_deduplicates() throws {
        // Create two masters with overlapping caps
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)
            let caps: [String] = [
                "cap:in=media:;out=media:",
                "cap:in=\"media:void\";op=double;out=\"media:void\""
            ]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)
            let caps: [String] = [
                "cap:in=media:;out=media:",  // Duplicate
                "cap:in=\"media:void\";op=triple;out=\"media:void\""
            ]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(read: pair1_1.read, write: pair1_2.write),
            SocketPair(read: pair2_1.read, write: pair2_2.write),
        ])

        let capList = (try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String]).sorted()

        // Should have 3 unique caps (echo appears twice but deduplicated)
        XCTAssertEqual(capList.count, 3)
        XCTAssertTrue(capList.contains("cap:in=\"media:void\";op=double;out=\"media:void\""))
        XCTAssertTrue(capList.contains("cap:in=media:;out=media:"))
        XCTAssertTrue(capList.contains("cap:in=\"media:void\";op=triple;out=\"media:void\""))
    }

    // TEST434: Limits negotiation takes minimum
    func test434_limits_negotiation_minimum() throws {
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)
            let caps: [String] = ["cap:in=media:;out=media:"]
            let limits1 = Limits(maxFrame: 1_000_000, maxChunk: 100_000)
            try! self.sendNotify(writer: writer, capabilities: caps, limits: limits1)
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)
            let caps: [String] = ["cap:in=media:;out=media:"]
            let limits2 = Limits(maxFrame: 2_000_000, maxChunk: 50_000)  // Larger frame, smaller chunk
            try! self.sendNotify(writer: writer, capabilities: caps, limits: limits2)
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(read: pair1_1.read, write: pair1_2.write),
            SocketPair(read: pair2_1.read, write: pair2_2.write),
        ])

        // Should take minimum of each limit
        XCTAssertEqual(switch_.limits().maxFrame, 1_000_000)  // min(1M, 2M)
        XCTAssertEqual(switch_.limits().maxChunk, 50_000)     // min(100K, 50K)
    }

    // TEST435: URN matching (exact vs accepts())
    func test435_urn_matching_exact_and_accepts() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        // Master advertises a specific cap
        let registeredCap = "cap:in=\"media:text;utf8\";op=process;out=\"media:text;utf8\""

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = ["cap:in=media:;out=media:", registeredCap]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Respond to request
            while let frame = try? reader.read() {
                if frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([42]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(read: pair1.read, write: pair2.write)])

        // Exact match should work
        let req1 = Frame.req(id: MessageId.uint(1), capUrn: registeredCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req1)
        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([42]))

        // More specific request should NOT match less specific registered cap
        // (request is more specific, registered is less specific → no match)
        let req2 = Frame.req(
            id: MessageId.uint(2),
            capUrn: "cap:in=\"media:text;utf8;normalized\";op=process;out=\"media:text\"",
            payload: Data(),
            contentType: "text/plain"
        )
        XCTAssertThrowsError(try switch_.sendToMaster(req2)) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error")
                return
            }
        }
    }
}

// Helper extension for creating socket pairs
extension FileHandle {
    static func socketPair() -> (read: FileHandle, write: FileHandle) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        return (
            read: FileHandle(fileDescriptor: fds[0], closeOnDealloc: true),
            write: FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        )
    }
}
