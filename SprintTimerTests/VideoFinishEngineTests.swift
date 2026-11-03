import XCTest
@preconcurrency import AVFoundation
import CoreVideo
@testable import SprintTimer

final class VideoFinishEngineTests: XCTestCase {
    @MainActor
    func testRecordedMoviePreservesThreeNonUniformFrameTimestampsAndDimensions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = try VideoFinishEngine(directory: directory)
        let sourceTimes = [1000.0, 1000.02, 1000.07]
        for (index, time) in sourceTimes.enumerated() {
            let sample = try makeSample(seconds: time, frame: index)
            try await appendWhenReady(sample, to: engine)
        }
        let warning: String? = await withCheckedContinuation { continuation in
            engine.finish { continuation.resume(returning: $0) }
        }
        XCTAssertNil(warning, "The actual AVAssetWriter must finish successfully")

        let url = directory.appendingPathComponent(engine.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)

        // Decode the produced movie rather than inspecting only the input fixture
        // or our timing manifest. AVAssetWriter rebases the first source PTS to 0.
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading(), reader.error?.localizedDescription ?? "Reader did not start")

        var decodedTimes: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(CVPixelBufferGetWidth(image), 128)
            XCTAssertEqual(CVPixelBufferGetHeight(image), 96)
            decodedTimes.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
            // A corrupt loop must not make this fixture test unbounded.
            if decodedTimes.count > sourceTimes.count + 1 { break }
        }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "Reader did not complete")
        XCTAssertEqual(decodedTimes.count, sourceTimes.count)
        guard decodedTimes.count == sourceTimes.count else { return }
        XCTAssertEqual(decodedTimes[0], 0, accuracy: 0.001)
        for index in 1..<decodedTimes.count {
            XCTAssertEqual(decodedTimes[index] - decodedTimes[index - 1],
                           sourceTimes[index] - sourceTimes[index - 1], accuracy: 0.001,
                           "Real movie timing must retain gaps instead of inventing a constant frame rate")
        }
        XCTAssertEqual(decodedTimes[2], 0.07, accuracy: 0.001)

        // Exercise the exact-frame extraction used by VideoReviewView, not only
        // sequential decoding. A selected timestamp must identify its own image.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for relativeSeconds in [0.0, 0.02, 0.07] {
            let requested = CMTime(seconds: relativeSeconds, preferredTimescale: 1_000_000_000)
            let result = try await generator.image(at: requested)
            XCTAssertEqual(result.image.width, 128)
            XCTAssertEqual(result.image.height, 96)
            XCTAssertEqual(CMTimeGetSeconds(result.actualTime), relativeSeconds, accuracy: 0.003,
                           "An exact seek must decode the image for the selected timestamp")
        }
    }

    @MainActor
    func testFinishingWithoutFramesReturnsExplicitWarning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = try VideoFinishEngine(directory: directory)
        let warning: String? = await withCheckedContinuation { continuation in
            engine.finish { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(warning, "Aucune image vidéo enregistrée.")
    }

    /// Offline test fixture: retry a temporarily backpressured encoder for at
    /// most one second per frame. Production capture never uses this waiting loop.
    @MainActor
    private func appendWhenReady(_ sample: CMSampleBuffer, to engine: VideoFinishEngine) async throws {
        for _ in 0..<100 {
            if try engine.append(sample) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The encoder never accepted the synthetic frame within one second")
        throw VideoFixtureError.encoderNotReady
    }

    private func makeSample(seconds: Double, frame: Int) throws -> CMSampleBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 128, 96, kCVPixelFormatType_32BGRA,
                                           attributes as CFDictionary, &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        do {
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            base.update(repeating: 0, count: stride * 96)
            for row in 0..<96 {
                for column in 0..<128 {
                    let offset = row * stride + column * 4
                    base[offset] = UInt8(20 + frame * 50)
                    base[offset + 1] = 80
                    base[offset + 2] = 180
                    base[offset + 3] = 255
                }
            }
        }
        var optionalDescription: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                   imageBuffer: buffer,
                                                                   formatDescriptionOut: &optionalDescription), noErr)
        let description = try XCTUnwrap(optionalDescription)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 100),
                                         presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 60_000),
                                         decodeTimeStamp: .invalid)
        var optionalSample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                                imageBuffer: buffer, formatDescription: description,
                                                                sampleTiming: &timing, sampleBufferOut: &optionalSample), noErr)
        return try XCTUnwrap(optionalSample)
    }
}

private enum VideoFixtureError: Error { case encoderNotReady }
