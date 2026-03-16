//
//  PlanConverter.swift
//  Bifaci
//
//  Converts CapExecutionPlan (node-centric, from planner) to ResolvedGraph
//  (edge-centric, for executor).
//  Mirrors Rust: src/orchestrator/plan_converter.rs
//
//  Strategy:
//  - InputSlot nodes → source data nodes
//  - Cap nodes → edges from input source to output target
//  - Output nodes → mark terminal data nodes
//  - WrapInList nodes → transparent pass-through (rewritten to predecessor)
//  - ForEach/Collect/Merge/Split → REJECTED (caller must decompose first)

import Foundation
@preconcurrency import CapDAG

// MARK: - Plan Converter

/// Convert CapExecutionPlan to ResolvedGraph for execution.
///
/// The planner creates execution plans where caps are nodes with edges
/// representing data flow. The orchestrator expects caps to be edge labels
/// connecting data nodes.
///
/// - Parameters:
///   - plan: Execution plan from planner
///   - registry: Cap registry for resolving full Cap definitions
/// - Returns: ResolvedGraph suitable for execute_dag
/// - Throws: ParseOrchestrationError if conversion fails
public func planToResolvedGraph(
    _ plan: CSCapExecutionPlan,
    registry: any CapRegistryProtocol
) async throws -> ResolvedGraph {
    // Phase 1: Reject ForEach/Collect/Merge/Split — caller must decompose
    let topoOrder = try plan.topologicalOrder()

    for capNode in topoOrder {
        if capNode.isFanOut() {
            throw ParseOrchestrationError.dotParseFailed(
                "Plan contains ForEach node '\(capNode.nodeId)'. " +
                "Decompose the plan using extractPrefixTo:/extractForeachBody:/extractSuffixFrom: first.")
        }
        if capNode.isFanIn() {
            throw ParseOrchestrationError.dotParseFailed(
                "Plan contains Collect node '\(capNode.nodeId)'. " +
                "Decompose the plan using extractPrefixTo:/extractForeachBody:/extractSuffixFrom: first.")
        }
    }

    // Phase 2: Register data nodes with their media URNs
    var nodeMedia: [String: String] = [:]    // nodeId → media URN
    var wrapPredecessors: [String: String] = [:] // wrapNodeId → predecessorNodeId

    // Build reverse adjacency for finding predecessors
    var predecessorOf: [String: String] = [:]
    for case let capEdge as CSCapEdge in plan.edges {
        predecessorOf[capEdge.toNode] = capEdge.fromNode
    }

    for capNode in topoOrder {
        let nodeId = capNode.nodeId

        if capNode.slotName != nil {
            // InputSlot node — use expected media URN
            nodeMedia[nodeId] = capNode.expectedMediaUrn ?? "media:"
        } else if let capUrnStr = capNode.capUrn {
            // Cap node — look up in registry, use out_spec
            let cap = try await registry.lookup(capUrnStr)
            let outSpec = cap.capUrn.getOutSpec()
            nodeMedia[nodeId] = outSpec
        } else if capNode.outputName != nil {
            // Output node — inherit from source
            if let sourceNode = capNode.sourceNode {
                nodeMedia[nodeId] = nodeMedia[sourceNode] ?? "media:"
            }
        } else if capNode.isWrapInList() {
            // WrapInList node — use list media URN, track predecessor
            if let listUrn = capNode.wrapListMediaUrn {
                nodeMedia[nodeId] = listUrn
            }
            if let pred = predecessorOf[nodeId] {
                wrapPredecessors[nodeId] = pred
            }
        }
    }

    // Phase 3: Convert edges leading INTO Cap nodes to ResolvedEdges
    var resolvedEdges: [ResolvedEdge] = []

    for capNode in topoOrder {
        let nodeId = capNode.nodeId
        guard let capUrnStr = capNode.capUrn else { continue }

        let cap = try await registry.lookup(capUrnStr)
        let inMedia = cap.capUrn.getInSpec()
        let outMedia = cap.capUrn.getOutSpec()

        // Find all edges leading into this cap node
        for case let capEdge as CSCapEdge in plan.edges {
            guard capEdge.toNode == nodeId else { continue }
            var fromNode = capEdge.fromNode

            // Resolve through WrapInList nodes
            if let actualPred = wrapPredecessors[fromNode] {
                fromNode = actualPred
            }

            let resolved = ResolvedEdge(
                from: fromNode,
                to: nodeId,
                capUrn: capUrnStr,
                cap: cap,
                inMedia: inMedia,
                outMedia: outMedia
            )
            resolvedEdges.append(resolved)
        }
    }

    return ResolvedGraph(nodes: nodeMedia, edges: resolvedEdges)
}
