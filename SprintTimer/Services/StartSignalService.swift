@preconcurrency import AVFoundation
import Foundation

/// One-shot gate shared with the real-time audio callback. No UI work in the tap.
private final class AudioGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var lastMeter = 0.0
    func update(host: Double, peak: Double, threshold: Double) -> (trigger: Bool, meter: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let trigger = peak >= threshold && !fired
        if trigger { fired = true }
        let meter = host - lastMeter > 0.1
        if meter { lastMeter = host }
        return (trigger, meter)
    }
}

@MainActor
final class StartSignalService {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayer?

    func armMicrophone(threshold: Double,
                       level: @escaping @MainActor @Sendable (Double) -> Void,
                       trigger: @escaping @MainActor @Sendable (Double) -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
        let next = AVAudioEngine()
        let input = next.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SprintError.message("Microphone indisponible.") }
        let gate = AudioGate()
        input.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, when in
            guard when.isHostTimeValid, let samples = buffer.floatChannelData?[0] else { return }
            var peak: Float = 0
            var firstCrossing: Int?
            for i in 0..<Int(buffer.frameLength) {
                let amplitude = abs(samples[i])
                peak = max(peak, amplitude)
                if firstCrossing == nil, Double(amplitude) >= threshold { firstCrossing = i }
            }
            let host = AVAudioTime.seconds(forHostTime: when.hostTime)
            let update = gate.update(host: host, peak: Double(peak), threshold: threshold)
            if update.meter { Task { @MainActor in level(Double(peak)) } }
            if update.trigger, let firstCrossing {
                let eventTime = host + Double(firstCrossing) / format.sampleRate
                Task { @MainActor in trigger(eventTime) }
            }
        }
        next.prepare()
        try next.start()
        engine = next
    }

    /// Returns the scheduled host time, not a claim about acoustic output latency.
    func playStart() throws -> Double {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        let sound = try AVAudioPlayer(data: Self.beepWAV())
        sound.prepareToPlay()
        let delay = 0.08
        let host = HostClock.now + delay
        guard sound.play(atTime: sound.deviceCurrentTime + delay) else { throw SprintError.message("Le signal sonore n’a pas pu démarrer.") }
        player = sound
        return host
    }

    func stop() {
        if let engine { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        engine = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func beepWAV() -> Data {
        let rate = 44_100
        let count = Int(Double(rate) * 0.16)
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(Data("RIFF".utf8)); word(UInt32(36 + count * 2)); data.append(Data("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(rate)); word(UInt32(rate * 2))
        word(UInt16(2)); word(UInt16(16)); data.append(Data("data".utf8)); word(UInt32(count * 2))
        for i in 0..<count {
            let envelope = min(1, Double(i) / 150) * min(1, Double(count - i) / 300)
            word(Int16(sin(Double(i) * 2 * .pi * 1000 / Double(rate)) * envelope * 26_000))
        }
        return data
    }
}
