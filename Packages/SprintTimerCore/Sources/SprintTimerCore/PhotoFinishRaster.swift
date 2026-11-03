import Foundation

public enum RasterError: Error, Equatable, Sendable {
    case invalidDimensions
    case invalidPixelCount
    case invalidPosition
    case incompatibleStrip
    case memoryLimit
    case noFrames
}

/// Image RGBA8, lignes de haut en bas, pixels de gauche à droite.
/// Aucune rotation implicite : l'adaptateur caméra fournit l'orientation.
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        let count = try Self.byteCount(width: width, height: height)
        guard pixels.count == count else { throw RasterError.invalidPixelCount }
        self.width = width; self.height = height; self.pixels = pixels
    }

    static func byteCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else { throw RasterError.invalidDimensions }
        let (pixels, overflow1) = width.multipliedReportingOverflow(by: height)
        let (bytes, overflow2) = pixels.multipliedReportingOverflow(by: 4)
        guard !overflow1, !overflow2 else { throw RasterError.invalidDimensions }
        return bytes
    }
}

/// Assembleur indépendant de SwiftUI/CoreImage. Pour une longue capture,
/// l'appelant utilise des tuiles et écrit chaque tuile sur disque.
public struct PhotoFinishRaster: Sendable {
    public let height: Int
    public let stripWidth: Int
    public let maximumBytes: Int
    public private(set) var frameCount: Int = 0
    private var strips: [[UInt8]] = []
    public var width: Int { frameCount * stripWidth }

    public init(height: Int, stripWidth: Int, maximumBytes: Int = 32 * 1024 * 1024) throws {
        let bytes = try RGBAImage.byteCount(width: stripWidth, height: height)
        guard maximumBytes > 0, bytes <= maximumBytes else { throw RasterError.memoryLimit }
        self.height = height; self.stripWidth = stripWidth; self.maximumBytes = maximumBytes
    }

    public mutating func append(frame: RGBAImage, linePosition: Double) throws {
        try append(strip: Self.extractStrip(from: frame, linePosition: linePosition, stripWidth: stripWidth))
    }

    public mutating func append(strip: RGBAImage) throws {
        guard strip.height == height, strip.width == stripWidth else { throw RasterError.incompatibleStrip }
        let (nextCount, overflow) = (frameCount + 1).multipliedReportingOverflow(by: strip.pixels.count)
        guard !overflow, nextCount <= maximumBytes else { throw RasterError.memoryLimit }
        strips.append(strip.pixels)
        frameCount += 1
    }

    public func image() throws -> RGBAImage {
        guard frameCount > 0 else { throw RasterError.noFrames }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let stripRowBytes = stripWidth * 4
        for row in 0..<height {
            for (index, strip) in strips.enumerated() {
                let source = row * stripRowBytes
                let destination = (row * width + index * stripWidth) * 4
                pixels.replaceSubrange(destination..<(destination + stripRowBytes), with: strip[source..<(source + stripRowBytes)])
            }
        }
        return try RGBAImage(width: width, height: height, pixels: pixels)
    }

    public static func extractStrip(from frame: RGBAImage, linePosition: Double, stripWidth: Int) throws -> RGBAImage {
        guard linePosition.isFinite, (0...1).contains(linePosition) else { throw RasterError.invalidPosition }
        guard stripWidth > 0, stripWidth <= frame.width else { throw RasterError.invalidDimensions }
        let center = Int((linePosition * Double(frame.width - 1)).rounded())
        let left = min(frame.width - stripWidth, max(0, center - stripWidth / 2))
        let rowBytes = stripWidth * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * frame.height)
        for row in 0..<frame.height {
            let source = (row * frame.width + left) * 4
            let destination = row * rowBytes
            pixels.replaceSubrange(destination..<(destination + rowBytes), with: frame.pixels[source..<(source + rowBytes)])
        }
        return try RGBAImage(width: stripWidth, height: frame.height, pixels: pixels)
    }
}
