//
//  CborPluginHost.swift
//  CapNsCbor
//
//  Host-side runtime for communicating with CBOR-based plugins.
//
//  This is the ONLY supported way to communicate with plugins.
//  The host (e.g., XPC service) uses this runtime to:
//  1. Spawn and manage plugin processes
//  2. Perform HELLO handshake
//  3. Send REQ frames and receive responses
//  4. Handle HEARTBEAT for health monitoring
//  5. Process streaming CHUNK responses
//
//  Usage:
//  ```swift
//  let host = try CborPluginHost(
//      stdinHandle: pluginStdin,
//      stdoutHandle: pluginStdout,
//      onChunk: { requestId, payload in ... },
//      onLog: { requestId, level, message in ... }
//  )
//  try host.performHandshake()
//  let requestId = try host.sendRequest(capUrn: "cap:op=test", payload: requestData)
//  // Responses arrive via callbacks
//  ```

import Foundation
@preconcurrency import SwiftCBOR

/// Errors specific to PluginHost operations
public enum CborPluginHostError: Error, LocalizedError, @unchecked Sendable {
    case notConnected
    case handshakeNotComplete
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case pluginError(code: String, message: String)
    case unexpectedFrameType(CborFrameType)
    case protocolError(String)
    case timeout
    case processExited(code: Int32?)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Plugin not connected"
        case .handshakeNotComplete: return "Handshake not complete"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        case .receiveFailed(let msg): return "Receive failed: \(msg)"
        case .pluginError(let code, let message): return "Plugin error [\(code)]: \(message)"
        case .unexpectedFrameType(let t): return "Unexpected frame type: \(t)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .timeout: return "Operation timed out"
        case .processExited(let code): return "Plugin process exited with code: \(code?.description ?? "unknown")"
        }
    }
}

/// Response from a plugin request
public enum CborPluginResponse: Sendable {
    /// Single complete response
    case single(Data)
    /// Stream ended with optional final payload
    case streamEnd(Data?)
    /// Error response from plugin
    case error(code: String, message: String)
}

/// Delegate protocol for receiving plugin events
@available(macOS 10.15.4, iOS 13.4, *)
public protocol CborPluginHostDelegate: AnyObject, Sendable {
    /// Called when a CHUNK frame is received for a request
    func pluginHost(_ host: CborPluginHost, didReceiveChunk payload: Data, forRequest requestId: CborMessageId, seq: UInt64)

    /// Called when a LOG frame is received
    func pluginHost(_ host: CborPluginHost, didReceiveLog level: String, message: String, forRequest requestId: CborMessageId)

    /// Called when a request completes (RES or END frame)
    func pluginHost(_ host: CborPluginHost, didCompleteRequest requestId: CborMessageId, response: CborPluginResponse)

    /// Called when the plugin sends a REQ (cap invocation from plugin)
    func pluginHost(_ host: CborPluginHost, didReceiveCapRequest requestId: CborMessageId, capUrn: String, payload: Data)
}

/// Host-side runtime for CBOR plugin communication.
///
/// This class manages the complete communication lifecycle with a plugin process:
/// - Performs HELLO handshake to negotiate limits
/// - Sends REQ frames for cap invocations
/// - Processes responses (RES, CHUNK, END, ERR frames)
/// - Handles HEARTBEAT for health monitoring
/// - Supports multiplexed concurrent requests
///
/// **This is the ONLY supported way for the host to communicate with plugins.**
/// There are no fallbacks, no alternative protocols. CBOR over stdin/stdout pipes.
@available(macOS 10.15.4, iOS 13.4, *)
public final class CborPluginHost: @unchecked Sendable {

    // MARK: - Properties

    private let stdinHandle: FileHandle   // Write to plugin's stdin
    private let stdoutHandle: FileHandle  // Read from plugin's stdout

    private var frameReader: CborFrameReader
    private var frameWriter: CborFrameWriter
    private var chunkAssembler: CborChunkAssembler

    private var limits: CborLimits
    private var handshakeComplete = false

    private let lock = NSLock()

    /// Delegate for receiving async events
    public weak var delegate: CborPluginHostDelegate?

    /// Active request tracking for multiplexing
    private var activeRequests: Set<CborMessageId> = []

    // MARK: - Initialization

    /// Create a new plugin host with the given I/O handles.
    ///
    /// - Parameters:
    ///   - stdinHandle: FileHandle to write to the plugin's stdin
    ///   - stdoutHandle: FileHandle to read from the plugin's stdout
    public init(stdinHandle: FileHandle, stdoutHandle: FileHandle) {
        self.stdinHandle = stdinHandle
        self.stdoutHandle = stdoutHandle
        self.limits = CborLimits()
        self.frameReader = CborFrameReader(handle: stdoutHandle, limits: limits)
        self.frameWriter = CborFrameWriter(handle: stdinHandle, limits: limits)
        self.chunkAssembler = CborChunkAssembler(limits: limits)
    }

    // MARK: - Handshake

    /// Perform HELLO handshake with the plugin.
    ///
    /// This MUST be called before any other communication.
    /// Sends our HELLO, receives plugin's HELLO, negotiates limits.
    ///
    /// - Throws: CborPluginHostError if handshake fails
    public func performHandshake() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !handshakeComplete else { return }

        // Send our HELLO
        let ourHello = CborFrame.hello(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK)
        do {
            try frameWriter.write(ourHello)
        } catch {
            throw CborPluginHostError.handshakeFailed("Failed to send HELLO: \(error)")
        }

        // Read plugin's HELLO
        let theirFrame: CborFrame
        do {
            guard let frame = try frameReader.read() else {
                throw CborPluginHostError.handshakeFailed("Plugin closed connection before HELLO")
            }
            theirFrame = frame
        } catch {
            throw CborPluginHostError.handshakeFailed("Failed to receive HELLO: \(error)")
        }

        guard theirFrame.frameType == .hello else {
            throw CborPluginHostError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
        }

        // Negotiate limits (use minimum of both)
        let theirMaxFrame = theirFrame.helloMaxFrame ?? DEFAULT_MAX_FRAME
        let theirMaxChunk = theirFrame.helloMaxChunk ?? DEFAULT_MAX_CHUNK

        let negotiatedLimits = CborLimits(
            maxFrame: min(DEFAULT_MAX_FRAME, theirMaxFrame),
            maxChunk: min(DEFAULT_MAX_CHUNK, theirMaxChunk)
        )

        self.limits = negotiatedLimits
        self.frameReader.setLimits(negotiatedLimits)
        self.frameWriter.setLimits(negotiatedLimits)
        self.chunkAssembler = CborChunkAssembler(limits: negotiatedLimits)
        self.handshakeComplete = true
    }

    /// Check if handshake has been completed
    public var isHandshakeComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handshakeComplete
    }

    /// Get the negotiated limits
    public var negotiatedLimits: CborLimits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    // MARK: - Sending Requests

    /// Send a request to invoke a cap on the plugin.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN to invoke
    ///   - payload: Request payload (typically JSON)
    ///   - contentType: Content type of payload (default: "application/json")
    /// - Returns: The message ID for this request (use to correlate responses)
    /// - Throws: CborPluginHostError if send fails
    @discardableResult
    public func sendRequest(capUrn: String, payload: Data, contentType: String = "application/json") throws -> CborMessageId {
        lock.lock()
        defer { lock.unlock() }

        guard handshakeComplete else {
            throw CborPluginHostError.handshakeNotComplete
        }

        let requestId = CborMessageId.newUUID()
        let frame = CborFrame.req(id: requestId, capUrn: capUrn, payload: payload, contentType: contentType)

        do {
            try frameWriter.write(frame)
            activeRequests.insert(requestId)
        } catch {
            throw CborPluginHostError.sendFailed("\(error)")
        }

        return requestId
    }

    /// Send a heartbeat to the plugin.
    ///
    /// - Returns: The message ID for this heartbeat
    /// - Throws: CborPluginHostError if send fails
    @discardableResult
    public func sendHeartbeat() throws -> CborMessageId {
        lock.lock()
        defer { lock.unlock() }

        guard handshakeComplete else {
            throw CborPluginHostError.handshakeNotComplete
        }

        let heartbeatId = CborMessageId.newUUID()
        let frame = CborFrame.heartbeat(id: heartbeatId)

        do {
            try frameWriter.write(frame)
        } catch {
            throw CborPluginHostError.sendFailed("\(error)")
        }

        return heartbeatId
    }

    /// Respond to a cap invocation from the plugin.
    ///
    /// When a plugin sends a REQ to the host (for cap invocation),
    /// use this to send the response back.
    ///
    /// - Parameters:
    ///   - requestId: The request ID from the plugin's REQ
    ///   - payload: Response payload
    ///   - contentType: Content type of payload
    public func respondToPluginRequest(requestId: CborMessageId, payload: Data, contentType: String = "application/json") throws {
        lock.lock()
        defer { lock.unlock() }

        guard handshakeComplete else {
            throw CborPluginHostError.handshakeNotComplete
        }

        let frame = CborFrame.res(id: requestId, payload: payload, contentType: contentType)

        do {
            try frameWriter.write(frame)
        } catch {
            throw CborPluginHostError.sendFailed("\(error)")
        }
    }

    /// Send an error response to a plugin's cap invocation request.
    public func respondToPluginRequestWithError(requestId: CborMessageId, code: String, message: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard handshakeComplete else {
            throw CborPluginHostError.handshakeNotComplete
        }

        let frame = CborFrame.err(id: requestId, code: code, message: message)

        do {
            try frameWriter.write(frame)
        } catch {
            throw CborPluginHostError.sendFailed("\(error)")
        }
    }

    // MARK: - Receiving Responses

    /// Read and process the next frame from the plugin.
    ///
    /// This is the main receive loop method. Call this repeatedly to process
    /// incoming frames. Frames are dispatched to the delegate.
    ///
    /// - Returns: true if a frame was processed, false if no frame available
    /// - Throws: CborPluginHostError on protocol errors
    public func processNextFrame() throws -> Bool {
        lock.lock()
        guard handshakeComplete else {
            lock.unlock()
            throw CborPluginHostError.handshakeNotComplete
        }
        lock.unlock()

        // Read outside the lock to avoid blocking other operations
        let frame: CborFrame
        do {
            guard let f = try frameReader.read() else {
                return false
            }
            frame = f
        } catch {
            throw CborPluginHostError.receiveFailed("\(error)")
        }

        // Process the frame
        try processFrame(frame)
        return true
    }

    /// Process a single frame and dispatch to delegate
    private func processFrame(_ frame: CborFrame) throws {
        switch frame.frameType {
        case .chunk:
            // Streaming chunk - may need assembly for large payloads
            if let totalLen = frame.len, Int(totalLen) > limits.maxChunk {
                // Multi-chunk stream - use assembler
                if let assembled = try chunkAssembler.processChunk(frame) {
                    delegate?.pluginHost(self, didCompleteRequest: frame.id, response: .single(assembled))
                    lock.lock()
                    activeRequests.remove(frame.id)
                    lock.unlock()
                }
                // Not complete yet, will get more chunks
            } else {
                // Single chunk - deliver directly
                let payload = frame.payload ?? Data()
                delegate?.pluginHost(self, didReceiveChunk: payload, forRequest: frame.id, seq: frame.seq)

                if frame.isEof {
                    delegate?.pluginHost(self, didCompleteRequest: frame.id, response: .streamEnd(payload))
                    lock.lock()
                    activeRequests.remove(frame.id)
                    lock.unlock()
                }
            }

        case .res:
            // Single complete response
            let payload = frame.payload ?? Data()
            delegate?.pluginHost(self, didCompleteRequest: frame.id, response: .single(payload))
            lock.lock()
            activeRequests.remove(frame.id)
            lock.unlock()

        case .end:
            // Stream complete
            delegate?.pluginHost(self, didCompleteRequest: frame.id, response: .streamEnd(frame.payload))
            lock.lock()
            activeRequests.remove(frame.id)
            lock.unlock()

        case .log:
            // Log message from plugin
            let level = frame.logLevel ?? "info"
            let message = frame.logMessage ?? ""
            delegate?.pluginHost(self, didReceiveLog: level, message: message, forRequest: frame.id)

        case .err:
            // Error response from plugin
            let code = frame.errorCode ?? "UNKNOWN"
            let message = frame.errorMessage ?? "Unknown error"
            delegate?.pluginHost(self, didCompleteRequest: frame.id, response: .error(code: code, message: message))
            lock.lock()
            activeRequests.remove(frame.id)
            lock.unlock()

        case .heartbeat:
            // Plugin sent us a heartbeat - respond immediately
            lock.lock()
            do {
                let response = CborFrame.heartbeat(id: frame.id)
                try frameWriter.write(response)
            } catch {
                lock.unlock()
                throw CborPluginHostError.sendFailed("Failed to respond to heartbeat: \(error)")
            }
            lock.unlock()

        case .req:
            // Plugin is requesting a cap from us (cap invocation)
            let capUrn = frame.cap ?? ""
            let payload = frame.payload ?? Data()
            delegate?.pluginHost(self, didReceiveCapRequest: frame.id, capUrn: capUrn, payload: payload)

        case .hello:
            // Unexpected HELLO after handshake
            throw CborPluginHostError.protocolError("Unexpected HELLO after handshake")
        }
    }

    // MARK: - Synchronous Request (Blocking)

    /// Send a request and wait for the complete response.
    ///
    /// This is a blocking call that waits for the response.
    /// For streaming responses, all chunks are collected.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN to invoke
    ///   - payload: Request payload
    ///   - timeoutSeconds: Maximum time to wait (0 = no timeout)
    /// - Returns: The response data
    /// - Throws: CborPluginHostError on failure
    public func call(capUrn: String, payload: Data, timeoutSeconds: TimeInterval = 0) throws -> Data {
        let requestId = try sendRequest(capUrn: capUrn, payload: payload)

        let startTime = Date()
        var chunks: [Data] = []

        while true {
            // Check timeout
            if timeoutSeconds > 0 && Date().timeIntervalSince(startTime) > timeoutSeconds {
                throw CborPluginHostError.timeout
            }

            // Read next frame
            let frame: CborFrame
            do {
                guard let f = try frameReader.read() else {
                    throw CborPluginHostError.processExited(code: nil)
                }
                frame = f
            } catch let error as CborError {
                throw CborPluginHostError.receiveFailed("\(error)")
            }

            // Only process frames for our request
            guard frame.id == requestId else {
                // Could be heartbeat or other concurrent request
                if frame.frameType == .heartbeat {
                    // Respond to heartbeat
                    lock.lock()
                    do {
                        let response = CborFrame.heartbeat(id: frame.id)
                        try frameWriter.write(response)
                    } catch {
                        lock.unlock()
                        throw CborPluginHostError.sendFailed("Failed to respond to heartbeat: \(error)")
                    }
                    lock.unlock()
                }
                continue
            }

            switch frame.frameType {
            case .chunk:
                let payload = frame.payload ?? Data()
                chunks.append(payload)
                if frame.isEof {
                    return combineChunks(chunks)
                }

            case .res:
                return frame.payload ?? Data()

            case .end:
                if let finalPayload = frame.payload {
                    chunks.append(finalPayload)
                }
                return combineChunks(chunks)

            case .log:
                // Log messages during sync call - just continue
                continue

            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let message = frame.errorMessage ?? "Unknown error"
                throw CborPluginHostError.pluginError(code: code, message: message)

            default:
                throw CborPluginHostError.unexpectedFrameType(frame.frameType)
            }
        }
    }

    private func combineChunks(_ chunks: [Data]) -> Data {
        var result = Data()
        for chunk in chunks {
            result.append(chunk)
        }
        return result
    }

    // MARK: - Low-Level Frame Access

    /// Read the next frame without processing.
    ///
    /// This is for callers who want to handle frame dispatch themselves
    /// (e.g., XPC service that needs to convert frames to its own response format).
    ///
    /// - Returns: The next frame, or nil if no data available
    /// - Throws: CborError on read failure
    public func readNextFrame() throws -> CborFrame? {
        lock.lock()
        guard handshakeComplete else {
            lock.unlock()
            throw CborPluginHostError.handshakeNotComplete
        }
        lock.unlock()

        // Read outside the lock to avoid blocking
        return try frameReader.read()
    }

    /// Respond to a heartbeat frame from the plugin.
    ///
    /// Call this when you receive a heartbeat frame via `readNextFrame()`.
    ///
    /// - Parameter id: The message ID from the heartbeat frame
    /// - Throws: CborPluginHostError on send failure
    public func respondToHeartbeat(_ id: CborMessageId) throws {
        lock.lock()
        defer { lock.unlock() }

        guard handshakeComplete else {
            throw CborPluginHostError.handshakeNotComplete
        }

        let response = CborFrame.heartbeat(id: id)
        do {
            try frameWriter.write(response)
        } catch {
            throw CborPluginHostError.sendFailed("Failed to respond to heartbeat: \(error)")
        }
    }

    // MARK: - Cleanup

    /// Check if there are any active requests
    public var hasActiveRequests: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !activeRequests.isEmpty
    }

    /// Get count of active requests
    public var activeRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeRequests.count
    }

    /// Cancel tracking for a request (does not notify plugin)
    public func cancelRequest(_ requestId: CborMessageId) {
        lock.lock()
        activeRequests.remove(requestId)
        chunkAssembler.cancelStream(id: requestId)
        lock.unlock()
    }

    /// Clean up all state
    public func cleanup() {
        lock.lock()
        activeRequests.removeAll()
        chunkAssembler.cleanup()
        lock.unlock()
    }

    /// Close the plugin host, closing the stdin handle.
    ///
    /// This signals EOF to the plugin, which should trigger graceful shutdown.
    /// Does not close stdout - caller may want to drain remaining output.
    public func close() {
        lock.lock()
        defer { lock.unlock() }

        // Close stdin to signal EOF to plugin
        try? stdinHandle.close()

        // Clean up state
        activeRequests.removeAll()
        chunkAssembler.cleanup()
    }
}

// MARK: - Convenience Extensions

@available(macOS 10.15.4, iOS 13.4, *)
public extension CborPluginHost {
    /// Send a JSON-encodable request
    func sendRequest<T: Encodable>(capUrn: String, request: T) throws -> CborMessageId {
        let data = try JSONEncoder().encode(request)
        return try sendRequest(capUrn: capUrn, payload: data)
    }

    /// Call with JSON-encodable request and JSON-decodable response
    func call<Req: Encodable, Res: Decodable>(capUrn: String, request: Req, timeoutSeconds: TimeInterval = 0) throws -> Res {
        let requestData = try JSONEncoder().encode(request)
        let responseData = try call(capUrn: capUrn, payload: requestData, timeoutSeconds: timeoutSeconds)
        return try JSONDecoder().decode(Res.self, from: responseData)
    }
}
