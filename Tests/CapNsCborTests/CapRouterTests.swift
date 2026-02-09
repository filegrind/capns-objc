//
//  CapRouterTests.swift
//  CapNsCborTests
//
//  Tests for cap router infrastructure (peer invoke routing)

import XCTest
@testable import CapNsCbor

final class CapRouterTests: XCTestCase {
    // MARK: - NoCborPeerRouter Tests

    // TEST385: NoPeerRouter rejects all peer invoke requests with peerInvokeNotSupported error
    func testNoPeerRouterRejectsAll() async throws {
        let router = NoCborPeerRouter()
        let reqId = Data(repeating: 0, count: 16)

        do {
            _ = try await router.beginRequest(
                capUrn: "cap:in=\"media:void\";op=test;out=\"media:void\"",
                reqId: reqId
            )
            XCTFail("NoPeerRouter should reject all requests")
        } catch let error as CborPluginHostError {
            switch error {
            case .peerInvokeNotSupported:
                // Expected error type
                break
            default:
                XCTFail("Expected peerInvokeNotSupported error, got: \(error)")
            }
        } catch {
            XCTFail("Expected CborPluginHostError, got: \(error)")
        }
    }

    // TEST388: CapRouter::begin_request error from NoPeerRouter contains the cap URN
    func testCapRouterBeginRequestError() async throws {
        let router = NoCborPeerRouter()
        let reqId = Data(repeating: 0, count: 16)
        let testCapUrn = "cap:in=\"media:void\";op=specific_test;out=\"media:void\""

        do {
            _ = try await router.beginRequest(capUrn: testCapUrn, reqId: reqId)
            XCTFail("NoPeerRouter should reject all requests")
        } catch let error as CborPluginHostError {
            switch error {
            case .peerInvokeNotSupported(let capUrn):
                XCTAssertEqual(capUrn, testCapUrn,
                    "Error should contain the exact cap URN that was requested")
            default:
                XCTFail("Expected peerInvokeNotSupported error with cap URN, got: \(error)")
            }
        } catch {
            XCTFail("Expected CborPluginHostError, got: \(error)")
        }
    }

    // MARK: - LocalCborPluginRouter Tests

    // TEST386: LocalPluginRouter creation produces empty router
    func testLocalPluginRouterCreation() async throws {
        let router = LocalCborPluginRouter()

        // Router should start empty - findPlugin returns nil for any cap
        let found = await router.findPlugin("cap:in=\"media:void\";op=test;out=\"media:void\"")
        XCTAssertNil(found, "Newly created router should have no registered plugins")
    }

    // TEST387: LocalPluginRouter::find_plugin returns None for empty router
    func testLocalPluginRouterFindPluginEmpty() async throws {
        let router = LocalCborPluginRouter()

        // Test multiple cap URNs - all should return nil
        let testCaps = [
            "cap:in=\"media:void\";op=missing;out=\"media:void\"",
            "cap:in=\"media:bytes\";op=process;out=\"media:bytes\"",
            "cap:in=\"media:json\";op=transform;out=\"media:json\""
        ]

        for capUrn in testCaps {
            let found = await router.findPlugin(capUrn)
            XCTAssertNil(found, "Empty router should return nil for cap: \(capUrn)")
        }
    }
}
