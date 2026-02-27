//
//  PluginRuntime.swift
//  Bifaci
//
//  Plugin-side runtime for CBOR-based plugin communication.
//
//  This is the ONLY supported way for a plugin to communicate with the host.
//  Swift plugins use this runtime to:
//  1. Perform HELLO handshake with the host
//  2. Register handlers for caps they provide
//  3. Process incoming REQ frames
//  4. Send CHUNK/END/ERR responses
//  5. Respond to HEARTBEAT for health monitoring
//  6. Invoke caps on the host via PeerInvoker (bidirectional communication)
//
//  Usage:
//  ```swift
//  let runtime = PluginRuntime(manifest: manifestData)
//  runtime.register(capUrn: "cap:op=my_op") { payload, emitter, peer in
//      emitter.emitStatus(operation: "processing", details: "Working...")
//      // Optionally invoke host caps via peer.invoke()
//      emitter.emit(chunk: someData)
//      return finalResult
//  }
//  try runtime.run()  // Blocks until stdin closes
//  ```

import Foundation
import CapNs
import TaggedUrn
@preconcurrency import SwiftCBOR
import Glob
import Ops

// MARK: - Error Types

/// Errors specific to PluginRuntime operations
public enum PluginRuntimeError: Error, LocalizedError, @unchecked Sendable {
    case handshakeFailed(String)
    case noHandler(String)
    case handlerError(String)
    case deserializationError(String)
    case serializationError(String)
    case ioError(String)
    case protocolError(String)
    case peerRequestError(String)
    case peerResponseError(String)
    case cliError(String)
    case missingArgument(String)
    case unknownSubcommand(String)
    case manifestError(String)
    case capUrnError(String)

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .noHandler(let cap): return "No handler registered for cap: \(cap)"
        case .handlerError(let msg): return "Handler error: \(msg)"
        case .deserializationError(let msg): return "Deserialization error: \(msg)"
        case .serializationError(let msg): return "Serialization error: \(msg)"
        case .ioError(let msg): return "I/O error: \(msg)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .peerRequestError(let msg): return "Peer request error: \(msg)"
        case .peerResponseError(let msg): return "Peer response error: \(msg)"
        case .cliError(let msg): return "CLI error: \(msg)"
        case .missingArgument(let arg): return "Missing required argument: \(arg)"
        case .unknownSubcommand(let cmd): return "Unknown subcommand: \(cmd)"
        case .manifestError(let msg): return "Manifest error: \(msg)"
        case .capUrnError(let msg): return "Cap URN error: \(msg)"
        }
    }
}

// MARK: - Stream Abstractions
// Stream abstractions hide the frame protocol from handlers.
// Handlers work with streams of CBOR values, not raw frames.

/// Errors that can occur during stream operations.
public enum StreamError: Error {
    case remoteError(code: String, message: String)
    case closed
    case decode(String)
    case io(String)
    case protocolError(String)
}

/// Allows sending frames directly through the output channel.
/// Internal to the runtime — handlers never see this.
protocol FrameSender: Sendable {
    func send(_ frame: Frame) throws
}

/// A single input stream — yields decoded CBOR values from CHUNK frames.
/// Handler never sees Frame, STREAM_START, STREAM_END, checksum, seq, or index.
public final class InputStream: Sequence, @unchecked Sendable {
    private let _mediaUrn: String
    private let rx: UnsafeTransfer<AnyIterator<Result<CBOR, StreamError>>>

    init(mediaUrn: String, rx: AnyIterator<Result<CBOR, StreamError>>) {
        self._mediaUrn = mediaUrn
        self.rx = UnsafeTransfer(rx)
    }

    /// Media URN of this stream (from STREAM_START).
    public var mediaUrn: String {
        _mediaUrn
    }

    /// Collect all chunks into a single byte vector.
    /// Extracts inner bytes from .byteString/.utf8String and concatenates.
    public func collectBytes() throws -> Data {
        var result = Data()
        for itemResult in self {
            let item = try itemResult.get()
            switch item {
            case .byteString(let bytes):
                result.append(contentsOf: bytes)
            case .utf8String(let str):
                result.append(str.data(using: .utf8) ?? Data())
            default:
                // For non-byte types, CBOR-encode them
                let encoded = Data(item.encode())
                result.append(encoded)
            }
        }
        return result
    }

    /// Collect a single CBOR value (expects exactly one chunk).
    public func collectValue() throws -> CBOR {
        guard let first = rx.value.next() else {
            throw StreamError.closed
        }
        return try first.get()
    }

    public func makeIterator() -> AnyIterator<Result<CBOR, StreamError>> {
        rx.value
    }
}

/// The bundle of all input arg streams for one request.
/// Yields InputStream objects as STREAM_START frames arrive from the wire.
/// Returns nil after END frame (all args delivered).
public final class InputPackage: Sequence, @unchecked Sendable {
    private let rx: UnsafeTransfer<AnyIterator<Result<InputStream, StreamError>>>

    init(rx: AnyIterator<Result<InputStream, StreamError>>) {
        self.rx = UnsafeTransfer(rx)
    }

    /// Get the next input stream. Returns nil when all streams delivered (after END).
    public func nextStream() -> Result<InputStream, StreamError>? {
        rx.value.next()
    }

    /// Collect all streams' bytes into a single Data.
    public func collectAllBytes() throws -> Data {
        var all = Data()
        for streamResult in self {
            let stream = try streamResult.get()
            all.append(try stream.collectBytes())
        }
        return all
    }

    /// Collect each stream individually into an array of (mediaUrn, bytes) pairs.
    /// Each stream's bytes are accumulated separately — NOT concatenated.
    public func collectStreams() throws -> [(mediaUrn: String, bytes: Data)] {
        var result: [(mediaUrn: String, bytes: Data)] = []
        for streamResult in self {
            let stream = try streamResult.get()
            let urn = stream.mediaUrn
            let bytes = try stream.collectBytes()
            result.append((mediaUrn: urn, bytes: bytes))
        }
        return result
    }

    public func makeIterator() -> AnyIterator<Result<InputStream, StreamError>> {
        rx.value
    }
}

/// Find a stream's bytes by exact URN equivalence (order-independent tag matching).
/// Uses CSMediaUrn.isEquivalentTo — matches only if both URNs have the exact same tag set.
public func findStream(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) -> Data? {
    guard let target = try? CSMediaUrn.fromString(mediaUrn) else { return nil }
    for (urnStr, bytes) in streams {
        guard let urn = try? CSMediaUrn.fromString(urnStr) else { continue }
        if target.isEquivalent(to: urn) {
            return bytes
        }
    }
    return nil
}

/// Like findStream but returns a UTF-8 string.
public func findStreamStr(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) -> String? {
    guard let data = findStream(streams, mediaUrn: mediaUrn) else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Like findStream but fails hard if not found.
public func requireStream(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) throws -> Data {
    guard let data = findStream(streams, mediaUrn: mediaUrn) else {
        throw StreamError.protocolError("Missing required arg: \(mediaUrn)")
    }
    return data
}

/// Like requireStream but returns a UTF-8 string.
public func requireStreamStr(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) throws -> String {
    let data = try requireStream(streams, mediaUrn: mediaUrn)
    guard let str = String(data: data, encoding: .utf8) else {
        throw StreamError.decode("Arg '\(mediaUrn)' is not valid UTF-8")
    }
    return str
}

/// Writable stream handle for handler output or peer call arguments.
/// Manages STREAM_START/CHUNK/STREAM_END framing automatically.
public final class OutputStream: @unchecked Sendable {
    private let sender: any FrameSender
    private let streamId: String
    private let _mediaUrn: String
    private let requestId: MessageId
    private let routingId: MessageId?
    private let maxChunk: Int

    private let streamStartedLock = NSLock()
    private var _streamStarted = false

    private let chunkStateLock = NSLock()
    private var _chunkIndex: UInt64 = 0
    private var _chunkCount: UInt64 = 0

    private let closedLock = NSLock()
    private var _closed = false

    init(
        sender: any FrameSender,
        streamId: String,
        mediaUrn: String,
        requestId: MessageId,
        routingId: MessageId?,
        maxChunk: Int
    ) {
        self.sender = sender
        self.streamId = streamId
        self._mediaUrn = mediaUrn
        self.requestId = requestId
        self.routingId = routingId
        self.maxChunk = maxChunk
    }

    /// Media URN of this stream.
    public var mediaUrn: String {
        _mediaUrn
    }

    private func ensureStarted() throws {
        streamStartedLock.lock()
        let alreadyStarted = _streamStarted
        if !alreadyStarted {
            _streamStarted = true
        }
        streamStartedLock.unlock()

        if !alreadyStarted {
            var startFrame = Frame.streamStart(
                reqId: requestId,
                streamId: streamId,
                mediaUrn: _mediaUrn
            )
            startFrame.routingId = routingId
            try sender.send(startFrame)
        }
    }

    private func sendChunk(_ value: CBOR) throws {
        let cborPayload = Data(value.encode())

        chunkStateLock.lock()
        let currentChunkIndex = _chunkIndex
        _chunkIndex += 1
        _chunkCount += 1
        chunkStateLock.unlock()

        let checksum = Frame.computeChecksum(cborPayload)
        var frame = Frame.chunk(
            reqId: requestId,
            streamId: streamId,
            seq: 0, // seq assigned by writer thread SeqAssigner
            payload: cborPayload,
            chunkIndex: currentChunkIndex,
            checksum: checksum
        )
        frame.routingId = routingId
        try sender.send(frame)
    }

    /// Write raw bytes. Splits into maxChunk pieces, each wrapped as CBOR byteString.
    /// Auto-sends STREAM_START before first chunk.
    public func write(_ data: Data) throws {
        try ensureStarted()
        if data.isEmpty {
            return
        }
        var offset = 0
        while offset < data.count {
            let chunkSize = min(data.count - offset, maxChunk)
            let chunkBytes = data.subdata(in: offset..<(offset + chunkSize))
            try sendChunk(.byteString([UInt8](chunkBytes)))
            offset += chunkSize
        }
    }

    /// Emit a CBOR value. Handles byteString/utf8String/array/map chunking.
    public func emitCbor(_ value: CBOR) throws {
        try ensureStarted()
        switch value {
        case .byteString(let bytes):
            var offset = 0
            while offset < bytes.count {
                let chunkSize = min(bytes.count - offset, maxChunk)
                let chunkBytes = Array(bytes[offset..<(offset + chunkSize)])
                try sendChunk(.byteString(chunkBytes))
                offset += chunkSize
            }

        case .utf8String(let text):
            let textBytes = Data(text.utf8)
            var offset = 0
            while offset < textBytes.count {
                var chunkSize = min(textBytes.count - offset, maxChunk)
                // Ensure we don't split UTF-8 mid-character
                while chunkSize > 0 {
                    let chunkData = textBytes.subdata(in: offset..<(offset + chunkSize))
                    if String(data: chunkData, encoding: .utf8) != nil {
                        break
                    }
                    chunkSize -= 1
                }
                if chunkSize == 0 {
                    throw PluginRuntimeError.handlerError("Cannot split text on character boundary")
                }
                let chunkData = textBytes.subdata(in: offset..<(offset + chunkSize))
                let chunkText = String(data: chunkData, encoding: .utf8)!
                try sendChunk(.utf8String(chunkText))
                offset += chunkSize
            }

        case .array(let elements):
            for element in elements {
                try sendChunk(element)
            }

        case .map(let entries):
            for (key, val) in entries {
                let entry = CBOR.array([key, val])
                try sendChunk(entry)
            }

        default:
            // Other types (int, float, bool, null): send as single chunk
            try sendChunk(value)
        }
    }

    /// Emit a log message.
    public func log(level: String, message: String) {
        var frame = Frame.log(id: requestId, level: level, message: message)
        frame.routingId = routingId
        try? sender.send(frame)
    }

    /// Close the output stream (sends STREAM_END). Idempotent.
    /// If stream was never started, sends STREAM_START first.
    public func close() throws {
        closedLock.lock()
        let alreadyClosed = _closed
        if !alreadyClosed {
            _closed = true
        }
        closedLock.unlock()

        if alreadyClosed {
            return
        }

        try ensureStarted()

        chunkStateLock.lock()
        let finalChunkCount = _chunkCount
        chunkStateLock.unlock()

        var frame = Frame.streamEnd(
            reqId: requestId,
            streamId: streamId,
            chunkCount: finalChunkCount
        )
        frame.routingId = routingId
        try sender.send(frame)
    }
}

/// Handle for an in-progress peer invocation.
/// Handler creates arg streams with `arg()`, writes data, then calls `finish()`
/// to get the single response InputStream.
public final class PeerCall: @unchecked Sendable {
    private let sender: any FrameSender
    private let requestId: MessageId
    private let maxChunk: Int
    private var responseRx: AnyIterator<Frame>?
    private let lock = NSLock()

    init(sender: any FrameSender, requestId: MessageId, maxChunk: Int, responseRx: AnyIterator<Frame>) {
        self.sender = sender
        self.requestId = requestId
        self.maxChunk = maxChunk
        self.responseRx = responseRx
    }

    /// Create a new arg OutputStream for this peer call.
    /// Each arg is an independent stream (own stream_id, no routing_id).
    public func arg(mediaUrn: String) -> OutputStream {
        let streamId = UUID().uuidString
        return OutputStream(
            sender: sender,
            streamId: streamId,
            mediaUrn: mediaUrn,
            requestId: requestId,
            routingId: nil, // No routing_id for peer requests
            maxChunk: maxChunk
        )
    }

    /// Finish sending args and get the response stream.
    /// Sends END for the peer request, spawns Demux on response channel.
    public func finish() throws -> InputStream {
        // Send END frame for the peer request
        let endFrame = Frame.end(id: requestId, finalPayload: nil)
        try sender.send(endFrame)

        // Take the response receiver
        lock.lock()
        guard let rx = responseRx else {
            lock.unlock()
            throw PluginRuntimeError.peerRequestError("PeerCall already finished")
        }
        responseRx = nil
        lock.unlock()

        // Spawn single-stream Demux for the response
        let inputStream = try demuxSingleStream(responseRx: rx, maxChunk: maxChunk)
        return inputStream
    }
}

/// Wrapper to transfer non-Sendable types across concurrency boundaries.
/// Use with extreme caution — ensures external synchronization.
private final class UnsafeTransfer<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

/// Thread-safe blocking queue for bridging async streams to sync iterators.
/// Used to stream frames from AsyncStream to handler threads.
public final class BlockingQueue<T>: @unchecked Sendable {
    private var queue: [T] = []
    private let lock = NSLock()
    private let condition = NSCondition()
    private var finished = false

    public init() {}

    public func push(_ item: T) {
        condition.lock()
        queue.append(item)
        condition.signal()
        condition.unlock()
    }

    public func enqueue(_ item: T) {
        push(item)
    }

    public func dequeue() -> T? {
        condition.lock()
        defer { condition.unlock() }

        while queue.isEmpty && !finished {
            condition.wait()
        }

        if !queue.isEmpty {
            return queue.removeFirst()
        }
        return nil
    }

    public func tryPop(timeout: TimeInterval) -> T? {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while queue.isEmpty && !finished {
            guard condition.wait(until: deadline) else {
                return nil  // Timeout
            }
        }

        if !queue.isEmpty {
            return queue.removeFirst()
        }
        return nil
    }

    public func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty
    }

    public func finish() {
        condition.lock()
        finished = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Demux a single response stream from frame channel.
/// Used by PeerCall.finish() to convert response frames into InputStream.
private func demuxSingleStream(responseRx: AnyIterator<Frame>, maxChunk: Int) throws -> InputStream {
    // Create a channel for decoded CBOR values
    var chunks: [Result<CBOR, StreamError>] = []
    var mediaUrn = "media:" // Default, updated by STREAM_START

    // Drain the response channel and decode CHUNKs
    for frame in responseRx {
        switch frame.frameType {
        case .streamStart:
            if let urn = frame.mediaUrn {
                mediaUrn = urn
            }

        case .chunk:
            // Decode CBOR payload
            guard let payload = frame.payload else {
                chunks.append(.failure(.protocolError("CHUNK frame missing payload")))
                break
            }

            // Verify checksum (MANDATORY in protocol v2)
            guard let expectedChecksum = frame.checksum else {
                chunks.append(.failure(.protocolError("CHUNK frame missing required checksum field")))
                continue
            }
            let actualChecksum = Frame.computeChecksum(payload)
            if actualChecksum != expectedChecksum {
                chunks.append(.failure(.protocolError("Checksum mismatch: expected=\(expectedChecksum), actual=\(actualChecksum) (payload \(payload.count) bytes)")))
                continue
            }

            do {
                guard let value = try CBOR.decode([UInt8](payload)) else {
                    chunks.append(.failure(.decode("Failed to decode CBOR chunk - decode returned nil")))
                    continue
                }
                chunks.append(.success(value))
            } catch {
                chunks.append(.failure(.decode("Failed to decode CBOR chunk: \(error)")))
            }

        case .streamEnd:
            // Stream ended normally
            break

        case .end:
            // Response END — stream should have ended already
            break

        case .err:
            let code = frame.errorCode ?? "UNKNOWN"
            let message = frame.errorMessage ?? "Unknown error"
            chunks.append(.failure(.remoteError(code: code, message: message)))
            break

        default:
            // Unexpected frame type
            chunks.append(.failure(.protocolError("Unexpected frame type in response: \(frame.frameType)")))
            break
        }
    }

    // Create iterator from collected chunks
    var index = 0
    let iterator = AnyIterator<Result<CBOR, StreamError>> {
        guard index < chunks.count else { return nil }
        let item = chunks[index]
        index += 1
        return item
    }

    return InputStream(mediaUrn: mediaUrn, rx: iterator)
}

/// Demux multiple input streams from frame iterator into InputPackage.
/// Groups frames by stream_id, yields InputStream for each stream.
/// Used for incoming requests (plugin receiving from host).
internal func demuxMultiStream(frameIterator: AnyIterator<Frame>) -> InputPackage {
    // Track per-stream state
    class StreamState {
        var mediaUrn: String = "media:"
        var chunks: [Result<CBOR, StreamError>] = []
        var ended = false
    }

    var streams: [String: StreamState] = [:]
    var streamOrder: [String] = [] // Track order of STREAM_START arrivals

    // Drain all frames and organize by stream_id
    for frame in frameIterator {
        switch frame.frameType {
        case .streamStart:
            guard let streamId = frame.streamId else {
                continue
            }
            let state = StreamState()
            if let urn = frame.mediaUrn {
                state.mediaUrn = urn
            }
            streams[streamId] = state
            streamOrder.append(streamId)

        case .chunk:
            guard let streamId = frame.streamId,
                  let state = streams[streamId],
                  let payload = frame.payload else {
                continue
            }

            // Verify checksum (MANDATORY in protocol v2)
            guard let expectedChecksum = frame.checksum else {
                state.chunks.append(.failure(.protocolError("CHUNK frame missing required checksum field")))
                continue
            }
            let actualChecksum = Frame.computeChecksum(payload)
            if actualChecksum != expectedChecksum {
                state.chunks.append(.failure(.protocolError("Checksum mismatch: expected=\(expectedChecksum), actual=\(actualChecksum)")))
                continue
            }

            do {
                guard let value = try CBOR.decode([UInt8](payload)) else {
                    state.chunks.append(.failure(.decode("Failed to decode CBOR chunk - decode returned nil")))
                    continue
                }
                state.chunks.append(.success(value))
            } catch {
                state.chunks.append(.failure(.decode("Failed to decode CBOR chunk: \(error)")))
            }

        case .streamEnd:
            guard let streamId = frame.streamId,
                  let state = streams[streamId] else {
                continue
            }
            state.ended = true

        case .end:
            break

        case .err:
            // Error frame - propagate to all streams
            let code = frame.errorCode ?? "UNKNOWN"
            let message = frame.errorMessage ?? "Unknown error"
            let error = StreamError.remoteError(code: code, message: message)
            for state in streams.values {
                state.chunks.append(.failure(error))
            }
            break

        default:
            break
        }
    }

    // Build InputStream for each stream in arrival order
    var inputStreams: [Result<InputStream, StreamError>] = []
    for streamId in streamOrder {
        guard let state = streams[streamId] else {
            continue
        }

        var chunkIndex = 0
        let chunksCopy = state.chunks
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard chunkIndex < chunksCopy.count else { return nil }
            let item = chunksCopy[chunkIndex]
            chunkIndex += 1
            return item
        }

        let inputStream = InputStream(mediaUrn: state.mediaUrn, rx: iterator)
        inputStreams.append(.success(inputStream))
    }

    // Create InputPackage iterator
    var streamIndex = 0
    let streamsIterator = AnyIterator<Result<InputStream, StreamError>> {
        guard streamIndex < inputStreams.count else { return nil }
        let item = inputStreams[streamIndex]
        streamIndex += 1
        return item
    }

    return InputPackage(rx: streamsIterator)
}

// MARK: - Stream Chunk Type - REMOVED
// StreamChunk wrapper removed - handlers now receive bare Frame objects directly

// MARK: - Argument Types

/// Unified argument for cap invocation - arguments are identified by media_urn.
public struct CapArgumentValue: Sendable {
    /// Semantic identifier, e.g., "media:model-spec;textable"
    public let mediaUrn: String
    /// Value bytes (UTF-8 for text, raw for binary)
    public let value: Data

    public init(mediaUrn: String, value: Data) {
        self.mediaUrn = mediaUrn
        self.value = value
    }

    /// Create from a string value
    public static func fromString(mediaUrn: String, value: String) -> CapArgumentValue {
        guard let data = value.data(using: .utf8) else {
            fatalError("Failed to encode string as UTF-8: \(value)")
        }
        return CapArgumentValue(mediaUrn: mediaUrn, value: data)
    }

    /// Get the value as a UTF-8 string (fails for binary data)
    public func valueAsString() throws -> String {
        guard let str = String(data: value, encoding: .utf8) else {
            throw PluginRuntimeError.deserializationError("Value is not valid UTF-8")
        }
        return str
    }
}


// MARK: - PeerInvoker Protocol

/// Allows handlers to invoke caps on the peer (host).
///
/// This protocol enables bidirectional communication where a plugin handler can
/// invoke caps on the host while processing a request.
///
/// The `call` method starts a peer invocation and returns a `PeerCall`.
/// The handler creates arg streams with `call.arg()`, writes data, then
/// calls `call.finish()` to get the single response `InputStream`.
public protocol PeerInvoker: Sendable {
    /// Start a peer call. Sends REQ, registers response channel.
    func call(capUrn: String) throws -> PeerCall

    /// Convenience: open call, write each arg's bytes, finish, return response.
    func callWithBytes(capUrn: String, args: [(mediaUrn: String, data: Data)]) throws -> InputStream
}

// Default implementation of callWithBytes
extension PeerInvoker {
    public func callWithBytes(capUrn: String, args: [(mediaUrn: String, data: Data)]) throws -> InputStream {
        let call = try self.call(capUrn: capUrn)
        for (mediaUrn, data) in args {
            let arg = call.arg(mediaUrn: mediaUrn)
            try arg.write(data)
            try arg.close()
        }
        return try call.finish()
    }
}

/// A no-op PeerInvoker that always returns an error.
/// Used when peer invocation is not supported (e.g., CLI mode).
public struct NoPeerInvoker: PeerInvoker {
    public init() {}

    public func call(capUrn: String) throws -> PeerCall {
        throw PluginRuntimeError.peerRequestError("Peer invocation not supported in this context")
    }
}

// MARK: - CliFrameSender

/// CLI-mode frame sender that extracts and writes raw content to stdout.
/// Used by OutputStream in CLI mode.
///
/// Supports NDJSON mode (default: true) which adds newlines after each emit,
/// matching Rust's CliStreamEmitter behavior.
final class CliFrameSender: FrameSender, @unchecked Sendable {
    private let stdoutHandle: FileHandle

    /// Whether to add newlines after each emit (NDJSON style)
    let ndjson: Bool

    /// Create a new CLI sender with NDJSON formatting (newline after each emit)
    init() {
        self.stdoutHandle = FileHandle.standardOutput
        self.ndjson = true
    }

    /// Create a CLI sender with explicit ndjson setting
    init(ndjson: Bool) {
        self.stdoutHandle = FileHandle.standardOutput
        self.ndjson = ndjson
    }

    /// Create a CLI sender without NDJSON formatting
    static func withoutNdjson() -> CliFrameSender {
        return CliFrameSender(ndjson: false)
    }

    func send(_ frame: Frame) throws {
        // In CLI mode, only handle CHUNK frames with payload
        // STREAM_START, STREAM_END are ignored
        guard frame.frameType == .chunk, let payload = frame.payload else {
            return
        }

        // Decode CBOR value from payload
        guard let value = try CBOR.decode([UInt8](payload)) else {
            throw PluginRuntimeError.protocolError("Failed to decode CBOR chunk payload")
        }

        // Extract and write raw content
        try extractAndWrite(value, to: stdoutHandle)

        // Add newline in NDJSON mode
        if ndjson {
            stdoutHandle.write(Data("\n".utf8))
        }
    }

    /// Recursively extract and write raw content from CBOR values
    /// Throws on unsupported types - no fallbacks
    private func extractAndWrite(_ value: CBOR, to handle: FileHandle) throws {
        switch value {
        case .byteString(let bytes):
            handle.write(Data(bytes))

        case .utf8String(let text):
            handle.write(Data(text.utf8))

        case .array(let items):
            // Emit each element's raw content
            for item in items {
                try extractAndWrite(item, to: handle)
            }

        case .map(let m):
            // Extract "value" field if present
            if let val = m[.utf8String("value")] {
                try extractAndWrite(val, to: handle)
            } else {
                // No value field - fail hard (no fallback)
                throw PluginRuntimeError.handlerError("Map in CLI output has no 'value' field")
            }

        default:
            // Unsupported type - fail hard (no fallback)
            throw PluginRuntimeError.handlerError("CLI output does not support CBOR type")
        }
    }
}


// MARK: - Payload Extraction

/// Extract the effective payload from a REQ frame.
///
/// If the content_type is "application/cbor", the payload is expected to be
/// CBOR arguments: `[{media_urn: string, value: bytes}, ...]`
/// The function extracts the value whose media_urn matches the cap's input type.
///
/// For other content types (or if content_type is nil), returns the raw payload.
///
/// - Parameters:
///   - payload: Raw payload bytes from the REQ frame
///   - contentType: Content-Type header from the REQ frame
///   - capUrn: The cap URN being invoked (used to determine expected input type)
/// - Returns: The effective payload bytes
/// - Throws: PluginRuntimeError if parsing fails or no matching argument found
func extractEffectivePayload(payload: Data, contentType: String?, capUrn: String) throws -> Data {
    // Check if this is CBOR arguments
    guard contentType == "application/cbor" else {
        // Not CBOR arguments - return raw payload
        return payload
    }

    // Parse the cap URN to get the expected input media type using proper CSCapUrn
    let parsedUrn: CSCapUrn
    do {
        parsedUrn = try CSCapUrn.fromString(capUrn)
    } catch {
        throw PluginRuntimeError.capUrnError("Failed to parse cap URN '\(capUrn)': \(error.localizedDescription)")
    }
    let expectedInput = parsedUrn.getInSpec()

    // Parse the CBOR payload as an array of argument maps
    let cborValue: CBOR
    do {
        guard let decoded = try CBOR.decode([UInt8](payload)) else {
            throw PluginRuntimeError.deserializationError("Failed to decode CBOR payload")
        }
        cborValue = decoded
    } catch {
        throw PluginRuntimeError.deserializationError("Failed to parse CBOR arguments: \(error)")
    }

    // Must be an array
    guard case .array(let arguments) = cborValue else {
        throw PluginRuntimeError.deserializationError("CBOR arguments must be an array")
    }

    // Parse the expected input as a tagged URN for proper matching
    let expectedUrn = try? CSTaggedUrn.fromString(expectedInput)

    // Find the argument with matching media_urn
    for arg in arguments {
        guard case .map(let argMap) = arg else {
            continue
        }

        var mediaUrn: String?
        var value: Data?

        for (k, v) in argMap {
            if case .utf8String(let key) = k {
                switch key {
                case "media_urn":
                    if case .utf8String(let s) = v {
                        mediaUrn = s
                    }
                case "value":
                    if case .byteString(let bytes) = v {
                        value = Data(bytes)
                    }
                default:
                    break
                }
            }
        }

        // Check if this argument matches the expected input using tagged URN matching
        if let urnStr = mediaUrn, let val = value {
            if let expectedUrn = expectedUrn,
               let argUrn = try? CSTaggedUrn.fromString(urnStr) {
                // Use proper semantic matching in both directions
                let conformsForward = (try? argUrn.conforms(to: expectedUrn)) != nil
                let conformsReverse = (try? expectedUrn.conforms(to: argUrn)) != nil
                if conformsForward || conformsReverse {
                    return val
                }
            }
        }
    }

    // No matching argument found - this is an error, no fallbacks
    throw PluginRuntimeError.deserializationError(
        "No argument found matching expected input media type '\(expectedInput)' in CBOR arguments"
    )
}


// MARK: - Handler Type

/// Handler function type for Frame-based streaming.
///
/// Handlers receive bare CBOR Frame objects for both input arguments and peer responses.
/// No wrapper types - frames are delivered directly as they arrive.
/// Handler has full streaming control - decides when to consume frames and when to produce output.
///
/// Input frames: STREAM_START, CHUNK, STREAM_END, END (request arguments)
/// Peer response frames: STREAM_START, CHUNK, STREAM_END, END, ERR (from PeerInvoker)
///
/// Handler processes frames and emits output via CborStreamEmitter.
/// Handler signature for cap invocations.
// =============================================================================
// OP-BASED HANDLER SYSTEM — handlers implement Ops.Op<Void>
// =============================================================================

/// Bundles capns I/O for WetContext. Op handlers extract this from WetContext
/// to access streaming input, output, and peer invocation.
public final class CborRequest: @unchecked Sendable {
    private let _inputLock = NSLock()
    private var _inputPackage: InputPackage?
    private let _output: OutputStream
    private let _peer: any PeerInvoker

    public init(input: InputPackage, output: OutputStream, peer: any PeerInvoker) {
        _inputPackage = input
        _output = output
        _peer = peer
    }

    /// Take the input package. Can only be called once — second call throws.
    public func takeInput() throws -> InputPackage {
        _inputLock.lock()
        defer { _inputLock.unlock() }
        guard let pkg = _inputPackage else {
            throw PluginRuntimeError.protocolError("Input already consumed")
        }
        _inputPackage = nil
        return pkg
    }

    public func output() -> OutputStream { _output }
    public func peer() -> any PeerInvoker { _peer }
}

/// WetContext key for the CborRequest object.
public let WET_KEY_REQUEST: String = "request"

/// Factory that creates a fresh AnyOp<Void> per invocation.
/// Matches Rust's `Arc<dyn Fn() -> Box<dyn Op<()>> + Send + Sync>`.
public typealias OpFactory = @Sendable () -> AnyOp<Void>

/// Standard identity handler — pure passthrough. Forwards all input chunks to output.
public struct IdentityOp: Op, Sendable {
    public typealias Output = Void
    public init() {}
    public func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        for streamResult in input {
            let stream = try streamResult.get()
            for chunkResult in stream {
                let chunk = try chunkResult.get()
                try req.output().emitCbor(chunk)
            }
        }
    }
    public func metadata() -> OpMetadata {
        OpMetadata.builder("IdentityOp").description("Pure passthrough — forwards all input to output").build()
    }
}

/// Standard discard handler — terminal morphism. Drains all input, produces nothing.
public struct DiscardOp: Op, Sendable {
    public typealias Output = Void
    public init() {}
    public func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        for streamResult in input {
            let stream = try streamResult.get()
            for chunkResult in stream {
                _ = try chunkResult.get()
            }
        }
    }
    public func metadata() -> OpMetadata {
        OpMetadata.builder("DiscardOp").description("Terminal morphism — drains all input, produces nothing").build()
    }
}

/// Dispatch an AnyOp<Void> with a CborRequest via WetContext.
/// Bridges sync handler threads to async Op.perform via DispatchSemaphore + Task.
/// Closes the output stream on success (sends STREAM_END if stream was started).
func dispatchOp(op: AnyOp<Void>, input: InputPackage, output: OutputStream, peer: any PeerInvoker) throws {
    let req = CborRequest(input: input, output: output, peer: peer)
    let dry = DryContext()
    let wet = WetContext()
    wet.insertRef(req, for: WET_KEY_REQUEST)

    // Use a class wrapper so Task can capture it as @Sendable (Swift 6 requirement)
    final class ErrorHolder: @unchecked Sendable { var error: Error? = nil }
    let holder = ErrorHolder()
    let sema = DispatchSemaphore(value: 0)
    Task { [holder, sema] in
        do {
            _ = try await op.perform(dry: dry, wet: wet)
        } catch {
            holder.error = error
        }
        sema.signal()
    }
    sema.wait()

    if let err = holder.error {
        throw err
    }
    // Auto-close output stream on success
    try? output.close()
}

// MARK: - Internal: Pending Peer Request

/// Internal struct to track pending peer requests (plugin invoking host caps).
/// Now uses AsyncStream continuation to forward frames instead of condition variables.
private struct PendingPeerRequest {
    let continuation: AsyncStream<Frame>.Continuation
    var isComplete: Bool
}

// MARK: - Internal: PeerInvokerImpl

/// Implementation of PeerInvoker that sends REQ frames to the host.
/// Spawns a background task that forwards response frames via FrameQueue.
@available(macOS 10.15.4, iOS 13.4, *)
/// ChannelFrameSender implementation for sending frames from PeerInvokerImpl and OutputStream.
/// Applies SeqAssigner to every outbound frame, matching Rust's writer-thread seq assignment.
/// Cleans up flow tracking on terminal frames (END/ERR).
@available(macOS 10.15.4, iOS 13.4, *)
private final class ChannelFrameSender: FrameSender, @unchecked Sendable {
    private let writer: FrameWriter
    private let writerLock: NSLock
    private let seqAssigner: SeqAssigner

    init(writer: FrameWriter, writerLock: NSLock, seqAssigner: SeqAssigner) {
        self.writer = writer
        self.writerLock = writerLock
        self.seqAssigner = seqAssigner
    }

    func send(_ frame: Frame) throws {
        writerLock.lock()
        defer { writerLock.unlock() }
        var mutableFrame = frame
        seqAssigner.assign(&mutableFrame)
        try writer.write(mutableFrame)
        if mutableFrame.frameType == .end || mutableFrame.frameType == .err {
            seqAssigner.remove(FlowKey.fromFrame(mutableFrame))
        }
    }
}

@available(macOS 10.15.4, iOS 13.4, *)
final class PeerInvokerImpl: PeerInvoker, @unchecked Sendable {
    private let writer: FrameWriter
    private let writerLock: NSLock
    private let seqAssigner: SeqAssigner
    private let pendingRequests: NSMutableDictionary // [MessageId: PendingPeerRequest]
    private let pendingRequestsLock: NSLock
    private let maxChunk: Int

    init(writer: FrameWriter, writerLock: NSLock, seqAssigner: SeqAssigner, pendingRequests: NSMutableDictionary, pendingRequestsLock: NSLock, maxChunk: Int) {
        self.writer = writer
        self.writerLock = writerLock
        self.seqAssigner = seqAssigner
        self.pendingRequests = pendingRequests
        self.pendingRequestsLock = pendingRequestsLock
        self.maxChunk = maxChunk
    }

    func call(capUrn: String) throws -> PeerCall {
        // Generate a new message ID for this request
        let requestId = MessageId.newUUID()

        // Create AsyncStream and continuation for response frames
        let (stream, continuation) = AsyncStream<Frame>.makeStream()

        // Create pending request tracking
        let pending = PendingPeerRequest(
            continuation: continuation,
            isComplete: false
        )

        // Register the pending request before sending REQ
        pendingRequestsLock.lock()
        pendingRequests[requestId] = pending
        pendingRequestsLock.unlock()

        // Send REQ with empty payload — apply seq assignment
        writerLock.lock()
        do {
            var reqFrame = Frame.req(id: requestId, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
            seqAssigner.assign(&reqFrame)
            try writer.write(reqFrame)
        } catch {
            writerLock.unlock()
            pendingRequestsLock.lock()
            pendingRequests.removeObject(forKey: requestId)
            pendingRequestsLock.unlock()
            continuation.finish()
            throw PluginRuntimeError.peerRequestError("Failed to send peer REQ: \(error)")
        }
        writerLock.unlock()

        // Convert AsyncStream to AnyIterator for PeerCall
        // Use thread-safe queue with @unchecked Sendable wrappers to bridge async→sync
        final class FrameQueue: @unchecked Sendable {
            private var frames: [Frame] = []
            private let lock = NSLock()
            private let semaphore = DispatchSemaphore(value: 0)
            private var completed = false

            func add(_ frame: Frame) {
                lock.lock()
                frames.append(frame)
                lock.unlock()
                semaphore.signal()
            }

            func complete() {
                lock.lock()
                completed = true
                lock.unlock()
                semaphore.signal()
            }

            func next() -> Frame? {
                semaphore.wait()
                lock.lock()
                defer { lock.unlock() }

                if !frames.isEmpty {
                    return frames.removeFirst()
                } else if completed {
                    return nil
                } else {
                    return nil // Should not happen
                }
            }
        }

        let queue = FrameQueue()

        // Spawn background task to drain AsyncStream
        Task.detached {
            for await frame in stream {
                queue.add(frame)
            }
            queue.complete()
        }

        let frameIterator = AnyIterator<Frame> {
            queue.next()
        }

        // Create ChannelFrameSender for arg streams (shares seqAssigner)
        let sender = ChannelFrameSender(writer: writer, writerLock: writerLock, seqAssigner: seqAssigner)

        // Return PeerCall with response iterator
        return PeerCall(
            sender: sender,
            requestId: requestId,
            maxChunk: maxChunk,
            responseRx: frameIterator
        )
    }
}

// MARK: - Manifest Types (for CLI mode)

/// Source for extracting argument values in CLI mode.
public enum ArgSource: Codable, Sendable {
    case cliFlag(String)
    case positional(Int)
    case stdin(String)  // Media URN for stdin input

    enum CodingKeys: String, CodingKey {
        case type
        case cliFlag = "cli_flag"
        case position
        case stdin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // The format is a single-key object: {"stdin": "..."}, {"position": 0}, or {"cli_flag": "..."}
        // NOT {"type": "stdin", "stdin": "..."}
        if let flag = try? container.decode(String.self, forKey: .cliFlag) {
            self = .cliFlag(flag)
        } else if let pos = try? container.decode(Int.self, forKey: .position) {
            self = .positional(pos)
        } else if let mediaUrn = try? container.decode(String.self, forKey: .stdin) {
            self = .stdin(mediaUrn)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid source format: must have exactly one of 'cli_flag', 'position', or 'stdin'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode as single-key object: {"stdin": "..."}, {"position": 0}, or {"cli_flag": "..."}
        switch self {
        case .cliFlag(let flag):
            try container.encode(flag, forKey: .cliFlag)
        case .positional(let pos):
            try container.encode(pos, forKey: .position)
        case .stdin(let mediaUrn):
            try container.encode(mediaUrn, forKey: .stdin)
        }
    }
}

/// Argument definition in a cap.
public struct CapArg: Codable, Sendable {
    public let mediaUrn: String
    public let required: Bool
    public let sources: [ArgSource]
    public let argDescription: String?
    public let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case mediaUrn = "media_urn"
        case required
        case sources
        case argDescription = "description"
        case defaultValue = "default"
    }

    public init(mediaUrn: String, required: Bool, sources: [ArgSource], argDescription: String? = nil, defaultValue: String? = nil) {
        self.mediaUrn = mediaUrn
        self.required = required
        self.sources = sources
        self.argDescription = argDescription
        self.defaultValue = defaultValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaUrn = try container.decode(String.self, forKey: .mediaUrn)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        sources = try container.decodeIfPresent([ArgSource].self, forKey: .sources) ?? []
        argDescription = try container.decodeIfPresent(String.self, forKey: .argDescription)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
    }
}

/// Cap definition in the manifest.
public struct CapDefinition: Codable, Sendable {
    public let urn: String
    public let title: String
    public let command: String
    public let capDescription: String?
    public let args: [CapArg]

    enum CodingKeys: String, CodingKey {
        case urn
        case title
        case command
        case capDescription = "description"
        case args
    }

    public init(urn: String, title: String, command: String, capDescription: String? = nil, args: [CapArg] = []) {
        self.urn = urn
        self.title = title
        self.command = command
        self.capDescription = capDescription
        self.args = args
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urn = try container.decode(String.self, forKey: .urn)
        title = try container.decode(String.self, forKey: .title)
        command = try container.decode(String.self, forKey: .command)
        capDescription = try container.decodeIfPresent(String.self, forKey: .capDescription)
        args = try container.decodeIfPresent([CapArg].self, forKey: .args) ?? []
    }

    /// Check if this cap accepts stdin input.
    public func acceptsStdin() -> Bool {
        for arg in args {
            for source in arg.sources {
                if case .stdin(_) = source {
                    return true
                }
            }
        }
        return false
    }
}

/// Plugin manifest structure.
public struct Manifest: Codable, Sendable {
    public let name: String
    public let version: String
    public let description: String
    public let caps: [CapDefinition]

    public init(name: String, version: String, description: String, caps: [CapDefinition]) {
        self.name = name
        self.version = version
        self.description = description
        self.caps = caps
    }
}

// MARK: - PluginRuntime

/// Plugin-side runtime for CBOR protocol communication.
///
/// Plugins create a runtime, register handlers for their caps, then call `run()`.
/// The runtime handles all I/O mechanics:
/// - HELLO handshake for limit negotiation (includes manifest in response)
/// - Frame encoding/decoding
/// - Request routing to handlers
/// - Streaming response support
/// - HEARTBEAT health monitoring
/// - Bidirectional peer invocation (plugin can call host caps)
///
/// **Multiplexed execution**: Multiple requests can be processed concurrently.
/// Each request handler runs in its own thread, allowing the runtime to:
/// - Respond to heartbeats while handlers are running
/// - Accept new requests while previous ones are still processing
/// - Route response frames to handlers that invoked peer caps
///
/// **This is the ONLY supported way for plugins to communicate with the host.**
/// The manifest MUST be provided - plugins without a manifest will fail handshake.
@available(macOS 10.15.4, iOS 13.4, *)
public final class PluginRuntime: @unchecked Sendable {

    // MARK: - Properties

    private var handlers: [String: OpFactory] = [:]
    private let handlersLock = NSLock()

    private var limits = Limits()

    /// Plugin manifest JSON data - sent in HELLO response.
    /// This is REQUIRED - plugins must provide their manifest.
    let manifestData: Data

    /// Parsed manifest for CLI mode support.
    /// Contains cap definitions with command names and argument sources.
    let parsedManifest: Manifest?

    // MARK: - Initialization

    /// Create a plugin runtime with the required manifest.
    ///
    /// The manifest is JSON-encoded plugin metadata including:
    /// - name: Plugin name
    /// - version: Plugin version
    /// - caps: Array of capability definitions with args and sources
    ///
    /// This manifest is sent in the HELLO response to the host (CBOR mode)
    /// and used for CLI argument parsing (CLI mode).
    /// **Plugins MUST provide a manifest - there is no fallback.**
    ///
    /// The runtime automatically registers:
    /// - CAP_IDENTITY handler (mandatory) - passes input through unchanged
    /// - CAP_DISCARD handler (standard, optional) - consumes input, produces void
    ///
    /// - Parameter manifest: JSON-encoded manifest data
    public init(manifest: Data) {
        self.manifestData = manifest
        // Parse manifest for CLI mode support
        self.parsedManifest = try? JSONDecoder().decode(Manifest.self, from: manifest)

        // FAIL HARD if manifest doesn't declare CAP_IDENTITY
        // Plugins MUST explicitly declare all caps they provide - no fallbacks
        if let parsed = self.parsedManifest {
            // Check using URN conformance, not string equality
            // CAP_IDENTITY ("cap:") can be declared as "cap:" or "cap:in=media:;out=media:"
            var hasIdentity = false
            if let identityUrn = try? CSCapUrn.fromString(CSCapIdentity) {
                hasIdentity = parsed.caps.contains { cap in
                    if let capUrn = try? CSCapUrn.fromString(cap.urn) {
                        // Check if the cap URN conforms to CAP_IDENTITY (is identity or more specific)
                        return (try? capUrn.conforms(to: identityUrn)) == true ||
                               (try? identityUrn.conforms(to: capUrn)) == true
                    }
                    return false
                }
            }
            precondition(hasIdentity, "Manifest validation failed - plugin MUST declare CAP_IDENTITY (\(CSCapIdentity))")
        }

        // Auto-register standard capability handlers
        autoRegisterStandardCaps()
    }

    /// Create a plugin runtime with manifest JSON string.
    /// - Parameter manifestJSON: JSON string of the manifest
    public convenience init(manifestJSON: String) {
        guard let data = manifestJSON.data(using: .utf8) else {
            fatalError("Failed to encode manifest JSON as UTF-8")
        }
        self.init(manifest: data)
    }

    /// Auto-register standard capability handlers.
    /// Called during initialization to provide mandatory and optional standard caps.
    private func autoRegisterStandardCaps() {
        // CAP_IDENTITY: "cap:in=media:;out=media:" (mandatory)
        if findHandler(capUrn: CSCapIdentity) == nil {
            register_op_type(capUrn: CSCapIdentity, make: IdentityOp.init)
        }
        // CAP_DISCARD: "cap:in=media:;out=media:void" (standard, optional)
        if findHandler(capUrn: CSCapDiscard) == nil {
            register_op_type(capUrn: CSCapDiscard, make: DiscardOp.init)
        }
    }

    // MARK: - Handler Registration

    /// Register an Op factory for a cap URN.
    /// The factory creates a fresh AnyOp<Void> per invocation.
    public func register_op(capUrn: String, factory: @escaping OpFactory) {
        handlersLock.lock()
        handlers[capUrn] = factory
        handlersLock.unlock()
    }

    /// Convenience: register an Op type for a cap URN using a no-arg factory closure.
    /// Call as: register_op_type(capUrn: "cap:...", make: { MyOp() })
    /// Or shorthand: register_op_type(capUrn: "cap:...", make: MyOp.init)
    public func register_op_type<T: Op>(capUrn: String, make: @escaping @Sendable () -> T) where T.Output == Void {
        register_op(capUrn: capUrn, factory: { AnyOp(make()) })
    }

    /// Find an Op factory for a cap URN (supports exact match and pattern matching).
    ///
    /// Matching direction: request is pattern, registered cap is instance.
    /// `request.accepts(registered_cap)` — the request must accept the registered cap,
    /// meaning the registered cap must be able to satisfy what the request asks for.
    ///
    /// Returns the factory with the closest specificity to the request (not necessarily the most specific).
    func findHandler(capUrn: String) -> OpFactory? {
        handlersLock.lock()
        defer { handlersLock.unlock() }

        // Parse request URN
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        let requestSpecificity = requestUrn.specificity()
        var best: (factory: OpFactory, distance: Int)? = nil

        // Find all matching handlers, prefer closest specificity
        for (registeredCapStr, factory) in handlers {
            guard let registeredUrn = try? CSCapUrn.fromString(registeredCapStr) else {
                continue
            }

            // Request is pattern, registered cap is instance
            if requestUrn.accepts(registeredUrn) {
                let specificity = registeredUrn.specificity()
                let distance = abs(Int(specificity) - Int(requestSpecificity))

                if let currentBest = best {
                    if distance < currentBest.distance {
                        best = (factory, distance)
                    }
                } else {
                    best = (factory, distance)
                }
            }
        }

        return best?.factory
    }

    // MARK: - Main Run Loop

    /// Run the plugin runtime.
    ///
    /// **Mode Detection**:
    /// - No CLI arguments: Plugin CBOR mode (stdin/stdout binary frames)
    /// - Any CLI arguments: CLI mode (parse args from cap definitions)
    ///
    /// **CLI Mode**:
    /// - `manifest` subcommand: output manifest JSON
    /// - `<command>` subcommand: find cap by command, parse args, invoke handler
    /// - `--help`: show available subcommands
    ///
    /// **Plugin CBOR Mode** (no CLI args):
    /// 1. Receive HELLO from host
    /// 2. Send HELLO back with manifest (handshake)
    /// 3. Main loop reads frames, dispatches handlers
    /// 4. Exit when stdin closes
    ///
    /// - Throws: PluginRuntimeError on fatal errors
    public func run() throws {
        let args = CommandLine.arguments

        // No CLI arguments at all → Plugin CBOR mode
        if args.count == 1 {
            try runCborMode()
            return
        }

        // Any CLI arguments → CLI mode
        // For CLI mode, we need to bridge async runCliMode to sync run()
        // Use a simple blocking approach with explicit Sendable conformance

        // Create a container class marked as @unchecked Sendable (safe because we use locks)
        final class ResultContainer: @unchecked Sendable {
            private let lock = NSLock()
            private var _result: Result<Void, Error>?

            func set(_ result: Result<Void, Error>) {
                lock.lock()
                _result = result
                lock.unlock()
            }

            func get() -> Result<Void, Error>? {
                lock.lock()
                defer { lock.unlock() }
                return _result
            }
        }

        let container = ResultContainer()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached { [container, semaphore] in
            let result: Result<Void, Error>
            do {
                try self.runCliMode(args)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            container.set(result)
            semaphore.signal()
        }

        semaphore.wait()

        switch container.get() {
        case .success:
            return
        case .failure(let error):
            throw error
        case .none:
            throw PluginRuntimeError.cliError("CLI mode failed to complete")
        }
    }

    // MARK: - CLI Mode

    /// Run in CLI mode - parse arguments and invoke handler.
    private func runCliMode(_ args: [String]) throws {
        guard let manifest = parsedManifest else {
            throw PluginRuntimeError.manifestError("Failed to parse manifest for CLI mode")
        }

        // Handle --help at top level
        if args.count == 2 && (args[1] == "--help" || args[1] == "-h") {
            printHelp(manifest: manifest)
            return
        }

        let subcommand = args[1]

        // Special subcommand: manifest
        if subcommand == "manifest" {
            // Output the raw manifest JSON to stdout
            FileHandle.standardOutput.write(manifestData)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Find cap by command name
        guard let cap = findCapByCommand(manifest: manifest, commandName: subcommand) else {
            throw PluginRuntimeError.unknownSubcommand("Unknown command '\(subcommand)'. Run with --help to see available commands.")
        }

        // Handle --help for specific command
        if args.count == 3 && (args[2] == "--help" || args[2] == "-h") {
            printCapHelp(cap: cap)
            return
        }

        // Find Op factory
        guard let factory = findHandler(capUrn: cap.urn) else {
            throw PluginRuntimeError.noHandler("No handler registered for cap '\(cap.urn)'")
        }

        // Build payload from CLI arguments
        let cliArgs = Array(args.dropFirst(2))
        let payload = try buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Create AsyncStream with Frame sequence for each argument
        // Each argument as separate stream: STREAM_START → CHUNK → STREAM_END per arg, then END
        let (stream, continuation) = AsyncStream<Frame>.makeStream()
        let requestId = MessageId.newUUID()

        // Decode CBOR arguments array
        if !payload.isEmpty {
            if let cborValue = try? CBOR.decode([UInt8](payload)),
               case .array(let arguments) = cborValue {
                // Send each argument as a separate stream
                for (i, arg) in arguments.enumerated() {
                    guard case .map(let argMap) = arg else { continue }

                    var mediaUrn: String?
                    var value: CBOR?

                    // Extract media_urn and value from arg map
                    for (key, val) in argMap {
                        if case .utf8String(let keyStr) = key {
                            if keyStr == "media_urn" {
                                if case .utf8String(let urnStr) = val {
                                    mediaUrn = urnStr
                                }
                            } else if keyStr == "value" {
                                value = val
                            }
                        }
                    }

                    guard let mediaUrn = mediaUrn, let value = value else { continue }

                    let streamId = "arg-\(i)"

                    // STREAM_START
                    continuation.yield(Frame.streamStart(
                        reqId: requestId,
                        streamId: streamId,
                        mediaUrn: mediaUrn
                    ))

                    // CHUNK: CBOR-encode the value before sending
                    // Protocol: ALL values must be CBOR-encoded (encode once, no double-wrapping)
                    let cborValue = Data(value.encode())
                    let checksum = Frame.computeChecksum(cborValue)

                    continuation.yield(Frame.chunk(
                        reqId: requestId,
                        streamId: streamId,
                        seq: 0,
                        payload: cborValue,
                        chunkIndex: 0,
                        checksum: checksum
                    ))

                    // STREAM_END with chunk count = 1 (single chunk per argument)
                    continuation.yield(Frame.streamEnd(
                        reqId: requestId,
                        streamId: streamId,
                        chunkCount: 1
                    ))
                }
            }
        }

        // END
        continuation.yield(Frame.end(id: requestId))
        continuation.finish()

        // Collect all frames synchronously using DispatchGroup
        final class FrameCollector: @unchecked Sendable {
            var frames: [Frame] = []
            let lock = NSLock()

            func add(_ frame: Frame) {
                lock.lock()
                frames.append(frame)
                lock.unlock()
            }

            func getAll() -> [Frame] {
                lock.lock()
                defer { lock.unlock() }
                return frames
            }
        }

        let collector = FrameCollector()
        let group = DispatchGroup()
        group.enter()

        // Spawn detached task to drain stream
        Task.detached {
            for await frame in stream {
                collector.add(frame)
            }
            group.leave()
        }

        group.wait()
        let allFrames = collector.getAll()

        // Build iterator for demux
        var frameIndex = 0
        let frameIterator = AnyIterator<Frame> {
            guard frameIndex < allFrames.count else { return nil }
            let frame = allFrames[frameIndex]
            frameIndex += 1
            return frame
        }

        // Demux frames into InputPackage
        let inputPackage = demuxMultiStream(frameIterator: frameIterator)

        // Create CLI-mode OutputStream (writes to stdout)
        let cliSender = CliFrameSender()
        let outputStream = OutputStream(
            sender: cliSender,
            streamId: "cli-output",
            mediaUrn: "media:", // CLI outputs raw bytes
            requestId: requestId,
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )

        // Create no-op peer invoker (CLI mode doesn't support peer calls)
        let peer = NoPeerInvoker()

        // Invoke Op handler — dispatchOp closes output stream on success
        let op = factory()
        try dispatchOp(op: op, input: inputPackage, output: outputStream, peer: peer)
    }

    /// Find a cap by its command name (the CLI subcommand).
    private func findCapByCommand(manifest: Manifest, commandName: String) -> CapDefinition? {
        return manifest.caps.first { $0.command == commandName }
    }

    /// Read file(s) for file-path arguments and return bytes.
    ///
    /// This method implements automatic file-path to bytes conversion when:
    /// - arg.media_urn is "media:file-path" or "media:file-path-array"
    /// - arg has a stdin source (indicating bytes are the canonical type)
    ///
    /// - Parameters:
    ///   - pathValue: File path string (single path or JSON array of path patterns)
    ///   - isArray: True if media:file-path-array (read multiple files with glob expansion)
    /// - Returns:
    ///   - For single file: Data containing raw file bytes
    ///   - For array: CBOR-encoded array of file bytes (each element is one file's contents)
    /// - Throws: PluginRuntimeError.ioError if file cannot be read with clear error message
    private func readFilePathToBytes(_ pathValue: String, isArray: Bool) throws -> Data {
        if isArray {
            // Parse JSON array of path patterns
            guard let pathData = pathValue.data(using: .utf8),
                  let pathPatterns = try? JSONSerialization.jsonObject(with: pathData) as? [String] else {
                throw PluginRuntimeError.cliError(
                    "Failed to parse file-path-array: expected JSON array of path patterns, got '\(pathValue)'"
                )
            }

            // Expand globs and collect all file paths
            var allFiles: [URL] = []
            let fileManager = FileManager.default

            for pattern in pathPatterns {
                // Check if this is a literal path (no glob metacharacters) or a glob pattern
                let isGlob = pattern.contains("*") || pattern.contains("?") || pattern.contains("[")

                if !isGlob {
                    // Literal path - verify it exists and is a file
                    let url = URL(fileURLWithPath: pattern)
                    if !fileManager.fileExists(atPath: pattern) {
                        throw PluginRuntimeError.ioError(
                            "Failed to read file '\(pattern)' from file-path-array: No such file or directory"
                        )
                    }
                    var isDirectory: ObjCBool = false
                    fileManager.fileExists(atPath: pattern, isDirectory: &isDirectory)
                    if !isDirectory.boolValue {
                        allFiles.append(url)
                    }
                    // Skip directories silently for consistency with glob behavior
                } else {
                    // Glob pattern - validate and expand it
                    // Check for unclosed brackets (invalid pattern)
                    var bracketDepth = 0
                    for char in pattern {
                        if char == "[" {
                            bracketDepth += 1
                        } else if char == "]" {
                            bracketDepth -= 1
                        }
                    }
                    if bracketDepth != 0 {
                        throw PluginRuntimeError.cliError(
                            "Invalid glob pattern '\(pattern)': unclosed bracket"
                        )
                    }

                    let paths = Glob(pattern: pattern)
                    for path in paths {
                        let url = URL(fileURLWithPath: path)
                        // Only include files (skip directories)
                        var isDirectory: ObjCBool = false
                        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue {
                            allFiles.append(url)
                        }
                    }
                }
            }

            // Read each file sequentially
            var filesData: [CBOR] = []
            for url in allFiles {
                do {
                    let bytes = try Data(contentsOf: url)
                    filesData.append(.byteString([UInt8](bytes)))
                } catch {
                    throw PluginRuntimeError.ioError(
                        "Failed to read file '\(url.path)' from file-path-array: \(error.localizedDescription)"
                    )
                }
            }

            // Encode as CBOR array
            let cborArray = CBOR.array(filesData)
            return Data(cborArray.encode())
        } else {
            // Single file path - read and return raw bytes
            do {
                let url = URL(fileURLWithPath: pathValue)
                return try Data(contentsOf: url)
            } catch {
                throw PluginRuntimeError.ioError(
                    "Failed to read file '\(pathValue)': \(error.localizedDescription)"
                )
            }
        }
    }

    /// Build payload from CLI arguments based on cap's arg definitions.
    /// Internal for testing purposes.
    func buildPayloadFromCli(cap: CapDefinition, cliArgs: [String]) throws -> Data {
        var arguments: [CapArgumentValue] = []

        // Check for stdin data if cap accepts stdin
        let stdinData: Data?
        if cap.acceptsStdin() {
            stdinData = try readStdinIfAvailable()
        } else {
            stdinData = nil
        }

        // Process each argument definition
        for argDef in cap.args {
            let value = try extractArgValue(argDef: argDef, cliArgs: cliArgs, stdinData: stdinData)

            if let v = value {
                // Determine the media URN to use in the CBOR payload:
                // - For file-path args, use the stdin source's media URN if present (the target type)
                // - Otherwise, use the arg's media URN
                let argMediaUrn = try CSTaggedUrn.fromString(argDef.mediaUrn)
                let filePathPattern = try CSTaggedUrn.fromString(CSMediaFilePath)
                let filePathArrayPattern = try CSTaggedUrn.fromString(CSMediaFilePathArray)

                let isFilePath = (try? filePathPattern.accepts(argMediaUrn)) != nil ||
                                 (try? filePathArrayPattern.accepts(argMediaUrn)) != nil

                var mediaUrn = argDef.mediaUrn
                if isFilePath {
                    // Check if there's a stdin source and use its media URN
                    for source in argDef.sources {
                        if case .stdin(let stdinMediaUrn) = source {
                            mediaUrn = stdinMediaUrn
                            break
                        }
                    }
                }

                arguments.append(CapArgumentValue(mediaUrn: mediaUrn, value: v))
            } else if argDef.required {
                // Required argument not found
                let sources = argDef.sources.map { source -> String in
                    switch source {
                    case .cliFlag(let flag): return flag
                    case .positional(let pos): return "<pos \(pos)>"
                    case .stdin(_): return "<stdin>"
                    }
                }.joined(separator: " or ")
                throw PluginRuntimeError.missingArgument("Required argument '\(argDef.mediaUrn)' not provided. Use: \(sources)")
            }
        }

        // Check if any argument has stdin source (indicates file-path conversion happened)
        var hasStdinSourceArg = false
        for argDef in cap.args {
            if argDef.sources.contains(where: { source in
                if case .stdin(_) = source { return true }
                return false
            }) {
                hasStdinSourceArg = true
                break
            }
        }

        // Build CBOR arguments array if we have arguments with stdin sources
        // (this matches the Rust implementation for file-path conversion)
        if !arguments.isEmpty && hasStdinSourceArg {
            // Build CBOR: [{media_urn: "...", value: bytes}, ...]
            var cborArgs: [CBOR] = []
            for arg in arguments {
                let argMap: CBOR = .map([
                    .utf8String("media_urn"): .utf8String(arg.mediaUrn),
                    .utf8String("value"): .byteString([UInt8](arg.value))
                ])
                cborArgs.append(argMap)
            }

            let cborArray = CBOR.array(cborArgs)
            return Data(cborArray.encode())
        } else if !arguments.isEmpty {
            // No stdin sources - use JSON payload (old behavior)
            var jsonObj: [String: Any] = [:]
            for arg in arguments {
                // Try to parse as JSON first
                if let parsed = try? JSONSerialization.jsonObject(with: arg.value) {
                    // Use the last part of media_urn as key
                    let key = extractArgKey(from: arg.mediaUrn)
                    jsonObj[key] = parsed
                } else if let str = String(data: arg.value, encoding: .utf8) {
                    let key = extractArgKey(from: arg.mediaUrn)
                    jsonObj[key] = str
                } else {
                    throw PluginRuntimeError.cliError("Binary data cannot be passed via CLI flags. Use stdin instead.")
                }
            }
            return try JSONSerialization.data(withJSONObject: jsonObj)
        } else if let stdin = stdinData {
            // No arguments but have stdin data
            return stdin
        } else {
            // No arguments, no stdin - return empty payload
            return Data()
        }
    }

    /// Extract a key name from a media URN for JSON object.
    private func extractArgKey(from mediaUrn: String) -> String {
        // media:model-spec;textable -> model_spec
        var key = mediaUrn
        if key.hasPrefix("media:") {
            key = String(key.dropFirst(6))
        }
        if let semicolon = key.firstIndex(of: ";") {
            key = String(key[..<semicolon])
        }
        return key.replacingOccurrences(of: "-", with: "_")
    }

    /// Extract a single argument value from CLI args or stdin.
    private func extractArgValue(argDef: CapArg, cliArgs: [String], stdinData: Data?) throws -> Data? {
        // Check if this arg requires file-path to bytes conversion using proper URN matching
        let argMediaUrn = try CSTaggedUrn.fromString(argDef.mediaUrn)

        let filePathPattern = try CSTaggedUrn.fromString(CSMediaFilePath)
        let filePathArrayPattern = try CSTaggedUrn.fromString(CSMediaFilePathArray)

        // Check array first (more specific), then single file-path
        let isArray = (try? filePathArrayPattern.accepts(argMediaUrn)) != nil
        let isFilePath = isArray || (try? filePathPattern.accepts(argMediaUrn)) != nil

        // Get stdin source media URN if it exists (tells us target type)
        let hasStdinSource = argDef.sources.contains { source in
            if case .stdin(_) = source {
                return true
            }
            return false
        }

        // Try each source in order
        for source in argDef.sources {
            switch source {
            case .cliFlag(let flag):
                if let value = getCliFlagValue(args: cliArgs, flag: flag) {
                    // If file-path type with stdin source, read file(s)
                    if isFilePath && hasStdinSource {
                        return try readFilePathToBytes(value, isArray: isArray)
                    }
                    return Data(value.utf8)
                }
            case .positional(let position):
                let positional = getPositionalArgs(args: cliArgs)
                if position < positional.count {
                    let value = positional[position]
                    // If file-path type with stdin source, read file(s)
                    if isFilePath && hasStdinSource {
                        return try readFilePathToBytes(value, isArray: isArray)
                    }
                    return Data(value.utf8)
                }
            case .stdin(_):
                if let data = stdinData {
                    return data
                }
            }
        }

        // Try default value
        if let defaultValue = argDef.defaultValue {
            return Data(defaultValue.utf8)
        }

        return nil
    }

    /// Get value for a CLI flag (e.g., --model "value")
    private func getCliFlagValue(args: [String], flag: String) -> String? {
        var iter = args.makeIterator()
        while let arg = iter.next() {
            if arg == flag {
                return iter.next()
            }
            // Handle --flag=value format
            if arg.hasPrefix("\(flag)=") {
                return String(arg.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    /// Get positional arguments (non-flag arguments)
    private func getPositionalArgs(args: [String]) -> [String] {
        var positional: [String] = []
        var skipNext = false

        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if arg.hasPrefix("-") {
                // This is a flag - skip its value too if not using =
                if !arg.contains("=") {
                    skipNext = true
                }
            } else {
                positional.append(arg)
            }
        }
        return positional
    }

    /// Read stdin if data is available (non-blocking check).
    private func readStdinIfAvailable() throws -> Data? {
        let stdin = FileHandle.standardInput

        // Check if stdin is a terminal (interactive)
        if isatty(stdin.fileDescriptor) != 0 {
            return nil
        }

        // Non-blocking check: use poll() with 0 timeout to see if data is ready
        var pollfd = Darwin.pollfd(fd: stdin.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let pollResult = Darwin.poll(&pollfd, 1, 0)  // 0 timeout = non-blocking

        if pollResult < 0 {
            throw PluginRuntimeError.ioError("poll() failed")
        }

        // No data ready - return nil immediately without blocking
        if pollResult == 0 || (pollfd.revents & Int16(POLLIN)) == 0 {
            return nil
        }

        // Data is ready - read it
        let data = stdin.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    /// Build payload from streaming reader (testable version).
    ///
    /// This simulates the CBOR chunked request flow for CLI piped stdin:
    /// - Pure binary chunks from reader
    /// - Accumulated in chunks (respecting maxChunk size)
    /// - Built into CBOR arguments array (same format as CBOR mode)
    ///
    /// This makes all 4 modes use the SAME payload format:
    /// - CLI file path → read file → payload
    /// - CLI piped binary → chunk reader → payload
    /// - CBOR chunked → payload
    /// - CBOR file path → auto-convert → payload
    func buildPayloadFromStreamingReader(cap: CapDefinition, reader: Foundation.InputStream, maxChunk: Int) throws -> Data {
        // Accumulate chunks
        var chunks: [Data] = []
        var totalBytes = 0

        reader.open()
        defer { reader.close() }

        while reader.hasBytesAvailable {
            var buffer = [UInt8](repeating: 0, count: maxChunk)
            let bytesRead = reader.read(&buffer, maxLength: maxChunk)
            if bytesRead < 0 {
                throw PluginRuntimeError.ioError("Stream read error: \(reader.streamError?.localizedDescription ?? "unknown")")
            }
            if bytesRead == 0 {
                break
            }
            let chunk = Data(buffer.prefix(bytesRead))
            chunks.append(chunk)
            totalBytes += bytesRead
        }

        // Concatenate chunks
        var completePayload = Data()
        for chunk in chunks {
            completePayload.append(chunk)
        }

        // Build CBOR arguments array (same format as CBOR mode)
        let capUrn = try CSCapUrn.fromString(cap.urn)
        let expectedMediaUrn = capUrn.inSpec

        let arg = CapArgumentValue(mediaUrn: expectedMediaUrn, value: completePayload)

        // Encode as CBOR array
        let cborArgs: [CBOR] = [
            CBOR.map([
                CBOR.utf8String("media_urn"): CBOR.utf8String(arg.mediaUrn),
                CBOR.utf8String("value"): CBOR.byteString([UInt8](arg.value)),
            ])
        ]

        let cborArray = CBOR.array(cborArgs)
        return Data(cborArray.encode())
    }

    /// Print help message showing all available subcommands.
    private func printHelp(manifest: Manifest) {
        let stderr = FileHandle.standardError
        stderr.write(Data("\(manifest.name) v\(manifest.version)\n".utf8))
        stderr.write(Data("\(manifest.description)\n\n".utf8))
        stderr.write(Data("USAGE:\n".utf8))
        stderr.write(Data("    \(manifest.name.lowercased()) <COMMAND> [OPTIONS]\n\n".utf8))
        stderr.write(Data("COMMANDS:\n".utf8))
        stderr.write(Data("    manifest    Output the plugin manifest as JSON\n".utf8))

        for cap in manifest.caps {
            let desc = cap.capDescription ?? cap.title
            let line = String(format: "    %-12s %@\n", cap.command, desc)
            stderr.write(Data(line.utf8))
        }

        stderr.write(Data("\nRun '\(manifest.name.lowercased()) <COMMAND> --help' for more information on a command.\n".utf8))
    }

    /// Print help for a specific cap.
    private func printCapHelp(cap: CapDefinition) {
        let stderr = FileHandle.standardError
        stderr.write(Data("\(cap.title)\n".utf8))
        if let desc = cap.capDescription {
            stderr.write(Data("\(desc)\n".utf8))
        }
        stderr.write(Data("\nUSAGE:\n".utf8))
        stderr.write(Data("    plugin \(cap.command) [OPTIONS]\n\n".utf8))

        if !cap.args.isEmpty {
            stderr.write(Data("OPTIONS:\n".utf8))
            for arg in cap.args {
                let requiredStr = arg.required ? " (required)" : ""
                let desc = arg.argDescription ?? ""

                for source in arg.sources {
                    switch source {
                    case .cliFlag(let flag):
                        let line = String(format: "    %-16s %@%@\n", flag, desc, requiredStr)
                        stderr.write(Data(line.utf8))
                    case .positional(let pos):
                        let line = String(format: "    <arg%d>          %@%@\n", pos, desc, requiredStr)
                        stderr.write(Data(line.utf8))
                    case .stdin(_):
                        let line = "    <stdin>          \(desc)\(requiredStr)\n"
                        stderr.write(Data(line.utf8))
                    }
                }
            }
        }
    }

    // MARK: - CBOR Mode

    /// Run in CBOR mode - binary protocol over stdin/stdout.
    private func runCborMode() throws {
        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput

        let frameReader = FrameReader(handle: stdinHandle, limits: limits)
        let frameWriter = FrameWriter(handle: stdoutHandle, limits: limits)
        let writerLock = NSLock()
        let seqAssigner = SeqAssigner()

        // Perform handshake
        try performHandshake(reader: frameReader, writer: frameWriter)

        // Shared output sender — all outbound frames go through this.
        // Applies SeqAssigner and cleans up flow tracking on terminal frames.
        let outputSender = ChannelFrameSender(writer: frameWriter, writerLock: writerLock, seqAssigner: seqAssigner)

        // Track pending peer requests (plugin invoking host caps)
        // Maps request ID to AsyncStream.Continuation for forwarding response frames
        let pendingPeerRequests = NSMutableDictionary()
        let pendingPeerRequestsLock = NSLock()

        // Track pending heartbeats (plugin-initiated health probes)
        // Prevents infinite ping-pong: only respond to heartbeats we didn't send
        let pendingHeartbeats = NSMutableSet()
        let pendingHeartbeatsLock = NSLock()

        // Track pending incoming requests (host invoking plugin caps)
        // Maps request ID to (capUrn, continuation) - forwards request frames to handler
        struct PendingIncomingRequest {
            let capUrn: String
            let continuation: AsyncStream<Frame>.Continuation
        }
        var pendingIncoming: [MessageId: PendingIncomingRequest] = [:]
        let pendingIncomingLock = NSLock()

        // Main loop - stays responsive for heartbeats
        while true {

            // Read next frame
            let frame: Frame
            do {
                guard let f = try frameReader.read() else {
                    break // EOF - stdin closed
                }
                frame = f
            } catch {
                throw PluginRuntimeError.ioError("\(error)")
            }

            switch frame.frameType {
            case .req:
                // Extract routing_id (XID) FIRST — all error paths must include it
                let routingIdForErrors = frame.routingId

                guard let capUrn = frame.cap else {
                    var err = Frame.err(id: frame.id, code: "INVALID_REQUEST", message: "Request missing cap URN")
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                let rawPayload = frame.payload ?? Data()

                // Protocol v2: REQ must have empty payload — arguments come as streams
                if !rawPayload.isEmpty {
                    var err = Frame.err(
                        id: frame.id,
                        code: "PROTOCOL_ERROR",
                        message: "REQ frame must have empty payload — use STREAM_START for arguments"
                    )
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                // Find Op factory (using pattern matching to support wildcards)
                guard let factory = findHandler(capUrn: capUrn) else {
                    var err = Frame.err(id: frame.id, code: "NO_HANDLER", message: "No handler registered for cap: \(capUrn)")
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                // Parse cap URN for output media type
                let cap: CSCapUrn
                do {
                    cap = try CSCapUrn.fromString(capUrn)
                } catch {
                    var err = Frame.err(id: frame.id, code: "INVALID_CAP_URN", message: "Failed to parse cap URN: \(error)")
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                // Create AsyncStream for forwarding frames to handler
                let (stream, continuation) = AsyncStream<Frame>.makeStream()

                // Register pending request
                pendingIncomingLock.lock()
                pendingIncoming[frame.id] = PendingIncomingRequest(
                    capUrn: capUrn,
                    continuation: continuation
                )
                pendingIncomingLock.unlock()

                // Spawn handler thread immediately (matches Rust: spawn on REQ, stream frames)
                let requestId = frame.id
                let routingId = frame.routingId  // Capture routing_id to include in responses
                let outputMediaUrn = cap.getOutSpec()

                Thread.detachNewThread {
                    // Create blocking queue for frame delivery
                    let framesQueue = BlockingQueue<Frame>()

                    // Spawn async task to feed frames into queue
                    Task {
                        for await frame in stream {
                            framesQueue.enqueue(frame)
                        }
                        framesQueue.finish() // Signal no more frames
                    }

                    // Create iterator that reads from blocking queue
                    let frameIterator = AnyIterator<Frame> {
                        return framesQueue.dequeue()
                    }

                    // Demux frames into InputPackage
                    let inputPackage = demuxMultiStream(frameIterator: frameIterator)

                    // Create OutputStream for response (uses shared outputSender for seq assignment)
                    let responseStreamId = UUID().uuidString
                    let outputStream = OutputStream(
                        sender: outputSender,
                        streamId: responseStreamId,
                        mediaUrn: outputMediaUrn,
                        requestId: requestId,
                        routingId: routingId,
                        maxChunk: self.limits.maxChunk
                    )

                    // Create PeerInvoker (shares seqAssigner)
                    let peer = PeerInvokerImpl(
                        writer: frameWriter,
                        writerLock: writerLock,
                        seqAssigner: seqAssigner,
                        pendingRequests: pendingPeerRequests,
                        pendingRequestsLock: pendingPeerRequestsLock,
                        maxChunk: self.limits.maxChunk
                    )

                    do {
                        // Invoke Op handler — dispatchOp closes output stream on success
                        let op = factory()
                        try dispatchOp(op: op, input: inputPackage, output: outputStream, peer: peer)

                        // Send END frame with routing_id (via outputSender for seq assignment)
                        var endFrame = Frame.end(id: requestId, finalPayload: nil)
                        endFrame.routingId = routingId
                        try? outputSender.send(endFrame)

                    } catch {
                        var errFrame = Frame.err(id: requestId, code: "HANDLER_ERROR", message: "\(error)")
                        errFrame.routingId = routingId
                        try? outputSender.send(errFrame)
                    }
                }
                continue

            case .heartbeat:
                // Check if this is a response to a heartbeat we sent
                pendingHeartbeatsLock.lock()
                let isOurProbe = pendingHeartbeats.contains(frame.id)
                if isOurProbe {
                    pendingHeartbeats.remove(frame.id)
                }
                pendingHeartbeatsLock.unlock()

                if isOurProbe {
                    // Response to our health probe - host is alive, no action needed
                } else {
                    // Host-initiated heartbeat - respond immediately (non-flow, seq stays 0)
                    try outputSender.send(Frame.heartbeat(id: frame.id))
                }

            case .hello:
                // Unexpected HELLO after handshake - protocol error
                try outputSender.send(Frame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "Unexpected HELLO after handshake"))

            // case .res: REMOVED - old single-response protocol no longer supported

            case .chunk:
                // Forward frame to appropriate stream

                // Check if this is a chunk for an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming[frame.id] {
                    pendingReq.continuation.yield(frame)
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request chunk - must be a peer response chunk
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .end:
                // Forward frame to appropriate stream and finish it

                // Check if this is the end of an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming.removeValue(forKey: frame.id) {
                    pendingReq.continuation.yield(frame)
                    pendingReq.continuation.finish()
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request end - must be a peer response end
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                    pending.continuation.finish()
                    pendingPeerRequests.removeObject(forKey: frame.id)
                }
                pendingPeerRequestsLock.unlock()

            case .err:
                // Error frame from host - forward to pending peer request and finish stream
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                    pending.continuation.finish()
                    pendingPeerRequests.removeObject(forKey: frame.id)
                }
                pendingPeerRequestsLock.unlock()

            case .log:
                // Log frames from host - shouldn't normally receive these, ignore
                continue

            case .streamStart:
                // Forward frame to appropriate stream

                // Check if this is for an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming[frame.id] {
                    pendingReq.continuation.yield(frame)
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request - must be a peer response stream
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .streamEnd:
                // Forward frame to appropriate stream

                // Check if this is for an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming[frame.id] {
                    pendingReq.continuation.yield(frame)
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request - must be a peer response stream
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .relayNotify, .relayState:
                // Relay frame types should NEVER reach the plugin runtime — they are
                // intercepted by the relay layer. If one arrives here, it's a
                // protocol violation.
                throw PluginRuntimeError.protocolError("Relay frame type \(frame.frameType) must not reach plugin runtime")
            }
        }

        // Handlers run asynchronously via Task - they complete on their own
    }

    // MARK: - Handshake

    private func performHandshake(reader: FrameReader, writer: FrameWriter) throws {
        // Read host's HELLO first (host initiates)
        let theirFrame: Frame
        do {
            guard let f = try reader.read() else {
                throw PluginRuntimeError.handshakeFailed("Connection closed before HELLO")
            }
            theirFrame = f
        } catch let error as FrameError {
            throw PluginRuntimeError.handshakeFailed("\(error)")
        }

        guard theirFrame.frameType == .hello else {
            throw PluginRuntimeError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
        }

        // Protocol v2: All three limit fields are REQUIRED
        guard let theirMaxFrame = theirFrame.helloMaxFrame else {
            throw PluginRuntimeError.handshakeFailed("Protocol violation: HELLO missing max_frame")
        }
        guard let theirMaxChunk = theirFrame.helloMaxChunk else {
            throw PluginRuntimeError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
        }
        guard let theirMaxReorderBuffer = theirFrame.helloMaxReorderBuffer else {
            throw PluginRuntimeError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
        }

        // Negotiate minimum of both sides
        let ourLimits = Limits()
        let negotiatedLimits = Limits(
            maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
            maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
            maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
        )

        self.limits = negotiatedLimits

        // Send our HELLO with negotiated limits AND manifest
        // The manifest is REQUIRED - this is the ONLY way to communicate plugin capabilities
        let ourHello = Frame.helloWithManifest(limits: negotiatedLimits, manifest: manifestData)
        do {
            try writer.write(ourHello)
        } catch {
            throw PluginRuntimeError.handshakeFailed("Failed to send HELLO: \(error)")
        }

        // Update reader/writer limits
        reader.setLimits(negotiatedLimits)
        writer.setLimits(negotiatedLimits)
    }

    // MARK: - Accessors

    /// Get the negotiated protocol limits
    public var negotiatedLimits: Limits {
        return limits
    }
}
