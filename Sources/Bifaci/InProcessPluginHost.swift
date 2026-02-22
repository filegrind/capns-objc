//
//  InProcessPluginHost.swift
//  In-Process Plugin Host — Direct dispatch to FrameHandler protocols
//
//  Sits where PluginHost sits (connected to RelaySlave via local socket pair),
//  but routes requests to `FrameHandler` protocol conformers instead of plugin binaries.
//
//  ## Architecture
//
//  RelaySlave ←→ InProcessPluginHost ←→ Handler A (streaming frames)
//                                    ←→ Handler B (streaming frames)
//                                    ←→ Handler C (streaming frames)
//
//  ## Design
//
//  The host does NOT accumulate data. On REQ, it spawns a handler with
//  channels for frame I/O. All continuation frames (STREAM_START, CHUNK, STREAM_END,
//  END) are forwarded to the handler. The handler processes frames natively —
//  streaming or accumulating as it sees fit.
//
//  This matches how real plugins work: PluginRuntime forwards frames to handlers,
//  and each handler decides how to consume/produce data.

import Foundation
import CapNs
import SwiftCBOR

// MARK: - FrameHandler Protocol

/// Handler for streaming frame-based requests.
///
/// Handlers receive input frames (STREAM_START, CHUNK, STREAM_END, END) via a
/// channel and send response frames via a ResponseWriter. The host never
/// accumulates — handlers decide how to process input (stream or accumulate).
///
/// For handlers that don't need streaming, use `accumulateInput()` to collect
/// all input streams into `[CapArgumentValue]`.
public protocol FrameHandler: Sendable {
    /// Handle a streaming request.
    ///
    /// Called in a dedicated thread for each incoming request. The handler reads
    /// input frames from `inputStream` and sends response frames via `output`.
    ///
    /// The REQ frame has already been consumed by the host. `inputStream` receives:
    /// STREAM_START, CHUNK, STREAM_END (per argument stream), then END.
    ///
    /// The handler MUST send a complete response: either response frames
    /// (STREAM_START + CHUNK(s) + STREAM_END + END) or an error (via `output.emitError()`).
    func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) async
}

// MARK: - ResponseWriter

/// Wraps an output channel with automatic request_id and routing_id stamping.
///
/// All frames sent via ResponseWriter get the correct request_id and routing_id
/// for relay routing. Seq is left at 0 — the wire writer's SeqAssigner handles it.
public final class ResponseWriter: @unchecked Sendable {
    private let requestId: MessageId
    private let routingId: MessageId?
    private let sendFrame: @Sendable (Frame) -> Void
    private let maxChunkSize: Int

    init(requestId: MessageId, routingId: MessageId?, sendFrame: @escaping @Sendable (Frame) -> Void, maxChunk: Int) {
        self.requestId = requestId
        self.routingId = routingId
        self.sendFrame = sendFrame
        self.maxChunkSize = maxChunk
    }

    /// Send a frame, stamping it with the request_id and routing_id.
    public func send(_ frame: Frame) {
        var stamped = frame
        stamped.id = requestId
        stamped.routingId = routingId
        stamped.seq = 0 // SeqAssigner handles this
        sendFrame(stamped)
    }

    /// Max chunk size for this connection.
    public func maxChunk() -> Int {
        return maxChunkSize
    }

    /// Send a complete data response: STREAM_START + CBOR-encoded CHUNK(s) + STREAM_END + END.
    public func emitResponse(mediaUrn: String, data: Data) {
        let streamId = "result"

        send(Frame.streamStart(reqId: MessageId.uint(0), streamId: streamId, mediaUrn: mediaUrn))

        if data.isEmpty {
            // Empty data: single chunk with CBOR-encoded empty bytes
            let cborPayload = Data(CBOR.byteString([UInt8](Data())).encode())
            let checksum = Frame.computeChecksum(cborPayload)
            send(Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: cborPayload, chunkIndex: 0, checksum: checksum))
            send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: 1))
        } else {
            let chunks = stride(from: 0, to: data.count, by: maxChunkSize).map {
                data[$0..<min($0 + maxChunkSize, data.count)]
            }
            let chunkCount = UInt64(chunks.count)

            for (index, chunkData) in chunks.enumerated() {
                let cborPayload = Data(CBOR.byteString([UInt8](chunkData)).encode())
                let checksum = Frame.computeChecksum(cborPayload)
                send(Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: cborPayload, chunkIndex: UInt64(index), checksum: checksum))
            }
            send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: chunkCount))
        }

        send(Frame.end(id: MessageId.uint(0)))
    }

    /// Send an error response.
    public func emitError(code: String, message: String) {
        send(Frame.err(id: MessageId.uint(0), code: code, message: message))
    }
}

// MARK: - Input Accumulation Utility

/// Accumulate all input streams from a frame channel into CapArgumentValues.
///
/// Reads frames until END. CBOR-decodes chunk payloads to extract raw bytes.
/// For handlers that don't need streaming — they accumulate all input, process,
/// then emit a response.
///
/// Returns nil on CBOR decode failure (protocol violation).
public func accumulateInput(inputStream: AsyncStream<Frame>) async throws -> [CapArgumentValue] {
    var streams: [(streamId: String, mediaUrn: String, data: Data)] = []
    var active: [String: Int] = [:]

    for await frame in inputStream {
        switch frame.frameType {
        case .streamStart:
            let sid = frame.streamId ?? ""
            let mediaUrn = frame.mediaUrn ?? ""
            let idx = streams.count
            streams.append((sid, mediaUrn, Data()))
            active[sid] = idx

        case .chunk:
            let sid = frame.streamId ?? ""
            if let idx = active[sid], let payload = frame.payload {
                // CBOR-decode chunk payload to extract raw bytes
                guard let cbor = try? CBOR.decode([UInt8](payload)) else {
                    throw NSError(domain: "accumulateInput", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "chunk payload is not valid CBOR (stream=\(sid), \(payload.count) bytes)"
                    ])
                }

                switch cbor {
                case .byteString(let bytes):
                    streams[idx].data.append(contentsOf: bytes)
                case .utf8String(let str):
                    streams[idx].data.append(contentsOf: str.data(using: String.Encoding.utf8) ?? Data())
                default:
                    throw NSError(domain: "accumulateInput", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "unexpected CBOR type in chunk payload: \(cbor)"
                    ])
                }
            }

        case .streamEnd:
            break // nothing to do

        case .end:
            return streams.map { CapArgumentValue(mediaUrn: $0.mediaUrn, value: $0.data) }

        default:
            break // ignore unexpected frame types
        }
    }

    // If we exit the loop without seeing END, return what we have
    return streams.map { CapArgumentValue(mediaUrn: $0.mediaUrn, value: $0.data) }
}

// MARK: - Built-in Identity Handler

/// Identity handler: raw byte passthrough (no CBOR decode/encode).
///
/// Echoes all accumulated chunk payloads back as-is. This is the protocol-level
/// identity verification — it proves the transport works end-to-end.
final class IdentityHandler: FrameHandler {
    func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) async {
        // Accumulate raw payload bytes (no CBOR decode — identity is raw passthrough)
        var data = Data()
        for await frame in inputStream {
            switch frame.frameType {
            case .chunk:
                if let payload = frame.payload {
                    data.append(payload)
                }
            case .end:
                // Echo back as a single stream (raw bytes, no CBOR encode)
                let streamId = "identity"
                output.send(Frame.streamStart(reqId: MessageId.uint(0), streamId: streamId, mediaUrn: "media:"))

                let checksum = Frame.computeChecksum(data)
                output.send(Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: data, chunkIndex: 0, checksum: checksum))

                output.send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: 1))
                output.send(Frame.end(id: MessageId.uint(0)))
                return

            default:
                break // STREAM_START, STREAM_END — skip
            }
        }
    }
}

// MARK: - In-Process Plugin Host

/// Entry for a registered in-process handler.
struct HandlerEntry {
    let name: String
    let caps: [CSCap]
    let handler: FrameHandler
}

/// Cap table entry: (cap_urn_string, handler_index).
typealias CapTable = [(String, Int)]

/// A plugin host that dispatches to in-process FrameHandler implementations.
///
/// Speaks the Frame protocol to a RelaySlave, but routes requests to
/// `FrameHandler` protocol conformers via frame channels — no accumulation
/// at the host level, handlers own the streaming.
public final class InProcessPluginHost {
    private let handlers: [HandlerEntry]

    /// Create a new in-process plugin host with the given handlers.
    ///
    /// Each handler is a tuple of (name, caps, handler).
    public init(handlers: [(name: String, caps: [CSCap], handler: FrameHandler)]) {
        self.handlers = handlers.map { HandlerEntry(name: $0.name, caps: $0.caps, handler: $0.handler) }
    }

    /// Build the aggregate manifest as a JSON array of cap URN strings.
    /// Always includes CAP_IDENTITY as the first entry.
    internal func buildManifest() -> Data {
        var capUrns: [String] = [CSCapIdentity]
        for entry in handlers {
            for cap in entry.caps {
                let urn = cap.capUrn.toString()
                if urn != CSCapIdentity {
                    capUrns.append(urn)
                }
            }
        }
        return (try? JSONEncoder().encode(capUrns)) ?? Data("[]".utf8)
    }

    /// Build the cap table for routing: flat list of (cap_urn, handler_idx).
    private static func buildCapTable(handlers: [HandlerEntry]) -> CapTable {
        var table: CapTable = []
        for (idx, entry) in handlers.enumerated() {
            for cap in entry.caps {
                table.append((cap.capUrn.toString(), idx))
            }
        }
        return table
    }

    /// Find the best handler for a cap URN using closest-specificity matching.
    ///
    /// Mirrors `PluginHostRuntime::find_plugin_for_cap()` exactly:
    /// - Request is pattern, registered cap is instance
    /// - Closest specificity to request wins
    /// - Ties broken by first match (deterministic)
    private static func findHandlerForCap(capTable: CapTable, capUrn: String) -> Int? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        let requestSpecificity = Int(requestUrn.specificity())
        var matches: [(handlerIdx: Int, specificity: Int)] = []

        for (registeredCap, handlerIdx) in capTable {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                if requestUrn.accepts(registeredUrn) {
                    let specificity = Int(registeredUrn.specificity())
                    matches.append((handlerIdx, specificity))
                }
            }
        }

        guard !matches.isEmpty else {
            return nil
        }

        let minDistance = matches.map { abs($0.specificity - requestSpecificity) }.min()!

        return matches.first { abs($0.specificity - requestSpecificity) == minDistance }?.handlerIdx
    }

    /// Run the host. Blocks until the local connection closes.
    ///
    /// `localRead` / `localWrite` connect to the RelaySlave's local side.
    public func run(localRead: FileHandle, localWrite: FileHandle) throws {
        let reader = FrameReader(handle: localRead)

        // Writer runs with SeqAssigner
        let writeContinuation: AsyncStream<Frame>.Continuation
        let writeStream: AsyncStream<Frame>
        (writeStream, writeContinuation) = AsyncStream<Frame>.makeStream()

        let writerTask = Task {
            let writer = FrameWriter(handle: localWrite)
            let seqAssigner = SeqAssigner()

            for await var frame in writeStream {
                seqAssigner.assign(&frame)
                try? writer.write(frame)
                if frame.frameType == .end || frame.frameType == .err {
                    seqAssigner.remove(FlowKey.fromFrame(frame))
                }
            }
        }

        // Send initial RelayNotify with aggregate caps
        let manifest = buildManifest()
        let notify = Frame.relayNotify(manifest: manifest, limits: Limits())
        writeContinuation.yield(notify)

        // Build cap table
        let capTable = Self.buildCapTable(handlers: handlers)

        // Active request channels: request_id → AsyncStream.Continuation for forwarding frames to handler
        var active: [MessageId: AsyncStream<Frame>.Continuation] = [:]

        // Built-in identity handler
        let identityHandler = IdentityHandler()

        // Main read loop — forward frames to handlers, no accumulation
        while let frame = try? reader.read() {
            switch frame.frameType {
            case .req:
                let rid = frame.id
                let xid = frame.routingId
                guard let capUrn = frame.cap else {
                    var err = Frame.err(id: rid, code: "PROTOCOL_ERROR", message: "REQ missing cap URN")
                    err.routingId = xid
                    writeContinuation.yield(err)
                    continue
                }

                // Identity cap is "cap:" — exact string match, NOT conforms_to.
                let isIdentity = capUrn == CSCapIdentity

                let handler: FrameHandler = isIdentity ? identityHandler : {
                    if let idx = Self.findHandlerForCap(capTable: capTable, capUrn: capUrn) {
                        return handlers[idx].handler
                    } else {
                        var err = Frame.err(id: rid, code: "NO_HANDLER", message: "no handler for cap: \(capUrn)")
                        err.routingId = xid
                        writeContinuation.yield(err)
                        return identityHandler // dummy, never used
                    }
                }()

                // If NO_HANDLER was sent, skip spawning handler
                if !isIdentity && Self.findHandlerForCap(capTable: capTable, capUrn: capUrn) == nil {
                    continue
                }

                // Create channel for forwarding frames to handler
                let inputContinuation: AsyncStream<Frame>.Continuation
                let inputStream: AsyncStream<Frame>
                (inputStream, inputContinuation) = AsyncStream<Frame>.makeStream()
                active[rid] = inputContinuation

                // Spawn handler task
                let output = ResponseWriter(
                    requestId: rid,
                    routingId: xid,
                    sendFrame: { writeContinuation.yield($0) },
                    maxChunk: Limits().maxChunk
                )

                Task.detached {
                    await handler.handleRequest(capUrn: capUrn, inputStream: inputStream, output: output)
                }

            // Continuation frames: forward to handler
            case .streamStart, .chunk, .streamEnd:
                if let continuation = active[frame.id] {
                    continuation.yield(frame)
                }

            case .end:
                // Forward END to handler, then remove from active
                if let continuation = active.removeValue(forKey: frame.id) {
                    continuation.yield(frame)
                    continuation.finish()
                }

            case .heartbeat:
                let response = Frame.heartbeat(id: frame.id)
                writeContinuation.yield(response)

            case .err:
                // Error from relay for a pending request — close handler's input
                if let continuation = active.removeValue(forKey: frame.id) {
                    continuation.finish()
                }

            default:
                // RelayNotify, RelayState, etc. — not expected from relay side
                break
            }
        }

        // Drop all active channels to signal handlers to exit
        for (_, continuation) in active {
            continuation.finish()
        }
        active.removeAll()

        writeContinuation.finish()
        writerTask.cancel()
    }
}
