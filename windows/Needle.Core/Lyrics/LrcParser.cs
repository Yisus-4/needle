using System.Globalization;
using System.Text.RegularExpressions;
using Needle.Core.Models;

namespace Needle.Core.Lyrics;

public static partial class LrcParser
{
    private const double MaxSecondsPerWord = 0.85;
    private const double MaxLineWindow = 8.0;
    private const double DefaultTailDuration = 4.0;

    [GeneratedRegex(@"\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]")]
    private static partial Regex LineTagRegex();

    [GeneratedRegex(@"<(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?>")]
    private static partial Regex WordTagRegex();

    private readonly record struct RawEvent(double Time, string Body);

    private enum EnhancedKind { NotEnhanced, EmptyMarker, Words }

    public static SyncedLyrics Parse(string raw, double? trackDuration = null)
    {
        var events = new List<RawEvent>();

        foreach (var rawLine in raw.Split(["\r\n", "\n", "\r"], StringSplitOptions.None))
        {
            var trimmed = rawLine.Trim();
            if (string.IsNullOrEmpty(trimmed)) continue;

            var matches = LineTagRegex().Matches(trimmed);
            if (matches.Count == 0) continue;

            var last = matches[^1];
            var body = trimmed[(last.Index + last.Length)..].Trim();

            foreach (Match m in matches)
            {
                if (TryExtractTimestamp(m, out double time))
                {
                    events.Add(new RawEvent(time, body));
                }
            }
        }

        events.Sort((a, b) => a.Time.CompareTo(b.Time));
        var parsedLines = new List<LyricLine>();

        for (int i = 0; i < events.Count; i++)
        {
            var ev = events[i];
            if (string.IsNullOrEmpty(ev.Body)) continue;

            bool hasNext = i + 1 < events.Count;
            double nextTime;
            if (hasNext)
                nextTime = events[i + 1].Time;
            else if (trackDuration is > 0 && trackDuration.Value > ev.Time)
                nextTime = trackDuration.Value;
            else
                nextTime = ev.Time + DefaultTailDuration;

            double rawGap = nextTime - ev.Time;
            if (hasNext && rawGap <= 0.001) continue;

            double available = Math.Max(0.05, rawGap);
            double lineLimit = ev.Time + available;

            var (kind, enhancedWords) = ParseEnhancedWords(ev.Body, ev.Time, lineLimit);
            if (kind == EnhancedKind.EmptyMarker) continue;
            if (kind == EnhancedKind.Words && enhancedWords is { Count: > 0 })
            {
                string cleanText = string.Join(" ", enhancedWords.Select(w => w.Text));
                double endTime = Math.Min(lineLimit, Math.Max(enhancedWords[^1].EndTime, ev.Time + Math.Min(0.3, available)));
                parsedLines.Add(new LyricLine(ev.Time, endTime, cleanText, enhancedWords));
                continue;
            }

            var tokens = ev.Body.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (tokens.Length == 0) continue;

            double capped = Math.Min(available, Math.Min(tokens.Length * MaxSecondsPerWord, MaxLineWindow));
            double window = hasNext ? Math.Min(available, Math.Max(0.05, capped)) : Math.Max(0.3, capped);
            double totalWeight = tokens.Sum(t => (double)Math.Max(t.Length, 2));

            var words = new List<WordTiming>(tokens.Length);
            double cursor = ev.Time;
            foreach (var token in tokens)
            {
                double weight = Math.Max(token.Length, 2);
                double dur = window * (weight / totalWeight);
                double end = cursor + dur;
                words.Add(new WordTiming(token, cursor, end));
                cursor = end;
            }

            parsedLines.Add(new LyricLine(ev.Time, ev.Time + window, string.Join(" ", tokens), words));
        }

        return new SyncedLyrics(parsedLines);
    }

    private static (EnhancedKind Kind, List<WordTiming>? Words) ParseEnhancedWords(
        string body,
        double lineStart,
        double lineLimit)
    {
        var matches = WordTagRegex().Matches(body);
        if (matches.Count == 0) return (EnhancedKind.NotEnhanced, null);

        var rawWords = new List<(double Time, string Text)>();

        if (matches[0].Index > 0)
        {
            var leading = body[..matches[0].Index].Trim();
            foreach (var token in leading.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
            {
                rawWords.Add((lineStart, token));
            }
        }

        for (int i = 0; i < matches.Count; i++)
        {
            var m = matches[i];
            if (!TryExtractTimestamp(m, out double t)) continue;
            int startIdx = m.Index + m.Length;
            int endIdx = i + 1 < matches.Count ? matches[i + 1].Index : body.Length;
            var segment = body[startIdx..endIdx].Trim();
            if (!string.IsNullOrEmpty(segment))
            {
                rawWords.Add((Math.Max(t, lineStart), segment));
            }
        }

        if (rawWords.Count == 0) return (EnhancedKind.EmptyMarker, null);

        var result = new List<WordTiming>(rawWords.Count);
        for (int i = 0; i < rawWords.Count; i++)
        {
            double start = Math.Min(rawWords[i].Time, lineLimit);
            double nextStart = i + 1 < rawWords.Count
                ? Math.Min(rawWords[i + 1].Time, lineLimit)
                : Math.Min(lineLimit, start + MaxSecondsPerWord);
            double end = Math.Min(lineLimit, Math.Max(start + 0.05, Math.Min(nextStart, start + MaxSecondsPerWord * 1.5)));
            result.Add(new WordTiming(rawWords[i].Text, start, end));
        }
        return (EnhancedKind.Words, result);
    }

    private static bool TryExtractTimestamp(Match match, out double seconds)
    {
        seconds = 0;
        if (!double.TryParse(match.Groups[1].Value, CultureInfo.InvariantCulture, out double mins) ||
            !double.TryParse(match.Groups[2].Value, CultureInfo.InvariantCulture, out double secs))
        {
            return false;
        }

        double frac = 0;
        var fracGroup = match.Groups[3];
        if (fracGroup.Success && double.TryParse(fracGroup.Value, CultureInfo.InvariantCulture, out double fracVal))
        {
            frac = fracVal / Math.Pow(10.0, fracGroup.Value.Length);
        }

        seconds = mins * 60.0 + secs + frac;
        return true;
    }
}
