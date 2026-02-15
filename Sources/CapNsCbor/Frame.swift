import Foundation
@preconcurrency import SwiftCBOR

/// Protocol version. Version 2: Result-based emitters, negotiated chunk limits, per-request errors.
public let CBOR_PROTOCOL_VERSION: UInt8 = 2

/// Default maximum frame size (3.5 MB) - safe margin below 3.75MB limit
/// Larger payloads automatically use CHUNK frames
public let DEFAULT_MAX_FRAME: Int = 3_670_016

/// Default maximum chunk size (256 KB)
public let DEFAULT_MAX_CHUNK: Int = 262_144

/// Default maximum reorder buffer size (per-flow frame count)
public let DEFAULT_MAX_REORDER_BUFFER: Int = 64

/// Hard limit for frame size (16 MB) - prevents memory exhaustion
public let MAX_FRAME_HARD_LIMIT: Int = 16 * 1024 * 1024

/// Frame type discriminator
public enum FrameType: UInt8, Sendable {
    /// Handshake frame for negotiating limits
    case hello = 0
    /// Request to invoke a cap
    case req = 1
    // res = 2 REMOVED - old single-response protocol no longer supported
    /// Streaming data chunk
    case chunk = 3
    /// Stream complete marker
    case end = 4
    /// Log/progress message
    case log = 5
    /// Error message
    case err = 6
    /// Health monitoring ping/pong - either side can send, receiver must respond with same ID
    case heartbeat = 7
    /// Announce new stream for a request (multiplexed streaming)
    case streamStart = 8
    /// End a specific stream (multiplexed streaming)
    case streamEnd = 9
    /// Relay capability advertisement (slave → master). Carries aggregate manifest + limits.
    case relayNotify = 10
    /// Relay host system resources + cap demands (master → slave). Carries opaque resource payload.
    case relayState = 11
}

/// Message ID - either a 16-byte UUID or a simple integer
public enum MessageId: Equatable, Hashable, Sendable {
    case uuid(Data)
    case uint(UInt64)

    /// Create a new random UUID message ID
    public static func newUUID() -> MessageId {
        return .uuid(UUID().data)
    }

    /// Create from a UUID
    public init(uuid: UUID) {
        self = .uuid(uuid.data)
    }

    /// Create from a UUID string
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self = .uuid(uuid.data)
    }

    /// Convert to UUID if this is a UUID
    public var uuid: UUID? {
        if case .uuid(let data) = self, data.count == 16 {
            return UUID(data: data)
        }
        return nil
    }

    /// Get the UUID string if this is a UUID
    public var uuidString: String? {
        return uuid?.uuidString
    }
}

/// Negotiated protocol limits
public struct Limits: Sendable {
    /// Maximum frame size in bytes
    public var maxFrame: Int
    /// Maximum chunk payload size in bytes
    public var maxChunk: Int
    /// Maximum reorder buffer size per flow (frame count)
    public var maxReorderBuffer: Int

    public init(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK, maxReorderBuffer: Int = DEFAULT_MAX_REORDER_BUFFER) {
        self.maxFrame = maxFrame
        self.maxChunk = maxChunk
        self.maxReorderBuffer = maxReorderBuffer
    }

    /// Negotiate minimum of both limits
    public func negotiate(with other: Limits) -> Limits {
        return Limits(
            maxFrame: min(self.maxFrame, other.maxFrame),
            maxChunk: min(self.maxChunk, other.maxChunk),
            maxReorderBuffer: min(self.maxReorderBuffer, other.maxReorderBuffer)
        )
    }
}

/// A CBOR protocol frame
public struct Frame: @unchecked Sendable {
    /// Protocol version (always 2)
    public var version: UInt8 = CBOR_PROTOCOL_VERSION
    /// Frame type
    public var frameType: FrameType
    /// Message ID for correlation (request ID)
    public var id: MessageId
    /// Routing ID assigned by RelaySwitch for routing decisions
    /// Separates logical request ID (id) from routing concerns
    /// RelaySwitch assigns this when REQ arrives, all response frames carry it
    public var routingId: MessageId?
    /// Stream ID for multiplexed streams (used in STREAM_START, CHUNK, STREAM_END)
    public var streamId: String?
    /// Media URN for stream type identification (used in STREAM_START)
    public var mediaUrn: String?
    /// Sequence number within a flow (per request ID).
    /// Assigned centrally by SeqAssigner at the output stage (writer thread).
    /// Monotonically increasing for all frame types within the same RID.
    public var seq: UInt64 = 0
    /// Content type of payload (MIME-like)
    public var contentType: String?
    /// Metadata map
    public var meta: [String: CBOR]?
    /// Binary payload
    public var payload: Data?
    /// Total length for chunked transfers (first chunk only)
    public var len: UInt64?
    /// Byte offset in chunked stream
    public var offset: UInt64?
    /// End of stream marker
    public var eof: Bool?
    /// Cap URN (for requests)
    public var cap: String?
    /// Chunk sequence index within stream (CHUNK frames only, starts at 0)
    public var chunkIndex: UInt64?
    /// Total chunk count (STREAM_END frames only, by source's reckoning)
    public var chunkCount: UInt64?
    /// FNV-1a checksum of payload (CHUNK frames only)
    public var checksum: UInt64?

    public init(frameType: FrameType, id: MessageId) {
        self.frameType = frameType
        self.id = id
    }

    // MARK: - Factory Methods

    /// Create a HELLO frame for handshake (host side - no manifest)
    public static func hello(limits: Limits) -> Frame {
        var frame = Frame(frameType: .hello, id: .uint(0))
        frame.meta = [
            "max_frame": .unsignedInt(UInt64(limits.maxFrame)),
            "max_chunk": .unsignedInt(UInt64(limits.maxChunk)),
            "max_reorder_buffer": .unsignedInt(UInt64(limits.maxReorderBuffer)),
            "version": .unsignedInt(UInt64(CBOR_PROTOCOL_VERSION))
        ]
        return frame
    }

    /// Create a HELLO frame for handshake with manifest (plugin side)
    /// The manifest is JSON-encoded plugin metadata including name, version, and caps.
    /// This is the ONLY way for plugins to communicate their capabilities.
    public static func helloWithManifest(limits: Limits, manifest: Data) -> Frame {
        var frame = Frame(frameType: .hello, id: .uint(0))
        frame.meta = [
            "max_frame": .unsignedInt(UInt64(limits.maxFrame)),
            "max_chunk": .unsignedInt(UInt64(limits.maxChunk)),
            "max_reorder_buffer": .unsignedInt(UInt64(limits.maxReorderBuffer)),
            "version": .unsignedInt(UInt64(CBOR_PROTOCOL_VERSION)),
            "manifest": .byteString([UInt8](manifest))
        ]
        return frame
    }

    /// Create a REQ frame for invoking a cap
    public static func req(id: MessageId, capUrn: String, payload: Data, contentType: String) -> Frame {
        var frame = Frame(frameType: .req, id: id)
        frame.cap = capUrn
        frame.payload = payload
        frame.contentType = contentType
        return frame
    }

    // Frame.res() REMOVED - old single-response protocol no longer supported
    // Use stream multiplexing: STREAM_START + CHUNK + STREAM_END + END

    /// Create a CHUNK frame for multiplexed streaming.
    /// Each chunk belongs to a specific stream within a request.
    ///
    /// - Parameters:
    ///   - reqId: The request ID this chunk belongs to
    ///   - streamId: The stream ID this chunk belongs to
    ///   - seq: Sequence number within the stream
    ///   - payload: Chunk data
    ///   - chunkIndex: Chunk sequence index (starts at 0)
    ///   - checksum: FNV-1a checksum of payload
    public static func chunk(reqId: MessageId, streamId: String, seq: UInt64, payload: Data, chunkIndex: UInt64, checksum: UInt64) -> Frame {
        var frame = Frame(frameType: .chunk, id: reqId)
        frame.streamId = streamId
        frame.seq = seq
        frame.payload = payload
        frame.chunkIndex = chunkIndex
        frame.checksum = checksum
        return frame
    }

    /// Create a CHUNK frame with offset info (for large binary transfers).
    /// Used for multiplexed streaming with offset tracking.
    public static func chunkWithOffset(
        reqId: MessageId,
        streamId: String,
        seq: UInt64,
        payload: Data,
        offset: UInt64,
        totalLen: UInt64?,
        isLast: Bool,
        chunkIndex: UInt64,
        checksum: UInt64
    ) -> Frame {
        var frame = Frame(frameType: .chunk, id: reqId)
        frame.streamId = streamId
        frame.seq = seq
        frame.payload = payload
        frame.offset = offset
        frame.chunkIndex = chunkIndex
        frame.checksum = checksum
        if chunkIndex == 0 {
            frame.len = totalLen
        }
        if isLast {
            frame.eof = true
        }
        return frame
    }

    /// Create an END frame to mark stream completion
    public static func end(id: MessageId, finalPayload: Data? = nil) -> Frame {
        var frame = Frame(frameType: .end, id: id)
        frame.payload = finalPayload
        frame.eof = true
        return frame
    }

    /// Create a LOG frame for progress/status
    public static func log(id: MessageId, level: String, message: String) -> Frame {
        var frame = Frame(frameType: .log, id: id)
        frame.meta = [
            "level": .utf8String(level),
            "message": .utf8String(message)
        ]
        return frame
    }

    /// Create an ERR frame
    public static func err(id: MessageId, code: String, message: String) -> Frame {
        var frame = Frame(frameType: .err, id: id)
        frame.meta = [
            "code": .utf8String(code),
            "message": .utf8String(message)
        ]
        return frame
    }

    /// Create a HEARTBEAT frame for health monitoring.
    /// Either side can send; receiver must respond with HEARTBEAT using the same ID.
    public static func heartbeat(id: MessageId) -> Frame {
        return Frame(frameType: .heartbeat, id: id)
    }

    /// Create a STREAM_START frame to announce a new stream within a request.
    /// Used for multiplexed streaming - multiple streams can exist per request.
    ///
    /// - Parameters:
    ///   - reqId: The request ID this stream belongs to
    ///   - streamId: Unique ID for this stream (UUID generated by sender)
    ///   - mediaUrn: Media URN identifying the stream's data type
    public static func streamStart(reqId: MessageId, streamId: String, mediaUrn: String) -> Frame {
        var frame = Frame(frameType: .streamStart, id: reqId)
        frame.streamId = streamId
        frame.mediaUrn = mediaUrn
        return frame
    }

    /// Create a STREAM_END frame to mark completion of a specific stream.
    /// After this, any CHUNK for this stream_id is a fatal protocol error.
    ///
    /// - Parameters:
    ///   - reqId: The request ID this stream belongs to
    ///   - streamId: The stream being ended
    ///   - chunkCount: Total number of chunks sent in this stream (by source's reckoning)
    public static func streamEnd(reqId: MessageId, streamId: String, chunkCount: UInt64) -> Frame {
        var frame = Frame(frameType: .streamEnd, id: reqId)
        frame.streamId = streamId
        frame.chunkCount = chunkCount
        return frame
    }

    /// Create a RELAY_NOTIFY frame for capability advertisement (slave → master).
    /// Carries the aggregate manifest and negotiated limits.
    public static func relayNotify(manifest: Data, limits: Limits) -> Frame {
        var frame = Frame(frameType: .relayNotify, id: .uint(0))
        frame.meta = [
            "manifest": CBOR.byteString([UInt8](manifest)),
            "max_frame": CBOR.unsignedInt(UInt64(limits.maxFrame)),
            "max_chunk": CBOR.unsignedInt(UInt64(limits.maxChunk)),
            "max_reorder_buffer": CBOR.unsignedInt(UInt64(limits.maxReorderBuffer)),
        ]
        return frame
    }

    /// Create a RELAY_STATE frame for host system resources + cap demands (master → slave).
    /// Carries an opaque resource payload.
    public static func relayState(resources: Data) -> Frame {
        var frame = Frame(frameType: .relayState, id: .uint(0))
        frame.payload = resources
        return frame
    }

    // MARK: - Accessors

    /// Check if this is the final frame in a stream
    public var isEof: Bool {
        return eof ?? false
    }

    /// Get error code if this is an ERR frame
    public var errorCode: String? {
        guard frameType == .err, let meta = meta, case .utf8String(let s) = meta["code"] else {
            return nil
        }
        return s
    }

    /// Get error message if this is an ERR frame
    public var errorMessage: String? {
        guard frameType == .err, let meta = meta, case .utf8String(let s) = meta["message"] else {
            return nil
        }
        return s
    }

    /// Get log level if this is a LOG frame
    public var logLevel: String? {
        guard frameType == .log, let meta = meta, case .utf8String(let s) = meta["level"] else {
            return nil
        }
        return s
    }

    /// Get log message if this is a LOG frame
    public var logMessage: String? {
        guard frameType == .log, let meta = meta, case .utf8String(let s) = meta["message"] else {
            return nil
        }
        return s
    }

    /// Extract manifest from RELAY_NOTIFY metadata
    public var relayNotifyManifest: Data? {
        guard frameType == .relayNotify, let meta = meta, case .byteString(let bytes) = meta["manifest"] else {
            return nil
        }
        return Data(bytes)
    }

    /// Extract limits from RELAY_NOTIFY metadata
    /// Returns nil if any required field is missing (protocol violation in v2)
    public var relayNotifyLimits: Limits? {
        guard frameType == .relayNotify, let meta = meta,
              case .unsignedInt(let maxFrame) = meta["max_frame"],
              case .unsignedInt(let maxChunk) = meta["max_chunk"],
              case .unsignedInt(let maxReorderBuffer) = meta["max_reorder_buffer"] else {
            return nil
        }
        return Limits(maxFrame: Int(maxFrame), maxChunk: Int(maxChunk), maxReorderBuffer: Int(maxReorderBuffer))
    }

    /// Extract max_frame from HELLO metadata
    public var helloMaxFrame: Int? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["max_frame"] else {
            return nil
        }
        return Int(n)
    }

    /// Extract max_chunk from HELLO metadata
    public var helloMaxChunk: Int? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["max_chunk"] else {
            return nil
        }
        return Int(n)
    }

    /// Extract max_reorder_buffer from HELLO metadata
    /// Returns nil if missing (protocol violation in v2)
    public var helloMaxReorderBuffer: Int? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["max_reorder_buffer"] else {
            return nil
        }
        return Int(n)
    }

    /// Extract manifest from HELLO metadata (plugin side sends this)
    /// Returns nil if no manifest present (host HELLO) or not a HELLO frame.
    /// The manifest is JSON-encoded plugin metadata.
    public var helloManifest: Data? {
        guard frameType == .hello, let meta = meta, case .byteString(let bytes) = meta["manifest"] else {
            return nil
        }
        return Data(bytes)
    }

    // MARK: - Checksum and Flow Control

    /// Compute FNV-1a 64-bit checksum of bytes.
    /// This is a simple, fast hash function suitable for detecting transmission errors.
    public static func computeChecksum(_ data: Data) -> UInt64 {
        let FNV_OFFSET_BASIS: UInt64 = 0xcbf29ce484222325
        let FNV_PRIME: UInt64 = 0x100000001b3

        var hash = FNV_OFFSET_BASIS
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* FNV_PRIME  // wrapping multiply
        }
        return hash
    }

    /// Returns true if this frame type participates in flow ordering (seq tracking).
    /// Non-flow frames (Hello, Heartbeat, RelayNotify, RelayState) bypass seq assignment
    /// and reorder buffers entirely.
    public func isFlowFrame() -> Bool {
        switch frameType {
        case .hello, .heartbeat, .relayNotify, .relayState:
            return false
        default:
            return true
        }
    }
}

// MARK: - UUID Extension

extension UUID {
    var data: Data {
        return withUnsafeBytes(of: uuid) { Data($0) }
    }

    init?(data: Data) {
        guard data.count == 16 else { return nil }
        let bytes = [UInt8](data)
        let uuid = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        self.init(uuid: uuid)
    }
}

/// Integer keys for CBOR map fields (must match Rust side)
public enum FrameKey: UInt64 {
    case version = 0
    case frameType = 1
    case id = 2
    case seq = 3
    case contentType = 4
    case meta = 5
    case payload = 6
    case len = 7
    case offset = 8
    case eof = 9
    case cap = 10
    case streamId = 11
    case mediaUrn = 12
    case routingId = 13
    case chunkIndex = 14
    case chunkCount = 15
    case checksum = 16
}
