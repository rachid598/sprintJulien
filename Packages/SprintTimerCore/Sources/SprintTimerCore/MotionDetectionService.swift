import Foundation

public struct MotionDetection: Equatable, Sendable {
    public let score: Double
    public let triggered: Bool
    public init(score: Double, triggered: Bool) { self.score = score; self.triggered = triggered }
}

/// Différence moyenne normalisée entre deux échantillonnages d'une même zone.
/// Le premier échantillon établit le fond. Deux trames calmes sont nécessaires
/// pour réarmer le détecteur. Cela ne distingue pas une personne d'une ombre.
public struct MotionDetectionService: Sendable {
    public var threshold: Double
    public var cooldown: Double
    public private(set) var isArmed = true
    private var previous: [UInt8]?
    private var previousTimestamp: Double?
    private var lastTriggerTimestamp: Double?
    private var calmFrames = 0

    public init(threshold: Double = 0.12, cooldown: Double = 1) {
        self.threshold = threshold
        self.cooldown = cooldown
    }

    public mutating func reset() {
        previous = nil; previousTimestamp = nil; lastTriggerTimestamp = nil
        isArmed = true; calmFrames = 0
    }

    public mutating func process(luminance: [UInt8], timestamp: Double) -> MotionDetection {
        guard timestamp.isFinite, !luminance.isEmpty else { return MotionDetection(score: 0, triggered: false) }
        defer { previous = luminance; previousTimestamp = timestamp }
        guard let previous, previous.count == luminance.count,
              let previousTimestamp, timestamp > previousTimestamp else {
            isArmed = true; calmFrames = 0
            // A reset/backward clock cannot carry an old cooldown reference.
            if let old = self.previousTimestamp, timestamp <= old { lastTriggerTimestamp = nil }
            return MotionDetection(score: 0, triggered: false)
        }
        var sum: Double = 0
        for (left, right) in zip(previous, luminance) { sum += Double(abs(Int(left) - Int(right))) }
        let score = sum / (255 * Double(luminance.count))
        let level = threshold.isFinite ? min(1, max(0.001, threshold)) : 0.12
        let delay = cooldown.isFinite ? max(0, cooldown) : 1
        if score < level * 0.5 {
            calmFrames += 1
            if calmFrames >= 2 { isArmed = true }
            return MotionDetection(score: score, triggered: false)
        }
        calmFrames = 0
        guard score >= level, isArmed else { return MotionDetection(score: score, triggered: false) }
        // Consume the rising edge even during the cooldown; sustained motion
        // must not become a delayed second arrival once the delay expires.
        isArmed = false
        guard lastTriggerTimestamp.map({ timestamp - $0 >= delay }) ?? true else {
            return MotionDetection(score: score, triggered: false)
        }
        lastTriggerTimestamp = timestamp
        return MotionDetection(score: score, triggered: true)
    }
}
