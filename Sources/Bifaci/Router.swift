/// Cap Router - Pluggable routing for peer invoke requests
///
/// When a plugin sends a peer invoke REQ (calling another cap), the host needs to route
/// that request to an appropriate handler. This module provides a protocol-based abstraction
/// for different routing strategies.
///
/// The router receives frames (REQ, STREAM_START, CHUNK, STREAM_END, END) and delegates
/// them to the appropriate target plugin, then forwards responses back.

import Foundation

/// Handle for an active peer invoke request.
///
/// The PluginHost creates this by calling router.beginRequest(), then forwards
/// incoming frames (STREAM_START, CHUNK, STREAM_END, END) to the handle. The handle
/// provides an async stream for response chunks.
public protocol PeerRequestHandle: Sendable {
    /// Forward an incoming frame (STREAM_START, CHUNK, STREAM_END, or END) to the target.
    /// The router forwards these directly to the target plugin.
    func forwardFrame(_ frame: Frame)

    /// Get an async stream for response chunks from the target plugin.
    /// The host reads from this and forwards responses back to the requesting plugin.
    var responseStream: AsyncStream<Result<ResponseChunk, PluginHostError>> { get }
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
/// let handle = try router.beginRequest(capUrn: capUrn, reqId: reqId)
///
/// // 2. Host forwards argument streams to handle
/// handle.forwardFrame(streamStartFrame)
/// handle.forwardFrame(chunkFrame)
/// handle.forwardFrame(streamEndFrame)
/// handle.forwardFrame(endFrame)
///
/// // 3. Host reads responses from handle and forwards back to plugin
/// for await chunkResult in handle.responseStream {
///     let chunk = try chunkResult.get()
///     sendToPlugin(chunk)
/// }
/// ```
public protocol CapRouter: Sendable {
    /// Begin routing a peer invoke request.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN being requested
    ///   - reqId: The request ID from the REQ frame (16 bytes)
    ///
    /// - Returns: A handle for forwarding frames and receiving responses
    ///
    /// - Throws:
    ///   - `PluginHostError.peerInvokeNotSupported` - No plugin provides the requested cap
    ///   - Other errors for plugin spawn failures
    func beginRequest(capUrn: String, reqId: Data) throws -> any PeerRequestHandle
}

/// No-op router that rejects all peer invoke requests.
public struct NoPeerRouter: CapRouter {
    public init() {}

    public func beginRequest(capUrn: String, reqId: Data) throws -> any PeerRequestHandle {
        throw PluginHostError.peerInvokeNotSupported(capUrn)
    }
}
