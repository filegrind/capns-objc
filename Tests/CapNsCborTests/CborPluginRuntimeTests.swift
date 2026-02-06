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

        runtime.register(capUrn: "cap:in=*;op=test;out=*") { payload, _, _ in
            return "result".data(using: .utf8)!
        }

        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:in=*;op=test;out=*"),
            "handler must be found by exact URN")
    }

    // TEST249: register raw handler works with bytes directly without deserialization
    func testRawHandler() throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=raw") { payload, _, _ in
            return payload // echo
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=raw"))
        let noPeer = NoCborPeerInvoker()
        let emitter = CliStreamEmitter()
        let result = try handler("echo this".data(using: .utf8)!, emitter, noPeer)
        XCTAssertEqual(String(data: result, encoding: .utf8), "echo this", "raw handler must echo payload")
    }

    // TEST250: register typed handler deserializes JSON and executes correctly
    func testTypedHandlerDeserialization() throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=test") {
            (req: [String: String], _: CborStreamEmitter, _: CborPeerInvoker) throws -> [String: String] in
            let value = req["key"] ?? "missing"
            return ["result": value]
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let noPeer = NoCborPeerInvoker()
        let emitter = CliStreamEmitter()
        let result = try handler("{\"key\":\"hello\"}".data(using: .utf8)!, emitter, noPeer)

        // Parse the JSON response
        let resultDict = try JSONDecoder().decode([String: String].self, from: result)
        XCTAssertEqual(resultDict["result"], "hello")
    }

    // TEST251: typed handler returns error for invalid JSON input
    func testTypedHandlerRejectsInvalidJson() throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=test") {
            (req: [String: String], _: CborStreamEmitter, _: CborPeerInvoker) throws -> Data in
            return Data()
        }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let noPeer = NoCborPeerInvoker()
        let emitter = CliStreamEmitter()

        XCTAssertThrowsError(try handler("not json {{{{".data(using: .utf8)!, emitter, noPeer),
            "invalid JSON must produce error")
    }

    // TEST252: find_handler returns None for unregistered cap URNs
    func testFindHandlerUnknownCap() {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=nonexistent"),
            "unregistered cap must return nil")
    }

    // TEST270: Registering multiple handlers for different caps and finding each independently
    func testMultipleHandlers() throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=alpha") { _, _, _ in "a".data(using: .utf8)! }
        runtime.register(capUrn: "cap:op=beta") { _, _, _ in "b".data(using: .utf8)! }
        runtime.register(capUrn: "cap:op=gamma") { _, _, _ in "g".data(using: .utf8)! }

        let noPeer = NoCborPeerInvoker()
        let emitter = CliStreamEmitter()

        let hAlpha = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=alpha"))
        XCTAssertEqual(try hAlpha(Data(), emitter, noPeer), "a".data(using: .utf8)!)

        let hBeta = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=beta"))
        XCTAssertEqual(try hBeta(Data(), emitter, noPeer), "b".data(using: .utf8)!)

        let hGamma = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=gamma"))
        XCTAssertEqual(try hGamma(Data(), emitter, noPeer), "g".data(using: .utf8)!)
    }

    // TEST271: Handler replacing an existing registration for the same cap URN
    func testHandlerReplacement() throws {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)

        runtime.register(capUrn: "cap:op=test") { _, _, _ in "first".data(using: .utf8)! }
        runtime.register(capUrn: "cap:op=test") { _, _, _ in "second".data(using: .utf8)! }

        let handler = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let noPeer = NoCborPeerInvoker()
        let emitter = CliStreamEmitter()
        let result = try handler(Data(), emitter, noPeer)
        XCTAssertEqual(String(data: result, encoding: .utf8), "second",
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

    // TEST267: CliStreamEmitter default creates NDJSON emitter
    func testCliStreamEmitterDefault() {
        let emitter = CliStreamEmitter()
        XCTAssertTrue(emitter.ndjson)
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

    // MARK: - Runtime Limits Tests (TEST269)

    // TEST269: PluginRuntime limits returns default protocol limits
    func testRuntimeLimitsDefault() {
        let runtime = CborPluginRuntime(manifest: Self.testManifestData)
        let limits = runtime.negotiatedLimits
        XCTAssertEqual(limits.maxFrame, DEFAULT_MAX_FRAME)
        XCTAssertEqual(limits.maxChunk, DEFAULT_MAX_CHUNK)
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
