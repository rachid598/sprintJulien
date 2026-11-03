import SwiftUI
import SprintTimerCore

struct ResultEditView: View {
    @Environment(\.dismiss) private var dismiss
    let result: RaceResult
    let participant: Participant?
    let save: (String, String, String, Double) -> Void
    @State private var name = ""
    @State private var bib = ""
    @State private var lane = ""
    @State private var seconds = ""
    private var parsed: Double? {
        guard let value = Double(seconds.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                TextField("Dossard", text: $bib)
                TextField("Couloir", text: $lane)
                TextField("Temps en secondes", text: $seconds).keyboardType(.decimalPad)
                Text("Une modification du temps est identifiée comme correction manuelle. Les images et horodatages originaux sont conservés.")
                    .font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Modifier l’arrivée")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") { if let parsed { save(name, bib, lane, parsed); dismiss() } }.disabled(parsed == nil)
                    }
                }
                .onAppear {
                    name = participant?.name ?? ""
                    bib = participant?.bib ?? ""
                    lane = participant?.lane ?? ""
                    // Preserve sub-centisecond precision unless the user changes it.
                    seconds = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), result.elapsedSeconds)
                }
        }
    }
}
