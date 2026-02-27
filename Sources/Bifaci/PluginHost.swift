//
//  PluginHost.swift
//  Bifaci
//
//  Multi-plugin host runtime — manages N plugin binaries with frame routing.
//
//  The PluginHost sits between the relay connection (to the engine) and
//  individual plugin processes. It handles:
//
//  - HELLO handshake and limit negotiation per plugin
//  - Cap-based routing (REQ by cap_urn, continuation frames by req_id)
//  - Heartbeat health monitoring per plugin
//  - Plugin death detection and ERR propagation
//  - Aggregate capability advertisement
//
//  Architecture:
//
//    Relay (engine) <-> PluginHost <-> Plugin A (stdin/stdout)
//                                      <-> Plugin B (stdin/stdout)
//                                      <-> Plugin C (stdin/stdout)
//
//  Frame Routing:
//
//  Engine -> Plugin:
//  - REQ: route by cap_urn to the plugin that handles it
//  - STREAM_START/CHUNK/STREAM_END/END/ERR: route by req_id to the mapped plugin
//
//  Plugin -> Engine:
//  - HEARTBEAT: handled locally, never forwarded
//  - REQ (peer invoke): registered in routing table, forwarded to relay
//  - Everything else: forwarded to relay (pass-through)

import Foundation
@preconcurrency import SwiftCBOR
import CapNs

// MARK: - Error Types

/// Errors that can occur in the plugin host
public enum PluginHostError: Error, LocalizedError, Sendable {
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case pluginError(code: String, message: String)
    case unexpectedFrameType(FrameType)
    case protocolError(String)
    case processExited
    case closed
    case noHandler(String)
    case pluginDied(String)
    case peerInvokeNotSupported(String)
    // Protocol violation errors (per-request)
    case duplicateStreamId(String)
    case chunkAfterStreamEnd(String)
    case unknownStreamId(String)
    case chunkMissingStreamId
    case streamAfterRequestEnd

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        case .receiveFailed(let msg): return "Receive failed: \(msg)"
        case .pluginError(let code, let message): return "Plugin error [\(code)]: \(message)"
        case .unexpectedFrameType(let t): return "Unexpected frame type: \(t)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .processExited: return "Plugin process exited unexpectedly"
        case .closed: return "Host is closed"
        case .noHandler(let cap): return "No handler found for cap: \(cap)"
        case .pluginDied(let msg): return "Plugin died: \(msg)"
        case .duplicateStreamId(let streamId): return "Duplicate stream ID: \(streamId)"
        case .chunkAfterStreamEnd(let streamId): return "Chunk after stream end: \(streamId)"
        case .unknownStreamId(let streamId): return "Unknown stream ID: \(streamId)"
        case .chunkMissingStreamId: return "Chunk missing stream ID"
        case .streamAfterRequestEnd: return "Stream after request end"
        case .peerInvokeNotSupported(let cap): return "Peer invoke not supported for cap: \(cap)"
        }
    }
}

/// A response chunk from a plugin
public struct ResponseChunk: Sendable {
    public let payload: Data
    public let seq: UInt64
    public let offset: UInt64?
    public let len: UInt64?
    public let isEof: Bool

    public init(payload: Data, seq: UInt64, offset: UInt64?, len: UInt64?, isEof: Bool) {
        self.payload = payload
        self.seq = seq
        self.offset = offset
        self.len = len
        self.isEof = isEof
    }
}

/// Response from a plugin request (for convenience call() method)
public enum PluginResponse: Sendable {
    case single(Data)
    case streaming([ResponseChunk])

    public var finalPayload: Data? {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks): return chunks.last?.payload
        }
    }

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

// MARK: - Internal Types

/// Events from reader threads, delivered to the main run() loop.
private enum PluginEvent {
    case frame(pluginIdx: Int, frame: Frame)
    case death(pluginIdx: Int)
    case relayFrame(Frame)
    case relayClosed
}

/// Composite routing key: (XID, RID) — uniquely identifies a request flow from relay.
/// XID is assigned by RelaySwitch, RID is the request's MessageId.
private struct RxidKey: Hashable {
    let xid: MessageId
    let rid: MessageId
}

/// Interval between heartbeat probes (seconds).
private let HEARTBEAT_INTERVAL: TimeInterval = 30.0

/// Maximum time to wait for a heartbeat response (seconds).
private let HEARTBEAT_TIMEOUT: TimeInterval = 10.0

/// A managed plugin binary.
@available(macOS 10.15.4, iOS 13.4, *)
private class ManagedPlugin {
    let path: String
    var pid: pid_t?
    var stdinHandle: FileHandle?
    var stdoutHandle: FileHandle?
    var stderrHandle: FileHandle?
    var writer: FrameWriter?
    let writerLock = NSLock()
    var manifest: Data
    var limits: Limits
    var caps: [String]
    var knownCaps: [String]
    var running: Bool
    var helloFailed: Bool
    var readerThread: Thread?
    var pendingHeartbeats: [MessageId: Date]

    init(path: String, knownCaps: [String]) {
        self.path = path
        self.manifest = Data()
        self.limits = Limits()
        self.caps = []
        self.knownCaps = knownCaps
        self.running = false
        self.helloFailed = false
        self.pendingHeartbeats = [:]
    }

    static func attached(manifest: Data, limits: Limits, caps: [String]) -> ManagedPlugin {
        let plugin = ManagedPlugin(path: "", knownCaps: caps)
        plugin.manifest = manifest
        plugin.limits = limits
        plugin.caps = caps
        plugin.running = true
        return plugin
    }

    /// Kill the plugin process if running. Waits for exit.
    func killProcess() {
        guard let p = pid else { return }
        kill(p, SIGTERM)
        var status: Int32 = 0
        let result = waitpid(p, &status, WNOHANG)
        if result == 0 {
            // Still running after SIGTERM
            Thread.sleep(forTimeInterval: 0.5)
            let result2 = waitpid(p, &status, WNOHANG)
            if result2 == 0 {
                kill(p, SIGKILL)
                _ = waitpid(p, &status, 0)
            }
        }
        pid = nil
    }

    /// Write a frame to this plugin's stdin (thread-safe).
    /// Returns false if the plugin is dead or write fails.
    @discardableResult
    func writeFrame(_ frame: Frame) -> Bool {
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let w = writer else { return false }
        do {
            try w.write(frame)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - PluginHost

/// Multi-plugin host runtime managing N plugin processes.
///
/// Routes CBOR protocol frames between a relay connection (engine) and
/// individual plugin processes. Handles HELLO handshake, heartbeat health
/// monitoring, and capability advertisement.
///
/// Usage:
/// ```swift
/// let host = PluginHost()
/// try host.attachPlugin(stdinHandle: pluginStdin, stdoutHandle: pluginStdout)
/// try host.run(relayRead: relayReadHandle, relayWrite: relayWriteHandle) { Data() }
/// ```
@available(macOS 10.15.4, iOS 13.4, *)
public final class PluginHost: @unchecked Sendable {

    // MARK: - Properties

    /// Managed plugin binaries.
    private var plugins: [ManagedPlugin] = []

    /// Routing: cap_urn -> plugin index.
    private var capTable: [(String, Int)] = []

    /// List 1: OUTGOING_RIDS — tracks peer requests sent BY plugins (RID → plugin_idx).
    /// Used for death cleanup (ERR all pending peer requests when plugin dies).
    /// Cleaned up only on plugin death, never on terminal frames.
    private var outgoingRids: [MessageId: Int] = [:]

    /// List 2: INCOMING_RXIDS — tracks incoming requests FROM relay ((XID, RID) → plugin_idx).
    /// Routes continuation frames (STREAM_START/CHUNK/STREAM_END/END/ERR) to the correct plugin.
    /// NEVER cleaned up on terminal frames — intentionally leaked until plugin death.
    /// This avoids premature cleanup in self-loop peer request scenarios where the same RID
    /// appears in both outgoing and incoming maps.
    private var incomingRxids: [RxidKey: Int] = [:]

    /// Aggregate capabilities (serialized JSON manifest of all plugin caps).
    private var _capabilities: Data = Data()

    /// State lock — protects plugins, capTable, outgoingRids, incomingRxids, capabilities, closed.
    private let stateLock = NSLock()

    /// Outbound writer — writes frames to the relay (toward engine).
    private var outboundWriter: FrameWriter?
    private let outboundLock = NSLock()

    /// Max-seen seq per flow for plugin-originated frames.
    /// Used to set seq on host-generated ERR frames (max_seen + 1).
    /// Protected by stateLock (same as outgoingRids/incomingRxids).
    private var outgoingMaxSeq: [FlowKey: UInt64] = [:]

    /// Plugin events from reader threads.
    private var eventQueue: [PluginEvent] = []
    private let eventLock = NSLock()
    private let eventSemaphore = DispatchSemaphore(value: 0)

    /// Whether the host is closed.
    private var closed = false

    // MARK: - Initialization

    /// Create a new plugin host runtime.
    ///
    /// After creation, register plugins with `registerPlugin()` or
    /// attach pre-connected plugins with `attachPlugin()`, then call `run()`.
    public init() {}

    // MARK: - Plugin Management

    /// Register a plugin binary for on-demand spawning.
    ///
    /// The plugin is NOT spawned immediately. It will be spawned on demand when
    /// a REQ arrives for one of its known caps.
    ///
    /// - Parameters:
    ///   - path: Path to plugin binary
    ///   - knownCaps: Cap URNs this plugin is expected to handle
    public func registerPlugin(path: String, knownCaps: [String]) {
        stateLock.lock()
        let plugin = ManagedPlugin(path: path, knownCaps: knownCaps)
        let idx = plugins.count
        plugins.append(plugin)
        for cap in knownCaps {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()
    }

    /// Attach a pre-connected plugin (already running, ready for handshake).
    ///
    /// Performs HELLO handshake synchronously. Extracts manifest and caps.
    /// Starts a reader thread for this plugin.
    ///
    /// - Parameters:
    ///   - stdinHandle: FileHandle to write to the plugin's stdin
    ///   - stdoutHandle: FileHandle to read from the plugin's stdout
    /// - Returns: Plugin index
    /// - Throws: PluginHostError if handshake fails
    @discardableResult
    public func attachPlugin(stdinHandle: FileHandle, stdoutHandle: FileHandle) throws -> Int {
        let reader = FrameReader(handle: stdoutHandle)
        let writer = FrameWriter(handle: stdinHandle)

        // Perform HELLO handshake
        let ourLimits = Limits()
        let ourHello = Frame.hello(limits: ourLimits)
        try writer.write(ourHello)

        guard let theirHello = try reader.read() else {
            throw PluginHostError.handshakeFailed("Plugin closed connection before HELLO")
        }
        guard theirHello.frameType == .hello else {
            throw PluginHostError.handshakeFailed("Expected HELLO, got \(theirHello.frameType)")
        }
        guard let manifest = theirHello.helloManifest else {
            throw PluginHostError.handshakeFailed("Plugin HELLO missing required manifest")
        }

        // Protocol v2: All three limit fields are REQUIRED
        guard let theirMaxFrame = theirHello.helloMaxFrame else {
            throw PluginHostError.handshakeFailed("Protocol violation: HELLO missing max_frame")
        }
        guard let theirMaxChunk = theirHello.helloMaxChunk else {
            throw PluginHostError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
        }
        guard let theirMaxReorderBuffer = theirHello.helloMaxReorderBuffer else {
            throw PluginHostError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
        }

        let negotiatedLimits = Limits(
            maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
            maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
            maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
        )
        writer.setLimits(negotiatedLimits)
        reader.setLimits(negotiatedLimits)

        // Parse caps from manifest (validates CAP_IDENTITY presence)
        let caps = try Self.extractCaps(from: manifest)

        // Perform identity verification - send nonce, expect echo
        try Self.verifyPluginIdentity(reader: reader, writer: writer)

        // Create managed plugin
        let plugin = ManagedPlugin.attached(manifest: manifest, limits: negotiatedLimits, caps: caps)
        plugin.stdinHandle = stdinHandle
        plugin.stdoutHandle = stdoutHandle
        plugin.writer = writer

        stateLock.lock()
        let idx = plugins.count
        plugins.append(plugin)
        for cap in caps {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Start reader thread for this plugin
        startPluginReaderThread(pluginIdx: idx, reader: reader)

        return idx
    }

    /// Get the aggregate capabilities manifest (JSON-encoded list of all plugin caps).
    public var capabilities: Data {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _capabilities
    }

    /// Find which plugin handles a given cap URN.
    ///
    /// Uses exact string match first, then URN-level accepts() for semantic matching.
    ///
    /// - Parameter capUrn: The cap URN to look up
    /// - Returns: Plugin index, or nil if no plugin handles this cap
    public func findPluginForCap(_ capUrn: String) -> Int? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return findPluginForCapLocked(capUrn)
    }

    /// Internal: find plugin for cap (must hold stateLock).
    private func findPluginForCapLocked(_ capUrn: String) -> Int? {
        // Exact string match first (fast path)
        for (registeredCap, idx) in capTable {
            if registeredCap == capUrn { return idx }
        }

        // URN-level semantic matching (slow path)
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else { return nil }
        for (registeredCap, idx) in capTable {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                // Request is pattern, registered cap is instance
                if requestUrn.accepts(registeredUrn) { return idx }
            }
        }

        return nil
    }

    // MARK: - Main Run Loop

    /// Main run loop. Reads frames from the relay, routes to plugins.
    /// Plugin reader threads forward plugin frames to the relay.
    ///
    /// Blocks until the relay closes or a fatal error occurs.
    ///
    /// - Parameters:
    ///   - relayRead: FileHandle to read frames from (relay/engine side)
    ///   - relayWrite: FileHandle to write frames to (relay/engine side)
    ///   - resourceFn: Callback to get current system resource state
    /// - Throws: PluginHostError on fatal errors
    public func run(
        relayRead: FileHandle,
        relayWrite: FileHandle,
        resourceFn: @escaping () -> Data
    ) throws {
        outboundLock.lock()
        outboundWriter = FrameWriter(handle: relayWrite)
        outboundLock.unlock()

        // Send initial RelayNotify with capabilities from any already-attached plugins.
        // Plugins attached before run() was called won't have sent their RelayNotify yet.
        stateLock.lock()
        rebuildCapabilities()
        stateLock.unlock()

        // Start relay reader thread — feeds into the same event queue as plugin readers
        let relayReader = FrameReader(handle: relayRead)
        let relayThread = Thread { [weak self] in
            while true {
                do {
                    guard let frame = try relayReader.read() else {
                        self?.pushEvent(.relayClosed)
                        break
                    }
                    self?.pushEvent(.relayFrame(frame))
                } catch {
                    self?.pushEvent(.relayClosed)
                    break
                }
            }
        }
        relayThread.name = "PluginHost.relay"
        relayThread.start()

        // Main loop: wait for events from any source (relay or plugins)
        while true {
            eventSemaphore.wait()

            eventLock.lock()
            guard !eventQueue.isEmpty else {
                eventLock.unlock()
                continue
            }
            let event = eventQueue.removeFirst()
            eventLock.unlock()

            switch event {
            case .relayFrame(let frame):
                handleRelayFrame(frame)
            case .relayClosed:
                // Clean shutdown
                stateLock.lock()
                closed = true
                stateLock.unlock()
                return
            case .frame(let pluginIdx, let frame):
                handlePluginFrame(pluginIdx: pluginIdx, frame: frame)
            case .death(let pluginIdx):
                handlePluginDeath(pluginIdx: pluginIdx)
            }
        }
    }

    // MARK: - Relay Frame Handling (Engine -> Plugin)

    /// Handle a frame received from the relay (engine side).
    ///
    /// All relay frames MUST have XID (assigned by RelaySwitch).
    /// Routes incoming REQs to plugins by cap URN, continuation frames by (XID, RID).
    /// NEVER cleans up incomingRxids on terminal frames — intentionally leaked until plugin death.
    private func handleRelayFrame(_ frame: Frame) {
        switch frame.frameType {
        case .req:
            // REQ from relay MUST have XID
            guard let xid = frame.routingId else {
                sendToRelay(Frame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "REQ from relay missing XID"))
                return
            }

            guard let capUrn = frame.cap else {
                var err = Frame.err(id: frame.id, code: "INVALID_REQUEST", message: "REQ missing cap URN")
                err.routingId = xid
                sendToRelay(err)
                return
            }

            stateLock.lock()
            guard let pluginIdx = findPluginForCapLocked(capUrn) else {
                stateLock.unlock()
                var err = Frame.err(id: frame.id, code: "NO_HANDLER", message: "No plugin handles cap: \(capUrn)")
                err.routingId = xid
                sendToRelay(err)
                return
            }
            let needsSpawn = !plugins[pluginIdx].running && !plugins[pluginIdx].helloFailed
            stateLock.unlock()

            // Spawn on demand if registered but not running
            if needsSpawn {
                do {
                    try spawnPlugin(at: pluginIdx)
                } catch {
                    var err = Frame.err(id: frame.id, code: "SPAWN_FAILED", message: "Failed to spawn plugin: \(error.localizedDescription)")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
            }

            // Record in INCOMING_RXIDS: (XID, RID) → plugin_idx
            let key = RxidKey(xid: xid, rid: frame.id)
            stateLock.lock()
            incomingRxids[key] = pluginIdx
            let plugin = plugins[pluginIdx]
            stateLock.unlock()

            if !plugin.writeFrame(frame) {
                // Plugin is dead — send ERR with XID and clean up
                var err = Frame.err(id: frame.id, code: "PLUGIN_DIED", message: "Plugin exited while processing request")
                err.routingId = xid
                sendToRelay(err)
                stateLock.lock()
                incomingRxids.removeValue(forKey: key)
                stateLock.unlock()
            }

        case .streamStart, .chunk, .streamEnd, .end, .err:
            // Continuation from relay MUST have XID
            guard let xid = frame.routingId else {
                fputs("[PluginHost] Protocol error: continuation from relay missing XID\n", stderr)
                return
            }

            let key = RxidKey(xid: xid, rid: frame.id)

            // Route by (XID, RID) to the mapped plugin
            stateLock.lock()
            var pluginIdx = incomingRxids[key]
            if pluginIdx == nil {
                // Not an incoming engine request — check if it's a peer response.
                // outgoingRids[RID] tracks which plugin made a peer request with this RID.
                pluginIdx = outgoingRids[frame.id]
            }
            guard let resolvedIdx = pluginIdx else {
                stateLock.unlock()
                // Already cleaned up (e.g., plugin died, death handler sent ERR)
                return
            }
            let plugin = plugins[resolvedIdx]
            stateLock.unlock()

            // If the plugin is dead, send ERR to engine with XID and clean up
            if !plugin.writeFrame(frame) {
                let flowKey = FlowKey(rid: frame.id, xid: xid)
                stateLock.lock()
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                outgoingRids.removeValue(forKey: frame.id)
                incomingRxids.removeValue(forKey: key)
                stateLock.unlock()
                var err = Frame.err(id: frame.id, code: "PLUGIN_DIED", message: "Plugin exited while processing request")
                err.routingId = xid
                err.seq = nextSeq
                sendToRelay(err)
                return
            }

            // NOTE: Do NOT cleanup incomingRxids here!
            // Frames arrive asynchronously — END can arrive before StreamStart/Chunk.
            // We can't know when "all frames for (XID, RID) have arrived" without full stream tracking.
            // Accept the leak: entries cleaned up on plugin death.

        case .log:
            // LOG frames from peer responses — route back to the plugin that
            // made the peer request. Identified by outgoingRids[RID].
            stateLock.lock()
            let pluginIdx = outgoingRids[frame.id]
            stateLock.unlock()

            if let idx = pluginIdx {
                let plugin = plugins[idx]
                let _ = plugin.writeFrame(frame)
            }
            // If not a peer response LOG, ignore silently (e.g., stale routing)

        case .hello, .heartbeat:
            // These should never arrive from the engine through the relay
            fputs("[PluginHost] Protocol error: \(frame.frameType) from relay\n", stderr)

        case .relayNotify, .relayState:
            // Relay frames should be intercepted by the relay layer, never reach here
            fputs("[PluginHost] Protocol error: relay frame \(frame.frameType) reached host\n", stderr)
        }
    }

    // MARK: - Plugin Frame Handling (Plugin -> Engine)

    /// Handle a frame received from a plugin.
    ///
    /// REQ frames register in outgoingRids (peer invoke tracking).
    /// All frames track max-seen seq per FlowKey for host-generated ERR frames.
    /// All other frames are forwarded to relay as-is — no routing decisions needed
    /// (there's only one relay destination).
    private func handlePluginFrame(pluginIdx: Int, frame: Frame) {
        switch frame.frameType {
        case .hello:
            // HELLO should be consumed during handshake, never during run
            fputs("[PluginHost] Protocol error: HELLO from plugin \(pluginIdx) during run\n", stderr)

        case .heartbeat:
            // Handle heartbeat locally, never forward
            stateLock.lock()
            let plugin = plugins[pluginIdx]
            let wasOurs = plugin.pendingHeartbeats.removeValue(forKey: frame.id) != nil
            stateLock.unlock()

            if !wasOurs {
                // Plugin-initiated heartbeat — respond
                plugin.writeFrame(Frame.heartbeat(id: frame.id))
            }

        case .relayNotify, .relayState:
            // Plugins must never send relay frames
            fputs("[PluginHost] Protocol error: relay frame \(frame.frameType) from plugin \(pluginIdx)\n", stderr)

        case .req:
            // Plugin peer invoke — record in OUTGOING_RIDS and track max-seen seq.
            // Plugins MUST NOT send XID (that's a relay-level concept).
            stateLock.lock()
            outgoingRids[frame.id] = pluginIdx
            let flowKey = FlowKey.fromFrame(frame)
            outgoingMaxSeq[flowKey] = frame.seq
            stateLock.unlock()
            sendToRelay(frame)

        default:
            // Everything else: forward as-is to relay.
            // Track max-seen seq for flow, clean up on terminal.
            if frame.isFlowFrame() {
                let flowKey = FlowKey.fromFrame(frame)
                stateLock.lock()
                let isTerminal = frame.frameType == .end || frame.frameType == .err
                if isTerminal {
                    outgoingMaxSeq.removeValue(forKey: flowKey)
                } else {
                    outgoingMaxSeq[flowKey] = frame.seq
                }
                stateLock.unlock()
            }
            sendToRelay(frame)
        }
    }

    // MARK: - Plugin Death Handling

    /// Handle a plugin death (reader thread detected EOF/error).
    ///
    /// Sends ERR for pending peer requests (outgoingRids) and cleans up
    /// incoming routing entries (incomingRxids).
    /// Host-generated ERR uses max_seen + 1 seq for the flow.
    private func handlePluginDeath(pluginIdx: Int) {
        stateLock.lock()
        let plugin = plugins[pluginIdx]
        plugin.running = false
        plugin.writer = nil

        // Close stdin to ensure plugin process exits
        if let stdinHandle = plugin.stdinHandle {
            try? stdinHandle.close()
            plugin.stdinHandle = nil
        }

        // Send ERR for pending PEER requests (outgoingRids only).
        // These are requests the plugin initiated — the relay is waiting for
        // the plugin to complete its request body or receive its response.
        // Collect (rid, nextSeq) inside the lock.
        var failedOutgoing: [(rid: MessageId, nextSeq: UInt64)] = []
        for (rid, idx) in outgoingRids {
            if idx == pluginIdx {
                // Peer REQs have no XID (plugins never send XID)
                let flowKey = FlowKey(rid: rid, xid: nil)
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                failedOutgoing.append((rid: rid, nextSeq: nextSeq))
            }
        }
        for entry in failedOutgoing {
            outgoingRids.removeValue(forKey: entry.rid)
        }

        // Clean up incomingRxids entries for this plugin (leaked routing entries).
        // Also collect XID info so we can send ERR with correct XID for incoming requests.
        var failedIncoming: [(key: RxidKey, xid: MessageId, rid: MessageId, nextSeq: UInt64)] = []
        for (key, idx) in incomingRxids {
            if idx == pluginIdx {
                let flowKey = FlowKey(rid: key.rid, xid: key.xid)
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                failedIncoming.append((key: key, xid: key.xid, rid: key.rid, nextSeq: nextSeq))
            }
        }
        for entry in failedIncoming {
            incomingRxids.removeValue(forKey: entry.key)
        }

        // Replace actual caps with knownCaps for on-demand respawn routing.
        // If helloFailed, remove entirely (permanently broken).
        capTable.removeAll { $0.1 == pluginIdx }
        if !plugin.helloFailed {
            for cap in plugin.knownCaps {
                capTable.append((cap, pluginIdx))
            }
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Send ERR frames outside the lock — with correct seq from max-seen tracking
        for entry in failedOutgoing {
            var err = Frame.err(id: entry.rid, code: "PLUGIN_DIED", message: "Plugin exited while processing request")
            err.seq = entry.nextSeq
            sendToRelay(err)
        }
        for entry in failedIncoming {
            var err = Frame.err(id: entry.rid, code: "PLUGIN_DIED", message: "Plugin exited while processing request")
            err.routingId = entry.xid
            err.seq = entry.nextSeq
            sendToRelay(err)
        }
    }

    // MARK: - Plugin Reader Thread

    /// Start a background reader thread for a plugin.
    private func startPluginReaderThread(pluginIdx: Int, reader: FrameReader) {
        let thread = Thread { [weak self] in
            while true {
                do {
                    guard let frame = try reader.read() else {
                        // EOF — plugin closed stdout
                        self?.pushEvent(.death(pluginIdx: pluginIdx))
                        break
                    }
                    self?.pushEvent(.frame(pluginIdx: pluginIdx, frame: frame))
                } catch {
                    // Read error — treat as death
                    self?.pushEvent(.death(pluginIdx: pluginIdx))
                    break
                }
            }
        }
        thread.name = "PluginHost.plugin[\(pluginIdx)]"

        stateLock.lock()
        plugins[pluginIdx].readerThread = thread
        stateLock.unlock()

        thread.start()
    }

    // MARK: - Event Queue

    /// Push an event from a plugin reader thread.
    private func pushEvent(_ event: PluginEvent) {
        eventLock.lock()
        eventQueue.append(event)
        eventLock.unlock()
        eventSemaphore.signal()
    }

    /// Drain and process all pending events (used internally).
    private func processEvents() {
        eventLock.lock()
        let events = eventQueue
        eventQueue.removeAll()
        eventLock.unlock()

        for event in events {
            switch event {
            case .frame(let pluginIdx, let frame):
                handlePluginFrame(pluginIdx: pluginIdx, frame: frame)
            case .death(let pluginIdx):
                handlePluginDeath(pluginIdx: pluginIdx)
            case .relayFrame(let frame):
                handleRelayFrame(frame)
            case .relayClosed:
                break // Handled in run() loop
            }
        }
    }

    // MARK: - Outbound Writing

    /// Write a frame to the relay (toward engine). Thread-safe.
    /// Frames arrive with seq already assigned by PluginRuntime — no modification needed.
    private func sendToRelay(_ frame: Frame) {
        outboundLock.lock()
        defer { outboundLock.unlock() }
        guard let w = outboundWriter else { return }
        try? w.write(frame)
    }

    // MARK: - Internal Helpers

    /// Rebuild aggregate capabilities from all known/discovered plugins.
    /// Must hold stateLock when calling.
    /// Creates a JSON array of URN strings (not objects).
    ///
    /// Includes caps from ALL registered plugins that haven't permanently failed HELLO.
    /// Running plugins use their actual manifest caps; non-running plugins use knownCaps.
    /// This ensures the relay always advertises all caps that CAN be handled, regardless
    /// of whether the plugin process is currently alive (on-demand spawn handles restarts).
    ///
    /// If running in relay mode (outboundWriter is set), sends a RelayNotify frame
    /// to the relay interface with the updated capabilities.
    private func rebuildCapabilities() {
        // CAP_IDENTITY is always present — structural, not plugin-dependent
        var capUrns: [String] = [CSCapIdentity]

        for plugin in plugins where !plugin.helloFailed {
            if plugin.running {
                // Running: use actual caps from manifest (verified via HELLO handshake)
                if !plugin.manifest.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: plugin.manifest) as? [String: Any],
                   let caps = json["caps"] as? [[String: Any]] {
                    for cap in caps {
                        if let urn = cap["urn"] as? String, urn != CSCapIdentity {
                            capUrns.append(urn)
                        }
                    }
                }
            } else {
                // Not running: use knownCaps (from discovery, available for on-demand spawn)
                for cap in plugin.knownCaps where cap != CSCapIdentity {
                    capUrns.append(cap)
                }
            }
        }

        // Serialize as JSON array of strings (not objects)
        let capsData: Data
        if let data = try? JSONSerialization.data(withJSONObject: capUrns) {
            capsData = data
            _capabilities = data
        } else {
            capsData = "[]".data(using: .utf8) ?? Data()
            _capabilities = capsData
        }

        // Send RelayNotify to relay if in relay mode
        // RelayNotify contains the capability URN array (not a full manifest with version/caps keys)
        outboundLock.lock()
        if let writer = outboundWriter {
            let notify = Frame.relayNotify(manifest: capsData, limits: Limits())
            try? writer.write(notify) // Ignore error if relay closed
        }
        outboundLock.unlock()
    }

    /// Extract cap URN strings from a manifest JSON blob.
    /// Validates that CAP_IDENTITY is present (mandatory for all plugins).
    private static func extractCaps(from manifest: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let caps = json["caps"] as? [[String: Any]] else {
            throw PluginHostError.handshakeFailed("Invalid manifest JSON or missing caps array")
        }

        let capUrns = caps.compactMap { $0["urn"] as? String }

        // Verify CAP_IDENTITY is declared — mandatory for every plugin
        guard let identityUrn = try? CSCapUrn.fromString(CSCapIdentity) else {
            fatalError("BUG: CAP_IDENTITY constant '\(CSCapIdentity)' is invalid")
        }

        let hasIdentity = capUrns.contains { capUrnStr in
            guard let capUrn = try? CSCapUrn.fromString(capUrnStr) else { return false }
            return identityUrn.conforms(to: capUrn)
        }

        guard hasIdentity else {
            throw PluginHostError.handshakeFailed(
                "Plugin manifest missing required CAP_IDENTITY (\(CSCapIdentity))"
            )
        }

        return capUrns
    }

    /// Generate identity verification nonce — CBOR-encoded "bifaci" text.
    private static func identityNonce() -> Data {
        return Data(CBOR.utf8String("bifaci").encode())
    }

    /// Verify plugin identity by sending nonce and expecting echo response.
    ///
    /// This proves the transport works end-to-end and the plugin correctly
    /// implements the identity capability (echo behavior).
    ///
    /// - Parameters:
    ///   - reader: FrameReader for plugin stdout
    ///   - writer: FrameWriter for plugin stdin
    /// - Throws: PluginHostError if verification fails
    private static func verifyPluginIdentity(reader: FrameReader, writer: FrameWriter) throws {
        let nonce = identityNonce()
        let reqId = MessageId.newUUID()
        let streamId = "identity-verify"

        // Send REQ with CAP_IDENTITY
        let req = Frame.req(id: reqId, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor")
        try writer.write(req)

        // Send STREAM_START
        let ss = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: "media:")
        try writer.write(ss)

        // Send CHUNK with nonce
        let checksum = Frame.computeChecksum(nonce)
        let chunk = Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
        try writer.write(chunk)

        // Send STREAM_END
        let se = Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1)
        try writer.write(se)

        // Send END
        let end = Frame.end(id: reqId)
        try writer.write(end)

        // Read response - expect STREAM_START → CHUNK(s) → STREAM_END → END
        var accumulated = Data()
        while true {
            guard let frame = try reader.read() else {
                throw PluginHostError.handshakeFailed("Plugin closed connection during identity verification")
            }

            switch frame.frameType {
            case .streamStart:
                break // Expected, no action needed
            case .chunk:
                if let payload = frame.payload {
                    accumulated.append(payload)
                }
            case .streamEnd:
                break // Expected, no action needed
            case .end:
                // Verify nonce matches
                if accumulated != nonce {
                    throw PluginHostError.handshakeFailed(
                        "Identity verification payload mismatch (expected \(nonce.count) bytes, got \(accumulated.count))")
                }
                return // Success
            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let msg = frame.errorMessage ?? "no message"
                throw PluginHostError.handshakeFailed("Identity verification failed: [\(code)] \(msg)")
            default:
                throw PluginHostError.handshakeFailed("Identity verification: unexpected frame type \(frame.frameType)")
            }
        }
    }

    // MARK: - Spawn On Demand

    /// Spawn a registered plugin binary on demand.
    ///
    /// Performs posix_spawn + HELLO handshake + starts reader thread.
    /// Does NOT hold stateLock during blocking operations (handshake).
    ///
    /// - Parameter idx: Plugin index in the plugins array
    /// - Throws: PluginHostError if spawn or handshake fails
    private func spawnPlugin(at idx: Int) throws {
        // Read plugin info without holding lock during blocking ops
        stateLock.lock()
        let path = plugins[idx].path
        let alreadyRunning = plugins[idx].running
        let alreadyFailed = plugins[idx].helloFailed
        stateLock.unlock()

        guard !path.isEmpty else {
            throw PluginHostError.handshakeFailed("No binary path for plugin \(idx)")
        }
        guard !alreadyRunning else { return }
        guard !alreadyFailed else {
            throw PluginHostError.handshakeFailed("Plugin previously failed HELLO — permanently removed")
        }

        // Setup pipes
        let inputPipe = Pipe()   // host writes → plugin reads (stdin)
        let outputPipe = Pipe()  // plugin writes → host reads (stdout)
        let errorPipe = Pipe()   // plugin writes → host reads (stderr)

        var pid: pid_t = 0

        // Build argv (null-terminated for posix_spawn)
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        defer { argv.compactMap { $0 }.forEach { free($0) } }

        // File actions for pipe redirection
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_adddup2(&fileActions, inputPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errorPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        // Close all pipe descriptors in child
        posix_spawn_file_actions_addclose(&fileActions, inputPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, inputPipe.fileHandleForWriting.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe.fileHandleForWriting.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, errorPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, errorPipe.fileHandleForWriting.fileDescriptor)

        // Spawn
        let spawnResult = posix_spawn(&pid, path, &fileActions, nil, argv, nil)
        guard spawnResult == 0 else {
            let desc = String(cString: strerror(spawnResult))
            throw PluginHostError.handshakeFailed("posix_spawn failed for \(path): \(desc)")
        }

        // Close child's ends in parent
        inputPipe.fileHandleForReading.closeFile()
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        let stdinHandle = inputPipe.fileHandleForWriting
        let stdoutHandle = outputPipe.fileHandleForReading
        let stderrHandle = errorPipe.fileHandleForReading

        // HELLO handshake (blocking — stateLock NOT held)
        let reader = FrameReader(handle: stdoutHandle)
        let writer = FrameWriter(handle: stdinHandle)

        let handshakeResult: HandshakeResult
        do {
            handshakeResult = try performHandshakeWithManifest(reader: reader, writer: writer)
        } catch {
            // HELLO failure → permanent removal (binary is broken)
            kill(pid, SIGKILL)
            _ = waitpid(pid, nil, 0)
            stdinHandle.closeFile()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()

            stateLock.lock()
            plugins[idx].helloFailed = true
            capTable.removeAll { $0.1 == idx }
            rebuildCapabilities()
            stateLock.unlock()

            throw PluginHostError.handshakeFailed("HELLO failed for \(path): \(error.localizedDescription)")
        }

        let caps = try Self.extractCaps(from: handshakeResult.manifest ?? Data())

        // Update plugin state under lock
        stateLock.lock()
        let plugin = plugins[idx]
        plugin.pid = pid
        plugin.stdinHandle = stdinHandle
        plugin.stdoutHandle = stdoutHandle
        plugin.stderrHandle = stderrHandle
        plugin.writer = writer
        plugin.manifest = handshakeResult.manifest ?? Data()
        plugin.limits = handshakeResult.limits
        plugin.caps = caps
        plugin.running = true

        // Update capTable with actual caps from manifest
        capTable.removeAll { $0.1 == idx }
        for cap in caps {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Start reader thread
        startPluginReaderThread(pluginIdx: idx, reader: reader)
    }

    // MARK: - Lifecycle

    /// Close the host, killing all managed plugin processes.
    ///
    /// After close(), the run() loop will exit. Any pending requests get ERR frames.
    public func close() {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        closed = true

        // Kill all running plugins
        for plugin in plugins {
            plugin.writerLock.lock()
            plugin.writer = nil
            plugin.writerLock.unlock()

            if let stdin = plugin.stdinHandle {
                try? stdin.close()
                plugin.stdinHandle = nil
            }
            if let stderr = plugin.stderrHandle {
                try? stderr.close()
                plugin.stderrHandle = nil
            }
            plugin.killProcess()
            plugin.running = false
        }
        stateLock.unlock()

        // Signal the event loop to wake up and exit
        pushEvent(.relayClosed)
    }
}
