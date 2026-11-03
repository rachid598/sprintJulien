import SwiftUI
import SwiftData
import SprintTimerCore

struct RaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var manager: RaceManager
    @State private var shareURLs: [URL] = []
    @State private var sharing = false
    @State private var exporting = false
    @State private var editing: RaceResult?

    init(race: RaceDocument, context: ModelContext, reopening: Bool) {
        _manager = State(initialValue: RaceManager(race: race, context: context, reopening: reopening))
    }

    var body: some View {
        @Bindable var model = manager
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(manager.race.mode.title, systemImage: "flag.checkered").foregroundStyle(.orange).font(.subheadline.bold())
                    Spacer()
                    Text("\(manager.race.distance.formatted()) m").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                clock
                if let error = manager.errorMessage { notice(error, symbol: "exclamationmark.triangle", color: .orange) }
                if let error = manager.saveProblem {
                    notice(error, symbol: "externaldrive.badge.exclamationmark", color: .red)
                    Button("Réessayer la sauvegarde") { manager.persist() }
                }
                if manager.phase == .finished {
                    analysis
                } else {
                    live
                }
                if !manager.race.results.isEmpty || manager.phase == .finished { results }
            }.padding()
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(manager.race.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fermer") { manager.persist(); manager.close(); dismiss() }
                    .disabled(!manager.canLeave).accessibilityIdentifier("race.close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if manager.phase == .finished {
                    Menu {
                        Button("Résultats CSV", systemImage: "tablecells") { export { [try ExportService.csv(manager.race)] } }
                        Button("Rapport PDF", systemImage: "doc.richtext") { export { [try ExportService.pdf(manager.race)] } }
                        if manager.race.capture?.mode == .photo {
                            Button("Photo-finish PNG", systemImage: "photo") { export { [try ExportService.photo(manager.race)] } }
                        }
                        Button("Données et médias originaux", systemImage: "folder") { export { try ExportService.originals(manager.race) } }
                    } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                    .disabled(exporting)
                }
            }
        }
        .overlay { if exporting { ProgressView("Préparation de l’export…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .interactiveDismissDisabled(!manager.canLeave)
        .task { await manager.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { manager.background() }
            if phase == .active { Task { await manager.resume() } }
        }
        .onDisappear { manager.close() }
        .sheet(isPresented: $sharing) { ShareSheet(urls: shareURLs) }
        .sheet(item: $editing) { result in
            ResultEditView(result: result, participant: manager.race.participants.first { $0.id == result.participantID }) { name, bib, lane, time in
                manager.editResult(result.id, name: name, bib: bib, lane: lane, time: time)
            }
        }
    }

    private var clock: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 0.02, paused: manager.phase != .running && manager.phase != .recording)) { _ in
                Text(TimeDisplay.format(manager.elapsed))
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.4).lineLimit(1).accessibilityIdentifier("race.elapsed")
            }
            Text(statusLabel).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(manager.phase == .recording ? .red : .secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 15)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var live: some View {
        @Bindable var model = manager
        return VStack(spacing: 14) {
            if manager.race.mode != .stopwatch {
                if manager.cameraReady {
                    GeometryReader { outer in
                        let aspect: CGFloat = manager.cameraAspect
                        let height: CGFloat = min(380, outer.size.width / aspect)
                        let width: CGFloat = height * aspect
                        CameraPreview(session: manager.camera.session)
                            .frame(width: width, height: height)
                            .overlay {
                                Rectangle().fill(manager.motion > manager.race.settings.motionThreshold ? Color.green.opacity(0.24) : Color.orange.opacity(0.12))
                                    .frame(width: width * CGFloat(manager.race.settings.regionWidth))
                                    .position(x: width * CGFloat(manager.race.settings.linePosition), y: height * CGFloat(0.5))
                                Rectangle().fill(.orange).frame(width: 2)
                                    .position(x: width * CGFloat(manager.race.settings.linePosition), y: height * CGFloat(0.5))
                            }
                            .clipped().position(x: outer.size.width * CGFloat(0.5), y: outer.size.height * CGFloat(0.5))
                    }.frame(height: 380)
                        .background(.black).clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("iPhone en portrait · \(manager.configuredFPS.formatted(.number.precision(.fractionLength(1)))) i/s configurées")
                        .font(.caption).foregroundStyle(.secondary)
                    if manager.phase == .ready {
                        LabeledSlider(title: "Alignement de la ligne", value: $model.race.settings.linePosition, range: 0.05...0.95)
                            .onChange(of: manager.race.settings.linePosition) { _, _ in manager.updateAlignment() }
                        Text("Alignez la ligne orange sur la ligne d’arrivée réelle. Gardez la caméra immobile.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if manager.phase == .preparing { ProgressView("Préparation de la caméra…") }
                else {
                    Button("Réessayer la caméra") { Task { await manager.resume() } }
                    Button("Ouvrir les réglages iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            if manager.phase == .ready {
                action(startLabel, symbol: "play.fill", id: "race.start") { manager.start() }
                    .disabled(manager.race.mode != .stopwatch && !manager.cameraReady)
            }
            if manager.phase == .armed {
                Text("À l’écoute du signal de départ…").font(.headline)
                ProgressView(value: manager.microphoneLevel, total: 1).tint(.orange)
                Text("Niveau : \(manager.microphoneLevel.formatted(.percent.precision(.fractionLength(0)))) · seuil : \(manager.race.settings.microphoneThreshold.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Annuler le départ", role: .cancel) { manager.cancelStart() }.buttonStyle(.bordered)
            }
            if manager.phase == .countdown {
                Text("\(manager.countdown)").font(.system(size: 70, weight: .black, design: .rounded)).foregroundStyle(.orange)
                Button("Annuler le départ", role: .cancel) { manager.cancelStart() }.buttonStyle(.bordered)
            }
            if manager.phase == .running {
                if manager.race.mode == .stopwatch {
                    participantPicker
                    action("Marquer l’arrivée", symbol: "flag.fill", id: "race.mark.manual") { manager.markManual() }
                } else {
                    action("Capturer les arrivées", symbol: "record.circle", id: "race.record") { manager.record() }
                    Text("Le chronomètre tourne. Démarrez la capture à l’approche des concurrents.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Arrêter la course", role: .destructive) { manager.stop() }
                    .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("race.stop")
            }
            if manager.phase == .recording {
                Label("ENREGISTREMENT · \(manager.frames) images", systemImage: "record.circle.fill")
                    .font(.headline).foregroundStyle(.red)
                Text("\(manager.dropped) image(s) perdue(s) signalée(s)").font(.caption).foregroundStyle(.secondary)
                action("Terminer la capture", symbol: "stop.fill", id: "race.stop", tint: .red) { manager.stop() }
            }
            if manager.phase == .processing { ProgressView("Finalisation et sauvegarde…").padding() }
        }
    }

    private var analysis: some View {
        @Bindable var model = manager
        return VStack(alignment: .leading, spacing: 16) {
            if let capture = manager.race.capture, !capture.frames.isEmpty {
                Text("Analyser l’arrivée").font(.title2.bold())
                if capture.mode == .photo {
                    PhotoStripView(race: manager.race, manifest: capture, selectedFrame: $model.selectedFrame, zoom: $model.zoom)
                } else {
                    VideoReviewView(race: manager.race, manifest: capture, selectedFrame: manager.selectedFrame,
                                    frameReady: $model.videoFrameReady)
                }
                HStack {
                    Button { manager.selectedFrame = max(0, manager.selectedFrame - 1) } label: { Image(systemName: "backward.frame.fill").padding(10) }
                        .disabled(manager.selectedFrame <= 0).accessibilityLabel("Image précédente")
                    Spacer()
                    VStack {
                        Text("\(TimeDisplay.format(manager.currentStamp?.elapsedSeconds ?? 0)) s").font(.title2.bold().monospacedDigit())
                        Text("Image \(manager.selectedFrame + 1) / \(capture.frames.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { manager.selectedFrame = min(capture.frames.count - 1, manager.selectedFrame + 1) } label: { Image(systemName: "forward.frame.fill").padding(10) }
                        .disabled(manager.selectedFrame >= capture.frames.count - 1).accessibilityLabel("Image suivante")
                }.buttonStyle(.bordered)
                if capture.frames.count > 1 {
                    Slider(value: Binding(get: { Double(manager.selectedFrame) }, set: { manager.selectedFrame = Int($0.rounded()) }),
                           in: 0...Double(capture.frames.count - 1), step: 1).accessibilityLabel("Parcourir les images")
                }
                if manager.selectedFrame > 0 {
                    let gap = capture.frames[manager.selectedFrame].hostSeconds - capture.frames[manager.selectedFrame - 1].hostSeconds
                    Text("Intervalle avec l’image précédente : \((gap * 1000).formatted(.number.precision(.fractionLength(2)))) ms")
                        .font(.caption).foregroundStyle(.secondary)
                }
                participantPicker
                action("Marquer ce temps", symbol: "flag.fill", id: "race.mark.frame") { manager.markFrame() }
                    .disabled(capture.mode != .photo && !manager.videoFrameReady)
                DisclosureGroup("Qualité de la capture") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(capture.frames.count) images conservées · \(capture.droppedFrames) pertes signalées")
                        Text("Cadence moyenne enregistrée : \(capture.actualFPS.formatted(.number.precision(.fractionLength(1)))) i/s")
                        if let gap = FrameTimeline(frames: capture.frames).maxFrameGap {
                            Text("Plus grand intervalle : \((gap * 1000).formatted(.number.precision(.fractionLength(2)))) ms")
                        }
                        Text("Le curseur sélectionne une image réellement capturée ; aucune précision supplémentaire n’est créée entre deux images.")
                        if capture.interrupted { Text("Capture interrompue : contrôlez les médias avant utilisation.").foregroundStyle(.orange) }
                        ForEach(Array(capture.warnings.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(.orange) }
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            } else if manager.race.mode != .stopwatch {
                ContentUnavailableView("Aucune image enregistrée", systemImage: "video.slash",
                    description: Text("Le départ et la capture sont distincts. Pour la prochaine course, lancez Capturer les arrivées avant les premiers passages."))
            }
            if manager.race.mode == .instant {
                notice("Les arrivées automatiques sont des estimations par mouvement. Contrôlez la vidéo, puis corrigez les marquages si nécessaire.", symbol: "person.crop.rectangle", color: .orange)
            }
            Button("Nouvelle tentative", systemImage: "arrow.counterclockwise") { Task { await manager.reset() } }
                .buttonStyle(.bordered).accessibilityIdentifier("race.reset")
            Text("La course actuelle reste dans l’historique. Une nouvelle tentative crée une course distincte avec les mêmes réglages.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var participantPicker: some View {
        @Bindable var model = manager
        return Picker("Participant", selection: $model.selectedParticipant) {
            Text("Arrivée sans nom").tag(Optional<UUID>.none)
            ForEach(manager.race.participants) { participant in
                Text("\(participant.name)\(participant.lane.isEmpty ? "" : " · couloir \(participant.lane)")").tag(Optional(participant.id))
            }
        }.pickerStyle(.menu)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Résultats · \(manager.race.results.count)").font(.title2.bold())
            if manager.race.results.isEmpty { Text("Marquez une arrivée pour créer le classement.").foregroundStyle(.secondary) }
            ForEach(Array(ResultsManager.ranked(manager.race.results).enumerated()), id: \.element.id) { index, result in
                Button { editing = result } label: {
                    HStack {
                        Text("\(index + 1)").font(.headline).foregroundStyle(.orange).frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(manager.race.participants.first { $0.id == result.participantID }?.name ?? "Arrivée \(index + 1)")
                                .font(.headline).foregroundStyle(.primary)
                            Text(result.source).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(TimeDisplay.format(result.elapsedSeconds)) s").font(.title3.bold().monospacedDigit()).foregroundStyle(.primary)
                        Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                    }.padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).contextMenu {
                    Button("Modifier", systemImage: "pencil") { editing = result }
                    Button("Supprimer l’arrivée", systemImage: "trash", role: .destructive) { manager.removeResult(result.id) }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("race.results")
    }

    private func action(_ text: String, symbol: String, id: String, tint: Color = .orange, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Label(text, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(tint).accessibilityIdentifier(id)
    }
    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(color)
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    private func export(_ operation: @escaping @MainActor () throws -> [URL]) {
        exporting = true
        Task { @MainActor in
            await Task.yield()
            do { shareURLs = try operation(); sharing = true }
            catch { manager.errorMessage = error.localizedDescription }
            exporting = false
        }
    }
    private var startLabel: String {
        switch manager.race.settings.startMode {
        case .manual: "Démarrer"
        case .sound: "Donner le départ sonore"
        case .countdown: "Lancer le compte à rebours"
        case .microphone: "Armer le départ sonore"
        }
    }
    private var statusLabel: String {
        switch manager.phase {
        case .preparing: "PRÉPARATION"
        case .ready: "PRÊT POUR LE DÉPART"
        case .armed: "EN ATTENTE DU SIGNAL"
        case .countdown: "DÉPART DIFFÉRÉ"
        case .running: "COURSE EN COURS"
        case .recording: "CAPTURE DES ARRIVÉES"
        case .processing: "TRAITEMENT"
        case .finished: manager.saveProblem == nil ? "COURSE SAUVEGARDÉE" : "SAUVEGARDE À RÉESSAYER"
        }
    }
}
