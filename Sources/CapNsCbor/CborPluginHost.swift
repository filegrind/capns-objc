//
//  CborPluginHost.swift
//  CapNsCbor
//
//  Host-side runtime for communicating with plugin processes.
//
//  The CborPluginHost is the host-side runtime that manages all communication with
//  a running plugin process. It handles:
//
//  - HELLO handshake and limit negotiation
//  - Sending cap requests
//  - Receiving and routing responses
//  - Heartbeat handling (transparent)
//  - Multiplexed concurrent requests (transparent)
//
//  **This is the ONLY way for the host to communicate with plugins.**
//  No fallbacks, no alternative protocols.
//
//  Usage:
//
//  The host creates a CborPluginHost, then calls `request()` to invoke caps.
//  Responses arrive via an AsyncStream - the caller just iterates over chunks.
//  Multiple requests can be in flight simultaneously; the runtime handles
//  all correlation and routing.
//
//  ```swift
//  let host = try CborPluginHost(
//      stdinHandle: pluginStdin,
//      stdoutHandle: pluginStdout
//  )
//
//  // Send request - returns AsyncStream for responses
//  let stream = try host.request(capUrn: "cap:op=test", payload: requestData)
//
//  // Iterate over response chunks
//  for await result in stream {
//      switch result {
//      case .success(let chunk):
//          print("Got chunk: \(chunk.payload.count) bytes")
//      case .failure(let error):
//          print("Error: \(error)")
//      }
//  }
//  ```

import Foundation
@preconcurrency import SwiftCBOR

/// Errors that can occur in the plugin host
public enum CborPluginHostError: Error, LocalizedError, Sendable {
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case pluginError(code: String, message: String)
    case unexpectedFrameType(CborFrameType)
    case processExited
    case closed

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        case .receiveFailed(let msg): return "Receive failed: \(msg)"
        case .pluginError(let code, let message): return "Plugin error [\(code)]: \(message)"
        case .unexpectedFrameType(let t): return "Unexpected frame type: \(t)"
        case .processExited: return "Plugin process exited unexpectedly"
        case .closed: return "Host is closed"
        }
    }
}

/// A response chunk from a plugin
public struct CborResponseChunk: Sendable {
    /// The chunk payload data
    public let payload: Data
    /// Sequence number within the stream
    public let seq: UInt64
    /// Byte offset (for binary transfers)
    public let offset: UInt64?
    /// Total length (set on first chunk for binary transfers)
    public let len: UInt64?
    /// Whether this is the final chunk
    public let isEof: Bool
}

/// Response from a plugin request (for convenience call() method)
public enum CborPluginResponse: Sendable {
    /// Single complete response
    case single(Data)
    /// Streaming response with collected chunks
    case streaming([CborResponseChunk])

    /// Get final payload (last chunk's payload for streaming)
    public var finalPayload: Data? {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks): return chunks.last?.payload
        }
    }

    /// Concatenate all payloads
    public func concatenated() -> Data {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks):
            var result = Data()
            for chunk in chunks {
                result.append(chunk.payload)
            }
            return result
        }
    }
}

/// Internal state for pending requests
private struct PendingRequest: @unchecked Sendable {
    let continuation: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation
}


/// Host-side runtime for communicating with a plugin process.
///
/// **This is the ONLY way for the host to communicate with plugins.**
///
/// The runtime handles:
/// - Multiplexed concurrent requests (transparent)
/// - Heartbeat handling (transparent)
/// - Request/response correlation (transparent)
///
/// Callers simply send requests and receive responses via AsyncStreams.
@available(macOS 10.15.4, iOS 13.4, *)
public final class CborPluginHost: @unchecked Sendable {

    // MARK: - Properties

    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle

    private var frameWriter: CborFrameWriter
    private let writerLock = NSLock()

    private var limits: CborLimits
    private var closed = false

    /// Plugin manifest extracted from HELLO response.
    /// This is JSON-encoded plugin metadata including name, version, and caps.
    /// Will be nil only if the plugin doesn't send a manifest (protocol violation).
    private var _pluginManifest: Data?

    /// Pending requests waiting for responses
    private var pending: [CborMessageId: PendingRequest] = [:]
    private let pendingLock = NSLock()

    /// Pending heartbeat IDs we've sent (to avoid responding to our own heartbeat responses)
    private var pendingHeartbeats: Set<CborMessageId> = []
    private let heartbeatLock = NSLock()

    /// Background reader thread
    private var readerThread: Thread?

    /// Pending plugin cap requests awaiting responses, keyed by request ID (CborMessageId).
    /// When a cap_response message arrives via handleCapResponse, it's routed to the correct request.
    private var pendingPluginCapRequests: [CborMessageId: AsyncStream<Result<Data, Error>>.Continuation] = [:]
    private let pendingPluginCapRequestsLock = NSLock()

    // MARK: - Initialization

    /// Create a new plugin host and perform handshake.
    ///
    /// This sends a HELLO frame, waits for the plugin's HELLO,
    /// negotiates protocol limits, then starts the background reader.
    ///
    /// - Parameters:
    ///   - stdinHandle: FileHandle to write to the plugin's stdin
    ///   - stdoutHandle: FileHandle to read from the plugin's stdout
    /// - Throws: CborPluginHostError if handshake fails
    public init(stdinHandle: FileHandle, stdoutHandle: FileHandle) throws {
        self.stdinHandle = stdinHandle
        self.stdoutHandle = stdoutHandle
        self.limits = CborLimits()
        self.frameWriter = CborFrameWriter(handle: stdinHandle, limits: limits)

        // Perform handshake synchronously before starting reader
        try performHandshake()

        // Start background reader thread
        startReaderLoop()
    }

    deinit {
        close()
    }

    // MARK: - Handshake

    private func performHandshake() throws {
        let frameReader = CborFrameReader(handle: stdoutHandle, limits: limits)

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

        // Extract manifest from plugin's HELLO response
        // This is REQUIRED - plugins MUST include their manifest in HELLO
        guard let manifest = theirFrame.helloManifest else {
            throw CborPluginHostError.handshakeFailed("Plugin HELLO missing required manifest")
        }
        self._pluginManifest = manifest

        // Negotiate limits (use minimum of both)
        let theirMaxFrame = theirFrame.helloMaxFrame ?? DEFAULT_MAX_FRAME
        let theirMaxChunk = theirFrame.helloMaxChunk ?? DEFAULT_MAX_CHUNK

        let negotiatedLimits = CborLimits(
            maxFrame: min(DEFAULT_MAX_FRAME, theirMaxFrame),
            maxChunk: min(DEFAULT_MAX_CHUNK, theirMaxChunk)
        )

        self.limits = negotiatedLimits
        self.frameWriter.setLimits(negotiatedLimits)
    }

    // MARK: - Background Reader

    private func startReaderLoop() {
        let thread = Thread { [weak self] in
            self?.readerLoop()
        }
        thread.name = "CborPluginHost.readerLoop"
        self.readerThread = thread
        thread.start()
    }

    private func readerLoop() {
        let frameReader = CborFrameReader(handle: stdoutHandle, limits: limits)

        while true {
            let frame: CborFrame
            do {
                guard let f = try frameReader.read() else {
                    // EOF - plugin closed
                    notifyAllPending(error: .processExited)
                    break
                }
                frame = f
            } catch {
                // Read error - notify all pending requests
                notifyAllPending(error: .receiveFailed("\(error)"))
                break
            }

            // Handle heartbeats transparently - before ID check
            if frame.frameType == .heartbeat {
                // Check if this is a response to a heartbeat we sent
                heartbeatLock.lock()
                let isOurHeartbeat = pendingHeartbeats.remove(frame.id) != nil
                heartbeatLock.unlock()

                if isOurHeartbeat {
                    // This is a response to our heartbeat - don't respond
                    continue
                }

                // This is a heartbeat request from the plugin - respond
                let response = CborFrame.heartbeat(id: frame.id)
                writerLock.lock()
                do {
                    try frameWriter.write(response)
                } catch {
                    // Log but continue - heartbeat response failure is not fatal
                    fputs("[CborPluginHost] Failed to respond to heartbeat: \(error)\n", stderr)
                }
                writerLock.unlock()
                continue
            }

            // Handle plugin-initiated REQ frames (plugin invoking host caps)
            if frame.frameType == .req {
                self.handlePluginRequest(frame)
                continue
            }

            // Route frame to the appropriate pending request
            let requestId = frame.id
            pendingLock.lock()
            let pendingRequest = pending[requestId]
            pendingLock.unlock()

            guard let request = pendingRequest else {
                // Frame for unknown request ID - drop it
                continue
            }

            var shouldRemove = false

            switch frame.frameType {
            case .chunk:
                let isEof = frame.isEof
                let chunk = CborResponseChunk(
                    payload: frame.payload ?? Data(),
                    seq: frame.seq,
                    offset: frame.offset,
                    len: frame.len,
                    isEof: isEof
                )
                request.continuation.yield(.success(chunk))
                shouldRemove = isEof

            case .res:
                // Single complete response - send as final chunk
                let chunk = CborResponseChunk(
                    payload: frame.payload ?? Data(),
                    seq: 0,
                    offset: nil,
                    len: nil,
                    isEof: true
                )
                request.continuation.yield(.success(chunk))
                shouldRemove = true

            case .end:
                // Stream end - send final payload if any
                if let payload = frame.payload {
                    let chunk = CborResponseChunk(
                        payload: payload,
                        seq: frame.seq,
                        offset: frame.offset,
                        len: frame.len,
                        isEof: true
                    )
                    request.continuation.yield(.success(chunk))
                }
                shouldRemove = true

            case .log:
                // Log frames don't produce response chunks, skip
                break

            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let message = frame.errorMessage ?? "Unknown error"
                request.continuation.yield(.failure(.pluginError(code: code, message: message)))
                shouldRemove = true

            case .hello, .heartbeat:
                // Protocol errors - Heartbeat is handled above, these should not happen
                request.continuation.yield(.failure(.unexpectedFrameType(frame.frameType)))
                shouldRemove = true

            case .req:
                // Plugin is invoking a cap on the host - this should be handled at top level,
                // not routed to a pending request. If we get here, it's a bug.
                fputs("[CborPluginHost] BUG: REQ frame routed to pending request handler\n", stderr)
                shouldRemove = false
            }

            // Remove completed request - extract continuation while holding lock,
            // then finish OUTSIDE the lock to avoid deadlock with onTermination handler
            if shouldRemove {
                var continuationToFinish: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation? = nil
                pendingLock.lock()
                if let removed = pending.removeValue(forKey: requestId) {
                    continuationToFinish = removed.continuation
                }
                pendingLock.unlock()

                continuationToFinish?.finish()
            }
        }

        // Mark as closed
        pendingLock.lock()
        closed = true
        pendingLock.unlock()
    }

    private func notifyAllPending(error: CborPluginHostError) {
        pendingLock.lock()
        closed = true
        let allPending = pending
        pending.removeAll()
        pendingLock.unlock()

        for (_, request) in allPending {
            request.continuation.yield(.failure(error))
            request.continuation.finish()
        }
    }

    /// Thread-safe write of a frame. This is nonisolated to allow calling from async contexts.
    private func writeFrameLocked(_ frame: CborFrame) {
        writerLock.lock()
        try? frameWriter.write(frame)
        writerLock.unlock()
    }

    /// Handle a plugin-initiated REQ frame (plugin invoking a cap on the host).
    ///
    /// This encodes the request as a special NDJSON message and yields it to ALL pending
    /// host requests' streams. The PluginStreamingSession's readNextMessage will receive
    /// it and forward it to fgnd via PluginGRPCBridge. The response comes back via
    /// handleCapResponse, which sends CHUNK/END/ERR frames back to the plugin.
    private func handlePluginRequest(_ frame: CborFrame) {
        let pluginRequestId = frame.id

        // Extract cap URN from the frame
        guard let capUrn = frame.cap else {
            // Missing cap URN - send error back to plugin
            let errFrame = CborFrame.err(id: pluginRequestId, code: "INVALID_REQUEST", message: "Missing cap URN")
            writeFrameLocked(errFrame)
            return
        }

        let payload = frame.payload ?? Data()

        // Generate a string request ID for correlation with cap_response
        let requestIdString: String
        if let uuidString = pluginRequestId.uuidString {
            requestIdString = uuidString
        } else if case .uint(let n) = pluginRequestId {
            requestIdString = String(n)
        } else {
            requestIdString = UUID().uuidString
        }

        // Create the cap_request message as NDJSON
        let capRequestMessage: [String: Any] = [
            "type": "cap_request",
            "request_id": requestIdString,
            "cap": capUrn,
            "payload": payload.base64EncodedString()
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: capRequestMessage),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            let errFrame = CborFrame.err(id: pluginRequestId, code: "ENCODING_ERROR", message: "Failed to encode cap request")
            writeFrameLocked(errFrame)
            return
        }

        // Add newline for NDJSON format
        jsonString += "\n"
        let messageData = Data(jsonString.utf8)

        // Create a continuation to receive the response from the host
        let (responseStream, continuation) = AsyncStream<Result<Data, Error>>.makeStream()

        // Register the pending plugin cap request
        pendingPluginCapRequestsLock.lock()
        pendingPluginCapRequests[pluginRequestId] = continuation
        pendingPluginCapRequestsLock.unlock()

        // Yield the cap_request message to ALL pending host requests' streams.
        // This way, readNextMessage will see it and can forward it to fgnd.
        // Create a special chunk that contains the cap_request NDJSON.
        let capRequestChunk = CborResponseChunk(
            payload: messageData,
            seq: 0,
            offset: nil,
            len: nil,
            isEof: false  // Not EOF - this is an intermediate message
        )

        pendingLock.lock()
        let allPending = pending
        pendingLock.unlock()

        for (_, request) in allPending {
            request.continuation.yield(.success(capRequestChunk))
        }

        // Handle the response asynchronously and stream it back to the plugin
        Task { [weak self, pluginRequestId] in
            guard let self = self else { return }

            var seq: UInt64 = 0
            for await result in responseStream {
                switch result {
                case .success(let data):
                    // Send CHUNK frame with the response data back to the plugin
                    let chunk = CborFrame.chunk(id: pluginRequestId, seq: seq, payload: data)
                    self.writeFrameLocked(chunk)
                    seq += 1

                case .failure(let error):
                    // Send ERR frame to the plugin and stop
                    let errFrame = CborFrame.err(
                        id: pluginRequestId,
                        code: "CAP_INVOCATION_ERROR",
                        message: error.localizedDescription
                    )
                    self.writeFrameLocked(errFrame)
                    return
                }
            }

            // Stream completed - send END frame to the plugin
            let endFrame = CborFrame.end(id: pluginRequestId, finalPayload: nil)
            self.writeFrameLocked(endFrame)
        }
    }

    /// Handle a cap response message from the host.
    /// Called when fgnd responds to a plugin-initiated cap request.
    /// Routes the response to the pending plugin request's continuation,
    /// which then sends CHUNK/END/ERR frames back to the plugin.
    public func handleCapResponse(requestIdString: String, payload: Data?, error: Error?) {
        // Find the matching plugin request by iterating over pending requests
        // and matching the string representation of the request ID
        pendingPluginCapRequestsLock.lock()
        var matchingKey: CborMessageId? = nil
        for (key, _) in pendingPluginCapRequests {
            let keyString: String
            if let uuidString = key.uuidString {
                keyString = uuidString
            } else if case .uint(let n) = key {
                keyString = String(n)
            } else {
                continue
            }
            if keyString == requestIdString {
                matchingKey = key
                break
            }
        }

        guard let key = matchingKey,
              let continuation = pendingPluginCapRequests.removeValue(forKey: key) else {
            pendingPluginCapRequestsLock.unlock()
            fputs("[CborPluginHost] Received cap_response for unknown request: \(requestIdString)\n", stderr)
            return
        }
        pendingPluginCapRequestsLock.unlock()

        if let error = error {
            continuation.yield(.failure(error))
        } else if let payload = payload {
            continuation.yield(.success(payload))
        }
        continuation.finish()
    }

    // MARK: - Public API

    /// Send a cap request and receive responses via an AsyncStream.
    ///
    /// Returns an AsyncStream that yields response chunks. Iterate over it
    /// to receive all chunks until completion.
    ///
    /// Multiple requests can be sent concurrently - each gets its own
    /// response stream. The runtime handles all multiplexing and
    /// heartbeats transparently.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN to invoke
    ///   - payload: Request payload
    ///   - contentType: Content type of payload (default: "application/json")
    /// - Returns: AsyncStream of response chunks
    /// - Throws: CborPluginHostError if host is closed or send fails
    public func request(
        capUrn: String,
        payload: Data,
        contentType: String = "application/json"
    ) throws -> AsyncStream<Result<CborResponseChunk, CborPluginHostError>> {
        pendingLock.lock()
        if closed {
            pendingLock.unlock()
            throw CborPluginHostError.closed
        }
        pendingLock.unlock()

        let requestId = CborMessageId.newUUID()
        let frame = CborFrame.req(id: requestId, capUrn: capUrn, payload: payload, contentType: contentType)

        // Create stream before sending request
        let stream = AsyncStream<Result<CborResponseChunk, CborPluginHostError>> { continuation in
            // Register pending request
            pendingLock.lock()
            pending[requestId] = PendingRequest(continuation: continuation)
            pendingLock.unlock()

            continuation.onTermination = { [weak self] _ in
                // Clean up if stream is cancelled
                self?.pendingLock.lock()
                self?.pending.removeValue(forKey: requestId)
                self?.pendingLock.unlock()
            }
        }

        // Send request
        writerLock.lock()
        do {
            try frameWriter.write(frame)
        } catch {
            writerLock.unlock()
            // Remove pending request on send failure - extract continuation while holding lock,
            // then finish OUTSIDE the lock to avoid deadlock with onTermination handler
            var continuationToFinish: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation? = nil
            pendingLock.lock()
            if let removed = pending.removeValue(forKey: requestId) {
                continuationToFinish = removed.continuation
            }
            pendingLock.unlock()
            continuationToFinish?.finish()
            throw CborPluginHostError.sendFailed("\(error)")
        }
        writerLock.unlock()

        return stream
    }

    /// Send a cap request and wait for the complete response.
    ///
    /// This is a convenience method that collects all chunks.
    /// For streaming responses, use `request()` directly.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN to invoke
    ///   - payload: Request payload
    ///   - contentType: Content type of payload (default: "application/json")
    /// - Returns: The complete response
    /// - Throws: CborPluginHostError on failure
    public func call(
        capUrn: String,
        payload: Data,
        contentType: String = "application/json"
    ) async throws -> CborPluginResponse {
        let stream = try request(capUrn: capUrn, payload: payload, contentType: contentType)

        var chunks: [CborResponseChunk] = []
        for await result in stream {
            switch result {
            case .success(let chunk):
                let isEof = chunk.isEof
                chunks.append(chunk)
                if isEof {
                    break
                }
            case .failure(let error):
                throw error
            }
        }

        if chunks.count == 1 && chunks[0].seq == 0 {
            return .single(chunks[0].payload)
        } else {
            return .streaming(chunks)
        }
    }

    /// Send a heartbeat to the plugin.
    ///
    /// Note: Heartbeat response is handled by reader loop transparently.
    /// This method returns immediately after sending.
    ///
    /// - Throws: CborPluginHostError if host is closed or send fails
    public func sendHeartbeat() throws {
        pendingLock.lock()
        if closed {
            pendingLock.unlock()
            throw CborPluginHostError.closed
        }
        pendingLock.unlock()

        let heartbeatId = CborMessageId.newUUID()
        let frame = CborFrame.heartbeat(id: heartbeatId)

        // Track this heartbeat so we don't respond to the response
        heartbeatLock.lock()
        pendingHeartbeats.insert(heartbeatId)
        heartbeatLock.unlock()

        writerLock.lock()
        do {
            try frameWriter.write(frame)
        } catch {
            writerLock.unlock()
            // Remove from tracking on failure
            heartbeatLock.lock()
            pendingHeartbeats.remove(heartbeatId)
            heartbeatLock.unlock()
            throw CborPluginHostError.sendFailed("\(error)")
        }
        writerLock.unlock()
    }

    /// Get the negotiated protocol limits
    public var negotiatedLimits: CborLimits {
        return limits
    }

    /// Get the plugin manifest extracted from HELLO handshake.
    /// This is JSON-encoded plugin metadata including name, version, and caps.
    /// Returns the manifest data received from the plugin during handshake.
    public var pluginManifest: Data? {
        return _pluginManifest
    }

    /// Check if the host is closed
    public var isClosed: Bool {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return closed
    }


    /// Close the plugin host.
    ///
    /// Signals EOF to the plugin by closing stdin, marks as closed,
    /// and notifies all pending requests.
    public func close() {
        pendingLock.lock()
        if closed {
            pendingLock.unlock()
            return
        }
        closed = true
        pendingLock.unlock()

        // Close stdin to signal EOF to plugin
        try? stdinHandle.close()

        // Notify all pending requests
        notifyAllPending(error: .closed)
    }
}

// MARK: - Convenience Extensions

@available(macOS 10.15.4, iOS 13.4, *)
public extension CborPluginHost {
    /// Send a JSON-encodable request and receive raw response
    func request<T: Encodable>(capUrn: String, request: T) throws -> AsyncStream<Result<CborResponseChunk, CborPluginHostError>> {
        let data = try JSONEncoder().encode(request)
        return try self.request(capUrn: capUrn, payload: data)
    }

    /// Call with JSON-encodable request and JSON-decodable response
    func call<Req: Encodable, Res: Decodable>(capUrn: String, request: Req) async throws -> Res {
        let requestData = try JSONEncoder().encode(request)
        let response = try await call(capUrn: capUrn, payload: requestData)
        return try JSONDecoder().decode(Res.self, from: response.concatenated())
    }
}
