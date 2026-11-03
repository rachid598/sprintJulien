import Foundation

public enum FinishMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo, video, instant, stopwatch
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .photo: "Photo-finish"
        case .video: "Vidéo-finish"
        case .instant: "Arrivée instantanée"
        case .stopwatch: "Chronomètre"
        }
    }
}

public enum StartMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, sound, countdown, microphone
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .manual: "Manuel"
        case .sound: "Signal sonore"
        case .countdown: "Compte à rebours"
        case .microphone: "Détection du son"
        }
    }
}

public struct RaceSettings: Codable, Equatable, Sendable {
    public var linePosition: Double = 0.5
    public var stripWidth: Int = 2
    public var requestedFPS: Int = 120
    public var maxRecordingDuration: Double = 60
    public var startMode: StartMode = .manual
    public var countdownSeconds: Double = 3
    /// Positif : l'origine est reculée, le temps mesuré augmente.
    public var startOffsetSeconds: Double = 0
    public var microphoneThreshold: Double = 0.35
    public var motionThreshold: Double = 0.12
    public var motionCooldown: Double = 1
    public var regionWidth: Double = 0.12
    public var humanFilter: Bool = false

    public init(
        linePosition: Double = 0.5, stripWidth: Int = 2, requestedFPS: Int = 120,
        maxRecordingDuration: Double = 60, startMode: StartMode = .manual,
        countdownSeconds: Double = 3, startOffsetSeconds: Double = 0,
        microphoneThreshold: Double = 0.35, motionThreshold: Double = 0.12,
        motionCooldown: Double = 1, regionWidth: Double = 0.12, humanFilter: Bool = false
    ) {
        self.linePosition = linePosition
        self.stripWidth = stripWidth
        self.requestedFPS = requestedFPS
        self.maxRecordingDuration = maxRecordingDuration
        self.startMode = startMode
        self.countdownSeconds = countdownSeconds
        self.startOffsetSeconds = startOffsetSeconds
        self.microphoneThreshold = microphoneThreshold
        self.motionThreshold = motionThreshold
        self.motionCooldown = motionCooldown
        self.regionWidth = regionWidth
        self.humanFilter = humanFilter
    }
}

public struct Participant: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bib: String
    public var lane: String
    public init(id: UUID = UUID(), name: String = "", bib: String = "", lane: String = "") {
        self.id = id; self.name = name; self.bib = bib; self.lane = lane
    }
}

public struct RaceResult: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var participantID: UUID?
    public var elapsedSeconds: Double
    public var source: String
    public var frameIndex: Int?
    public var createdAt: Date
    public init(
        id: UUID = UUID(), participantID: UUID? = nil, elapsedSeconds: Double,
        source: String = "manuel", frameIndex: Int? = nil, createdAt: Date = Date()
    ) {
        self.id = id; self.participantID = participantID; self.elapsedSeconds = elapsedSeconds
        self.source = source; self.frameIndex = frameIndex; self.createdAt = createdAt
    }
}

public struct FrameStamp: Codable, Equatable, Sendable {
    public var index: Int
    public var presentationSeconds: Double
    public var hostSeconds: Double
    public var elapsedSeconds: Double
    public var motionScore: Double
    public init(
        index: Int, presentationSeconds: Double, hostSeconds: Double,
        elapsedSeconds: Double, motionScore: Double = 0
    ) {
        self.index = index; self.presentationSeconds = presentationSeconds
        self.hostSeconds = hostSeconds; self.elapsedSeconds = elapsedSeconds; self.motionScore = motionScore
    }
}

public struct PhotoTile: Codable, Equatable, Identifiable, Sendable {
    public var relativePath: String
    public var startFrame: Int
    public var frameCount: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var id: String { relativePath }
    public init(relativePath: String, startFrame: Int, frameCount: Int, pixelWidth: Int, pixelHeight: Int) {
        self.relativePath = relativePath; self.startFrame = startFrame; self.frameCount = frameCount
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
}

public struct CaptureManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var raceID: UUID
    public var mode: FinishMode
    public var imageWidth: Int
    public var imageHeight: Int
    public var stripWidth: Int
    public var frames: [FrameStamp]
    public var tiles: [PhotoTile]
    public var videoFile: String?
    public var droppedFrames: Int
    public var requestedFPS: Int
    public var actualFPS: Double
    public var startHostSeconds: Double
    public var startOffsetSeconds: Double
    public var interrupted: Bool
    public var warnings: [String]

    public init(
        version: Int = 1, raceID: UUID, mode: FinishMode, imageWidth: Int = 0,
        imageHeight: Int = 0, stripWidth: Int = 2, frames: [FrameStamp] = [],
        tiles: [PhotoTile] = [], videoFile: String? = nil, droppedFrames: Int = 0,
        requestedFPS: Int = 120, actualFPS: Double = 0, startHostSeconds: Double = 0,
        startOffsetSeconds: Double = 0, interrupted: Bool = false, warnings: [String] = []
    ) {
        self.version = version; self.raceID = raceID; self.mode = mode
        self.imageWidth = imageWidth; self.imageHeight = imageHeight; self.stripWidth = stripWidth
        self.frames = frames; self.tiles = tiles; self.videoFile = videoFile
        self.droppedFrames = droppedFrames; self.requestedFPS = requestedFPS; self.actualFPS = actualFPS
        self.startHostSeconds = startHostSeconds; self.startOffsetSeconds = startOffsetSeconds
        self.interrupted = interrupted; self.warnings = warnings
    }
}

public struct RaceDocument: Codable, Equatable, Identifiable, Sendable {
    public var version: Int
    public var id: UUID
    public var name: String
    public var date: Date
    public var distance: Double
    public var mode: FinishMode
    public var settings: RaceSettings
    public var participants: [Participant]
    public var results: [RaceResult]
    public var capture: CaptureManifest?
    public var elapsedSeconds: Double

    public init(
        version: Int = 1, id: UUID = UUID(), name: String = "Nouvelle course", date: Date = Date(),
        distance: Double = 100, mode: FinishMode = .photo, settings: RaceSettings = RaceSettings(),
        participants: [Participant] = [], results: [RaceResult] = [], capture: CaptureManifest? = nil,
        elapsedSeconds: Double = 0
    ) {
        self.version = version; self.id = id; self.name = name; self.date = date
        self.distance = distance; self.mode = mode; self.settings = settings
        self.participants = participants; self.results = results; self.capture = capture
        self.elapsedSeconds = elapsedSeconds
    }
}
