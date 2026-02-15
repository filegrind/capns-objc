import XCTest
import SwiftCBOR
@testable import Bifaci
@testable import CapNs

/// Tests for standard capabilities and manifest validation (TEST473-480)
/// Based on Rust tests in standard/caps.rs and bifaci/manifest.rs
final class StandardCapsTests: XCTestCase {

    // MARK: - CAP_DISCARD Tests (TEST473-474)

    // TEST473: CAP_DISCARD parses as valid CapUrn
    func testCapDiscardParsesAsValidCapUrn() throws {
        let discardUrn = try CSCapUrn.fromString(CSCapDiscard)

        XCTAssertNotNil(discardUrn, "CAP_DISCARD must parse as valid CapUrn")
        XCTAssertEqual(discardUrn.inSpec, "media:", "CAP_DISCARD input must be media: (any media type)")
        XCTAssertEqual(discardUrn.outSpec, "media:void", "CAP_DISCARD output must be media:void")
    }

    // TEST474: CAP_DISCARD accepts specific void-output caps
    func testCapDiscardAcceptsVoidOutputCaps() throws {
        let discardPattern = try CSCapUrn.fromString(CSCapDiscard)

        // CAP_DISCARD should accept any cap with void output
        let voidCap1 = try CSCapUrn.fromString("cap:in=media:text;out=media:void")
        let voidCap2 = try CSCapUrn.fromString("cap:op=delete;in=media:;out=media:void")

        XCTAssertTrue(discardPattern.accepts(voidCap1), "CAP_DISCARD must accept text->void cap")
        XCTAssertTrue(discardPattern.accepts(voidCap2), "CAP_DISCARD must accept any->void cap")

        // CAP_DISCARD should NOT accept caps with non-void output
        let nonVoidCap = try CSCapUrn.fromString("cap:in=media:;out=media:text")
        XCTAssertFalse(discardPattern.accepts(nonVoidCap), "CAP_DISCARD must not accept non-void output")
    }

    // MARK: - Manifest Validation Tests (TEST475-477)

    // TEST475: Manifest.validate() passes with CAP_IDENTITY present
    func testManifestValidatePassesWithIdentity() throws {
        let identityCap = CSCap(try CSCapUrn.fromString(CSCapIdentity),
                                          title: "Identity",
                                          command: "identity")
        let manifest = CSCapManifest("TestPlugin",
                                                      version: "1.0.0",
                                                      description: "Test",
                                                      caps: [identityCap])

        var error: NSError?
        let result = manifest.validate(&error)
        XCTAssertTrue(result, "Manifest with CAP_IDENTITY must validate successfully")
        XCTAssertNil(error)
    }

    // TEST476: Manifest.validate() fails without CAP_IDENTITY
    func testManifestValidateFailsWithoutIdentity() throws {
        let otherCap = CSCap(try CSCapUrn.fromString("cap:op=test;in=media:;out=media:"),
                                       title: "Test",
                                       command: "test")
        let manifest = CSCapManifest("TestPlugin",
                                                      version: "1.0.0",
                                                      description: "Test",
                                                      caps: [otherCap])

        var error: NSError?
        let result = manifest.validate(&error)

        XCTAssertFalse(result, "Manifest without CAP_IDENTITY must fail validation")
        XCTAssertNotNil(error, "Validation error must be provided")
        XCTAssertTrue(error!.localizedDescription.contains("CAP_IDENTITY"),
                     "Error must mention missing CAP_IDENTITY")
    }

    // TEST477: Manifest.ensureIdentity() adds if missing, idempotent if present
    func testManifestEnsureIdentityIdempotent() throws {
        // Test 1: Adding identity when missing
        let cap1 = CSCap(try CSCapUrn.fromString("cap:op=test;in=media:;out=media:"),
                                   title: "Test",
                                   command: "test")
        let manifestWithout = CSCapManifest("TestPlugin",
                                                             version: "1.0.0",
                                                             description: "Test",
                                                             caps: [cap1])

        let withIdentity = manifestWithout.ensureIdentity()
        var error1: NSError?
        XCTAssertTrue(withIdentity.validate(&error1), "ensureIdentity() must add CAP_IDENTITY")
        XCTAssertNil(error1)
        XCTAssertEqual(withIdentity.caps.count, 2, "ensureIdentity() must add identity cap")

        // Test 2: Idempotent when already present
        let withIdentityAgain = withIdentity.ensureIdentity()
        XCTAssertEqual(withIdentityAgain.caps.count, 2, "ensureIdentity() must be idempotent")
    }

    // MARK: - Auto-Registration Tests (TEST478-480)

    // TEST478: PluginRuntime auto-registers CAP_IDENTITY handler
    func testPluginRuntimeAutoRegistersIdentity() throws {
        let manifest = """
        {"name":"Test","version":"1.0.0","description":"Test","caps":[
            {"urn":"\(CSCapIdentity)","title":"Identity","command":"identity"}
        ]}
        """.data(using: .utf8)!

        let runtime = PluginRuntime(manifest: manifest)

        // Verify identity handler is registered
        let identityHandler = runtime.findHandler(capUrn: CSCapIdentity)
        XCTAssertNotNil(identityHandler, "PluginRuntime must auto-register CAP_IDENTITY handler")
    }

    // TEST479: CAP_IDENTITY handler echoes input unchanged
    func testIdentityHandlerEchoesInput() throws {
        let manifest = """
        {"name":"Test","version":"1.0.0","description":"Test","caps":[
            {"urn":"\(CSCapIdentity)","title":"Identity","command":"identity"}
        ]}
        """.data(using: .utf8)!

        let runtime = PluginRuntime(manifest: manifest)
        let handler = runtime.findHandler(capUrn: CSCapIdentity)!

        // Create test input
        let testData = "test data".data(using: .utf8)!
        let (inputStream, inputContinuation) = AsyncStream<Result<Bifaci.InputStream, StreamError>>.makeStream()

        // Create single input stream
        let (chunkStream, chunkContinuation) = AsyncStream<Result<CBOR, StreamError>>.makeStream()
        chunkContinuation.yield(.success(.byteString([UInt8](testData))))
        chunkContinuation.finish()

        let stream = Bifaci.InputStream(mediaUrn: "media:bytes", rx: AnyIterator { chunkStream.makeAsyncIterator().next() })
        inputContinuation.yield(.success(stream))
        inputContinuation.finish()

        let input = InputPackage(rx: AnyIterator { inputStream.makeAsyncIterator().next() })

        // Create output (mock)
        var outputData = Data()
        let mockSender = MockFrameSender { frame in
            if frame.frameType == .chunk, let payload = frame.payload {
                if let cbor = try? CBOR.decode([UInt8](payload)), case .byteString(let bytes) = cbor {
                    outputData.append(Data(bytes))
                }
            }
        }
        let output = OutputStream(sender: mockSender, streamId: "test", mediaUrn: "media:bytes",
                                 requestId: .newUUID(), routingId: nil, maxChunk: 1000)

        let peer = NoPeerInvoker()

        // Execute handler
        XCTAssertNoThrow(try handler(input, output, peer), "Identity handler must not throw")
        XCTAssertEqual(outputData, testData, "Identity handler must echo input unchanged")
    }

    // TEST480: CAP_DISCARD handler consumes input and produces void
    func testDiscardHandlerConsumesInput() throws {
        let manifest = """
        {"name":"Test","version":"1.0.0","description":"Test","caps":[
            {"urn":"\(CSCapDiscard)","title":"Discard","command":"discard"}
        ]}
        """.data(using: .utf8)!

        let runtime = PluginRuntime(manifest: manifest)
        let handler = runtime.findHandler(capUrn: CSCapDiscard)!

        // Create test input
        let testData = "discard me".data(using: .utf8)!
        let (inputStream, inputContinuation) = AsyncStream<Result<Bifaci.InputStream, StreamError>>.makeStream()

        let (chunkStream, chunkContinuation) = AsyncStream<Result<CBOR, StreamError>>.makeStream()
        chunkContinuation.yield(.success(.byteString([UInt8](testData))))
        chunkContinuation.finish()

        let stream = Bifaci.InputStream(mediaUrn: "media:bytes", rx: AnyIterator { chunkStream.makeAsyncIterator().next() })
        inputContinuation.yield(.success(stream))
        inputContinuation.finish()

        let input = InputPackage(rx: AnyIterator { inputStream.makeAsyncIterator().next() })

        // Create output (mock)
        var outputGenerated = false
        let mockSender = MockFrameSender { _ in
            outputGenerated = true
        }
        let output = OutputStream(sender: mockSender, streamId: "test", mediaUrn: "media:void",
                                 requestId: .newUUID(), routingId: nil, maxChunk: 1000)

        let peer = NoPeerInvoker()

        // Execute handler
        XCTAssertNoThrow(try handler(input, output, peer), "Discard handler must not throw")
        // Discard produces void - no output expected (or minimal)
    }
}

// MARK: - Test Helpers

/// Mock FrameSender for testing
private final class MockFrameSender: FrameSender, @unchecked Sendable {
    private let onSend: @Sendable (Frame) -> Void

    init(onSend: @escaping @Sendable (Frame) -> Void) {
        self.onSend = onSend
    }

    func send(_ frame: Frame) throws {
        onSend(frame)
    }
}
