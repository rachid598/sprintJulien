import Foundation
import SwiftData
import SprintTimerCore

@Model
final class StoredRace {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var payload: Data

    init(document: RaceDocument) throws {
        id = document.id
        name = document.name
        date = document.date
        payload = try JSONEncoder().encode(document)
    }

    func document() throws -> RaceDocument { try JSONDecoder().decode(RaceDocument.self, from: payload) }
}
