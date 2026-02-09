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
public actor LocalCborPluginRouter: CborCapRouter {
    private var routes: [String: CborPluginHost] = [:]

    public init() {}

    /// Register a plugin for a specific cap URN.
    ///
    /// When a peer invoke request arrives for a compatible cap, it will be routed to this plugin.
    public func registerPlugin(capUrn: String, host: CborPluginHost) {
        routes[capUrn] = host
    }

    /// Find a plugin that can handle the given cap URN.
    ///
    /// Returns nil if no registered plugin is compatible with the request.
    public func findPlugin(_ capUrn: String) async -> CborPluginHost? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        for (registeredCap, host) in routes {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                // Check if registered cap accepts the request
                if registeredUrn.accepts(requestUrn) {
                    return host
                }
            }
        }

        return nil
    }

    public func beginRequest(capUrn: String, reqId: Data) async throws -> CborPeerRequestHandle {
        guard let plugin = await findPlugin(capUrn) else {
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
/// This accumulates argument streams, then executes the cap on the target plugin
/// and streams responses back.
///
/// Uses actor isolation for thread-safe stream accumulation.
@available(macOS 10.15.4, iOS 13.4, *)
actor LocalPluginRequestHandle: CborPeerRequestHandle {
    private let capUrn: String
    private let plugin: CborPluginHost
    private let reqId: Data
    private var streams: [(String, String, Data)] = []  // (stream_id, media_urn, data) - ordered
    private let responseContinuation: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation
    private let _responseStream: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>

    init(capUrn: String, plugin: CborPluginHost, reqId: Data) {
        self.capUrn = capUrn
        self.plugin = plugin
        self.reqId = reqId

        // Create response stream
        var continuation: AsyncStream<Result<CborResponseChunk, CborPluginHostError>>.Continuation!
        self._responseStream = AsyncStream { cont in
            continuation = cont
        }
        self.responseContinuation = continuation
    }

    func forwardFrame(_ frame: CborFrame) async {
        switch frame.frameType {
        case .streamStart:
            let streamId = frame.streamId ?? ""
            let mediaUrn = frame.mediaUrn ?? ""
            fputs("[LocalPluginRequestHandle] STREAM_START: stream_id=\(streamId) media_urn=\(mediaUrn)\n", stderr)

            streams.append((streamId, mediaUrn, Data()))

        case .chunk:
            let streamId = frame.streamId ?? ""
            if let payload = frame.payload {
                if let index = streams.firstIndex(where: { $0.0 == streamId }) {
                    streams[index].2.append(payload)
                    fputs("[LocalPluginRequestHandle] CHUNK: stream_id=\(streamId) total_size=\(streams[index].2.count)\n", stderr)
                }
            }

        case .streamEnd:
            let streamId = frame.streamId ?? ""
            fputs("[LocalPluginRequestHandle] STREAM_END: stream_id=\(streamId)\n", stderr)

        case .end:
            fputs("[LocalPluginRequestHandle] END: executing cap with accumulated arguments\n", stderr)

            // Build CborCapArgumentValue array from accumulated streams
            let currentStreams = streams

            let arguments: [CborCapArgumentValue] = currentStreams.map { (_streamId, mediaUrn, data) in
                CborCapArgumentValue(mediaUrn: mediaUrn, value: data)
            }

            fputs("[LocalPluginRequestHandle] Executing cap with \(arguments.count) arguments\n", stderr)

            // Execute cap on plugin in background task
            let continuation = responseContinuation
            let plugin = self.plugin
            let capUrn = self.capUrn
            Task {
                do {
                    // Convert CborCapArgumentValue to tuple format
                    let tupleArgs = arguments.map { ($0.mediaUrn, $0.value) }

                    let responseStream = try plugin.requestWithArguments(
                        capUrn: capUrn,
                        arguments: tupleArgs
                    )

                    // Forward all response chunks
                    for await chunkResult in responseStream {
                        continuation.yield(chunkResult)
                    }

                    // End the response stream
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

    nonisolated func responseStream() -> AsyncStream<Result<CborResponseChunk, CborPluginHostError>> {
        return _responseStream
    }
}
