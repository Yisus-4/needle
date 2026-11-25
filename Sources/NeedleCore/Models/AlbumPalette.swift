import Foundation

public struct RGBColor: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    public func toHSB() -> (h: Double, s: Double, b: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue = 0.0
        if delta > 0.0001 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6.0
            if hue < 0 { hue += 1.0 }
        }
        let sat = maxC > 0.0001 ? delta / maxC : 0.0
        return (hue, sat, maxC)
    }

    public static func fromHSB(h: Double, s: Double, b: Double) -> RGBColor {
        let hh = ((h.truncatingRemainder(dividingBy: 1.0)) + 1.0).truncatingRemainder(dividingBy: 1.0)
        let ss = min(max(s, 0), 1)
        let bb = min(max(b, 0), 1)

        let c = bb * ss
        let x = c * (1 - abs((hh * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = bb - c

        let (r1, g1, b1): (Double, Double, Double)
        switch hh * 6 {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default:    (r1, g1, b1) = (c, 0, x)
        }
        return RGBColor(r: r1 + m, g: g1 + m, b: b1 + m)
    }
}

public struct AlbumPalette: Sendable, Equatable {
    public let backdropPrimary: RGBColor
    public let backdropSecondary: RGBColor
    public let accent: RGBColor

    public init(backdropPrimary: RGBColor, backdropSecondary: RGBColor, accent: RGBColor) {
        self.backdropPrimary = backdropPrimary
        self.backdropSecondary = backdropSecondary
        self.accent = accent
    }

    public static let fallback = AlbumPalette(
        backdropPrimary: RGBColor(r: 0.05, g: 0.07, b: 0.14),
        backdropSecondary: RGBColor(r: 0.03, g: 0.04, b: 0.09),
        accent: RGBColor(r: 0.62, g: 0.78, b: 1.0)
    )
}
