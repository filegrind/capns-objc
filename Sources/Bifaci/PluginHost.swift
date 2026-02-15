//
//  PluginHost.swift
//  CapNsCbor
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

    /// Routing: req_id -> plugin index (for in-flight request frame correlation).
    private var requestRouting: [MessageId: Int] = [:]

    /// Request IDs initiated by plugins (peer invokes).
    /// Plugin's END is the end of the outgoing request body, NOT the final response.
    /// Routing survives until the relay sends back the response (END/ERR).
    private var peerRequests: Set<MessageId> = []

    /// Aggregate capabilities (serialized JSON manifest of all plugin caps).
    private var _capabilities: Data = Data()

    /// State lock — protects plugins, capTable, requestRouting, peerRequests, capabilities, closed.
    private let stateLock = NSLock()

    /// Outbound writer — writes frames to the relay (toward engine).
    private var outboundWriter: FrameWriter?
    private let outboundLock = NSLock()

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

        // Parse caps from manifest
        let caps = Self.extractCaps(from: manifest)

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
                if registeredUrn.accepts(requestUrn) { return idx }
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
    private func handleRelayFrame(_ frame: Frame) {
        switch frame.frameType {
        case .req:
            // Route by cap_urn to the appropriate plugin
            guard let capUrn = frame.cap else {
                sendToRelay(Frame.err(id: frame.id, code: "INVALID_REQUEST", message: "REQ missing cap URN"))
                return
            }

            stateLock.lock()
            guard let pluginIdx = findPluginForCapLocked(capUrn) else {
                stateLock.unlock()
                sendToRelay(Frame.err(id: frame.id, code: "NO_HANDLER", message: "No plugin handles cap: \(capUrn)"))
                return
            }
            let needsSpawn = !plugins[pluginIdx].running && !plugins[pluginIdx].helloFailed
            stateLock.unlock()

            // Spawn on demand if registered but not running
            if needsSpawn {
                do {
                    try spawnPlugin(at: pluginIdx)
                } catch {
                    sendToRelay(Frame.err(id: frame.id, code: "SPAWN_FAILED", message: "Failed to spawn plugin: \(error.localizedDescription)"))
                    return
                }
            }

            stateLock.lock()
            requestRouting[frame.id] = pluginIdx
            let plugin = plugins[pluginIdx]
            stateLock.unlock()

            if !plugin.writeFrame(frame) {
                // Plugin is dead — send ERR and clean up
                sendToRelay(Frame.err(id: frame.id, code: "PLUGIN_DIED", message: "Plugin exited while processing request"))
                stateLock.lock()
                requestRouting.removeValue(forKey: frame.id)
                stateLock.unlock()
            }

        case .streamStart, .chunk, .streamEnd, .end, .err:
            // Route by req_id to the mapped plugin
            stateLock.lock()
            guard let pluginIdx = requestRouting[frame.id] else {
                stateLock.unlock()
                // Already cleaned up (e.g., plugin died, death handler sent ERR)
                return
            }
            let plugin = plugins[pluginIdx]
            let isPeerResponse = peerRequests.contains(frame.id)
            stateLock.unlock()

            let isTerminal = frame.frameType == .end || frame.frameType == .err

            // If the plugin is dead, send ERR to engine and clean up routing
            if !plugin.writeFrame(frame) {
                sendToRelay(Frame.err(id: frame.id, code: "PLUGIN_DIED", message: "Plugin exited while processing request"))
                stateLock.lock()
                requestRouting.removeValue(forKey: frame.id)
                peerRequests.remove(frame.id)
                stateLock.unlock()
                return
            }

            // Only remove routing on terminal frames if this is a peer response
            // (engine responding to a plugin's peer invoke). For engine-initiated
            // requests, the relay END is just the end of the request body — the
            // plugin still needs to respond, so routing must survive.
            if isTerminal && isPeerResponse {
                stateLock.lock()
                requestRouting.removeValue(forKey: frame.id)
                peerRequests.remove(frame.id)
                stateLock.unlock()
            }

        case .hello, .heartbeat, .log:
            // These should never arrive from the engine through the relay
            fputs("[PluginHost] Protocol error: \(frame.frameType) from relay\n", stderr)

        case .relayNotify, .relayState:
            // Relay frames should be intercepted by the relay layer, never reach here
            fputs("[PluginHost] Protocol error: relay frame \(frame.frameType) reached host\n", stderr)
        }
    }

    // MARK: - Plugin Frame Handling (Plugin -> Engine)

    /// Handle a frame received from a plugin.
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
            // Plugin peer invoke — register routing and forward to relay
            stateLock.lock()
            requestRouting[frame.id] = pluginIdx
            peerRequests.insert(frame.id)
            stateLock.unlock()
            sendToRelay(frame)

        default:
            // Everything else: pass through to relay
            let isTerminal = frame.frameType == .end || frame.frameType == .err

            if isTerminal {
                stateLock.lock()
                if !peerRequests.contains(frame.id) {
                    // Engine-initiated request: plugin's END/ERR is the final response
                    if let idx = requestRouting[frame.id], idx == pluginIdx {
                        requestRouting.removeValue(forKey: frame.id)
                    }
                }
                // Peer-initiated: don't remove routing — relay's response
                // (END/ERR from engine) will clean up in handleRelayFrame
                stateLock.unlock()
            }

            sendToRelay(frame)
        }
    }

    // MARK: - Plugin Death Handling

    /// Handle a plugin death (reader thread detected EOF/error).
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

        // Send ERR for all requests routed to this plugin
        var requestsToClean: [MessageId] = []
        for (reqId, idx) in requestRouting {
            if idx == pluginIdx {
                requestsToClean.append(reqId)
            }
        }
        for reqId in requestsToClean {
            requestRouting.removeValue(forKey: reqId)
            peerRequests.remove(reqId)
        }

        // Remove caps for this plugin
        capTable.removeAll { $0.1 == pluginIdx }
        rebuildCapabilities()
        stateLock.unlock()

        // Send ERR frames outside the lock
        for reqId in requestsToClean {
            sendToRelay(Frame.err(id: reqId, code: "PLUGIN_DIED", message: "Plugin exited while processing request"))
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
    private func sendToRelay(_ frame: Frame) {
        outboundLock.lock()
        defer { outboundLock.unlock() }
        guard let w = outboundWriter else { return }
        try? w.write(frame)
    }

    // MARK: - Internal Helpers

    /// Rebuild aggregate capabilities from all running plugins.
    /// Must hold stateLock when calling.
    private func rebuildCapabilities() {
        var allCaps: [[String: Any]] = []
        for plugin in plugins where plugin.running {
            // Try to parse manifest as JSON to extract caps
            if !plugin.manifest.isEmpty,
               let json = try? JSONSerialization.jsonObject(with: plugin.manifest) as? [String: Any],
               let caps = json["caps"] as? [[String: Any]] {
                allCaps.append(contentsOf: caps)
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: allCaps) {
            _capabilities = data
        } else {
            _capabilities = "[]".data(using: .utf8) ?? Data()
        }
    }

    /// Extract cap URN strings from a manifest JSON blob.
    private static func extractCaps(from manifest: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let caps = json["caps"] as? [[String: Any]] else {
            return []
        }
        return caps.compactMap { $0["urn"] as? String }
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

        let caps = Self.extractCaps(from: handshakeResult.manifest ?? Data())

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
