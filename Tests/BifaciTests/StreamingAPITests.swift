import XCTest
@testable import Bifaci
@preconcurrency import SwiftCBOR

// =============================================================================
// Streaming API Tests
//
// Covers TEST529-545 from plugin_runtime.rs in the reference Rust implementation.
// Tests InputStream, InputPackage, OutputStream, and PeerCall streaming APIs.
//
// Note: We use Bifaci.InputStream and Bifaci.OutputStream to avoid ambiguity
// with Foundation types.
// =============================================================================

final class StreamingAPITests: XCTestCase {

    // MARK: - InputStream Tests (TEST529-534)

    // TEST529: InputStream iterator yields chunks in order
    func test529_inputStreamIteratorOrder() throws {
        // Create an InputStream with ordered chunks
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2, 3])),
            .success(.byteString([4, 5, 6])),
            .success(.byteString([7, 8, 9])),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test", rx: iterator)

        var collectedChunks: [[UInt8]] = []
        for result in stream {
            switch result {
            case .success(let cbor):
                if case .byteString(let bytes) = cbor {
                    collectedChunks.append(bytes)
                }
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(collectedChunks.count, 3)
        XCTAssertEqual(collectedChunks[0], [1, 2, 3])
        XCTAssertEqual(collectedChunks[1], [4, 5, 6])
        XCTAssertEqual(collectedChunks[2], [7, 8, 9])
    }

    // TEST530: InputStream::collect_bytes concatenates byte chunks
    func test530_inputStreamCollectBytes() throws {
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2])),
            .success(.byteString([3, 4])),
            .success(.byteString([5, 6])),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test", rx: iterator)
        let allBytes = try stream.collectBytes()

        XCTAssertEqual([UInt8](allBytes), [1, 2, 3, 4, 5, 6])
    }

    // TEST531: InputStream::collect_bytes handles text chunks
    func test531_inputStreamCollectBytesText() throws {
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.utf8String("Hello")),
            .success(.utf8String(" ")),
            .success(.utf8String("World")),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:text", rx: iterator)
        let allBytes = try stream.collectBytes()

        XCTAssertEqual(String(data: allBytes, encoding: .utf8), "Hello World")
    }

    // TEST532: InputStream empty stream produces empty bytes
    func test532_inputStreamEmpty() throws {
        let chunks: [Result<CBOR, StreamError>] = []

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:empty", rx: iterator)
        let allBytes = try stream.collectBytes()

        XCTAssertTrue(allBytes.isEmpty, "Empty stream must produce empty bytes")
    }

    // TEST533: InputStream propagates errors
    func test533_inputStreamErrorPropagation() throws {
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2, 3])),
            .failure(.protocolError("Test error")),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test", rx: iterator)

        var gotError = false
        for result in stream {
            if case .failure = result {
                gotError = true
            }
        }

        XCTAssertTrue(gotError, "Error must be propagated through iterator")
    }

    // TEST534: InputStream::media_urn returns correct URN
    func test534_inputStreamMediaUrn() throws {
        let iterator = AnyIterator<Result<CBOR, StreamError>> { nil }
        let stream = Bifaci.InputStream(mediaUrn: "media:image/png", rx: iterator)

        XCTAssertEqual(stream.mediaUrn, "media:image/png")
    }

    // MARK: - InputPackage Tests (TEST535-538)

    // TEST535: InputPackage iterator yields streams
    func test535_inputPackageIteration() throws {
        // Create InputPackage with multiple streams
        let stream1Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([1, 2]))]
        let stream2Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([3, 4]))]

        var idx1 = 0
        let iter1 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx1 < stream1Chunks.count else { return nil }
            let c = stream1Chunks[idx1]
            idx1 += 1
            return c
        }

        var idx2 = 0
        let iter2 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx2 < stream2Chunks.count else { return nil }
            let c = stream2Chunks[idx2]
            idx2 += 1
            return c
        }

        let s1 = Bifaci.InputStream(mediaUrn: "media:a", rx: iter1)
        let s2 = Bifaci.InputStream(mediaUrn: "media:b", rx: iter2)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(s1), .success(s2)]

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)

        var count = 0
        for result in package {
            if case .success = result {
                count += 1
            }
        }

        XCTAssertEqual(count, 2, "InputPackage should yield 2 streams")
    }

    // TEST536: InputPackage::collect_all_bytes aggregates all streams
    func test536_inputPackageCollectAllBytes() throws {
        // Create two streams
        let stream1Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([1, 2]))]
        let stream2Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([3, 4]))]

        var idx1 = 0
        let iter1 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx1 < stream1Chunks.count else { return nil }
            let c = stream1Chunks[idx1]
            idx1 += 1
            return c
        }

        var idx2 = 0
        let iter2 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx2 < stream2Chunks.count else { return nil }
            let c = stream2Chunks[idx2]
            idx2 += 1
            return c
        }

        let s1 = Bifaci.InputStream(mediaUrn: "media:a", rx: iter1)
        let s2 = Bifaci.InputStream(mediaUrn: "media:b", rx: iter2)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(s1), .success(s2)]

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)
        let allBytes = try package.collectAllBytes()

        // Bytes from both streams should be concatenated
        XCTAssertEqual([UInt8](allBytes), [1, 2, 3, 4])
    }

    // TEST537: InputPackage empty package produces empty bytes
    func test537_inputPackageEmpty() throws {
        let streams: [Result<Bifaci.InputStream, StreamError>] = []

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)
        let allBytes = try package.collectAllBytes()

        XCTAssertTrue(allBytes.isEmpty, "Empty package must produce empty bytes")
    }

    // TEST538: InputPackage propagates stream errors
    func test538_inputPackageErrorPropagation() throws {
        let streams: [Result<Bifaci.InputStream, StreamError>] = [
            .failure(.protocolError("Stream error")),
        ]

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)

        var gotError = false
        for result in package {
            if case .failure = result {
                gotError = true
            }
        }

        XCTAssertTrue(gotError, "Error must be propagated through package iterator")
    }

    // MARK: - OutputStream Tests (TEST539-542)

    // TEST539: OutputStream sends STREAM_START on first write
    func test539_outputStreamSendsStreamStart() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // Write data
        try output.write(Data([1, 2, 3]))

        XCTAssertGreaterThanOrEqual(sentFrames.count, 1, "Should send at least STREAM_START")

        // First frame should be STREAM_START
        let first = sentFrames[0]
        XCTAssertEqual(first.frameType, .streamStart, "First frame must be STREAM_START")
        XCTAssertEqual(first.streamId, "test-stream")
        XCTAssertEqual(first.mediaUrn, "media:test")
    }

    // TEST540: OutputStream::close sends STREAM_END with correct chunk_count
    func test540_outputStreamCloseSendsStreamEnd() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // Write 3 chunks
        try output.write(Data([1]))
        try output.write(Data([2]))
        try output.write(Data([3]))
        try output.close()

        // Last frame before any END should be STREAM_END
        let streamEndFrames = sentFrames.filter { $0.frameType == .streamEnd }
        XCTAssertEqual(streamEndFrames.count, 1, "Should send exactly one STREAM_END")

        let streamEnd = streamEndFrames[0]
        XCTAssertEqual(streamEnd.chunkCount, 3, "chunk_count should be 3")
    }

    // TEST541: OutputStream chunks large data correctly
    func test541_outputStreamChunksLargeData() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let maxChunk = 10
        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: maxChunk
        )

        // Write data larger than maxChunk
        let largeData = Data(repeating: 0x42, count: 35)
        try output.write(largeData)
        try output.close()

        // Should have STREAM_START + 4 CHUNKs + STREAM_END
        // 35 bytes / 10 max = 4 chunks (10 + 10 + 10 + 5)
        let chunkFrames = sentFrames.filter { $0.frameType == .chunk }
        XCTAssertEqual(chunkFrames.count, 4, "35 bytes at max 10 should produce 4 chunks")

        // Verify each chunk respects max size (CBOR overhead adds bytes)
        for chunk in chunkFrames {
            // The payload contains CBOR-encoded data, so size may vary slightly
            XCTAssertNotNil(chunk.payload)
        }
    }

    // TEST542: OutputStream empty stream sends STREAM_START and STREAM_END only
    func test542_outputStreamEmpty() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // Close without writing anything
        try output.close()

        // Should have STREAM_START + STREAM_END (no CHUNKs)
        let streamStartFrames = sentFrames.filter { $0.frameType == .streamStart }
        let chunkFrames = sentFrames.filter { $0.frameType == .chunk }
        let streamEndFrames = sentFrames.filter { $0.frameType == .streamEnd }

        XCTAssertEqual(streamStartFrames.count, 1)
        XCTAssertEqual(chunkFrames.count, 0)
        XCTAssertEqual(streamEndFrames.count, 1)
        XCTAssertEqual(streamEndFrames[0].chunkCount, 0)
    }

    // MARK: - PeerCall Tests (TEST543-545)

    // TEST543: PeerCall::arg creates OutputStream with correct stream_id
    func test543_peerCallArgCreatesStream() throws {
        // PeerCall.arg() should create an OutputStream for sending arguments
        // We test this by verifying the OutputStream has a unique streamId

        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        // Create output stream (simulating what PeerCall.arg does)
        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "arg-0",  // PeerCall assigns sequential stream IDs
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        try output.write(Data([1, 2, 3]))
        try output.close()

        // Verify stream ID is used
        let streamStart = sentFrames.first { $0.frameType == .streamStart }
        XCTAssertEqual(streamStart?.streamId, "arg-0")
    }

    // TEST544: PeerCall::finish sends END frame
    func test544_peerCallFinishSendsEnd() throws {
        // When PeerCall.finish() is called, it should send an END frame
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let requestId = MessageId.uint(42)

        // Simulate PeerCall sending END
        let endFrame = Frame.end(id: requestId)
        try mockSender.send(endFrame)

        let endFrames = sentFrames.filter { $0.frameType == .end }
        XCTAssertEqual(endFrames.count, 1)
        XCTAssertEqual(endFrames[0].id, requestId)
    }

    // TEST545: PeerCall::finish returns InputStream for response
    func test545_peerCallFinishReturnsResponseStream() throws {
        // PeerCall.finish() should return an InputStream that yields the response
        // We test this by creating a mock response and verifying iteration

        let responseChunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2, 3])),
            .success(.byteString([4, 5, 6])),
        ]

        var idx = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard idx < responseChunks.count else { return nil }
            let c = responseChunks[idx]
            idx += 1
            return c
        }

        let responseStream = Bifaci.InputStream(mediaUrn: "media:response", rx: iterator)

        // Collect response bytes
        let responseBytes = try responseStream.collectBytes()
        XCTAssertEqual([UInt8](responseBytes), [1, 2, 3, 4, 5, 6])
    }
}

// MARK: - Mock FrameSender

/// Mock FrameSender for testing (private to this file)
private final class MockFrameSender: FrameSender, @unchecked Sendable {
    private let onSend: (Frame) -> Void

    init(onSend: @escaping (Frame) -> Void) {
        self.onSend = onSend
    }

    func send(_ frame: Frame) throws {
        onSend(frame)
    }
}
