/// CborRelaySlave — Slave endpoint of the CBOR frame relay.
///
/// Sits inside the plugin host process (e.g., XPC service). Bridges between a socket
/// connection (to the RelayMaster in the engine) and local I/O (to/from CborPluginHost).
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
public enum CborRelayError: Error, Sendable {
    case socketClosed
    case localClosed
    case ioError(String)
    case protocolError(String)
}

/// Slave relay endpoint. Manages bidirectional frame forwarding between
/// a socket (master/engine side) and local streams (PluginHostRuntime side).
@available(macOS 10.15.4, iOS 13.4, *)
public final class CborRelaySlave: @unchecked Sendable {
    /// Read from PluginHostRuntime
    private let localReader: CborFrameReader
    /// Write to PluginHostRuntime
    private let localWriter: CborFrameWriter
    /// Latest RelayState payload from master (thread-safe)
    private let resourceStateLock = NSLock()
    private var _resourceState: Data = Data()

    /// Create a relay slave with local I/O streams (to/from PluginHostRuntime).
    ///
    /// - Parameters:
    ///   - localRead: FileHandle to read frames from (PluginHostRuntime output)
    ///   - localWrite: FileHandle to write frames to (PluginHostRuntime input)
    public init(localRead: FileHandle, localWrite: FileHandle) {
        self.localReader = CborFrameReader(handle: localRead)
        self.localWriter = CborFrameWriter(handle: localWrite)
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
    /// - Thread 1 (socket -> local): RelayState is stored (not forwarded); all other frames pass through
    /// - Thread 2 (local -> socket): RelayNotify/RelayState from local are silently dropped; all others pass through
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
        initialNotify: (manifest: Data, limits: CborLimits)? = nil
    ) throws {
        let socketReader = CborFrameReader(handle: socketRead)
        let socketWriter = CborFrameWriter(handle: socketWrite)

        // Send initial RelayNotify if provided
        if let notify = initialNotify {
            let frame = CborFrame.relayNotify(
                manifest: notify.manifest,
                maxFrame: notify.limits.maxFrame,
                maxChunk: notify.limits.maxChunk
            )
            try socketWriter.write(frame)
        }

        let group = DispatchGroup()
        let errorLock = NSLock()
        var firstError: Error?

        // Thread 1: Socket -> Local (master -> slave direction)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer {
                group.leave()
                // Close local writer to signal CborPluginHost that relay is gone.
                // This causes the host's relay reader thread to get EOF -> relayClosed.
                try? localWriter.handle.close()
            }
            while true {
                do {
                    guard let frame = try socketReader.read() else {
                        return // Socket closed by master
                    }
                    if frame.frameType == .relayState {
                        if let payload = frame.payload {
                            resourceStateLock.lock()
                            _resourceState = payload
                            resourceStateLock.unlock()
                        }
                    } else if frame.frameType == .relayNotify {
                        // RelayNotify from master? Protocol error — ignore
                    } else {
                        try localWriter.write(frame)
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
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
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
                    if frame.frameType == .relayNotify || frame.frameType == .relayState {
                        // Relay frames from local side should not happen — ignore
                    } else {
                        try socketWriter.write(frame)
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

    /// Legacy run() signature for existing tests. Delegates to concurrent implementation.
    public func run(
        socketReader: CborFrameReader,
        socketWriter: CborFrameWriter,
        initialNotify: (manifest: Data, limits: CborLimits)? = nil
    ) throws {
        // For tests using pre-constructed readers/writers, fall back to alternating mode.
        // Send initial RelayNotify if provided.
        if let notify = initialNotify {
            let frame = CborFrame.relayNotify(
                manifest: notify.manifest,
                maxFrame: notify.limits.maxFrame,
                maxChunk: notify.limits.maxChunk
            )
            try socketWriter.write(frame)
        }

        while true {
            guard let socketFrame = try socketReader.read() else { return }

            if socketFrame.frameType == .relayState {
                if let payload = socketFrame.payload {
                    resourceStateLock.lock()
                    _resourceState = payload
                    resourceStateLock.unlock()
                }
            } else if socketFrame.frameType == .relayNotify {
                // ignore
            } else {
                try localWriter.write(socketFrame)
            }

            guard let localFrame = try localReader.read() else { return }

            if localFrame.frameType == .relayNotify || localFrame.frameType == .relayState {
                // ignore
            } else {
                try socketWriter.write(localFrame)
            }
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
        socketWriter: CborFrameWriter,
        manifest: Data,
        limits: CborLimits
    ) throws {
        let frame = CborFrame.relayNotify(
            manifest: manifest,
            maxFrame: limits.maxFrame,
            maxChunk: limits.maxChunk
        )
        try socketWriter.write(frame)
    }
}

/// Master relay endpoint. Sits in the engine process.
///
/// - Reads frames from the socket (from slave): RelayNotify -> update internal state; others -> return to caller
/// - Can send RelayState frames to the slave
@available(macOS 10.15.4, iOS 13.4, *)
public final class CborRelayMaster: @unchecked Sendable {
    /// Latest manifest from slave's RelayNotify
    private(set) public var manifest: Data
    /// Latest limits from slave's RelayNotify
    private(set) public var limits: CborLimits

    private init(manifest: Data, limits: CborLimits) {
        self.manifest = manifest
        self.limits = limits
    }

    /// Connect to a relay slave by reading the initial RelayNotify frame.
    ///
    /// The slave MUST send a RelayNotify as its first frame after connection.
    /// This extracts the manifest and limits from that frame.
    ///
    /// - Parameter socketReader: Reader connected to the slave relay socket
    /// - Returns: A connected RelayMaster with manifest and limits from the slave
    public static func connect(socketReader: CborFrameReader) throws -> CborRelayMaster {
        guard let frame = try socketReader.read() else {
            throw CborRelayError.socketClosed
        }

        guard frame.frameType == .relayNotify else {
            throw CborRelayError.protocolError("expected RelayNotify, got \(frame.frameType)")
        }

        guard let manifest = frame.relayNotifyManifest else {
            throw CborRelayError.protocolError("RelayNotify missing manifest")
        }

        guard let limits = frame.relayNotifyLimits else {
            throw CborRelayError.protocolError("RelayNotify missing limits")
        }

        return CborRelayMaster(manifest: manifest, limits: limits)
    }

    /// Send a RelayState frame to the slave with host system resource info.
    ///
    /// - Parameters:
    ///   - socketWriter: Writer connected to the slave relay socket
    ///   - resources: Opaque resource payload (CBOR or JSON encoded by the host)
    public static func sendState(
        socketWriter: CborFrameWriter,
        resources: Data
    ) throws {
        let frame = CborFrame.relayState(resources: resources)
        try socketWriter.write(frame)
    }

    /// Read the next non-relay frame from the socket.
    ///
    /// RelayNotify frames are intercepted: manifest and limits are updated.
    /// All other frames are returned to the caller.
    ///
    /// - Parameter socketReader: Reader connected to the slave relay socket
    /// - Returns: The next protocol frame, or nil on EOF
    public func readFrame(socketReader: CborFrameReader) throws -> CborFrame? {
        while true {
            guard let frame = try socketReader.read() else {
                return nil // Socket closed
            }

            if frame.frameType == .relayNotify {
                // Intercept: update manifest and limits
                if let m = frame.relayNotifyManifest {
                    self.manifest = m
                }
                if let l = frame.relayNotifyLimits {
                    self.limits = l
                }
                continue // Don't return relay frames to caller
            } else if frame.frameType == .relayState {
                // RelayState from slave? Protocol error - ignore
                continue
            }

            return frame
        }
    }
}
