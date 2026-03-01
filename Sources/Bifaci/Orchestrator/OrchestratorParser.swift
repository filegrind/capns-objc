//
//  OrchestratorParser.swift
//  DOT graph parsing and Cap URN resolution
//
//  Parses DOT digraphs and interprets edge labels starting with `cap:` as Cap URNs.
//  Resolves each Cap URN via a CapDag registry, validates the graph, and produces
//  a validated, executable DAG IR.

import Foundation
@preconcurrency import CapDAG

// MARK: - CSMediaUrn Swift Extension

extension CSMediaUrn {
    /// Convenience method to create CSMediaUrn from string (uses throwing variant)
    static func from(_ string: String) -> CSMediaUrn? {
        return try? CSMediaUrn.fromString(string)
    }

    /// Check if this URN has a given tag (tag value exists, even if empty)
    func hasTag(_ tag: String) -> Bool {
        return getTag(tag) != nil
    }
}

// MARK: - Media URN Compatibility

/// Check if two media URN strings are compatible via bidirectional accepts.
///
/// Returns true if either URN accepts the other, meaning they represent
/// related media types where one may be more specific than the other.
/// For example, `media:image;png` and `media:image;png;bytes` are compatible
/// because the less-specific one accepts the more-specific one.
private func mediaUrnsCompatible(_ a: String, _ b: String) -> Result<Bool, ParseOrchestrationError> {
    guard let aUrn = CSMediaUrn.from(a) else {
        return .failure(.mediaUrnParseError("Failed to parse '\(a)'"))
    }
    guard let bUrn = CSMediaUrn.from(b) else {
        return .failure(.mediaUrnParseError("Failed to parse '\(b)'"))
    }

    // Use conformsTo (non-throwing convenience version)
    // conformsTo checks if instance conforms to pattern = pattern.accepts(instance)
    let fwd = bUrn.conforms(to: aUrn)  // aUrn accepts bUrn
    let rev = aUrn.conforms(to: bUrn)  // bUrn accepts aUrn
    return .success(fwd || rev)
}

/// Check if a media URN has the 'record' marker tag
private func isRecordUrn(_ urnString: String) -> Bool {
    guard let urn = CSMediaUrn.from(urnString) else {
        return false
    }
    return urn.isRecord()
}

/// Check if two media URN strings have compatible structures (record/opaque).
///
/// Structure compatibility is strict:
/// - Opaque → Opaque: Compatible
/// - Record → Record: Compatible
/// - Opaque → Record: Incompatible (cannot add structure to opaque data)
/// - Record → Opaque: Incompatible (cannot discard structure from record)
private func checkStructureCompatibility(
    sourceUrn: String,
    targetUrn: String,
    nodeName: String
) -> Result<Void, ParseOrchestrationError> {
    let sourceStructure: InputStructure = isRecordUrn(sourceUrn) ? .record : .opaque
    let targetStructure: InputStructure = isRecordUrn(targetUrn) ? .record : .opaque

    if sourceStructure != targetStructure {
        return .failure(.structureMismatch(
            node: nodeName,
            sourceStructure: sourceStructure,
            expectedStructure: targetStructure
        ))
    }

    return .success(())
}

// MARK: - Main Parser

/// Parse a DOT digraph and produce a validated orchestration graph
///
/// - Parameters:
///   - dot: DOT source code
///   - registry: Cap registry for resolving Cap URNs
/// - Returns: Resolved and validated orchestration graph
/// - Throws: ParseOrchestrationError for any validation failure
public func parseDotToCapDag(
    _ dot: String,
    registry: CapRegistryProtocol
) async throws -> ResolvedGraph {
    // Step 1: Parse DOT
    let dotGraph = try DotParser.parse(dot)

    // Step 2: Process node attributes first.
    //
    // Nodes with an explicit `media="..."` attribute declare their actual data type.
    // This takes priority over the cap's in= spec when deriving stream labels.
    var nodeMedia: [String: String] = [:]
    var attrNodes: Set<String> = []
    var resolvedEdges: [ResolvedEdge] = []

    for (nodeId, node) in dotGraph.nodes {
        if let mediaAttr = node.attributes["media"] {
            nodeMedia[nodeId] = mediaAttr
            attrNodes.insert(nodeId)
        }
    }

    // Step 3: Pre-scan edges to identify fan-in groups (multiple edges to same `to` node).
    var toEdgeCount: [String: Int] = [:]
    for edge in dotGraph.edges {
        toEdgeCount[edge.to, default: 0] += 1
    }

    // Step 4-5: Process edges and resolve caps
    for edge in dotGraph.edges {
        let from = edge.from
        let to = edge.to

        // Extract and validate edge label
        guard let label = edge.label else {
            throw ParseOrchestrationError.edgeMissingLabel(from: from, to: to)
        }

        // Validate label starts with "cap:"
        guard label.hasPrefix("cap:") else {
            throw ParseOrchestrationError.edgeLabelNotCapUrn(from: from, to: to, label: label)
        }

        let capUrn = label

        // Resolve Cap URN via registry
        let cap: CSCap
        do {
            cap = try await registry.lookup(capUrn)
        } catch let error as ParseOrchestrationError {
            throw error
        } catch {
            throw ParseOrchestrationError.capNotFound(capUrn: capUrn)
        }

        // Parse the cap URN to extract in/out specs
        guard let parsedCapUrn = try? CSCapUrn.fromString(capUrn) else {
            throw ParseOrchestrationError.capUrnParseError("Failed to parse '\(capUrn)'")
        }

        let capInMedia = parsedCapUrn.inSpec
        let capOutMedia = parsedCapUrn.outSpec

        // Determine the stream label for this edge's input.
        let edgeInMedia: String

        if attrNodes.contains(from) {
            let declared = nodeMedia[from]!

            // For single-edge targets (not fan-in), validate compatibility.
            let isFanin = (toEdgeCount[to] ?? 1) > 1
            if !isFanin {
                switch mediaUrnsCompatible(declared, capInMedia) {
                case .success(let compatible):
                    if !compatible {
                        throw ParseOrchestrationError.nodeMediaAttrConflict(
                            node: from,
                            existing: declared,
                            attrValue: capInMedia
                        )
                    }
                case .failure(let error):
                    throw error
                }

                // Check structure compatibility
                switch checkStructureCompatibility(sourceUrn: declared, targetUrn: capInMedia, nodeName: from) {
                case .success:
                    break
                case .failure(let error):
                    throw error
                }
            }
            edgeInMedia = declared
        } else {
            // Implicitly-typed node: use cap's in= spec as stream label.
            if let existing = nodeMedia[from] {
                switch mediaUrnsCompatible(existing, capInMedia) {
                case .success(let compatible):
                    if !compatible {
                        throw ParseOrchestrationError.nodeMediaConflict(
                            node: from,
                            existing: existing,
                            requiredByCap: capInMedia
                        )
                    }
                case .failure(let error):
                    throw error
                }

                // Check structure compatibility
                switch checkStructureCompatibility(sourceUrn: existing, targetUrn: capInMedia, nodeName: from) {
                case .success:
                    break
                case .failure(let error):
                    throw error
                }
            } else {
                nodeMedia[from] = capInMedia
            }
            edgeInMedia = capInMedia
        }

        // Check 'to' node output type — use semantic accepts() matching
        if let existing = nodeMedia[to] {
            switch mediaUrnsCompatible(existing, capOutMedia) {
            case .success(let compatible):
                if !compatible {
                    throw ParseOrchestrationError.nodeMediaConflict(
                        node: to,
                        existing: existing,
                        requiredByCap: capOutMedia
                    )
                }
            case .failure(let error):
                throw error
            }

            // Check structure compatibility
            switch checkStructureCompatibility(sourceUrn: capOutMedia, targetUrn: existing, nodeName: to) {
            case .success:
                break
            case .failure(let error):
                throw error
            }
        } else {
            nodeMedia[to] = capOutMedia
        }

        resolvedEdges.append(ResolvedEdge(
            from: from,
            to: to,
            capUrn: capUrn,
            cap: cap,
            inMedia: edgeInMedia,
            outMedia: capOutMedia
        ))
    }

    // Step 6: DAG validation (topological sort to detect cycles)
    try validateDag(nodes: nodeMedia, edges: resolvedEdges)

    return ResolvedGraph(
        nodes: nodeMedia,
        edges: resolvedEdges,
        graphName: dotGraph.name
    )
}

// MARK: - DAG Validation

/// Validate that the graph is a DAG (no cycles) using topological sort
private func validateDag(nodes: [String: String], edges: [ResolvedEdge]) throws {
    // Build adjacency list
    var adjacency: [String: [String]] = [:]
    var inDegree: [String: Int] = [:]

    for nodeName in nodes.keys {
        adjacency[nodeName] = []
        inDegree[nodeName] = 0
    }

    for edge in edges {
        adjacency[edge.from, default: []].append(edge.to)
        inDegree[edge.to, default: 0] += 1
    }

    // Kahn's algorithm for topological sort
    var queue: [String] = []
    for (node, degree) in inDegree {
        if degree == 0 {
            queue.append(node)
        }
    }

    var visited = 0
    while !queue.isEmpty {
        let node = queue.removeFirst()
        visited += 1

        for neighbor in adjacency[node] ?? [] {
            inDegree[neighbor]! -= 1
            if inDegree[neighbor] == 0 {
                queue.append(neighbor)
            }
        }
    }

    // If we didn't visit all nodes, there's a cycle
    if visited < nodes.count {
        // Find nodes involved in cycle (those with non-zero in-degree)
        let cycleNodes = inDegree.filter { $0.value > 0 }.map { $0.key }.sorted()
        throw ParseOrchestrationError.notADag(cycleNodes: cycleNodes)
    }
}
