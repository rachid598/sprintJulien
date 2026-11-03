import XCTest
import UIKit
import PDFKit
import CoreVideo
import SprintTimerCore
@testable import SprintTimer

final class ExportTests: XCTestCase {
    @MainActor
    func testCSVExportWritesReadableUTF8WithAccentsAndQuotes() async throws {
        let participant = Participant(name: "Élodie \"Rapide\", Léa", bib: "É17", lane: "2")
        let race = RaceDocument(name: "Finale d’été", participants: [participant],
                                results: [RaceResult(participantID: participant.id, elapsedSeconds: 12.345,
                                                     source: "Photo-finish")])
        let url = try ExportService.csv(race)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.pathExtension, "csv")
        let data = try Data(contentsOf: url)
        let content = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(content.contains("Finale d’été"))
        XCTAssertTrue(content.contains("\"Élodie \"\"Rapide\"\", Léa\""))
        XCTAssertTrue(content.contains("É17"))
        XCTAssertTrue(content.contains("12.345000"))
        XCTAssertTrue(content.hasSuffix("\r\n"))
        XCTAssertFalse(content.contains("\u{FFFD}"), "UTF-8 export must preserve accented names")
    }

    @MainActor
    func testPDFExportPaginatesAndIncludesAll150Participants() async throws {
        let participants = (1...150).map { Participant(name: "Participant \($0)", bib: String($0), lane: "1") }
        let results = participants.enumerated().map { index, participant in
            RaceResult(participantID: participant.id, elapsedSeconds: 10 + Double(index) / 10, source: "Manuel")
        }
        let race = RaceDocument(name: "Classe EPS — 150 arrivées", distance: 100,
                                participants: participants, results: results)
        let url = try ExportService.pdf(race)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1, "A large results list must span multiple readable pages")
        let allText = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for index in 1...150 {
            XCTAssertTrue(allText.contains("Participant \(index)"), "Missing participant \(index) in exported PDF")
        }
        XCTAssertTrue(allText.contains("précision non certifiée"))
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            XCTAssertEqual(page.bounds(for: .mediaBox).width, 595, accuracy: 0.1)
            XCTAssertEqual(page.bounds(for: .mediaBox).height, 842, accuracy: 0.1)
        }
    }

    @MainActor
    func testPhotoPNGAndOriginalsContainRealTilesAndTimingMetadata() async throws {
        let raceID = UUID()
        let directory = try RaceFiles.directory(for: raceID)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = PhotoFinishEngine(directory: directory, stripWidth: 4, linePosition: 0.5)
        let buffer = try makePixelBuffer()
        for index in 0..<3 { try engine.append(buffer, frameIndex: index) }
        try engine.flush()
        let frames = (0..<3).map { index in
            FrameStamp(index: index, presentationSeconds: 200 + Double(index) / 120,
                       hostSeconds: 200 + Double(index) / 120,
                       elapsedSeconds: 12 + Double(index) / 120)
        }
        let manifest = CaptureManifest(raceID: raceID, mode: .photo, imageWidth: 12, imageHeight: 8,
                                       stripWidth: 4, frames: frames, tiles: engine.tiles,
                                       actualFPS: 120, startHostSeconds: 188)
        let participant = Participant(name: "Julien")
        let race = RaceDocument(id: raceID, name: "Photo exportée", participants: [participant],
                                results: [RaceResult(participantID: participant.id, elapsedSeconds: frames[1].elapsedSeconds,
                                                     source: "Photo-finish", frameIndex: 1)],
                                capture: manifest, elapsedSeconds: 13)
        let pngURL = try ExportService.photo(race)
        defer { try? FileManager.default.removeItem(at: pngURL.deletingLastPathComponent()) }
        let png = try Data(contentsOf: pngURL)
        XCTAssertTrue(png.starts(with: Data([137, 80, 78, 71, 13, 10, 26, 10])))
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(image.width, 12)
        XCTAssertEqual(image.height, 72, "Export includes the original image height plus a timing header")

        let originals = try ExportService.originals(race)
        let names = Set(originals.map(\.lastPathComponent))
        XCTAssertTrue(names.contains("race.json"))
        XCTAssertTrue(names.contains("capture.json"))
        for tile in engine.tiles { XCTAssertTrue(names.contains(tile.relativePath)) }
        XCTAssertTrue(originals.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let restoredRace = try JSONDecoder().decode(RaceDocument.self, from: Data(contentsOf: directory.appendingPathComponent("race.json")))
        let restoredCapture = try JSONDecoder().decode(CaptureManifest.self, from: Data(contentsOf: directory.appendingPathComponent("capture.json")))
        XCTAssertEqual(restoredRace, race)
        XCTAssertEqual(restoredCapture, manifest)
        XCTAssertEqual(restoredCapture.frames.map(\.presentationSeconds), frames.map(\.presentationSeconds))
        XCTAssertEqual(restoredCapture.frames.map(\.elapsedSeconds), frames.map(\.elapsedSeconds))
        let original = try XCTUnwrap(UIImage(contentsOfFile: directory.appendingPathComponent(engine.tiles[0].relativePath).path)?.cgImage)
        XCTAssertEqual(original.width, 12)
        XCTAssertEqual(original.height, 8)
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 8, kCVPixelFormatType_32BGRA,
                                           nil, &result), kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        base.update(repeating: 0, count: stride * 8)
        for row in 0..<8 {
            for column in 0..<16 {
                let offset = row * stride + column * 4
                base[offset] = 40; base[offset + 1] = UInt8(row * 25)
                base[offset + 2] = UInt8(column * 12); base[offset + 3] = 255
            }
        }
        return buffer
    }
}
