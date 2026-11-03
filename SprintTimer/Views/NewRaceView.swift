import SwiftUI
import SprintTimerCore

struct NewRaceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mode = FinishMode.photo
    @State private var distance = 100
    @State private var customDistance = 100.0
    @State private var settings = RaceSettings()
    @State private var participants: [Participant] = []
    let onCreate: (RaceDocument) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Nom de la course", text: $name).accessibilityIdentifier("race.name")
                    Picker("Distance", selection: $distance) {
                        ForEach([30, 50, 100, 200, 400], id: \.self) { Text("\($0) m").tag($0) }
                        Text("Personnalisée").tag(0)
                    }
                    if distance == 0 { TextField("Distance en mètres", value: $customDistance, format: .number).keyboardType(.decimalPad) }
                    Picker("Mode d’arrivée", selection: $mode) {
                        ForEach(FinishMode.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("race.mode")
                    Text(modeHelp).font(.caption).foregroundStyle(.secondary)
                }
                Section("Départ") {
                    Picker("Déclenchement", selection: $settings.startMode) {
                        ForEach(StartMode.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.startMode == .countdown {
                        Stepper("Compte à rebours : \(Int(settings.countdownSeconds)) s", value: $settings.countdownSeconds, in: 1...60, step: 1)
                    }
                    if settings.startMode == .microphone {
                        LabeledSlider(title: "Seuil sonore", value: $settings.microphoneThreshold, range: 0.02...0.95)
                        Text("Le premier échantillon dépassant le seuil déclenche le départ. Évitez les conversations à proximité et faites un essai.").font(.caption)
                    }
                    TextField("Décalage du départ (s)", value: $settings.startOffsetSeconds, format: .number.precision(.fractionLength(3)))
                        .keyboardType(.numbersAndPunctuation)
                    Text("Décalage positif : ajoute du temps. Le départ avec bip utilise l’instant programmé ; la latence acoustique doit être calibrée.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if mode != .stopwatch {
                    Section("Caméra · réglages avant la course") {
                        LabeledSlider(title: "Position de la ligne", value: $settings.linePosition, range: 0.05...0.95)
                        if mode == .photo {
                            Stepper("Largeur de bande : \(settings.stripWidth) px", value: $settings.stripWidth, in: 1...16)
                        }
                        Picker("Cadence demandée", selection: $settings.requestedFPS) {
                            ForEach([30, 60, 120, 240], id: \.self) { Text("\($0) i/s").tag($0) }
                        }
                        Stepper("Capture maximale : \(Int(settings.maxRecordingDuration)) s", value: $settings.maxRecordingDuration, in: 5...120, step: 5)
                        Text("La cadence dépend du matériel. Vidéo et Instant Finish sont plafonnés à 60 i/s pour l’encodage. La capture photo conserve les bandes originales, sans vidéo complète.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Zone de mouvement") {
                        LabeledSlider(title: "Largeur de zone", value: $settings.regionWidth, range: 0.02...0.4)
                        LabeledSlider(title: "Seuil de variation", value: $settings.motionThreshold, range: 0.01...0.5)
                        Text("Un seuil plus bas augmente la sensibilité.").font(.caption).foregroundStyle(.secondary)
                        Stepper("Temporisation : \(settings.motionCooldown, specifier: "%.1f") s", value: $settings.motionCooldown, in: 0.1...5, step: 0.1)
                        if mode == .instant {
                            Toggle("Confirmer la présence d’une personne (Vision)", isOn: $settings.humanFilter)
                        }
                    }
                }
                Section {
                    ForEach($participants) { $participant in
                        VStack(alignment: .leading) {
                            TextField("Nom du participant", text: $participant.name)
                            HStack {
                                TextField("Dossard", text: $participant.bib)
                                TextField("Couloir", text: $participant.lane)
                            }.font(.caption)
                        }
                    }.onDelete { participants.remove(atOffsets: $0) }
                    Button("Ajouter un participant", systemImage: "person.badge.plus") { participants.append(Participant()) }
                } header: { Text("Participants · \(participants.count)") } footer: {
                    Text("Sans liste, les arrivées sont numérotées. Vous pourrez attribuer un nom lors de l’analyse.")
                }
            }
            .navigationTitle("Nouvelle course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Préparer") {
                        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleaned = participants.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        settings.startOffsetSeconds = max(-10, min(10, settings.startOffsetSeconds.isFinite ? settings.startOffsetSeconds : 0))
                        let meters = distance == 0 ? customDistance : Double(distance)
                        let race = RaceDocument(name: title.isEmpty ? "Course du \(Date().formatted(date: .abbreviated, time: .shortened))" : title,
                            distance: meters.isFinite ? max(1, min(100_000, meters)) : 100,
                            mode: mode, settings: settings, participants: cleaned)
                        onCreate(race)
                    }.bold().accessibilityIdentifier("race.prepare")
                }
            }
        }
    }

    private var modeHelp: String {
        switch mode {
        case .photo: "Bandes verticales horodatées et assemblées pour départager les arrivées."
        case .video: "Vidéo continue, indicateur de mouvement et analyse image par image."
        case .instant: "Détection de mouvement, résultats immédiats estimés et vidéo de contrôle."
        case .stopwatch: "Départ et arrivées manuels, sans caméra."
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary) }
            Slider(value: $value, in: range).accessibilityLabel(title)
        }
    }
}
