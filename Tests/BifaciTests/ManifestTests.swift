import XCTest
@testable import Bifaci
@testable import CapNs

// =============================================================================
// Manifest Tests
//
// Covers TEST148-155 from manifest.rs in the reference Rust implementation.
// Tests both Swift Manifest struct and Objective-C CSCapManifest class.
// =============================================================================

final class ManifestTests: XCTestCase {

    // MARK: - Swift Manifest Tests

    // TEST148: Test creating cap manifest with name, version, description, and caps
    func test148_capManifestCreation() throws {
        let cap = CapDefinition(urn: "cap:in=media:;out=media:", title: "Test Cap", command: "test")
        let manifest = Manifest(
            name: "test-plugin",
            version: "1.0.0",
            description: "A test plugin",
            caps: [cap]
        )

        XCTAssertEqual(manifest.name, "test-plugin")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.description, "A test plugin")
        XCTAssertEqual(manifest.caps.count, 1)
        XCTAssertEqual(manifest.caps[0].urn, "cap:in=media:;out=media:")
    }

    // TEST149: Test cap manifest with author field (via CSCapManifest which has author)
    func test149_capManifestWithAuthor() throws {
        let csManifest = CSCapManifest(
            name: "test-plugin",
            version: "1.0.0",
            manifestDescription: "A test plugin",
            caps: []
        ).withAuthor("Test Author")

        XCTAssertEqual(csManifest.author, "Test Author")
    }

    // TEST150: Test cap manifest JSON serialization and deserialization roundtrip
    func test150_capManifestJsonRoundtrip() throws {
        let capUrn = "cap:in=media:;out=media:"
        let cap = CapDefinition(urn: capUrn, title: "Process", command: "process")
        let original = Manifest(
            name: "roundtrip-plugin",
            version: "2.0.0",
            description: "Roundtrip test",
            caps: [cap]
        )

        // Serialize to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        // Deserialize from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Manifest.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.caps.count, original.caps.count)
        XCTAssertEqual(decoded.caps[0].urn, capUrn)
    }

    // TEST151: Test cap manifest deserialization fails when required fields are missing
    func test151_capManifestRequiredFields() throws {
        // Missing "name" field
        let missingName = """
        {"version": "1.0.0", "description": "test", "caps": []}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingName)) { error in
            // Should fail to decode due to missing name
            XCTAssertTrue(error is DecodingError)
        }

        // Missing "version" field
        let missingVersion = """
        {"name": "test", "description": "test", "caps": []}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingVersion)) { error in
            XCTAssertTrue(error is DecodingError)
        }

        // Missing "caps" field
        let missingCaps = """
        {"name": "test", "version": "1.0.0", "description": "test"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingCaps)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    // TEST152: Test cap manifest with multiple caps stores and retrieves all capabilities
    func test152_capManifestWithMultipleCaps() throws {
        let caps = [
            CapDefinition(urn: "cap:in=media:;out=media:", title: "Process", command: "process"),
            CapDefinition(urn: "cap:in=text:;out=text:", title: "Transform", command: "transform"),
            CapDefinition(urn: "cap:in=image:;out=image:", title: "Convert", command: "convert"),
        ]
        let manifest = Manifest(
            name: "multi-cap-plugin",
            version: "1.0.0",
            description: "Plugin with multiple caps",
            caps: caps
        )

        XCTAssertEqual(manifest.caps.count, 3)
        XCTAssertEqual(manifest.caps[0].urn, "cap:in=media:;out=media:")
        XCTAssertEqual(manifest.caps[1].urn, "cap:in=text:;out=text:")
        XCTAssertEqual(manifest.caps[2].urn, "cap:in=image:;out=image:")

        // JSON roundtrip preserves all caps
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(Manifest.self, from: data)

        XCTAssertEqual(decoded.caps.count, 3)
    }

    // TEST153: Test cap manifest with empty caps list serializes and deserializes correctly
    func test153_capManifestEmptyCaps() throws {
        let manifest = Manifest(
            name: "empty-caps-plugin",
            version: "1.0.0",
            description: "Plugin with no caps",
            caps: []
        )

        XCTAssertEqual(manifest.caps.count, 0)

        // JSON roundtrip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(Manifest.self, from: data)

        XCTAssertEqual(decoded.caps.count, 0)
    }

    // TEST154: Test cap manifest optional author field (using CSCapManifest)
    func test154_capManifestOptionalAuthorField() throws {
        // Without author
        let manifestNoAuthor = CSCapManifest(
            name: "test",
            version: "1.0.0",
            manifestDescription: "test",
            caps: []
        )
        XCTAssertNil(manifestNoAuthor.author)

        // With author
        let manifestWithAuthor = manifestNoAuthor.withAuthor("Author Name")
        XCTAssertEqual(manifestWithAuthor.author, "Author Name")
    }

    // TEST155: Test ComponentMetadata provides manifest and caps accessor methods
    func test155_componentMetadataAccessors() throws {
        // CSCapManifest provides accessor methods for manifest data
        let capUrn = try CSCapUrn.fromString("cap:in=media:;out=media:")
        let cap = CSCap(urn: capUrn, title: "Test", command: "test")
        let manifest = CSCapManifest(
            name: "test-component",
            version: "1.0.0",
            manifestDescription: "Test component",
            caps: [cap]
        )

        // Access name
        XCTAssertEqual(manifest.name, "test-component")
        // Access version
        XCTAssertEqual(manifest.version, "1.0.0")
        // Access description
        XCTAssertEqual(manifest.manifestDescription, "Test component")
        // Access caps
        XCTAssertEqual(manifest.caps.count, 1)
    }

    // MARK: - CSCapManifest With PageUrl Test

    // Additional test: CSCapManifest with pageUrl
    func test_csCapManifestWithPageUrl() throws {
        let manifest = CSCapManifest(
            name: "plugin-with-url",
            version: "1.0.0",
            manifestDescription: "Plugin with page URL",
            caps: []
        ).withPageUrl("https://example.com/plugin")

        XCTAssertEqual(manifest.pageUrl, "https://example.com/plugin")
    }
}
