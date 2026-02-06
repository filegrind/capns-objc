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
public protocol CborStreamEmitter: Sendable {
    /// Emit raw bytes as a chunk immediately
    func emit(chunk: Data)

    /// Emit a JSON-encodable value as a chunk
    func emit<T: Encodable>(value: T) throws

    /// Emit a status/progress message
    func emitStatus(operation: String, details: String)

    /// Emit a log message at the given level
    func log(level: String, message: String)
}

// MARK: - PeerInvoker Protocol

/// Allows handlers to invoke caps on the peer (host).
///
/// This protocol enables bidirectional communication where a plugin handler can
/// invoke caps on the host while processing a request. This is essential for
/// sandboxed plugins that need to delegate certain operations (like model
/// downloading) to the host.
///
/// The `invoke` method sends a REQ frame to the host and returns an iterator
/// that yields response chunks as they arrive.
public protocol CborPeerInvoker: Sendable {
    /// Invoke a cap on the host with unified arguments.
    ///
    /// Sends a REQ frame to the host with the specified cap URN and arguments.
    /// Arguments are serialized as CBOR with native binary values.
    /// Returns an iterator that yields response chunks (Data) or errors.
    /// The iterator will be exhausted when the response is complete (END frame received).
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN to invoke on the host
    ///   - arguments: Arguments identified by media_urn
    /// - Returns: An iterator yielding Result<Data, CborPluginRuntimeError> for each chunk
    func invoke(capUrn: String, arguments: [CborCapArgumentValue]) throws -> AnyIterator<Result<Data, CborPluginRuntimeError>>
}

/// A no-op PeerInvoker that always returns an error.
/// Used when peer invocation is not supported (CLI mode).
public struct NoCborPeerInvoker: CborPeerInvoker {
    public init() {}

    public func invoke(capUrn: String, arguments: [CborCapArgumentValue]) throws -> AnyIterator<Result<Data, CborPluginRuntimeError>> {
        throw CborPluginRuntimeError.peerRequestError("Peer invocation not supported in CLI mode")
    }
}

// MARK: - CliStreamEmitter

/// CLI-mode emitter that writes directly to stdout.
/// Used when the plugin is invoked via CLI (with arguments).
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

    public func emit(chunk: Data) {
        stdoutHandle.write(chunk)
        if ndjson {
            stdoutHandle.write(Data("\n".utf8))
        }
    }

    public func emit<T: Encodable>(value: T) throws {
        let data = try JSONEncoder().encode(value)
        emit(chunk: data)
    }

    public func emitStatus(operation: String, details: String) {
        // In CLI mode, status goes to stderr
        let status = ["type": "status", "operation": operation, "details": details]
        if let json = try? JSONSerialization.data(withJSONObject: status) {
            FileHandle.standardError.write(json)
            FileHandle.standardError.write(Data("\n".utf8))
        }
    }

    public func log(level: String, message: String) {
        // In CLI mode, logs go to stderr
        let logLine = "[\(level.uppercased())] \(message)\n"
        FileHandle.standardError.write(Data(logLine.utf8))
    }
}

// MARK: - Payload Extraction

/// Extract the effective payload from a REQ frame.
///
/// If the content_type is "application/cbor", the payload is expected to be
/// CBOR unified arguments: `[{media_urn: string, value: bytes}, ...]`
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
    // Check if this is CBOR unified arguments
    guard contentType == "application/cbor" else {
        // Not CBOR unified arguments - return raw payload
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
        throw CborPluginRuntimeError.deserializationError("Failed to parse CBOR unified arguments: \(error)")
    }

    // Must be an array
    guard case .array(let arguments) = cborValue else {
        throw CborPluginRuntimeError.deserializationError("CBOR unified arguments must be an array")
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
                let matchesForward = (try? argUrn.matches(expectedUrn)) != nil
                let matchesReverse = (try? expectedUrn.matches(argUrn)) != nil
                if matchesForward || matchesReverse {
                    return val
                }
            }
        }
    }

    // No matching argument found - this is an error, no fallbacks
    throw CborPluginRuntimeError.deserializationError(
        "No argument found matching expected input media type '\(expectedInput)' in CBOR unified arguments"
    )
}


// MARK: - Handler Type

/// Handler function type - receives request payload, emitter, and peer invoker; returns response payload.
///
/// The `CborPeerInvoker` allows the handler to invoke caps on the host (peer) during
/// request processing. This enables bidirectional communication for operations
/// like model downloading that sandboxed plugins cannot perform directly.
public typealias CborCapHandler = @Sendable (Data, CborStreamEmitter, CborPeerInvoker) throws -> Data

// MARK: - Internal: Pending Peer Request

/// Internal struct to track pending peer requests (plugin invoking host caps).
private struct PendingPeerRequest {
    let condition: NSCondition
    var chunks: [Data]
    var error: CborPluginRuntimeError?
    var isComplete: Bool
}

// MARK: - Internal: ThreadSafeStreamEmitter

/// Thread-safe emitter implementation that writes CBOR frames.
@available(macOS 10.15.4, iOS 13.4, *)
final class ThreadSafeStreamEmitter: CborStreamEmitter, @unchecked Sendable {
    private let writer: CborFrameWriter
    private let writerLock: NSLock
    private let requestId: CborMessageId
    private var seq: UInt64 = 0
    private let seqLock = NSLock()

    init(writer: CborFrameWriter, writerLock: NSLock, requestId: CborMessageId) {
        self.writer = writer
        self.writerLock = writerLock
        self.requestId = requestId
    }

    func emit(chunk: Data) {
        seqLock.lock()
        let currentSeq = seq
        seq += 1
        seqLock.unlock()

        let frame = CborFrame.chunk(id: requestId, seq: currentSeq, payload: chunk)

        writerLock.lock()
        defer { writerLock.unlock() }
        do {
            try writer.write(frame)
        } catch {
            fputs("[CborPluginRuntime] Failed to write chunk: \(error)\n", stderr)
        }
    }

    func emit<T: Encodable>(value: T) throws {
        let data = try JSONEncoder().encode(value)
        emit(chunk: data)
    }

    func emitStatus(operation: String, details: String) {
        let status: [String: String] = [
            "type": "status",
            "operation": operation,
            "details": details
        ]
        do {
            try emit(value: status)
        } catch {
            fputs("[CborPluginRuntime] Failed to emit status: \(error)\n", stderr)
        }
    }

    func log(level: String, message: String) {
        let frame = CborFrame.log(id: requestId, level: level, message: message)

        writerLock.lock()
        defer { writerLock.unlock() }
        do {
            try writer.write(frame)
        } catch {
            fputs("[CborPluginRuntime] Failed to write log: \(error)\n", stderr)
        }
    }
}

// MARK: - Internal: PeerInvokerImpl

/// Implementation of PeerInvoker that sends REQ frames to the host.
@available(macOS 10.15.4, iOS 13.4, *)
final class PeerInvokerImpl: CborPeerInvoker, @unchecked Sendable {
    private let writer: CborFrameWriter
    private let writerLock: NSLock
    private let pendingRequests: NSMutableDictionary // [CborMessageId: PendingPeerRequest]
    private let pendingRequestsLock: NSLock

    init(writer: CborFrameWriter, writerLock: NSLock, pendingRequests: NSMutableDictionary, pendingRequestsLock: NSLock) {
        self.writer = writer
        self.writerLock = writerLock
        self.pendingRequests = pendingRequests
        self.pendingRequestsLock = pendingRequestsLock
    }

    func invoke(capUrn: String, arguments: [CborCapArgumentValue]) throws -> AnyIterator<Result<Data, CborPluginRuntimeError>> {
        // Generate a new message ID for this request
        let requestId = CborMessageId.newUUID()

        // Create pending request tracking
        let pending = PendingPeerRequest(
            condition: NSCondition(),
            chunks: [],
            error: nil,
            isComplete: false
        )

        // Register the pending request before sending
        pendingRequestsLock.lock()
        pendingRequests[requestId] = pending
        pendingRequestsLock.unlock()

        // Serialize arguments as CBOR: [{media_urn: string, value: bytes}, ...]
        var cborArray: [CBOR] = []
        for arg in arguments {
            let argMap: CBOR = .map([
                .utf8String("media_urn"): .utf8String(arg.mediaUrn),
                .utf8String("value"): .byteString([UInt8](arg.value))
            ])
            cborArray.append(argMap)
        }
        let payloadCbor = CBOR.array(cborArray)
        let payloadData = Data(payloadCbor.encode())

        // Create and send the REQ frame
        let frame = CborFrame.req(id: requestId, capUrn: capUrn, payload: payloadData, contentType: "application/cbor")

        writerLock.lock()
        do {
            try writer.write(frame)
        } catch {
            writerLock.unlock()
            // Remove pending request on failure
            pendingRequestsLock.lock()
            pendingRequests.removeObject(forKey: requestId)
            pendingRequestsLock.unlock()
            throw CborPluginRuntimeError.peerRequestError("Failed to send REQ frame: \(error)")
        }
        writerLock.unlock()

        // Return an iterator that yields chunks as they arrive
        var chunkIndex = 0
        return AnyIterator { [weak self] in
            guard let self = self else { return nil }

            self.pendingRequestsLock.lock()
            guard var request = self.pendingRequests[requestId] as? PendingPeerRequest else {
                self.pendingRequestsLock.unlock()
                return nil
            }

            // Wait for more data if needed
            while chunkIndex >= request.chunks.count && !request.isComplete && request.error == nil {
                self.pendingRequestsLock.unlock()
                request.condition.lock()
                request.condition.wait()
                request.condition.unlock()
                self.pendingRequestsLock.lock()
                guard let updated = self.pendingRequests[requestId] as? PendingPeerRequest else {
                    self.pendingRequestsLock.unlock()
                    return nil
                }
                request = updated
            }

            // Check for error
            if let error = request.error {
                self.pendingRequests.removeObject(forKey: requestId)
                self.pendingRequestsLock.unlock()
                return .failure(error)
            }

            // Check for more chunks
            if chunkIndex < request.chunks.count {
                let chunk = request.chunks[chunkIndex]
                chunkIndex += 1
                self.pendingRequestsLock.unlock()
                return .success(chunk)
            }

            // Complete - clean up
            if request.isComplete {
                self.pendingRequests.removeObject(forKey: requestId)
            }
            self.pendingRequestsLock.unlock()
            return nil
        }
    }
}

// MARK: - Manifest Types (for CLI mode)

/// Source for extracting argument values in CLI mode.
public enum CborArgSource: Codable, Sendable {
    case cliFlag(String)
    case positional(Int)
    case stdin

    enum CodingKeys: String, CodingKey {
        case type
        case cliFlag = "cli_flag"
        case position
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "cli_flag":
            let flag = try container.decode(String.self, forKey: .cliFlag)
            self = .cliFlag(flag)
        case "positional":
            let pos = try container.decode(Int.self, forKey: .position)
            self = .positional(pos)
        case "stdin":
            self = .stdin
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown source type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cliFlag(let flag):
            try container.encode("cli_flag", forKey: .type)
            try container.encode(flag, forKey: .cliFlag)
        case .positional(let pos):
            try container.encode("positional", forKey: .type)
            try container.encode(pos, forKey: .position)
        case .stdin:
            try container.encode("stdin", forKey: .type)
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
                if case .stdin = source {
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

    /// Register a handler for a cap URN.
    ///
    /// The handler receives:
    /// - Request payload bytes
    /// - Emitter for streaming output
    /// - Peer invoker for calling host caps
    ///
    /// It returns the final response payload.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN pattern to handle
    ///   - handler: Handler closure that processes requests
    public func register(capUrn: String, handler: @escaping CborCapHandler) {
        handlersLock.lock()
        handlers[capUrn] = handler
        handlersLock.unlock()
    }

    /// Register a handler with typed request/response
    public func register<Req: Decodable & Sendable, Res: Encodable & Sendable>(
        capUrn: String,
        handler: @escaping @Sendable (Req, CborStreamEmitter, CborPeerInvoker) throws -> Res
    ) {
        register(capUrn: capUrn) { payload, emitter, peer in
            let request = try JSONDecoder().decode(Req.self, from: payload)
            let response = try handler(request, emitter, peer)
            return try JSONEncoder().encode(response)
        }
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
        try runCliMode(args)
    }

    // MARK: - CLI Mode

    /// Run in CLI mode - parse arguments and invoke handler.
    private func runCliMode(_ args: [String]) throws {
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

        // Create CLI-mode emitter and no-op peer invoker
        let emitter = CliStreamEmitter()
        let peer = NoCborPeerInvoker()

        // Invoke handler
        let result = try handler(payload, emitter, peer)

        // Output final response if not empty
        if !result.isEmpty {
            FileHandle.standardOutput.write(result)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    /// Find a cap by its command name (the CLI subcommand).
    private func findCapByCommand(manifest: CborManifest, commandName: String) -> CborCapDefinition? {
        return manifest.caps.first { $0.command == commandName }
    }

    /// Build payload from CLI arguments based on cap's arg definitions.
    private func buildPayloadFromCli(cap: CborCapDefinition, cliArgs: [String]) throws -> Data {
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
                arguments.append(CborCapArgumentValue(mediaUrn: argDef.mediaUrn, value: v))
            } else if argDef.required {
                // Required argument not found
                let sources = argDef.sources.map { source -> String in
                    switch source {
                    case .cliFlag(let flag): return flag
                    case .positional(let pos): return "<pos \(pos)>"
                    case .stdin: return "<stdin>"
                    }
                }.joined(separator: " or ")
                throw CborPluginRuntimeError.missingArgument("Required argument '\(argDef.mediaUrn)' not provided. Use: \(sources)")
            }
        }

        // Serialize arguments to JSON payload
        if !arguments.isEmpty {
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
            // No arguments, no stdin - return empty object
            return Data("{}".utf8)
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
        // Try each source in order
        for source in argDef.sources {
            switch source {
            case .cliFlag(let flag):
                if let value = getCliFlagValue(args: cliArgs, flag: flag) {
                    return Data(value.utf8)
                }
            case .positional(let position):
                let positional = getPositionalArgs(args: cliArgs)
                if position < positional.count {
                    return Data(positional[position].utf8)
                }
            case .stdin:
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
                    case .stdin:
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
        let pendingPeerRequests = NSMutableDictionary()
        let pendingPeerRequestsLock = NSLock()

        // Track active handler threads
        var activeHandlers: [Thread] = []
        let activeHandlersLock = NSLock()

        // Main loop - stays responsive for heartbeats
        while true {
            // Clean up finished handlers
            activeHandlersLock.lock()
            activeHandlers.removeAll { !$0.isExecuting }
            activeHandlersLock.unlock()

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

                guard let handler = findHandler(capUrn: capUrn) else {
                    let errFrame = CborFrame.err(id: frame.id, code: "NO_HANDLER", message: "No handler for cap: \(capUrn)")
                    writerLock.lock()
                    try? frameWriter.write(errFrame)
                    writerLock.unlock()
                    continue
                }

                // Clone values for handler thread
                let requestId = frame.id
                let payload = frame.payload ?? Data()

                let handlerThread = Thread { [writerLock, pendingPeerRequests, pendingPeerRequestsLock] in
                    let emitter = ThreadSafeStreamEmitter(writer: frameWriter, writerLock: writerLock, requestId: requestId)
                    let peer = PeerInvokerImpl(
                        writer: frameWriter,
                        writerLock: writerLock,
                        pendingRequests: pendingPeerRequests,
                        pendingRequestsLock: pendingPeerRequestsLock
                    )

                    do {
                        let result = try handler(payload, emitter, peer)
                        let endFrame = CborFrame.end(id: requestId, finalPayload: result)
                        writerLock.lock()
                        try frameWriter.write(endFrame)
                        writerLock.unlock()
                    } catch {
                        let errFrame = CborFrame.err(id: requestId, code: "HANDLER_ERROR", message: "\(error)")
                        writerLock.lock()
                        try? frameWriter.write(errFrame)
                        writerLock.unlock()
                    }
                }

                activeHandlersLock.lock()
                activeHandlers.append(handlerThread)
                activeHandlersLock.unlock()

                handlerThread.start()

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

            case .res, .chunk, .end:
                // Response frames from host - route to pending peer request by frame.id
                pendingPeerRequestsLock.lock()
                if var pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    let payload = frame.payload ?? Data()
                    pending.chunks.append(payload)

                    // Mark complete on RES or END frame
                    if frame.frameType == .res || frame.frameType == .end {
                        pending.isComplete = true
                    }

                    pendingPeerRequests[frame.id] = pending
                    pending.condition.lock()
                    pending.condition.signal()
                    pending.condition.unlock()
                }
                pendingPeerRequestsLock.unlock()

            case .err:
                // Error frame from host - route to pending peer request
                pendingPeerRequestsLock.lock()
                if var pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    let code = frame.errorCode ?? "UNKNOWN"
                    let message = frame.errorMessage ?? "Unknown error"
                    pending.error = CborPluginRuntimeError.peerResponseError("[\(code)] \(message)")
                    pending.isComplete = true
                    pendingPeerRequests[frame.id] = pending
                    pending.condition.lock()
                    pending.condition.signal()
                    pending.condition.unlock()
                }
                pendingPeerRequestsLock.unlock()

            case .log:
                // Log frames from host - shouldn't normally receive these, ignore
                continue
            }
        }

        // Wait for active handlers to complete
        activeHandlersLock.lock()
        let handlersToWait = activeHandlers
        activeHandlersLock.unlock()

        for handler in handlersToWait {
            while handler.isExecuting {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
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
