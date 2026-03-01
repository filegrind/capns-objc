//
//  OrchestratorTypes.swift
//  Orchestrator: DOT Parser with CapDag Orchestration
//
//  This module parses DOT digraphs and interprets edge labels starting with `cap:`
//  as Cap URNs. It resolves each Cap URN via a CapDag registry, validates the graph,
//  and produces a validated, executable DAG IR.

import Foundation
@preconcurrency import CapDAG

// MARK: - Error Types

/// Errors that can occur during DOT parsing and orchestration
public enum ParseOrchestrationError: Error, Equatable {
    /// DOT parsing failed
    case dotParseFailed(String)

    /// Edge is missing the required 'label' attribute
    case edgeMissingLabel(from: String, to: String)

    /// Edge label does not start with 'cap:'
    case edgeLabelNotCapUrn(from: String, to: String, label: String)

    /// Cap URN not found in registry
    case capNotFound(capUrn: String)

    /// Cap URN is invalid
    case capInvalid(capUrn: String, details: String)

    /// Node media URN conflicts with existing assignment
    case nodeMediaConflict(node: String, existing: String, requiredByCap: String)

    /// Node media attribute conflicts with derived media URN
    case nodeMediaAttrConflict(node: String, existing: String, attrValue: String)

    /// Graph contains a cycle (not a DAG)
    case notADag(cycleNodes: [String])

    /// Cap URN parsing error
    case capUrnParseError(String)

    /// Media URN parsing error
    case mediaUrnParseError(String)

    /// Registry error
    case registryError(String)

    /// Structure mismatch between connected nodes (record vs opaque)
    case structureMismatch(node: String, sourceStructure: InputStructure, expectedStructure: InputStructure)
}

extension ParseOrchestrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .dotParseFailed(let msg):
            return "DOT parse failed: \(msg)"
        case .edgeMissingLabel(let from, let to):
            return "Edge from '\(from)' to '\(to)' is missing label attribute"
        case .edgeLabelNotCapUrn(let from, let to, let label):
            return "Edge from '\(from)' to '\(to)' has label '\(label)' that does not start with 'cap:'"
        case .capNotFound(let capUrn):
            return "Cap URN '\(capUrn)' not found in registry"
        case .capInvalid(let capUrn, let details):
            return "Cap URN '\(capUrn)' is invalid: \(details)"
        case .nodeMediaConflict(let node, let existing, let requiredByCap):
            return "Node '\(node)' has conflicting media URNs: existing='\(existing)', required_by_cap='\(requiredByCap)'"
        case .nodeMediaAttrConflict(let node, let existing, let attrValue):
            return "Node '\(node)' has media attribute '\(attrValue)' that conflicts with derived media URN '\(existing)'"
        case .notADag(let cycleNodes):
            return "Graph is not a DAG, contains cycle involving nodes: \(cycleNodes)"
        case .capUrnParseError(let msg):
            return "Failed to parse Cap URN: \(msg)"
        case .mediaUrnParseError(let msg):
            return "Failed to parse Media URN: \(msg)"
        case .registryError(let msg):
            return "Registry error: \(msg)"
        case .structureMismatch(let node, let sourceStructure, let expectedStructure):
            return "Structure mismatch at node '\(node)': source is \(sourceStructure) but cap expects \(expectedStructure)"
        }
    }
}

// MARK: - Input Structure

/// Structure of input data - record (structured JSON) vs opaque (binary/text blob)
public enum InputStructure: String, Equatable, Sendable {
    case record = "record"
    case opaque = "opaque"
}

// MARK: - IR Structures

/// A resolved edge in the orchestration graph
public struct ResolvedEdge: Equatable {
    /// Source node DOT ID
    public let from: String
    /// Target node DOT ID
    public let to: String
    /// Cap URN string from label
    public let capUrn: String
    /// Resolved cap definition
    public let cap: CSCap
    /// Input media URN (the actual stream label for this edge)
    public let inMedia: String
    /// Output media URN from cap definition
    public let outMedia: String

    public init(from: String, to: String, capUrn: String, cap: CSCap, inMedia: String, outMedia: String) {
        self.from = from
        self.to = to
        self.capUrn = capUrn
        self.cap = cap
        self.inMedia = inMedia
        self.outMedia = outMedia
    }

    public static func == (lhs: ResolvedEdge, rhs: ResolvedEdge) -> Bool {
        return lhs.from == rhs.from &&
               lhs.to == rhs.to &&
               lhs.capUrn == rhs.capUrn &&
               lhs.inMedia == rhs.inMedia &&
               lhs.outMedia == rhs.outMedia
    }
}

/// A resolved orchestration graph
public struct ResolvedGraph: Equatable {
    /// Map from DOT node ID to derived media URN
    public var nodes: [String: String]
    /// Resolved edges with cap definitions
    public var edges: [ResolvedEdge]
    /// Original graph name (if any)
    public var graphName: String?

    public init(nodes: [String: String] = [:], edges: [ResolvedEdge] = [], graphName: String? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.graphName = graphName
    }
}

// MARK: - Cap Registry Protocol

/// Protocol for Cap registry abstraction
///
/// This allows dependency injection and testing without network access
public protocol CapRegistryProtocol: Sendable {
    /// Look up a cap by URN
    func lookup(_ urn: String) async throws -> CSCap
}
