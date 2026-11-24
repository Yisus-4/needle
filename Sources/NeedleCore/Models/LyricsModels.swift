import Foundation

public struct WordTiming: Sendable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct LyricLine: Sendable, Equatable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    public let words: [WordTiming]

    public init(startTime: TimeInterval, endTime: TimeInterval, text: String, words: [WordTiming]) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.words = words
    }
}

public struct SyncedLyrics: Sendable, Equatable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        self.lines = lines
    }

    public func activeLine(at time: TimeInterval) -> (index: Int, line: LyricLine)? {
        for (idx, line) in lines.enumerated() {
            if time >= line.startTime && time < line.endTime {
                return (idx, line)
            }
        }
        return nil
    }
}
