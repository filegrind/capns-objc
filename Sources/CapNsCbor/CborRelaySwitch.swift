/// CborRelaySwitch — Cap-aware routing multiplexer for multiple RelayMasters.
///
/// The RelaySwitch sits above multiple RelayMasters and provides deterministic
/// request routing based on cap URN matching. It plays the same role for RelayMasters
/// that CborPluginHost plays for plugins.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────┐
/// │   Test Engine / API Client  │
/// └──────────────┬──────────────┘
///                │
/// ┌──────────────▼──────────────┐
/// │       CborRelaySwitch        │
/// │  • Aggregates capabilities   │
/// │  • Routes REQ by cap URN     │
/// │  • Routes frames by req_id   │
/// │  • Tracks peer requests      │
/// └─┬───┬───┬───┬───────────────┘
///   │   │   │   │
///   ▼   ▼   ▼   ▼
///  RM  RM  RM  RM   (Relay Masters - via socket pairs)
/// ```
///
/// No fallbacks. No heuristics. No special cases. Just deterministic frame routing
/// based on URN matching and request ID tracking.

import Foundation
@preconcurrency import SwiftCBOR
import CapNs

// MARK: - Helper Extensions

extension CborMessageId {
    /// Convert message ID to string for use as dictionary key
    func toString() -> String {
        switch self {
        case .uuid(let data):
            return data.base64EncodedString()
        case .uint(let value):
            return String(value)
        }
    }
}

// MARK: - Error Types

/// Errors specific to RelaySwitch operations
public enum CborRelaySwitchError: Error, LocalizedError, Sendable {
    case noHandler(String)
    case unknownRequest(String)
    case protocolError(String)
    case allMastersUnhealthy

    public var errorDescription: String? {
        switch self {
        case .noHandler(let cap): return "No handler for cap: \(cap)"
        case .unknownRequest(let reqId): return "Unknown request ID: \(reqId)"
        case .protocolError(let msg): return "Protocol violation: \(msg)"
        case .allMastersUnhealthy: return "All relay masters are unhealthy"
        }
    }
}

// MARK: - Data Structures

/// Socket pair for master connection
public struct CborSocketPair: Sendable {
    public let read: FileHandle
    public let write: FileHandle

    public init(read: FileHandle, write: FileHandle) {
        self.read = read
        self.write = write
    }
}

/// Routing entry for request tracking
private struct RoutingEntry: Sendable {
    let sourceMasterIdx: Int  // ENGINE_SOURCE for engine-initiated
    let destinationMasterIdx: Int
}

/// Frame received from a master
private struct MasterFrame: Sendable {
    let masterIdx: Int
    let frame: CborFrame?
    let error: Error?
}

/// Sentinel value for engine-initiated requests
private let ENGINE_SOURCE = Int.max

// MARK: - Master Connection

/// Connection to a single RelayMaster
@available(macOS 10.15.4, iOS 13.4, *)
private final class MasterConnection: @unchecked Sendable {
    let socketWriter: CborFrameWriter
    var manifest: Data
    var limits: CborLimits
    var caps: [String]
    var healthy: Bool
    let readerQueue: DispatchQueue

    init(socketWriter: CborFrameWriter, manifest: Data, limits: CborLimits, caps: [String], healthy: Bool, readerQueue: DispatchQueue) {
        self.socketWriter = socketWriter
        self.manifest = manifest
        self.limits = limits
        self.caps = caps
        self.healthy = healthy
        self.readerQueue = readerQueue
    }
}

// MARK: - Relay Switch

/// Cap-aware routing multiplexer for multiple RelayMasters.
///
/// Routes requests based on cap URN matching and tracks bidirectional request/response flows.
@available(macOS 10.15.4, iOS 13.4, *)
public final class CborRelaySwitch: @unchecked Sendable {
    private var masters: [MasterConnection] = []
    private var capTable: [(capUrn: String, masterIdx: Int)] = []
    private var requestRouting: [String: RoutingEntry] = [:]
    private var peerRequests: Set<String> = Set()
    private var aggregateCapabilities: Data = Data()
    private var negotiatedLimits: CborLimits = CborLimits()
    private let lock = NSLock()
    private let frameQueue = DispatchQueue(label: "com.capns.relayswitch.frames", qos: .userInitiated)
    private var frameChannel: [(masterIdx: Int, frame: CborFrame?, error: Error?)] = []
    private let frameSemaphore = DispatchSemaphore(value: 0)

    /// Create a RelaySwitch from socket pairs.
    ///
    /// - Parameter sockets: Array of socket pairs (one per master)
    /// - Throws: CborRelaySwitchError if construction fails
    public init(sockets: [CborSocketPair]) throws {
        guard !sockets.isEmpty else {
            throw CborRelaySwitchError.protocolError("RelaySwitch requires at least one master")
        }

        // Connect to all masters
        for (masterIdx, sockPair) in sockets.enumerated() {
            var reader = CborFrameReader(handle: sockPair.read)
            let writer = CborFrameWriter(handle: sockPair.write)

            // Perform handshake (read initial RelayNotify)
            guard let frame = try reader.read() else {
                throw CborRelaySwitchError.protocolError("Expected RelayNotify during handshake")
            }

            guard frame.frameType == .relayNotify else {
                throw CborRelaySwitchError.protocolError("Expected RelayNotify during handshake")
            }

            guard let manifest = frame.relayNotifyManifest,
                  let limits = frame.relayNotifyLimits else {
                throw CborRelaySwitchError.protocolError("RelayNotify missing manifest or limits")
            }

            let caps = try Self.parseCapabilitiesFromManifest(manifest)

            // Spawn reader thread for this master
            let readerQueue = DispatchQueue(label: "com.capns.relayswitch.reader.\(masterIdx)", qos: .userInitiated)
            readerQueue.async { [weak self] in
                self?.readerLoop(masterIdx: masterIdx, reader: reader)
            }

            let masterConn = MasterConnection(
                socketWriter: writer,
                manifest: manifest,
                limits: limits,
                caps: caps,
                healthy: true,
                readerQueue: readerQueue
            )
            masters.append(masterConn)
        }

        // Build initial routing tables
        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
    }

    // MARK: - Reader Loop

    private func readerLoop(masterIdx: Int, reader: CborFrameReader) {
        var mutableReader = reader  // CborFrameReader.read() mutates state
        while true {
            do {
                guard let frame = try mutableReader.read() else {
                    // EOF
                    enqueueFrame(masterIdx: masterIdx, frame: nil, error: nil)
                    return
                }

                // Handle RelayNotify here (intercept before sending to queue)
                if frame.frameType == .relayNotify {
                    lock.lock()
                    if let manifest = frame.relayNotifyManifest,
                       let limits = frame.relayNotifyLimits {
                        let caps = try Self.parseCapabilitiesFromManifest(manifest)
                        masters[masterIdx].manifest = manifest
                        masters[masterIdx].limits = limits
                        masters[masterIdx].caps = caps
                        rebuildCapTable()
                        rebuildCapabilities()
                        rebuildLimits()
                    }
                    lock.unlock()
                    continue
                }

                enqueueFrame(masterIdx: masterIdx, frame: frame, error: nil)
            } catch {
                enqueueFrame(masterIdx: masterIdx, frame: nil, error: error)
                return
            }
        }
    }

    private func enqueueFrame(masterIdx: Int, frame: CborFrame?, error: Error?) {
        lock.lock()
        frameChannel.append((masterIdx: masterIdx, frame: frame, error: error))
        lock.unlock()
        frameSemaphore.signal()
    }

    // MARK: - Public API

    /// Get aggregate capabilities (union of all masters)
    public func capabilities() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return aggregateCapabilities
    }

    /// Get negotiated limits (minimum across all masters)
    public func limits() -> CborLimits {
        lock.lock()
        defer { lock.unlock() }
        return negotiatedLimits
    }

    /// Send a frame to the appropriate master (engine → plugin direction)
    ///
    /// Routes REQ by cap URN. Routes continuation frames by request ID.
    ///
    /// - Parameter frame: Frame to send
    /// - Throws: CborRelaySwitchError if routing fails
    public func sendToMaster(_ frame: CborFrame) throws {
        lock.lock()
        defer { lock.unlock() }

        switch frame.frameType {
        case .req:
            // Find master for this cap
            guard let cap = frame.cap, let destIdx = findMasterForCap(cap) else {
                throw CborRelaySwitchError.noHandler(frame.cap ?? "nil")
            }

            // Register routing (source = engine)
            requestRouting[frame.id.toString()] = RoutingEntry(
                sourceMasterIdx: ENGINE_SOURCE,
                destinationMasterIdx: destIdx
            )

            try masters[destIdx].socketWriter.write(frame)

        case .streamStart, .chunk, .streamEnd, .end, .err:
            // Continuation frames route by request ID
            guard let entry = requestRouting[frame.id.toString()] else {
                throw CborRelaySwitchError.unknownRequest(frame.id.toString())
            }

            let destIdx = entry.destinationMasterIdx
            try masters[destIdx].socketWriter.write(frame)

            // Cleanup on terminal frames for peer responses
            let isTerminal = frame.frameType == .end || frame.frameType == .err
            if isTerminal && peerRequests.contains(frame.id.toString()) {
                requestRouting.removeValue(forKey: frame.id.toString())
                peerRequests.remove(frame.id.toString())
            }

        default:
            // Other frame types pass through to first master (or error)
            if !masters.isEmpty {
                try masters[0].socketWriter.write(frame)
            }
        }
    }

    /// Read the next frame from any master (plugin → engine direction).
    ///
    /// Blocks until a frame is available. Returns nil when all masters have closed.
    /// Peer requests (plugin → plugin) are handled internally and not returned.
    ///
    /// - Returns: Frame if available, nil if all masters closed
    /// - Throws: CborRelaySwitchError on errors
    public func readFromMasters() throws -> CborFrame? {
        while true {
            // Block on semaphore - reader threads signal when frames arrive
            frameSemaphore.wait()

            lock.lock()
            guard !frameChannel.isEmpty else {
                lock.unlock()
                continue
            }
            let masterFrame = frameChannel.removeFirst()
            lock.unlock()

            if let error = masterFrame.error {
                // Error reading from master
                print("Error reading from master \(masterFrame.masterIdx): \(error)")
                try handleMasterDeath(masterFrame.masterIdx)
                continue
            }

            guard let frame = masterFrame.frame else {
                // EOF from master
                try handleMasterDeath(masterFrame.masterIdx)
                // Check if all masters are dead
                lock.lock()
                let allDead = masters.allSatisfy { !$0.healthy }
                lock.unlock()
                if allDead {
                    return nil
                }
                continue
            }

            // Handle the frame
            if let resultFrame = try handleMasterFrame(sourceIdx: masterFrame.masterIdx, frame: frame) {
                return resultFrame
            }
            // Peer request was handled internally, continue reading
        }
    }

    // MARK: - Internal Routing

    private func findMasterForCap(_ capUrn: String) -> Int? {
        // Exact match first
        for (registeredCap, idx) in capTable {
            if registeredCap == capUrn {
                return idx
            }
        }

        // URN-level matching: request is pattern, registered is instance
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        for (registeredCap, idx) in capTable {
            guard let registeredUrn = try? CSCapUrn.fromString(registeredCap) else {
                continue
            }

            if requestUrn.accepts(registeredUrn) {
                return idx
            }
        }

        return nil
    }

    private func handleMasterFrame(sourceIdx: Int, frame: CborFrame) throws -> CborFrame? {
        lock.lock()
        defer { lock.unlock() }

        switch frame.frameType {
        case .req:
            // Peer request: plugin → plugin via switch
            guard let cap = frame.cap, let destIdx = findMasterForCap(cap) else {
                throw CborRelaySwitchError.noHandler(frame.cap ?? "nil")
            }

            // Register routing (source = plugin's master)
            requestRouting[frame.id.toString()] = RoutingEntry(
                sourceMasterIdx: sourceIdx,
                destinationMasterIdx: destIdx
            )
            peerRequests.insert(frame.id.toString())

            try masters[destIdx].socketWriter.write(frame)

            // Do NOT return to engine (internal routing)
            return nil

        case .streamStart, .chunk, .streamEnd, .end, .err, .log:
            guard let entry = requestRouting[frame.id.toString()] else {
                // Unknown request - just return to engine
                return frame
            }

            if entry.sourceMasterIdx != ENGINE_SOURCE {
                // Response to peer request
                let destIdx = entry.sourceMasterIdx
                let isTerminal = frame.frameType == .end || frame.frameType == .err

                try masters[destIdx].socketWriter.write(frame)

                if isTerminal && !peerRequests.contains(frame.id.toString()) {
                    requestRouting.removeValue(forKey: frame.id.toString())
                }

                return nil
            }

            // Response to engine request
            let isTerminal = frame.frameType == .end || frame.frameType == .err
            if isTerminal && !peerRequests.contains(frame.id.toString()) {
                requestRouting.removeValue(forKey: frame.id.toString())
            }

            return frame

        default:
            // Unknown frame type - return to engine
            return frame
        }
    }

    private func handleMasterDeath(_ masterIdx: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        guard masters[masterIdx].healthy else {
            return  // Already handled
        }

        masters[masterIdx].healthy = false

        // ERR all pending requests to this master
        var toRemove: [String] = []
        for (reqId, entry) in requestRouting {
            if entry.destinationMasterIdx == masterIdx {
                // TODO: Send ERR to source
                toRemove.append(reqId)
            }
        }

        for reqId in toRemove {
            requestRouting.removeValue(forKey: reqId)
            peerRequests.remove(reqId)
        }

        // Rebuild cap table without dead master
        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
    }

    // MARK: - Capability Management

    private func rebuildCapTable() {
        capTable.removeAll()
        for (idx, master) in masters.enumerated() {
            if master.healthy {
                for cap in master.caps {
                    capTable.append((capUrn: cap, masterIdx: idx))
                }
            }
        }
    }

    private func rebuildCapabilities() {
        var allCaps = Set<String>()
        for master in masters {
            if master.healthy {
                allCaps.formUnion(master.caps)
            }
        }

        let manifest: [String: Any] = [
            "capabilities": Array(allCaps).sorted()
        ]

        aggregateCapabilities = (try? JSONSerialization.data(withJSONObject: manifest)) ?? Data()
    }

    private func rebuildLimits() {
        var minFrame = Int.max
        var minChunk = Int.max

        for master in masters {
            if master.healthy {
                if master.limits.maxFrame < minFrame {
                    minFrame = master.limits.maxFrame
                }
                if master.limits.maxChunk < minChunk {
                    minChunk = master.limits.maxChunk
                }
            }
        }

        if minFrame == Int.max {
            minFrame = DEFAULT_MAX_FRAME
        }
        if minChunk == Int.max {
            minChunk = DEFAULT_MAX_CHUNK
        }

        negotiatedLimits = CborLimits(maxFrame: minFrame, maxChunk: minChunk)
    }

    // MARK: - Helper Functions

    private static func parseCapabilitiesFromManifest(_ manifest: Data) throws -> [String] {
        guard let parsed = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let capsArray = parsed["capabilities"] as? [String] else {
            throw CborRelaySwitchError.protocolError("Manifest capabilities must be array")
        }
        return capsArray
    }
}
