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
//
//  This mirrors the Rust CapRouter/PeerRequestHandle traits exactly:
//  - beginRequest is SYNCHRONOUS (called from the reader thread)
//  - forwardFrame is SYNCHRONOUS (called from the reader thread)
//  - responseStream provides an AsyncStream for reading responses

import Foundation

/// Handle for an active peer invoke request.
///
/// The CborPluginHost creates this by calling router.beginRequest(), then forwards
/// incoming frames (STREAM_START, CHUNK, STREAM_END, END) to the handle. The handle
/// provides an async stream for response chunks.
///
/// forwardFrame is called synchronously from the reader thread.
/// responseStream is read asynchronously by a Task that forwards chunks back.
public protocol CborPeerRequestHandle: Sendable {
    /// Forward an incoming frame (STREAM_START, CHUNK, STREAM_END, or END) to the target.
    /// Called synchronously from the reader thread — must not block.
    func forwardFrame(_ frame: CborFrame)

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
/// beginRequest is called SYNCHRONOUSLY from the reader thread (matching Rust's CapRouter).
public protocol CborCapRouter: Sendable {
    /// Begin routing a peer invoke request.
    /// Called synchronously from the reader thread — must not block.
    ///
    /// - Parameters:
    ///   - capUrn: The cap URN being requested
    ///   - reqId: The request ID (16-byte UUID) from the REQ frame
    /// - Returns: A handle for forwarding frames and receiving responses
    /// - Throws: peerInvokeNotSupported if no plugin provides the cap
    func beginRequest(capUrn: String, reqId: Data) throws -> CborPeerRequestHandle
}

/// No-op router that rejects all peer invoke requests.
public struct NoCborPeerRouter: CborCapRouter {
    public init() {}

    public func beginRequest(capUrn: String, reqId: Data) throws -> CborPeerRequestHandle {
        throw CborPluginHostError.peerInvokeNotSupported(capUrn)
    }
}
