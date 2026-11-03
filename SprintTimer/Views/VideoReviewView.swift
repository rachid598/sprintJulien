import SwiftUI
@preconcurrency import AVFoundation
import SprintTimerCore

struct VideoReviewView: View {
    let race: RaceDocument
    let manifest: CaptureManifest
    let selectedFrame: Int
    @State private var image: UIImage?
    @State private var problem: String?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                GeometryReader { geometry in
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    // Fit the overlay to the same letterboxed image rectangle.
                    let aspect: CGFloat = image.size.width / image.size.height
                    let width: CGFloat = min(geometry.size.width, geometry.size.height * aspect)
                    let height: CGFloat = width / aspect
                    let lineX: CGFloat = (geometry.size.width - width) * CGFloat(0.5) + width * CGFloat(race.settings.linePosition)
                    let lineY: CGFloat = geometry.size.height * CGFloat(0.5)
                    Rectangle().fill(.orange).frame(width: 2, height: height)
                        .position(x: lineX, y: lineY)
                }
            } else { ProgressView().tint(.white) }
            if let problem { Text(problem).font(.caption).foregroundStyle(.white).padding().background(.black.opacity(0.8)) }
        }
        .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: selectedFrame) { await loadFrame() }
    }

    @MainActor
    private func loadFrame() async {
        guard manifest.frames.indices.contains(selectedFrame), let file = manifest.videoFile else { return }
        let index = selectedFrame
        do {
            let url = try RaceFiles.directory(for: race.id).appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { throw SprintError.message("La vidéo est introuvable.") }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            let seconds = manifest.frames[index].presentationSeconds - manifest.frames[0].presentationSeconds
            let result = try await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 1_000_000_000))
            try Task.checkCancellation()
            guard index == selectedFrame else { return }
            image = UIImage(cgImage: result.image)
            problem = abs(CMTimeGetSeconds(result.actualTime) - seconds) > 0.003
                ? "L’image décodée diffère de l’horodatage demandé. Vérifiez les images voisines avant de marquer." : nil
        } catch is CancellationError { }
        catch { guard !Task.isCancelled else { return }; problem = error.localizedDescription }
    }
}
