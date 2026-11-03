@preconcurrency import AVFoundation
import Vision
import SprintTimerCore

enum CaptureEvent: Sendable {
    case ready(fps: Double, aspect: Double)
    case progress(frames: Int, dropped: Int, motion: Double)
    case crossing(elapsed: Double, frameIndex: Int?)
    case finished(CaptureManifest)
    case failure(String)
    case interrupted(String)
}

/// AVCaptureSession, detector and engines are confined to ONE serial queue.
/// No pixel buffers are transferred to the main actor or retained in a backlog.
final class CameraManager: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.sprintjulien.capture", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let onEvent: @Sendable (CaptureEvent) -> Void
    private var configured = false
    private var recording = false
    private var settings = RaceSettings()
    private var origin: Double?
    private var photo: PhotoFinishEngine?
    private var video: VideoFinishEngine?
    private var manifest: CaptureManifest?
    private var directory: URL?
    private var detector = MotionDetectionService(threshold: 0.12, cooldown: 1)
    private var fps = 30.0
    private var lastProgress = 0.0
    private var firstRecordingHost = 0.0
    private var lastCheckpoint = 0.0
    private var notifications: [NSObjectProtocol] = []

    init(onEvent: @escaping @Sendable (CaptureEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [self] in
                    let message = "Capture interrompue par iOS. Les images déjà écrites sont conservées."
                    if recording { finishCapture(interrupted: true, warning: message) }
                    onEvent(.interrupted(message))
                }
            })
        }
    }

    deinit { notifications.forEach(NotificationCenter.default.removeObserver) }

    func prepare(settings: RaceSettings, mode: FinishMode) {
        queue.async { [self] in
            do {
                self.settings = settings
                detector = MotionDetectionService(threshold: settings.motionThreshold, cooldown: settings.motionCooldown)
                if !configured { try configureCamera(mode: mode) }
                if !session.isRunning { session.startRunning() }
                let dimensions = output.connection(with: .video)?.isVideoRotationAngleSupported(90) == true
                // The selected format is landscape; data output physically rotates to portrait.
                if let input = session.inputs.first as? AVCaptureDeviceInput {
                    let size = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription)
                    let aspect = dimensions ? Double(size.height) / Double(size.width) : Double(size.width) / Double(size.height)
                    onEvent(.ready(fps: fps, aspect: aspect))
                }
            } catch { onEvent(.failure(error.localizedDescription)) }
        }
    }

    private func configureCamera(mode: FinishMode) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw SprintError.message("Aucune caméra arrière disponible. Le chronomètre manuel reste accessible depuis une nouvelle course.")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw SprintError.message("Impossible de connecter la caméra.") }
        session.addInput(input)
        let requested = Double(mode == .photo ? settings.requestedFPS : min(60, settings.requestedFPS))
        let candidates = device.formats.compactMap { format -> (AVCaptureDevice.Format, Double, Int32)? in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard d.width >= 640, d.width <= 1920, d.height <= 1080,
                  let rate = format.videoSupportedFrameRateRanges.map({ min(requested, $0.maxFrameRate) })
                    .filter({ rate in format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= rate && $0.maxFrameRate >= rate } }).max()
            else { return nil }
            return (format, rate, d.width * d.height)
        }.sorted { $0.1 == $1.1 ? $0.2 > $1.2 : $0.1 > $1.1 }
        guard let chosen = candidates.first else { throw SprintError.message("Aucun format vidéo compatible.") }
        try device.lockForConfiguration()
        device.activeFormat = chosen.0
        fps = chosen.1
        let range = chosen.0.videoSupportedFrameRateRanges.first { $0.minFrameRate <= fps && $0.maxFrameRate >= fps }!
        // Use the device's exact duration at a fractional maximum (e.g. 59.94).
        let duration = abs(fps - range.maxFrameRate) < 0.001 ? range.minFrameDuration
            : CMTime(seconds: 1 / fps, preferredTimescale: 1_000_000_000)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw SprintError.message("La sortie vidéo est indisponible.") }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        }
        configured = true
    }

    func beginTiming(eventHost: Double, offset: Double) {
        queue.async { [self] in origin = eventHost - offset }
    }

    func updateSettings(_ next: RaceSettings) {
        queue.async { [self] in
            guard !recording else { return }
            settings = next
            detector = MotionDetectionService(threshold: next.motionThreshold, cooldown: next.motionCooldown)
        }
    }

    func startRecording(raceID: UUID, mode: FinishMode) {
        queue.async { [self] in
            do {
                guard !recording, let origin, session.isRunning else { throw SprintError.message("La caméra et le départ doivent être prêts.") }
                let folder = try RaceFiles.directory(for: raceID)
                directory = folder
                var next = CaptureManifest(raceID: raceID, mode: mode)
                next.stripWidth = settings.stripWidth
                next.requestedFPS = settings.requestedFPS
                next.startHostSeconds = origin
                next.startOffsetSeconds = settings.startOffsetSeconds
                // A checkpoint remains marked interrupted until finalisation succeeds.
                next.interrupted = true
                manifest = next
                detector = MotionDetectionService(threshold: settings.motionThreshold, cooldown: settings.motionCooldown)
                if mode == .photo {
                    photo = PhotoFinishEngine(directory: folder, stripWidth: settings.stripWidth, linePosition: settings.linePosition)
                } else {
                    video = try VideoFinishEngine(directory: folder)
                    manifest?.videoFile = video?.fileName
                }
                firstRecordingHost = 0
                lastCheckpoint = 0
                recording = true
                try checkpoint(final: false)
            } catch { onEvent(.failure(error.localizedDescription)) }
        }
    }

    func stopRecording() { queue.async { [self] in finishCapture(interrupted: false) } }

    func stopSession() {
        queue.async { [self] in
            if recording { finishCapture(interrupted: true, warning: "La capture a été arrêtée en quittant cet écran.") }
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let clock = session.synchronizationClock else { return }
            let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let hostTime = CMSyncConvertTime(presentation, from: clock, to: CMClockGetHostTimeClock())
            let host = CMTimeGetSeconds(hostTime)
            guard host.isFinite else { return }
            let luminance = sampleLuminance(buffer)
            let detection = detector.process(luminance: luminance, timestamp: host)
            guard recording, let origin, host >= origin else {
                if host - lastProgress >= 0.2 { lastProgress = host; onEvent(.progress(frames: 0, dropped: 0, motion: detection.score)) }
                return
            }
            do {
                if firstRecordingHost == 0 { firstRecordingHost = host }
                if host - firstRecordingHost >= settings.maxRecordingDuration {
                    finishCapture(interrupted: false, warning: "Durée maximale de capture atteinte.")
                    return
                }
                let index = manifest?.frames.count ?? 0
                let elapsed = host - origin
                if let last = manifest?.frames.last, host <= last.hostSeconds {
                    manifest?.droppedFrames += 1
                    return
                }
                let stamp = FrameStamp(index: index, presentationSeconds: CMTimeGetSeconds(presentation),
                                       hostSeconds: host, elapsedSeconds: elapsed, motionScore: detection.score)
                let crossing = detection.triggered && manifest?.mode == .instant && (!settings.humanFilter || containsHuman(buffer))
                if let video, try !video.append(sampleBuffer) {
                    manifest?.droppedFrames += 1
                    if crossing { onEvent(.crossing(elapsed: elapsed, frameIndex: nil)) }
                    return
                }
                // Register the timestamp before a tile flush can throw. The final
                // checkpoint trims metadata to the strips actually made durable.
                manifest?.frames.append(stamp)
                try photo?.append(buffer, frameIndex: index)
                manifest?.imageHeight = CVPixelBufferGetHeight(buffer)
                manifest?.imageWidth = photo == nil ? CVPixelBufferGetWidth(buffer) : (index + 1) * settings.stripWidth
                if crossing {
                    onEvent(.crossing(elapsed: elapsed, frameIndex: index))
                }
                if let photo, photo.tiles.count != manifest?.tiles.count { try checkpoint(final: false) }
                if video != nil, host - lastCheckpoint >= 2 {
                    lastCheckpoint = host
                    try checkpoint(final: false)
                }
                if host - lastProgress >= 0.2 {
                    lastProgress = host
                    onEvent(.progress(frames: index + 1, dropped: manifest?.droppedFrames ?? 0, motion: detection.score))
                }
            } catch { finishCapture(interrupted: true, warning: error.localizedDescription) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if recording { manifest?.droppedFrames += 1 }
    }

    private func finishCapture(interrupted: Bool, warning: String? = nil) {
        guard recording else { return }
        recording = false
        manifest?.interrupted = interrupted
        if let warning { manifest?.warnings.append(warning) }
        do { try photo?.flush() } catch { manifest?.interrupted = true; manifest?.warnings.append(error.localizedDescription) }
        if let video {
            video.finish { [weak self] error in
                guard let self else { return }
                self.queue.async { [self] in
                    if let error { manifest?.interrupted = true; manifest?.warnings.append(error) }
                    completeCapture()
                }
            }
        } else { completeCapture() }
    }

    private func completeCapture() {
        do {
            try checkpoint(final: true)
            if let manifest { onEvent(.finished(manifest)) }
        } catch { onEvent(.failure("Sauvegarde incomplète : \(error.localizedDescription)")) }
        photo = nil
        video = nil
    }

    private func checkpoint(final: Bool) throws {
        guard var snapshot = manifest, let directory else { return }
        if let photo {
            snapshot.tiles = photo.tiles
            // Pending strips are not claimed as durable in a crash checkpoint.
            let durable = photo.tiles.reduce(0) { $0 + $1.frameCount }
            snapshot.frames = Array(snapshot.frames.prefix(durable))
            snapshot.imageWidth = durable * snapshot.stripWidth
            manifest?.tiles = photo.tiles
        }
        if !final { snapshot.interrupted = true }
        snapshot.actualFPS = FrameTimeline(frames: snapshot.frames).effectiveFPS
        if final { manifest = snapshot }
        try RaceFiles.write(snapshot, to: directory.appendingPathComponent("capture.json"))
    }

    private func sampleLuminance(_ buffer: CVPixelBuffer) -> [UInt8] {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let raw = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let base = raw.assumingMemoryBound(to: UInt8.self)
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        let region = max(0.02, min(0.5, settings.regionWidth))
        let center = settings.linePosition
        var result = [UInt8]()
        result.reserveCapacity(24 * 48)
        for row in 0..<48 {
            let y = min(h - 1, Int(Double(row) / 48 * Double(h)))
            for column in 0..<24 {
                let point = max(0, min(1, center - region / 2 + Double(column) / 24 * region))
                let x = min(w - 1, Int(point * Double(w)))
                let offset = y * stride + x * 4
                result.append(UInt8((Int(base[offset]) * 29 + Int(base[offset + 1]) * 150 + Int(base[offset + 2]) * 77) >> 8))
            }
        }
        return result
    }

    private func containsHuman(_ buffer: CVPixelBuffer) -> Bool {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let region = CGRect(x: max(0, settings.linePosition - settings.regionWidth / 2), y: 0,
                                width: settings.regionWidth, height: 1)
            return request.results?.contains { $0.confidence >= 0.4 && $0.boundingBox.intersects(region) } == true
        } catch { return false }
    }
}
