import Foundation
@testable import NeedleCore

private func solidRGBA(r: UInt8, g: UInt8, b: UInt8, count: Int = 64) -> [UInt8] {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(count * 4)
    for _ in 0..<count {
        bytes.append(contentsOf: [r, g, b, 255])
    }
    return bytes
}

func registerPaletteExtractorTests(_ runner: TestRunner) {

    runner.add("PaletteExtractorTests", "extractsDominantHueFromVibrantImage") {
        var pixels = solidRGBA(r: 120, g: 40, b: 210, count: 48)
        pixels.append(contentsOf: solidRGBA(r: 30, g: 190, b: 200, count: 16))
        let palette = PaletteExtractor.extract(from: pixels, width: 8, height: 8)
        try expect(palette.backdropPrimary.relativeLuminance <= 0.14, "backdrop must stay dark")
        try expect(palette.accent.relativeLuminance >= 0.35, "accent must stay bright")
        try expect(palette.backdropPrimary.b > palette.backdropPrimary.g, "backdrop preserves purple/blue hue")
    }

    runner.add("PaletteExtractorTests", "pureBlackAndPureWhiteCoversClampToReadablePalette") {
        let black = PaletteExtractor.extract(from: solidRGBA(r: 0, g: 0, b: 0), width: 8, height: 8)
        try expect(black.backdropPrimary.relativeLuminance <= 0.14, "black cover backdrop stays dark")
        try expect(black.accent.relativeLuminance >= 0.45, "black cover accent stays bright")

        let white = PaletteExtractor.extract(from: solidRGBA(r: 255, g: 255, b: 255), width: 8, height: 8)
        try expect(white.backdropPrimary.relativeLuminance <= 0.14, "white cover backdrop clamps dark")
        try expect(white.accent.relativeLuminance >= 0.45, "white cover accent stays bright")
    }

    runner.add("PaletteExtractorTests", "invalidImageDataReturnsFallback") {
        let palette = PaletteExtractor.extract(from: Data("not-an-image".utf8))
        try expectEqual(palette, .fallback)
    }
}
