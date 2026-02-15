/// Tests for RelaySwitch — TEST426-TEST435

import XCTest
import Foundation
@testable import Bifaci
import CapNs

@available(macOS 10.15.4, iOS 13.4, *)
final class CborRelaySwitchTests: XCTestCase {

    // Helper to send RelayNotify
    private func sendNotify(writer: FrameWriter, manifestJSON: [String: Any], limits: Limits) throws {
        let manifestBytes = try JSONSerialization.data(withJSONObject: manifestJSON)
        let notify = Frame.relayNotify(
            manifest: manifestBytes,
            limits: limits
        )
        try writer.write(notify)
    }

    // TEST426: Single master REQ/response routing
    func test_426_single_master_req_response() throws {
        // Create socket pairs for master
        let engineSocks = FileHandle.socketPair()
        let slaveSocks = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        // Spawn mock slave that sends RelayNotify then echoes frames
        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks.read, limits: Limits())
            let writer = FrameWriter(handle: slaveSocks.write, limits: Limits())

            let manifest: [String: Any] = ["capabilities": ["cap:in=media:;out=media:"]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done.signal()

            // Read one REQ and send response
            if let frame = try? reader.read(), frame?.frameType == .req {
                let response = Frame.end(id: frame!.id, payload: Data([42]))
                try! writer.write(response)
            }
        }

        // Wait for RelayNotify
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        // Create RelaySwitch
        let switch_ = try RelaySwitch(sockets: [SocketPair(read: engineSocks.read, write: engineSocks.write)])

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
    func test_427_multi_master_cap_routing() throws {
        // Create two masters with different caps
        let engineSocks1 = FileHandle.socketPair()
        let slaveSocks1 = FileHandle.socketPair()
        let engineSocks2 = FileHandle.socketPair()
        let slaveSocks2 = FileHandle.socketPair()

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        // Spawn slave 1 (echo cap)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks1.read, limits: Limits())
            let writer = FrameWriter(handle: slaveSocks1.write, limits: Limits())

            let manifest: [String: Any] = ["capabilities": ["cap:in=media:;out=media:"]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done1.signal()

            while let frame = try? reader.read(), frame != nil {
                if frame!.frameType == .req {
                    let response = Frame.end(id: frame!.id, payload: Data([1]))
                    try! writer.write(response)
                }
            }
        }

        // Spawn slave 2 (double cap)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks2.read, limits: Limits())
            let writer = FrameWriter(handle: slaveSocks2.write, limits: Limits())

            let manifest: [String: Any] = ["capabilities": ["cap:in=\"media:void\";op=double;out=\"media:void\""]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done2.signal()

            while let frame = try? reader.read(), frame != nil {
                if frame!.frameType == .req {
                    let response = Frame.end(id: frame!.id, payload: Data([2]))
                    try! writer.write(response)
                }
            }
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(read: engineSocks1.read, write: engineSocks1.write),
            SocketPair(read: engineSocks2.read, write: engineSocks2.write),
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
    func test_428_unknown_cap_returns_error() throws {
        let engineSocks = FileHandle.socketPair()
        let slaveSocks = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks.write)

            let manifest: [String: Any] = ["capabilities": ["cap:in=media:;out=media:"]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done.signal()
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [CborSocketPair(read: engineSocks.read, write: engineSocks.write)])

        // Send REQ for unknown cap
        let req = Frame.req(
            id: MessageId(1),
            cap: "cap:in=\"media:void\";op=unknown;out=\"media:void\"",
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
    func test_429_find_master_for_cap() throws {
        // Create two masters with different caps
        let engineSocks1 = FileHandle.socketPair()
        let slaveSocks1 = FileHandle.socketPair()
        let engineSocks2 = FileHandle.socketPair()
        let slaveSocks2 = FileHandle.socketPair()

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks1.write)
            let manifest: [String: Any] = ["capabilities": ["cap:in=media:;out=media:"]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done1.signal()
        }

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks2.write)
            let manifest: [String: Any] = ["capabilities": ["cap:in=\"media:void\";op=double;out=\"media:void\""]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done2.signal()
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            CborSocketPair(read: engineSocks1.read, write: engineSocks1.write),
            CborSocketPair(read: engineSocks2.read, write: engineSocks2.write),
        ])

        // Verify aggregate capabilities
        let caps = try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String: Any]
        let capList = caps["capabilities"] as! [String]
        XCTAssertEqual(capList.count, 2)
    }

    // TEST430: Tie-breaking (same cap on multiple masters - first match wins, routing is consistent)
    func test_430_tie_breaking_same_cap_multiple_masters() throws {
        // Create two masters with the SAME cap
        let engineSocks1 = FileHandle.socketPair()
        let slaveSocks1 = FileHandle.socketPair()
        let engineSocks2 = FileHandle.socketPair()
        let slaveSocks2 = FileHandle.socketPair()

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        let sameCap = "cap:in=media:;out=media:"

        // Spawn slave 1
        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks1.read)
            let writer = FrameWriter(handle: slaveSocks1.write)
            let manifest: [String: Any] = ["capabilities": [sameCap]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done1.signal()

            // Echo with marker 1
            while let frame = try? reader.read(), frame != nil {
                if frame!.frameType == .req {
                    let response = Frame.end(id: frame!.id, payload: Data([1]))
                    try! writer.write(response)
                }
            }
        }

        // Spawn slave 2
        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks2.read)
            let writer = FrameWriter(handle: slaveSocks2.write)
            let manifest: [String: Any] = ["capabilities": [sameCap]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done2.signal()

            // Echo with marker 2 (should never be called if routing is consistent)
            while let frame = try? reader.read(), frame != nil {
                if frame!.frameType == .req {
                    let response = Frame.end(id: frame!.id, payload: Data([2]))
                    try! writer.write(response)
                }
            }
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            CborSocketPair(read: engineSocks1.read, write: engineSocks1.write),
            CborSocketPair(read: engineSocks2.read, write: engineSocks2.write),
        ])

        // Send first request - should go to master 0 (first match)
        let req1 = Frame.req(id: MessageId(1), cap: sameCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req1)

        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([1]))  // From master 0

        // Send second request - should ALSO go to master 0 (consistent routing)
        let req2 = Frame.req(id: MessageId(2), cap: sameCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req2)

        let resp2 = try switch_.readFromMasters()
        XCTAssertEqual(resp2?.payload, Data([1]))  // Also from master 0
    }

    // TEST431: Continuation frame routing (CHUNK, END follow REQ)
    func test_431_continuation_frame_routing() throws {
        let engineSocks = FileHandle.socketPair()
        let slaveSocks = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks.read)
            let writer = FrameWriter(handle: slaveSocks.write)

            let manifest: [String: Any] = ["capabilities": ["cap:in=\"media:void\";op=test;out=\"media:void\""]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done.signal()

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

            // Send response
            let response = Frame.end(id: req.id, payload: Data([42]))
            try! writer.write(response)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [CborSocketPair(read: engineSocks.read, write: engineSocks.write)])

        let reqId = MessageId(1)

        // Send REQ
        let req = Frame.req(id: reqId, cap: "cap:in=\"media:void\";op=test;out=\"media:void\"", payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req)

        // Send CHUNK continuation
        let chunk = Frame.chunk(id: reqId, streamId: "stream1", seq: 0, payload: Data([1, 2, 3]))
        try switch_.sendToMaster(chunk)

        // Send END continuation
        let end = Frame.end(id: reqId, payload: nil)
        try switch_.sendToMaster(end)

        // Read response
        let response = try switch_.readFromMasters()
        XCTAssertEqual(response?.frameType, .end)
        XCTAssertEqual(response?.payload, Data([42]))
    }

    // TEST432: Empty masters list returns error
    func test_432_empty_masters_list_error() throws {
        XCTAssertThrowsError(try RelaySwitch(sockets: [])) { error in
            guard case RelaySwitchError.protocolError(let msg) = error else {
                XCTFail("Expected protocolError")
                return
            }
            XCTAssertTrue(msg.contains("at least one master"))
        }
    }

    // TEST433: Capability aggregation deduplicates caps
    func test_433_capability_aggregation_deduplicates() throws {
        // Create two masters with overlapping caps
        let engineSocks1 = FileHandle.socketPair()
        let slaveSocks1 = FileHandle.socketPair()
        let engineSocks2 = FileHandle.socketPair()
        let slaveSocks2 = FileHandle.socketPair()

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks1.write)
            let manifest: [String: Any] = [
                "capabilities": [
                    "cap:in=media:;out=media:",
                    "cap:in=\"media:void\";op=double;out=\"media:void\""
                ]
            ]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done1.signal()
        }

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks2.write)
            let manifest: [String: Any] = [
                "capabilities": [
                    "cap:in=media:;out=media:",  // Duplicate
                    "cap:in=\"media:void\";op=triple;out=\"media:void\""
                ]
            ]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done2.signal()
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            CborSocketPair(read: engineSocks1.read, write: engineSocks1.write),
            CborSocketPair(read: engineSocks2.read, write: engineSocks2.write),
        ])

        let caps = try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String: Any]
        let capList = (caps["capabilities"] as! [String]).sorted()

        // Should have 3 unique caps (echo appears twice but deduplicated)
        XCTAssertEqual(capList.count, 3)
        XCTAssertTrue(capList.contains("cap:in=\"media:void\";op=double;out=\"media:void\""))
        XCTAssertTrue(capList.contains("cap:in=media:;out=media:"))
        XCTAssertTrue(capList.contains("cap:in=\"media:void\";op=triple;out=\"media:void\""))
    }

    // TEST434: Limits negotiation takes minimum
    func test_434_limits_negotiation_minimum() throws {
        let engineSocks1 = FileHandle.socketPair()
        let slaveSocks1 = FileHandle.socketPair()
        let engineSocks2 = FileHandle.socketPair()
        let slaveSocks2 = FileHandle.socketPair()

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks1.write)
            let manifest: [String: Any] = ["capabilities": []]
            let limits1 = Limits(maxFrame: 1_000_000, maxChunk: 100_000)
            try! self.sendNotify(writer: writer, manifest: manifest, limits: limits1)
            done1.signal()
        }

        DispatchQueue.global().async {
            let writer = FrameWriter(handle: slaveSocks2.write)
            let manifest: [String: Any] = ["capabilities": []]
            let limits2 = Limits(maxFrame: 2_000_000, maxChunk: 50_000)  // Larger frame, smaller chunk
            try! self.sendNotify(writer: writer, manifest: manifest, limits: limits2)
            done2.signal()
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            CborSocketPair(read: engineSocks1.read, write: engineSocks1.write),
            CborSocketPair(read: engineSocks2.read, write: engineSocks2.write),
        ])

        // Should take minimum of each limit
        XCTAssertEqual(switch_.limits().maxFrame, 1_000_000)  // min(1M, 2M)
        XCTAssertEqual(switch_.limits().maxChunk, 50_000)     // min(100K, 50K)
    }

    // TEST435: URN matching (exact vs accepts())
    func test_435_urn_matching_exact_and_accepts() throws {
        let engineSocks = FileHandle.socketPair()
        let slaveSocks = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        // Master advertises a specific cap
        let registeredCap = "cap:in=\"media:text;utf8\";op=process;out=\"media:text;utf8\""

        DispatchQueue.global().async {
            var reader = FrameReader(handle: slaveSocks.read)
            let writer = FrameWriter(handle: slaveSocks.write)
            let manifest: [String: Any] = ["capabilities": [registeredCap]]
            try! self.sendNotify(writer: writer, manifest: manifest, limits: Limits())
            done.signal()

            // Respond to request
            while let frame = try? reader.read(), frame != nil {
                if frame!.frameType == .req {
                    let response = Frame.end(id: frame!.id, payload: Data([42]))
                    try! writer.write(response)
                }
            }
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [CborSocketPair(read: engineSocks.read, write: engineSocks.write)])

        // Exact match should work
        let req1 = Frame.req(id: MessageId(1), cap: registeredCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req1)
        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([42]))

        // More specific request should NOT match less specific registered cap
        // (request is more specific, registered is less specific → no match)
        let req2 = Frame.req(
            id: MessageId(2),
            cap: "cap:in=\"media:text;utf8;normalized\";op=process;out=\"media:text\"",
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
