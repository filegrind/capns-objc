//
//  LocalPluginRouter.swift
//  CapNsCbor
//
//  Local Plugin Router - Routes peer invoke requests to local plugin instances
//
//  This router maintains a registry of local CborPluginHost instances and routes
//  peer invoke requests to them based on cap URN matching.

import Foundation
@preconcurrency import SwiftCBOR
import CapNs

/// Router that routes to locally registered plugin instances.
///
/// Use this when you have multiple plugins running locally and want them to invoke
/// each other's capabilities. The router matches incoming cap URNs against registered
/// plugins and forwards requests to compatible handlers.
@available(macOS 10.15.4, iOS 13.4, *)
public final class LocalCborPluginRouter: CborCapRouter, @unchecked Sendable {
    private var routes: [(String, CborPluginHost)] = []  // ordered
    private let lock = NSLock()

    public init() {}

    /// Register a plugin for a specific cap URN.
    public func registerPlugin(capUrn: String, host: CborPluginHost) {
        lock.lock()
        routes.append((capUrn, host))
        lock.unlock()
    }

    /// Find a plugin that can handle the given cap URN.
    public func findPlugin(_ capUrn: String) -> CborPluginHost? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        for (registeredCap, host) in routes {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                if registeredUrn.accepts(requestUrn) {
                    return host
                }
            }
        }

        return nil
    }

    public func beginRequest(capUrn: String, reqId: Data) throws -> CborPeerRequestHandle {
        guard let plugin = findPlugin(capUrn) else {
            throw CborPluginHostError.peerInvokeNotSupported(capUrn)
        }

        return LocalPluginRequestHandle(
            capUrn: capUrn,
            plugin: plugin,
            reqId: reqId
        )
    }
}

/// Handle for an active peer request being routed to a local plugin.
///
/// Accumulates argument streams synchronously (called from reader thread),
/// then executes the cap on the target plugin asynchronously on END.
@available(macOS 10.15.4, iOS 13.4, *)
final class LocalPluginRequestHandle: CborPeerRequestHandle, @unchecked Sendable {
    private let capUrn: String
    private let plugin: CborPluginHost
    private let reqId: Data
    private var streams: [(String, String, Data)] = []  // (stream_id, media_urn, data) - ordered
    private let lock = NSLock()
    private let responseContinuation: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation
    private let _responseStream: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>

    init(capUrn: String, plugin: CborPluginHost, reqId: Data) {
        self.capUrn = capUrn
        self.plugin = plugin
        self.reqId = reqId

        var continuation: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation!
        self._responseStream = AsyncStream { cont in
            continuation = cont
        }
        self.responseContinuation = continuation
    }

    /// Called synchronously from the reader thread.
    func forwardFrame(_ frame: CborFrame) {
        switch frame.frameType {
        case .streamStart:
            let streamId = frame.streamId ?? ""
            let mediaUrn = frame.mediaUrn ?? ""
            lock.lock()
            streams.append((streamId, mediaUrn, Data()))
            lock.unlock()

        case .chunk:
            let streamId = frame.streamId ?? ""
            if let payload = frame.payload {
                lock.lock()
                if let index = streams.firstIndex(where: { $0.0 == streamId }) {
                    streams[index].2.append(payload)
                }
                lock.unlock()
            }

        case .streamEnd:
            // Stream tracking only
            break

        case .end:
            // Collect accumulated arguments
            lock.lock()
            let currentStreams = streams
            lock.unlock()

            let tupleArgs = currentStreams.map { (mediaUrn: $0.1, value: $0.2) }

            // Execute cap on target plugin asynchronously
            let continuation = responseContinuation
            let plugin = self.plugin
            let capUrn = self.capUrn
            Task {
                do {
                    let responseStream = try plugin.requestWithArguments(
                        capUrn: capUrn,
                        arguments: tupleArgs
                    )

                    for await chunkResult in responseStream {
                        continuation.yield(chunkResult)
                    }

                    continuation.finish()
                } catch {
                    continuation.yield(.failure(.sendFailed(error.localizedDescription)))
                    continuation.finish()
                }
            }

        default:
            break
        }
    }

    func responseStream() -> AsyncStream<Result<CborResponseChunk, CborPluginHostError>> {
        return _responseStream
    }
}
