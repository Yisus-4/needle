import CoreGraphics
import Foundation
import ImageIO

public enum PaletteExtractor {
    private struct HueBucket {
        var weight: Double = 0
        var rSum: Double = 0
        var gSum: Double = 0
        var bSum: Double = 0
        var satSum: Double = 0
    }

    public static func extract(from imageData: Data) -> AlbumPalette {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return .fallback
        }

        let targetSize = 32
        var pixels = [UInt8](repeating: 0, count: targetSize * targetSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: targetSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .fallback
        }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        return extract(from: pixels, width: targetSize, height: targetSize)
    }

    public static func extract(from rgbaPixels: [UInt8], width: Int, height: Int) -> AlbumPalette {
        let pixelCount = min(width * height, rgbaPixels.count / 4)
        guard pixelCount > 0 else { return .fallback }

        let bucketCount = 12
        var buckets = [HueBucket](repeating: HueBucket(), count: bucketCount)
        var totalSat = 0.0
        var rAvg = 0.0
        var gAvg = 0.0
        var bAvg = 0.0

        for i in 0..<pixelCount {
            let base = i * 4
            let a = Double(rgbaPixels[base + 3]) / 255.0
            guard a > 0.1 else { continue }
            let r = Double(rgbaPixels[base]) / 255.0
            let g = Double(rgbaPixels[base + 1]) / 255.0
            let b = Double(rgbaPixels[base + 2]) / 255.0

            rAvg += r
            gAvg += g
            bAvg += b

            let hsb = RGBColor(r: r, g: g, b: b).toHSB()
            totalSat += hsb.s

            let idx = min(bucketCount - 1, Int(hsb.h * Double(bucketCount)))
            let w = (0.2 + hsb.s * 1.8) * (0.25 + hsb.b * 0.75)
            buckets[idx].weight += w
            buckets[idx].rSum += r * w
            buckets[idx].gSum += g * w
            buckets[idx].bSum += b * w
            buckets[idx].satSum += hsb.s * w
        }

        let avgSat = totalSat / Double(pixelCount)
        if avgSat < 0.08 {
            // Monochrome or near-monochrome cover (pure black/white/gray) -> crisp midnight tint + bright ice accent
            let meanLuma = RGBColor(
                r: rAvg / Double(pixelCount),
                g: gAvg / Double(pixelCount),
                b: bAvg / Double(pixelCount)
            ).relativeLuminance
            let primary = RGBColor.fromHSB(h: 0.61, s: 0.22, b: meanLuma > 0.5 ? 0.18 : 0.11)
            let secondary = RGBColor.fromHSB(h: 0.64, s: 0.28, b: 0.08)
            let accent = RGBColor.fromHSB(h: 0.59, s: 0.18, b: 0.94)
            return AlbumPalette(backdropPrimary: primary, backdropSecondary: secondary, accent: accent)
        }

        let ranked = buckets.enumerated()
            .filter { $0.element.weight > 0 }
            .sorted { $0.element.weight > $1.element.weight }

        guard let top = ranked.first?.element else { return .fallback }
        let primaryRaw = RGBColor(r: top.rSum / top.weight, g: top.gSum / top.weight, b: top.bSum / top.weight)
        let primaryHSB = primaryRaw.toHSB()

        let secondaryRaw: RGBColor
        if let second = ranked.dropFirst().first(where: { abs($0.offset - ranked[0].offset) >= 2 })?.element {
            secondaryRaw = RGBColor(r: second.rSum / second.weight, g: second.gSum / second.weight, b: second.bSum / second.weight)
        } else {
            secondaryRaw = RGBColor.fromHSB(h: primaryHSB.h + 0.08, s: primaryHSB.s, b: primaryHSB.b)
        }
        let secondaryHSB = secondaryRaw.toHSB()

        let backdropPrimary = RGBColor.fromHSB(
            h: primaryHSB.h,
            s: min(max(primaryHSB.s, 0.35), 0.78),
            b: 0.20
        )
        let backdropSecondary = RGBColor.fromHSB(
            h: secondaryHSB.h,
            s: min(max(secondaryHSB.s, 0.30), 0.72),
            b: 0.13
        )
        let accentHue = secondaryHSB.s > 0.35 ? secondaryHSB.h : primaryHSB.h
        let accent = RGBColor.fromHSB(
            h: accentHue,
            s: min(max(primaryHSB.s * 0.65, 0.28), 0.58),
            b: 0.95
        )

        return AlbumPalette(
            backdropPrimary: backdropPrimary,
            backdropSecondary: backdropSecondary,
            accent: accent
        )
    }
}
