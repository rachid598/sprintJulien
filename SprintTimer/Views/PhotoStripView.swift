import SwiftUI
import SprintTimerCore

struct PhotoStripView: View {
    let race: RaceDocument
    let manifest: CaptureManifest
    @Binding var selectedFrame: Int
    @Binding var zoom: Double
    @GestureState private var magnification = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(manifest.tiles) { tile in
                            tileView(tile)
                                .id(tile.id)
                        }
                    }
                }
                .frame(height: 340)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in
                    state = value.magnification
                }.onEnded { value in zoom = max(1, min(12, zoom * value.magnification)) })
                .onChange(of: selectedFrame) { _, frame in
                    guard let tile = manifest.tiles.first(where: { frame >= $0.startFrame && frame < $0.startFrame + $0.frameCount }) else { return }
                    let fraction = Double(frame - tile.startFrame) / Double(max(1, tile.frameCount - 1))
                    proxy.scrollTo(tile.id, anchor: UnitPoint(x: fraction, y: 0.5))
                }
            }
            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $zoom, in: 1...12).accessibilityLabel("Zoom photo-finish")
                Image(systemName: "plus.magnifyingglass")
            }
            Text("Balayez pour parcourir le temps. Touchez une bande pour placer le curseur. Pincez pour zoomer.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tileView(_ tile: PhotoTile) -> some View {
        let scale = 340 / Double(max(1, manifest.imageHeight)) * max(1, min(12, zoom * magnification))
        let width = Double(tile.pixelWidth) * scale
        return ZStack(alignment: .topLeading) {
            if let folder = try? RaceFiles.directory(for: race.id),
               let image = UIImage(contentsOfFile: folder.appendingPathComponent(tile.relativePath).path) {
                Image(uiImage: image).resizable().interpolation(.none)
                    .frame(width: width, height: 340)
            } else {
                Color.gray.overlay { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.white) }
            }
            ForEach(race.results.filter { result in
                guard let frame = result.frameIndex else { return false }
                return frame >= tile.startFrame && frame < tile.startFrame + tile.frameCount
            }) { result in
                Rectangle().fill(.orange).frame(width: 1, height: 340)
                    .offset(x: Double((result.frameIndex ?? 0) - tile.startFrame) * Double(manifest.stripWidth) * scale)
            }
            if selectedFrame >= tile.startFrame && selectedFrame < tile.startFrame + tile.frameCount {
                Rectangle().fill(.red).frame(width: 2, height: 340)
                    .offset(x: Double(selectedFrame - tile.startFrame) * Double(manifest.stripWidth) * scale)
            }
        }
        .frame(width: width, height: 340)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { location in
            let local = Int(location.x / max(0.001, Double(manifest.stripWidth) * scale))
            selectedFrame = tile.startFrame + max(0, min(tile.frameCount - 1, local))
        }
        .accessibilityLabel("Photo-finish, bandes \(tile.startFrame + 1) à \(tile.startFrame + tile.frameCount)")
    }
}
