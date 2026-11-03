import Foundation

/// Correspondance bande-image ↔ horodatage réel. Aucun FPS théorique n'est
/// utilisé pour calculer un temps; une trame manquante reste un trou temporel.
public struct FrameTimeline: Sendable {
    public let frames: [FrameStamp]
    public let isValid: Bool

    public init(frames: [FrameStamp]) {
        self.frames = frames
        var valid = true
        var previous: FrameStamp?
        for frame in frames {
            guard frame.presentationSeconds.isFinite, frame.hostSeconds.isFinite,
                  frame.elapsedSeconds.isFinite, frame.elapsedSeconds >= 0, frame.index >= 0 else {
                valid = false; break
            }
            if let previous,
               (frame.index <= previous.index || frame.presentationSeconds <= previous.presentationSeconds
                || frame.hostSeconds <= previous.hostSeconds || frame.elapsedSeconds <= previous.elapsedSeconds) {
                valid = false; break
            }
            previous = frame
        }
        self.isValid = valid
    }

    /// Retourne une position dans `frames`, pas la valeur FrameStamp.index.
    /// En cas d'égalité, conserve la trame précédente.
    public func nearestIndex(elapsedSeconds target: Double) -> Int? {
        guard isValid, !frames.isEmpty, target.isFinite else { return nil }
        var low = 0
        var high = frames.count
        while low < high {
            let middle = low + (high - low) / 2
            if frames[middle].elapsedSeconds < target { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return 0 }
        if low == frames.count { return frames.count - 1 }
        let before = target - frames[low - 1].elapsedSeconds
        let after = frames[low].elapsedSeconds - target
        return before <= after ? low - 1 : low
    }

    public func time(atPixel pixel: Double, stripWidth: Int) -> Double? {
        guard isValid, !frames.isEmpty, stripWidth > 0, pixel.isFinite, pixel >= 0 else { return nil }
        let totalWidth = Double(frames.count) * Double(stripWidth)
        guard pixel <= totalWidth else { return nil }
        let index = min(frames.count - 1, Int(pixel / Double(stripWidth)))
        return frames[index].elapsedSeconds
    }

    public var maxFrameGap: Double? {
        guard isValid, frames.count > 1 else { return nil }
        return zip(frames, frames.dropFirst()).map { $1.hostSeconds - $0.hostSeconds }.max()
    }

    /// Cadence observée sur les horodatages, incluant les trames perdues.
    public var effectiveFPS: Double {
        guard isValid, frames.count > 1, let first = frames.first, let last = frames.last else { return 0 }
        return Double(frames.count - 1) / (last.hostSeconds - first.hostSeconds)
    }
}
