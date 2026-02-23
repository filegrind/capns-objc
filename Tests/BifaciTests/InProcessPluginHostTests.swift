//
//  InProcessPluginHostTests.swift
//  Tests for InProcessPluginHost
//
//  Mirrors Rust tests from capns/src/bifaci/in_process_host.rs exactly
//  Tests numbered TEST654-TEST660

import XCTest
import Foundation
import SwiftCBOR
@testable import Bifaci
@testable import CapNs

final class InProcessPluginHostTests: XCTestCase {

    // MARK: - Test Helpers

    /// Make a test cap from a URN string
    private func makeTestCap(_ urnStr: String) -> CSCap {
        let urn = try! CSCapUrn.fromString(urnStr)
        return CSCap(urn: urn, title: "test", command: "")
    }

    /// Build a CBOR-encoded chunk payload from raw bytes (matching build_request_frames).
    private func cborBytesPayload(_ data: Data) -> Data {
        return Data(CBOR.byteString([UInt8](data)).encode())
    }

    /// CBOR-decode a response chunk payload to extract raw bytes.
    private func decodeChunkPayload(_ payload: Data) -> Data {
        guard let cbor = try? CBOR.decode([UInt8](payload)) else {
            fatalError("Failed to decode CBOR from payload")
        }
        switch cbor {
        case .byteString(let bytes):
            return Data(bytes)
        case .utf8String(let str):
            return str.data(using: .utf8) ?? Data()
        default:
            fatalError("unexpected CBOR type in response chunk: \(cbor)")
        }
    }

    /// Identity nonce for verification (must match Rust exactly)
    private func identityNonce() -> Data {
        let components: [UInt8] = [
            0x63, 0x61, 0x70, 0x6e, 0x73,  // "capns"
            0x2d,                           // "-"
            0x69, 0x64, 0x65, 0x6e, 0x74,  // "ident"
            0x69, 0x74, 0x79,               // "ity"
            0x2d,                           // "-"
            0x76, 0x65, 0x72, 0x69, 0x66,  // "verif"
            0x79                            // "y"
        ]
        return Data(components)
    }

    // MARK: - Test Handlers

    /// Echo handler: accumulates input, echoes raw bytes back (for TEST654, TEST657, TEST660)
    final class EchoHandler: FrameHandler {
        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                do {
                    let args = try await accumulateInput(inputStream: inputStream)
                    let data = args.flatMap { $0.value }
                    output.emitResponse(mediaUrn: "media:", data: Data(data))
                } catch {
                    output.emitError(code: "ACCUMULATE_ERROR", message: error.localizedDescription)
                }
            }
        }
    }

    /// Fail handler: always returns error (for TEST659)
    final class FailHandler: FrameHandler {
        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                // Drain input
                for await frame in inputStream {
                    if frame.frameType == .end {
                        break
                    }
                }
                output.emitError(code: "PROVIDER_ERROR", message: "provider crashed")
            }
        }
    }

    /// Tagged handler: returns its tag name (for TEST660)
    final class TaggedHandler: FrameHandler {
        let tag: String

        init(tag: String) {
            self.tag = tag
        }

        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                // Drain input
                for await frame in inputStream {
                    if frame.frameType == .end {
                        break
                    }
                }
                output.emitResponse(mediaUrn: "media:text", data: tag.data(using: .utf8)!)
            }
        }
    }

    // MARK: - TEST654: InProcessPluginHost routes REQ to matching handler and returns response

    func test654_routesReqToHandler() throws {
        let capUrn = "cap:in=\"media:text\";op=echo;out=\"media:text\""
        let cap = makeTestCap(capUrn)
        let handlers: [(name: String, caps: [CSCap], handler: FrameHandler)] = [
            ("echo", [cap], EchoHandler())
        ]

        let host = InProcessPluginHost(handlers: handlers)

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        // Run host in background thread
        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // First frame should be RelayNotify with manifest
        let notify = try! reader.read()!
        XCTAssertEqual(notify.frameType, .relayNotify)
        let manifest = notify.relayNotifyManifest!
        let capUrns: [String] = try! JSONDecoder().decode([String].self, from: manifest)
        XCTAssertTrue(capUrns.count >= 2) // identity + echo cap
        XCTAssertEqual(capUrns[0], CSCapIdentity)

        // Send a REQ + STREAM_START + CHUNK (CBOR-encoded) + STREAM_END + END
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        let ss = Frame.streamStart(reqId: rid, streamId: "arg0", mediaUrn: "media:text")
        try! writer.write(ss)

        let payload = cborBytesPayload("hello world".data(using: .utf8)!)
        let checksum = Frame.computeChecksum(payload)
        let chunk = Frame.chunk(reqId: rid, streamId: "arg0", seq: 0, payload: payload, chunkIndex: 0, checksum: checksum)
        try! writer.write(chunk)

        let se = Frame.streamEnd(reqId: rid, streamId: "arg0", chunkCount: 1)
        try! writer.write(se)

        let end = Frame.end(id: rid)
        try! writer.write(end)

        // Read response: STREAM_START + CHUNK (CBOR-encoded) + STREAM_END + END
        let respSs = try! reader.read()!
        XCTAssertEqual(respSs.frameType, .streamStart)
        XCTAssertEqual(respSs.id, rid)
        XCTAssertEqual(respSs.streamId, "result")

        let respChunk = try! reader.read()!
        XCTAssertEqual(respChunk.frameType, .chunk)
        let respData = decodeChunkPayload(respChunk.payload!)
        XCTAssertEqual(respData, "hello world".data(using: .utf8)!)

        let respSe = try! reader.read()!
        XCTAssertEqual(respSe.frameType, .streamEnd)

        let respEnd = try! reader.read()!
        XCTAssertEqual(respEnd.frameType, .end)

        // Cleanup
        testWrite.closeFile()
        testRead.closeFile()
        // Host thread will exit when sockets close
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - TEST655: InProcessPluginHost handles identity verification (echo nonce)

    func test655_identityVerification() throws {
        let host = InProcessPluginHost(handlers: [])

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        // Send identity verification
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: CSCapIdentity, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(0)
        try! writer.write(req)

        // Send nonce via stream (raw bytes, NOT CBOR-encoded for identity)
        let nonce = identityNonce()
        let ss = Frame.streamStart(reqId: rid, streamId: "identity-verify", mediaUrn: "media:")
        try! writer.write(ss)

        let checksum = Frame.computeChecksum(nonce)
        let chunk = Frame.chunk(reqId: rid, streamId: "identity-verify", seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
        try! writer.write(chunk)

        let se = Frame.streamEnd(reqId: rid, streamId: "identity-verify", chunkCount: 1)
        try! writer.write(se)

        let end = Frame.end(id: rid)
        try! writer.write(end)

        // Read echoed response — identity echoes raw bytes (no CBOR decode/encode)
        let respSs = try! reader.read()!
        XCTAssertEqual(respSs.frameType, .streamStart)

        let respChunk = try! reader.read()!
        XCTAssertEqual(respChunk.frameType, .chunk)
        XCTAssertEqual(respChunk.payload, nonce)

        let respSe = try! reader.read()!
        XCTAssertEqual(respSe.frameType, .streamEnd)

        let respEnd = try! reader.read()!
        XCTAssertEqual(respEnd.frameType, .end)

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - TEST656: InProcessPluginHost returns NO_HANDLER for unregistered cap

    func test656_noHandlerReturnsErr() throws {
        let host = InProcessPluginHost(handlers: [])

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        let rid = MessageId.newUUID()
        var req = Frame.req(
            id: rid,
            capUrn: "cap:in=\"media:pdf\";op=unknown;out=\"media:text\"",
            payload: Data(),
            contentType: "application/cbor"
        )
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        // Should get ERR back
        let errFrame = try! reader.read()!
        XCTAssertEqual(errFrame.frameType, .err)
        XCTAssertEqual(errFrame.id, rid)
        XCTAssertEqual(errFrame.errorCode, "NO_HANDLER")

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - TEST657: InProcessPluginHost manifest includes identity cap and handler caps

    func test657_manifestIncludesAllCaps() throws {
        let capUrn = "cap:in=\"media:pdf\";op=thumbnail;out=\"media:image;png\""
        let cap = makeTestCap(capUrn)
        let host = InProcessPluginHost(handlers: [
            ("thumb", [cap], EchoHandler())
        ])

        let manifest = host.buildManifest()
        let capUrns: [String] = try! JSONDecoder().decode([String].self, from: manifest)
        XCTAssertEqual(capUrns[0], CSCapIdentity)
        XCTAssertTrue(capUrns.contains { $0.contains("thumbnail") })
    }

    // MARK: - TEST658: InProcessPluginHost handles heartbeat by echoing same ID

    func test658_heartbeatResponse() throws {
        let host = InProcessPluginHost(handlers: [])

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        let hbId = MessageId.newUUID()
        let hb = Frame.heartbeat(id: hbId)
        try! writer.write(hb)

        let resp = try! reader.read()!
        XCTAssertEqual(resp.frameType, .heartbeat)
        XCTAssertEqual(resp.id, hbId)

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - TEST659: InProcessPluginHost handler error returns ERR frame

    func test659_handlerErrorReturnsErrFrame() throws {
        let capUrn = "cap:in=\"media:void\";op=fail;out=\"media:void\""
        let cap = makeTestCap(capUrn)
        let host = InProcessPluginHost(handlers: [
            ("fail", [cap], FailHandler())
        ])

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        // Send REQ + END (no streams, void input)
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        let end = Frame.end(id: rid)
        try! writer.write(end)

        // Should get ERR frame
        let errFrame = try! reader.read()!
        XCTAssertEqual(errFrame.frameType, .err)
        XCTAssertEqual(errFrame.id, rid)
        XCTAssertEqual(errFrame.errorCode, "PROVIDER_ERROR")
        XCTAssertTrue(errFrame.errorMessage!.contains("provider crashed"))

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - TEST660: InProcessPluginHost closest-specificity routing prefers specific over generic

    func test660_closestSpecificityRouting() throws {
        let specificUrn = "cap:in=\"media:pdf\";op=thumbnail;out=\"media:image;png\""
        let genericUrn = "cap:in=\"media:image\";op=thumbnail;out=\"media:image;png\""

        let specificCap = makeTestCap(specificUrn)
        let genericCap = makeTestCap(genericUrn)

        let handlers: [(name: String, caps: [CSCap], handler: FrameHandler)] = [
            ("generic", [genericCap], TaggedHandler(tag: "generic")),
            ("specific", [specificCap], TaggedHandler(tag: "specific")),
        ]

        let host = InProcessPluginHost(handlers: handlers)

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        // Request with specific input (media:pdf) — should route to "specific" handler
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: specificUrn, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        let end = Frame.end(id: rid, finalPayload: nil)
        try! writer.write(end)

        // Read response
        let respSs = try! reader.read()!
        XCTAssertEqual(respSs.frameType, .streamStart)

        let respChunk = try! reader.read()!
        XCTAssertEqual(respChunk.frameType, .chunk)
        let respData = decodeChunkPayload(respChunk.payload!)
        XCTAssertEqual(String(data: respData, encoding: .utf8), "specific")

        let respSe = try! reader.read()!
        XCTAssertEqual(respSe.frameType, .streamEnd)

        let respEnd = try! reader.read()!
        XCTAssertEqual(respEnd.frameType, .end)

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }
}

// MARK: - Socket Pair Extension

extension Pipe {
    /// Create a bidirectional socket pair (like UnixStream::pair in Rust)
    static func socketPair() -> (FileHandle, FileHandle) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        return (FileHandle(fileDescriptor: fds[0]), FileHandle(fileDescriptor: fds[1]))
    }
}
