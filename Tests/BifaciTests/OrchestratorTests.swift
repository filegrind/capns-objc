//
//  OrchestratorTests.swift
//  Bifaci
//
//  Integration tests for capdag orchestrator
//
//  These tests verify the orchestrator's ability to:
//  1. Parse and validate DOT graphs with Cap URNs
//  2. Resolve Cap URNs via registry
//  3. Validate media URN compatibility
//  4. Detect cycles (not a DAG)
//
//  Tests use // TEST###: comments matching the Rust implementation for cross-tracking.

import XCTest
@testable import Bifaci
import CapDAG
import Foundation

// MARK: - Mock Registry

/// Mock registry for testcartridge caps
final class TestcartridgeRegistry: CapRegistryProtocol, @unchecked Sendable {
    private var caps: [String: CSCap] = [:]

    init() {
        // Helper to add a cap
        func addCap(_ urnStr: String) {
            guard let capUrn = try? CSCapUrn.fromString(urnStr) else {
                fatalError("Invalid test cap URN: \(urnStr)")
            }
            let cap = CSCap(
                urn: capUrn,
                title: "Test \(capUrn.getTag("op") ?? "unknown")",
                command: "testcartridge"
            )
            caps[capUrn.toString()] = cap
        }

        // Register all testcartridge caps
        addCap(#"cap:in="media:node1;textable";op=test_edge1;out="media:node2;textable""#)
        addCap(#"cap:in="media:node2;textable";op=test_edge2;out="media:node3;textable""#)
        addCap(#"cap:in="media:node3;textable";op=test_edge3;out="media:node4;list;textable""#)
        addCap(#"cap:in="media:node4;list;textable";op=test_edge4;out="media:node5;textable""#)
        addCap(#"cap:in="media:node3;textable";op=test_edge7;out="media:node6;textable""#)
        addCap(#"cap:in="media:node6;textable";op=test_edge8;out="media:node7;textable""#)
        addCap(#"cap:in="media:node7;textable";op=test_edge9;out="media:node8;textable""#)
        addCap(#"cap:in="media:node8;textable";op=test_edge10;out="media:node1;textable""#)
        addCap(#"cap:in="media:void";op=test_large;out="media:""#)
        addCap(#"cap:in="media:node1;textable";op=test_peer;out="media:node3;textable""#)

        // Add identity cap for cycle testing
        addCap(#"cap:in="media:node1;textable";op=identity;out="media:node1;textable""#)
    }

    func lookup(_ urn: String) async throws -> CSCap {
        // Normalize the URN for lookup
        guard let capUrn = try? CSCapUrn.fromString(urn) else {
            throw ParseOrchestrationError.capUrnParseError("Failed to parse '\(urn)'")
        }
        let normalized = capUrn.toString()

        // Find the cap (normalize keys for comparison)
        for (key, cap) in caps {
            if let keyUrn = try? CSCapUrn.fromString(key),
               keyUrn.toString() == normalized {
                return cap
            }
        }

        throw ParseOrchestrationError.capNotFound(capUrn: urn)
    }
}

// MARK: - Tests

final class OrchestratorTests: XCTestCase {

    // MARK: - Phase 1: Basic Functionality

    // TEST935: Parse simple DOT graph with test-edge1
    func test935_parseSimpleTestcartridgeGraph() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.nodes["A"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["B"], "media:node2;textable")
    }

    // TEST936: Parse single-edge DAG (test-edge1)
    func test936_parseSingleEdgeDag() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                input -> output [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.nodes["input"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["output"], "media:node2;textable")
    }

    // TEST937: Parse two-edge chain (test-edge1 -> test-edge2)
    func test937_parseEdge1ToEdge2Chain() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
                B -> C [label="cap:in=\"media:node2;textable\";op=test_edge2;out=\"media:node3;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 3)
        XCTAssertEqual(graph.edges.count, 2)
        XCTAssertEqual(graph.nodes["A"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["B"], "media:node2;textable")
        XCTAssertEqual(graph.nodes["C"], "media:node3;textable")
    }

    // TEST940: Parse fan-in pattern
    func test940_parseFanInPattern() async throws {
        let registry = TestcartridgeRegistry()

        // Two parallel paths that merge
        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
                C -> D [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
                B -> E [label="cap:in=\"media:node2;textable\";op=test_edge2;out=\"media:node3;textable\""];
                D -> E [label="cap:in=\"media:node2;textable\";op=test_edge2;out=\"media:node3;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 5)
        XCTAssertEqual(graph.edges.count, 4)
        XCTAssertEqual(graph.nodes["A"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["B"], "media:node2;textable")
        XCTAssertEqual(graph.nodes["C"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["D"], "media:node2;textable")
        XCTAssertEqual(graph.nodes["E"], "media:node3;textable")
    }

    // TEST941: Validate that cycles are rejected
    func test941_rejectCycles() async throws {
        let registry = TestcartridgeRegistry()

        // Create a self-loop using identity cap
        let dot = #"""
            digraph G {
                A -> A [label="cap:in=\"media:node1;textable\";op=identity;out=\"media:node1;textable\""];
            }
        """#

        do {
            _ = try await parseDotToCapDag(dot, registry: registry)
            XCTFail("Should reject cycle")
        } catch let error as ParseOrchestrationError {
            switch error {
            case .notADag:
                // Expected error
                break
            default:
                XCTFail("Expected NotADag error, got: \(error)")
            }
        }
    }

    // TEST942: Empty graph (no edges)
    func test942_emptyGraph() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A;
                B;
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.edges.count, 0)
        // Nodes without caps won't have media URNs derived
        XCTAssert(graph.nodes.isEmpty)
    }

    // TEST943: Invalid cap URN in label
    func test943_invalidCapUrn() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:INVALID"];
            }
        """#

        do {
            _ = try await parseDotToCapDag(dot, registry: registry)
            XCTFail("Should reject invalid cap URN")
        } catch {
            // Expected - invalid cap URN format should fail
        }
    }

    // TEST944: Cap not found in registry
    func test944_capNotFound() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:unknown\";op=nonexistent;out=\"media:unknown\""];
            }
        """#

        do {
            _ = try await parseDotToCapDag(dot, registry: registry)
            XCTFail("Should fail when cap not found")
        } catch let error as ParseOrchestrationError {
            switch error {
            case .capNotFound:
                // Expected
                break
            default:
                XCTFail("Expected CapNotFound, got: \(error)")
            }
        }
    }

    // MARK: - Phase 2: Long Chain Tests

    // TEST945: 4-cap chain: edge1 -> edge2 -> edge7 -> edge8
    func test945_fourCapChain() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
                B -> C [label="cap:in=\"media:node2;textable\";op=test_edge2;out=\"media:node3;textable\""];
                C -> D [label="cap:in=\"media:node3;textable\";op=test_edge7;out=\"media:node6;textable\""];
                D -> E [label="cap:in=\"media:node6;textable\";op=test_edge8;out=\"media:node7;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 5)
        XCTAssertEqual(graph.edges.count, 4)
        XCTAssertEqual(graph.nodes["A"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["B"], "media:node2;textable")
        XCTAssertEqual(graph.nodes["C"], "media:node3;textable")
        XCTAssertEqual(graph.nodes["D"], "media:node6;textable")
        XCTAssertEqual(graph.nodes["E"], "media:node7;textable")
    }

    // TEST946: 5-cap chain: edge1 -> edge2 -> edge7 -> edge8 -> edge9
    func test946_fiveCapChain() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
                B -> C [label="cap:in=\"media:node2;textable\";op=test_edge2;out=\"media:node3;textable\""];
                C -> D [label="cap:in=\"media:node3;textable\";op=test_edge7;out=\"media:node6;textable\""];
                D -> E [label="cap:in=\"media:node6;textable\";op=test_edge8;out=\"media:node7;textable\""];
                E -> F [label="cap:in=\"media:node7;textable\";op=test_edge9;out=\"media:node8;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 6)
        XCTAssertEqual(graph.edges.count, 5)
        XCTAssertEqual(graph.nodes["A"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["B"], "media:node2;textable")
        XCTAssertEqual(graph.nodes["C"], "media:node3;textable")
        XCTAssertEqual(graph.nodes["D"], "media:node6;textable")
        XCTAssertEqual(graph.nodes["E"], "media:node7;textable")
        XCTAssertEqual(graph.nodes["F"], "media:node8;textable")
    }

    // TEST947: 6-cap chain: edge1 -> edge2 -> edge7 -> edge8 -> edge9 -> edge10
    func test947_sixCapChain() async throws {
        let registry = TestcartridgeRegistry()

        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test_edge1;out=\"media:node2;textable\""];
                B -> C [label="cap:in=\"media:node2;textable\";op=test_edge2;out=\"media:node3;textable\""];
                C -> D [label="cap:in=\"media:node3;textable\";op=test_edge7;out=\"media:node6;textable\""];
                D -> E [label="cap:in=\"media:node6;textable\";op=test_edge8;out=\"media:node7;textable\""];
                E -> F [label="cap:in=\"media:node7;textable\";op=test_edge9;out=\"media:node8;textable\""];
                F -> G [label="cap:in=\"media:node8;textable\";op=test_edge10;out=\"media:node1;textable\""];
            }
        """#

        let graph = try await parseDotToCapDag(dot, registry: registry)

        XCTAssertEqual(graph.nodes.count, 7)
        XCTAssertEqual(graph.edges.count, 6)
        XCTAssertEqual(graph.nodes["A"], "media:node1;textable")
        XCTAssertEqual(graph.nodes["B"], "media:node2;textable")
        XCTAssertEqual(graph.nodes["C"], "media:node3;textable")
        XCTAssertEqual(graph.nodes["D"], "media:node6;textable")
        XCTAssertEqual(graph.nodes["E"], "media:node7;textable")
        XCTAssertEqual(graph.nodes["F"], "media:node8;textable")
        XCTAssertEqual(graph.nodes["G"], "media:node1;textable")
    }

    // MARK: - DOT Parser Tests

    // TEST: Parse simple digraph
    func testDotParserSimpleDigraph() throws {
        let dot = #"""
            digraph G {
                A -> B;
            }
        """#

        let graph = try DotParser.parse(dot)

        XCTAssertEqual(graph.name, "G")
        XCTAssertTrue(graph.isDigraph)
        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertNotNil(graph.nodes["A"])
        XCTAssertNotNil(graph.nodes["B"])
        XCTAssertEqual(graph.edges[0].from, "A")
        XCTAssertEqual(graph.edges[0].to, "B")
    }

    // TEST: Parse edge with label attribute
    func testDotParserEdgeWithLabel() throws {
        let dot = #"""
            digraph G {
                A -> B [label="my_label"];
            }
        """#

        let graph = try DotParser.parse(dot)

        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges[0].label, "my_label")
    }

    // TEST: Parse node with attributes
    func testDotParserNodeWithAttributes() throws {
        let dot = #"""
            digraph G {
                A [shape=box, color=red];
                A -> B;
            }
        """#

        let graph = try DotParser.parse(dot)

        let nodeA = graph.nodes["A"]
        XCTAssertNotNil(nodeA)
        XCTAssertEqual(nodeA?.attributes["shape"], "box")
        XCTAssertEqual(nodeA?.attributes["color"], "red")
    }

    // TEST: Parse quoted identifiers
    func testDotParserQuotedIdentifiers() throws {
        let dot = #"""
            digraph G {
                "node with spaces" -> "another node" [label="test"];
            }
        """#

        let graph = try DotParser.parse(dot)

        XCTAssertNotNil(graph.nodes["node with spaces"])
        XCTAssertNotNil(graph.nodes["another node"])
        XCTAssertEqual(graph.edges[0].from, "node with spaces")
        XCTAssertEqual(graph.edges[0].to, "another node")
    }

    // TEST: Parse graph with comments
    func testDotParserComments() throws {
        let dot = #"""
            // This is a comment
            digraph G {
                /* Block comment */
                A -> B; // Inline comment
            }
        """#

        let graph = try DotParser.parse(dot)

        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.edges.count, 1)
    }

    // TEST: Parse cap URN label with escaped quotes
    func testDotParserCapUrnLabel() throws {
        let dot = #"""
            digraph G {
                A -> B [label="cap:in=\"media:node1;textable\";op=test;out=\"media:node2;textable\""];
            }
        """#

        let graph = try DotParser.parse(dot)

        XCTAssertEqual(graph.edges.count, 1)
        let label = graph.edges[0].label
        XCTAssertNotNil(label)
        XCTAssertTrue(label!.hasPrefix("cap:"))
        XCTAssertTrue(label!.contains("media:node1;textable"))
    }
}
