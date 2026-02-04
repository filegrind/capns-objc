import Foundation
@preconcurrency import SwiftCBOR

/// Protocol version. Always 1 for this implementation.
public let CBOR_PROTOCOL_VERSION: UInt8 = 1

/// Default maximum frame size (1 MB)
public let DEFAULT_MAX_FRAME: Int = 1_048_576

/// Default maximum chunk size (256 KB)
public let DEFAULT_MAX_CHUNK: Int = 262_144

/// Hard limit for frame size (16 MB) - prevents memory exhaustion
public let MAX_FRAME_HARD_LIMIT: Int = 16 * 1024 * 1024

/// Frame type discriminator
public enum CborFrameType: UInt8, Sendable {
    /// Handshake frame for negotiating limits
    case hello = 0
    /// Request to invoke a cap
    case req = 1
    /// Single complete response
    case res = 2
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
}

/// Message ID - either a 16-byte UUID or a simple integer
public enum CborMessageId: Equatable, Hashable, Sendable {
    case uuid(Data)
    case uint(UInt64)

    /// Create a new random UUID message ID
    public static func newUUID() -> CborMessageId {
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
public struct CborLimits: Sendable {
    /// Maximum frame size in bytes
    public var maxFrame: Int
    /// Maximum chunk payload size in bytes
    public var maxChunk: Int

    public init(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) {
        self.maxFrame = maxFrame
        self.maxChunk = maxChunk
    }

    /// Negotiate minimum of both limits
    public func negotiate(with other: CborLimits) -> CborLimits {
        return CborLimits(
            maxFrame: min(self.maxFrame, other.maxFrame),
            maxChunk: min(self.maxChunk, other.maxChunk)
        )
    }
}

/// A CBOR protocol frame
public struct CborFrame: @unchecked Sendable {
    /// Protocol version (always 1)
    public var version: UInt8 = CBOR_PROTOCOL_VERSION
    /// Frame type
    public var frameType: CborFrameType
    /// Message ID for correlation
    public var id: CborMessageId
    /// Sequence number within a stream
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

    public init(frameType: CborFrameType, id: CborMessageId) {
        self.frameType = frameType
        self.id = id
    }

    // MARK: - Factory Methods

    /// Create a HELLO frame for handshake
    public static func hello(maxFrame: Int, maxChunk: Int) -> CborFrame {
        var frame = CborFrame(frameType: .hello, id: .uint(0))
        frame.meta = [
            "max_frame": .unsignedInt(UInt64(maxFrame)),
            "max_chunk": .unsignedInt(UInt64(maxChunk)),
            "version": .unsignedInt(UInt64(CBOR_PROTOCOL_VERSION))
        ]
        return frame
    }

    /// Create a REQ frame for invoking a cap
    public static func req(id: CborMessageId, capUrn: String, payload: Data, contentType: String) -> CborFrame {
        var frame = CborFrame(frameType: .req, id: id)
        frame.cap = capUrn
        frame.payload = payload
        frame.contentType = contentType
        return frame
    }

    /// Create a RES frame for a single response
    public static func res(id: CborMessageId, payload: Data, contentType: String) -> CborFrame {
        var frame = CborFrame(frameType: .res, id: id)
        frame.payload = payload
        frame.contentType = contentType
        return frame
    }

    /// Create a CHUNK frame for streaming
    public static func chunk(id: CborMessageId, seq: UInt64, payload: Data) -> CborFrame {
        var frame = CborFrame(frameType: .chunk, id: id)
        frame.seq = seq
        frame.payload = payload
        return frame
    }

    /// Create a CHUNK frame with offset info (for large binary transfers)
    public static func chunkWithOffset(
        id: CborMessageId,
        seq: UInt64,
        payload: Data,
        offset: UInt64,
        totalLen: UInt64?,
        isLast: Bool
    ) -> CborFrame {
        var frame = CborFrame(frameType: .chunk, id: id)
        frame.seq = seq
        frame.payload = payload
        frame.offset = offset
        if seq == 0 {
            frame.len = totalLen
        }
        if isLast {
            frame.eof = true
        }
        return frame
    }

    /// Create an END frame to mark stream completion
    public static func end(id: CborMessageId, finalPayload: Data? = nil) -> CborFrame {
        var frame = CborFrame(frameType: .end, id: id)
        frame.payload = finalPayload
        frame.eof = true
        return frame
    }

    /// Create a LOG frame for progress/status
    public static func log(id: CborMessageId, level: String, message: String) -> CborFrame {
        var frame = CborFrame(frameType: .log, id: id)
        frame.meta = [
            "level": .utf8String(level),
            "message": .utf8String(message)
        ]
        return frame
    }

    /// Create an ERR frame
    public static func err(id: CborMessageId, code: String, message: String) -> CborFrame {
        var frame = CborFrame(frameType: .err, id: id)
        frame.meta = [
            "code": .utf8String(code),
            "message": .utf8String(message)
        ]
        return frame
    }

    /// Create a HEARTBEAT frame for health monitoring.
    /// Either side can send; receiver must respond with HEARTBEAT using the same ID.
    public static func heartbeat(id: CborMessageId) -> CborFrame {
        return CborFrame(frameType: .heartbeat, id: id)
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
public enum CborFrameKey: UInt64 {
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
}
