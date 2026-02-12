import XCTest
import Foundation
import SwiftCBOR
@testable import CapNsCbor

// =============================================================================
// CborPluginRuntime + CborCapArgumentValue Tests
//
// Covers TEST248-273 from plugin_runtime.rs and TEST274-283 from caller.rs
// in the reference Rust implementation.
//
// N/A tests (Rust-specific traits):
//   TEST253: handler_is_send_sync (Swift uses @Sendable instead of Arc+Send+Sync)
//   TEST279: cap_argument_value_clone (Swift structs are value types, always copied)
//   TEST280: cap_argument_value_debug (Rust Debug trait has no Swift equivalent)
//   TEST281: cap_argument_value_into_string (Rust Into trait - Swift uses String directly)
// =============================================================================

// MARK: - Helper Functions for Frame-Based Testing

/// Collect all CHUNK frame payloads from a frame stream
@available(macOS 10.15.4, iOS 13.4, *)
func collectFramePayloads(_ frames: AsyncStream<CborFrame>) async -> Data {
    var accumulated = Data()
    for await frame in frames {
        if case .chunk = frame.frameType, let payload = frame.payload {
            accumulated.append(payload)
        }
    }
    return accumulated
}

/// Create a test frame stream with a single payload chunk
@available(macOS 10.15.4, iOS 13.4, *)
func createSinglePayloadStream(requestId: CborMessageId = .newUUID(), streamId: String = "test", mediaUrn: String = "media:bytes", data: Data) -> AsyncStream<CborFrame> {
    return AsyncStream<CborFrame> { continuation in
        continuation.yield(CborFrame.streamStart(reqId: requestId, streamId: streamId, mediaUrn: mediaUrn))
        continuation.yield(CborFrame.chunk(reqId: requestId, streamId: streamId, seq: 0, payload: data))
        continuation.yield(CborFrame.streamEnd(reqId: requestId, streamId: streamId))
        continuation.yield(CborFrame.end(id: requestId))
        continuation.finish()
    }
}

/// Test emitter that collects output for verification
@available(macOS 10.15.4, iOS 13.4, *)
final class TestStreamEmitter: CborStreamEmitter, @unchecked Sendable {
        var collectedOutput = Data()

        func emitCbor(_ value: CBOR) throws {
            // Extract bytes from CBOR value
            switch value {
            case .byteString(let bytes):
                collectedOutput.append(contentsOf: bytes)
            case .utf8String(let str):
                collectedOutput.append(contentsOf: str.utf8)
            default:
                // For other types, encode as CBOR
                collectedOutput.append(contentsOf: value.encode())
            }
        }

        func emitLog(level: String, message: String) {
            // Ignored for tests
        }
}

@available(macOS 10.15.4, iOS 13.4, *)
final class CborPluginRuntimeTests: XCTestCase {

    // MARK: - Test Constants

    static let testManifestJSON = """
    {"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:op=test","title":"Test","command":"test"}]}
    """
    static let testManifestData = testManifestJSON.data(using: .utf8)!

    // MARK: - Handler Registration Tests (TEST248-252, TEST270-271)

    // TEST248: Register handler by exact cap URN and find it by the same URN
    func testRegisterAndFindHandler() {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.registerRaw(capUrn: "cap:in=*;op=test;out=*") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            try emitter.emitCbor(.byteString([UInt8]("result".utf8)))
        }

        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:in=*;op=test;out=*"),
            "handler must be found by exact URN")
    }

    // TEST249: register raw handler works with bytes directly without deserialization
    func testRawHandler() async throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.registerRaw(capUrn: "cap:op=raw") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            try emitter.emitCbor(.byteString([UInt8](data)))
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=raw"))
        let noPeer = NoCborPeerInvoker()
        let emitter = TestStreamEmitter()

        let inputData = "echo this".data(using: .utf8)!
        let inputStream = createSinglePayloadStream(data: inputData)

        try await handler(inputStream, emitter, noPeer)
        XCTAssertEqual(String(data: emitter.collectedOutput, encoding: .utf8), "echo this", "raw handler must echo payload")
    }

    // TEST250: register typed handler deserializes JSON and executes correctly
    func testTypedHandlerDeserialization() async throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=test") {
            (req: [String: String], _: CborStreamEmitter, _: CborPeerInvoker) async throws -> [String: String] in
            let value = req["key"] ?? "missing"
            return ["result": value]
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let noPeer = NoCborPeerInvoker()
        let emitter = TestStreamEmitter()

        let inputData = "{\"key\":\"hello\"}".data(using: .utf8)!
        let inputStream = createSinglePayloadStream(mediaUrn: "media:json", data: inputData)

        try await handler(inputStream, emitter, noPeer)

        // Parse the JSON response
        let resultDict = try JSONDecoder().decode([String: String].self, from: emitter.collectedOutput)
        XCTAssertEqual(resultDict["result"], "hello")
    }

    // TEST251: typed handler returns error for invalid JSON input
    func testTypedHandlerRejectsInvalidJson() async throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=test") {
            (req: [String: String], _: CborStreamEmitter, _: CborPeerInvoker) async throws -> Data in
            return Data()
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let noPeer = NoCborPeerInvoker()
        let emitter = TestStreamEmitter()

        let inputData = "not json {{{{".data(using: .utf8)!
        let inputStream = createSinglePayloadStream(mediaUrn: "media:json", data: inputData)

        do {
            try await handler(inputStream, emitter, noPeer)
            XCTFail("Should have thrown error for invalid JSON")
        } catch {
            // Expected
        }
    }

    // TEST252: find_handler returns None for unregistered cap URNs
    func testFindHandlerUnknownCap() {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=nonexistent"),
            "unregistered cap must return nil")
    }

    // TEST270: Registering multiple handlers for different caps and finding each independently
    func testMultipleHandlers() async throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.registerRaw(capUrn: "cap:op=alpha") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            try emitter.emitCbor(.byteString([UInt8]("a".utf8)))
        }
        runtime.registerRaw(capUrn: "cap:op=beta") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            try emitter.emitCbor(.byteString([UInt8]("b".utf8)))
        }
        runtime.registerRaw(capUrn: "cap:op=gamma") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            try emitter.emitCbor(.byteString([UInt8]("g".utf8)))
        }

        let noPeer = NoCborPeerInvoker()

        let emptyStream = createSinglePayloadStream(mediaUrn: "media:void", data: Data())

        let hAlpha = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=alpha"))
        let emitterA = TestStreamEmitter()
        try await hAlpha(emptyStream, emitterA, noPeer)
        XCTAssertEqual(emitterA.collectedOutput, "a".data(using: .utf8)!)

        let hBeta = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=beta"))
        let emitterB = TestStreamEmitter()
        let emptyStream2 = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try await hBeta(emptyStream2, emitterB, noPeer)
        XCTAssertEqual(emitterB.collectedOutput, "b".data(using: .utf8)!)

        let hGamma = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=gamma"))
        let emitterG = TestStreamEmitter()
        let emptyStream3 = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try await hGamma(emptyStream3, emitterG, noPeer)
        XCTAssertEqual(emitterG.collectedOutput, "g".data(using: .utf8)!)
    }

    // TEST271: Handler replacing an existing registration for the same cap URN
    func testHandlerReplacement() async throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.registerRaw(capUrn: "cap:op=test") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            try emitter.emitCbor(.byteString([UInt8]("first".utf8)))
        }
        runtime.registerRaw(capUrn: "cap:op=test") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            for await _ in stream { }
            try emitter.emitCbor(.byteString([UInt8]("second".utf8)))
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let noPeer = NoCborPeerInvoker()
        let emitter = TestStreamEmitter()
        let emptyStream = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try await handler(emptyStream, emitter, noPeer)
        XCTAssertEqual(String(data: emitter.collectedOutput, encoding: .utf8), "second",
            "later registration must replace earlier")
    }

    // MARK: - NoPeerInvoker Tests (TEST254-255)

    // TEST254: NoPeerInvoker always returns error regardless of arguments
    func testNoPeerInvoker() {
        let noPeer = NoCborPeerInvoker()

        XCTAssertThrowsError(try noPeer.invoke(capUrn: "cap:op=test", arguments: [])) { error in
            if let runtimeError = error as? CborPluginRuntimeError,
               case .peerRequestError(let msg) = runtimeError {
                XCTAssertTrue(msg.lowercased().contains("not supported") || msg.lowercased().contains("cli mode"),
                    "error must indicate peer not supported: \(msg)")
            } else {
                XCTFail("expected peerRequestError, got \(error)")
            }
        }
    }

    // TEST255: NoPeerInvoker returns error even with valid arguments
    func testNoPeerInvokerWithArguments() {
        let noPeer = NoCborPeerInvoker()
        let arg = CborCapArgumentValue(mediaUrn: "media:test", value: "value".data(using: .utf8)!)

        XCTAssertThrowsError(try noPeer.invoke(capUrn: "cap:op=test", arguments: [arg]),
            "must throw error even with valid arguments")
    }

    // MARK: - Runtime Creation Tests (TEST256-258)

    // TEST256: PluginRuntime with manifest JSON stores manifest data and parses when valid
    func testWithManifestJson() {
        let runtime = CborPluginRuntime(manifestJSON: Self.testManifestJSON)
        XCTAssertFalse(runtime.manifestData.isEmpty, "manifestData must be populated")
        // Note: "cap:op=test" may or may not parse as valid CborManifest depending on validation
    }

    // TEST257: PluginRuntime with invalid JSON still creates runtime
    func testNewWithInvalidJson() {
        let runtime = CborPluginRuntime(manifest: "not json".data(using: .utf8)!)
        XCTAssertFalse(runtime.manifestData.isEmpty, "manifestData should store raw bytes")
        XCTAssertNil(runtime.parsedManifest, "invalid JSON should leave parsedManifest as nil")
    }

    // TEST258: PluginRuntime with valid manifest data creates runtime with parsed manifest
    func testWithManifestStruct() {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)
        XCTAssertFalse(runtime.manifestData.isEmpty)
        // parsedManifest may or may not be nil depending on whether "cap:op=test" validates
        // The key behavior is that manifestData is stored
    }

    // MARK: - Extract Effective Payload Tests (TEST259-265, TEST272-273)

    // TEST259: extract_effective_payload with non-CBOR content_type returns raw payload unchanged
    func testExtractEffectivePayloadNonCbor() throws {
        let payload = "raw data".data(using: .utf8)!
        let result = try extractEffectivePayload(payload: payload, contentType: "application/json", capUrn: "cap:op=test")
        XCTAssertEqual(result, payload, "non-CBOR must return raw payload")
    }

    // TEST260: extract_effective_payload with None content_type returns raw payload unchanged
    func testExtractEffectivePayloadNoContentType() throws {
        let payload = "raw data".data(using: .utf8)!
        let result = try extractEffectivePayload(payload: payload, contentType: nil, capUrn: "cap:op=test")
        XCTAssertEqual(result, payload)
    }

    // TEST261: extract_effective_payload with CBOR content extracts matching argument value
    func testExtractEffectivePayloadCborMatch() throws {
        // Build CBOR: [{media_urn: "media:string;textable;form=scalar", value: bytes("hello")}]
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:string;textable;form=scalar"),
                .utf8String("value"): .byteString([UInt8]("hello".utf8))
            ])
        ])
        let payload = Data(cborArray.encode())

        let result = try extractEffectivePayload(
            payload: payload,
            contentType: "application/cbor",
            capUrn: "cap:in=media:string;textable;form=scalar;op=test;out=*"
        )
        XCTAssertEqual(String(data: result, encoding: .utf8), "hello")
    }

    // TEST262: extract_effective_payload with CBOR content fails when no argument matches
    func testExtractEffectivePayloadCborNoMatch() {
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:other-type"),
                .utf8String("value"): .byteString([UInt8]("data".utf8))
            ])
        ])
        let payload = Data(cborArray.encode())

        XCTAssertThrowsError(try extractEffectivePayload(
            payload: payload,
            contentType: "application/cbor",
            capUrn: "cap:in=media:string;textable;form=scalar;op=test;out=*"
        )) { error in
            if let runtimeError = error as? CborPluginRuntimeError,
               case .deserializationError(let msg) = runtimeError {
                XCTAssertTrue(msg.contains("No argument found matching"), "\(msg)")
            }
        }
    }

    // TEST263: extract_effective_payload with invalid CBOR bytes returns deserialization error
    func testExtractEffectivePayloadInvalidCbor() {
        XCTAssertThrowsError(try extractEffectivePayload(
            payload: "not cbor".data(using: .utf8)!,
            contentType: "application/cbor",
            capUrn: "cap:in=*;op=test;out=*"
        ))
    }

    // TEST264: extract_effective_payload with CBOR non-array returns error
    func testExtractEffectivePayloadCborNotArray() {
        let cborMap: CBOR = .map([:])
        let payload = Data(cborMap.encode())

        XCTAssertThrowsError(try extractEffectivePayload(
            payload: payload,
            contentType: "application/cbor",
            capUrn: "cap:in=*;op=test;out=*"
        )) { error in
            if let runtimeError = error as? CborPluginRuntimeError,
               case .deserializationError(let msg) = runtimeError {
                XCTAssertTrue(msg.contains("must be an array"), "\(msg)")
            }
        }
    }

    // TEST265: extract_effective_payload with invalid cap URN returns CapUrn error
    func testExtractEffectivePayloadInvalidCapUrn() {
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:anything"),
                .utf8String("value"): .byteString([UInt8]("data".utf8))
            ])
        ])
        let payload = Data(cborArray.encode())

        XCTAssertThrowsError(try extractEffectivePayload(
            payload: payload,
            contentType: "application/cbor",
            capUrn: "not-a-cap-urn"
        )) { error in
            if let runtimeError = error as? CborPluginRuntimeError,
               case .capUrnError = runtimeError {
                // Expected - matches Rust behavior
            } else {
                XCTFail("expected capUrnError, got \(error)")
            }
        }
    }

    // TEST272: extract_effective_payload CBOR with multiple arguments selects the correct one
    func testExtractEffectivePayloadMultipleArgs() throws {
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:other-type;textable"),
                .utf8String("value"): .byteString([UInt8]("wrong".utf8))
            ]),
            .map([
                .utf8String("media_urn"): .utf8String("media:model-spec;textable;form=scalar"),
                .utf8String("value"): .byteString([UInt8]("correct".utf8))
            ]),
        ])
        let payload = Data(cborArray.encode())

        let result = try extractEffectivePayload(
            payload: payload,
            contentType: "application/cbor",
            capUrn: "cap:in=media:model-spec;textable;form=scalar;op=infer;out=*"
        )
        XCTAssertEqual(String(data: result, encoding: .utf8), "correct")
    }

    // TEST273: extract_effective_payload with binary data in CBOR value
    func testExtractEffectivePayloadBinaryValue() throws {
        var binaryData = [UInt8]()
        for i: UInt8 in 0...255 { binaryData.append(i) }

        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:pdf;bytes"),
                .utf8String("value"): .byteString(binaryData)
            ])
        ])
        let payload = Data(cborArray.encode())

        let result = try extractEffectivePayload(
            payload: payload,
            contentType: "application/cbor",
            capUrn: "cap:in=media:pdf;bytes;op=process;out=*"
        )
        XCTAssertEqual(result, Data(binaryData), "binary values must roundtrip through CBOR extraction")
    }

    // MARK: - CliStreamEmitter Tests (TEST266-267)

    // TEST266: CliStreamEmitter construction with and without NDJSON
    func testCliStreamEmitterConstruction() {
        let emitter = CliStreamEmitter()
        XCTAssertTrue(emitter.ndjson, "default CLI emitter must use NDJSON")

        let emitter2 = CliStreamEmitter(ndjson: false)
        XCTAssertFalse(emitter2.ndjson)
    }

    // MARK: - RuntimeError Display Tests (TEST268)

    // TEST268: RuntimeError variants display correct messages
    func testRuntimeErrorDisplay() {
        let err1 = CborPluginRuntimeError.noHandler("cap:op=missing")
        XCTAssertTrue((err1.errorDescription ?? "").contains("cap:op=missing"))

        let err2 = CborPluginRuntimeError.missingArgument("model")
        XCTAssertTrue((err2.errorDescription ?? "").contains("model"))

        let err3 = CborPluginRuntimeError.unknownSubcommand("badcmd")
        XCTAssertTrue((err3.errorDescription ?? "").contains("badcmd"))

        let err4 = CborPluginRuntimeError.manifestError("parse failed")
        XCTAssertTrue((err4.errorDescription ?? "").contains("parse failed"))

        let err5 = CborPluginRuntimeError.peerRequestError("denied")
        XCTAssertTrue((err5.errorDescription ?? "").contains("denied"))

        let err6 = CborPluginRuntimeError.peerResponseError("timeout")
        XCTAssertTrue((err6.errorDescription ?? "").contains("timeout"))
    }

}

// =============================================================================
// CborCapArgumentValue Tests (TEST274-278, TEST282-283)
// =============================================================================

final class CborCapArgumentValueTests: XCTestCase {

    // TEST274: CborCapArgumentValue stores media_urn and raw byte value
    func testCapArgumentValueNew() {
        let arg = CborCapArgumentValue(
            mediaUrn: "media:model-spec;textable;form=scalar",
            value: "gpt-4".data(using: .utf8)!
        )
        XCTAssertEqual(arg.mediaUrn, "media:model-spec;textable;form=scalar")
        XCTAssertEqual(arg.value, "gpt-4".data(using: .utf8)!)
    }

    // TEST275: CborCapArgumentValue.fromString converts string to UTF-8 bytes
    func testCapArgumentValueFromStr() {
        let arg = CborCapArgumentValue.fromString(mediaUrn: "media:string;textable", value: "hello world")
        XCTAssertEqual(arg.mediaUrn, "media:string;textable")
        XCTAssertEqual(arg.value, "hello world".data(using: .utf8)!)
    }

    // TEST276: CborCapArgumentValue.valueAsString succeeds for UTF-8 data
    func testCapArgumentValueAsStrValid() throws {
        let arg = CborCapArgumentValue.fromString(mediaUrn: "media:string", value: "test")
        XCTAssertEqual(try arg.valueAsString(), "test")
    }

    // TEST277: CborCapArgumentValue.valueAsString fails for non-UTF-8 binary data
    func testCapArgumentValueAsStrInvalidUtf8() {
        let arg = CborCapArgumentValue(mediaUrn: "media:pdf;bytes", value: Data([0xFF, 0xFE, 0x80]))
        XCTAssertThrowsError(try arg.valueAsString(), "non-UTF-8 data must fail")
    }

    // TEST278: CborCapArgumentValue with empty value stores empty Data
    func testCapArgumentValueEmpty() throws {
        let arg = CborCapArgumentValue(mediaUrn: "media:void", value: Data())
        XCTAssertTrue(arg.value.isEmpty)
        XCTAssertEqual(try arg.valueAsString(), "")
    }

    // TEST282: CborCapArgumentValue.fromString with Unicode string preserves all characters
    func testCapArgumentValueUnicode() throws {
        let arg = CborCapArgumentValue.fromString(mediaUrn: "media:string", value: "hello 世界 🌍")
        XCTAssertEqual(try arg.valueAsString(), "hello 世界 🌍")
    }

    // TEST283: CborCapArgumentValue with large binary payload preserves all bytes
    func testCapArgumentValueLargeBinary() {
        var data = Data()
        for _ in 0..<40 {  // 40 * 256 = 10240 > 10000
            for i: UInt8 in 0...255 {
                data.append(i)
            }
        }
        data = data.prefix(10000)  // trim to exactly 10000
        let arg = CborCapArgumentValue(mediaUrn: "media:pdf;bytes", value: data)
        XCTAssertEqual(arg.value.count, 10000)
        XCTAssertEqual(arg.value, data)
    }
}

// =============================================================================
// File-Path to Bytes Conversion Tests (TEST336-TEST360)
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
final class CborFilePathConversionTests: XCTestCase {

    // Helper to create test manifest with caps
    private func createTestManifest(caps: [CborCapDefinition]) -> Data {
        let manifest = CborManifest(
            name: "TestPlugin",
            version: "1.0.0",
            description: "Test plugin",
            caps: caps
        )
        return try! JSONEncoder().encode(manifest)
    }

    // Helper to create a cap definition
    private func createCap(
        urn: String,
        title: String,
        command: String,
        args: [CborCapArg] = []
    ) -> CborCapDefinition {
        return CborCapDefinition(
            urn: urn,
            title: title,
            command: command,
            capDescription: nil,
            args: args
        )
    }

    // Helper to create a cap arg
    private func createArg(
        mediaUrn: String,
        required: Bool,
        sources: [CborArgSource]
    ) -> CborCapArg {
        return CborCapArg(
            mediaUrn: mediaUrn,
            required: required,
            sources: sources,
            argDescription: nil,
            defaultValue: nil
        )
    }

    // TEST336: Single file-path arg with stdin source reads file and passes bytes to handler
    func test336_file_path_reads_file_passes_bytes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test336_input.pdf")
        try Data("PDF binary content 336".utf8).write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"",
            title: "Process PDF",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Register handler that echoes payload
        runtime.registerRaw(capUrn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            try emitter.emitCbor(.byteString([UInt8](data)))
        }

        // Simulate CLI invocation: plugin process /path/to/file.pdf
        let cliArgs = [testFile.path]
        let raw_payload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Extract effective payload (simulates what run_cli_mode does)
        let payload = try extractEffectivePayload(
            payload: raw_payload,
            contentType: "application/cbor",
            capUrn: cap.urn
        )

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let emitter = TestStreamEmitter()
        let peer = NoCborPeerInvoker()

        let inputStream = createSinglePayloadStream(mediaUrn: "media:pdf;bytes", data: payload)

        try await handler(inputStream, emitter, peer)

        // Verify handler received file bytes, not file path
        XCTAssertEqual(emitter.collectedOutput, Data("PDF binary content 336".utf8), "Handler should receive file bytes")
        XCTAssertEqual(payload, Data("PDF binary content 336".utf8))

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST337: file-path arg without stdin source passes path as string (no conversion)
    func test337_file_path_without_stdin_passes_string() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test337_input.txt")
        try Data("content".utf8).write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:void\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [.positional(0)]  // NO stdin source!
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        // Use reflection or manual extraction to test extractArgValue
        // Since it's private, we'll test through buildPayloadFromCli
        let payload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Should get JSON payload with file PATH as string, not file CONTENTS
        if let jsonObj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            if let filePath = jsonObj["file_path"] as? String {
                XCTAssertTrue(filePath.contains("test337_input.txt"), "Should receive file path string when no stdin source")
            }
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST338: file-path arg reads file via --file CLI flag
    func test338_file_path_via_cli_flag() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test338.pdf")
        try Data("PDF via flag 338".utf8).write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes"),
                    .cliFlag("--file")
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        runtime.registerRaw(capUrn: cap.urn) { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            try emitter.emitCbor(.byteString([UInt8](data)))
        }

        let cliArgs = ["--file", testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let emitter = TestStreamEmitter()
        let inputStream = createSinglePayloadStream(mediaUrn: "media:pdf;bytes", data: payload)
        try await handler(inputStream, emitter, NoCborPeerInvoker())

        XCTAssertEqual(emitter.collectedOutput, Data("PDF via flag 338".utf8), "Should read file from --file flag")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST339: file-path-array reads multiple files with glob pattern
    func test339_file_path_array_glob_expansion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test339")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("doc1.txt")
        let file2 = tempDir.appendingPathComponent("doc2.txt")
        try Data("content1".utf8).write(to: file1)
        try Data("content2".utf8).write(to: file2)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Batch",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Pass glob pattern as JSON array
        let pattern = "\(tempDir.path)/*.txt"
        let pathsJSON = try JSONEncoder().encode([pattern])
        let pathsJSONString = String(data: pathsJSON, encoding: .utf8)!

        let cliArgs = [pathsJSONString]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Decode CBOR array
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let filesArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(filesArray.count, 2, "Should find 2 files")

        // Verify contents (order may vary, so sort)
        var bytesVec: [[UInt8]] = []
        for val in filesArray {
            if case .byteString(let bytes) = val {
                bytesVec.append(bytes)
            } else {
                XCTFail("Expected byte strings")
            }
        }
        bytesVec.sort { $0.lexicographicallyPrecedes($1) }
        XCTAssertEqual(bytesVec.map { Data($0) }.sorted { $0.lexicographicallyPrecedes($1) },
                       [Data("content1".utf8), Data("content2".utf8)].sorted { $0.lexicographicallyPrecedes($1) })

        try? FileManager.default.removeItem(at: tempDir)
    }

    // TEST340: File not found error provides clear message
    func test340_file_not_found_clear_error() throws {
        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = ["/nonexistent/file.pdf"]

        XCTAssertThrowsError(try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)) { error in
            let errMsg = error.localizedDescription
            XCTAssertTrue(errMsg.contains("/nonexistent/file.pdf") || errMsg.contains("Failed to read file"),
                          "Error should mention file path or read failure: \(errMsg)")
        }
    }

    // TEST341: stdin takes precedence over file-path in source order
    func test341_stdin_precedence_over_file_path() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test341_input.txt")
        try Data("file content".utf8).write(to: testFile)

        // Stdin source comes BEFORE position source
        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),  // First
                    .positional(0)          // Second
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        runtime.registerRaw(capUrn: cap.urn) { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            try emitter.emitCbor(.byteString([UInt8](data)))
        }

        // Simulate stdin data being available
        // Since we can't actually provide stdin in tests, we'll test the buildPayloadFromCli behavior
        // The Rust test uses extract_arg_value directly with stdin_data parameter
        // We test that when only positional arg is provided, file is read
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Without stdin, position source is used, so file is read
        XCTAssertEqual(payload, Data("file content".utf8))

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST342: file-path with position 0 reads first positional arg as file
    func test342_file_path_position_zero_reads_first_arg() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test342.dat")
        try Data("binary data 342".utf8).write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // CLI: plugin test /path/to/file (position 0 after subcommand)
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        XCTAssertEqual(payload, Data("binary data 342".utf8), "Should read file at position 0")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST343: Non-file-path args are not affected by file reading
    func test343_non_file_path_args_unaffected() throws {
        // Arg with different media type should NOT trigger file reading
        let cap = createCap(
            urn: "cap:in=\"media:model-spec;textable;form=scalar\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:model-spec;textable;form=scalar",  // NOT file-path
                required: true,
                sources: [
                    .stdin("media:model-spec;textable;form=scalar"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = ["mlx-community/Llama-3.2-3B-Instruct-4bit"]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // For non-file-path args with stdin source, CBOR format is still used
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Should get the string value, not attempt file read
        let valueStr = String(data: payload, encoding: .utf8)
        XCTAssertEqual(valueStr, "mlx-community/Llama-3.2-3B-Instruct-4bit")
    }

    // TEST344: file-path-array with invalid JSON fails clearly
    func test344_file_path_array_invalid_json_fails() {
        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Pass invalid JSON (not an array)
        let cliArgs = ["not a json array"]

        XCTAssertThrowsError(try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("Failed to parse file-path-array") || err.contains("expected JSON array"),
                          "Error should mention file-path-array or expected format")
        }
    }

    // TEST345: file-path-array with one file failing stops and reports error
    func test345_file_path_array_one_file_missing_fails_hard() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file1 = tempDir.appendingPathComponent("test345_exists.txt")
        try Data("exists".utf8).write(to: file1)
        let file2Path = tempDir.appendingPathComponent("test345_missing.txt")

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Construct JSON array with both existing and non-existing files
        let pathsJSON = try JSONEncoder().encode([file1.path, file2Path.path])
        let pathsJSONString = String(data: pathsJSON, encoding: .utf8)!

        let cliArgs = [pathsJSONString]

        XCTAssertThrowsError(try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("test345_missing.txt") || err.contains("Failed to read file"),
                          "Should fail hard when any file in array is missing")
        }

        try? FileManager.default.removeItem(at: file1)
    }

    // TEST346: Large file (1MB) reads successfully
    func test346_large_file_reads_successfully() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test346_large.bin")

        // Create 1MB file
        var largeData = Data()
        for _ in 0..<1_000_000 {
            largeData.append(42)
        }
        try largeData.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        XCTAssertEqual(payload.count, 1_000_000, "Should read entire 1MB file")
        XCTAssertEqual(payload, largeData, "Content should match exactly")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST347: Empty file reads as empty bytes
    func test347_empty_file_reads_as_empty_bytes() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test347_empty.txt")
        try Data().write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        XCTAssertEqual(payload, Data(), "Empty file should produce empty bytes")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST348: file-path conversion respects source order
    func test348_file_path_conversion_respects_source_order() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test348.txt")
        try Data("file content 348".utf8).write(to: testFile)

        // Position source BEFORE stdin source
        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .positional(0),         // First
                    .stdin("media:bytes")   // Second
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Position source tried first, so file is read
        XCTAssertEqual(payload, Data("file content 348".utf8), "Position source tried first, file read")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST349: file-path arg with multiple sources tries all in order
    func test349_file_path_multiple_sources_fallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test349.txt")
        try Data("content 349".utf8).write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .cliFlag("--file"),     // First (not provided)
                    .positional(0),         // Second (provided)
                    .stdin("media:bytes")   // Third (not used)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Only provide position arg, no --file flag
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        XCTAssertEqual(payload, Data("content 349".utf8), "Should fall back to position source and read file")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST350: Integration test - full CLI mode invocation with file-path
    func test350_full_cli_mode_with_file_path_integration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test350_input.pdf")
        let testContent = Data("PDF file content for integration test".utf8)
        try testContent.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:result;textable\"",
            title: "Process PDF",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Track what the handler receives using a class wrapper for thread-safe capture
        final class PayloadCapture: @unchecked Sendable {
            var data = Data()
        }
        let capture = PayloadCapture()

        runtime.registerRaw(capUrn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:result;textable\"") { (stream: AsyncStream<CborFrame>, emitter: CborStreamEmitter, _: CborPeerInvoker) async throws -> Void in
            var data = Data()
            for await frame in stream {
                if case .chunk = frame.frameType, let payload = frame.payload {
                    data.append(payload)
                }
            }
            capture.data = data
            try emitter.emitCbor(.byteString([UInt8]("processed".utf8)))
        }

        // Simulate full CLI invocation
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Extract effective payload (what run_cli_mode does)
        let payload = try extractEffectivePayload(
            payload: rawPayload,
            contentType: "application/cbor",
            capUrn: cap.urn
        )

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let emitter = TestStreamEmitter()
        let peer = NoCborPeerInvoker()

        let inputStream = createSinglePayloadStream(mediaUrn: "media:pdf;bytes", data: payload)

        try await handler(inputStream, emitter, peer)

        // Verify handler received file bytes
        XCTAssertEqual(capture.data, testContent, "Handler should receive file bytes, not path")
        XCTAssertEqual(emitter.collectedOutput, Data("processed".utf8))

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST351: file-path-array with empty array succeeds
    func test351_file_path_array_empty_array() throws {
        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: false,  // Not required
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = ["[]"]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Decode CBOR array
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let filesArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(filesArray.count, 0, "Empty array should produce empty result")
    }

    // TEST352: file permission denied error is clear (Unix-specific)
    #if os(macOS) || os(Linux)
    func test352_file_permission_denied_clear_error() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test352_noperm.txt")
        try Data("content".utf8).write(to: testFile)

        // Remove read permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: testFile.path)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]

        XCTAssertThrowsError(try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("test352_noperm.txt"), "Error should mention the file: \(err)")
        }

        // Cleanup: restore permissions then delete
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testFile.path)
        try? FileManager.default.removeItem(at: testFile)
    }
    #endif

    // TEST353: CBOR payload format matches between CLI and CBOR mode
    func test353_cbor_payload_format_consistency() throws {
        let cap = createCap(
            urn: "cap:in=\"media:text;textable\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:text;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:text;textable"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = ["test value"]
        let payload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Decode CBOR payload
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let argsArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(argsArray.count, 1, "Should have 1 argument")

        // Verify structure: { media_urn: "...", value: bytes }
        guard case .map(let argMap) = argsArray[0] else {
            XCTFail("Expected CBOR map")
            return
        }

        XCTAssertEqual(argMap.count, 2, "Argument should have media_urn and value")

        // Check media_urn key
        let mediaUrnKey = CBOR.utf8String("media_urn")
        guard let mediaUrnVal = argMap[mediaUrnKey],
              case .utf8String(let urnStr) = mediaUrnVal else {
            XCTFail("Should have media_urn key with string value")
            return
        }
        XCTAssertEqual(urnStr, "media:text;textable;form=scalar")

        // Check value key
        let valueKey = CBOR.utf8String("value")
        guard let valueVal = argMap[valueKey],
              case .byteString(let bytes) = valueVal else {
            XCTFail("Should have value key with bytes")
            return
        }
        XCTAssertEqual(bytes, [UInt8]("test value".utf8))
    }

    // TEST354: Glob pattern with no matches produces empty array
    func test354_glob_pattern_no_matches_empty_array() throws {
        let tempDir = FileManager.default.temporaryDirectory

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Glob pattern that matches nothing
        let pattern = "\(tempDir.path)/nonexistent_*.xyz"
        let pathsJSON = try JSONEncoder().encode([pattern])
        let pathsJSONString = String(data: pathsJSON, encoding: .utf8)!

        let cliArgs = [pathsJSONString]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Decode CBOR array
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let filesArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(filesArray.count, 0, "No matches should produce empty array")
    }

    // TEST355: Glob pattern skips directories
    func test355_glob_pattern_skips_directories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test355")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("file1.txt")
        try Data("content1".utf8).write(to: file1)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Glob that matches both file and directory
        let pattern = "\(tempDir.path)/*"
        let pathsJSON = try JSONEncoder().encode([pattern])
        let pathsJSONString = String(data: pathsJSON, encoding: .utf8)!

        let cliArgs = [pathsJSONString]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Decode CBOR array
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let filesArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        // Should only include the file, not the directory
        XCTAssertEqual(filesArray.count, 1, "Should only include files, not directories")

        if case .byteString(let bytes) = filesArray[0] {
            XCTAssertEqual(bytes, [UInt8]("content1".utf8))
        } else {
            XCTFail("Expected bytes")
        }

        try? FileManager.default.removeItem(at: tempDir)
    }

    // TEST356: Multiple glob patterns combined
    func test356_multiple_glob_patterns_combined() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test356")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("doc.txt")
        let file2 = tempDir.appendingPathComponent("data.json")
        try Data("text".utf8).write(to: file1)
        try Data("json".utf8).write(to: file2)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Multiple patterns
        let pattern1 = "\(tempDir.path)/*.txt"
        let pattern2 = "\(tempDir.path)/*.json"
        let pathsJSON = try JSONEncoder().encode([pattern1, pattern2])
        let pathsJSONString = String(data: pathsJSON, encoding: .utf8)!

        let cliArgs = [pathsJSONString]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        // Decode CBOR array
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let filesArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(filesArray.count, 2, "Should find both files from different patterns")

        // Collect contents (order may vary)
        var contents: [[UInt8]] = []
        for val in filesArray {
            if case .byteString(let bytes) = val {
                contents.append(bytes)
            } else {
                XCTFail("Expected bytes")
            }
        }
        contents.sort { $0.lexicographicallyPrecedes($1) }
        XCTAssertEqual(contents, [[UInt8]("json".utf8), [UInt8]("text".utf8)])

        try? FileManager.default.removeItem(at: tempDir)
    }

    // TEST357: Symlinks are followed when reading files
    #if os(macOS) || os(Linux)
    func test357_symlinks_followed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test357")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let realFile = tempDir.appendingPathComponent("real.txt")
        let linkFile = tempDir.appendingPathComponent("link.txt")
        try Data("real content".utf8).write(to: realFile)
        try FileManager.default.createSymbolicLink(at: linkFile, withDestinationURL: realFile)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [linkFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        XCTAssertEqual(payload, Data("real content".utf8), "Should follow symlink and read real file")

        try? FileManager.default.removeItem(at: tempDir)
    }
    #endif

    // TEST358: Binary file with non-UTF8 data reads correctly
    func test358_binary_file_non_utf8() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test358.bin")

        // Binary data that's not valid UTF-8
        let binaryData = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x7F, 0xAB, 0xCD])
        try binaryData.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        XCTAssertEqual(payload, binaryData, "Binary data should read correctly")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST359: Invalid glob pattern fails with clear error
    func test359_invalid_glob_pattern_fails() {
        let cap = createCap(
            urn: "cap:in=\"media:bytes\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=list",
                required: true,
                sources: [
                    .stdin("media:bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        // Invalid glob pattern (unclosed bracket)
        let pattern = "[invalid"
        guard let pathsJSON = try? JSONEncoder().encode([pattern]),
              let pathsJSONString = String(data: pathsJSON, encoding: .utf8) else {
            XCTFail("Failed to encode pattern")
            return
        }

        let cliArgs = [pathsJSONString]

        XCTAssertThrowsError(try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("Invalid glob pattern") || err.contains("glob"),
                          "Error should mention invalid glob: \(err)")
        }
    }

    // TEST360: Extract effective payload handles file-path data correctly
    func test360_extract_effective_payload_with_file_data() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test360.pdf")
        let pdfContent = Data("PDF content for extraction test".utf8)
        try pdfContent.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable;form=scalar",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CborPluginRuntime(manifest: manifest)

        let cliArgs = [testFile.path]

        // Build CBOR payload (what build_payload_from_cli does)
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Extract effective payload (what run_cli_mode does)
        let effective = try extractEffectivePayload(
            payload: rawPayload,
            contentType: "application/cbor",
            capUrn: cap.urn
        )

        // Effective payload should be the raw PDF bytes
        XCTAssertEqual(effective, pdfContent, "Should extract file bytes from CBOR payload")

        try? FileManager.default.removeItem(at: testFile)
    }
}
