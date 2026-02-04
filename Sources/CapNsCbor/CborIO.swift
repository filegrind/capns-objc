import Foundation
@preconcurrency import SwiftCBOR

/// Errors that can occur during CBOR I/O
public enum CborError: Error, @unchecked Sendable {
    case ioError(String)
    case encodeError(String)
    case decodeError(String)
    case frameTooLarge(size: Int, max: Int)
    case invalidFrame(String)
    case unexpectedEof
    case protocolError(String)
    case handshakeFailed(String)
}

extension CborError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .ioError(let msg): return "I/O error: \(msg)"
        case .encodeError(let msg): return "CBOR encode error: \(msg)"
        case .decodeError(let msg): return "CBOR decode error: \(msg)"
        case .frameTooLarge(let size, let max): return "Frame too large: \(size) bytes (max \(max))"
        case .invalidFrame(let msg): return "Invalid frame: \(msg)"
        case .unexpectedEof: return "Unexpected end of stream"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        }
    }
}

// MARK: - Frame Encoding

/// Encode a frame to CBOR bytes
public func encodeFrame(_ frame: CborFrame) throws -> Data {
    var map: [CBOR: CBOR] = [:]

    // Required fields
    map[.unsignedInt(CborFrameKey.version.rawValue)] = .unsignedInt(UInt64(frame.version))
    map[.unsignedInt(CborFrameKey.frameType.rawValue)] = .unsignedInt(UInt64(frame.frameType.rawValue))

    // Message ID
    switch frame.id {
    case .uuid(let data):
        map[.unsignedInt(CborFrameKey.id.rawValue)] = .byteString([UInt8](data))
    case .uint(let n):
        map[.unsignedInt(CborFrameKey.id.rawValue)] = .unsignedInt(n)
    }

    // Sequence number
    map[.unsignedInt(CborFrameKey.seq.rawValue)] = .unsignedInt(frame.seq)

    // Optional fields
    if let ct = frame.contentType {
        map[.unsignedInt(CborFrameKey.contentType.rawValue)] = .utf8String(ct)
    }

    if let meta = frame.meta {
        var metaMap: [CBOR: CBOR] = [:]
        for (k, v) in meta {
            metaMap[.utf8String(k)] = v
        }
        map[.unsignedInt(CborFrameKey.meta.rawValue)] = .map(metaMap)
    }

    if let payload = frame.payload {
        map[.unsignedInt(CborFrameKey.payload.rawValue)] = .byteString([UInt8](payload))
    }

    if let len = frame.len {
        map[.unsignedInt(CborFrameKey.len.rawValue)] = .unsignedInt(len)
    }

    if let offset = frame.offset {
        map[.unsignedInt(CborFrameKey.offset.rawValue)] = .unsignedInt(offset)
    }

    if let eof = frame.eof {
        map[.unsignedInt(CborFrameKey.eof.rawValue)] = .boolean(eof)
    }

    if let cap = frame.cap {
        map[.unsignedInt(CborFrameKey.cap.rawValue)] = .utf8String(cap)
    }

    let cbor = CBOR.map(map)
    return Data(cbor.encode())
}

/// Decode a frame from CBOR bytes
public func decodeFrame(_ data: Data) throws -> CborFrame {
    guard let cbor = try? CBOR.decode([UInt8](data)) else {
        throw CborError.decodeError("Failed to parse CBOR")
    }

    guard case .map(let map) = cbor else {
        throw CborError.invalidFrame("Expected map")
    }

    // Helper to get integer key value
    func getUInt(_ key: CborFrameKey) -> UInt64? {
        if case .unsignedInt(let n) = map[.unsignedInt(key.rawValue)] {
            return n
        }
        return nil
    }

    // Extract required fields
    guard let versionRaw = getUInt(.version) else {
        throw CborError.invalidFrame("Missing version")
    }
    let version = UInt8(versionRaw)

    guard let frameTypeRaw = getUInt(.frameType),
          let frameType = CborFrameType(rawValue: UInt8(frameTypeRaw)) else {
        throw CborError.invalidFrame("Missing or invalid frame_type")
    }

    // Extract ID
    let id: CborMessageId
    if let idValue = map[.unsignedInt(CborFrameKey.id.rawValue)] {
        switch idValue {
        case .byteString(let bytes):
            if bytes.count == 16 {
                id = .uuid(Data(bytes))
            } else {
                id = .uint(0)
            }
        case .unsignedInt(let n):
            id = .uint(n)
        default:
            id = .uint(0)
        }
    } else {
        throw CborError.invalidFrame("Missing id")
    }

    var frame = CborFrame(frameType: frameType, id: id)
    frame.version = version
    frame.seq = getUInt(.seq) ?? 0

    // Optional fields
    if case .utf8String(let s) = map[.unsignedInt(CborFrameKey.contentType.rawValue)] {
        frame.contentType = s
    }

    if case .map(let metaMap) = map[.unsignedInt(CborFrameKey.meta.rawValue)] {
        var meta: [String: CBOR] = [:]
        for (k, v) in metaMap {
            if case .utf8String(let key) = k {
                meta[key] = v
            }
        }
        frame.meta = meta
    }

    if case .byteString(let bytes) = map[.unsignedInt(CborFrameKey.payload.rawValue)] {
        frame.payload = Data(bytes)
    }

    if let len = getUInt(.len) {
        frame.len = len
    }

    if let offset = getUInt(.offset) {
        frame.offset = offset
    }

    if case .boolean(let b) = map[.unsignedInt(CborFrameKey.eof.rawValue)] {
        frame.eof = b
    }

    if case .utf8String(let s) = map[.unsignedInt(CborFrameKey.cap.rawValue)] {
        frame.cap = s
    }

    return frame
}

// MARK: - Length-Prefixed I/O

/// Write a length-prefixed CBOR frame
@available(macOS 10.15.4, iOS 13.4, *)
public func writeFrame(_ frame: CborFrame, to handle: FileHandle, limits: CborLimits) throws {
    let data = try encodeFrame(frame)

    if data.count > limits.maxFrame {
        throw CborError.frameTooLarge(size: data.count, max: limits.maxFrame)
    }

    if data.count > MAX_FRAME_HARD_LIMIT {
        throw CborError.frameTooLarge(size: data.count, max: MAX_FRAME_HARD_LIMIT)
    }

    let length = UInt32(data.count)
    var lengthBytes = Data(count: 4)
    lengthBytes[0] = UInt8((length >> 24) & 0xFF)
    lengthBytes[1] = UInt8((length >> 16) & 0xFF)
    lengthBytes[2] = UInt8((length >> 8) & 0xFF)
    lengthBytes[3] = UInt8(length & 0xFF)

    try handle.write(contentsOf: lengthBytes)
    try handle.write(contentsOf: data)
    // Note: No synchronize() - it fails on pipes and isn't needed
    // Pipe writes are immediately available to the reader
}

/// Read a length-prefixed CBOR frame
/// Returns nil on clean EOF
public func readFrame(from handle: FileHandle, limits: CborLimits) throws -> CborFrame? {
    // Read 4-byte length prefix
    let lengthData = handle.readData(ofLength: 4)

    if lengthData.isEmpty {
        return nil  // Clean EOF
    }

    guard lengthData.count == 4 else {
        throw CborError.unexpectedEof
    }

    let bytes = [UInt8](lengthData)
    let length = Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))

    // Validate length
    if length > limits.maxFrame || length > MAX_FRAME_HARD_LIMIT {
        throw CborError.frameTooLarge(size: length, max: min(limits.maxFrame, MAX_FRAME_HARD_LIMIT))
    }

    // Read payload
    let payloadData = handle.readData(ofLength: length)
    guard payloadData.count == length else {
        throw CborError.unexpectedEof
    }

    return try decodeFrame(payloadData)
}

// MARK: - Frame Reader/Writer Classes

/// CBOR frame reader with incremental decoding
public class CborFrameReader: @unchecked Sendable {
    private let handle: FileHandle
    private var limits: CborLimits
    private let lock = NSLock()

    public init(handle: FileHandle, limits: CborLimits = CborLimits()) {
        self.handle = handle
        self.limits = limits
    }

    /// Update limits (after handshake)
    public func setLimits(_ limits: CborLimits) {
        lock.lock()
        defer { lock.unlock() }
        self.limits = limits
    }

    /// Get current limits
    public func getLimits() -> CborLimits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    /// Read the next frame (blocking)
    public func read() throws -> CborFrame? {
        lock.lock()
        let currentLimits = limits
        lock.unlock()
        return try readFrame(from: handle, limits: currentLimits)
    }
}

/// CBOR frame writer
@available(macOS 10.15.4, iOS 13.4, *)
public class CborFrameWriter: @unchecked Sendable {
    private let handle: FileHandle
    private var limits: CborLimits
    private let lock = NSLock()

    public init(handle: FileHandle, limits: CborLimits = CborLimits()) {
        self.handle = handle
        self.limits = limits
    }

    /// Update limits (after handshake)
    public func setLimits(_ limits: CborLimits) {
        lock.lock()
        defer { lock.unlock() }
        self.limits = limits
    }

    /// Get current limits
    public func getLimits() -> CborLimits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    /// Write a frame
    public func write(_ frame: CborFrame) throws {
        lock.lock()
        let currentLimits = limits
        lock.unlock()
        try writeFrame(frame, to: handle, limits: currentLimits)
    }

    /// Write a large payload as multiple chunks
    public func writeChunked(id: CborMessageId, contentType: String, data: Data) throws {
        lock.lock()
        let currentLimits = limits
        lock.unlock()

        let totalLen = UInt64(data.count)
        let maxChunk = currentLimits.maxChunk

        if data.isEmpty {
            // Empty payload - single chunk with eof
            var frame = CborFrame.chunk(id: id, seq: 0, payload: Data())
            frame.contentType = contentType
            frame.len = 0
            frame.offset = 0
            frame.eof = true
            try writeFrame(frame, to: handle, limits: currentLimits)
            return
        }

        var seq: UInt64 = 0
        var offset = 0

        while offset < data.count {
            let chunkSize = min(maxChunk, data.count - offset)
            let isLast = offset + chunkSize >= data.count

            let chunkData = data.subdata(in: offset..<(offset + chunkSize))

            var frame = CborFrame.chunk(id: id, seq: seq, payload: chunkData)
            frame.offset = UInt64(offset)

            // Set content_type and total len on first chunk
            if seq == 0 {
                frame.contentType = contentType
                frame.len = totalLen
            }

            if isLast {
                frame.eof = true
            }

            try writeFrame(frame, to: handle, limits: currentLimits)

            seq += 1
            offset += chunkSize
        }
    }
}

// MARK: - Handshake

/// Handshake result including manifest (host side - receives plugin's HELLO with manifest)
public struct HandshakeResult: Sendable {
    /// Negotiated protocol limits
    public let limits: CborLimits
    /// Plugin manifest JSON data (from plugin's HELLO response)
    public let manifest: Data?
}

/// Perform HELLO handshake and extract plugin manifest (host side - sends first)
/// Returns HandshakeResult containing negotiated limits and plugin manifest.
@available(macOS 10.15.4, iOS 13.4, *)
public func performHandshakeWithManifest(reader: CborFrameReader, writer: CborFrameWriter) throws -> HandshakeResult {
    // Send our HELLO
    let ourHello = CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK)
    try writer.write(ourHello)

    // Read their HELLO (should include manifest)
    guard let theirFrame = try reader.read() else {
        throw CborError.handshakeFailed("Connection closed before receiving HELLO")
    }

    guard theirFrame.frameType == .hello else {
        throw CborError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
    }

    // Extract manifest - REQUIRED for plugins
    guard let manifest = theirFrame.helloManifest else {
        throw CborError.handshakeFailed("Plugin HELLO missing required manifest")
    }

    // Negotiate minimum of both
    let theirMaxFrame = theirFrame.helloMaxFrame ?? DEFAULT_MAX_FRAME
    let theirMaxChunk = theirFrame.helloMaxChunk ?? DEFAULT_MAX_CHUNK

    let limits = CborLimits(
        maxFrame: min(DEFAULT_MAX_FRAME, theirMaxFrame),
        maxChunk: min(DEFAULT_MAX_CHUNK, theirMaxChunk)
    )

    // Update both reader and writer with negotiated limits
    reader.setLimits(limits)
    writer.setLimits(limits)

    return HandshakeResult(limits: limits, manifest: manifest)
}

/// Accept HELLO handshake with manifest (plugin side - receives first, sends manifest in response)
/// - Parameters:
///   - reader: Frame reader for incoming data
///   - writer: Frame writer for outgoing data
///   - manifest: Plugin manifest JSON data to include in HELLO response
/// - Returns: Negotiated protocol limits
@available(macOS 10.15.4, iOS 13.4, *)
public func acceptHandshakeWithManifest(reader: CborFrameReader, writer: CborFrameWriter, manifest: Data) throws -> CborLimits {
    // Read their HELLO first (host initiates)
    guard let theirFrame = try reader.read() else {
        throw CborError.handshakeFailed("Connection closed before receiving HELLO")
    }

    guard theirFrame.frameType == .hello else {
        throw CborError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
    }

    // Negotiate minimum of both
    let theirMaxFrame = theirFrame.helloMaxFrame ?? DEFAULT_MAX_FRAME
    let theirMaxChunk = theirFrame.helloMaxChunk ?? DEFAULT_MAX_CHUNK

    let limits = CborLimits(
        maxFrame: min(DEFAULT_MAX_FRAME, theirMaxFrame),
        maxChunk: min(DEFAULT_MAX_CHUNK, theirMaxChunk)
    )

    // Send our HELLO with manifest
    let ourHello = CborFrame.hello(maxFrame: limits.maxFrame, maxChunk: limits.maxChunk, manifest: manifest)
    try writer.write(ourHello)

    // Update both reader and writer with negotiated limits
    reader.setLimits(limits)
    writer.setLimits(limits)

    return limits
}

