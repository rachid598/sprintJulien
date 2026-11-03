@preconcurrency import AVFoundation
import SprintTimerCore

/// All methods except the asynchronous completion run on CameraManager's queue.
final class VideoFinishEngine: @unchecked Sendable {
    private let writer: AVAssetWriter
    private var input: AVAssetWriterInput?
    private var started = false
    private(set) var droppedFrames = 0
    let fileName = "finish.mov"

    init(directory: URL) throws {
        writer = try AVAssetWriter(outputURL: directory.appendingPathComponent(fileName), fileType: .mov)
    }

    func append(_ sample: CMSampleBuffer) throws -> Bool {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return false }
        if input == nil {
            let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: CVPixelBufferGetWidth(buffer), AVVideoHeightKey: CVPixelBufferGetHeight(buffer),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                                                   AVVideoAllowFrameReorderingKey: false]]
            let next = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            next.expectsMediaDataInRealTime = true
            guard writer.canAdd(next) else { throw SprintError.message("Encodeur vidéo non disponible.") }
            writer.add(next)
            input = next
            guard writer.startWriting() else { throw writer.error ?? SprintError.message("Échec de l’enregistrement vidéo.") }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
            started = true
        }
        guard writer.status == .writing, let input else {
            throw writer.error ?? SprintError.message("L’enregistrement vidéo s’est interrompu.")
        }
        guard input.isReadyForMoreMediaData else { droppedFrames += 1; return false }
        guard input.append(sample) else { throw writer.error ?? SprintError.message("Image vidéo refusée.") }
        return true
    }

    func finish(_ completion: @escaping @Sendable (String?) -> Void) {
        guard started else { writer.cancelWriting(); completion("Aucune image vidéo enregistrée."); return }
        input?.markAsFinished()
        writer.finishWriting { [self] in
            completion(writer.status == .completed ? nil : writer.error?.localizedDescription ?? "Vidéo incomplète.")
        }
    }
}
