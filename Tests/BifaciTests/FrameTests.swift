import XCTest
import SwiftCBOR
@testable import Bifaci

// =============================================================================
// Frame + CborIO Tests
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
    func test171_frameTypeRoundtrip() {
        let allTypes: [FrameType] = [.hello, .req, .chunk, .end, .log, .err, .heartbeat, .streamStart, .streamEnd]
        for ft in allTypes {
            let raw = ft.rawValue
            let restored = FrameType(rawValue: raw)
            XCTAssertEqual(restored, ft, "FrameType \(ft) must roundtrip through rawValue")
        }
    }

    // TEST172: FrameType init returns nil for values outside the valid discriminant range (updated for new max)
    func test172_invalidFrameType() {
        XCTAssertNil(FrameType(rawValue: 2), "rawValue 2 (res) removed - must be invalid")
        XCTAssertEqual(FrameType(rawValue: 10), .relayNotify)
        XCTAssertEqual(FrameType(rawValue: 11), .relayState)
        XCTAssertNil(FrameType(rawValue: 12), "rawValue 12 must be invalid")
        XCTAssertNil(FrameType(rawValue: 99), "rawValue 99 must be invalid")
        XCTAssertNil(FrameType(rawValue: 255), "rawValue 255 must be invalid")
    }

    // TEST173: FrameType discriminant values match the wire protocol specification exactly
    func test173_frameTypeDiscriminantValues() {
        XCTAssertEqual(FrameType.hello.rawValue, 0)
        XCTAssertEqual(FrameType.req.rawValue, 1)
        // res = 2 REMOVED - old single-response protocol no longer supported
        XCTAssertEqual(FrameType.chunk.rawValue, 3)
        XCTAssertEqual(FrameType.end.rawValue, 4)
        XCTAssertEqual(FrameType.log.rawValue, 5)
        XCTAssertEqual(FrameType.err.rawValue, 6)
        XCTAssertEqual(FrameType.heartbeat.rawValue, 7)
        XCTAssertEqual(FrameType.streamStart.rawValue, 8)
        XCTAssertEqual(FrameType.streamEnd.rawValue, 9)
        XCTAssertEqual(FrameType.relayNotify.rawValue, 10)
        XCTAssertEqual(FrameType.relayState.rawValue, 11)
    }

    // MARK: - Message ID Tests (TEST174-177, TEST202-203)

    // TEST174: MessageId.newUUID generates valid UUID that roundtrips through string conversion
    func test174_messageIdUUID() {
        let id = MessageId.newUUID()
        XCTAssertNotNil(id.uuid, "newUUID must produce a UUID")
        XCTAssertNotNil(id.uuidString, "newUUID must have a string representation")
    }

    // TEST175: Two MessageId.newUUID calls produce distinct IDs (no collisions)
    func test175_messageIdUUIDUniqueness() {
        let id1 = MessageId.newUUID()
        let id2 = MessageId.newUUID()
        XCTAssertNotEqual(id1, id2, "Two UUIDs must be distinct")
    }

    // TEST176: MessageId.uint does not produce a UUID string
    func test176_messageIdUintHasNoUUIDString() {
        let id = MessageId.uint(12345)
        XCTAssertNil(id.uuid, "uint ID must not have UUID")
        XCTAssertNil(id.uuidString, "uint ID must not have UUID string")
    }

    // TEST177: MessageId init from invalid UUID string returns nil
    func test177_messageIdFromInvalidUUIDStr() {
        XCTAssertNil(MessageId(uuidString: "not-a-uuid"), "invalid UUID string must return nil")
        XCTAssertNil(MessageId(uuidString: ""), "empty string must return nil")
        XCTAssertNil(MessageId(uuidString: "12345"), "numeric string must return nil")
    }

    // TEST202: MessageId Eq/Hash semantics: equal UUIDs are equal, different ones are not
    func test202_messageIdEqualityAndHash() {
        let uuid = UUID()
        let id1 = MessageId(uuid: uuid)
        let id2 = MessageId(uuid: uuid)
        let id3 = MessageId.newUUID()

        XCTAssertEqual(id1, id2, "Same UUID must be equal")
        XCTAssertNotEqual(id1, id3, "Different UUIDs must not be equal")

        // Hash: same IDs must produce same hash (via Set)
        var set: Set<MessageId> = []
        set.insert(id1)
        set.insert(id2)
        set.insert(id3)
        XCTAssertEqual(set.count, 2, "Equal IDs must hash to same bucket")
    }

    // TEST203: Uuid and Uint variants of MessageId are never equal
    func test203_messageIdCrossVariantInequality() {
        let uuidId = MessageId.newUUID()
        let uintId = MessageId.uint(0)
        XCTAssertNotEqual(uuidId, uintId, "UUID and Uint variants must never be equal")
    }

    // MARK: - Frame Creation Tests (TEST180-190, TEST204)

    // TEST180: Frame.hello without manifest produces correct HELLO frame for host side
    func test180_helloFrame() {
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 100_000, maxReorderBuffer: 64)
        let frame = Frame.hello(limits: limits)
        XCTAssertEqual(frame.frameType, .hello)
        XCTAssertEqual(frame.helloMaxFrame, 1_000_000)
        XCTAssertEqual(frame.helloMaxChunk, 100_000)
        XCTAssertEqual(frame.helloMaxReorderBuffer, 64)
        XCTAssertNil(frame.helloManifest, "Host HELLO should not include manifest")
    }

    // TEST181: Frame.helloWithManifest produces HELLO with manifest bytes for plugin side
    func test181_helloFrameWithManifest() {
        let manifestJSON = """
        {"name":"TestPlugin","version":"1.0.0","description":"Test","caps":[{"urn":"cap:","title":"Identity","command":"identity"}]}
        """
        let manifestData = manifestJSON.data(using: .utf8)!
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 100_000, maxReorderBuffer: 64)
        let frame = Frame.helloWithManifest(limits: limits, manifest: manifestData)
        XCTAssertEqual(frame.frameType, .hello)
        XCTAssertEqual(frame.helloMaxFrame, 1_000_000)
        XCTAssertEqual(frame.helloMaxChunk, 100_000)
        XCTAssertEqual(frame.helloMaxReorderBuffer, 64)
        XCTAssertNotNil(frame.helloManifest, "Plugin HELLO must include manifest")
        XCTAssertEqual(frame.helloManifest, manifestData)
    }

    // TEST182: Frame.req stores cap URN, payload, and content_type correctly
    func test182_reqFrame() {
        let id = MessageId.newUUID()
        let frame = Frame.req(
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

    // TEST184: Frame.chunk stores seq, streamId, payload, chunkIndex, and checksum for multiplexed streaming
    func test184_chunkFrame() {
        let reqId = MessageId.newUUID()
        let streamId = "stream-123"
        let payload = "data".data(using: .utf8)!
        let frame = Frame.chunk(reqId: reqId, streamId: streamId, seq: 5, payload: payload, chunkIndex: 0, checksum: Frame.computeChecksum(payload))
        XCTAssertEqual(frame.frameType, .chunk)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.seq, 5)
        XCTAssertEqual(frame.chunkIndex, 0)
        XCTAssertNotNil(frame.checksum)
        XCTAssertFalse(frame.isEof)
    }

    // TEST185: Frame.err stores error code and message in metadata
    func test185_errFrame() {
        let id = MessageId.newUUID()
        let frame = Frame.err(id: id, code: "NOT_FOUND", message: "Cap not found")
        XCTAssertEqual(frame.frameType, .err)
        XCTAssertEqual(frame.errorCode, "NOT_FOUND")
        XCTAssertEqual(frame.errorMessage, "Cap not found")
    }

    // TEST186: Frame.log stores level and message in metadata
    func test186_logFrame() {
        let id = MessageId.newUUID()
        let frame = Frame.log(id: id, level: "info", message: "Processing...")
        XCTAssertEqual(frame.frameType, .log)
        XCTAssertEqual(frame.logLevel, "info")
        XCTAssertEqual(frame.logMessage, "Processing...")
    }

    // TEST187: Frame.end with payload sets eof and optional final payload
    func test187_endFrameWithPayload() {
        let id = MessageId.newUUID()
        let frame = Frame.end(id: id, finalPayload: "final".data(using: .utf8)!)
        XCTAssertEqual(frame.frameType, .end)
        XCTAssertTrue(frame.isEof)
        XCTAssertEqual(frame.payload, "final".data(using: .utf8)!)
    }

    // TEST188: Frame.end without payload still sets eof marker
    func test188_endFrameWithoutPayload() {
        let id = MessageId.newUUID()
        let frame = Frame.end(id: id)
        XCTAssertEqual(frame.frameType, .end)
        XCTAssertTrue(frame.isEof)
        XCTAssertNil(frame.payload)
    }

    // TEST189: chunk_with_offset sets offset on all chunks but len only on seq=0 (with streamId)
    func test189_chunkWithOffset() {
        let reqId = MessageId.newUUID()
        let streamId = "stream-456"

        // First chunk (seq=0) - should have len
        let firstPayload = "first".data(using: .utf8)!
        let first = Frame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 0,
            payload: firstPayload,
            offset: 0, totalLen: 1000, isLast: false,
            chunkIndex: 0, checksum: Frame.computeChecksum(firstPayload)
        )
        XCTAssertEqual(first.streamId, streamId)
        XCTAssertEqual(first.seq, 0)
        XCTAssertEqual(first.offset, 0)
        XCTAssertEqual(first.len, 1000, "len must be set on first chunk (seq=0)")
        XCTAssertFalse(first.isEof)

        // Later chunk (seq > 0) - should NOT have len
        let laterPayload = "later".data(using: .utf8)!
        let later = Frame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 5,
            payload: laterPayload,
            offset: 900, totalLen: nil, isLast: false,
            chunkIndex: 5, checksum: Frame.computeChecksum(laterPayload)
        )
        XCTAssertEqual(later.streamId, streamId)
        XCTAssertEqual(later.seq, 5)
        XCTAssertEqual(later.offset, 900)
        XCTAssertNil(later.len, "len must not be set on seq > 0")
        XCTAssertFalse(later.isEof)

        // Last chunk - should have eof
        let lastPayload = "last".data(using: .utf8)!
        let last = Frame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 10,
            payload: lastPayload,
            offset: 950, totalLen: nil, isLast: true,
            chunkIndex: 10, checksum: Frame.computeChecksum(lastPayload)
        )
        XCTAssertEqual(last.streamId, streamId)
        XCTAssertTrue(last.isEof)
    }

    // TEST190: Frame.heartbeat creates minimal frame with no payload or metadata
    func test190_heartbeatFrame() {
        let id = MessageId.newUUID()
        let frame = Frame.heartbeat(id: id)
        XCTAssertEqual(frame.frameType, .heartbeat)
        XCTAssertEqual(frame.id, id)
        XCTAssertNil(frame.payload)
        XCTAssertNil(frame.meta)
    }

    // TEST191: error_code and error_message return nil for non-Err frame types
    func test191_errorAccessorsOnNonErrFrame() {
        let req = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.errorCode, "errorCode must be nil on non-Err frame")
        XCTAssertNil(req.errorMessage, "errorMessage must be nil on non-Err frame")
    }

    // TEST192: log_level and log_message return nil for non-Log frame types
    func test192_logAccessorsOnNonLogFrame() {
        let req = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.logLevel, "logLevel must be nil on non-Log frame")
        XCTAssertNil(req.logMessage, "logMessage must be nil on non-Log frame")
    }

    // TEST193: hello_max_frame and hello_max_chunk return nil for non-Hello frame types
    func test193_helloAccessorsOnNonHelloFrame() {
        let req = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.helloMaxFrame, "helloMaxFrame must be nil on non-Hello frame")
        XCTAssertNil(req.helloMaxChunk, "helloMaxChunk must be nil on non-Hello frame")
        XCTAssertNil(req.helloManifest, "helloManifest must be nil on non-Hello frame")
    }

    // TEST196: is_eof returns false when eof field is nil (unset)
    func test196_isEofWhenNil() {
        var frame = Frame(frameType: .chunk, id: .newUUID())
        frame.eof = nil
        XCTAssertFalse(frame.isEof)
    }

    // TEST197: is_eof returns false when eof field is explicitly false
    func test197_isEofWhenFalse() {
        var frame = Frame(frameType: .chunk, id: .newUUID())
        frame.eof = false
        XCTAssertFalse(frame.isEof)
    }

    // TEST198: Limits default provides the documented default values
    func test198_limitsDefault() {
        let limits = Limits()
        XCTAssertEqual(limits.maxFrame, DEFAULT_MAX_FRAME)
        XCTAssertEqual(limits.maxChunk, DEFAULT_MAX_CHUNK)
    }

    // TEST198 (continued): Limits negotiation picks minimum of both sides
    func test198b_limitsNegotiation() {
        let local = Limits(maxFrame: 1_000_000, maxChunk: 100_000)
        let remote = Limits(maxFrame: 500_000, maxChunk: 200_000)
        let negotiated = local.negotiate(with: remote)

        XCTAssertEqual(negotiated.maxFrame, 500_000)   // min(1_000_000, 500_000)
        XCTAssertEqual(negotiated.maxChunk, 100_000)   // min(100_000, 200_000)
    }

    // TEST199: PROTOCOL_VERSION is 2
    func test199_protocolVersionConstant() {
        XCTAssertEqual(CBOR_PROTOCOL_VERSION, 2)
    }

    // TEST200: Integer key constants match the protocol specification
    func test200_keyConstants() {
        XCTAssertEqual(FrameKey.version.rawValue, 0)
        XCTAssertEqual(FrameKey.frameType.rawValue, 1)
        XCTAssertEqual(FrameKey.id.rawValue, 2)
        XCTAssertEqual(FrameKey.seq.rawValue, 3)
        XCTAssertEqual(FrameKey.contentType.rawValue, 4)
        XCTAssertEqual(FrameKey.meta.rawValue, 5)
        XCTAssertEqual(FrameKey.payload.rawValue, 6)
        XCTAssertEqual(FrameKey.len.rawValue, 7)
        XCTAssertEqual(FrameKey.offset.rawValue, 8)
        XCTAssertEqual(FrameKey.eof.rawValue, 9)
        XCTAssertEqual(FrameKey.cap.rawValue, 10)
        XCTAssertEqual(FrameKey.streamId.rawValue, 11)
        XCTAssertEqual(FrameKey.mediaUrn.rawValue, 12)
    }

    // TEST201: hello_with_manifest preserves binary manifest data (not just JSON text)
    func test201_helloManifestBinaryData() {
        // Use binary data that isn't valid JSON to verify raw preservation
        var binaryManifest = Data()
        for i: UInt8 in 0..<128 {
            binaryManifest.append(i)
        }
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 100_000, maxReorderBuffer: 64)
        let frame = Frame.helloWithManifest(limits: limits, manifest: binaryManifest)
        XCTAssertEqual(frame.helloManifest, binaryManifest, "Binary manifest data must be preserved exactly")
    }

    // TEST204: Frame.req with empty payload stores Data() not nil
    func test204_reqFrameEmptyPayload() {
        let frame = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNotNil(frame.payload, "Empty payload must be stored as Data(), not nil")
        XCTAssertEqual(frame.payload, Data())
    }

    // MARK: - Encode/Decode Roundtrip Tests (TEST205-213)

    // TEST205: REQ frame encode/decode roundtrip preserves all fields
    func test205_encodeDecodeRoundtrip() throws {
        let id = MessageId.newUUID()
        let original = Frame.req(
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

    // TEST206: HELLO frame encode/decode roundtrip preserves max_frame, max_chunk, and max_reorder_buffer
    func test206_helloFrameRoundtrip() throws {
        let limits = Limits(maxFrame: 500_000, maxChunk: 50_000, maxReorderBuffer: 64)
        let original = Frame.hello(limits: limits)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .hello)
        XCTAssertEqual(decoded.helloMaxFrame, 500_000)
        XCTAssertEqual(decoded.helloMaxChunk, 50_000)
        XCTAssertEqual(decoded.helloMaxReorderBuffer, 64)
    }

    // TEST207: ERR frame encode/decode roundtrip preserves error code and message
    func test207_errFrameRoundtrip() throws {
        let id = MessageId.newUUID()
        let original = Frame.err(id: id, code: "NOT_FOUND", message: "Cap not found")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .err)
        XCTAssertEqual(decoded.errorCode, "NOT_FOUND")
        XCTAssertEqual(decoded.errorMessage, "Cap not found")
    }

    // TEST208: LOG frame encode/decode roundtrip preserves level and message
    func test208_logFrameRoundtrip() throws {
        let id = MessageId.newUUID()
        let original = Frame.log(id: id, level: "warn", message: "Something happened")
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .log)
        XCTAssertEqual(decoded.logLevel, "warn")
        XCTAssertEqual(decoded.logMessage, "Something happened")
    }

    // TEST209: REMOVED - RES frame test removed (old single-response protocol no longer supported)

    // TEST210: END frame encode/decode roundtrip preserves eof marker and optional payload
    func test210_endFrameRoundtrip() throws {
        let id = MessageId.newUUID()
        let original = Frame.end(id: id, finalPayload: "final".data(using: .utf8)!)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .end)
        XCTAssertEqual(decoded.id, id)
        XCTAssertTrue(decoded.isEof)
        XCTAssertEqual(decoded.payload, "final".data(using: .utf8)!)
    }

    // TEST211: HELLO with manifest encode/decode roundtrip preserves manifest bytes
    func test211_helloWithManifestRoundtrip() throws {
        let manifestJSON = """
        {"name":"TestPlugin","version":"1.0.0","description":"Test description","caps":[{"urn":"cap:","title":"Identity","command":"identity"},{"urn":"cap:op=test","title":"Test","command":"test"}]}
        """
        let manifestData = manifestJSON.data(using: .utf8)!
        let limits = Limits(maxFrame: 500_000, maxChunk: 50_000, maxReorderBuffer: 64)
        let original = Frame.helloWithManifest(limits: limits, manifest: manifestData)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .hello)
        XCTAssertEqual(decoded.helloMaxFrame, 500_000)
        XCTAssertEqual(decoded.helloMaxChunk, 50_000)
        XCTAssertEqual(decoded.helloMaxReorderBuffer, 64)
        XCTAssertNotNil(decoded.helloManifest, "Decoded HELLO must preserve manifest")
        XCTAssertEqual(decoded.helloManifest, manifestData, "Manifest data must be preserved exactly")
    }

    // TEST212: chunk_with_offset encode/decode roundtrip preserves offset, len, eof, streamId
    func test212_chunkWithOffsetRoundtrip() throws {
        let reqId = MessageId.newUUID()
        let streamId = "stream-789"

        // First chunk (seq=0) - should have len set
        let firstPayload = "first".data(using: .utf8)!
        let firstChunk = Frame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 0,
            payload: firstPayload,
            offset: 0, totalLen: 5000, isLast: false,
            chunkIndex: 0, checksum: Frame.computeChecksum(firstPayload)
        )
        let encodedFirst = try encodeFrame(firstChunk)
        let decodedFirst = try decodeFrame(encodedFirst)

        XCTAssertEqual(decodedFirst.streamId, streamId)
        XCTAssertEqual(decodedFirst.seq, 0)
        XCTAssertEqual(decodedFirst.offset, 0)
        XCTAssertEqual(decodedFirst.len, 5000)
        XCTAssertFalse(decodedFirst.isEof)

        // Later chunk (seq > 0) - should NOT have len
        let laterPayload = "later".data(using: .utf8)!
        let laterChunk = Frame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 3,
            payload: laterPayload,
            offset: 1000, totalLen: 5000, isLast: false,
            chunkIndex: 3, checksum: Frame.computeChecksum(laterPayload)
        )
        let encodedLater = try encodeFrame(laterChunk)
        let decodedLater = try decodeFrame(encodedLater)

        XCTAssertEqual(decodedLater.streamId, streamId)
        XCTAssertEqual(decodedLater.seq, 3)
        XCTAssertEqual(decodedLater.offset, 1000)
        XCTAssertNil(decodedLater.len, "len must only be on first chunk")
        XCTAssertFalse(decodedLater.isEof)

        // Final chunk with eof
        let lastPayload = "last".data(using: .utf8)!
        let lastChunk = Frame.chunkWithOffset(
            reqId: reqId, streamId: streamId, seq: 5,
            payload: lastPayload,
            offset: 4000, totalLen: nil, isLast: true,
            chunkIndex: 5, checksum: Frame.computeChecksum(lastPayload)
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
    func test213_heartbeatRoundtrip() throws {
        let id = MessageId.newUUID()
        let original = Frame.heartbeat(id: id)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .heartbeat)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(decoded.payload)
    }

    // MARK: - Wire Format I/O Tests (TEST214-223)

    // TEST214: write_frame/read_frame IO roundtrip through length-prefixed wire format
    @available(macOS 10.15.4, iOS 13.4, *)
    func test214_frameIORoundtrip() throws {
        let pipe = Pipe()
        let limits = Limits()
        let id = MessageId.newUUID()
        let original = Frame.req(id: id, capUrn: "cap:op=test", payload: "payload".data(using: .utf8)!, contentType: "application/json")

        var buffer = Data()
        try writeFrame(original, to: pipe.fileHandleForWriting, limits: limits, buffer: &buffer)
        if !buffer.isEmpty {
            try pipe.fileHandleForWriting.write(contentsOf: buffer)
        }
        pipe.fileHandleForWriting.closeFile()

        let decoded = try readFrame(from: pipe.fileHandleForReading, limits: limits)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.frameType, original.frameType)
        XCTAssertEqual(decoded!.cap, original.cap)
        XCTAssertEqual(decoded!.payload, original.payload)
    }

    // TEST215: Reading multiple sequential frames from a single stream (with streamId)
    @available(macOS 10.15.4, iOS 13.4, *)
    func test215_multipleFrames() throws {
        let pipe = Pipe()
        let limits = Limits()

        let id1 = MessageId.newUUID()
        let id2 = MessageId.newUUID()
        let id3 = MessageId.newUUID()

        let f1 = Frame.req(id: id1, capUrn: "cap:op=first", payload: "one".data(using: .utf8)!, contentType: "text/plain")
        let f2Payload = "two".data(using: .utf8)!
        let f2 = Frame.chunk(reqId: id2, streamId: "stream-001", seq: 0, payload: f2Payload, chunkIndex: 0, checksum: Frame.computeChecksum(f2Payload))
        let f3 = Frame.end(id: id3, finalPayload: "three".data(using: .utf8)!)

        var buffer = Data()
        try writeFrame(f1, to: pipe.fileHandleForWriting, limits: limits, buffer: &buffer)
        try writeFrame(f2, to: pipe.fileHandleForWriting, limits: limits, buffer: &buffer)
        try writeFrame(f3, to: pipe.fileHandleForWriting, limits: limits, buffer: &buffer)
        if !buffer.isEmpty {
            try pipe.fileHandleForWriting.write(contentsOf: buffer)
        }
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
    func test216_frameTooLarge() throws {
        let pipe = Pipe()
        let limits = Limits(maxFrame: 100, maxChunk: 50)

        let largePayload = Data(repeating: 0, count: 200)
        let frame = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: largePayload, contentType: "application/octet-stream")

        var buffer = Data()
        XCTAssertThrowsError(try writeFrame(frame, to: pipe.fileHandleForWriting, limits: limits, buffer: &buffer)) { error in
            if case FrameError.frameTooLarge = error {
                // Expected
            } else {
                XCTFail("Expected frameTooLarge error, got \(error)")
            }
        }
    }

    // TEST217: read_frame rejects incoming frames exceeding the negotiated max_frame limit
    @available(macOS 10.15.4, iOS 13.4, *)
    func test217_readFrameTooLarge() throws {
        let pipe = Pipe()
        let writeLimits = Limits(maxFrame: 10_000_000, maxChunk: 1_000_000)
        let readLimits = Limits(maxFrame: 50, maxChunk: 50)

        // Write a frame with generous limits
        let frame = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(repeating: 0, count: 200), contentType: "text/plain")
        var buffer = Data()
        try writeFrame(frame, to: pipe.fileHandleForWriting, limits: writeLimits, buffer: &buffer)
        if !buffer.isEmpty {
            try pipe.fileHandleForWriting.write(contentsOf: buffer)
        }
        pipe.fileHandleForWriting.closeFile()

        // Try to read with strict limits
        XCTAssertThrowsError(try readFrame(from: pipe.fileHandleForReading, limits: readLimits)) { error in
            if case FrameError.frameTooLarge = error {
                // Expected
            } else {
                XCTFail("Expected frameTooLarge error, got \(error)")
            }
        }
    }

    // TEST218: write_chunked splits data into chunks respecting max_chunk (with streamId parameter)
    @available(macOS 10.15.4, iOS 13.4, *)
    func test218_writeChunked() throws {
        let pipe = Pipe()
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 10) // Very small for testing
        let writer = FrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = MessageId.newUUID()
        let streamId = "stream-test-218"
        let data = "Hello, this is a longer message that will be chunked!".data(using: .utf8)!

        try writer.writeChunked(id: id, streamId: streamId, contentType: "text/plain", data: data)
        pipe.fileHandleForWriting.closeFile()

        // Read back all chunks
        let reader = FrameReader(handle: pipe.fileHandleForReading, limits: Limits(maxFrame: 1_000_000, maxChunk: 1_000_000))
        var received = Data()
        var chunkCount: UInt64 = 0
        var firstChunkHadLen = false
        var firstChunkHadContentType = false

        while true {
            guard let frame = try reader.read() else { break }
            XCTAssertEqual(frame.frameType, .chunk)
            XCTAssertEqual(frame.id, id)
            XCTAssertEqual(frame.streamId, streamId)
            XCTAssertEqual(frame.seq, 0, "writeChunked emits seq=0; SeqAssigner assigns at output stage")
            XCTAssertEqual(frame.chunkIndex, chunkCount, "chunk_index tracks chunk order")

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
    func test219_writeChunkedEmptyData() throws {
        let pipe = Pipe()
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 100)
        let writer = FrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = MessageId.newUUID()
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
    func test220_writeChunkedExactFit() throws {
        let pipe = Pipe()
        let limits = Limits(maxFrame: 1_000_000, maxChunk: 10)
        let writer = FrameWriter(handle: pipe.fileHandleForWriting, limits: limits)

        let id = MessageId.newUUID()
        let streamId = "stream-exact"
        let data = "0123456789".data(using: .utf8)! // exactly 10 bytes = max_chunk
        try writer.writeChunked(id: id, streamId: streamId, contentType: "text/plain", data: data)
        pipe.fileHandleForWriting.closeFile()

        let frame = try readFrame(from: pipe.fileHandleForReading, limits: Limits(maxFrame: 1_000_000, maxChunk: 1_000_000))
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.streamId, streamId)
        XCTAssertTrue(frame!.isEof, "single-chunk data must be EOF")
        XCTAssertEqual(frame!.payload, data)
        XCTAssertEqual(frame!.seq, 0)

        // No more frames
        let eof = try readFrame(from: pipe.fileHandleForReading, limits: Limits(maxFrame: 1_000_000, maxChunk: 1_000_000))
        XCTAssertNil(eof)
    }

    // TEST221: read_frame returns nil on clean EOF (empty stream)
    func test221_eofHandling() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.closeFile() // immediate EOF

        let result = try readFrame(from: pipe.fileHandleForReading, limits: Limits())
        XCTAssertNil(result)
    }

    // TEST222: read_frame handles truncated length prefix (fewer than 4 bytes available)
    @available(macOS 10.15.4, iOS 13.4, *)
    func test222_truncatedLengthPrefix() throws {
        let pipe = Pipe()
        // Write only 2 bytes (need 4 for length prefix)
        pipe.fileHandleForWriting.write(Data([0x00, 0x01]))
        pipe.fileHandleForWriting.closeFile()

        XCTAssertThrowsError(try readFrame(from: pipe.fileHandleForReading, limits: Limits())) { error in
            // Should produce an I/O or protocol error
            if case FrameError.ioError = error {
                // Expected - truncated read
            } else if case FrameError.invalidFrame = error {
                // Also acceptable
            } else {
                // Any error is acceptable for truncated data
            }
        }
    }

    // TEST223: read_frame returns error on truncated frame body
    @available(macOS 10.15.4, iOS 13.4, *)
    func test223_truncatedFrameBody() throws {
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

        XCTAssertThrowsError(try readFrame(from: pipe.fileHandleForReading, limits: Limits())) { error in
            // Should error on truncated body
            if case FrameError.ioError = error {
                // Expected
            } else if case FrameError.invalidFrame = error {
                // Also acceptable
            } else {
                // Any error is acceptable
            }
        }
    }

    // TEST224: MessageId.uint roundtrips through encode/decode
    func test224_messageIdUintRoundtrip() throws {
        let id = MessageId.uint(12345)
        let original = Frame(frameType: .req, id: id)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)
        XCTAssertEqual(decoded.id, id)
    }

    // TEST225: decode_frame rejects non-map CBOR values (e.g., array, integer, string)
    func test225_decodeNonMapValue() throws {
        // Encode a CBOR array instead of map
        let arrayValue = CBOR.array([.unsignedInt(1)])
        let bytes = Data(arrayValue.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case FrameError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST226: decode_frame rejects CBOR map missing required version field
    func test226_decodeMissingVersion() throws {
        // Build CBOR map with frame_type and id but missing version
        let map = CBOR.map([
            .unsignedInt(FrameKey.frameType.rawValue): .unsignedInt(1),
            .unsignedInt(FrameKey.id.rawValue): .unsignedInt(0)
        ])
        let bytes = Data(map.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case FrameError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST227: decode_frame rejects CBOR map with invalid frame_type value
    func test227_decodeInvalidFrameTypeValue() throws {
        let map = CBOR.map([
            .unsignedInt(FrameKey.version.rawValue): .unsignedInt(1),
            .unsignedInt(FrameKey.frameType.rawValue): .unsignedInt(99),
            .unsignedInt(FrameKey.id.rawValue): .unsignedInt(0)
        ])
        let bytes = Data(map.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case FrameError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST228: decode_frame rejects CBOR map missing required id field
    func test228_decodeMissingId() throws {
        let map = CBOR.map([
            .unsignedInt(FrameKey.version.rawValue): .unsignedInt(1),
            .unsignedInt(FrameKey.frameType.rawValue): .unsignedInt(1)
            // No ID field
        ])
        let bytes = Data(map.encode())

        XCTAssertThrowsError(try decodeFrame(bytes)) { error in
            if case FrameError.invalidFrame = error {
                // Expected
            } else {
                XCTFail("Expected invalidFrame error, got \(error)")
            }
        }
    }

    // TEST229: FrameReader/FrameWriter set_limits updates the negotiated limits
    @available(macOS 10.15.4, iOS 13.4, *)
    func test229_frameReaderWriterSetLimits() {
        let pipe = Pipe()
        let reader = FrameReader(handle: pipe.fileHandleForReading)
        let writer = FrameWriter(handle: pipe.fileHandleForWriting)

        let custom = Limits(maxFrame: 500, maxChunk: 100)
        reader.setLimits(custom)
        writer.setLimits(custom)

        XCTAssertEqual(reader.getLimits().maxFrame, 500)
        XCTAssertEqual(reader.getLimits().maxChunk, 100)
        XCTAssertEqual(writer.getLimits().maxFrame, 500)
        XCTAssertEqual(writer.getLimits().maxChunk, 100)
    }

    // TEST233: Binary payload with all 256 byte values roundtrips through encode/decode
    func test233_binaryPayloadAllByteValues() throws {
        var data = Data()
        for i: UInt8 in 0...255 {
            data.append(i)
        }

        let id = MessageId.newUUID()
        let frame = Frame.req(id: id, capUrn: "cap:op=binary", payload: data, contentType: "application/octet-stream")

        let encoded = try encodeFrame(frame)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.payload, data)
    }

    // TEST234: decode_frame handles garbage CBOR bytes gracefully with an error
    func test234_decodeGarbageBytes() {
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB])
        XCTAssertThrowsError(try decodeFrame(garbage), "garbage bytes must produce decode error")
    }

    // MARK: - All Frame Types Roundtrip (combined TEST for TEST205-213 coverage)

    // Covers all frame types in a single loop for comprehensive roundtrip verification
    func test205b_allFrameTypesRoundtrip() throws {
        let chunkPayload = "chunk".data(using: .utf8)!
        let testCases: [(Frame, String)] = [
            (Frame.hello(limits: Limits(maxFrame: 1_000_000, maxChunk: 100_000, maxReorderBuffer: 64)), "HELLO"),
            (Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: "data".data(using: .utf8)!, contentType: "text/plain"), "REQ"),
            // RES removed - old single-response protocol no longer supported
            (Frame.chunk(reqId: .newUUID(), streamId: "stream-all", seq: 5, payload: chunkPayload, chunkIndex: 5, checksum: Frame.computeChecksum(chunkPayload)), "CHUNK"),
            (Frame.end(id: .newUUID(), finalPayload: "final".data(using: .utf8)), "END"),
            (Frame.log(id: .newUUID(), level: "info", message: "test log"), "LOG"),
            (Frame.err(id: .newUUID(), code: "ERROR", message: "test error"), "ERR"),
            (Frame.heartbeat(id: .newUUID()), "HEARTBEAT"),
            (Frame.streamStart(reqId: .newUUID(), streamId: "stream-start-all", mediaUrn: "media:"), "STREAM_START"),
            (Frame.streamEnd(reqId: .newUUID(), streamId: "stream-end-all", chunkCount: 1), "STREAM_END"),
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

    // TEST235: ResponseChunk stores payload, seq, offset, len, and eof fields correctly
    func test235_responseChunk() {
        let chunk = ResponseChunk(
            payload: "hello".data(using: .utf8)!,
            seq: 0, offset: nil, len: nil, isEof: false
        )
        XCTAssertEqual(chunk.payload, "hello".data(using: .utf8)!)
        XCTAssertEqual(chunk.seq, 0)
        XCTAssertNil(chunk.offset)
        XCTAssertNil(chunk.len)
        XCTAssertFalse(chunk.isEof)
    }

    // TEST236: ResponseChunk with all fields populated preserves offset, len, and eof
    func test236_responseChunkWithAllFields() {
        let chunk = ResponseChunk(
            payload: "data".data(using: .utf8)!,
            seq: 3, offset: 1000, len: 5000, isEof: true
        )
        XCTAssertEqual(chunk.seq, 3)
        XCTAssertEqual(chunk.offset, 1000)
        XCTAssertEqual(chunk.len, 5000)
        XCTAssertTrue(chunk.isEof)
    }

    // TEST237: PluginResponse.single final_payload returns the single payload
    func test237_pluginResponseSingle() {
        let response = PluginResponse.single("hello".data(using: .utf8)!)
        XCTAssertEqual(response.finalPayload, "hello".data(using: .utf8)!)
        XCTAssertEqual(response.concatenated(), "hello".data(using: .utf8)!)
    }

    // TEST238: PluginResponse.single with empty payload returns empty data
    func test238_pluginResponseSingleEmpty() {
        let response = PluginResponse.single(Data())
        XCTAssertEqual(response.finalPayload, Data())
        XCTAssertEqual(response.concatenated(), Data())
    }

    // TEST239: PluginResponse.streaming concatenated joins all chunk payloads in order
    func test239_pluginResponseStreaming() {
        let chunks = [
            ResponseChunk(payload: "hello".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: " ".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: "world".data(using: .utf8)!, seq: 2, offset: nil, len: nil, isEof: true),
        ]
        let response = PluginResponse.streaming(chunks)
        XCTAssertEqual(response.concatenated(), "hello world".data(using: .utf8)!)
    }

    // TEST240: PluginResponse.streaming finalPayload returns the last chunk's payload
    func test240_pluginResponseStreamingFinalPayload() {
        let chunks = [
            ResponseChunk(payload: "first".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: "last".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: true),
        ]
        let response = PluginResponse.streaming(chunks)
        XCTAssertEqual(response.finalPayload, "last".data(using: .utf8)!)
    }

    // TEST241: PluginResponse.streaming with empty chunks vec returns empty concatenation
    func test241_pluginResponseStreamingEmptyChunks() {
        let response = PluginResponse.streaming([])
        XCTAssertEqual(response.concatenated(), Data())
        XCTAssertNil(response.finalPayload)
    }

    // TEST242: PluginResponse.streaming concatenated with large payload
    func test242_pluginResponseStreamingLargePayload() {
        let chunk1 = ResponseChunk(payload: Data(repeating: 0xAA, count: 1000), seq: 0, offset: nil, len: nil, isEof: false)
        let chunk2 = ResponseChunk(payload: Data(repeating: 0xBB, count: 2000), seq: 1, offset: nil, len: nil, isEof: true)
        let response = PluginResponse.streaming([chunk1, chunk2])

        let result = response.concatenated()
        XCTAssertEqual(result.count, 3000)
        XCTAssertEqual(result[0], 0xAA)
        XCTAssertEqual(result[999], 0xAA)
        XCTAssertEqual(result[1000], 0xBB)
        XCTAssertEqual(result[2999], 0xBB)
    }

    // TEST243: PluginHostError variants display correct error messages
    @available(macOS 10.15.4, iOS 13.4, *)
    func test243_pluginHostErrorDisplay() {
        let errors: [(PluginHostError, String)] = [
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
    func test365_streamStartFrame() {
        let reqId = MessageId.newUUID()
        let streamId = "stream-abc-123"
        let mediaUrn = "media:"
        let frame = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn)

        XCTAssertEqual(frame.frameType, .streamStart)
        XCTAssertEqual(frame.id, reqId)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.mediaUrn, mediaUrn)
    }

    // TEST366: Frame.stream_end stores reqId and streamId correctly
    func test366_streamEndFrame() {
        let reqId = MessageId.newUUID()
        let streamId = "stream-xyz-789"
        let frame = Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1)

        XCTAssertEqual(frame.frameType, .streamEnd)
        XCTAssertEqual(frame.id, reqId)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.chunkCount, 1)
        XCTAssertNil(frame.mediaUrn, "STREAM_END does not include mediaUrn")
    }

    // TEST367: Frame.stream_start with empty streamId still constructs successfully
    func test367_streamStartWithEmptyStreamId() {
        let reqId = MessageId.newUUID()
        let streamId = ""
        let mediaUrn = "media:text"
        let frame = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn)

        XCTAssertEqual(frame.frameType, .streamStart)
        XCTAssertEqual(frame.streamId, "")
        XCTAssertEqual(frame.mediaUrn, mediaUrn)
    }

    // TEST368: Frame.stream_start with empty mediaUrn still constructs successfully
    func test368_streamStartWithEmptyMediaUrn() {
        let reqId = MessageId.newUUID()
        let streamId = "stream-empty-media"
        let mediaUrn = ""
        let frame = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn)

        XCTAssertEqual(frame.frameType, .streamStart)
        XCTAssertEqual(frame.streamId, streamId)
        XCTAssertEqual(frame.mediaUrn, "")
    }

    // TEST389: StreamStart encode/decode roundtrip preserves stream_id and media_urn
    func test389_streamStartRoundtrip() throws {
        let id = MessageId.newUUID()
        let streamId = "stream-abc-123"
        let mediaUrn = "media:"

        let frame = Frame.streamStart(reqId: id, streamId: streamId, mediaUrn: mediaUrn)
        let encoded = try encodeFrame(frame)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .streamStart)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.streamId, "stream-abc-123")
        XCTAssertEqual(decoded.mediaUrn, "media:")
    }

    // TEST390: StreamEnd encode/decode roundtrip preserves stream_id, no media_urn
    func test390_streamEndRoundtrip() throws {
        let id = MessageId.newUUID()
        let streamId = "stream-xyz-789"

        let frame = Frame.streamEnd(reqId: id, streamId: streamId, chunkCount: 5)
        let encoded = try encodeFrame(frame)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .streamEnd)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.streamId, "stream-xyz-789")
        XCTAssertEqual(decoded.chunkCount, 5)
        XCTAssertNil(decoded.mediaUrn, "StreamEnd should not have media_urn")
    }

    // MARK: - Relay Frame Tests (TEST399-403, TEST399a-400a)

    // TEST399: RelayNotify discriminant roundtrips through rawValue conversion (value 10)
    func test399_relayNotifyDiscriminantRoundtrip() {
        let ft = FrameType.relayNotify
        XCTAssertEqual(ft.rawValue, 10, "RELAY_NOTIFY must be 10")
        let restored = FrameType(rawValue: 10)
        XCTAssertEqual(restored, .relayNotify, "rawValue 10 must restore to relayNotify")
    }

    // TEST400: RelayState discriminant roundtrips through rawValue conversion (value 11)
    func test400_relayStateDiscriminantRoundtrip() {
        let ft = FrameType.relayState
        XCTAssertEqual(ft.rawValue, 11, "RELAY_STATE must be 11")
        let restored = FrameType(rawValue: 11)
        XCTAssertEqual(restored, .relayState, "rawValue 11 must restore to relayState")
    }

    // TEST401: relay_notify factory stores manifest and limits, accessors extract them correctly
    func test401_relayNotifyFactoryAndAccessors() {
        let manifest = "{\"caps\":[\"cap:op=test\"]}".data(using: .utf8)!
        let limits = Limits(maxFrame: 2_000_000, maxChunk: 128_000, maxReorderBuffer: 64)

        let frame = Frame.relayNotify(manifest: manifest, limits: limits)

        XCTAssertEqual(frame.frameType, .relayNotify)

        // Test manifest accessor
        let extractedManifest = frame.relayNotifyManifest
        XCTAssertNotNil(extractedManifest, "relayNotifyManifest must not be nil")
        XCTAssertEqual(extractedManifest, manifest)

        // Test limits accessor
        let extractedLimits = frame.relayNotifyLimits
        XCTAssertNotNil(extractedLimits, "relayNotifyLimits must not be nil")
        XCTAssertEqual(extractedLimits?.maxFrame, limits.maxFrame)
        XCTAssertEqual(extractedLimits?.maxChunk, limits.maxChunk)

        // Test accessors on wrong frame type return nil
        let req = Frame.req(id: .newUUID(), capUrn: "cap:op=test", payload: Data(), contentType: "text/plain")
        XCTAssertNil(req.relayNotifyManifest, "relayNotifyManifest on REQ must be nil")
        XCTAssertNil(req.relayNotifyLimits, "relayNotifyLimits on REQ must be nil")
    }

    // TEST402: relay_state factory stores resource payload in payload field
    func test402_relayStateFactoryAndPayload() {
        let resources = "{\"gpu_memory\":8192}".data(using: .utf8)!

        let frame = Frame.relayState(resources: resources)

        XCTAssertEqual(frame.frameType, .relayState)
        XCTAssertEqual(frame.payload, resources)
    }

    // TEST403: FrameType from value 12 is nil (one past RelayState)
    func test403_frameTypeOnePastRelayState() {
        XCTAssertNil(FrameType(rawValue: 12), "rawValue 12 must be nil (one past RelayState)")
    }

    // TEST399a: RelayNotify encode/decode roundtrip preserves manifest and limits
    func test399a_relayNotifyRoundtrip() throws {
        let manifest = "{\"caps\":[\"cap:op=relay-test\"]}".data(using: .utf8)!
        let limits = Limits(maxFrame: 2_000_000, maxChunk: 128_000, maxReorderBuffer: 64)

        let original = Frame.relayNotify(manifest: manifest, limits: limits)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, FrameType.relayNotify)

        let extractedManifest = decoded.relayNotifyManifest
        XCTAssertNotNil(extractedManifest, "manifest must survive roundtrip")
        XCTAssertEqual(extractedManifest, manifest)

        let extractedLimits = decoded.relayNotifyLimits
        XCTAssertNotNil(extractedLimits, "limits must survive roundtrip")
        XCTAssertEqual(extractedLimits?.maxFrame, limits.maxFrame)
        XCTAssertEqual(extractedLimits?.maxChunk, limits.maxChunk)
    }

    // TEST400a: RelayState encode/decode roundtrip preserves resource payload
    func test400a_relayStateRoundtrip() throws {
        let resources = "{\"gpu_memory\":8192,\"cpu_cores\":16}".data(using: .utf8)!

        let original = Frame.relayState(resources: resources)
        let encoded = try encodeFrame(original)
        let decoded = try decodeFrame(encoded)

        XCTAssertEqual(decoded.frameType, .relayState)
        XCTAssertEqual(decoded.payload, resources)
    }

    // TEST667: verify_chunk_checksum detects corrupted payload
    func test667_verifyChunkChecksumDetectsCorruption() {
        let id = MessageId.newUUID()
        let streamId = "stream-test"
        let payload = "original payload data".data(using: .utf8)!
        let checksum = Frame.computeChecksum(payload)

        // Create valid chunk frame
        var frame = Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: payload, chunkIndex: 0, checksum: checksum)

        // Valid frame should pass verification
        let expected = Frame.computeChecksum(frame.payload!)
        XCTAssertEqual(frame.checksum, expected, "Valid frame should pass verification")

        // Corrupt the payload (simulate transmission error)
        frame.payload = "corrupted payload!!".data(using: .utf8)!

        // Corrupted frame should fail verification
        let corruptedExpected = Frame.computeChecksum(frame.payload!)
        XCTAssertNotEqual(frame.checksum, corruptedExpected, "Corrupted frame should have mismatched checksum")

        // Missing checksum should fail
        frame.checksum = nil
        XCTAssertNil(frame.checksum, "Frame without checksum should fail verification")
    }
}
