import SwiftUI
import SwiftData
@preconcurrency import AVFoundation
import SprintTimerCore

enum RacePhase: Equatable {
    case preparing, ready, armed, countdown, running, recording, processing, finished
}

@MainActor
@Observable
final class RaceManager {
    var race: RaceDocument
    var phase = RacePhase.preparing
    var errorMessage: String?
    var cameraReady = false
    var cameraAspect = 9.0 / 16.0
    var configuredFPS = 0.0
    var frames = 0
    var dropped = 0
    var motion = 0.0
    var microphoneLevel = 0.0
    var countdown = 0
    var selectedFrame = 0
    var selectedParticipant: UUID?
    var zoom = 1.0
    var saveProblem: String?
    private var timer = TimingEngine()
    private let signals = StartSignalService()
    private var countdownTask: Task<Void, Never>?
    private let persistence: PersistenceService
    private var closed = false
    private var foreground = true
    @ObservationIgnored private var cameraStorage: CameraManager?

    var camera: CameraManager {
        if let cameraStorage { return cameraStorage }
        let next = CameraManager { [weak self] event in
            // FIFO delivery preserves the final crossing before .finished.
            DispatchQueue.main.async { [weak self] in self?.handle(event) }
        }
        cameraStorage = next
        return next
    }

    init(race: RaceDocument, context: ModelContext, reopening: Bool = false) {
        self.race = race
        persistence = PersistenceService(context: context)
        selectedParticipant = race.participants.first?.id
        if reopening { phase = .finished }
    }

    var elapsed: Double { phase == .finished ? race.elapsedSeconds : timer.elapsed(at: HostClock.now) }
    var currentStamp: FrameStamp? {
        guard let frames = race.capture?.frames, frames.indices.contains(selectedFrame) else { return nil }
        return frames[selectedFrame]
    }
    var canLeave: Bool { [.ready, .finished, .preparing].contains(phase) }

    func prepare() async {
        guard !closed, foreground, phase == .preparing || (phase == .ready && !cameraReady) else { return }
        persist()
        guard race.mode != .stopwatch else { phase = .ready; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        guard !closed, foreground else { return }
        guard allowed else {
            errorMessage = "Autorisez la caméra dans Réglages > SprintTimer. Vous pouvez aussi créer une course en mode chronomètre."
            phase = .ready
            return
        }
        camera.prepare(settings: race.settings, mode: race.mode)
    }

    func start() {
        guard phase == .ready, race.mode == .stopwatch || cameraReady else { return }
        errorMessage = nil
        switch race.settings.startMode {
        case .manual: begin(at: HostClock.now)
        case .sound:
            do { begin(at: try signals.playStart()) } catch { errorMessage = error.localizedDescription }
        case .countdown:
            phase = .countdown
            let duration = max(1, min(60, race.settings.countdownSeconds))
            let deadline = HostClock.now + duration
            countdownTask = Task { [weak self] in
                guard let self else { return }
                while HostClock.now < deadline {
                    countdown = Int(ceil(deadline - HostClock.now))
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                do { begin(at: try signals.playStart()) } catch { errorMessage = error.localizedDescription; phase = .ready }
            }
        case .microphone:
            phase = .armed
            Task { [weak self] in
                guard let self else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                var allowed = status == .authorized
                if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
                guard !closed, foreground, phase == .armed else { return }
                guard allowed else { errorMessage = "Autorisez le microphone dans Réglages > SprintTimer."; phase = .ready; return }
                do {
                    try signals.armMicrophone(threshold: race.settings.microphoneThreshold,
                        level: { [weak self] in self?.microphoneLevel = $0 },
                        trigger: { [weak self] host in
                            guard let self, phase == .armed else { return }
                            signals.stop()
                            begin(at: host)
                        })
                } catch { errorMessage = error.localizedDescription; phase = .ready }
            }
        }
    }

    private func begin(at host: Double) {
        timer.start(at: host, offset: race.settings.startOffsetSeconds)
        cameraStorage?.beginTiming(eventHost: host, offset: race.settings.startOffsetSeconds)
        phase = .running
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func cancelStart() {
        countdownTask?.cancel()
        signals.stop()
        timer.reset()
        phase = .ready
    }

    func record() {
        guard phase == .running, race.mode != .stopwatch else { return }
        camera.startRecording(raceID: race.id, mode: race.mode)
        phase = .recording
    }

    func stop() {
        if phase == .armed || phase == .countdown { cancelStart(); return }
        guard phase == .running || phase == .recording else { return }
        timer.stop(at: HostClock.now)
        race.elapsedSeconds = timer.elapsed(at: HostClock.now)
        if phase == .recording { phase = .processing; camera.stopRecording() }
        else { phase = .finished; cameraStorage?.stopSession(); persist() }
        signals.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func background() {
        foreground = false
        if phase == .armed || phase == .countdown { cancelStart() }
        if phase == .running || phase == .recording {
            errorMessage = "Course arrêtée : l’application est passée en arrière-plan. La capture ne continue pas écran verrouillé."
            stop()
        }
        cameraStorage?.stopSession()
        cameraReady = false
    }

    func resume() async {
        foreground = true
        guard !closed else { return }
        await prepare()
    }

    func updateAlignment() {
        guard phase == .ready else { return }
        cameraStorage?.updateSettings(race.settings)
    }

    func reset() async {
        guard phase == .finished else { return }
        persist()
        let previous = race
        race = RaceDocument(name: previous.name, distance: previous.distance, mode: previous.mode,
                            settings: previous.settings, participants: previous.participants)
        timer.reset()
        selectedFrame = 0; frames = 0; dropped = 0; motion = 0
        errorMessage = nil
        selectedParticipant = race.participants.first?.id
        cameraReady = false
        phase = .preparing
        await prepare()
    }

    func close() {
        closed = true
        if phase == .armed || phase == .countdown { cancelStart() }
        countdownTask?.cancel()
        signals.stop()
        cameraStorage?.stopSession()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func markManual() {
        guard phase == .running, race.mode == .stopwatch else { return }
        addResult(time: timer.elapsed(at: HostClock.now), source: "Manuel", frame: nil)
    }

    func markFrame() {
        guard let stamp = currentStamp else { return }
        addResult(time: stamp.elapsedSeconds, source: race.mode == .photo ? "Photo-finish" : "Vidéo", frame: selectedFrame)
    }

    func addResult(time: Double, source: String, frame: Int?) {
        guard time.isFinite, time >= 0 else { return }
        if let id = selectedParticipant, let index = race.results.firstIndex(where: { $0.participantID == id }) {
            race.results[index].elapsedSeconds = time
            race.results[index].source = source
            race.results[index].frameIndex = frame
        } else {
            race.results.append(RaceResult(participantID: selectedParticipant, elapsedSeconds: time, source: source, frameIndex: frame))
        }
        selectedParticipant = race.participants.first { p in !race.results.contains { $0.participantID == p.id } }?.id
        persist()
    }

    func removeResult(_ id: UUID) { race.results.removeAll { $0.id == id }; persist() }
    func editResult(_ id: UUID, name: String, bib: String, lane: String, time: Double) {
        guard let index = race.results.firstIndex(where: { $0.id == id }), time.isFinite, time >= 0 else { return }
        if let participantID = race.results[index].participantID,
           let p = race.participants.firstIndex(where: { $0.id == participantID }) {
            race.participants[p].name = name
            race.participants[p].bib = bib
            race.participants[p].lane = lane
        } else if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let participant = Participant(name: name, bib: bib, lane: lane)
            race.participants.append(participant)
            race.results[index].participantID = participant.id
        }
        if abs(race.results[index].elapsedSeconds - time) > 0.000001 {
            race.results[index].elapsedSeconds = time
            race.results[index].source = "Corrigé manuellement"
        }
        persist()
    }
    func renameParticipant(_ id: UUID, name: String) {
        if let i = race.participants.firstIndex(where: { $0.id == id }) { race.participants[i].name = name; persist() }
    }
    func persist() {
        do { try persistence.save(race); saveProblem = nil }
        catch { saveProblem = "Sauvegarde impossible : \(error.localizedDescription)" }
    }

    private func handle(_ event: CaptureEvent) {
        switch event {
        case .ready(let fps, let aspect):
            guard !closed, foreground, phase == .preparing || phase == .ready else { return }
            configuredFPS = fps; cameraAspect = aspect; cameraReady = true
            if phase == .preparing { phase = .ready }
        case .progress(let frames, let dropped, let motion):
            self.motion = motion
            if phase == .recording { self.frames = frames; self.dropped = dropped }
        case .crossing(let elapsed, let frame):
            guard phase == .recording || phase == .processing else { return }
            addResult(time: elapsed, source: "Mouvement (estimation)", frame: frame)
        case .finished(let manifest):
            if phase == .recording {
                timer.stop(at: HostClock.now)
                race.elapsedSeconds = timer.elapsed(at: HostClock.now)
            }
            race.capture = manifest
            phase = .finished
            selectedFrame = 0
            cameraStorage?.stopSession()
            UIApplication.shared.isIdleTimerDisabled = false
            persist()
        case .failure(let message):
            errorMessage = message
            if phase == .preparing { phase = .ready }
            else if phase == .recording || phase == .processing { stopAfterFailure() }
        case .interrupted(let message):
            errorMessage = message
            cameraReady = false
            if phase == .armed || phase == .countdown { cancelStart() }
            if phase == .running { stop() }
        }
    }

    private func stopAfterFailure() {
        timer.stop(at: HostClock.now)
        race.elapsedSeconds = timer.elapsed(at: HostClock.now)
        phase = .finished
        cameraStorage?.stopSession()
        UIApplication.shared.isIdleTimerDisabled = false
        persist()
    }
}
