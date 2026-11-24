import Foundation

public struct ConstellationNode: Sendable, Equatable, Identifiable {
    public let id: Int
    public let text: String
    public let x: Double
    public let y: Double
    public let baseFontSize: Double
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(
        id: Int,
        text: String,
        x: Double,
        y: Double,
        baseFontSize: Double,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.baseFontSize = baseFontSize
        self.startTime = startTime
        self.endTime = endTime
    }
}

public enum ConstellationLayout {
    public static let safeMinX: Double = 0.08
    public static let safeMaxX: Double = 0.92
    public static let safeMinY: Double = 0.26
    public static let safeMaxY: Double = 0.72
    public static let minFontSize: Double = 15.0
    public static let maxFontSize: Double = 34.0

    private struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func nextUnit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
    }

    private struct Rect {
        let minX: Double
        let maxX: Double
        let minY: Double
        let maxY: Double

        func intersects(_ other: Rect) -> Bool {
            minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
        }
    }

    public static func generate(
        for line: LyricLine,
        seed: UInt64,
        canvasWidth: Double,
        canvasHeight: Double
    ) -> [ConstellationNode] {
        let words = line.words
        guard !words.isEmpty else { return [] }

        let w = max(canvasWidth, 640)
        let h = max(canvasHeight, 480)
        var rng = SplitMix64(seed: seed)

        let count = words.count
        var placedRects: [Rect] = []
        var nodes: [ConstellationNode] = []

        // Keep long lines comfortable by gently scaling font range when word count is high
        let densityScale = count > 10 ? 0.85 : 1.0

        for (i, word) in words.enumerated() {
            let lengthFactor = min(max(Double(word.text.count - 2) / 7.0, 0.0), 1.0)
            let jitter = rng.nextUnit() * 4.5
            let rawSize = (15.5 + lengthFactor * 7.5 + jitter) * densityScale
            let fontSize = min(max(rawSize, minFontSize), 26.0)

            let progress = count == 1 ? 0.5 : Double(i) / Double(count - 1)
            let targetX = 0.14 + progress * 0.72
            let waveSign = (i % 2 == 0) ? -1.0 : 1.0
            let targetY = 0.49 + waveSign * (0.07 + rng.nextUnit() * 0.11)

            let estW = Double(word.text.count) * fontSize * 0.62 + 24.0
            let estH = fontSize * 1.6 + 22.0
            let halfNormW = min((estW / 2.0) / w, 0.15)
            let halfNormH = min((estH / 2.0) / h, 0.08)

            let clampMinX = max(safeMinX, halfNormW + 0.02)
            let clampMaxX = min(safeMaxX, 1.0 - halfNormW - 0.02)
            let clampMinY = max(safeMinY, safeMinY + halfNormH * 0.2)
            let clampMaxY = min(safeMaxY, safeMaxY - halfNormH * 0.2)

            func makeRect(nx: Double, ny: Double) -> Rect {
                let cx = nx * w
                let cy = ny * h
                return Rect(minX: cx - estW / 2, maxX: cx + estW / 2, minY: cy - estH / 2, maxY: cy + estH / 2)
            }

            var chosenX = min(max(targetX, clampMinX), clampMaxX)
            var chosenY = min(max(targetY, clampMinY), clampMaxY)
            var chosenRect = makeRect(nx: chosenX, ny: chosenY)

            if placedRects.contains(where: { $0.intersects(chosenRect) }) {
                var found = false
                // Search progressively wider organic offsets around target first, then full safe band
                for attempt in 0..<120 {
                    let spreadX = attempt < 50 ? 0.14 : 0.42
                    let spreadY = attempt < 50 ? 0.20 : 0.44
                    let cx: Double
                    let cy: Double
                    if attempt < 50 {
                        cx = min(max(targetX + (rng.nextUnit() - 0.5) * 2.0 * spreadX, clampMinX), clampMaxX)
                        cy = min(max(0.49 + (rng.nextUnit() - 0.5) * 2.0 * spreadY, clampMinY), clampMaxY)
                    } else {
                        cx = clampMinX + rng.nextUnit() * (clampMaxX - clampMinX)
                        cy = clampMinY + rng.nextUnit() * (clampMaxY - clampMinY)
                    }
                    let candidate = makeRect(nx: cx, ny: cy)
                    if !placedRects.contains(where: { $0.intersects(candidate) }) {
                        chosenX = cx
                        chosenY = cy
                        chosenRect = candidate
                        found = true
                        break
                    }
                }
                if !found {
                    // Deterministic grid fallback inside safe zone
                    outer: for row in 0..<5 {
                        for col in 0..<8 {
                            let gx = clampMinX + (Double(col) / 7.0) * (clampMaxX - clampMinX)
                            let gy = clampMinY + (Double(row) / 4.0) * (clampMaxY - clampMinY)
                            let candidate = makeRect(nx: gx, ny: gy)
                            if !placedRects.contains(where: { $0.intersects(candidate) }) {
                                chosenX = gx
                                chosenY = gy
                                chosenRect = candidate
                                break outer
                            }
                        }
                    }
                }
            }

            placedRects.append(chosenRect)
            nodes.append(ConstellationNode(
                id: i,
                text: word.text,
                x: chosenX,
                y: chosenY,
                baseFontSize: fontSize,
                startTime: word.startTime,
                endTime: word.endTime
            ))
        }

        return nodes
    }
}
