/// RelaySlave — Slave endpoint of the CBOR frame relay.
///
/// Sits inside the plugin host process (e.g., XPC service). Bridges between a socket
/// connection (to the RelayMaster in the engine) and local I/O (to/from PluginHost).
///
/// Two relay-specific frame types are intercepted and never leaked through:
/// - RelayNotify (slave -> master): Capability advertisement, injected by the host runtime
/// - RelayState (master -> slave): Host system resources, stored for the host runtime
///
/// All other frames pass through transparently in both directions.

import Foundation
#if canImport(PotentCBOR)
import PotentCBOR
#endif

/// Errors specific to relay operations.
public enum RelayError: Error, Sendable {
    case socketClosed
    case localClosed
    case ioError(String)
    case protocolError(String)
}

/// Slave relay endpoint. Manages bidirectional frame forwarding between
/// a socket (master/engine side) and local streams (PluginHostRuntime side).
@available(macOS 10.15.4, iOS 13.4, *)
public final class RelaySlave: @unchecked Sendable {
    /// Read from PluginHostRuntime
    private let localReader: FrameReader
    /// Write to PluginHostRuntime
    private let localWriter: FrameWriter
    /// Latest RelayState payload from master (thread-safe)
    private let resourceStateLock = NSLock()
    private var _resourceState: Data = Data()

    /// Create a relay slave with local I/O streams (to/from PluginHostRuntime).
    ///
    /// - Parameters:
    ///   - localRead: FileHandle to read frames from (PluginHostRuntime output)
    ///   - localWrite: FileHandle to write frames to (PluginHostRuntime input)
    public init(localRead: FileHandle, localWrite: FileHandle) {
        self.localReader = FrameReader(handle: localRead)
        self.localWriter = FrameWriter(handle: localWrite)
    }

    /// Get the latest resource state payload received from the master.
    public var resourceState: Data {
        resourceStateLock.lock()
        defer { resourceStateLock.unlock() }
        return _resourceState
    }

    /// Run the relay. Blocks until one side closes or an error occurs.
    ///
    /// Uses two concurrent threads for true bidirectional forwarding:
    /// - Thread 1 (socket -> local): ReorderBuffer validates seq, RelayState is stored (not forwarded); all other frames pass through
    /// - Thread 2 (local -> socket): ReorderBuffer validates seq, RelayNotify forwarded (cap updates), RelayState dropped; all others pass through
    ///
    /// When either direction closes, the other is shut down by closing the
    /// corresponding write handle, causing the blocked read to return EOF.
    ///
    /// - Parameters:
    ///   - socketRead: FileHandle for the socket read end (from master)
    ///   - socketWrite: FileHandle for the socket write end (to master)
    ///   - initialNotify: If provided, sends a RelayNotify frame to the master before starting the loop
    public func run(
        socketRead: FileHandle,
        socketWrite: FileHandle,
        initialNotify: (manifest: Data, limits: Limits)? = nil
    ) throws {
        let socketReader = FrameReader(handle: socketRead)
        let socketWriter = FrameWriter(handle: socketWrite)

        // Send initial RelayNotify if provided
        if let notify = initialNotify {
            let frame = Frame.relayNotify(
                manifest: notify.manifest,
                limits: notify.limits
            )
            try socketWriter.write(frame)
        }

        let group = DispatchGroup()
        let errorLock = NSLock()
        var firstError: Error?

        // Thread 1: Socket -> Local (master -> slave direction)
        // Uses ReorderBuffer to validate and reorder incoming frames from master
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Create reorder buffer for socket -> local direction
            // Use negotiated limit from initialNotify, or default
            let maxReorderBuffer = initialNotify?.limits.maxReorderBuffer ?? DEFAULT_MAX_REORDER_BUFFER
            let reorderBuffer = ReorderBuffer(maxBufferPerFlow: maxReorderBuffer)

            defer {
                group.leave()
                // Close local writer to signal PluginHost that relay is gone.
                // This causes the host's relay reader thread to get EOF -> relayClosed.
                try? localWriter.handle.close()
            }
            while true {
                do {
                    guard let frame = try socketReader.read() else {
                        return // Socket closed by master
                    }

                    // Intercept RelayState frames
                    if frame.frameType == .relayState {
                        if let payload = frame.payload {
                            resourceStateLock.lock()
                            _resourceState = payload
                            resourceStateLock.unlock()
                        }
                        continue
                    }

                    // RelayNotify from master is a protocol error — ignore
                    if frame.frameType == .relayNotify {
                        continue
                    }

                    // Pass through reorder buffer
                    let readyFrames = try reorderBuffer.accept(frame)
                    for readyFrame in readyFrames {
                        // Cleanup flow state after terminal frames
                        if readyFrame.frameType == .end || readyFrame.frameType == .err {
                            let key = FlowKey.fromFrame(readyFrame)
                            reorderBuffer.cleanupFlow(key)
                        }
                        try localWriter.write(readyFrame)
                    }
                } catch {
                    errorLock.lock()
                    if firstError == nil { firstError = error }
                    errorLock.unlock()
                    return
                }
            }
        }

        // Thread 2: Local -> Socket (slave -> master direction)
        // Uses ReorderBuffer to validate incoming seq from PluginHost
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Create reorder buffer for local -> socket direction
            let maxReorderBuffer = initialNotify?.limits.maxReorderBuffer ?? DEFAULT_MAX_REORDER_BUFFER
            let reorderBuffer = ReorderBuffer(maxBufferPerFlow: maxReorderBuffer)

            defer {
                group.leave()
                // Close socket write to signal master that slave is gone.
                try? socketWrite.close()
            }
            while true {
                do {
                    guard let frame = try localReader.read() else {
                        return // Local side closed (host shut down)
                    }

                    // Forward all frames, including RelayNotify (capability updates from PluginHost)
                    // RelayState from local is dropped (deprecated/unused)
                    if frame.frameType == .relayState {
                        continue
                    }

                    // Pass through reorder buffer to validate seq
                    let readyFrames = try reorderBuffer.accept(frame)
                    for readyFrame in readyFrames {
                        // Cleanup flow state after terminal frames
                        if readyFrame.frameType == .end || readyFrame.frameType == .err {
                            let key = FlowKey.fromFrame(readyFrame)
                            reorderBuffer.cleanupFlow(key)
                        }
                        try socketWriter.write(readyFrame)
                    }
                } catch {
                    errorLock.lock()
                    if firstError == nil { firstError = error }
                    errorLock.unlock()
                    return
                }
            }
        }

        group.wait()

        errorLock.lock()
        let err = firstError
        errorLock.unlock()

        if let err = err {
            throw err
        }
    }


    /// Send a RelayNotify frame directly to the socket writer.
    /// Used when capabilities change (plugin discovered, plugin died).
    ///
    /// - Parameters:
    ///   - socketWriter: Writer connected to the master relay socket
    ///   - manifest: Aggregate manifest JSON of all available plugin capabilities
    ///   - limits: Negotiated protocol limits
    public static func sendNotify(
        socketWriter: FrameWriter,
        manifest: Data,
        limits: Limits
    ) throws {
        let frame = Frame.relayNotify(
            manifest: manifest,
            limits: limits
        )
        try socketWriter.write(frame)
    }
}

/// Master relay endpoint. Sits in the engine process.
///
/// - Reads frames from the socket (from slave): RelayNotify -> update internal state; others -> return to caller (via reorder buffer)
/// - Can send RelayState frames to the slave
@available(macOS 10.15.4, iOS 13.4, *)
public final class RelayMaster: @unchecked Sendable {
    /// Latest manifest from slave's RelayNotify
    private(set) public var manifest: Data
    /// Latest limits from slave's RelayNotify
    private(set) public var limits: Limits
    /// Reorder buffer for validating incoming seq from slave
    private let reorderBuffer: ReorderBuffer
    /// Internal queue of ready frames (when reorder buffer returns multiple frames)
    private var readyQueue: [Frame] = []
    private let stateLock = NSLock()

    private init(manifest: Data, limits: Limits) {
        self.manifest = manifest
        self.limits = limits
        self.reorderBuffer = ReorderBuffer(maxBufferPerFlow: limits.maxReorderBuffer)
    }

    /// Connect to a relay slave by reading the initial RelayNotify frame.
    ///
    /// The slave MUST send a RelayNotify as its first frame after connection.
    /// This extracts the manifest and limits from that frame.
    ///
    /// - Parameter socketReader: Reader connected to the slave relay socket
    /// - Returns: A connected RelayMaster with manifest and limits from the slave
    public static func connect(socketReader: FrameReader) throws -> RelayMaster {
        guard let frame = try socketReader.read() else {
            throw RelayError.socketClosed
        }

        guard frame.frameType == .relayNotify else {
            throw RelayError.protocolError("expected RelayNotify, got \(frame.frameType)")
        }

        guard let manifest = frame.relayNotifyManifest else {
            throw RelayError.protocolError("RelayNotify missing manifest")
        }

        guard let limits = frame.relayNotifyLimits else {
            throw RelayError.protocolError("RelayNotify missing limits")
        }

        return RelayMaster(manifest: manifest, limits: limits)
    }

    /// Send a RelayState frame to the slave with host system resource info.
    ///
    /// - Parameters:
    ///   - socketWriter: Writer connected to the slave relay socket
    ///   - resources: Opaque resource payload (CBOR or JSON encoded by the host)
    public static func sendState(
        socketWriter: FrameWriter,
        resources: Data
    ) throws {
        let frame = Frame.relayState(resources: resources)
        try socketWriter.write(frame)
    }

    /// Read the next non-relay frame from the socket.
    ///
    /// RelayNotify frames are intercepted: manifest and limits are updated.
    /// All other frames pass through reorder buffer for seq validation.
    /// When reorder buffer returns multiple frames (gap filled), they are queued
    /// and returned one at a time on subsequent calls.
    ///
    /// - Parameter socketReader: Reader connected to the slave relay socket
    /// - Returns: The next protocol frame (reordered), or nil on EOF
    public func readFrame(socketReader: FrameReader) throws -> Frame? {
        stateLock.lock()

        // First, check if we have buffered frames from previous reordering
        if !readyQueue.isEmpty {
            let frame = readyQueue.removeFirst()
            stateLock.unlock()
            return frame
        }
        stateLock.unlock()

        // No buffered frames - read from socket and process through reorder buffer
        while true {
            guard let frame = try socketReader.read() else {
                return nil // Socket closed
            }

            if frame.frameType == .relayNotify {
                // Intercept: update manifest and limits
                stateLock.lock()
                if let m = frame.relayNotifyManifest {
                    self.manifest = m
                }
                if let l = frame.relayNotifyLimits {
                    self.limits = l
                }
                stateLock.unlock()
                continue // Don't return relay frames to caller
            } else if frame.frameType == .relayState {
                // RelayState from slave? Protocol error - ignore
                continue
            }

            // Pass through reorder buffer
            let readyFrames = try reorderBuffer.accept(frame)

            if readyFrames.isEmpty {
                // Frame buffered out-of-order, keep reading
                continue
            }

            // Process all ready frames
            for readyFrame in readyFrames {
                // Cleanup flow state after terminal frames
                if readyFrame.frameType == .end || readyFrame.frameType == .err {
                    let key = FlowKey.fromFrame(readyFrame)
                    reorderBuffer.cleanupFlow(key)
                }
            }

            stateLock.lock()
            // Add all ready frames to queue
            readyQueue.append(contentsOf: readyFrames)
            // Return first frame
            let result = readyQueue.removeFirst()
            stateLock.unlock()

            return result
        }
    }
}
