import Testing
@testable import SprintTimerCore

struct RasterTests {
    private func image(_ reds: [[UInt8]]) throws -> RGBAImage {
        let pixels = reds.flatMap { row in row.flatMap { [$0, 0, 0, 255] as [UInt8] } }
        return try RGBAImage(width: reds[0].count, height: reds.count, pixels: pixels)
    }

    @Test func testBandExtractionAndChronologicalCompositionPreserveRows() throws {
        let first = try image([[1, 2, 3], [4, 5, 6]])
        let second = try image([[10, 20, 30], [40, 50, 60]])
        var raster = try PhotoFinishRaster(height: 2, stripWidth: 1)
        try raster.append(frame: first, linePosition: 0.5)
        try raster.append(frame: second, linePosition: 0.5)
        #expect(raster.frameCount == 2)
        #expect(raster.width == 2)
        #expect(try raster.image() == image([[2, 20], [5, 50]]))
    }

    @Test func testTwoPixelStripsAndEdgeClamping() throws {
        let source = try image([[1, 2, 3, 4], [5, 6, 7, 8]])
        #expect(try PhotoFinishRaster.extractStrip(from: source, linePosition: 0, stripWidth: 2) == image([[1, 2], [5, 6]]))
        #expect(try PhotoFinishRaster.extractStrip(from: source, linePosition: 1, stripWidth: 2) == image([[3, 4], [7, 8]]))
        var raster = try PhotoFinishRaster(height: 2, stripWidth: 2)
        try raster.append(frame: source, linePosition: 0)
        try raster.append(frame: source, linePosition: 1)
        #expect(try raster.image() == source)
    }

    @Test func testMemoryLimitFailsBeforeMutatingExistingTile() throws {
        var raster = try PhotoFinishRaster(height: 2, stripWidth: 1, maximumBytes: 8)
        let source = try image([[1], [2]])
        try raster.append(strip: source)
        #expect(throws: RasterError.memoryLimit) { try raster.append(strip: source) }
        #expect(raster.frameCount == 1)
        #expect(try raster.image() == source)
    }

    @Test func testCorruptDimensionsAndPositionsAreRejected() throws {
        #expect(throws: (any Error).self) { try RGBAImage(width: 0, height: 2, pixels: []) }
        #expect(throws: (any Error).self) { try RGBAImage(width: Int.max, height: Int.max, pixels: []) }
        #expect(throws: (any Error).self) { try RGBAImage(width: 1, height: 1, pixels: [0]) }
        #expect(throws: (any Error).self) { try PhotoFinishRaster(height: 2, stripWidth: 2, maximumBytes: 1) }
        let source = try image([[1, 2]])
        #expect(throws: (any Error).self) { try PhotoFinishRaster.extractStrip(from: source, linePosition: .nan, stripWidth: 1) }
        #expect(throws: (any Error).self) { try PhotoFinishRaster.extractStrip(from: source, linePosition: -1, stripWidth: 1) }
        #expect(throws: (any Error).self) { try PhotoFinishRaster.extractStrip(from: source, linePosition: 1, stripWidth: 3) }
        var raster = try PhotoFinishRaster(height: 2, stripWidth: 1)
        #expect(throws: (any Error).self) { try raster.image() }
        #expect(throws: (any Error).self) { try raster.append(strip: source) }
    }
}
