import XCTest
@testable import Bifaci
@preconcurrency import SwiftCBOR

// =============================================================================
// CBOR Sequence (RFC 8742) Tests
//
// Covers splitCborSequence and assembleCborSequence — the Swift equivalents
// of Rust split_cbor_sequence / assemble_cbor_sequence in cbor_util.rs.
//
// TEST810-822: mirrors Rust TEST791-802 in capdag/src/orchestrator/cbor_util.rs
// =============================================================================

final class CborSequenceTests: XCTestCase {

    /// Helper: build a CBOR sequence by concatenating individually-encoded values.
    private func buildCborSequence(_ values: [CBOR]) -> Data {
        var result = Data()
        for v in values {
            result.append(contentsOf: v.encode())
        }
        return result
    }

    // TEST810: splitCborSequence splits concatenated CBOR Bytes values
    func test810_splitSequenceBytes() throws {
        let page1: [UInt8] = Array("page1 json data".utf8)
        let page2: [UInt8] = Array("page2 json data".utf8)
        let page3: [UInt8] = Array("page3 json data".utf8)

        let seq = buildCborSequence([
            .byteString(page1),
            .byteString(page2),
            .byteString(page3),
        ])

        let items = try splitCborSequence(seq)
        XCTAssertEqual(items.count, 3)

        // Verify each item decodes to the expected value
        let d0 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(d0, .byteString(page1))
        let d1 = try CBOR.decode([UInt8](items[1]))
        XCTAssertEqual(d1, .byteString(page2))
        let d2 = try CBOR.decode([UInt8](items[2]))
        XCTAssertEqual(d2, .byteString(page3))
    }

    // TEST811: splitCborSequence splits concatenated CBOR Text values
    func test811_splitSequenceText() throws {
        let seq = buildCborSequence([
            .utf8String("hello"),
            .utf8String("world"),
        ])

        let items = try splitCborSequence(seq)
        XCTAssertEqual(items.count, 2)

        let d0 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(d0, .utf8String("hello"))
        let d1 = try CBOR.decode([UInt8](items[1]))
        XCTAssertEqual(d1, .utf8String("world"))
    }

    // TEST812: splitCborSequence handles mixed types
    func test812_splitSequenceMixed() throws {
        let seq = buildCborSequence([
            .byteString([1, 2, 3]),
            .utf8String("mixed"),
            .map([.utf8String("key"): .unsignedInt(42)]),
            .unsignedInt(99),
        ])

        let items = try splitCborSequence(seq)
        XCTAssertEqual(items.count, 4)

        let d0 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(d0, .byteString([1, 2, 3]))
        let d3 = try CBOR.decode([UInt8](items[3]))
        XCTAssertEqual(d3, .unsignedInt(99))
    }

    // TEST813: splitCborSequence single-item sequence
    func test813_splitSequenceSingle() throws {
        let seq = buildCborSequence([
            .byteString([0xDE, 0xAD]),
        ])

        let items = try splitCborSequence(seq)
        XCTAssertEqual(items.count, 1)
        let d0 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(d0, .byteString([0xDE, 0xAD]))
    }

    // TEST814: roundtrip — assemble then split preserves items
    func test814_roundtripAssembleSplitSequence() throws {
        let itemValues: [CBOR] = [
            .byteString(Array("first".utf8)),
            .byteString(Array("second".utf8)),
            .utf8String("third"),
        ]
        let items: [Data] = itemValues.map { Data($0.encode()) }

        let assembled = try assembleCborSequence(items)
        let splitBack = try splitCborSequence(assembled)

        XCTAssertEqual(splitBack.count, 3)
        XCTAssertEqual(splitBack[0], items[0])
        XCTAssertEqual(splitBack[1], items[1])
        XCTAssertEqual(splitBack[2], items[2])
    }

    // TEST815: roundtrip — split then assemble preserves byte-for-byte
    func test815_roundtripSplitAssembleSequence() throws {
        let seq = buildCborSequence([
            .byteString(Array("alpha".utf8)),
            .byteString(Array("beta".utf8)),
        ])

        let items = try splitCborSequence(seq)
        let reassembled = try assembleCborSequence(items)

        XCTAssertEqual(reassembled, seq, "split then assemble must preserve bytes exactly")
    }

    // TEST816: splitCborSequence rejects empty data
    func test816_splitSequenceEmpty() {
        XCTAssertThrowsError(try splitCborSequence(Data())) { error in
            guard let seqError = error as? CborSequenceError else {
                XCTFail("Expected CborSequenceError, got \(error)")
                return
            }
            if case .emptySequence = seqError {
                // expected
            } else {
                XCTFail("Expected .emptySequence, got \(seqError)")
            }
        }
    }

    // TEST817: splitCborSequence rejects truncated CBOR
    func test817_splitSequenceTruncated() {
        // Build a valid CBOR Bytes value, then append a truncated item
        var seq = buildCborSequence([
            .byteString(Array("complete".utf8)),
        ])
        // Add truncated CBOR: major type 2 (bytes), length 10, but only 3 bytes
        seq.append(0x4A) // bytes(10)
        seq.append(contentsOf: [0x01, 0x02, 0x03]) // only 3 of 10 bytes

        XCTAssertThrowsError(try splitCborSequence(seq)) { error in
            guard let seqError = error as? CborSequenceError else {
                XCTFail("Expected CborSequenceError, got \(error)")
                return
            }
            if case .deserializationError = seqError {
                // expected
            } else {
                XCTFail("Expected .deserializationError, got \(seqError)")
            }
        }
    }

    // TEST818: assembleCborSequence rejects invalid CBOR item
    func test818_assembleSequenceInvalidItem() {
        // Use a truncated CBOR bytestring: header says 10 bytes, but only 2 provided
        let items: [Data] = [
            Data(CBOR.unsignedInt(1).encode()),
            Data([0x4A, 0x01, 0x02]), // bytes(10) but only 2 bytes of content — truncated
        ]

        XCTAssertThrowsError(try assembleCborSequence(items)) { error in
            guard let seqError = error as? CborSequenceError else {
                XCTFail("Expected CborSequenceError, got \(error)")
                return
            }
            if case .deserializationError = seqError {
                // expected
            } else {
                XCTFail("Expected .deserializationError, got \(seqError)")
            }
        }
    }

    // TEST819: assembleCborSequence with empty items list produces empty bytes
    func test819_assembleSequenceEmpty() throws {
        let assembled = try assembleCborSequence([])
        XCTAssertTrue(assembled.isEmpty, "empty sequence must produce empty bytes")
    }

    // TEST820: single CBOR value is a valid sequence of 1 item
    func test820_singleValueSequence() throws {
        let single = Data(CBOR.byteString(Array("solo".utf8)).encode())

        let items = try splitCborSequence(single)
        XCTAssertEqual(items.count, 1)
        let d0 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(d0, .byteString(Array("solo".utf8)))
    }

    // TEST821: collectCborSequence on InputStream preserves CBOR structure
    func test821_inputStreamCollectCborSequence() throws {
        let page1 = CBOR.byteString(Array("page1".utf8))
        let page2 = CBOR.byteString(Array("page2".utf8))

        let chunks: [Result<CBOR, StreamError>] = [
            .success(page1),
            .success(page2),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test;list", rx: iterator)
        let sequence = try stream.collectCborSequence()

        // The result should be a valid CBOR sequence
        let items = try splitCborSequence(sequence)
        XCTAssertEqual(items.count, 2)

        let d0 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(d0, page1)
        let d1 = try CBOR.decode([UInt8](items[1]))
        XCTAssertEqual(d1, page2)
    }

    // MARK: - CBOR Array Tests (splitCborArray / assembleCborArray)
    // Mirrors Rust tests 780-786, 955-956 in cbor_util.rs

    // TEST780: splitCborArray splits integer array
    func test780_splitIntegerArray() throws {
        let array = CBOR.array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)])
        let data = Data(array.encode())

        let items = try splitCborArray(data)
        XCTAssertEqual(items.count, 3)

        for (i, item) in items.enumerated() {
            let decoded = try CBOR.decode([UInt8](item))
            XCTAssertEqual(decoded, .unsignedInt(UInt64(i + 1)))
        }
    }

    // TEST955: splitCborArray with nested maps
    func test955_splitMapArray() throws {
        let map1 = CBOR.map([.utf8String("name"): .utf8String("Alice")])
        let map2 = CBOR.map([.utf8String("name"): .utf8String("Bob")])
        let array = CBOR.array([map1, map2])
        let data = Data(array.encode())

        let items = try splitCborArray(data)
        XCTAssertEqual(items.count, 2)

        let decoded1 = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(decoded1, map1)
        let decoded2 = try CBOR.decode([UInt8](items[1]))
        XCTAssertEqual(decoded2, map2)
    }

    // TEST782: splitCborArray rejects non-array input
    func test782_splitNonArray() {
        let text = CBOR.utf8String("not an array")
        let data = Data(text.encode())

        XCTAssertThrowsError(try splitCborArray(data)) { error in
            guard let seqError = error as? CborSequenceError else {
                XCTFail("Expected CborSequenceError, got \(error)")
                return
            }
            if case .notAnArray = seqError {
                // expected
            } else {
                XCTFail("Expected .notAnArray, got \(seqError)")
            }
        }
    }

    // TEST783: splitCborArray rejects empty array
    func test783_splitEmptyArray() {
        let array = CBOR.array([])
        let data = Data(array.encode())

        XCTAssertThrowsError(try splitCborArray(data)) { error in
            guard let seqError = error as? CborSequenceError else {
                XCTFail("Expected CborSequenceError, got \(error)")
                return
            }
            if case .emptyArray = seqError {
                // expected
            } else {
                XCTFail("Expected .emptyArray, got \(seqError)")
            }
        }
    }

    // TEST784: splitCborArray rejects invalid CBOR bytes
    func test784_splitInvalidCbor() {
        // 0xFF 0xFE 0xFD is garbage — SwiftCBOR may decode it as a non-array
        // value rather than failing outright, so accept either error variant.
        let data = Data([0xFF, 0xFE, 0xFD])
        XCTAssertThrowsError(try splitCborArray(data)) { error in
            guard let seqError = error as? CborSequenceError else {
                XCTFail("Expected CborSequenceError, got \(error)")
                return
            }
            switch seqError {
            case .deserializationError, .notAnArray:
                break // both acceptable for garbage input
            default:
                XCTFail("Expected .deserializationError or .notAnArray, got \(seqError)")
            }
        }
    }

    // TEST785: assembleCborArray creates array from individual items
    func test785_assembleIntegerArray() throws {
        let items: [Data] = [
            Data(CBOR.unsignedInt(10).encode()),
            Data(CBOR.unsignedInt(20).encode()),
            Data(CBOR.unsignedInt(30).encode()),
        ]

        let assembled = try assembleCborArray(items)

        let decoded = try CBOR.decode([UInt8](assembled))
        guard case .array(let values) = decoded else {
            XCTFail("Expected CBOR array")
            return
        }
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], .unsignedInt(10))
        XCTAssertEqual(values[1], .unsignedInt(20))
        XCTAssertEqual(values[2], .unsignedInt(30))
    }

    // TEST786: split then assemble roundtrip preserves data
    func test786_roundtripSplitAssemble() throws {
        let original = CBOR.array([
            .utf8String("hello"),
            .boolean(true),
            .unsignedInt(42),
            .byteString([1, 2, 3]),
        ])
        let originalBytes = Data(original.encode())

        let items = try splitCborArray(originalBytes)
        XCTAssertEqual(items.count, 4)

        let reassembled = try assembleCborArray(items)
        let decoded = try CBOR.decode([UInt8](reassembled))
        XCTAssertEqual(decoded, original)
    }

    // TEST956: assemble then split roundtrip preserves data
    func test956_roundtripAssembleSplit() throws {
        let items: [Data] = [
            Data(CBOR.utf8String("a").encode()),
            Data(CBOR.utf8String("b").encode()),
        ]

        let assembled = try assembleCborArray(items)
        let splitBack = try splitCborArray(assembled)

        XCTAssertEqual(splitBack.count, 2)
        XCTAssertEqual(splitBack[0], items[0])
        XCTAssertEqual(splitBack[1], items[1])
    }

    // MARK: - Stream Tests

    // TEST822: collectBytes vs collectCborSequence produce different results for same input
    func test822_collectBytesVsSequence() throws {
        // With byteString chunks, collectBytes extracts inner bytes while
        // collectCborSequence preserves CBOR encoding

        let page = CBOR.byteString([0xDE, 0xAD, 0xBE, 0xEF])
        let chunks: [Result<CBOR, StreamError>] = [.success(page)]

        // Test collectBytes (scalar path)
        var idx1 = 0
        let iter1 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx1 < chunks.count else { return nil }
            let c = chunks[idx1]; idx1 += 1; return c
        }
        let scalarStream = Bifaci.InputStream(mediaUrn: "media:test", rx: iter1)
        let scalarResult = try scalarStream.collectBytes()

        // Test collectCborSequence (list path)
        var idx2 = 0
        let iter2 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx2 < chunks.count else { return nil }
            let c = chunks[idx2]; idx2 += 1; return c
        }
        let listStream = Bifaci.InputStream(mediaUrn: "media:test;list", rx: iter2)
        let listResult = try listStream.collectCborSequence()

        // Scalar extracts inner bytes: [0xDE, 0xAD, 0xBE, 0xEF]
        XCTAssertEqual(scalarResult, Data([0xDE, 0xAD, 0xBE, 0xEF]))

        // List preserves CBOR encoding: CBOR byteString header + [0xDE, 0xAD, 0xBE, 0xEF]
        XCTAssertNotEqual(listResult, scalarResult,
            "collectCborSequence must differ from collectBytes — it includes CBOR framing")
        XCTAssertGreaterThan(listResult.count, scalarResult.count,
            "CBOR sequence includes encoding overhead")

        // Verify the CBOR sequence is valid
        let items = try splitCborSequence(listResult)
        XCTAssertEqual(items.count, 1)
        let decoded = try CBOR.decode([UInt8](items[0]))
        XCTAssertEqual(decoded, page)
    }
}
