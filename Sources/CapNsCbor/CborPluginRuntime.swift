//
//  CborPluginRuntime.swift
//  CapNsCbor
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
//  let runtime = CborPluginRuntime(manifest: manifestData)
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

// MARK: - Error Types

/// Errors specific to PluginRuntime operations
public enum CborPluginRuntimeError: Error, LocalizedError, @unchecked Sendable {
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

// MARK: - Stream Chunk Type - REMOVED
// StreamChunk wrapper removed - handlers now receive bare CborFrame objects directly

// MARK: - Argument Types

/// Unified argument for cap invocation - arguments are identified by media_urn.
public struct CborCapArgumentValue: Sendable {
    /// Semantic identifier, e.g., "media:model-spec;textable;form=scalar"
    public let mediaUrn: String
    /// Value bytes (UTF-8 for text, raw for binary)
    public let value: Data

    public init(mediaUrn: String, value: Data) {
        self.mediaUrn = mediaUrn
        self.value = value
    }

    /// Create from a string value
    public static func fromString(mediaUrn: String, value: String) -> CborCapArgumentValue {
        guard let data = value.data(using: .utf8) else {
            fatalError("Failed to encode string as UTF-8: \(value)")
        }
        return CborCapArgumentValue(mediaUrn: mediaUrn, value: data)
    }

    /// Get the value as a UTF-8 string (fails for binary data)
    public func valueAsString() throws -> String {
        guard let str = String(data: value, encoding: .utf8) else {
            throw CborPluginRuntimeError.deserializationError("Value is not valid UTF-8")
        }
        return str
    }
}

// MARK: - StreamEmitter Protocol

/// Protocol for streaming output from handlers.
/// Thread-safe for use in concurrent handlers.
///
/// IMPORTANT: Handlers MUST emit CBOR values, not raw bytes.
/// The emitter handles protocol framing (STREAM_START + CHUNK + STREAM_END).
public protocol CborStreamEmitter: Sendable {
    /// Emit a CBOR value as output.
    /// The value is CBOR-encoded once and sent as raw CBOR bytes in CHUNK frames.
    /// No double-encoding: one CBOR layer from handler to consumer.
    /// Large values are automatically split into multiple chunks.
    ///
    /// Handlers construct CBOR values using SwiftCBOR's CBOR enum:
    /// - .byteString([UInt8]) for binary data
    /// - .utf8String(String) for text
    /// - .array([CBOR]) for arrays
    /// - .map([CBOR: CBOR]) for structured data
    func emitCbor(_ value: CBOR) throws

    /// Emit a log message at the given level (sent as LOG frame, side-channel)
    func emitLog(level: String, message: String)
}

// MARK: - PeerInvoker Protocol

/// Allows handlers to invoke caps on the peer (host).
///
/// This protocol enables bidirectional communication where a plugin handler can
/// invoke caps on the host while processing a request. This is essential for
/// sandboxed plugins that need to delegate certain operations (like model
/// downloading) to the host.
///
/// The `invoke` method sends a REQ frame to the host and spawns a thread that
/// receives response frames, yielding bare CBOR Frame objects as they arrive.
public protocol CborPeerInvoker: Sendable {
    /// Invoke a cap on the host with arguments.
    ///
    /// Sends a REQ frame (empty payload) + STREAM_START + CHUNK + STREAM_END + END
    /// for each argument. Spawns a dedicated thread that forwards response frames
    /// to an AsyncStream. Returns bare CBOR Frame objects (STREAM_START, CHUNK,
    /// STREAM_END, END, ERR) as they arrive from the host. The consumer processes
    /// frames directly - no decoding, no wrapper types.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN to invoke on the host
    ///   - arguments: Arguments identified by media_urn
    /// - Returns: AsyncStream yielding bare CborFrame objects
    func invoke(capUrn: String, arguments: [CborCapArgumentValue]) throws -> AsyncStream<CborFrame>
}

/// A no-op PeerInvoker that always returns an error.
/// Used when peer invocation is not supported (CLI mode).
public struct NoCborPeerInvoker: CborPeerInvoker {
    public init() {}

    public func invoke(capUrn: String, arguments: [CborCapArgumentValue]) throws -> AsyncStream<CborFrame> {
        throw CborPluginRuntimeError.peerRequestError("Peer invocation not supported in CLI mode")
    }
}

// MARK: - CliStreamEmitter

/// CLI-mode emitter that writes directly to stdout.
/// Extracts raw bytes/text from CBOR values for CLI output.
public final class CliStreamEmitter: CborStreamEmitter, @unchecked Sendable {
    /// Whether to add newlines after each emit (NDJSON style)
    let ndjson: Bool
    private let stdoutHandle: FileHandle

    /// Create a new CLI emitter with NDJSON formatting (newline after each emit)
    public init() {
        self.ndjson = true
        self.stdoutHandle = FileHandle.standardOutput
    }

    /// Create a CLI emitter without NDJSON formatting
    public init(ndjson: Bool) {
        self.ndjson = ndjson
        self.stdoutHandle = FileHandle.standardOutput
    }

    public func emitCbor(_ value: CBOR) throws {
        // Extract raw bytes/text from CBOR and emit to stdout
        extractAndWrite(value, to: stdoutHandle)

        if ndjson {
            stdoutHandle.write(Data("\n".utf8))
        }
    }

    /// Recursively extract and write raw content from CBOR values
    private func extractAndWrite(_ value: CBOR, to handle: FileHandle) {
        switch value {
        case .byteString(let bytes):
            handle.write(Data(bytes))

        case .utf8String(let text):
            handle.write(Data(text.utf8))

        case .array(let items):
            // Emit each element's raw content
            for item in items {
                extractAndWrite(item, to: handle)
            }

        case .map(let m):
            // Extract "value" field if present, otherwise fail
            if let val = m[.utf8String("value")] {
                extractAndWrite(val, to: handle)
            } else {
                // No value field - this is a protocol error
                fatalError("CLI emitter received CBOR map without 'value' field. Handler must emit raw data types.")
            }

        default:
            // Unsupported CBOR type for CLI output
            fatalError("CLI emitter received unsupported CBOR type: \(value). Handler must emit byteString, utf8String, or array.")
        }
    }

    public func emitLog(level: String, message: String) {
        // In CLI mode, logs go to stderr
        let logLine = "[\(level.uppercased())] \(message)\n"
        FileHandle.standardError.write(Data(logLine.utf8))
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
/// - Throws: CborPluginRuntimeError if parsing fails or no matching argument found
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
        throw CborPluginRuntimeError.capUrnError("Failed to parse cap URN '\(capUrn)': \(error.localizedDescription)")
    }
    let expectedInput = parsedUrn.getInSpec()

    // Parse the CBOR payload as an array of argument maps
    let cborValue: CBOR
    do {
        guard let decoded = try CBOR.decode([UInt8](payload)) else {
            throw CborPluginRuntimeError.deserializationError("Failed to decode CBOR payload")
        }
        cborValue = decoded
    } catch {
        throw CborPluginRuntimeError.deserializationError("Failed to parse CBOR arguments: \(error)")
    }

    // Must be an array
    guard case .array(let arguments) = cborValue else {
        throw CborPluginRuntimeError.deserializationError("CBOR arguments must be an array")
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
    throw CborPluginRuntimeError.deserializationError(
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
/// The runtime sends STREAM_END + END frames after handler completes.
///
/// The `CborPeerInvoker` allows the handler to invoke caps on the host (peer) during
/// request processing. This enables bidirectional communication for operations
/// like model downloading that sandboxed plugins cannot perform directly.
public typealias CborCapHandler = @Sendable (
    AsyncStream<CborFrame>,
    CborStreamEmitter,
    CborPeerInvoker
) async throws -> Void

// MARK: - Internal: Pending Peer Request

/// Internal struct to track pending peer requests (plugin invoking host caps).
/// Now uses AsyncStream continuation to forward frames instead of condition variables.
private struct PendingPeerRequest {
    let continuation: AsyncStream<CborFrame>.Continuation
    var isComplete: Bool
}

// MARK: - Internal: ThreadSafeStreamEmitter

/// Thread-safe emitter implementation that writes CBOR frames with stream multiplexing.
/// Sends STREAM_START before first emission, then CHUNK frames, caller must send STREAM_END + END.
@available(macOS 10.15.4, iOS 13.4, *)
final class ThreadSafeStreamEmitter: CborStreamEmitter, @unchecked Sendable {
    private let writer: CborFrameWriter
    private let writerLock: NSLock
    private let requestId: CborMessageId
    private let streamId: String  // Unique stream ID for this response
    private let mediaUrn: String  // Response media type
    private let maxChunk: Int     // Negotiated max chunk size
    private var seq: UInt64 = 0
    private let seqLock = NSLock()
    private var streamStarted: Bool = false
    private let streamLock = NSLock()

    /// Whether STREAM_START was actually sent (used by callers to guard STREAM_END)
    var didStartStream: Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        return streamStarted
    }

    init(writer: CborFrameWriter, writerLock: NSLock, requestId: CborMessageId, streamId: String, mediaUrn: String, maxChunk: Int) {
        self.writer = writer
        self.writerLock = writerLock
        self.requestId = requestId
        self.streamId = streamId
        self.mediaUrn = mediaUrn
        self.maxChunk = maxChunk
    }

    func emitCbor(_ value: CBOR) throws {
        // Send STREAM_START if this is the first emission
        streamLock.lock()
        if !streamStarted {
            streamStarted = true
            streamLock.unlock()

            let startFrame = CborFrame.streamStart(
                reqId: requestId,
                streamId: streamId,
                mediaUrn: mediaUrn
            )
            writerLock.lock()
            do {
                try writer.write(startFrame)
            } catch {
                writerLock.unlock()
                throw CborPluginRuntimeError.ioError("Failed to write STREAM_START: \(error)")
            }
            writerLock.unlock()
        } else {
            streamLock.unlock()
        }

        // Encode CBOR value to bytes
        let bytes = Data(value.encode())

        // Auto-chunk using negotiated limit
        var offset = 0

        while offset < bytes.count {
            let chunkSize = min(maxChunk, bytes.count - offset)
            let chunkData = bytes.subdata(in: offset..<offset+chunkSize)

            seqLock.lock()
            let currentSeq = seq
            seq += 1
            seqLock.unlock()

            let frame = CborFrame.chunk(
                reqId: requestId,
                streamId: streamId,
                seq: currentSeq,
                payload: chunkData
            )

            writerLock.lock()
            do {
                try writer.write(frame)
            } catch {
                writerLock.unlock()
                throw CborPluginRuntimeError.ioError("Failed to write CHUNK: \(error)")
            }
            writerLock.unlock()

            offset += chunkSize
        }
    }

    func emitLog(level: String, message: String) {
        let frame = CborFrame.log(id: requestId, level: level, message: message)

        writerLock.lock()
        defer { writerLock.unlock() }
        try? writer.write(frame)  // Best effort - log failures are not fatal
    }
}

// MARK: - Internal: PeerInvokerImpl

/// Implementation of PeerInvoker that sends REQ frames to the host.
/// Spawns a thread that forwards response frames to an AsyncStream.
@available(macOS 10.15.4, iOS 13.4, *)
final class PeerInvokerImpl: CborPeerInvoker, @unchecked Sendable {
    private let writer: CborFrameWriter
    private let writerLock: NSLock
    private let pendingRequests: NSMutableDictionary // [CborMessageId: PendingPeerRequest]
    private let pendingRequestsLock: NSLock
    private let maxChunk: Int

    init(writer: CborFrameWriter, writerLock: NSLock, pendingRequests: NSMutableDictionary, pendingRequestsLock: NSLock, maxChunk: Int) {
        self.writer = writer
        self.writerLock = writerLock
        self.pendingRequests = pendingRequests
        self.pendingRequestsLock = pendingRequestsLock
        self.maxChunk = maxChunk
    }

    func invoke(capUrn: String, arguments: [CborCapArgumentValue]) throws -> AsyncStream<CborFrame> {
        // Generate a new message ID for this request
        let requestId = CborMessageId.newUUID()

        // Create AsyncStream and continuation for response frames
        let (stream, continuation) = AsyncStream<CborFrame>.makeStream()

        // Create pending request tracking
        let pending = PendingPeerRequest(
            continuation: continuation,
            isComplete: false
        )

        // Register the pending request before sending
        pendingRequestsLock.lock()
        pendingRequests[requestId] = pending
        pendingRequestsLock.unlock()

        // Protocol v2: REQ(empty) + STREAM_START + CHUNK(s) + STREAM_END + END per argument
        writerLock.lock()
        do {
            // 1. REQ with empty payload
            let reqFrame = CborFrame.req(id: requestId, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
            try writer.write(reqFrame)

            // 2. Each argument as an independent stream
            for arg in arguments {
                let streamId = UUID().uuidString

                // STREAM_START
                let startFrame = CborFrame.streamStart(reqId: requestId, streamId: streamId, mediaUrn: arg.mediaUrn)
                try writer.write(startFrame)

                // CHUNK(s)
                var offset = 0
                var seq: UInt64 = 0
                while offset < arg.value.count {
                    let chunkSize = min(arg.value.count - offset, maxChunk)
                    let chunkData = arg.value.subdata(in: offset..<(offset + chunkSize))
                    let chunkFrame = CborFrame.chunk(reqId: requestId, streamId: streamId, seq: seq, payload: chunkData)
                    try writer.write(chunkFrame)
                    offset += chunkSize
                    seq += 1
                }

                // STREAM_END
                let streamEndFrame = CborFrame.streamEnd(reqId: requestId, streamId: streamId)
                try writer.write(streamEndFrame)
            }

            // 3. END
            let endFrame = CborFrame.end(id: requestId)
            try writer.write(endFrame)
        } catch {
            writerLock.unlock()
            pendingRequestsLock.lock()
            pendingRequests.removeObject(forKey: requestId)
            pendingRequestsLock.unlock()
            continuation.finish()
            throw CborPluginRuntimeError.peerRequestError("Failed to send peer request frames: \(error)")
        }
        writerLock.unlock()

        // Return the AsyncStream - frames will be forwarded by reader loop
        return stream
    }
}

// MARK: - Manifest Types (for CLI mode)

/// Source for extracting argument values in CLI mode.
public enum CborArgSource: Codable, Sendable {
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
public struct CborCapArg: Codable, Sendable {
    public let mediaUrn: String
    public let required: Bool
    public let sources: [CborArgSource]
    public let argDescription: String?
    public let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case mediaUrn = "media_urn"
        case required
        case sources
        case argDescription = "description"
        case defaultValue = "default"
    }

    public init(mediaUrn: String, required: Bool, sources: [CborArgSource], argDescription: String? = nil, defaultValue: String? = nil) {
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
        sources = try container.decodeIfPresent([CborArgSource].self, forKey: .sources) ?? []
        argDescription = try container.decodeIfPresent(String.self, forKey: .argDescription)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
    }
}

/// Cap definition in the manifest.
public struct CborCapDefinition: Codable, Sendable {
    public let urn: String
    public let title: String
    public let command: String
    public let capDescription: String?
    public let args: [CborCapArg]

    enum CodingKeys: String, CodingKey {
        case urn
        case title
        case command
        case capDescription = "description"
        case args
    }

    public init(urn: String, title: String, command: String, capDescription: String? = nil, args: [CborCapArg] = []) {
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
        args = try container.decodeIfPresent([CborCapArg].self, forKey: .args) ?? []
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
public struct CborManifest: Codable, Sendable {
    public let name: String
    public let version: String
    public let description: String
    public let caps: [CborCapDefinition]

    public init(name: String, version: String, description: String, caps: [CborCapDefinition]) {
        self.name = name
        self.version = version
        self.description = description
        self.caps = caps
    }
}

// MARK: - CborPluginRuntime

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
public final class CborPluginRuntime: @unchecked Sendable {

    // MARK: - Properties

    private var handlers: [String: CborCapHandler] = [:]
    private let handlersLock = NSLock()

    private var limits = CborLimits()

    /// Plugin manifest JSON data - sent in HELLO response.
    /// This is REQUIRED - plugins must provide their manifest.
    let manifestData: Data

    /// Parsed manifest for CLI mode support.
    /// Contains cap definitions with command names and argument sources.
    let parsedManifest: CborManifest?

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
    /// - Parameter manifest: JSON-encoded manifest data
    public init(manifest: Data) {
        self.manifestData = manifest
        // Parse manifest for CLI mode support
        self.parsedManifest = try? JSONDecoder().decode(CborManifest.self, from: manifest)
    }

    /// Create a plugin runtime with manifest JSON string.
    /// - Parameter manifestJSON: JSON string of the manifest
    public convenience init(manifestJSON: String) {
        guard let data = manifestJSON.data(using: .utf8) else {
            fatalError("Failed to encode manifest JSON as UTF-8")
        }
        self.init(manifest: data)
    }

    // MARK: - Handler Registration

    /// Register a raw Frame-based handler.
    /// Handler receives AsyncStream of bare CBOR Frame objects and must emit CBOR values via emitter.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN pattern to handle
    ///   - handler: Frame-based handler closure
    public func registerRaw(capUrn: String, handler: @escaping CborCapHandler) {
        handlersLock.lock()
        handlers[capUrn] = handler
        handlersLock.unlock()
    }

    /// Register a raw Data handler (no JSON serialization).
    /// Accumulates frames into Data, passes raw bytes to handler,
    /// and CBOR-encodes the returned Data.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN pattern to handle
    ///   - handler: Handler that receives raw Data and returns raw Data
    public func register(
        capUrn: String,
        handler: @escaping @Sendable (Data, CborStreamEmitter, CborPeerInvoker) async throws -> Data
    ) {
        let frameHandler: CborCapHandler = { frames, emitter, peer in
            // Accumulate all frame payloads
            var accumulated = Data()
            for await frame in frames {
                if let payload = frame.payload {
                    accumulated.append(payload)
                }
            }

            // Invoke handler with raw bytes
            let response = try await handler(accumulated, emitter, peer)

            // Emit response as CBOR byteString (matches Rust emit_cbor)
            try emitter.emitCbor(.byteString([UInt8](response)))
        }

        handlersLock.lock()
        handlers[capUrn] = frameHandler
        handlersLock.unlock()
    }

    /// Register a handler with typed request/response.
    /// Automatically accumulates frames and handles serialization.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN pattern to handle
    ///   - handler: Typed handler closure
    public func register<Req: Decodable & Sendable, Res: Encodable & Sendable>(
        capUrn: String,
        handler: @escaping @Sendable (Req, CborStreamEmitter, CborPeerInvoker) async throws -> Res
    ) {
        // Wrapper that accumulates frames then deserializes
        let frameHandler: CborCapHandler = { frames, emitter, peer in
            // Accumulate all frame payloads
            var accumulated = Data()
            for await frame in frames {
                if let payload = frame.payload {
                    accumulated.append(payload)
                }
            }

            // Deserialize request
            let decoder = JSONDecoder()
            let request = try decoder.decode(Req.self, from: accumulated)

            // Invoke handler
            let response = try await handler(request, emitter, peer)

            // Emit response as CBOR byteString
            let encoder = JSONEncoder()
            let responseData = try encoder.encode(response)
            try emitter.emitCbor(.byteString([UInt8](responseData)))
        }

        handlersLock.lock()
        handlers[capUrn] = frameHandler
        handlersLock.unlock()
    }

    /// Find a handler for a cap URN (supports exact match and pattern matching)
    func findHandler(capUrn: String) -> CborCapHandler? {
        handlersLock.lock()
        defer { handlersLock.unlock() }

        // Exact match first
        if let handler = handlers[capUrn] {
            return handler
        }

        // Pattern matching would go here if needed
        // For now, just exact match
        return nil
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
    /// - Throws: CborPluginRuntimeError on fatal errors
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
                try await self.runCliMode(args)
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
            throw CborPluginRuntimeError.cliError("CLI mode failed to complete")
        }
    }

    // MARK: - CLI Mode

    /// Run in CLI mode - parse arguments and invoke handler.
    private func runCliMode(_ args: [String]) async throws {
        guard let manifest = parsedManifest else {
            throw CborPluginRuntimeError.manifestError("Failed to parse manifest for CLI mode")
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
            throw CborPluginRuntimeError.unknownSubcommand("Unknown command '\(subcommand)'. Run with --help to see available commands.")
        }

        // Handle --help for specific command
        if args.count == 3 && (args[2] == "--help" || args[2] == "-h") {
            printCapHelp(cap: cap)
            return
        }

        // Find handler
        guard let handler = findHandler(capUrn: cap.urn) else {
            throw CborPluginRuntimeError.noHandler("No handler registered for cap '\(cap.urn)'")
        }

        // Build payload from CLI arguments
        let cliArgs = Array(args.dropFirst(2))
        let payload = try buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Extract effective payload from CBOR arguments (same as CBOR mode)
        // CLI mode builds CBOR arguments, so content type is application/cbor
        let effectivePayload = try extractEffectivePayload(payload: payload, contentType: "application/cbor", capUrn: cap.urn)

        // Parse cap URN to get input spec
        let capParsed = try CSCapUrn.fromString(cap.urn)
        let inputMediaUrn = capParsed.getInSpec()

        // Create AsyncStream with Frame sequence: STREAM_START → CHUNK → STREAM_END → END
        let (stream, continuation) = AsyncStream<CborFrame>.makeStream()
        let requestId = CborMessageId.newUUID()
        let inputStreamId = "cli-input"

        // STREAM_START
        continuation.yield(CborFrame.streamStart(
            reqId: requestId,
            streamId: inputStreamId,
            mediaUrn: inputMediaUrn
        ))

        // CHUNK (single chunk with all data)
        continuation.yield(CborFrame.chunk(
            reqId: requestId,
            streamId: inputStreamId,
            seq: 0,
            payload: effectivePayload
        ))

        // STREAM_END
        continuation.yield(CborFrame.streamEnd(
            reqId: requestId,
            streamId: inputStreamId
        ))

        // END
        continuation.yield(CborFrame.end(id: requestId))
        continuation.finish()

        // Create CLI-mode emitter and no-op peer invoker
        let emitter = CliStreamEmitter()
        let peer = NoCborPeerInvoker()

        // Invoke handler (async)
        try await handler(stream, emitter, peer)

        // Handler emits directly via emitter - no return value
    }

    /// Find a cap by its command name (the CLI subcommand).
    private func findCapByCommand(manifest: CborManifest, commandName: String) -> CborCapDefinition? {
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
    /// - Throws: CborPluginRuntimeError.ioError if file cannot be read with clear error message
    private func readFilePathToBytes(_ pathValue: String, isArray: Bool) throws -> Data {
        if isArray {
            // Parse JSON array of path patterns
            guard let pathData = pathValue.data(using: .utf8),
                  let pathPatterns = try? JSONSerialization.jsonObject(with: pathData) as? [String] else {
                throw CborPluginRuntimeError.cliError(
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
                        throw CborPluginRuntimeError.ioError(
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
                        throw CborPluginRuntimeError.cliError(
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
                    throw CborPluginRuntimeError.ioError(
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
                throw CborPluginRuntimeError.ioError(
                    "Failed to read file '\(pathValue)': \(error.localizedDescription)"
                )
            }
        }
    }

    /// Build payload from CLI arguments based on cap's arg definitions.
    /// Internal for testing purposes.
    func buildPayloadFromCli(cap: CborCapDefinition, cliArgs: [String]) throws -> Data {
        var arguments: [CborCapArgumentValue] = []

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

                arguments.append(CborCapArgumentValue(mediaUrn: mediaUrn, value: v))
            } else if argDef.required {
                // Required argument not found
                let sources = argDef.sources.map { source -> String in
                    switch source {
                    case .cliFlag(let flag): return flag
                    case .positional(let pos): return "<pos \(pos)>"
                    case .stdin(_): return "<stdin>"
                    }
                }.joined(separator: " or ")
                throw CborPluginRuntimeError.missingArgument("Required argument '\(argDef.mediaUrn)' not provided. Use: \(sources)")
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
                    throw CborPluginRuntimeError.cliError("Binary data cannot be passed via CLI flags. Use stdin instead.")
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
        // media:model-spec;textable;form=scalar -> model_spec
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
    private func extractArgValue(argDef: CborCapArg, cliArgs: [String], stdinData: Data?) throws -> Data? {
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

        let data = stdin.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    /// Print help message showing all available subcommands.
    private func printHelp(manifest: CborManifest) {
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
    private func printCapHelp(cap: CborCapDefinition) {
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

        let frameReader = CborFrameReader(handle: stdinHandle, limits: limits)
        let frameWriter = CborFrameWriter(handle: stdoutHandle, limits: limits)
        let writerLock = NSLock()

        // Perform handshake
        try performHandshake(reader: frameReader, writer: frameWriter)

        // Track pending peer requests (plugin invoking host caps)
        // Maps request ID to AsyncStream.Continuation for forwarding response frames
        let pendingPeerRequests = NSMutableDictionary()
        let pendingPeerRequestsLock = NSLock()

        // Track pending incoming requests (host invoking plugin caps)
        // Maps request ID to (capUrn, continuation) - forwards request frames to handler
        struct PendingIncomingRequest {
            let capUrn: String
            let continuation: AsyncStream<CborFrame>.Continuation
        }
        var pendingIncoming: [CborMessageId: PendingIncomingRequest] = [:]
        let pendingIncomingLock = NSLock()

        // Main loop - stays responsive for heartbeats
        while true {

            // Read next frame
            let frame: CborFrame
            do {
                guard let f = try frameReader.read() else {
                    break // EOF - stdin closed
                }
                frame = f
            } catch {
                throw CborPluginRuntimeError.ioError("\(error)")
            }

            switch frame.frameType {
            case .req:
                guard let capUrn = frame.cap else {
                    let errFrame = CborFrame.err(id: frame.id, code: "INVALID_REQUEST", message: "Request missing cap URN")
                    writerLock.lock()
                    try? frameWriter.write(errFrame)
                    writerLock.unlock()
                    continue
                }

                let rawPayload = frame.payload ?? Data()

                // Protocol v2: REQ must have empty payload — arguments come as streams
                if !rawPayload.isEmpty {
                    let errFrame = CborFrame.err(
                        id: frame.id,
                        code: "PROTOCOL_ERROR",
                        message: "REQ frame must have empty payload — use STREAM_START for arguments"
                    )
                    writerLock.lock()
                    try? frameWriter.write(errFrame)
                    writerLock.unlock()
                    continue
                }

                // Find handler
                let handler: CborCapHandler?
                handlersLock.lock()
                handler = handlers[capUrn]
                handlersLock.unlock()

                guard let handler = handler else {
                    let errFrame = CborFrame.err(id: frame.id, code: "NO_HANDLER", message: "No handler registered for cap: \(capUrn)")
                    writerLock.lock()
                    try? frameWriter.write(errFrame)
                    writerLock.unlock()
                    continue
                }

                // Parse cap URN for output media type
                let cap: CSCapUrn
                do {
                    cap = try CSCapUrn.fromString(capUrn)
                } catch {
                    let errFrame = CborFrame.err(id: frame.id, code: "INVALID_CAP_URN", message: "Failed to parse cap URN: \(error)")
                    writerLock.lock()
                    try? frameWriter.write(errFrame)
                    writerLock.unlock()
                    continue
                }

                // Create AsyncStream for forwarding frames to handler
                let (stream, continuation) = AsyncStream<CborFrame>.makeStream()

                // Register pending request
                pendingIncomingLock.lock()
                pendingIncoming[frame.id] = PendingIncomingRequest(
                    capUrn: capUrn,
                    continuation: continuation
                )
                pendingIncomingLock.unlock()

                // Spawn async task for handler
                let requestId = frame.id
                let outputMediaUrn = cap.getOutSpec()

                DispatchQueue.global().async {
                    Task {
                        // Generate unique stream ID for response
                        let responseStreamId = UUID().uuidString

                        // Create emitter with stream ID and output media URN
                        let emitter = ThreadSafeStreamEmitter(
                            writer: frameWriter,
                            writerLock: writerLock,
                            requestId: requestId,
                            streamId: responseStreamId,
                            mediaUrn: outputMediaUrn,
                            maxChunk: self.limits.maxChunk
                        )

                        let peer = PeerInvokerImpl(
                            writer: frameWriter,
                            writerLock: writerLock,
                            pendingRequests: pendingPeerRequests,
                            pendingRequestsLock: pendingPeerRequestsLock,
                            maxChunk: self.limits.maxChunk
                        )

                        do {
                            // Execute handler with frame stream
                            try await handler(stream, emitter, peer)

                            // Send STREAM_END + END after handler completes
                            // Only send STREAM_END if STREAM_START was actually sent
                            DispatchQueue.global().sync {
                                writerLock.lock()
                                if emitter.didStartStream {
                                    let streamEndFrame = CborFrame.streamEnd(reqId: requestId, streamId: responseStreamId)
                                    try? frameWriter.write(streamEndFrame)
                                }
                                let endFrame = CborFrame.end(id: requestId, finalPayload: nil)
                                try? frameWriter.write(endFrame)
                                writerLock.unlock()
                            }

                        } catch {
                            let errFrame = CborFrame.err(id: requestId, code: "HANDLER_ERROR", message: "\(error)")

                            DispatchQueue.global().sync {
                                writerLock.lock()
                                try? frameWriter.write(errFrame)
                                writerLock.unlock()
                            }
                        }
                    }
                }
                continue

            case .heartbeat:
                // Respond immediately - never blocked by handlers
                let response = CborFrame.heartbeat(id: frame.id)
                writerLock.lock()
                try frameWriter.write(response)
                writerLock.unlock()

            case .hello:
                // Unexpected HELLO after handshake - protocol error
                let errFrame = CborFrame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "Unexpected HELLO after handshake")
                writerLock.lock()
                try frameWriter.write(errFrame)
                writerLock.unlock()

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
                throw CborPluginRuntimeError.protocolError("Relay frame type \(frame.frameType) must not reach plugin runtime")
            }
        }

        // Handlers run asynchronously via Task - they complete on their own
    }

    // MARK: - Handshake

    private func performHandshake(reader: CborFrameReader, writer: CborFrameWriter) throws {
        // Read host's HELLO first (host initiates)
        let theirFrame: CborFrame
        do {
            guard let f = try reader.read() else {
                throw CborPluginRuntimeError.handshakeFailed("Connection closed before HELLO")
            }
            theirFrame = f
        } catch let error as CborError {
            throw CborPluginRuntimeError.handshakeFailed("\(error)")
        }

        guard theirFrame.frameType == .hello else {
            throw CborPluginRuntimeError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
        }

        // Negotiate limits
        let theirMaxFrame = theirFrame.helloMaxFrame ?? DEFAULT_MAX_FRAME
        let theirMaxChunk = theirFrame.helloMaxChunk ?? DEFAULT_MAX_CHUNK

        let negotiatedLimits = CborLimits(
            maxFrame: min(DEFAULT_MAX_FRAME, theirMaxFrame),
            maxChunk: min(DEFAULT_MAX_CHUNK, theirMaxChunk)
        )

        self.limits = negotiatedLimits

        // Send our HELLO with negotiated limits AND manifest
        // The manifest is REQUIRED - this is the ONLY way to communicate plugin capabilities
        let ourHello = CborFrame.hello(maxFrame: negotiatedLimits.maxFrame, maxChunk: negotiatedLimits.maxChunk, manifest: manifestData)
        do {
            try writer.write(ourHello)
        } catch {
            throw CborPluginRuntimeError.handshakeFailed("Failed to send HELLO: \(error)")
        }

        // Update reader/writer limits
        reader.setLimits(negotiatedLimits)
        writer.setLimits(negotiatedLimits)
    }

    // MARK: - Accessors

    /// Get the negotiated protocol limits
    public var negotiatedLimits: CborLimits {
        return limits
    }
}
