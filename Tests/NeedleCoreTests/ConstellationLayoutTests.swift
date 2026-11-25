import Foundation
@testable import NeedleCore

func registerConstellationLayoutTests(_ runner: TestRunner) {
    runner.add("ConstellationLayoutTests", "deterministicForSameSeedAndRespectsSafeZone") {
        let line = LRCParser.parse("[00:10.00] needle find the Let Turn low down the lights", trackDuration: 60).lines[0]
        let a = ConstellationLayout.generate(for: line, seed: 42, canvasWidth: 1440, canvasHeight: 900)
        let b = ConstellationLayout.generate(for: line, seed: 42, canvasWidth: 1440, canvasHeight: 900)
        try expectEqual(a, b, "same seed must produce deterministic layout")
        try expectEqual(a.count, line.words.count)
        for node in a {
            try expect(node.x >= 0.08 && node.x <= 0.92, "x in safe bounds: \(node.x)")
            try expect(node.y >= ConstellationLayout.safeMinY && node.y <= ConstellationLayout.safeMaxY, "y in safe bounds: \(node.y)")
            try expect(node.baseFontSize >= ConstellationLayout.minFontSize && node.baseFontSize <= ConstellationLayout.maxFontSize, "font size in readable bounds: \(node.baseFontSize)")
        }
    }

    runner.add("ConstellationLayoutTests", "longLine14WordsHasZeroBoundingBoxOverlaps") {
        let line = LRCParser.parse(
            "[00:20.00] We are running through the midnight constellations chasing every glowing star across the sky",
            trackDuration: 120
        ).lines[0]
        let w = 1440.0
        let h = 900.0
        let nodes = ConstellationLayout.generate(for: line, seed: 99, canvasWidth: w, canvasHeight: h)
        try expectEqual(nodes.count, 14)

        let rects = nodes.map { n -> (minX: Double, maxX: Double, minY: Double, maxY: Double) in
            let estW = Double(n.text.count) * n.baseFontSize * 0.58 + 16.0
            let estH = n.baseFontSize * 1.45 + 14.0
            let cx = n.x * w
            let cy = n.y * h
            return (cx - estW / 2, cx + estW / 2, cy - estH / 2, cy + estH / 2)
        }

        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let r1 = rects[i]
                let r2 = rects[j]
                let overlaps = r1.minX < r2.maxX && r1.maxX > r2.minX && r1.minY < r2.maxY && r1.maxY > r2.minY
                try expect(!overlaps, "nodes \(i) ('\(nodes[i].text)') and \(j) ('\(nodes[j].text)') overlapped")
            }
        }
    }

    runner.add("ConstellationLayoutTests", "fontSizesVaryAcrossLineWhileStayingReadable") {
        let line = LRCParser.parse("[00:10.00] Turn down the glowing midnight lights in the sky", trackDuration: 60).lines[0]
        let nodes = ConstellationLayout.generate(for: line, seed: 7, canvasWidth: 1440, canvasHeight: 900)
        let distinctSizes = Set(nodes.map { Int($0.baseFontSize.rounded()) })
        try expect(distinctSizes.count >= 2, "expected varying font sizes, got \(distinctSizes)")
        for node in nodes {
            try expect(node.baseFontSize >= ConstellationLayout.minFontSize, "font size below readable floor")
        }
    }

    runner.add("ConstellationLayoutTests", "nodesStayInsideSafeBandEvenWithActiveWordOffsetAndScale") {
        let line = LRCParser.parse("[00:10.00] needle find the Let Turn low down the lights tonight", trackDuration: 60).lines[0]
        let h = 600.0 // smallest preview height
        let nodes = ConstellationLayout.generate(for: line, seed: 42, canvasWidth: 960, canvasHeight: h)
        for node in nodes {
            let activeBottomY = node.y * h + ConstellationLayout.activeLabelOffsetY + (ConstellationLayout.maxFontSize * 0.65)
            try expect(activeBottomY <= h * 0.75, "active label bottom \(activeBottomY) intruded past safe zone \(h * 0.75)")
        }
    }

    runner.add("ConstellationLayoutTests", "constellationMovesOrganicallyNotStrictlyLeftToRight") {
        let line = LRCParser.parse("[00:10.00] When it was real it is all that I could feel", trackDuration: 60).lines[0]
        var nonMonotonicLines = 0
        for seed in UInt64(1)...UInt64(10) {
            let nodes = ConstellationLayout.generate(for: line, seed: seed, canvasWidth: 1440, canvasHeight: 900)
            let xs = nodes.map(\.x)
            let hasLeftStep = zip(xs, xs.dropFirst()).contains { $1 < $0 }
            let hasRightStep = zip(xs, xs.dropFirst()).contains { $1 > $0 }
            if hasLeftStep && hasRightStep {
                nonMonotonicLines += 1
            }
        }
        try expect(nonMonotonicLines >= 8, "expected organic multi-directional movement in at least 8/10 seeds, got \(nonMonotonicLines)")
    }
}
