import Foundation
@testable import NeedleCore

func registerLRCParserTests(_ runner: TestRunner) {
    runner.add("LRCParserTests", "standardLRCDistributesWordsProportionally") {
        let raw = """
        [00:10.00] Hello beautiful world
        [00:13.00] Next line
        """
        let lyrics = LRCParser.parse(raw, trackDuration: 180)
        try expectEqual(lyrics.lines.count, 2)
        let words = lyrics.lines[0].words
        try expectEqual(words.map(\.text), ["Hello", "beautiful", "world"])
        try expectClose(words[0].startTime, 10.0, accuracy: 0.01)
        try expect((words[1].endTime - words[1].startTime) > (words[0].endTime - words[0].startTime), "longer word gets more time")
        try expect(words.last!.endTime <= 13.0 + 0.001, "words end before next line")
    }

    runner.add("LRCParserTests", "enhancedLRCUsesExactWordTimestamps") {
        let raw = "[00:05.00] <00:05.00> Esta <00:05.40> línea <00:06.10> brilla"
        let lyrics = LRCParser.parse(raw, trackDuration: 60)
        let words = lyrics.lines[0].words
        try expectEqual(words.map(\.text), ["Esta", "línea", "brilla"])
        try expectClose(words[0].startTime, 5.0, accuracy: 0.01)
        try expectClose(words[1].startTime, 5.4, accuracy: 0.01)
        try expectClose(words[2].startTime, 6.1, accuracy: 0.01)
    }

    runner.add("LRCParserTests", "instrumentalGapCapsLineWindowAndSkipsBlankLines") {
        let raw = """
        [00:10.00] Short phrase
        [00:14.00]
        [00:40.00] After solo
        """
        let lyrics = LRCParser.parse(raw, trackDuration: 120)
        try expectEqual(lyrics.lines.count, 2)
        try expect(lyrics.lines[0].endTime <= 14.0 + 0.001, "blank marker closes line")
        try expect(lyrics.activeLine(at: 25.0) == nil, "no active line during instrumental gap")
        try expectEqual(lyrics.activeLine(at: 40.5)?.line.text, "After solo")
    }

    runner.add("LRCParserTests", "enhancedLRCBlankMarkerIsSkippedAndLeadingTextPreserved") {
        let raw = """
        [00:05.00] First <00:05.40> second
        [00:14.00] <00:14.00>
        [00:20.00] Third
        """
        let lyrics = LRCParser.parse(raw, trackDuration: 60)
        try expectEqual(lyrics.lines.count, 2, "blank enhanced marker must be skipped")
        try expectEqual(lyrics.lines[0].words.map(\.text), ["First", "second"])
        try expectEqual(lyrics.lines[1].text, "Third")
    }

    runner.add("LRCParserTests", "rapidConsecutiveLinesDoNotOverlap") {
        let raw = """
        [00:10.00] QuickA
        [00:10.15] QuickB
        """
        let lyrics = LRCParser.parse(raw, trackDuration: 60)
        try expectEqual(lyrics.lines.count, 2)
        try expect(lyrics.lines[0].endTime <= lyrics.lines[1].startTime + 0.0001, "lines must not overlap")
        try expectEqual(lyrics.activeLine(at: 10.16)?.line.text, "QuickB")
    }
}
