import Foundation
import Testing
@testable import SprintTimerCore

struct ResultsTests {
    @Test func testRankingUsesRawPrecisionAndStableTies() {
        let first = RaceResult(elapsedSeconds: 10.004)
        let second = RaceResult(elapsedSeconds: 10.003)
        let tied = RaceResult(elapsedSeconds: 10.003)
        let invalid = RaceResult(elapsedSeconds: -.infinity)
        #expect(ResultsManager.ranked([first, second, tied, invalid]).map(\.id) == [second.id, tied.id, first.id, invalid.id])
    }

    @Test func testCSVQuotesNewlinesAndProtectsTextFormulaInjection() {
        let person = Participant(name: "=HYPERLINK(\"https://example.org\")\nÉlève", bib: "+2", lane: "3")
        let race = RaceDocument(
            name: "Course, \"EPS\"", date: Date(timeIntervalSince1970: 0), distance: 100,
            participants: [person], results: [RaceResult(participantID: person.id, elapsedSeconds: 12.123456, source: "@capture")]
        )
        let csv = ResultsManager.csv(race: race)
        #expect(csv.contains("\"Course, \"\"EPS\"\"\""))
        #expect(csv.contains("\"'=HYPERLINK(\"\"https://example.org\"\")\nÉlève\""))
        #expect(csv.contains("\"'+2\""))
        #expect(csv.contains("\"12.123456\""))
        #expect(csv.contains("\"'@capture\""))
        #expect(csv.hasSuffix("\r\n"))
        #expect(csv.contains("1970-01-01T00:00:00Z"))
    }

    @Test func testCSVDuplicateParticipantsAndUnassignedAreHandled() {
        let participant = Participant(name: "Élève")
        let race = RaceDocument(
            name: " \t=course", participants: [participant, participant],
            results: [RaceResult(elapsedSeconds: 1), RaceResult(elapsedSeconds: .nan)]
        )
        let csv = ResultsManager.csv(race: race)
        #expect(csv.contains("\"' \t=course\""))
        #expect(csv.contains("\"Non attribué\""))
        #expect(!(csv.contains("nan")))
    }

    @Test func testRaceAndCaptureRoundTripPreserveOriginalTimingAndMetadata() throws {
        let person = Participant(name: "Élève", bib: "12", lane: "4")
        var race = RaceDocument(name: "100 mètres", participants: [person])
        race.settings.startMode = .microphone
        race.settings.startOffsetSeconds = 0.25
        race.capture = CaptureManifest(
            raceID: race.id, mode: .photo, imageWidth: 2, imageHeight: 100, stripWidth: 2,
            frames: [FrameStamp(index: 0, presentationSeconds: 1024.123456789, hostSeconds: 1024.123456789, elapsedSeconds: 12.123456789)],
            tiles: [PhotoTile(relativePath: "tile-0.png", startFrame: 0, frameCount: 1, pixelWidth: 2, pixelHeight: 100)],
            droppedFrames: 1, actualFPS: 120, startHostSeconds: 1012,
            startOffsetSeconds: 0.25, interrupted: true, warnings: ["Capture interrompue"]
        )
        race.results = [RaceResult(participantID: person.id, elapsedSeconds: 12.123456789, source: "photo", frameIndex: 0)]
        let encoder = JSONEncoder()
        let data = try encoder.encode(race)
        let decoded = try JSONDecoder().decode(RaceDocument.self, from: data)
        #expect(decoded == race)
        #expect(decoded.capture?.frames.first?.presentationSeconds == 1024.123456789)
    }
}
