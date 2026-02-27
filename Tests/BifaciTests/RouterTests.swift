import XCTest
@testable import Bifaci

// =============================================================================
// Router Tests
//
// Covers TEST638 from router.rs in the reference Rust implementation.
// Tests the CapRouter protocol and NoPeerRouter implementation.
// =============================================================================

final class RouterTests: XCTestCase {

    // TEST638: NoPeerRouter rejects all requests with PeerInvokeNotSupported
    func test638_noPeerRouterRejectsAll() throws {
        let router = NoPeerRouter()

        // All cap URNs should be rejected
        let testCaps = [
            "cap:in=media:;out=media:",
            "cap:op=test",
            "cap:in=text:;out=text:",
            "cap:in=image:;out=audio:",
        ]

        for capUrn in testCaps {
            let reqId = Data(repeating: 0x42, count: 16)
            XCTAssertThrowsError(try router.beginRequest(capUrn: capUrn, reqId: reqId)) { error in
                guard case PluginHostError.peerInvokeNotSupported(let urn) = error else {
                    XCTFail("Expected peerInvokeNotSupported for \(capUrn), got \(error)")
                    return
                }
                XCTAssertEqual(urn, capUrn, "Error should contain the rejected cap URN")
            }
        }
    }
}
