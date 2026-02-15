import Foundation
@preconcurrency import SwiftCBOR

/// Errors that can occur during CBOR I/O
public enum FrameError: Error, @unchecked Sendable {
    case ioError(String)
    case encodeError(String)
    case decodeError(String)
    case frameTooLarge(size: Int, max: Int)
    case invalidFrame(String)
    case unexpectedEof
    case protocolError(String)
    case handshakeFailed(String)
}

extension FrameError: LocalizedError {
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
public func encodeFrame(_ frame: Frame) throws -> Data {
    var map: [CBOR: CBOR] = [:]

    // Required fields
    map[.unsignedInt(FrameKey.version.rawValue)] = .unsignedInt(UInt64(frame.version))
    map[.unsignedInt(FrameKey.frameType.rawValue)] = .unsignedInt(UInt64(frame.frameType.rawValue))

    // Message ID
    switch frame.id {
    case .uuid(let data):
        map[.unsignedInt(FrameKey.id.rawValue)] = .byteString([UInt8](data))
    case .uint(let n):
        map[.unsignedInt(FrameKey.id.rawValue)] = .unsignedInt(n)
    }

    // Sequence number
    map[.unsignedInt(FrameKey.seq.rawValue)] = .unsignedInt(frame.seq)

    // Optional fields
    if let ct = frame.contentType {
        map[.unsignedInt(FrameKey.contentType.rawValue)] = .utf8String(ct)
    }

    if let meta = frame.meta {
        var metaMap: [CBOR: CBOR] = [:]
        for (k, v) in meta {
            metaMap[.utf8String(k)] = v
        }
        map[.unsignedInt(FrameKey.meta.rawValue)] = .map(metaMap)
    }

    if let payload = frame.payload {
        map[.unsignedInt(FrameKey.payload.rawValue)] = .byteString([UInt8](payload))
    }

    if let len = frame.len {
        map[.unsignedInt(FrameKey.len.rawValue)] = .unsignedInt(len)
    }

    if let offset = frame.offset {
        map[.unsignedInt(FrameKey.offset.rawValue)] = .unsignedInt(offset)
    }

    if let eof = frame.eof {
        map[.unsignedInt(FrameKey.eof.rawValue)] = .boolean(eof)
    }

    if let cap = frame.cap {
        map[.unsignedInt(FrameKey.cap.rawValue)] = .utf8String(cap)
    }

    if let streamId = frame.streamId {
        map[.unsignedInt(FrameKey.streamId.rawValue)] = .utf8String(streamId)
    }

    if let mediaUrn = frame.mediaUrn {
        map[.unsignedInt(FrameKey.mediaUrn.rawValue)] = .utf8String(mediaUrn)
    }

    if let routingId = frame.routingId {
        switch routingId {
        case .uuid(let data):
            map[.unsignedInt(FrameKey.routingId.rawValue)] = .byteString([UInt8](data))
        case .uint(let n):
            map[.unsignedInt(FrameKey.routingId.rawValue)] = .unsignedInt(n)
        }
    }

    if let chunkIndex = frame.chunkIndex {
        map[.unsignedInt(FrameKey.chunkIndex.rawValue)] = .unsignedInt(chunkIndex)
    }

    if let chunkCount = frame.chunkCount {
        map[.unsignedInt(FrameKey.chunkCount.rawValue)] = .unsignedInt(chunkCount)
    }

    if let checksum = frame.checksum {
        map[.unsignedInt(FrameKey.checksum.rawValue)] = .unsignedInt(checksum)
    }

    let cbor = CBOR.map(map)
    return Data(cbor.encode())
}

/// Decode a frame from CBOR bytes
public func decodeFrame(_ data: Data) throws -> Frame {
    guard let cbor = try? CBOR.decode([UInt8](data)) else {
        throw FrameError.decodeError("Failed to parse CBOR")
    }

    guard case .map(let map) = cbor else {
        throw FrameError.invalidFrame("Expected map")
    }

    // Helper to get integer key value
    func getUInt(_ key: FrameKey) -> UInt64? {
        if case .unsignedInt(let n) = map[.unsignedInt(key.rawValue)] {
            return n
        }
        return nil
    }

    // Extract required fields
    guard let versionRaw = getUInt(.version) else {
        throw FrameError.invalidFrame("Missing version")
    }
    let version = UInt8(versionRaw)

    guard let frameTypeRaw = getUInt(.frameType),
          let frameType = FrameType(rawValue: UInt8(frameTypeRaw)) else {
        throw FrameError.invalidFrame("Missing or invalid frame_type")
    }

    // Extract ID
    let id: MessageId
    if let idValue = map[.unsignedInt(FrameKey.id.rawValue)] {
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
        throw FrameError.invalidFrame("Missing id")
    }

    var frame = Frame(frameType: frameType, id: id)
    frame.version = version
    frame.seq = getUInt(.seq) ?? 0

    // Optional fields
    if case .utf8String(let s) = map[.unsignedInt(FrameKey.contentType.rawValue)] {
        frame.contentType = s
    }

    if case .map(let metaMap) = map[.unsignedInt(FrameKey.meta.rawValue)] {
        var meta: [String: CBOR] = [:]
        for (k, v) in metaMap {
            if case .utf8String(let key) = k {
                meta[key] = v
            }
        }
        frame.meta = meta
    }

    if case .byteString(let bytes) = map[.unsignedInt(FrameKey.payload.rawValue)] {
        frame.payload = Data(bytes)
    }

    if let len = getUInt(.len) {
        frame.len = len
    }

    if let offset = getUInt(.offset) {
        frame.offset = offset
    }

    if case .boolean(let b) = map[.unsignedInt(FrameKey.eof.rawValue)] {
        frame.eof = b
    }

    if case .utf8String(let s) = map[.unsignedInt(FrameKey.cap.rawValue)] {
        frame.cap = s
    }

    if case .utf8String(let s) = map[.unsignedInt(FrameKey.streamId.rawValue)] {
        frame.streamId = s
    }

    if case .utf8String(let s) = map[.unsignedInt(FrameKey.mediaUrn.rawValue)] {
        frame.mediaUrn = s
    }

    // Extract routingId
    if let routingIdValue = map[.unsignedInt(FrameKey.routingId.rawValue)] {
        switch routingIdValue {
        case .byteString(let bytes):
            if bytes.count == 16 {
                frame.routingId = .uuid(Data(bytes))
            }
        case .unsignedInt(let n):
            frame.routingId = .uint(n)
        default:
            break
        }
    }

    if let chunkIndex = getUInt(.chunkIndex) {
        frame.chunkIndex = chunkIndex
    }

    if let chunkCount = getUInt(.chunkCount) {
        frame.chunkCount = chunkCount
    }

    if let checksum = getUInt(.checksum) {
        frame.checksum = checksum
    }

    // Protocol v2 validation: CHUNK frames MUST have chunkIndex and checksum
    if frame.frameType == .chunk {
        guard frame.chunkIndex != nil else {
            throw FrameError.protocolError("CHUNK frame missing required chunkIndex field")
        }
        guard frame.checksum != nil else {
            throw FrameError.protocolError("CHUNK frame missing required checksum field")
        }
    }

    // Protocol v2 validation: STREAM_END frames MUST have chunkCount
    if frame.frameType == .streamEnd {
        guard frame.chunkCount != nil else {
            throw FrameError.protocolError("STREAM_END frame missing required chunkCount field")
        }
    }

    return frame
}

// MARK: - Length-Prefixed I/O

/// Write a length-prefixed CBOR frame
@available(macOS 10.15.4, iOS 13.4, *)
public func writeFrame(_ frame: Frame, to handle: FileHandle, limits: Limits) throws {
    let data = try encodeFrame(frame)

    if data.count > limits.maxFrame {
        throw FrameError.frameTooLarge(size: data.count, max: limits.maxFrame)
    }

    if data.count > MAX_FRAME_HARD_LIMIT {
        throw FrameError.frameTooLarge(size: data.count, max: MAX_FRAME_HARD_LIMIT)
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
public func readFrame(from handle: FileHandle, limits: Limits) throws -> Frame? {
    // Read 4-byte length prefix
    let lengthData = handle.readData(ofLength: 4)

    if lengthData.isEmpty {
        return nil  // Clean EOF
    }

    guard lengthData.count == 4 else {
        throw FrameError.unexpectedEof
    }

    let bytes = [UInt8](lengthData)
    let length = Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))

    // Validate length
    if length > limits.maxFrame || length > MAX_FRAME_HARD_LIMIT {
        throw FrameError.frameTooLarge(size: length, max: min(limits.maxFrame, MAX_FRAME_HARD_LIMIT))
    }

    // Read payload
    let payloadData = handle.readData(ofLength: length)
    guard payloadData.count == length else {
        throw FrameError.unexpectedEof
    }

    return try decodeFrame(payloadData)
}

// MARK: - Frame Reader/Writer Classes

/// CBOR frame reader with incremental decoding
public class FrameReader: @unchecked Sendable {
    private let handle: FileHandle
    private var limits: Limits
    private let lock = NSLock()

    public init(handle: FileHandle, limits: Limits = Limits()) {
        self.handle = handle
        self.limits = limits
    }

    /// Update limits (after handshake)
    public func setLimits(_ limits: Limits) {
        lock.lock()
        defer { lock.unlock() }
        self.limits = limits
    }

    /// Get current limits
    public func getLimits() -> Limits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    /// Read the next frame (blocking)
    public func read() throws -> Frame? {
        lock.lock()
        let currentLimits = limits
        lock.unlock()
        return try readFrame(from: handle, limits: currentLimits)
    }
}

/// CBOR frame writer
@available(macOS 10.15.4, iOS 13.4, *)
public class FrameWriter: @unchecked Sendable {
    public let handle: FileHandle
    private var limits: Limits
    private let lock = NSLock()

    public init(handle: FileHandle, limits: Limits = Limits()) {
        self.handle = handle
        self.limits = limits
    }

    /// Update limits (after handshake)
    public func setLimits(_ limits: Limits) {
        lock.lock()
        defer { lock.unlock() }
        self.limits = limits
    }

    /// Get current limits
    public func getLimits() -> Limits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    /// Write a frame
    public func write(_ frame: Frame) throws {
        lock.lock()
        let currentLimits = limits
        lock.unlock()
        try writeFrame(frame, to: handle, limits: currentLimits)
    }

    /// Write a large payload as multiple chunks for multiplexed streaming.
    /// - Parameters:
    ///   - id: Request ID
    ///   - streamId: Stream ID for multiplexing
    ///   - contentType: Content type
    ///   - data: Data to chunk
    public func writeChunked(id: MessageId, streamId: String, contentType: String, data: Data) throws {
        lock.lock()
        let currentLimits = limits
        lock.unlock()

        let totalLen = UInt64(data.count)
        let maxChunk = currentLimits.maxChunk

        if data.isEmpty {
            // Empty payload - single chunk with eof
            let emptyData = Data()
            let checksum = Frame.computeChecksum(emptyData)
            var frame = Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: emptyData, chunkIndex: 0, checksum: checksum)
            frame.contentType = contentType
            frame.len = 0
            frame.offset = 0
            frame.eof = true
            try writeFrame(frame, to: handle, limits: currentLimits)
            return
        }

        var chunkIndex: UInt64 = 0
        var offset = 0

        while offset < data.count {
            let chunkSize = min(maxChunk, data.count - offset)
            let isLast = offset + chunkSize >= data.count

            let chunkData = data.subdata(in: offset..<(offset + chunkSize))
            let checksum = Frame.computeChecksum(chunkData)

            // seq=0 for all chunks - SeqAssigner handles seq assignment at output stage
            var frame = Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: chunkData, chunkIndex: chunkIndex, checksum: checksum)
            frame.offset = UInt64(offset)

            // Set content_type and total len on first chunk (chunk_index-based, not seq-based)
            if chunkIndex == 0 {
                frame.contentType = contentType
                frame.len = totalLen
            }

            if isLast {
                frame.eof = true
            }

            try writeFrame(frame, to: handle, limits: currentLimits)

            chunkIndex += 1
            offset += chunkSize
        }
    }
}

// MARK: - Handshake

/// Handshake result including manifest (host side - receives plugin's HELLO with manifest)
public struct HandshakeResult: Sendable {
    /// Negotiated protocol limits
    public let limits: Limits
    /// Plugin manifest JSON data (from plugin's HELLO response)
    public let manifest: Data?
}

/// Perform HELLO handshake and extract plugin manifest (host side - sends first)
/// Returns HandshakeResult containing negotiated limits and plugin manifest.
@available(macOS 10.15.4, iOS 13.4, *)
public func performHandshakeWithManifest(reader: FrameReader, writer: FrameWriter) throws -> HandshakeResult {
    // Send our HELLO with our current limits
    let ourLimits = writer.getLimits()
    let ourHello = Frame.hello(limits: ourLimits)
    try writer.write(ourHello)

    // Read their HELLO (should include manifest)
    guard let theirFrame = try reader.read() else {
        throw FrameError.handshakeFailed("Connection closed before receiving HELLO")
    }

    guard theirFrame.frameType == .hello else {
        throw FrameError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
    }

    // Extract manifest - REQUIRED for plugins
    guard let manifest = theirFrame.helloManifest else {
        throw FrameError.handshakeFailed("Plugin HELLO missing required manifest")
    }

    // Protocol v2: All three limit fields are REQUIRED
    guard let theirMaxFrame = theirFrame.helloMaxFrame else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_frame")
    }
    guard let theirMaxChunk = theirFrame.helloMaxChunk else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
    }
    guard let theirMaxReorderBuffer = theirFrame.helloMaxReorderBuffer else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
    }

    // Negotiate minimum of both sides
    let limits = Limits(
        maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
        maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
        maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
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
public func acceptHandshakeWithManifest(reader: FrameReader, writer: FrameWriter, manifest: Data) throws -> Limits {
    // Read their HELLO first (host initiates)
    guard let theirFrame = try reader.read() else {
        throw FrameError.handshakeFailed("Connection closed before receiving HELLO")
    }

    guard theirFrame.frameType == .hello else {
        throw FrameError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
    }

    // Protocol v2: All three limit fields are REQUIRED
    guard let theirMaxFrame = theirFrame.helloMaxFrame else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_frame")
    }
    guard let theirMaxChunk = theirFrame.helloMaxChunk else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
    }
    guard let theirMaxReorderBuffer = theirFrame.helloMaxReorderBuffer else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
    }

    // Negotiate minimum of both sides
    let ourLimits = writer.getLimits()
    let limits = Limits(
        maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
        maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
        maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
    )

    // Send our HELLO with manifest and negotiated limits
    let ourHello = Frame.helloWithManifest(limits: ourLimits, manifest: manifest)
    try writer.write(ourHello)

    // Update both reader and writer with negotiated limits
    reader.setLimits(limits)
    writer.setLimits(limits)

    return limits
}

