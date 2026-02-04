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
//
//  Usage:
//  ```swift
//  let runtime = CborPluginRuntime()
//  runtime.register(capUrn: "cap:op=my_op") { payload, emitter in
//      emitter.emitStatus(operation: "processing", details: "Working...")
//      emitter.emit(chunk: someData)
//      return finalResult
//  }
//  try runtime.run()  // Blocks until stdin closes
//  ```

import Foundation
@preconcurrency import SwiftCBOR

/// Errors specific to PluginRuntime operations
public enum CborPluginRuntimeError: Error, LocalizedError, @unchecked Sendable {
    case handshakeFailed(String)
    case noHandler(String)
    case handlerError(String)
    case deserializationError(String)
    case serializationError(String)
    case ioError(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .noHandler(let cap): return "No handler registered for cap: \(cap)"
        case .handlerError(let msg): return "Handler error: \(msg)"
        case .deserializationError(let msg): return "Deserialization error: \(msg)"
        case .serializationError(let msg): return "Serialization error: \(msg)"
        case .ioError(let msg): return "I/O error: \(msg)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        }
    }
}

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

/// Handler function type - receives request payload, returns response payload
public typealias CborCapHandler = @Sendable (Data, CborStreamEmitter) throws -> Data

/// Thread-safe emitter implementation
@available(macOS 10.15.4, iOS 13.4, *)
final class ThreadSafeStreamEmitter: CborStreamEmitter, @unchecked Sendable {
    private let writer: CborFrameWriter
    private let requestId: CborMessageId
    private var seq: UInt64 = 0
    private let lock = NSLock()

    init(writer: CborFrameWriter, requestId: CborMessageId) {
        self.writer = writer
        self.requestId = requestId
    }

    func emit(chunk: Data) {
        lock.lock()
        let currentSeq = seq
        seq += 1
        lock.unlock()

        let frame = CborFrame.chunk(id: requestId, seq: currentSeq, payload: chunk)

        lock.lock()
        defer { lock.unlock() }
        do {
            try writer.write(frame)
        } catch {
            // Log error but don't throw - emitter is fire-and-forget
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

        lock.lock()
        defer { lock.unlock() }
        do {
            try writer.write(frame)
        } catch {
            fputs("[CborPluginRuntime] Failed to write log: \(error)\n", stderr)
        }
    }
}

/// Plugin-side runtime for CBOR protocol communication.
///
/// Plugins create a runtime, register handlers for their caps, then call `run()`.
/// The runtime handles all I/O mechanics:
/// - HELLO handshake for limit negotiation
/// - Frame encoding/decoding
/// - Request routing to handlers
/// - Streaming response support
/// - HEARTBEAT health monitoring
///
/// **Multiplexed execution**: Multiple requests can be processed concurrently.
/// Each request handler runs in its own thread, allowing the runtime to:
/// - Respond to heartbeats while handlers are running
/// - Accept new requests while previous ones are still processing
///
/// **This is the ONLY supported way for plugins to communicate with the host.**
@available(macOS 10.15.4, iOS 13.4, *)
public final class CborPluginRuntime: @unchecked Sendable {

    // MARK: - Properties

    private var handlers: [String: CborCapHandler] = [:]
    private let handlersLock = NSLock()

    private var limits = CborLimits()

    // MARK: - Initialization

    public init() {}

    // MARK: - Handler Registration

    /// Register a handler for a cap URN.
    ///
    /// The handler receives the request payload and an emitter for streaming output.
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
    public func register<Req: Decodable, Res: Encodable>(
        capUrn: String,
        handler: @escaping @Sendable (Req, CborStreamEmitter) throws -> Res
    ) {
        register(capUrn: capUrn) { payload, emitter in
            let request = try JSONDecoder().decode(Req.self, from: payload)
            let response = try handler(request, emitter)
            return try JSONEncoder().encode(response)
        }
    }

    /// Find a handler for a cap URN (supports exact match and pattern matching)
    private func findHandler(capUrn: String) -> CborCapHandler? {
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

    /// Run the plugin runtime, processing requests until stdin closes.
    ///
    /// Protocol lifecycle:
    /// 1. Receive HELLO from host
    /// 2. Send HELLO back (handshake)
    /// 3. Main loop reads frames:
    ///    - REQ frames: spawn handler thread, continue reading
    ///    - HEARTBEAT frames: respond immediately
    ///    - Other frames: ignore
    /// 4. Exit when stdin closes, wait for active handlers
    ///
    /// **Multiplexing**: The main loop never blocks on handler execution.
    ///
    /// - Throws: CborPluginRuntimeError on fatal errors
    public func run() throws {
        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput

        let frameReader = CborFrameReader(handle: stdinHandle, limits: limits)
        let frameWriter = CborFrameWriter(handle: stdoutHandle, limits: limits)

        // Perform handshake
        try performHandshake(reader: frameReader, writer: frameWriter)

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
                    try? frameWriter.write(errFrame)
                    continue
                }

                guard let handler = findHandler(capUrn: capUrn) else {
                    let errFrame = CborFrame.err(id: frame.id, code: "NO_HANDLER", message: "No handler for cap: \(capUrn)")
                    try? frameWriter.write(errFrame)
                    continue
                }

                // Spawn handler in separate thread
                let requestId = frame.id
                let payload = frame.payload ?? Data()

                let handlerThread = Thread {
                    let emitter = ThreadSafeStreamEmitter(writer: frameWriter, requestId: requestId)

                    do {
                        let result = try handler(payload, emitter)
                        let endFrame = CborFrame.end(id: requestId, finalPayload: result)
                        try frameWriter.write(endFrame)
                    } catch {
                        let errFrame = CborFrame.err(id: requestId, code: "HANDLER_ERROR", message: "\(error)")
                        try? frameWriter.write(errFrame)
                    }
                }

                activeHandlersLock.lock()
                activeHandlers.append(handlerThread)
                activeHandlersLock.unlock()

                handlerThread.start()

            case .heartbeat:
                // Respond immediately - never blocked by handlers
                let response = CborFrame.heartbeat(id: frame.id)
                try frameWriter.write(response)

            case .hello:
                // Unexpected HELLO after handshake
                let errFrame = CborFrame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "Unexpected HELLO after handshake")
                try frameWriter.write(errFrame)

            case .res, .chunk, .end:
                // Responses to plugin-initiated requests (cap invocation)
                // Would be routed to waiting handlers in full implementation
                continue

            case .log, .err:
                // Shouldn't receive these from host
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

        // Send our HELLO with negotiated limits
        let ourHello = CborFrame.hello(maxFrame: negotiatedLimits.maxFrame, maxChunk: negotiatedLimits.maxChunk)
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
