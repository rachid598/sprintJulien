import Foundation
import SwiftData
import SprintTimerCore

/// Paths stored in the document are relative to Application Support/Races/<UUID>.
enum RaceFiles {
    static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("Races", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func directory(for id: UUID) throws -> URL {
        let url = try root().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

@MainActor
final class PersistenceService {
    let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func save(_ document: RaceDocument) throws {
        // Keep an independent portable JSON copy, also useful for recovery/export.
        try RaceFiles.write(document, to: RaceFiles.directory(for: document.id).appendingPathComponent("race.json"))
        let id = document.id
        let request = FetchDescriptor<StoredRace>(predicate: #Predicate { $0.id == id })
        if let stored = try context.fetch(request).first {
            stored.name = document.name
            stored.date = document.date
            stored.payload = try JSONEncoder().encode(document)
        } else {
            context.insert(try StoredRace(document: document))
        }
        try context.save()
    }

    func recover(_ stored: StoredRace) throws -> RaceDocument {
        var document = try stored.document()
        let manifestURL = try RaceFiles.directory(for: document.id).appendingPathComponent("capture.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let manifest = try JSONDecoder().decode(CaptureManifest.self, from: Data(contentsOf: manifestURL))
            if !manifest.frames.isEmpty { document.capture = manifest }
        }
        return document
    }

    func delete(_ stored: StoredRace) throws {
        let directory = try RaceFiles.root().appendingPathComponent(stored.id.uuidString)
        // Removing media first prevents a silent orphan if deletion is denied.
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        context.delete(stored)
        try context.save()
    }
}
