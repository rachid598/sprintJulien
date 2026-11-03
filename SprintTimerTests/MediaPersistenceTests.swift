import XCTest
import CoreVideo
import CoreGraphics
import ImageIO
import SwiftData
import SprintTimerCore
@testable import SprintTimer

final class MediaPersistenceTests: XCTestCase {
    func testPhotoFinishExtractsOrderedStripsWithPaddedSourceStride() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = PhotoFinishEngine(directory: directory, stripWidth: 2, linePosition: 0.5)
        let first = try makeBuffer(frame: 0)
        let second = try makeBuffer(frame: 1)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(first), 7 * 4, "The fixture must exercise row padding")
        try engine.append(first, frameIndex: 0)
        try engine.append(second, frameIndex: 1)
        try engine.flush()
        try engine.flush() // Empty flush must not create a duplicate tile.
        XCTAssertEqual(engine.tiles.count, 1)
        let tile = try XCTUnwrap(engine.tiles.first)
        XCTAssertEqual(tile.startFrame, 0)
        XCTAssertEqual(tile.frameCount, 2)
        XCTAssertEqual(tile.pixelWidth, 4)
        XCTAssertEqual(tile.pixelHeight, 3)
        let pixels = try readRGBA(directory.appendingPathComponent(tile.relativePath))
        XCTAssertEqual(pixels.width, 4, "The final tile must omit unfilled capacity")
        XCTAssertEqual(pixels.height, 3)
        for row in 0..<3 {
            for column in 0..<4 {
                let frame = column / 2
                let sourceColumn = 2 + column % 2
                let expected = color(x: sourceColumn, y: row, frame: frame)
                let offset = (row * pixels.width + column) * 4
                for component in 0..<4 {
                    XCTAssertLessThanOrEqual(abs(Int(pixels.bytes[offset + component]) - Int(expected[component])), 1,
                                   "Wrong pixel at row \(row), column \(column), component \(component)")
                }
            }
        }
    }

    func testPhotoFinishTileRolloverKeepsFrameIndices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = PhotoFinishEngine(directory: directory, stripWidth: 1, linePosition: 1)
        let buffer = try makeBuffer(frame: 0)
        for index in 41..<298 { try engine.append(buffer, frameIndex: index) }
        try engine.flush()
        XCTAssertEqual(engine.tiles.map(\.startFrame), [41, 297])
        XCTAssertEqual(engine.tiles.map(\.frameCount), [256, 1])
        XCTAssertEqual(engine.tiles.map(\.pixelWidth), [256, 1])
        for tile in engine.tiles {
            let decoded = try readRGBA(directory.appendingPathComponent(tile.relativePath))
            XCTAssertEqual(decoded.width, tile.pixelWidth)
            XCTAssertEqual(decoded.height, tile.pixelHeight)
        }
    }

    @MainActor
    func testPersistenceRoundTripUpdateRecoveryAndDelete() async throws {
        let schema = Schema([StoredRace.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let service = PersistenceService(context: context)
        let raceID = UUID()
        let directory = try RaceFiles.directory(for: raceID)
        defer { try? FileManager.default.removeItem(at: directory) }
        let participant = Participant(name: "Julien", bib: "17", lane: "3")
        var document = RaceDocument(id: raceID, name: "Course test", distance: 50, mode: .photo,
                                    participants: [participant])
        try service.save(document)

        document.name = "Finale mise à jour"
        document.elapsedSeconds = 12.45
        document.results = [RaceResult(participantID: participant.id, elapsedSeconds: 12.34,
                                       source: "Photo-finish", frameIndex: 0)]
        try service.save(document)

        // A distinct context must decode the saved payload, rather than reuse a UI value.
        let reloadedContext = ModelContext(container)
        let stored = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<StoredRace>()).first)
        XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<StoredRace>()), 1)
        XCTAssertEqual(stored.id, raceID)
        XCTAssertEqual(stored.name, document.name)
        XCTAssertEqual(try stored.document(), document)
        let portable = try JSONDecoder().decode(RaceDocument.self, from: Data(contentsOf: directory.appendingPathComponent("race.json")))
        XCTAssertEqual(portable, document)

        // Simulate recovery of capture metadata written after the last SwiftData save.
        let stamp = FrameStamp(index: 0, presentationSeconds: 200, hostSeconds: 200,
                               elapsedSeconds: 12.34, motionScore: 0.2)
        let recoveredCapture = CaptureManifest(raceID: raceID, mode: .photo, frames: [stamp],
                                              droppedFrames: 2, startHostSeconds: 187.66)
        try RaceFiles.write(recoveredCapture, to: directory.appendingPathComponent("capture.json"))
        let reloadedService = PersistenceService(context: reloadedContext)
        let recovered = try reloadedService.recover(stored)
        XCTAssertEqual(recovered.capture, recoveredCapture)
        XCTAssertEqual(recovered.results, document.results)
        XCTAssertEqual(recovered.participants, document.participants)

        try reloadedService.delete(stored)
        XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<StoredRace>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testHostClockIsFiniteAndNonDecreasing() {
        let first = HostClock.now
        let second = HostClock.now
        XCTAssertTrue(first.isFinite)
        XCTAssertGreaterThanOrEqual(second, first)
    }

    private func color(x: Int, y: Int, frame: Int) -> [UInt8] {
        [UInt8(20 + x * 25), UInt8(30 + y * 70), UInt8(15 + frame * 100), 255]
    }

    private func makeBuffer(frame: Int) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferBytesPerRowAlignmentKey: 64,
                                         kCVPixelBufferCGImageCompatibilityKey: true,
                                         kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 7, 3, kCVPixelFormatType_32BGRA,
                                           attributes as CFDictionary, &result), kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        base.update(repeating: 238, count: stride * 3)
        for y in 0..<3 {
            for x in 0..<7 {
                let rgba = color(x: x, y: y, frame: frame)
                let offset = y * stride + x * 4
                base[offset] = rgba[2]; base[offset + 1] = rgba[1]
                base[offset + 2] = rgba[0]; base[offset + 3] = rgba[3]
            }
        }
        return buffer
    }

    private func readRGBA(_ url: URL) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var output = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try output.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (image.width, image.height, output)
    }
}
