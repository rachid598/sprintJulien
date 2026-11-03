import Foundation
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import SprintTimerCore

/// Queue-confined, view-independent engine. At most 256 strips are resident.
/// Every PNG tile is lossless; capture.json retains the timestamp of EACH strip.
final class PhotoFinishEngine {
    let directory: URL
    let stripWidth: Int
    let linePosition: Double
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let tileCapacity = 256
    private var bytes: [UInt8] = []
    private var height = 0
    private var columns = 0
    private var tileStart = 0
    private(set) var tiles: [PhotoTile] = []

    init(directory: URL, stripWidth: Int, linePosition: Double) {
        self.directory = directory
        self.stripWidth = max(1, min(16, stripWidth))
        self.linePosition = max(0, min(1, linePosition))
    }

    func append(_ buffer: CVPixelBuffer, frameIndex: Int) throws {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
            throw SprintError.message("Format caméra non compatible : BGRA requis.")
        }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w >= stripWidth, h > 0 else { throw SprintError.message("Image caméra vide.") }
        if height == 0 {
            height = h
            bytes = [UInt8](repeating: 0, count: tileCapacity * stripWidth * h * 4)
            tileStart = frameIndex
        }
        guard h == height else { throw SprintError.message("Le format caméra a changé pendant la capture.") }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            throw SprintError.message("Impossible de lire l’image caméra.")
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw SprintError.message("Image caméra inaccessible.") }
        let sourceStride = CVPixelBufferGetBytesPerRow(buffer)
        let x = max(0, min(w - stripWidth, Int((Double(w - 1) * linePosition).rounded()) - stripWidth / 2))
        let destinationStride = tileCapacity * stripWidth * 4
        bytes.withUnsafeMutableBytes { destination in
            guard let out = destination.baseAddress else { return }
            for y in 0..<h {
                out.advanced(by: y * destinationStride + columns * stripWidth * 4)
                    .copyMemory(from: base.advanced(by: y * sourceStride + x * 4), byteCount: stripWidth * 4)
            }
        }
        columns += 1
        if columns == tileCapacity { try flush() }
    }

    func flush() throws {
        guard columns > 0 else { return }
        let width = columns * stripWidth
        let data = Data(bytes)
        let image = CIImage(bitmapData: data, bytesPerRow: tileCapacity * stripWidth * 4,
                            size: CGSize(width: tileCapacity * stripWidth, height: height),
                            format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard let cg = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            throw SprintError.message("Échec du rendu photo-finish.")
        }
        let name = String(format: "photo-%05d.png", tiles.count)
        let url = directory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SprintError.message("Impossible d’écrire la photo-finish.")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { throw SprintError.message("Sauvegarde de l’image incomplète.") }
        tiles.append(PhotoTile(relativePath: name, startFrame: tileStart, frameCount: columns,
                               pixelWidth: width, pixelHeight: height))
        tileStart += columns
        columns = 0
    }
}
