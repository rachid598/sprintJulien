import Foundation

public enum ResultsManager {
    /// Tri stable des temps valides; les mesures invalides sont placées en fin.
    public static func ranked(_ results: [RaceResult]) -> [RaceResult] {
        results.enumerated().sorted { left, right in
            let lhs = left.element.elapsedSeconds
            let rhs = right.element.elapsedSeconds
            let leftValid = lhs.isFinite && lhs >= 0
            let rightValid = rhs.isFinite && rhs >= 0
            if leftValid != rightValid { return leftValid }
            if leftValid, lhs != rhs { return lhs < rhs }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// CSV RFC 4180 UTF-8, virgule et CRLF. Les champs textuels susceptibles
    /// d'être interprétés comme formules sont précédés d'une apostrophe.
    public static func csv(race: RaceDocument) -> String {
        let header = ["Course", "Date", "Distance (m)", "Rang", "Dossard", "Couloir", "Participant", "Temps (s)", "Source"]
        var rows = [header.map(quoted).joined(separator: ",")]
        let people = Dictionary(race.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let date = ISO8601DateFormatter().string(from: race.date)
        for (index, result) in ranked(race.results).enumerated() {
            let person = result.participantID.flatMap { people[$0] }
            let elapsed = result.elapsedSeconds.isFinite && result.elapsedSeconds >= 0
                ? String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), result.elapsedSeconds) : ""
            let values = [
                safeText(race.name), date, decimal(race.distance), String(index + 1),
                safeText(person?.bib ?? ""), safeText(person?.lane ?? ""),
                safeText(person?.name ?? "Non attribué"), elapsed, safeText(result.source)
            ]
            rows.append(values.map(quoted).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func safeText(_ value: String) -> String {
        let trimmed = value.drop(while: { $0.isWhitespace || $0.isNewline })
        guard let first = trimmed.first else { return value }
        return ["=", "+", "-", "@"].contains(first) ? "'" + value : value
    }
}
