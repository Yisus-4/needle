import Foundation

public enum LRCParser {
    private static let maxSecondsPerWord: TimeInterval = 0.85
    private static let maxLineWindow: TimeInterval = 8.0
    private static let defaultTailDuration: TimeInterval = 4.0

    private struct RawEvent {
        let time: TimeInterval
        let body: String
    }

    private enum EnhancedParseResult {
        case notEnhanced
        case emptyMarker
        case words([WordTiming])
    }

    public static func parse(_ raw: String, trackDuration: TimeInterval? = nil) -> SyncedLyrics {
        let lineTagRegex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]"#)
        let wordTagRegex = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?>"#)

        var events: [RawEvent] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let nsLine = trimmed as NSString
            let matches = lineTagRegex.matches(in: trimmed, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            let lastEnd = matches.last!.range.location + matches.last!.range.length
            let body = nsLine.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)

            for match in matches {
                if let time = extractTimestamp(from: nsLine, match: match) {
                    events.append(RawEvent(time: time, body: body))
                }
            }
        }

        events.sort { $0.time < $1.time }

        var parsedLines: [LyricLine] = []

        for idx in events.indices {
            let event = events[idx]
            guard !event.body.isEmpty else { continue }

            let nextEventTime: TimeInterval
            let hasNextEvent = (idx + 1 < events.count)
            if hasNextEvent {
                nextEventTime = events[idx + 1].time
            } else if let trackDuration, trackDuration > event.time {
                nextEventTime = trackDuration
            } else {
                nextEventTime = event.time + defaultTailDuration
            }

            let rawGap = nextEventTime - event.time
            if hasNextEvent && rawGap <= 0.001 {
                continue
            }
            let available = max(0.05, rawGap)
            let lineLimit = event.time + available

            switch parseEnhancedWords(body: event.body, lineStart: event.time, lineLimit: lineLimit, regex: wordTagRegex) {
            case .emptyMarker:
                continue
            case .words(let enhancedWords):
                let cleanText = enhancedWords.map(\.text).joined(separator: " ")
                let endTime = min(lineLimit, max(enhancedWords.last!.endTime, event.time + min(0.3, available)))
                parsedLines.append(LyricLine(startTime: event.time, endTime: endTime, text: cleanText, words: enhancedWords))
                continue
            case .notEnhanced:
                break
            }

            let tokens = event.body
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            guard !tokens.isEmpty else { continue }

            let cappedWindow = min(available, Double(tokens.count) * maxSecondsPerWord, maxLineWindow)
            let window = hasNextEvent ? min(available, max(0.05, cappedWindow)) : max(0.3, cappedWindow)
            let weights = tokens.map { Double(max($0.count, 2)) }
            let totalWeight = weights.reduce(0, +)

            var words: [WordTiming] = []
            var cursor = event.time
            for (token, weight) in zip(tokens, weights) {
                let duration = window * (weight / totalWeight)
                let end = cursor + duration
                words.append(WordTiming(text: token, startTime: cursor, endTime: end))
                cursor = end
            }

            parsedLines.append(LyricLine(
                startTime: event.time,
                endTime: event.time + window,
                text: tokens.joined(separator: " "),
                words: words
            ))
        }

        return SyncedLyrics(lines: parsedLines)
    }

    private static func parseEnhancedWords(
        body: String,
        lineStart: TimeInterval,
        lineLimit: TimeInterval,
        regex: NSRegularExpression
    ) -> EnhancedParseResult {
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        guard !matches.isEmpty else { return .notEnhanced }

        var rawWords: [(time: TimeInterval, text: String)] = []

        // Preserve any leading words appearing before the first <mm:ss.xx> tag
        if matches[0].range.location > 0 {
            let leading = nsBody.substring(with: NSRange(location: 0, length: matches[0].range.location))
                .trimmingCharacters(in: .whitespaces)
            for token in leading.split(whereSeparator: { $0.isWhitespace }) {
                rawWords.append((time: lineStart, text: String(token)))
            }
        }

        for i in matches.indices {
            let match = matches[i]
            guard let t = extractTimestamp(from: nsBody, match: match) else { continue }
            let startIdx = match.range.location + match.range.length
            let endIdx = (i + 1 < matches.count) ? matches[i + 1].range.location : nsBody.length
            let segment = nsBody.substring(with: NSRange(location: startIdx, length: endIdx - startIdx))
                .trimmingCharacters(in: .whitespaces)
            if !segment.isEmpty {
                rawWords.append((time: max(t, lineStart), text: segment))
            }
        }

        guard !rawWords.isEmpty else { return .emptyMarker }

        var result: [WordTiming] = []
        for i in rawWords.indices {
            let start = min(rawWords[i].time, lineLimit)
            let nextStart = (i + 1 < rawWords.count) ? min(rawWords[i + 1].time, lineLimit) : min(lineLimit, start + maxSecondsPerWord)
            let end = min(lineLimit, max(start + 0.05, min(nextStart, start + maxSecondsPerWord * 1.5)))
            result.append(WordTiming(text: rawWords[i].text, startTime: start, endTime: end))
        }
        return .words(result)
    }

    private static func extractTimestamp(from string: NSString, match: NSTextCheckingResult) -> TimeInterval? {
        guard match.numberOfRanges >= 3 else { return nil }
        guard
            let minutes = Double(string.substring(with: match.range(at: 1))),
            let seconds = Double(string.substring(with: match.range(at: 2)))
        else { return nil }

        var fraction = 0.0
        if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound {
            let fracStr = string.substring(with: match.range(at: 3))
            if let fracVal = Double(fracStr) {
                fraction = fracVal / pow(10.0, Double(fracStr.count))
            }
        }
        return minutes * 60.0 + seconds + fraction
    }
}
