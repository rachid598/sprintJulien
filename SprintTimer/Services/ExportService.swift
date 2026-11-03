import UIKit
import SprintTimerCore

@MainActor
enum ExportService {
    static func csv(_ race: RaceDocument) throws -> URL {
        let url = try output("resultats.csv")
        try Data(ResultsManager.csv(race: race).utf8).write(to: url, options: .atomic)
        return url
    }

    static func pdf(_ race: RaceDocument) throws -> URL {
        let url = try output("resultats.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { context in
            var y = 0.0
            @MainActor func page() {
                context.beginPage()
                text("SprintTimer", x: 40, y: 38, width: 515, size: 24, bold: true)
                text(race.name, x: 40, y: 76, width: 515, size: 17, bold: true)
                text("\(race.date.formatted(date: .abbreviated, time: .shortened)) · \(race.distance.formatted()) m · \(race.mode.title)",
                     x: 40, y: 115, width: 515, size: 10)
                text("Rang    Participant / dossard / couloir", x: 40, y: 150, width: 370, size: 10, bold: true)
                text("Temps (s)", x: 460, y: 150, width: 95, size: 10, bold: true)
                y = 178
            }
            page()
            let ranked = ResultsManager.ranked(race.results)
            if ranked.isEmpty { text("Aucune arrivée marquée.", x: 40, y: y, width: 515, size: 12); y += 40 }
            for (index, result) in ranked.enumerated() {
                if y > 680 { page() }
                let participant = race.participants.first { $0.id == result.participantID }
                let label = participant.map { "\($0.name) · \($0.bib.isEmpty ? "—" : $0.bib) · \($0.lane.isEmpty ? "—" : $0.lane)" } ?? "Arrivée \(index + 1)"
                text("\(index + 1)", x: 40, y: y, width: 30, size: 12)
                text(label, x: 80, y: y, width: 365, size: 12)
                text(TimeDisplay.format(result.elapsedSeconds), x: 460, y: y, width: 95, size: 13, bold: true)
                text(result.source, x: 80, y: y + 19, width: 365, size: 9)
                y += 44
            }
            if y > 650 { page() }
            text("Mesure d’entraînement — précision non certifiée", x: 40, y: y + 18, width: 515, size: 10, bold: true)
            text("L’affichage au centième dépend des horodatages réellement capturés. Réaction humaine, latence audio, exposition et rolling shutter influent sur la mesure. Instant Finish fournit une estimation par mouvement.",
                 x: 40, y: y + 38, width: 515, size: 10, height: 55)
            if let capture = race.capture {
                text("Images : \(capture.frames.count) · pertes signalées : \(capture.droppedFrames) · cadence moyenne : \(capture.actualFPS.formatted(.number.precision(.fractionLength(1)))) i/s\(capture.interrupted ? " · CAPTURE INTERROMPUE" : "")",
                     x: 40, y: y + 100, width: 515, size: 10, height: 45)
            }
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Bounded-size flattened preview. Original full-resolution tiles stay intact.
    static func photo(_ race: RaceDocument) throws -> URL {
        guard let manifest = race.capture, !manifest.tiles.isEmpty, manifest.imageWidth > 0 else {
            throw SprintError.message("Cette course ne contient pas de photo-finish.")
        }
        let folder = try RaceFiles.directory(for: race.id)
        let width = min(16_000, manifest.imageWidth)
        let scale = Double(width) / Double(manifest.imageWidth)
        let height = max(1, min(1800, 16_000_000 / max(1, width), Int(Double(manifest.imageHeight) * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height + 64), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height + 64))
            for tile in manifest.tiles {
                let x = Double(tile.startFrame * manifest.stripWidth) * scale
                if let tileImage = UIImage(contentsOfFile: folder.appendingPathComponent(tile.relativePath).path) {
                    tileImage.draw(in: CGRect(x: x, y: 64, width: Double(tile.pixelWidth) * scale, height: Double(height)))
                }
            }
            for result in race.results {
                guard let frame = result.frameIndex else { continue }
                let x = Double(frame * manifest.stripWidth) * scale
                UIColor.orange.setStroke()
                context.cgContext.setLineWidth(1)
                context.cgContext.move(to: CGPoint(x: x, y: 58))
                context.cgContext.addLine(to: CGPoint(x: x, y: Double(height + 64)))
                context.cgContext.strokePath()
                let participant = race.participants.first { $0.id == result.participantID }
                let label = "\(participant?.name ?? "Arrivée") \(TimeDisplay.format(result.elapsedSeconds)) s"
                (label as NSString).draw(in: CGRect(x: min(x + 3, Double(max(0, width - 160))), y: 32, width: 160, height: 25),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.orange])
            }
            ("SprintTimer · \(race.name) · temps mesurés par bande" as NSString).draw(at: CGPoint(x: 8, y: 8),
                withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: UIColor.white])
        }
        guard let data = image.pngData() else { throw SprintError.message("Export PNG impossible.") }
        let url = try output("photo-finish.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func originals(_ race: RaceDocument) throws -> [URL] {
        let folder = try RaceFiles.directory(for: race.id)
        try RaceFiles.write(race, to: folder.appendingPathComponent("race.json"))
        var paths = ["race.json"]
        if let manifest = race.capture {
            try RaceFiles.write(manifest, to: folder.appendingPathComponent("capture.json"))
            paths += ["capture.json"] + manifest.tiles.map(\.relativePath)
            if let video = manifest.videoFile { paths.append(video) }
        }
        return paths.map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func output(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SprintTimerExports/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }

    private static func text(_ value: String, x: Double, y: Double, width: Double, size: Double, bold: Bool = false, height: Double = 32) {
        (value as NSString).draw(in: CGRect(x: x, y: y, width: width, height: height), withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: UIColor.black])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ view: UIActivityViewController, context: Context) { }
}

import SwiftUI
