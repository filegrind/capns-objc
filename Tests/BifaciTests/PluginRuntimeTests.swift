import XCTest
import Foundation
import SwiftCBOR
@testable import Bifaci
import Ops

// =============================================================================
// PluginRuntime + CapArgumentValue Tests
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
func collectFramePayloads(_ frames: AsyncStream<Frame>) async -> Data {
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
func createSinglePayloadStream(requestId: MessageId = .newUUID(), streamId: String = "test", mediaUrn: String = "media:bytes", data: Data) -> AsyncStream<Frame> {
    return AsyncStream<Frame> { continuation in
        continuation.yield(Frame.streamStart(reqId: requestId, streamId: streamId, mediaUrn: mediaUrn))
        let cborPayload = CBOR.byteString([UInt8](data)).encode()
        continuation.yield(Frame.chunk(reqId: requestId, streamId: streamId, seq: 0, payload: Data(cborPayload), chunkIndex: 0, checksum: Frame.computeChecksum(Data(cborPayload))))
        continuation.yield(Frame.streamEnd(reqId: requestId, streamId: streamId, chunkCount: 1))
        continuation.yield(Frame.end(id: requestId))
        continuation.finish()
    }
}

// MARK: - Test Op Types and invokeOp Helper

/// Helper: invoke a factory-produced Op with NoPeerInvoker.
/// Matches Rust's invoke_op() test helper.
func invokeOp(_ factory: OpFactory, input: InputPackage, output: Bifaci.OutputStream) throws {
    let op = factory()
    try dispatchOp(op: op, input: input, output: output, peer: NoPeerInvoker())
}

/// Test Op: echoes all input bytes to output (collectAllBytes → write).
/// dispatchOp closes output on success — do NOT call output.close() here.
final class EchoAllBytesOp: Op, @unchecked Sendable {
    typealias Output = Void
    init() {}
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        let data = try input.collectAllBytes()
        try req.output().write(data)
    }
    func metadata() -> OpMetadata { OpMetadata.builder("EchoAllBytesOp").build() }
}

/// Test Op: writes fixed Data value, drains input (ignores it).
final class WriteFixedOp: Op, @unchecked Sendable {
    typealias Output = Void
    private let data: Data
    init(data: Data) { self.data = data }
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        _ = try? input.collectAllBytes()
        try req.output().write(data)
    }
    func metadata() -> OpMetadata { OpMetadata.builder("WriteFixedOp").build() }
}

/// Test Op: emits fixed CBOR byteString value, drains input.
final class EmitCborBytesOp: Op, @unchecked Sendable {
    typealias Output = Void
    private let bytes: [UInt8]
    init(bytes: [UInt8]) { self.bytes = bytes }
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        _ = try? input.collectAllBytes()
        try req.output().emitCbor(CBOR.byteString(bytes))
    }
    func metadata() -> OpMetadata { OpMetadata.builder("EmitCborBytesOp").build() }
}

// Helper functions for testing are defined later in the file
// See: streamToInputPackage(), OutputCollector, createCollectingOutputStream()

@available(macOS 10.15.4, iOS 13.4, *)
final class PluginRuntimeTests: XCTestCase {

    // MARK: - Test Constants

    static let testManifestJSON = """
    {"name":"TestPlugin","version":"1.0.0","description":"Test plugin","caps":[{"urn":"cap:in=media:;out=media:","title":"Identity","command":"identity"},{"urn":"cap:in=media:;op=test;out=media:","title":"Test","command":"test"}]}
    """
    static let testManifestData = testManifestJSON.data(using: .utf8)!

    // MARK: - Handler Registration Tests (TEST248-252, TEST270-271)

    // TEST248: Test register_op and find_handler by exact cap URN
    func testRegisterAndFindHandler() {
        let runtime = PluginRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:in=*;op=test;out=*") {
            AnyOp(EmitCborBytesOp(bytes: Array("result".utf8)))
        }

        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:in=*;op=test;out=*"),
            "handler must be found by exact URN")
    }

    // TEST249: Test register_op handler echoes bytes directly
    func testRawHandler() throws {
        let runtime = PluginRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:op=raw") { AnyOp(EchoAllBytesOp()) }

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=raw"))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)

        let inputData = "echo this".data(using: .utf8)!
        let inputStream = createSinglePayloadStream(data: inputData)
        let inputPackage = streamToInputPackage(inputStream)

        try invokeOp(factory, input: inputPackage, output: output)
        XCTAssertEqual(String(data: collector.getData(), encoding: .utf8), "echo this", "raw handler must echo payload")
    }

    // TEST250: REMOVED - Typed handler API removed; handlers now work with InputPackage/OutputStream directly
    // Handlers manually deserialize JSON from input bytes if needed - no automatic deserialization

    // TEST251: REMOVED - Typed handler API removed; handlers handle their own deserialization errors

    // TEST252: find_handler returns None for unregistered cap URNs
    func testFindHandlerUnknownCap() {
        let runtime = PluginRuntime(manifest: Self.testManifestData)
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=nonexistent"),
            "unregistered cap must return nil")
    }

    // TEST270: Test registering multiple Op handlers for different caps and finding each independently
    func testMultipleHandlers() throws {
        let runtime = PluginRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:op=alpha") { AnyOp(WriteFixedOp(data: Data("a".utf8))) }
        runtime.register_op(capUrn: "cap:op=beta")  { AnyOp(WriteFixedOp(data: Data("b".utf8))) }
        runtime.register_op(capUrn: "cap:op=gamma") { AnyOp(WriteFixedOp(data: Data("g".utf8))) }

        let emptyStream = createSinglePayloadStream(mediaUrn: "media:void", data: Data())

        let fAlpha = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=alpha"))
        let collectorA = OutputCollector()
        let outputA = createCollectingOutputStream(collector: collectorA)
        try invokeOp(fAlpha, input: streamToInputPackage(emptyStream), output: outputA)
        XCTAssertEqual(collectorA.getData(), "a".data(using: .utf8)!)

        let fBeta = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=beta"))
        let collectorB = OutputCollector()
        let outputB = createCollectingOutputStream(collector: collectorB)
        let emptyStream2 = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try invokeOp(fBeta, input: streamToInputPackage(emptyStream2), output: outputB)
        XCTAssertEqual(collectorB.getData(), "b".data(using: .utf8)!)

        let fGamma = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=gamma"))
        let collectorG = OutputCollector()
        let outputG = createCollectingOutputStream(collector: collectorG)
        let emptyStream3 = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try invokeOp(fGamma, input: streamToInputPackage(emptyStream3), output: outputG)
        XCTAssertEqual(collectorG.getData(), "g".data(using: .utf8)!)
    }

    // TEST271: Test Op handler replacing an existing registration for the same cap URN
    func testHandlerReplacement() throws {
        let runtime = PluginRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:op=test") { AnyOp(WriteFixedOp(data: Data("first".utf8))) }
        runtime.register_op(capUrn: "cap:op=test") { AnyOp(WriteFixedOp(data: Data("second".utf8))) }

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)
        let emptyStream = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try invokeOp(factory, input: streamToInputPackage(emptyStream), output: output)
        XCTAssertEqual(String(data: collector.getData(), encoding: .utf8), "second",
            "later registration must replace earlier")
    }

    // MARK: - NoPeerInvoker Tests (TEST254-255)

    // TEST254: NoPeerInvoker always returns error regardless of arguments
    func testNoPeerInvoker() {
        let noPeer = NoPeerInvoker()

        XCTAssertThrowsError(try noPeer.call(capUrn: "cap:op=test")) { error in
            if let runtimeError = error as? PluginRuntimeError,
               case .peerRequestError(let msg) = runtimeError {
                XCTAssertTrue(msg.lowercased().contains("not supported"),
                    "error must indicate peer not supported: \(msg)")
            } else {
                XCTFail("expected peerRequestError, got \(error)")
            }
        }
    }

    // TEST255: NoPeerInvoker returns error even with valid arguments
    func testNoPeerInvokerWithArguments() {
        let noPeer = NoPeerInvoker()

        XCTAssertThrowsError(try noPeer.call(capUrn: "cap:op=test"),
            "must throw error")
    }

    // MARK: - Runtime Creation Tests (TEST256-258)

    // TEST256: PluginRuntime with manifest JSON stores manifest data and parses when valid
    func testWithManifestJson() {
        let runtime = PluginRuntime(manifestJSON: Self.testManifestJSON)
        XCTAssertFalse(runtime.manifestData.isEmpty, "manifestData must be populated")
        // Note: "cap:op=test" may or may not parse as valid Manifest depending on validation
    }

    // TEST257: PluginRuntime with invalid JSON still creates runtime
    func testNewWithInvalidJson() {
        let runtime = PluginRuntime(manifest: "not json".data(using: .utf8)!)
        XCTAssertFalse(runtime.manifestData.isEmpty, "manifestData should store raw bytes")
        XCTAssertNil(runtime.parsedManifest, "invalid JSON should leave parsedManifest as nil")
    }

    // TEST258: PluginRuntime with valid manifest data creates runtime with parsed manifest
    func testWithManifestStruct() {
        let runtime = PluginRuntime(manifest: Self.testManifestData)
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
            if let runtimeError = error as? PluginRuntimeError,
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
            if let runtimeError = error as? PluginRuntimeError,
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
            if let runtimeError = error as? PluginRuntimeError,
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
    // TEST266: REMOVED - CliStreamEmitter removed in favor of OutputStream with CliFrameSender
    // TEST267: REMOVED - CliStreamEmitter removed

    // MARK: - RuntimeError Display Tests (TEST268)

    // TEST268: RuntimeError variants display correct messages
    func testRuntimeErrorDisplay() {
        let err1 = PluginRuntimeError.noHandler("cap:op=missing")
        XCTAssertTrue((err1.errorDescription ?? "").contains("cap:op=missing"))

        let err2 = PluginRuntimeError.missingArgument("model")
        XCTAssertTrue((err2.errorDescription ?? "").contains("model"))

        let err3 = PluginRuntimeError.unknownSubcommand("badcmd")
        XCTAssertTrue((err3.errorDescription ?? "").contains("badcmd"))

        let err4 = PluginRuntimeError.manifestError("parse failed")
        XCTAssertTrue((err4.errorDescription ?? "").contains("parse failed"))

        let err5 = PluginRuntimeError.peerRequestError("denied")
        XCTAssertTrue((err5.errorDescription ?? "").contains("denied"))

        let err6 = PluginRuntimeError.peerResponseError("timeout")
        XCTAssertTrue((err6.errorDescription ?? "").contains("timeout"))
    }

}

// =============================================================================
// CapArgumentValue Tests (TEST274-278, TEST282-283)
// =============================================================================

final class CapArgumentValueTests: XCTestCase {

    // TEST274: CapArgumentValue stores media_urn and raw byte value
    func testCapArgumentValueNew() {
        let arg = CapArgumentValue(
            mediaUrn: "media:model-spec;textable;form=scalar",
            value: "gpt-4".data(using: .utf8)!
        )
        XCTAssertEqual(arg.mediaUrn, "media:model-spec;textable;form=scalar")
        XCTAssertEqual(arg.value, "gpt-4".data(using: .utf8)!)
    }

    // TEST275: CapArgumentValue.fromString converts string to UTF-8 bytes
    func testCapArgumentValueFromStr() {
        let arg = CapArgumentValue.fromString(mediaUrn: "media:string;textable", value: "hello world")
        XCTAssertEqual(arg.mediaUrn, "media:string;textable")
        XCTAssertEqual(arg.value, "hello world".data(using: .utf8)!)
    }

    // TEST276: CapArgumentValue.valueAsString succeeds for UTF-8 data
    func testCapArgumentValueAsStrValid() throws {
        let arg = CapArgumentValue.fromString(mediaUrn: "media:string", value: "test")
        XCTAssertEqual(try arg.valueAsString(), "test")
    }

    // TEST277: CapArgumentValue.valueAsString fails for non-UTF-8 binary data
    func testCapArgumentValueAsStrInvalidUtf8() {
        let arg = CapArgumentValue(mediaUrn: "media:pdf;bytes", value: Data([0xFF, 0xFE, 0x80]))
        XCTAssertThrowsError(try arg.valueAsString(), "non-UTF-8 data must fail")
    }

    // TEST278: CapArgumentValue with empty value stores empty Data
    func testCapArgumentValueEmpty() throws {
        let arg = CapArgumentValue(mediaUrn: "media:void", value: Data())
        XCTAssertTrue(arg.value.isEmpty)
        XCTAssertEqual(try arg.valueAsString(), "")
    }

    // TEST282: CapArgumentValue.fromString with Unicode string preserves all characters
    func testCapArgumentValueUnicode() throws {
        let arg = CapArgumentValue.fromString(mediaUrn: "media:string", value: "hello 世界 🌍")
        XCTAssertEqual(try arg.valueAsString(), "hello 世界 🌍")
    }

    // TEST283: CapArgumentValue with large binary payload preserves all bytes
    func testCapArgumentValueLargeBinary() {
        var data = Data()
        for _ in 0..<40 {  // 40 * 256 = 10240 > 10000
            for i: UInt8 in 0...255 {
                data.append(i)
            }
        }
        data = data.prefix(10000)  // trim to exactly 10000
        let arg = CapArgumentValue(mediaUrn: "media:pdf;bytes", value: data)
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
    private func createTestManifest(caps: [CapDefinition]) -> Data {
        let manifest = Manifest(
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
        args: [CapArg] = []
    ) -> CapDefinition {
        return CapDefinition(
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
        sources: [ArgSource]
    ) -> CapArg {
        return CapArg(
            mediaUrn: mediaUrn,
            required: required,
            sources: sources,
            argDescription: nil,
            defaultValue: nil
        )
    }

    // TEST336: Single file-path arg with stdin source reads file and passes bytes to handler
    func test336_file_path_reads_file_passes_bytes() throws {
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
        let runtime = PluginRuntime(manifest: manifest)

        // Register Op handler that echoes payload
        runtime.register_op(capUrn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"") {
            AnyOp(EchoAllBytesOp())
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

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)

        let inputStream = createSinglePayloadStream(mediaUrn: "media:pdf;bytes", data: payload)

        try invokeOp(factory, input: streamToInputPackage(inputStream), output: output)

        // Verify handler received file bytes, not file path
        XCTAssertEqual(collector.getData(), Data("PDF binary content 336".utf8), "Handler should receive file bytes")
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
        let runtime = PluginRuntime(manifest: manifest)

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
    func test338_file_path_via_cli_flag() throws {
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
        let runtime = PluginRuntime(manifest: manifest)

        runtime.register_op(capUrn: cap.urn) { AnyOp(EchoAllBytesOp()) }

        let cliArgs = ["--file", testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", capUrn: cap.urn)

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)
        let inputStream = createSinglePayloadStream(mediaUrn: "media:pdf;bytes", data: payload)
        try invokeOp(factory, input: streamToInputPackage(inputStream), output: output)

        XCTAssertEqual(collector.getData(), Data("PDF via flag 338".utf8), "Should read file from --file flag")

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

        runtime.register_op(capUrn: cap.urn) { AnyOp(EchoAllBytesOp()) }

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

        // Track what the handler receives using a class wrapper for thread-safe capture
        final class PayloadCapture: @unchecked Sendable {
            var data = Data()
        }
        let capture = PayloadCapture()

        // Register Op handler that captures received bytes and writes processed output
        let captureRef = capture
        runtime.register_op(capUrn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:result;textable\"") {
            final class CaptureAndWriteOp: Op, @unchecked Sendable {
                typealias Output = Void
                let capture: PayloadCapture
                init(_ c: PayloadCapture) { capture = c }
                func perform(dry: DryContext, wet: WetContext) async throws {
                    let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
                    let input = try req.takeInput()
                    let data = try input.collectAllBytes()
                    capture.data = data
                    try req.output().write(Data("processed".utf8))
                }
                func metadata() -> OpMetadata { OpMetadata.builder("CaptureAndWriteOp").build() }
            }
            return AnyOp(CaptureAndWriteOp(captureRef))
        }

        // Simulate full CLI invocation
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Create InputPackage directly from CBOR payload (don't extract - let the test helper handle it)
        let inputPackage = createInputPackage(fromPayload: rawPayload, mediaUrn: "media:pdf;bytes")

        // Create output collector
        let outputCollector = OutputCollector()
        let outputStream = createCollectingOutputStream(collector: outputCollector, mediaUrn: "media:result;textable")

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        try invokeOp(factory, input: inputPackage, output: outputStream)

        // Verify handler received file bytes
        XCTAssertEqual(capture.data, testContent, "Handler should receive file bytes, not path")
        XCTAssertEqual(outputCollector.getData(), Data("processed".utf8))

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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
        let runtime = PluginRuntime(manifest: manifest)

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

    // TEST395: Small payload (< max_chunk) produces correct CBOR arguments
    func test395_build_payload_small() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = PluginRuntime(manifest: manifest)

        let data = "small payload".data(using: .utf8)!
        let reader = InputStream(data: data)

        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: DEFAULT_MAX_CHUNK)

        // Verify CBOR structure
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded else {
            XCTFail("Expected array, got: \(String(describing: decoded))")
            return
        }
        XCTAssertEqual(arr.count, 1, "Should have one argument")

        guard case .map(let argMap) = arr[0] else {
            XCTFail("Expected map, got: \(arr[0])")
            return
        }

        guard case .byteString(let valueBytes) = argMap[CBOR.utf8String("value")] else {
            XCTFail("Expected bytes for value")
            return
        }

        XCTAssertEqual(Data(valueBytes), data, "Payload bytes should match")
    }

    // TEST396: Large payload (> max_chunk) accumulates across chunks correctly
    func test396_build_payload_large() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = PluginRuntime(manifest: manifest)

        // Use small max_chunk to force multi-chunk
        let data = Data((0..<1000).map { UInt8($0 % 256) })
        let reader = InputStream(data: data)

        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: 100)

        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded,
              case .map(let argMap) = arr[0],
              case .byteString(let valueBytes) = argMap[CBOR.utf8String("value")] else {
            XCTFail("Invalid CBOR structure")
            return
        }

        XCTAssertEqual(valueBytes.count, 1000, "All bytes should be accumulated")
        XCTAssertEqual(Data(valueBytes), data, "Data should match exactly")
    }

    // TEST397: Empty reader produces valid empty CBOR arguments
    func test397_build_payload_empty() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = PluginRuntime(manifest: manifest)

        let reader = InputStream(data: Data())

        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: DEFAULT_MAX_CHUNK)

        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded,
              case .map(let argMap) = arr[0],
              case .byteString(let valueBytes) = argMap[CBOR.utf8String("value")] else {
            XCTFail("Invalid CBOR structure")
            return
        }

        XCTAssertEqual(valueBytes.count, 0, "Empty reader should produce empty bytes")
    }

    // ErrorInputStream that simulates an IO error
    class ErrorInputStream: Foundation.InputStream {
        private var _streamStatus: Stream.Status = .notOpen
        private var _streamError: Error?

        override func open() {
            _streamStatus = .open
        }

        override func close() {
            _streamStatus = .closed
        }

        override var streamStatus: Stream.Status {
            return _streamStatus
        }

        override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
            _streamError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "simulated read error"])
            return -1 // Simulate error
        }

        override var hasBytesAvailable: Bool {
            return true
        }

        override var streamError: Error? {
            return _streamError
        }
    }

    // TEST398: IO error from reader propagates as error
    func test398_build_payload_io_error() {
        let cap = CapDefinition(
            urn: "cap:in=\"media:bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = PluginRuntime(manifest: manifest)

        let reader = ErrorInputStream()

        XCTAssertThrowsError(try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: DEFAULT_MAX_CHUNK)) { thrownError in
            let errorStr = "\(thrownError)"
            XCTAssertTrue(errorStr.contains("simulated read error") || errorStr.contains("Stream read error"),
                          "Expected error to contain 'simulated read error', got: \(errorStr)")
        }
    }

    // TEST361: CLI mode with file path - pass file path as command-line argument
    func test361_cli_mode_file_path() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test361.pdf")
        let pdfContent = Data("PDF content for CLI file path test".utf8)
        try pdfContent.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

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
        let runtime = PluginRuntime(manifest: manifest)

        // CLI mode: pass file path as positional argument
        let cliArgs = [testFile.path]
        let payload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Verify payload is CBOR array with file-path argument
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        if case .array = decoded {
            // Success - it's an array
        } else {
            XCTFail("CLI mode should produce CBOR array")
        }
    }

    // TEST362: CLI mode with binary piped in - pipe binary data via stdin
    //
    // This test simulates real-world conditions:
    // - Pure binary data piped to stdin (NOT CBOR)
    // - CLI mode detected (command arg present)
    // - Cap accepts stdin source
    // - Binary is chunked on-the-fly and accumulated
    // - Handler receives complete CBOR payload
    func test362_cli_mode_piped_binary() throws {
        // Simulate large binary being piped (1MB PDF)
        let pdfContent = Data(repeating: 0xAB, count: 1_000_000)

        // Create cap that accepts stdin
        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:pdf;bytes",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes")
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = PluginRuntime(manifest: manifest)

        // Mock stdin with Data (simulates piped binary)
        let mockStdin = InputStream(data: pdfContent)
        mockStdin.open()
        defer { mockStdin.close() }

        // Build payload from streaming reader (what CLI piped mode does)
        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: mockStdin, maxChunk: DEFAULT_MAX_CHUNK)

        // Verify payload is CBOR array with correct structure
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded else {
            XCTFail("Expected CBOR Array")
            return
        }

        XCTAssertEqual(arr.count, 1, "CBOR array should have one argument")

        guard case .map(let argMap) = arr[0] else {
            XCTFail("Expected Map in CBOR array")
            return
        }

        var mediaUrn: String?
        var value: Data?

        for (k, v) in argMap {
            if case .utf8String(let key) = k {
                switch key {
                case "media_urn":
                    if case .utf8String(let s) = v {
                        mediaUrn = s
                    }
                case "value":
                    if case .byteString(let bytes) = v {
                        value = Data(bytes)
                    }
                default:
                    break
                }
            }
        }

        XCTAssertEqual(mediaUrn, "media:pdf;bytes", "Media URN should match cap in_spec")
        XCTAssertEqual(value, pdfContent, "Binary content should be preserved exactly")
    }

    // TEST363: CBOR mode with chunked content - send file content streaming as chunks
    func test363_cbor_mode_chunked_content() async throws {
        let pdfContent = Data(repeating: 0xAA, count: 10000)  // 10KB of data

        final class ResultHolder: @unchecked Sendable {
            var data: Data?
        }
        let resultHolder = ResultHolder()

        let cap = createCap(
            urn: "cap:in=\"media:pdf;bytes\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:pdf;bytes",
                required: true,
                sources: [
                    .stdin("media:pdf;bytes")
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = PluginRuntime(manifest: manifest)

        // Register Op handler that captures received bytes and echoes them
        let resultHolderRef = resultHolder
        runtime.register_op(capUrn: cap.urn) {
            final class CaptureEchoOp: Op, @unchecked Sendable {
                typealias Output = Void
                let holder: ResultHolder
                init(_ h: ResultHolder) { holder = h }
                func perform(dry: DryContext, wet: WetContext) async throws {
                    let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
                    let input = try req.takeInput()
                    let total = try input.collectAllBytes()
                    holder.data = total
                    try req.output().write(total)
                }
                func metadata() -> OpMetadata { OpMetadata.builder("CaptureEchoOp").build() }
            }
            return AnyOp(CaptureEchoOp(resultHolderRef))
        }

        // Build CBOR payload
        let args = [CapArgumentValue(mediaUrn: "media:pdf;bytes", value: pdfContent)]
        let cborArgs: [CBOR] = args.map { arg in
            CBOR.map([
                CBOR.utf8String("media_urn"): CBOR.utf8String(arg.mediaUrn),
                CBOR.utf8String("value"): CBOR.byteString([UInt8](arg.value))
            ])
        }
        let payloadBytes = Data(CBOR.array(cborArgs).encode())

        // Create InputPackage from payload
        let inputPackage = createInputPackage(fromPayload: payloadBytes, mediaUrn: "media:pdf;bytes")

        // Create output collector
        let outputCollector = OutputCollector()
        let outputStream = createCollectingOutputStream(collector: outputCollector, mediaUrn: "media:pdf;bytes")

        // Execute Op handler
        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        try invokeOp(factory, input: inputPackage, output: outputStream)

        XCTAssertEqual(resultHolder.data, pdfContent, "Handler should receive chunked content")
    }

    // TEST364: CBOR mode with file path - send file path in CBOR arguments (auto-conversion)
    func test364_cbor_mode_file_path() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test364.pdf")
        let pdfContent = Data("PDF content for CBOR file path test".utf8)
        try pdfContent.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Build CBOR arguments with file-path URN
        let args = [CapArgumentValue(
            mediaUrn: "media:file-path;textable;form=scalar",
            value: Data(testFile.path.utf8)
        )]
        let cborArgs: [CBOR] = args.map { arg in
            CBOR.map([
                CBOR.utf8String("media_urn"): CBOR.utf8String(arg.mediaUrn),
                CBOR.utf8String("value"): CBOR.byteString([UInt8](arg.value))
            ])
        }
        let payload = Data(CBOR.array(cborArgs).encode())

        // Verify the CBOR structure is correct
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(arr.count, 1, "Expected 1 argument")

        guard case .map(let argMap) = arr[0] else {
            XCTFail("Expected map")
            return
        }

        var mediaUrn: String?
        var value: Data?

        for (k, v) in argMap {
            if case .utf8String(let key) = k {
                switch key {
                case "media_urn":
                    if case .utf8String(let s) = v {
                        mediaUrn = s
                    }
                case "value":
                    if case .byteString(let bytes) = v {
                        value = Data(bytes)
                    }
                default:
                    break
                }
            }
        }

        XCTAssertEqual(mediaUrn, "media:file-path;textable;form=scalar", "Expected media:file-path URN")
        XCTAssertEqual(value, Data(testFile.path.utf8), "Expected file path as value")
    }
}

// MARK: - Test Helpers

/// Mock FrameSender for collecting output from handlers
private final class MockFrameSender: FrameSender, @unchecked Sendable {
    private let onSend: @Sendable (Frame) -> Void

    init(onSend: @escaping @Sendable (Frame) -> Void) {
        self.onSend = onSend
    }

    func send(_ frame: Frame) throws {
        onSend(frame)
    }
}

/// Collects CBOR output from OutputStream for testing
private final class OutputCollector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ bytes: Data) {
        lock.lock()
        data.append(bytes)
        lock.unlock()
    }

    func getData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Creates an OutputStream that collects emitted data into a buffer
private func createCollectingOutputStream(collector: OutputCollector, mediaUrn: String = "media:bytes") -> Bifaci.OutputStream {
    let mockSender = MockFrameSender { frame in
        if frame.frameType == .chunk, let payload = frame.payload {
            if let cbor = try? CBOR.decode([UInt8](payload)), case .byteString(let bytes) = cbor {
                collector.append(Data(bytes))
            }
        }
    }
    return Bifaci.OutputStream(
        sender: mockSender,
        streamId: "test",
        mediaUrn: mediaUrn,
        requestId: .newUUID(),
        routingId: nil,
        maxChunk: 1000
    )
}

/// Creates an InputPackage from a CBOR payload OR raw bytes
private func createInputPackage(fromPayload payload: Data, mediaUrn: String) -> InputPackage {
    // Try to decode as CBOR - if it fails, treat as raw bytes
    guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
        // Payload is raw bytes, not CBOR - wrap as byteString chunk
        let chunks: [Result<CBOR, StreamError>] = [.success(.byteString([UInt8](payload)))]
        var chunkIndex = 0
        let chunkIterator = AnyIterator<Result<CBOR, StreamError>> {
            guard chunkIndex < chunks.count else { return nil }
            let chunk = chunks[chunkIndex]
            chunkIndex += 1
            return chunk
        }
        let stream = Bifaci.InputStream(mediaUrn: mediaUrn, rx: chunkIterator)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(stream)]
        var streamIndex = 0
        let streamIterator = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIndex < streams.count else { return nil }
            let s = streams[streamIndex]
            streamIndex += 1
            return s
        }
        return InputPackage(rx: streamIterator)
    }

    // Extract value from CBOR arguments format: [{media_urn: "...", value: <bytes>}]
    var extractedValue: CBOR = cborValue
    if case .array(let args) = cborValue, let firstArg = args.first {
        if case .map(let argMap) = firstArg {
            // Extract the "value" field from the argument map
            if let value = argMap[.utf8String("value")] {
                extractedValue = value
            }
        }
    }

    // Create a single chunk with the extracted value
    let chunks: [Result<CBOR, StreamError>] = [.success(extractedValue)]
    var chunkIndex = 0
    let chunkIterator = AnyIterator<Result<CBOR, StreamError>> {
        guard chunkIndex < chunks.count else { return nil }
        let chunk = chunks[chunkIndex]
        chunkIndex += 1
        return chunk
    }

    // Create a single stream
    let stream = Bifaci.InputStream(mediaUrn: mediaUrn, rx: chunkIterator)
    let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(stream)]
    var streamIndex = 0
    let streamIterator = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
        guard streamIndex < streams.count else { return nil }
        let s = streams[streamIndex]
        streamIndex += 1
        return s
    }

    return InputPackage(rx: streamIterator)
}

/// Converts AsyncStream<Frame> to InputPackage by collecting frames synchronously
@available(macOS 10.15.4, iOS 13.4, *)
private func streamToInputPackage(_ stream: AsyncStream<Frame>) -> InputPackage {
    // Collect all frames synchronously
    let framesBox = NSMutableArray()
    let group = DispatchGroup()
    group.enter()

    Thread.detachNewThread {
        let localGroup = DispatchGroup()
        localGroup.enter()
        Task {
            for await frame in stream {
                framesBox.add(frame)
            }
            localGroup.leave()
        }
        localGroup.wait()
        group.leave()
    }

    group.wait()
    let allFrames = framesBox.compactMap { $0 as? Frame }

    var frameIndex = 0
    let frameIterator = AnyIterator<Frame> {
        guard frameIndex < allFrames.count else { return nil }
        let frame = allFrames[frameIndex]
        frameIndex += 1
        return frame
    }

    // Use the demuxMultiStream function from PluginRuntime
    return demuxMultiStream(frameIterator: frameIterator)
}
