//
//  CapRouter.swift
//  CapNsCbor
//
//  Cap Router - Pluggable routing for peer invoke requests
//
//  When a plugin sends a peer invoke REQ (calling another cap), the host needs to route
//  that request to an appropriate handler. This module provides a protocol-based abstraction
//  for different routing strategies.
//
//  The router receives frames (REQ, STREAM_START, CHUNK, STREAM_END, END) and delegates
//  them to the appropriate target plugin, then forwards responses back.

import Foundation

/// Handle for an active peer invoke request.
///
/// The CborPluginHost creates this by calling router.beginRequest(), then forwards
/// incoming frames (STREAM_START, CHUNK, STREAM_END, END) to the handle. The handle
/// provides an async stream for response chunks.
public protocol CborPeerRequestHandle: Sendable {
    /// Forward an incoming frame (STREAM_START, CHUNK, STREAM_END, or END) to the target.
    /// The router forwards these directly to the target plugin.
    func forwardFrame(_ frame: CborFrame) async

    /// Get an async stream for response chunks from the target plugin.
    /// The host reads from this and forwards responses back to the requesting plugin.
    func responseStream() -> AsyncStream<Result<CborResponseChunk, CborPluginHostError>>
}

/// Protocol for routing cap invocation requests to appropriate handlers.
///
/// When a plugin issues a peer invoke, the host receives a REQ frame and calls beginRequest().
/// The router returns a handle that the host uses to forward incoming argument streams and
/// receive responses.
///
/// # Example Flow
/// ```swift
/// // 1. Plugin sends REQ frame
/// let handle = try await router.beginRequest(capUrn: capUrn, reqId: reqId)
///
/// // 2. Host forwards argument streams to handle
/// await handle.forwardFrame(streamStartFrame)
/// await handle.forwardFrame(chunkFrame)
/// await handle.forwardFrame(streamEndFrame)
/// await handle.forwardFrame(endFrame)
///
/// // 3. Host reads responses from handle and forwards back to plugin
/// for await chunkResult in handle.responseStream() {
///     switch chunkResult {
///     case .success(let chunk):
///         sendToPlugin(chunk)
///     case .failure(let error):
///         handleError(error)
///     }
/// }
/// ```
public protocol CborCapRouter: Sendable {
    /// Begin routing a peer invoke request.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN being requested
    ///   - reqId: The request ID (16-byte UUID) from the REQ frame
    /// - Returns: A handle for forwarding frames and receiving responses
    /// - Throws: peerInvokeNotSupported if no plugin provides the cap
    func beginRequest(capUrn: String, reqId: Data) async throws -> CborPeerRequestHandle
}

/// No-op router that rejects all peer invoke requests.
///
/// Use this when peer invoke support is not needed or not yet implemented.
/// All requests will fail immediately with peerInvokeNotSupported error.
public struct NoCborPeerRouter: CborCapRouter {
    public init() {}

    public func beginRequest(capUrn: String, reqId: Data) async throws -> CborPeerRequestHandle {
        throw CborPluginHostError.peerInvokeNotSupported(capUrn)
    }
}
