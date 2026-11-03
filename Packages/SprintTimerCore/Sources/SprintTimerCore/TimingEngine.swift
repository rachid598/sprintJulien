import Foundation

/// Horloge logique indépendante de la date civile. Tous les instants doivent
/// provenir de la même horloge hôte monotone, en secondes.
public struct TimingEngine: Sendable {
    public enum State: String, Sendable { case idle, running, stopped }
    public private(set) var state: State = .idle
    public private(set) var startHostSeconds: Double?
    public private(set) var startEventHostSeconds: Double?
    private var stoppedElapsedSeconds: Double = 0

    public init() {}

    /// Un offset positif ajoute du temps : origine = événement − offset.
    /// Un second départ est ignoré jusqu'à reset(), afin de ne pas déplacer
    /// accidentellement la référence pendant une course.
    public mutating func start(at hostSeconds: Double, offset: Double = 0) {
        guard state == .idle, hostSeconds.isFinite, offset.isFinite else { return }
        let origin = hostSeconds - offset
        guard origin.isFinite else { return }
        startEventHostSeconds = hostSeconds
        startHostSeconds = origin
        stoppedElapsedSeconds = 0
        state = .running
    }

    public mutating func stop(at hostSeconds: Double) {
        guard state == .running, hostSeconds.isFinite,
              let event = startEventHostSeconds, hostSeconds >= event else { return }
        stoppedElapsedSeconds = elapsed(at: hostSeconds)
        state = .stopped
    }

    public mutating func reset() { self = TimingEngine() }

    public func elapsed(at hostSeconds: Double) -> Double {
        if state == .stopped { return stoppedElapsedSeconds }
        guard state == .running, let origin = startHostSeconds, hostSeconds.isFinite else { return 0 }
        return max(0, hostSeconds - origin)
    }
}

public enum TimeDisplay {
    /// Affichage arrondi au centième, sans impliquer la précision du capteur.
    public static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        return String(format: "%.2f", locale: Locale(identifier: "fr_FR"), seconds)
    }
}
