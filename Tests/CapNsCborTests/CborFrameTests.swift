import XCTest
import SwiftCBOR
@testable import CapNsCbor

// =============================================================================
// CborFrame + CborIO Tests
//
// Covers TEST171-234 from cbor_frame.rs and cbor_io.rs in the reference
// Rust implementation, plus TEST235-243 for response/error data types.
//
// Tests marked N/A are Rust-specific (Default trait, Debug format, as_bytes,
// Clone, Send+Sync) and have no Swift equivalent.
//
// N/A tests: TEST178, TEST179, TEST194, TEST195, TEST244, TEST245, TEST246, TEST247
// =============================================================================

final class CborFrameTests: XCTestCase {

    // MARK: - Frame Type Tests (TEST171-173)

    // TEST171: All FrameType discriminants roundtrip through raw value conversion preserving identity
    func testFrameTypeRoundtrip() {
        let allTypes: [CborFrameType] = [.hello, .req, .chunk, .end, .log, .err, .heartbeat, .streamStart, .streamEnd]
        for ft in allTypes {
            let raw = ft.rawValue
            let restored = CborFrameType(rawValue: raw)
            XCTAssertEqual(restored, ft, "FrameType \(ft) must roundtrip through rawValue")
        }
    }

    // TEST172: FrameType init returns nil for values outside the valid discriminant range (updated for new max)
    func testInvalidFrameType() {
        XCTAssertNil(CborFrameType(rawValue: 2), "rawValue 2 (res) removed - must be invalid")
        XCTAssertEqual(CborFrameType(rawValue: 10), .relayNotify)
        XCTAssertEqual(CborFrameType(rawValue: 11), .relayState)
        XCTAssertNil(CborFrameType(rawValue: 12), "rawValue 12 must be invalid")
        XCTAssertNil(CborFrameType(rawValue: 99), "rawValue 99 must be invalid")
        XCTAssertNil(CborFrameType(rawValue: 255), "rawValue 255 must be invalid")
    }

    // TEST173: FrameType discriminant values match the wire protocol specification exactly
    func testFrameTypeDiscriminantValues() {
        XCTAssertEqual(CborFrameType.hello.rawValue, 0)
        XCTAssertEqual(CborFrameType.req.rawValue, 1)
        // res = 2 REMOVED - old single-response protocol no longer supported
        XCTAssertEqual(CborFrameType.chunk.rawValue, 3)
        XCTAssertEqual(CborFrameType.end.rawValue, 4)
        XCTAssertEqual(CborFrameType.log.rawValue, 5)
        XCTAssertEqual(CborFrameType.err.rawValue, 6)
        XCTAssertEqual(CborFrameType.heartbeat.rawValue, 7)
        XCTAssertEqual(CborFrameType.streamStart.rawValue, 8)
        XCTAssertEqual(CborFrameType.streamEnd.rawValue, 9)
        XCTAssertEqual(CborFrameType.relayNotify.rawValue, 10)
        XCTAssertEqual(CborFrameType.relayState.rawValue, 11)
    }

    // MARK: - Message ID Tests (TEST174-177, TEST202-203)

    // TEST174: MessageId.newUUID generates valid UUID that roundtrips through string conversion
    func testMessageIdUUID() {
        let id = CborMessageId.newUUID()
        XCTAssertNotNil(id.uuid, "newUUID must produce a UUID")
        XCTAssertNotNil(id.uuidString, "newUUID must have a string representation")
    }

    // TEST175: Two MessageId.newUUID calls produce distinct IDs (no collisions)
    func testMessageIdUUIDUniqueness() {
        let id1 = CborMessageId.newUUID()
        let id2 = CborMessageId.newUUID()
        XCTAssertNotEqual(id1, id2, "Two UUIDs must be distinct")
    }

    // TEST176: MessageId.uint does not produce a UUID string
    func testMessageIdUintHasNoUUIDString() {
        let id = CborMessageId.uint(12345)
        XCTAssertNil(id.uuid, "uint ID must not have UUID")
        XCTAssertNil(id.uuidString, "uint ID must not have UUID string")
    }

    // TEST177: MessageId init from invalid UUID string returns nil
    func testMessageIdFromInvalidUUIDStr() {
        XCTAssertNil(CborMessageId(uuidString: "not-a-uuid"), "invalid UUID string must return nil")
        XCTAssertNil(CborMessageId(uuidString: ""), "empty string must return nil")
        XCTAssertNil(CborMessageId(uuidString: "12345"), "numeric string must return nil")
    }

    // TEST202: MessageId Eq/Hash semantics: equal UUIDs are equal, different ones are not
    func testMessageIdEqualityAndHash() {
        let uuid = UUID()
        let id1 = CborMessageId(uuid: uuid)
        let id2 = CborMessageId(uuid: uuid)
        let id3 = CborMessageId.newUUID()

        XCTAssertEqual(id1, id2, "Same UUID must be equal")
        XCTAssertNotEqual(id1, id3, "Different UUIDs must not be equal")

        // Hash: same IDs must produce same hash (via Set)
        var set: Set<CborMessageId> = []
        set.insert(id1)
        set.insert(id2)
        set.insert(id3)
        XCTAssertEqual(set.count, 2, "Equal IDs must hash to same bucket")
    }

    // TEST203: Uuid and Uint variants of MessageId are never equal
    func testMessageIdCrossVariantInequality() {
        let uuidId = CborMessageId.newUUID()
        let uintId = CborMessageId.uint(0)
        XCTAssertNotEqual(uuidId, uintId, "UUID and Uint variants must never be equal")
    }

    // MARK: - Frame Creation Tests (TEST180-190, TEST204)

    // TEST180: Frame.hello without manifest produces correct HELLO frame for host side
    func testHelloFrame() {
        let frame = CborFrame.hello(maxFrame: 1_000_000, maxChunk: 100_000)
        XCTAssertEqual(frame.frameType, .hello)
        XCTAssertEqual(frame.helloMaxFrame, 1_000_000)
        XCTAssertEqual(frame.helloMaxChunk, 100_000)
        XCTAssertNil(frame.helloManifest, "Host HELLO should not include manifest")
    }

    // TEST181: Frame.hello with manifest produces HELLO with manifest bytes for plugin side
    func testHelloFrameWithManifest() {
        let manifestJSON = """
        {"name":"TestPlugin","version":"1.0.0","description":"Test","caps":[]}
        """
        let manifestData = manifestJSON.data(using: .utf8)!
        let frame = CborFrame.hello(maxFrame: 1_000_000, maxChunk: 100_000, manifest: manifestData)
        XCTAssertEqual(frame.frameType, .hello)
        XCTAssertEqual(frame.helloMaxFrame, 1_000_000)
        XCTAssertEqual(frame.helloMaxChunk, 100_000)
        XCTAssertNotNil(frame.helloManifest, "Plugin HELLO must include manifest")
        XCTAssertEqual(frame.helloManifest, manifestData)
    }

    // TEST182: Frame.req stores cap URN, payload, and content_type correctly
    func testReqFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.req(
            id: id,
            capUrn: "cap:op=test",
            payload: "payload".data(using: .utf8)!,
            contentType: "application/json"
        )
        XCTAssertEqual(frame.frameType, .req)
        XCTAssertEqual(frame.id, id)
        XCTAssertEqual(frame.cap, "cap:op=test")
        XCTAssertEqual(frame.payload, "payload".data(using: .utf8)!)
        XCTAssertEqual(frame.contentType, "application/json")
    }

    // TEST183: REMOVED - Frame.res() removed (old single-response protocol no longer supported)

    // TEST184: Frame.chunk stores seq, streamId and payload for multiplexed streaming
    func testChunkFrame() {
        let reqId = CborMessageId.newUUID()
        let streamId = "stream-123"
        let frame = CborFrame.chunk(reqId: reqId, streamId: streamId, seq: 5, payload: "data".data(using: .utf8)!)
        XCTAssertEqual(frame.frameType, .chunk)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.seq, 5)
        XCTAssertFalse(frame.isEof)
    }

    // TEST185: Frame.err stores error code and message in metadata
    func testErrFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.err(id: id, code: "NOT_FOUND", message: "Cap not found")
        XCTAssertEqual(frame.frameType, .err)
        XCTAssertEqual(frame.errorCode, "NOT_FOUND")
        XCTAssertEqual(frame.errorMessage, "Cap not found")
    }

    // TEST186: Frame.log stores level and message in metadata
    func testLogFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.log(id: id, level: "info", message: "Processing...")
        XCTAssertEqual(frame.frameType, .log)
        XCTAssertEqual(frame.logLevel, "info")
        XCTAssertEqual(frame.logMessage, "Processing...")
    }

    // TEST187: Frame.end with payload sets eof and optional final payload
    func testEndFrameWithPayload() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.end(id: id, finalPayload: "final".data(using: .utf8)!)
        XCTAssertEqual(frame.frameType, .end)
        XCTAssertTrue(frame.isEof)
        XCTAssertEqual(frame.payload, "final".data(using: .utf8)!)
    }

    // TEST188: Frame.end without payload still sets eof marker
    func testEndFrameWithoutPayload() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.end(id: id)
        XCTAssertEqual(frame.frameType, .end)
        XCTAssertTrue(frame.isEof)
        XCTAssertNil(frame.payload)
    }

    // TEST189: chunk_with_offset sets offset on all chunks but len only on seq=0 (with streamId)
    func testChunkWithOffset() {
        let reqId = CborMessageId.newUUID()
        let streamId = "stream-456"

        // First chunk (seq=0) - should have len
        let first = CborFrame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 0,
            payload: "first".data(using: .utf8)!,
            offset: 0, totalLen: 1000, isLast: false
        )
        XCTAssertEqual(first.streamId, streamId)
        XCTAssertEqual(first.seq, 0)
        XCTAssertEqual(first.offset, 0)
        XCTAssertEqual(first.len, 1000, "len must be set on first chunk (seq=0)")
        XCTAssertFalse(first.isEof)

        // Later chunk (seq > 0) - should NOT have len
        let later = CborFrame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 5,
            payload: "later".data(using: .utf8)!,
            offset: 900, totalLen: nil, isLast: false
        )
        XCTAssertEqual(later.streamId, streamId)
        XCTAssertEqual(later.seq, 5)
        XCTAssertEqual(later.offset, 900)
        XCTAssertNil(later.len, "len must not be set on seq > 0")
        XCTAssertFalse(later.isEof)

        // Last chunk - should have eof
        let last = CborFrame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 10,
            payload: "last".data(using: .utf8)!,
            offset: 950, totalLen: nil, isLast: true
        )
        XCTAssertEqual(last.streamId, streamId)
        XCTAssertTrue(last.isEof)
    }

    // TEST190: Frame.heartbeat creates minimal frame with no payload or metadata
    func testHeartbeatFrame() {
        let id = CborMessageId.newUUID()
        let frame = CborFrame.heartbeat(id: id)
        XCTAssertEqual(frame.frameType, .heartbeat)
        XCTAssertEqual(frame.id, id)
        XCTAssertNil(frame.payload)
        XCTAssertNil(frame.meta)
    }

    // TEST191: error_code and error_message return nil for non-Err frame types
    func testErrorAccessorsOnNonErrFrame() {
        let req = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.errorCode, "errorCode must be nil on non-Err frame")
        XCTAssertNil(req.errorMessage, "errorMessage must be nil on non-Err frame")
    }

    // TEST192: log_level and log_message return nil for non-Log frame types
    func testLogAccessorsOnNonLogFrame() {
        let req = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.logLevel, "logLevel must be nil on non-Log frame")
        XCTAssertNil(req.logMessage, "logMessage must be nil on non-Log frame")
    }

    // TEST193: hello_max_frame and hello_max_chunk return nil for non-Hello frame types
    func testHelloAccessorsOnNonHelloFrame() {
        let req = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.helloMaxFrame, "helloMaxFrame must be nil on non-Hello frame")
        XCTAssertNil(req.helloMaxChunk, "helloMaxChunk must be nil on non-Hello frame")
        XCTAssertNil(req.helloManifest, "helloManifest must be nil on non-Hello frame")
    }

    // TEST196: is_eof returns false when eof field is nil (unset)
    func testIsEofWhenNil() {
        var frame = CborFrame(frameType: .chunk, id: .newUUID())
        frame.eof = nil
        XCTAssertFalse(frame.isEof)
    }

    // TEST197: is_eof returns false when eof field is explicitly false
    func testIsEofWhenFalse() {
        var frame = CborFrame(frameType: .chunk, id: .newUUID())
        frame.eof = false
        XCTAssertFalse(frame.isEof)
    }

    // TEST198: Limits default provides the documented default values
    func testLimitsDefault() {
        let limits = CborLimits()
        XCTAssertEqual(limits.maxFrame, DEFAULT_MAX_FRAME)
        XCTAssertEqual(limits.maxChunk, DEFAULT_MAX_CHUNK)
    }

    // TEST198 (continued): Limits negotiation picks minimum of both sides
    func testLimitsNegotiation() {
        let local = CborLimits(maxFrame: 1_000_000, maxChunk: 100_000)
        let remote = CborLimits(maxFrame: 500_000, maxChunk: 200_000)
        let negotiated = local.negotiate(with: remote)

        XCTAssertEqual(negotiated.maxFrame, 500_000)   // min(1_000_000, 500_000)
        XCTAssertEqual(negotiated.maxChunk, 100_000)   // min(100_000, 200_000)
    }

    // TEST199: PROTOCOL_VERSION is 2
    func testProtocolVersionConstant() {
        XCTAssertEqual(CBOR_PROTOCOL_VERSION, 2)
    }

    // TEST200: Integer key constants match the protocol specification
    func testKeyConstants() {
        XCTAssertEqual(CborFrameKey.version.rawValue, 0)
        XCTAssertEqual(CborFrameKey.frameType.rawValue, 1)
        XCTAssertEqual(CborFrameKey.id.rawValue, 2)
        XCTAssertEqual(CborFrameKey.seq.rawValue, 3)
        XCTAssertEqual(CborFrameKey.contentType.rawValue, 4)
        XCTAssertEqual(CborFrameKey.meta.rawValue, 5)
        XCTAssertEqual(CborFrameKey.payload.rawValue, 6)
        XCTAssertEqual(CborFrameKey.len.rawValue, 7)
        XCTAssertEqual(CborFrameKey.offset.rawValue, 8)
        XCTAssertEqual(CborFrameKey.eof.rawValue, 9)
        XCTAssertEqual(CborFrameKey.cap.rawValue, 10)
        XCTAssertEqual(CborFrameKey.streamId.rawValue, 11)
        XCTAssertEqual(CborFrameKey.mediaUrn.rawValue, 12)
    }

    // TEST201: hello_with_manifest preserves binary manifest data (not just JSON text)
    func testHelloManifestBinaryData() {
        // Use binary data that isn't valid JSON to verify raw preservation
        var binaryManifest = Data()
        for i: UInt8 in 0..<128 {
            binaryManifest.append(i)
        }
        let frame = CborFrame.hello(maxFrame: 1_000_000, maxChunk: 100_000, manifest: binaryManifest)
        XCTAssertEqual(frame.helloManifest, binaryManifest, "Binary manifest data must be preserved exactly")
    }

    // TEST204: Frame.req with empty payload stores Data() not nil
    func testReqFrameEmptyPayload() {
        let frame = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNotNil(frame.payload, "Empty payload must be stored as Data(), not nil")
        XCTAssertEqual(frame.payload, Data())
    }

    // MARK: - Encode/Decode Roundtrip Tests (TEST205-213)

    // TEST205: REQ frame encode/decode roundtrip preserves all fields
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

    // TEST206: HELLO frame encode/decode roundtrip preserves max_frame and max_chunk metadata
    func testHelloFrameRoundtrip() throws {
        let original = CborFrame.hello(maxFrame: 500_000, maxChunk: 50_000)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .hello)
        XCTAssertEqual(decoded.helloMaxFrame, 500_000)
        XCTAssertEqual(decoded.helloMaxChunk, 50_000)
    }

    // TEST207: ERR frame encode/decode roundtrip preserves error code and message
    func testErrFrameRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.err(id: id, code: "NOT_FOUND", message: "Cap not found")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .err)
        XCTAssertEqual(decoded.errorCode, "NOT_FOUND")
        XCTAssertEqual(decoded.errorMessage, "Cap not found")
    }

    // TEST208: LOG frame encode/decode roundtrip preserves level and message
    func testLogFrameRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.log(id: id, level: "warn", message: "Something happened")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .log)
        XCTAssertEqual(decoded.logLevel, "warn")
        XCTAssertEqual(decoded.logMessage, "Something happened")
    }

    // TEST209: REMOVED - RES frame test removed (old single-response protocol no longer supported)

    // TEST210: END frame encode/decode roundtrip preserves eof marker and optional payload
    func testEndFrameRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.end(id: id, finalPayload: "final".data(using: .utf8)!)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .end)
        XCTAssertEqual(decoded.id, id)
        XCTAssertTrue(decoded.isEof)
        XCTAssertEqual(decoded.payload, "final".data(using: .utf8)!)
    }

    // TEST211: HELLO with manifest encode/decode roundtrip preserves manifest bytes
    func testHelloWithManifestRoundtrip() throws {
        let manifestJSON = """
        {"name":"TestPlugin","version":"1.0.0","description":"Test description","caps":[{"urn":"cap:op=test","title":"Test","command":"test"}]}
        """
        let manifestData = manifestJSON.data(using: .utf8)!
        let original = CborFrame.hello(maxFrame: 500_000, maxChunk: 50_000, manifest: manifestData)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .hello)
        XCTAssertEqual(decoded.helloMaxFrame, 500_000)
        XCTAssertEqual(decoded.helloMaxChunk, 50_000)
        XCTAssertNotNil(decoded.helloManifest, "Decoded HELLO must preserve manifest")
        XCTAssertEqual(decoded.helloManifest, manifestData, "Manifest data must be preserved exactly")
    }

    // TEST212: chunk_with_offset encode/decode roundtrip preserves offset, len, eof, streamId
    func testChunkWithOffsetRoundtrip() throws {
        let reqId = CborMessageId.newUUID()
        let streamId = "stream-789"

        // First chunk (seq=0) - should have len set
        let firstChunk = CborFrame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 0,
            payload: "first".data(using: .utf8)!,
            offset: 0, totalLen: 5000, isLast: false
        )
        let encodedFirst = try encodeFrame(firstChunk)
        let decodedFirst = try decodeFrame(encodedFirst)

        XCTAssertEqual(decodedFirst.streamId, streamId)
        XCTAssertEqual(decodedFirst.seq, 0)
        XCTAssertEqual(decodedFirst.offset, 0)
        XCTAssertEqual(decodedFirst.len, 5000)
        XCTAssertFalse(decodedFirst.isEof)

        // Later chunk (seq > 0) - should NOT have len
        let laterChunk = CborFrame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 3,
            payload: "later".data(using: .utf8)!,
            offset: 1000, totalLen: 5000, isLast: false
        )
        let encodedLater = try encodeFrame(laterChunk)
        let decodedLater = try decodeFrame(encodedLater)

        XCTAssertEqual(decodedLater.streamId, streamId)
        XCTAssertEqual(decodedLater.seq, 3)
        XCTAssertEqual(decodedLater.offset, 1000)
        XCTAssertNil(decodedLater.len, "len must only be on first chunk")
        XCTAssertFalse(decodedLater.isEof)

        // Final chunk with eof
        let lastChunk = CborFrame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 5,
            payload: "last".data(using: .utf8)!,
            offset: 4000, totalLen: nil, isLast: true
        )
        let encodedLast = try encodeFrame(lastChunk)
        let decodedLast = try decodeFrame(encodedLast)

        XCTAssertEqual(decodedLast.streamId, streamId)
        XCTAssertEqual(decodedLast.seq, 5)
        XCTAssertEqual(decodedLast.offset, 4000)
        XCTAssertNil(decodedLast.len)
        XCTAssertTrue(decodedLast.isEof)
    }

    // TEST213: Heartbeat frame encode/decode roundtrip preserves ID with no extra fields
    func testHeartbeatRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let original = CborFrame.heartbeat(id: id)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .heartbeat)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(decoded.payload)
    }

    // MARK: - Wire Format I/O Tests (TEST214-223)

    // TEST214: write_frame/read_frame IO roundtrip through length-prefixed wire format
    @available(macOS 10.15.4, iOS 13.4, *)
    func testFrameIORoundtrip() throws {
        let pipe = Pipe()
        let limits = CborLimits()
        let id = CborMessageId.newUUID()
        let original = CborFrame.req(id: id, capUrn: "cap:op=test", payload: "payload".data(using: .utf8)!, contentType: "application/json")

        try writeFrame(original, to: pipe.fileHandleForWriting, limits: limits)
        pipe.fileHandleForWriting.closeFile()

        let decoded = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.frameType, original.frameType)
        XCTAssertEqual(decoded!.cap, original.cap)
        XCTAssertEqual(decoded!.payload, original.payload)
    }

    // TEST215: Reading multiple sequential frames from a single stream (with streamId)
    @available(macOS 10.15.4, iOS 13.4, *)
    func testMultipleFrames() throws {
        let pipe = Pipe()
        let limits = CborLimits()

        let id1 = CborMessageId.newUUID()
        let id2 = CborMessageId.newUUID()
        let id3 = CborMessageId.newUUID()

        let f1 = CborFrame.req(id: id1, capUrn: "cap:op=first", payload: "one".data(using: .utf8)!, contentType: "text/plain")
        let f2 = CborFrame.chunk(reqId: id2, streamId: "stream-001", seq: 0, payload: "two".data(using: .utf8)!)
        let f3 = CborFrame.end(id: id3, finalPayload: "three".data(using: .utf8)!)

        try writeFrame(f1, to: pipe.fileHandleForWriting, limits: limits)
        try writeFrame(f2, to: pipe.fileHandleForWriting, limits: limits)
        try writeFrame(f3, to: pipe.fileHandleForWriting, limits: limits)
        pipe.fileHandleForWriting.closeFile()

        let r1 = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertEqual(r1?.frameType, .req)
        XCTAssertEqual(r1?.id, id1)

        let r2 = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertEqual(r2?.frameType, .chunk)
        XCTAssertEqual(r2?.id, id2)
        XCTAssertEqual(r2?.streamId, "stream-001")

        let r3 = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertEqual(r3?.frameType, .end)
        XCTAssertEqual(r3?.id, id3)

        // EOF after all frames read
        let eof = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertNil(eof)
    }

    // TEST216: write_frame rejects frames exceeding max_frame limit
    @available(macOS 10.15.4, iOS 13.4, *)
    func testFrameTooLarge() throws {
        let pipe = Pipe()
        let limits = CborLimits(maxFrame: 100, maxChunk: 50)

        let largePayload = Data(repeating: 0, count: 200)
        let frame = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: largePayload, contentType: "application/octet-stream")

        XCTAssertThrowsError(try writeFrame(frame, to: pipe.fileHandleForWriting, limits: limits)) { error in
            if case CborError.frameTooLarge = error {
                // Expected
            } else {
                XCTFail("Expected frameTooLarge error, got \(error)")
            }
        }
    }

    // TEST217: read_frame rejects incoming frames exceeding the negotiated max_frame limit
    @available(macOS 10.15.4, iOS 13.4, *)
    func testReadFrameTooLarge() throws {
        let pipe = Pipe()
        let writeLimits = CborLimits(maxFrame: 10_000_000, maxChunk: 1_000_000)
        let readLimits = CborLimits(maxFrame: 50, maxChunk: 50)

        // Write a frame with generous limits
        let frame = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(repeating: 0, count: 200), contentType: "text/plain")
        try writeFrame(frame, to: pipe.fileHandleForWriting, limits: writeLimits)
        pipe.fileHandleForWriting.closeFile()

        // Try to read with strict limits
        XCTAssertThrowsError(try readFrame(from: pipe.fileHandleForReading, limits: readLimits)) { error in
            if case CborError.frameTooLarge = error {
                // Expected
            } else {
                XCTFail("Expected frameTooLarge error, got \(error)")
            }
        }
    }

    // TEST218: write_chunked splits data into chunks respecting max_chunk (with streamId parameter)
    @available(macOS 10.15.4, iOS 13.4, *)
    func testWriteChunked() throws {
        let pipe = Pipe()
        let limits = CborLimits(maxFrame: 1_000_000, maxChunk: 10) // Very small for testing
        let writer = CborFrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = CborMessageId.newUUID()
        let streamId = "stream-test-218"
        let data = "Hello, this is a longer message that will be chunked!".data(using: .utf8)!

        try writer.writeChunked(id: id, streamId: streamId, contentType: "text/plain", data: data)
        pipe.fileHandleForWriting.closeFile()

        // Read back all chunks
        let reader = CborFrameReader(handle: pipe.fileHandleForReading, limits: CborLimits(maxFrame: 1_000_000, maxChunk: 1_000_000))
        var received = Data()
        var chunkCount: UInt64 = 0
        var firstChunkHadLen = false
        var firstChunkHadContentType = false

        while true {
            guard let frame = try reader.read() else { break }
            XCTAssertEqual(frame.frameType, .chunk)
            XCTAssertEqual(frame.id, id)
            XCTAssertEqual(frame.streamId, streamId)
            XCTAssertEqual(frame.seq, chunkCount)

            if chunkCount == 0 {
                firstChunkHadLen = frame.len != nil
                firstChunkHadContentType = frame.contentType != nil
                XCTAssertEqual(frame.len, UInt64(data.count), "first chunk must carry total len")
                XCTAssertEqual(frame.contentType, "text/plain")
            }

            if let payload = frame.payload {
                XCTAssertLessThanOrEqual(payload.count, limits.maxChunk, "chunk must not exceed max_chunk")
                received.append(payload)
            }

            if frame.isEof { break }
            chunkCount += 1
        }

        XCTAssertEqual(received, data)
        XCTAssertGreaterThan(chunkCount, 0, "data larger than max_chunk must produce multiple chunks")
        XCTAssertTrue(firstChunkHadLen, "first chunk must carry total length")
        XCTAssertTrue(firstChunkHadContentType, "first chunk must carry content_type")
    }

    // TEST219: write_chunked with empty data produces a single EOF chunk (with streamId)
    @available(macOS 10.15.4, iOS 13.4, *)
    func testWriteChunkedEmptyData() throws {
        let pipe = Pipe()
        let limits = CborLimits(maxFrame: 1_000_000, maxChunk: 100)
        let writer = CborFrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = CborMessageId.newUUID()
        let streamId = "stream-empty"
        try writer.writeChunked(id: id, streamId: streamId, contentType: "text/plain", data: Data())
        pipe.fileHandleForWriting.closeFile()

        let frame = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.frameType, .chunk)
        XCTAssertEqual(frame!.streamId, streamId)
        XCTAssertTrue(frame!.isEof, "empty data must produce immediate EOF")
        XCTAssertEqual(frame!.len, 0, "empty payload must report len=0")
    }

    // TEST220: write_chunked with data exactly equal to max_chunk produces exactly one chunk (with streamId)
    @available(macOS 10.15.4, iOS 13.4, *)
    func testWriteChunkedExactFit() throws {
        let pipe = Pipe()
        let limits = CborLimits(maxFrame: 1_000_000, maxChunk: 10)
        let writer = CborFrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = CborMessageId.newUUID()
        let streamId = "stream-exact"
        let data = "0123456789".data(using: .utf8)! // exactly 10 bytes = max_chunk
        try writer.writeChunked(id: id, streamId: streamId, contentType: "text/plain", data: data)
        pipe.fileHandleForWriting.closeFile()

        let frame = try readFrame(from: pipe.fileHandleForReading, limits: CborLimits(maxFrame: 1_000_000, maxChunk: 1_000_000))
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.streamId, streamId)
        XCTAssertTrue(frame!.isEof, "single-chunk data must be EOF")
        XCTAssertEqual(frame!.payload, data)
        XCTAssertEqual(frame!.seq, 0)

        // No more frames
        let eof = try readFrame(from: pipe.fileHandleForReading, limits: CborLimits(maxFrame: 1_000_000, maxChunk: 1_000_000))
        XCTAssertNil(eof)
    }

    // TEST221: read_frame returns nil on clean EOF (empty stream)
    func testEofHandling() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.closeFile() // immediate EOF

        let result = try readFrame(from: pipe.fileHandleForReading, limits: CborLimits())
        XCTAssertNil(result)
    }

    // TEST222: read_frame handles truncated length prefix (fewer than 4 bytes available)
    @available(macOS 10.15.4, iOS 13.4, *)
    func testTruncatedLengthPrefix() throws {
        let pipe = Pipe()
        // Write only 2 bytes (need 4 for length prefix)
        pipe.fileHandleForWriting.write(Data([0x00, 0x01]))
        pipe.fileHandleForWriting.closeFile()

        XCTAssertThrowsError(try readFrame(from: pipe.fileHandleForReading, limits: CborLimits())) { error in
            // Should produce an I/O or protocol error
            if case CborError.ioError = error {
                // Expected - truncated read
            } else if case CborError.invalidFrame = error {
                // Also acceptable
            } else {
                // Any error is acceptable for truncated data
            }
        }
    }

    // TEST223: read_frame returns error on truncated frame body
    @available(macOS 10.15.4, iOS 13.4, *)
    func testTruncatedFrameBody() throws {
        let pipe = Pipe()
        // Write length prefix claiming 100 bytes, but only provide 5
        var lengthBytes = Data(count: 4)
        lengthBytes[0] = 0
        lengthBytes[1] = 0
        lengthBytes[2] = 0
        lengthBytes[3] = 100
        pipe.fileHandleForWriting.write(lengthBytes)
        pipe.fileHandleForWriting.write(Data([0x01, 0x02, 0x03, 0x04, 0x05]))
        pipe.fileHandleForWriting.closeFile()

        XCTAssertThrowsError(try readFrame(from: pipe.fileHandleForReading, limits: CborLimits())) { error in
            // Should error on truncated body
            if case CborError.ioError = error {
                // Expected
            } else if case CborError.invalidFrame = error {
                // Also acceptable
            } else {
                // Any error is acceptable
            }
        }
    }

    // TEST224: MessageId.uint roundtrips through encode/decode
    func testMessageIdUintRoundtrip() throws {
        let id = CborMessageId.uint(12345)
        let original = CborFrame(frameType: .req, id: id)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)
        XCTAssertEqual(decoded.id, id)
    }

    // TEST225: decode_frame rejects non-map CBOR values (e.g., array, integer, string)
    func testDecodeNonMapValue() throws {
        // Encode a CBOR array instead of map
        let arrayValue = CBOR.array([.unsignedInt(1)])
        let bytes = Data(arrayValue.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case CborError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST226: decode_frame rejects CBOR map missing required version field
    func testDecodeMissingVersion() throws {
        // Build CBOR map with frame_type and id but missing version
        let map = CBOR.map([
            .unsignedInt(CborFrameKey.frameType.rawValue): .unsignedInt(1),
            .unsignedInt(CborFrameKey.id.rawValue): .unsignedInt(0)
        ])
        let bytes = Data(map.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case CborError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST227: decode_frame rejects CBOR map with invalid frame_type value
    func testDecodeInvalidFrameTypeValue() throws {
        let map = CBOR.map([
            .unsignedInt(CborFrameKey.version.rawValue): .unsignedInt(1),
            .unsignedInt(CborFrameKey.frameType.rawValue): .unsignedInt(99),
            .unsignedInt(CborFrameKey.id.rawValue): .unsignedInt(0)
        ])
        let bytes = Data(map.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case CborError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST228: decode_frame rejects CBOR map missing required id field
    func testDecodeMissingId() throws {
        let map = CBOR.map([
            .unsignedInt(CborFrameKey.version.rawValue): .unsignedInt(1),
            .unsignedInt(CborFrameKey.frameType.rawValue): .unsignedInt(1)
            // No ID field
        ])
        let bytes = Data(map.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case CborError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST229: FrameReader/FrameWriter set_limits updates the negotiated limits
    @available(macOS 10.15.4, iOS 13.4, *)
    func testFrameReaderWriterSetLimits() {
        let pipe = Pipe()
        let reader = CborFrameReader(handle: pipe.fileHandleForReading)
        let writer = CborFrameWriter(handle: pipe.fileHandleForWriting)

        let custom = CborLimits(maxFrame: 500, maxChunk: 100)
        reader.setLimits(custom)
        writer.setLimits(custom)

        XCTAssertEqual(reader.getLimits().maxFrame, 500)
        XCTAssertEqual(reader.getLimits().maxChunk, 100)
        XCTAssertEqual(writer.getLimits().maxFrame, 500)
        XCTAssertEqual(writer.getLimits().maxChunk, 100)
    }

    // TEST233: Binary payload with all 256 byte values roundtrips through encode/decode
    func testBinaryPayloadAllByteValues() throws {
        var data = Data()
        for i: UInt8 in 0...255 {
            data.append(i)
        }

        let id = CborMessageId.newUUID()
        let frame = CborFrame.req(id: id, capUrn: "cap:op=binary", payload: data, contentType: "application/octet-stream")

        let encoded = try encodeFrame(frame)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.payload, data)
    }

    // TEST234: decode_frame handles garbage CBOR bytes gracefully with an error
    func testDecodeGarbageBytes() {
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB])
        XCTAssertThrowsError(try decodeFrame(garbage), "garbage bytes must produce decode error")
    }

    // MARK: - All Frame Types Roundtrip (combined TEST for TEST205-213 coverage)

    // Covers all frame types in a single loop for comprehensive roundtrip verification
    func testAllFrameTypesRoundtrip() throws {
        let testCases: [(CborFrame, String)] = [
            (CborFrame.hello(maxFrame: 1_000_000, maxChunk: 100_000), "HELLO"),
            (CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: "data".data(using: .utf8)!, contentType: "text/plain"), "REQ"),
            // RES removed - old single-response protocol no longer supported
            (CborFrame.chunk(reqId: .newUUID(), streamId: "stream-all", seq: 5, payload: "chunk".data(using: .utf8)!), "CHUNK"),
            (CborFrame.end(id: .newUUID(), finalPayload: "final".data(using: .utf8)), "END"),
            (CborFrame.log(id: .newUUID(), level: "info", message: "test log"), "LOG"),
            (CborFrame.err(id: .newUUID(), code: "ERROR", message: "test error"), "ERR"),
            (CborFrame.heartbeat(id: .newUUID()), "HEARTBEAT"),
            (CborFrame.streamStart(reqId: .newUUID(), streamId: "stream-start-all", mediaUrn: "media:bytes"), "STREAM_START"),
            (CborFrame.streamEnd(reqId: .newUUID(), streamId: "stream-end-all"), "STREAM_END"),
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

    // MARK: - Response/Error Type Tests (TEST235-243)

    // TEST235: CborResponseChunk stores payload, seq, offset, len, and eof fields correctly
    func testResponseChunk() {
        let chunk = CborResponseChunk(
            payload: "hello".data(using: .utf8)!,
            seq: 0, offset: nil, len: nil, isEof: false
        )
        XCTAssertEqual(chunk.payload, "hello".data(using: .utf8)!)
        XCTAssertEqual(chunk.seq, 0)
        XCTAssertNil(chunk.offset)
        XCTAssertNil(chunk.len)
        XCTAssertFalse(chunk.isEof)
    }

    // TEST236: CborResponseChunk with all fields populated preserves offset, len, and eof
    func testResponseChunkWithAllFields() {
        let chunk = CborResponseChunk(
            payload: "data".data(using: .utf8)!,
            seq: 3, offset: 1000, len: 5000, isEof: true
        )
        XCTAssertEqual(chunk.seq, 3)
        XCTAssertEqual(chunk.offset, 1000)
        XCTAssertEqual(chunk.len, 5000)
        XCTAssertTrue(chunk.isEof)
    }

    // TEST237: CborPluginResponse.single final_payload returns the single payload
    func testPluginResponseSingle() {
        let response = CborPluginResponse.single("hello".data(using: .utf8)!)
        XCTAssertEqual(response.finalPayload, "hello".data(using: .utf8)!)
        XCTAssertEqual(response.concatenated(), "hello".data(using: .utf8)!)
    }

    // TEST238: CborPluginResponse.single with empty payload returns empty data
    func testPluginResponseSingleEmpty() {
        let response = CborPluginResponse.single(Data())
        XCTAssertEqual(response.finalPayload, Data())
        XCTAssertEqual(response.concatenated(), Data())
    }

    // TEST239: CborPluginResponse.streaming concatenated joins all chunk payloads in order
    func testPluginResponseStreaming() {
        let chunks = [
            CborResponseChunk(payload: "hello".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            CborResponseChunk(payload: " ".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: false),
            CborResponseChunk(payload: "world".data(using: .utf8)!, seq: 2, offset: nil, len: nil, isEof: true),
        ]
        let response = CborPluginResponse.streaming(chunks)
        XCTAssertEqual(response.concatenated(), "hello world".data(using: .utf8)!)
    }

    // TEST240: CborPluginResponse.streaming finalPayload returns the last chunk's payload
    func testPluginResponseStreamingFinalPayload() {
        let chunks = [
            CborResponseChunk(payload: "first".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            CborResponseChunk(payload: "last".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: true),
        ]
        let response = CborPluginResponse.streaming(chunks)
        XCTAssertEqual(response.finalPayload, "last".data(using: .utf8)!)
    }

    // TEST241: CborPluginResponse.streaming with empty chunks vec returns empty concatenation
    func testPluginResponseStreamingEmptyChunks() {
        let response = CborPluginResponse.streaming([])
        XCTAssertEqual(response.concatenated(), Data())
        XCTAssertNil(response.finalPayload)
    }

    // TEST242: CborPluginResponse.streaming concatenated with large payload
    func testPluginResponseStreamingLargePayload() {
        let chunk1 = CborResponseChunk(payload: Data(repeating: 0xAA, count: 1000), seq: 0, offset: nil, len: nil, isEof: false)
        let chunk2 = CborResponseChunk(payload: Data(repeating: 0xBB, count: 2000), seq: 1, offset: nil, len: nil, isEof: true)
        let response = CborPluginResponse.streaming([chunk1, chunk2])

        let result = response.concatenated()
        XCTAssertEqual(result.count, 3000)
        XCTAssertEqual(result[0], 0xAA)
        XCTAssertEqual(result[999], 0xAA)
        XCTAssertEqual(result[1000], 0xBB)
        XCTAssertEqual(result[2999], 0xBB)
    }

    // TEST243: CborPluginHostError variants display correct error messages
    @available(macOS 10.15.4, iOS 13.4, *)
    func testPluginHostErrorDisplay() {
        let errors: [(CborPluginHostError, String)] = [
            (.handshakeFailed("timeout"), "timeout"),
            (.pluginError(code: "NOT_FOUND", message: "Cap not found"), "NOT_FOUND"),
            (.processExited, "exited"),
            (.closed, "closed"),
        ]

        for (error, expectedSubstring) in errors {
            let msg = error.errorDescription ?? ""
            XCTAssertTrue(msg.contains(expectedSubstring),
                "Error message '\(msg)' must contain '\(expectedSubstring)'")
        }
    }

    // MARK: - Stream Multiplexing Frame Tests (TEST365-368)

    // TEST365: Frame.stream_start stores reqId, streamId, and mediaUrn correctly
    func testStreamStartFrame() {
        let reqId = CborMessageId.newUUID()
        let streamId = "stream-abc-123"
        let mediaUrn = "media:bytes"
        let frame = CborFrame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn)

        XCTAssertEqual(frame.frameType, .streamStart)
        XCTAssertEqual(frame.id, reqId)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.mediaUrn, mediaUrn)
    }

    // TEST366: Frame.stream_end stores reqId and streamId correctly
    func testStreamEndFrame() {
        let reqId = CborMessageId.newUUID()
        let streamId = "stream-xyz-789"
        let frame = CborFrame.streamEnd(reqId: reqId, streamId: streamId)

        XCTAssertEqual(frame.frameType, .streamEnd)
        XCTAssertEqual(frame.id, reqId)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertNil(frame.mediaUrn, "STREAM_END does not include mediaUrn")
    }

    // TEST367: Frame.stream_start with empty streamId still constructs successfully
    func testStreamStartWithEmptyStreamId() {
        let reqId = CborMessageId.newUUID()
        let streamId = ""
        let mediaUrn = "media:text"
        let frame = CborFrame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn)

        XCTAssertEqual(frame.frameType, .streamStart)
        XCTAssertEqual(frame.streamId, "")
        XCTAssertEqual(frame.mediaUrn, mediaUrn)
    }

    // TEST368: Frame.stream_start with empty mediaUrn still constructs successfully
    func testStreamStartWithEmptyMediaUrn() {
        let reqId = CborMessageId.newUUID()
        let streamId = "stream-empty-media"
        let mediaUrn = ""
        let frame = CborFrame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn)

        XCTAssertEqual(frame.frameType, .streamStart)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.mediaUrn, "")
    }

    // TEST389: StreamStart encode/decode roundtrip preserves stream_id and media_urn
    func testStreamStartRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let streamId = "stream-abc-123"
        let mediaUrn = "media:bytes"

        let frame = CborFrame.streamStart(reqId: id, streamId: streamId, mediaUrn: mediaUrn)
        let encoded = try encodeFrame(frame)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .streamStart)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.streamId, "stream-abc-123")
        XCTAssertEqual(decoded.mediaUrn, "media:bytes")
    }

    // TEST390: StreamEnd encode/decode roundtrip preserves stream_id, no media_urn
    func testStreamEndRoundtrip() throws {
        let id = CborMessageId.newUUID()
        let streamId = "stream-xyz-789"

        let frame = CborFrame.streamEnd(reqId: id, streamId: streamId)
        let encoded = try encodeFrame(frame)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .streamEnd)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.streamId, "stream-xyz-789")
        XCTAssertNil(decoded.mediaUrn, "StreamEnd should not have media_urn")
    }

    // MARK: - Relay Frame Tests (TEST399-403, TEST399a-400a)

    // TEST399: RelayNotify discriminant roundtrips through rawValue conversion (value 10)
    func testRelayNotifyDiscriminantRoundtrip() {
        let ft = CborFrameType.relayNotify
        XCTAssertEqual(ft.rawValue, 10, "RELAY_NOTIFY must be 10")
        let restored = CborFrameType(rawValue: 10)
        XCTAssertEqual(restored, .relayNotify, "rawValue 10 must restore to relayNotify")
    }

    // TEST400: RelayState discriminant roundtrips through rawValue conversion (value 11)
    func testRelayStateDiscriminantRoundtrip() {
        let ft = CborFrameType.relayState
        XCTAssertEqual(ft.rawValue, 11, "RELAY_STATE must be 11")
        let restored = CborFrameType(rawValue: 11)
        XCTAssertEqual(restored, .relayState, "rawValue 11 must restore to relayState")
    }

    // TEST401: relay_notify factory stores manifest and limits, accessors extract them correctly
    func testRelayNotifyFactoryAndAccessors() {
        let manifest = "{\"caps\":[\"cap:op=test\"]}".data(using: .utf8)!
        let maxFrame = 2_000_000
        let maxChunk = 128_000

        let frame = CborFrame.relayNotify(manifest: manifest, maxFrame: maxFrame, maxChunk: maxChunk)

        XCTAssertEqual(frame.frameType, .relayNotify)

        // Test manifest accessor
        let extractedManifest = frame.relayNotifyManifest
        XCTAssertNotNil(extractedManifest, "relayNotifyManifest must not be nil")
        XCTAssertEqual(extractedManifest, manifest)

        // Test limits accessor
        let extractedLimits = frame.relayNotifyLimits
        XCTAssertNotNil(extractedLimits, "relayNotifyLimits must not be nil")
        XCTAssertEqual(extractedLimits?.maxFrame, maxFrame)
        XCTAssertEqual(extractedLimits?.maxChunk, maxChunk)

        // Test accessors on wrong frame type return nil
        let req = CborFrame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.relayNotifyManifest, "relayNotifyManifest on REQ must be nil")
        XCTAssertNil(req.relayNotifyLimits, "relayNotifyLimits on REQ must be nil")
    }

    // TEST402: relay_state factory stores resource payload in payload field
    func testRelayStateFactoryAndPayload() {
        let resources = "{\"gpu_memory\":8192}".data(using: .utf8)!

        let frame = CborFrame.relayState(resources: resources)

        XCTAssertEqual(frame.frameType, .relayState)
        XCTAssertEqual(frame.payload, resources)
    }

    // TEST403: FrameType from value 12 is nil (one past RelayState)
    func testFrameTypeOnePastRelayState() {
        XCTAssertNil(CborFrameType(rawValue: 12), "rawValue 12 must be nil (one past RelayState)")
    }

    // TEST399a: RelayNotify encode/decode roundtrip preserves manifest and limits
    func testRelayNotifyRoundtrip() throws {
        let manifest = "{\"caps\":[\"cap:op=relay-test\"]}".data(using: .utf8)!
        let maxFrame = 2_000_000
        let maxChunk = 128_000

        let original = CborFrame.relayNotify(manifest: manifest, maxFrame: maxFrame, maxChunk: maxChunk)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .relayNotify)

        let extractedManifest = decoded.relayNotifyManifest
        XCTAssertNotNil(extractedManifest, "manifest must survive roundtrip")
        XCTAssertEqual(extractedManifest, manifest)

        let extractedLimits = decoded.relayNotifyLimits
        XCTAssertNotNil(extractedLimits, "limits must survive roundtrip")
        XCTAssertEqual(extractedLimits?.maxFrame, maxFrame)
        XCTAssertEqual(extractedLimits?.maxChunk, maxChunk)
    }

    // TEST400a: RelayState encode/decode roundtrip preserves resource payload
    func testRelayStateRoundtrip() throws {
        let resources = "{\"gpu_memory\":8192,\"cpu_cores\":16}".data(using: .utf8)!

        let original = CborFrame.relayState(resources: resources)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .relayState)
        XCTAssertEqual(decoded.payload, resources)
    }
}
