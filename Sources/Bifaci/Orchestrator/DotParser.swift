//
//  DotParser.swift
//  Minimal DOT graph parser for orchestration
//
//  Parses simple DOT digraphs with node declarations and edges.
//  Supports node attributes [key=value] and edge labels.

import Foundation

// MARK: - AST Types

/// A node in the DOT graph
public struct DotNode: Equatable {
    public let id: String
    public var attributes: [String: String]

    public init(id: String, attributes: [String: String] = [:]) {
        self.id = id
        self.attributes = attributes
    }
}

/// An edge in the DOT graph
public struct DotEdge: Equatable {
    public let from: String
    public let to: String
    public var attributes: [String: String]

    public init(from: String, to: String, attributes: [String: String] = [:]) {
        self.from = from
        self.to = to
        self.attributes = attributes
    }

    /// Get the label attribute (commonly used for cap URN)
    public var label: String? {
        return attributes["label"]
    }
}

/// A parsed DOT graph
public struct DotGraph: Equatable {
    public var name: String?
    public var nodes: [String: DotNode]
    public var edges: [DotEdge]
    public var isDigraph: Bool

    public init(name: String? = nil, nodes: [String: DotNode] = [:], edges: [DotEdge] = [], isDigraph: Bool = true) {
        self.name = name
        self.nodes = nodes
        self.edges = edges
        self.isDigraph = isDigraph
    }
}

// MARK: - Parser

/// Simple DOT graph parser
public struct DotParser {
    private let input: String
    private var position: String.Index
    private let endIndex: String.Index

    public init(_ input: String) {
        self.input = input
        self.position = input.startIndex
        self.endIndex = input.endIndex
    }

    /// Parse a DOT graph
    public static func parse(_ input: String) throws -> DotGraph {
        var parser = DotParser(input)
        return try parser.parseGraph()
    }

    // MARK: - Core Parsing

    private mutating func parseGraph() throws -> DotGraph {
        skipWhitespaceAndComments()

        // Parse graph type (digraph or graph)
        let isDigraph: Bool
        if consume("digraph") {
            isDigraph = true
        } else if consume("graph") {
            isDigraph = false
        } else {
            throw ParseOrchestrationError.dotParseFailed("Expected 'digraph' or 'graph'")
        }

        skipWhitespaceAndComments()

        // Parse optional graph name
        var graphName: String?
        if peek() != "{" {
            graphName = try parseIdentifier()
            skipWhitespaceAndComments()
        }

        // Expect opening brace
        guard consume("{") else {
            throw ParseOrchestrationError.dotParseFailed("Expected '{'")
        }

        var graph = DotGraph(name: graphName, isDigraph: isDigraph)

        // Parse statements until closing brace
        while !isAtEnd() && peek() != "}" {
            skipWhitespaceAndComments()
            if peek() == "}" { break }

            try parseStatement(&graph)
            skipWhitespaceAndComments()

            // Optional semicolon
            _ = consume(";")
            skipWhitespaceAndComments()
        }

        // Expect closing brace
        guard consume("}") else {
            throw ParseOrchestrationError.dotParseFailed("Expected '}'")
        }

        return graph
    }

    private mutating func parseStatement(_ graph: inout DotGraph) throws {
        skipWhitespaceAndComments()

        // Skip graph-level attributes (node [shape=...], edge [...], etc.)
        if consume("node") || consume("edge") || consume("graph") {
            skipWhitespaceAndComments()
            if peek() == "[" {
                _ = try parseAttributes()
            }
            return
        }

        // Parse first identifier
        let firstId = try parseIdentifier()
        skipWhitespaceAndComments()

        // Check for edge or node declaration
        if consume("->") || consume("--") {
            // Edge declaration
            skipWhitespaceAndComments()
            let secondId = try parseIdentifier()
            skipWhitespaceAndComments()

            var attributes: [String: String] = [:]
            if peek() == "[" {
                attributes = try parseAttributes()
            }

            // Ensure both nodes exist
            if graph.nodes[firstId] == nil {
                graph.nodes[firstId] = DotNode(id: firstId)
            }
            if graph.nodes[secondId] == nil {
                graph.nodes[secondId] = DotNode(id: secondId)
            }

            graph.edges.append(DotEdge(from: firstId, to: secondId, attributes: attributes))
        } else if peek() == "[" {
            // Node declaration with attributes
            let attributes = try parseAttributes()
            if let existing = graph.nodes[firstId] {
                var updated = existing
                for (k, v) in attributes {
                    updated.attributes[k] = v
                }
                graph.nodes[firstId] = updated
            } else {
                graph.nodes[firstId] = DotNode(id: firstId, attributes: attributes)
            }
        } else {
            // Simple node declaration
            if graph.nodes[firstId] == nil {
                graph.nodes[firstId] = DotNode(id: firstId)
            }
        }
    }

    private mutating func parseAttributes() throws -> [String: String] {
        guard consume("[") else {
            throw ParseOrchestrationError.dotParseFailed("Expected '['")
        }

        var attributes: [String: String] = [:]

        while !isAtEnd() && peek() != "]" {
            skipWhitespaceAndComments()
            if peek() == "]" { break }

            let key = try parseIdentifier()
            skipWhitespaceAndComments()

            guard consume("=") else {
                throw ParseOrchestrationError.dotParseFailed("Expected '=' in attribute")
            }

            skipWhitespaceAndComments()
            let value = try parseValue()
            attributes[key.lowercased()] = value

            skipWhitespaceAndComments()
            _ = consume(",") || consume(";")
            skipWhitespaceAndComments()
        }

        guard consume("]") else {
            throw ParseOrchestrationError.dotParseFailed("Expected ']'")
        }

        return attributes
    }

    private mutating func parseIdentifier() throws -> String {
        skipWhitespaceAndComments()

        // Check for quoted identifier
        if peek() == "\"" {
            return try parseQuotedString()
        }

        // Unquoted identifier
        var result = ""
        while !isAtEnd() {
            let c = currentChar()
            if c.isLetter || c.isNumber || c == "_" {
                result.append(c)
                advance()
            } else {
                break
            }
        }

        guard !result.isEmpty else {
            throw ParseOrchestrationError.dotParseFailed("Expected identifier")
        }

        return result
    }

    private mutating func parseValue() throws -> String {
        skipWhitespaceAndComments()

        if peek() == "\"" {
            return try parseQuotedString()
        }

        // Unquoted value (up to , ; ] or whitespace)
        var result = ""
        while !isAtEnd() {
            let c = currentChar()
            if c == "," || c == ";" || c == "]" || c.isWhitespace {
                break
            }
            result.append(c)
            advance()
        }

        return result
    }

    private mutating func parseQuotedString() throws -> String {
        guard consume("\"") else {
            throw ParseOrchestrationError.dotParseFailed("Expected '\"'")
        }

        var result = ""
        while !isAtEnd() {
            let c = currentChar()
            if c == "\"" {
                advance()
                return result
            } else if c == "\\" {
                advance()
                if !isAtEnd() {
                    let escaped = currentChar()
                    advance()
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default: result.append(escaped)
                    }
                }
            } else {
                result.append(c)
                advance()
            }
        }

        throw ParseOrchestrationError.dotParseFailed("Unterminated quoted string")
    }

    // MARK: - Helper Methods

    private func isAtEnd() -> Bool {
        return position >= endIndex
    }

    private func currentChar() -> Character {
        return input[position]
    }

    private func peek() -> String {
        guard !isAtEnd() else { return "" }
        return String(currentChar())
    }

    private mutating func advance() {
        if position < endIndex {
            position = input.index(after: position)
        }
    }

    private mutating func consume(_ expected: String) -> Bool {
        let start = position
        for char in expected {
            guard !isAtEnd() && currentChar() == char else {
                position = start
                return false
            }
            advance()
        }
        return true
    }

    private mutating func skipWhitespaceAndComments() {
        while !isAtEnd() {
            let c = currentChar()
            if c.isWhitespace {
                advance()
            } else if c == "/" && position < input.index(before: endIndex) {
                let nextPos = input.index(after: position)
                let next = input[nextPos]
                if next == "/" {
                    // Line comment
                    while !isAtEnd() && currentChar() != "\n" {
                        advance()
                    }
                } else if next == "*" {
                    // Block comment
                    advance()
                    advance()
                    while !isAtEnd() {
                        if currentChar() == "*" {
                            advance()
                            if !isAtEnd() && currentChar() == "/" {
                                advance()
                                break
                            }
                        } else {
                            advance()
                        }
                    }
                } else {
                    break
                }
            } else if c == "#" {
                // Hash comment (some DOT variants)
                while !isAtEnd() && currentChar() != "\n" {
                    advance()
                }
            } else {
                break
            }
        }
    }
}
