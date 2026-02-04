import XCTest
@testable import CapNsCbor

final class CborFrameTests: XCTestCase {

    // MARK: - Frame Type Tests

    func testFrameTypeRawValues() {
        XCTAssertEqual(CborFrameType.hello.rawValue, 0)
        XCTAssertEqual(CborFrameType.req.rawValue, 1)
        XCTAssertEqual(CborFrameType.res.rawValue, 2)
        XCTAssertEqual(CborFrameType.chunk.rawValue, 3)
        XCTAssertEqual(CborFrameType.end.rawValue, 4)
        XCTAssertEqual(CborFrameType.log.rawValue, 5)
        XCTAssertEqual(CborFrameType.err.rawValue, 6)
        XCTAssertEqual(CborFrameType.heartbeat.rawValue, 7)
    }

    // MARK: - Message ID Tests

    func testMessageIdUUID() {
        let id = CborMessageId.newUUID()
        XCTAssertNotNil(id.uuid)
        XCTAssertNotNil(id.uuidString)
    }

    func testMessageIdFromUUIDString() {
        let uuidStr = "550e8400-e29b-41d4-a716-446655440000"
        let id = CborMessageId(uuidString: uuidStr)
        XCTAssertNotNil(id)
        XCTAssertEqual(id?.uuidString?.lowercased(), uuidStr.lowercased())
    }

    func testMessageIdUint() {
        let id = CborMessageId.uint(12345)
        XCTAssertNil(id.uuid)
    }

    // MARK: - Frame Creation Tests

    func testHelloFrame() {
        let frame = CborFrame.hello(maxFrame: 1_000_000, maxChunk: 100_000)
        XCTAssertEqual(frame.frameType, .hello)
        XCTAssertEqual(frame.helloMaxFrame, 1_000_000)
        XCTAssertEqual(frame.helloMaxChunk, 100_000)
    }

    func testReqFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.req(
            id: id,
            capUrn: "cap:op=test",
            payload: "payload".data(using: .utf8)!,
            contentType: "application/json"
        )
        XCTAssertEqual(frame.frameType, .req)
        XCTAssertEqual(frame.cap, "cap:op=test")
        XCTAssertEqual(frame.payload, "payload".data(using: .utf8)!)
        XCTAssertEqual(frame.contentType, "application/json")
    }

    func testChunkFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.chunk(id: id, seq: 5, payload: "data".data(using: .utf8)!)
        XCTAssertEqual(frame.frameType, .chunk)
        XCTAssertEqual(frame.seq, 5)
        XCTAssertFalse(frame.isEof)
    }

    func testChunkWithOffset() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.chunkWithOffset(
            id: id,
            seq: 0,
            payload: "first".data(using: .utf8)!,
            offset: 0,
            totalLen: 1000,
            isLast: false
        )
        XCTAssertEqual(frame.seq, 0)
        XCTAssertEqual(frame.offset, 0)
        XCTAssertEqual(frame.len, 1000)
        XCTAssertFalse(frame.isEof)

        let lastFrame = CborFrame.chunkWithOffset(
            id: id,
            seq: 5,
            payload: "last".data(using: .utf8)!,
            offset: 900,
            totalLen: nil,
            isLast: true
        )
        XCTAssertTrue(lastFrame.isEof)
        XCTAssertNil(lastFrame.len)  // len only on first chunk
    }

    func testEndFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.end(id: id, finalPayload: "final".data(using: .utf8)!)
        XCTAssertEqual(frame.frameType, .end)
        XCTAssertTrue(frame.isEof)
        XCTAssertEqual(frame.payload, "final".data(using: .utf8)!)
    }

    func testLogFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.log(id: id, level: "info", message: "Processing...")
        XCTAssertEqual(frame.frameType, .log)
        XCTAssertEqual(frame.logLevel, "info")
        XCTAssertEqual(frame.logMessage, "Processing...")
    }

    func testErrFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.err(id: id, code: "NOT_FOUND", message: "Cap not found")
        XCTAssertEqual(frame.frameType, .err)
        XCTAssertEqual(frame.errorCode, "NOT_FOUND")
        XCTAssertEqual(frame.errorMessage, "Cap not found")
    }

    func testHeartbeatFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.heartbeat(id: id)
        XCTAssertEqual(frame.frameType, .heartbeat)
        XCTAssertEqual(frame.id, id)
        XCTAssertNil(frame.payload)
        XCTAssertNil(frame.meta)
    }

    func testHeartbeatFrameRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.heartbeat(id: id)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .heartbeat)
        XCTAssertEqual(decoded.id, original.id)
    }

    // MARK: - Encode/Decode Tests

    func testEncodeDecodeRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.req(
            id: id,
            capUrn: "cap:op=test",
            payload: "payload".data(using: .utf8)!,
            contentType: "application/json"
        )

        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.frameType, original.frameType)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.cap, original.cap)
        XCTAssertEqual(decoded.payload, original.payload)
        XCTAssertEqual(decoded.contentType, original.contentType)
    }

    func testHelloFrameRoundtrip() throws {
        let original = CborFrame.hello(maxFrame: 500_000, maxChunk: 50_000)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .hello)
        XCTAssertEqual(decoded.helloMaxFrame, 500_000)
        XCTAssertEqual(decoded.helloMaxChunk, 50_000)
    }

    func testErrFrameRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.err(id: id, code: "NOT_FOUND", message: "Cap not found")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .err)
        XCTAssertEqual(decoded.errorCode, "NOT_FOUND")
        XCTAssertEqual(decoded.errorMessage, "Cap not found")
    }

    func testMessageIdUintRoundtrip() throws {
        let id = CborMessageId.uint(12345)
        let original = CborFrame(frameType: .req, id: id)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.id, id)
    }

    // MARK: - Limits Tests

    func testLimitsNegotiation() {
        let local = CborLimits(maxFrame: 1_000_000, maxChunk: 100_000)
        let remote = CborLimits(maxFrame: 500_000, maxChunk: 200_000)
        let negotiated = local.negotiate(with: remote)

        XCTAssertEqual(negotiated.maxFrame, 500_000)
        XCTAssertEqual(negotiated.maxChunk, 100_000)
    }

    func testDefaultLimits() {
        let limits = CborLimits()
        XCTAssertEqual(limits.maxFrame, DEFAULT_MAX_FRAME)
        XCTAssertEqual(limits.maxChunk, DEFAULT_MAX_CHUNK)
    }
}
