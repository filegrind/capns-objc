import Foundation
@preconcurrency import SwiftCBOR

/// Incremental CBOR buffer reader for streaming data
/// Handles partial reads and reassembly of chunked data
public class CborBufferReader: @unchecked Sendable {
    private var buffer = Data()
    private let bufferLock = NSLock()
    private var limits: CborLimits

    /// Temporary file for large payloads (stream-to-disk)
    private var tempFileHandle: FileHandle?
    private var tempFileURL: URL?
    private var expectedLength: UInt64?
    private var receivedLength: UInt64 = 0

    public init(limits: CborLimits = CborLimits()) {
        self.limits = limits
    }

    deinit {
        cleanupTempFile()
    }

    /// Update limits
    public func setLimits(_ limits: CborLimits) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        self.limits = limits
    }

    /// Append data to the buffer
    public func append(_ data: Data) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        buffer.append(data)
    }

    /// Try to extract the next complete frame from the buffer
    /// Returns nil if no complete frame is available yet
    public func extractFrame() throws -> CborFrame? {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        // Need at least 4 bytes for length prefix
        guard buffer.count >= 4 else {
            return nil
        }

        // Read big-endian length
        let bytes = [UInt8](buffer.prefix(4))
        let length = Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))

        // Validate length
        if length > limits.maxFrame || length > MAX_FRAME_HARD_LIMIT {
            throw CborError.frameTooLarge(size: length, max: min(limits.maxFrame, MAX_FRAME_HARD_LIMIT))
        }

        // Check if we have the full payload
        let totalNeeded = 4 + length
        guard buffer.count >= totalNeeded else {
            return nil  // Need more data
        }

        // Extract the packet payload (skip 4-byte length prefix)
        let payloadData = buffer.subdata(in: 4..<totalNeeded)

        // Remove from buffer
        buffer.removeSubrange(0..<totalNeeded)

        return try decodeFrame(payloadData)
    }

    /// Check if buffer has any pending data
    public var hasPendingData: Bool {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return !buffer.isEmpty
    }

    /// Clear the buffer
    public func clear() {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        buffer.removeAll()
        cleanupTempFileInternal()
    }

    // MARK: - Chunk Reassembly

    /// Start assembling a chunked transfer
    /// If the total length exceeds maxChunk, uses disk storage
    public func startChunkedAssembly(totalLength: UInt64) throws {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        expectedLength = totalLength
        receivedLength = 0

        // For large payloads, use temp file to avoid RAM exhaustion
        if totalLength > UInt64(limits.maxChunk) {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + ".cbor_chunk"
            tempFileURL = tempDir.appendingPathComponent(fileName)
            FileManager.default.createFile(atPath: tempFileURL!.path, contents: nil)
            tempFileHandle = try FileHandle(forWritingTo: tempFileURL!)
        }
    }

    /// Add a chunk to the assembly
    @available(macOS 10.15.4, iOS 13.4, *)
    public func addChunk(_ data: Data, offset: UInt64) throws {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        if let handle = tempFileHandle {
            // Stream to disk
            try handle.seek(toOffset: offset)
            try handle.write(contentsOf: data)
            receivedLength += UInt64(data.count)
        } else {
            // In-memory assembly
            // Ensure buffer is large enough
            let neededSize = Int(offset) + data.count
            if buffer.count < neededSize {
                buffer.append(Data(count: neededSize - buffer.count))
            }
            buffer.replaceSubrange(Int(offset)..<(Int(offset) + data.count), with: data)
            receivedLength = max(receivedLength, offset + UInt64(data.count))
        }
    }

    /// Finalize chunked assembly and return the complete data
    public func finalizeChunkedAssembly() throws -> Data {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        if let url = tempFileURL, let handle = tempFileHandle {
            // Read from temp file
            try handle.close()
            let data = try Data(contentsOf: url)
            cleanupTempFileInternal()
            return data
        } else {
            // Return in-memory buffer
            let result = buffer.prefix(Int(receivedLength))
            buffer.removeAll()
            expectedLength = nil
            receivedLength = 0
            return Data(result)
        }
    }

    /// Check if chunked assembly is complete
    public var isChunkedAssemblyComplete: Bool {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        guard let expected = expectedLength else {
            return false
        }
        return receivedLength >= expected
    }

    // MARK: - Private

    private func cleanupTempFile() {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        cleanupTempFileInternal()
    }

    private func cleanupTempFileInternal() {
        if let handle = tempFileHandle {
            try? handle.close()
            tempFileHandle = nil
        }
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
        expectedLength = nil
        receivedLength = 0
    }
}

// MARK: - Chunk Assembler

/// Assembles chunks into complete payloads
/// Tracks multiple concurrent streams by message ID
@available(macOS 10.15.4, iOS 13.4, *)
public class CborChunkAssembler: @unchecked Sendable {
    private var streams: [CborMessageId: ChunkStream] = [:]
    private let streamsLock = NSLock()
    private let limits: CborLimits

    private struct ChunkStream {
        var buffer: CborBufferReader
        var expectedLength: UInt64?
        var receivedChunks: Set<UInt64> = []
        var contentType: String?
        var isComplete: Bool = false
    }

    public init(limits: CborLimits = CborLimits()) {
        self.limits = limits
    }

    /// Process a CHUNK frame and return complete data if assembly is done
    public func processChunk(_ frame: CborFrame) throws -> Data? {
        guard frame.frameType == .chunk else {
            throw CborError.invalidFrame("Expected CHUNK frame")
        }

        streamsLock.lock()
        defer { streamsLock.unlock() }

        // Get or create stream
        var stream = streams[frame.id] ?? ChunkStream(buffer: CborBufferReader(limits: limits))

        // First chunk - start assembly
        if frame.seq == 0 {
            if let len = frame.len {
                try stream.buffer.startChunkedAssembly(totalLength: len)
                stream.expectedLength = len
            }
            stream.contentType = frame.contentType
        }

        // Add chunk data
        if let payload = frame.payload, let offset = frame.offset {
            try stream.buffer.addChunk(payload, offset: offset)
        }

        stream.receivedChunks.insert(frame.seq)

        // Check if complete
        if frame.isEof {
            stream.isComplete = true
        }

        streams[frame.id] = stream

        // If complete, finalize and return
        if stream.isComplete && (stream.expectedLength == nil || stream.buffer.isChunkedAssemblyComplete) {
            let data = try stream.buffer.finalizeChunkedAssembly()
            streams.removeValue(forKey: frame.id)
            return data
        }

        return nil
    }

    /// Check if we have pending data for a message ID
    public func hasPendingStream(id: CborMessageId) -> Bool {
        streamsLock.lock()
        defer { streamsLock.unlock() }
        return streams[id] != nil
    }

    /// Cancel and cleanup a stream
    public func cancelStream(id: CborMessageId) {
        streamsLock.lock()
        defer { streamsLock.unlock() }
        streams.removeValue(forKey: id)
    }

    /// Cleanup all streams
    public func cleanup() {
        streamsLock.lock()
        defer { streamsLock.unlock() }
        streams.removeAll()
    }
}
