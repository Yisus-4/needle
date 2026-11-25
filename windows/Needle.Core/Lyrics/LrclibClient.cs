using System.Collections.Concurrent;
using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Needle.Core.Models;

namespace Needle.Core.Lyrics;

public interface IHttpTransport
{
    Task<(HttpStatusCode StatusCode, string Body)> GetAsync(Uri uri, string userAgent, CancellationToken ct);
}

public sealed class HttpClientTransport : IHttpTransport
{
    private readonly HttpClient _http;

    public HttpClientTransport(HttpClient? httpClient = null)
    {
        _http = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
    }

    public async Task<(HttpStatusCode StatusCode, string Body)> GetAsync(Uri uri, string userAgent, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, uri);
        req.Headers.UserAgent.ParseAdd(userAgent);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        string body = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        return (resp.StatusCode, body);
    }
}

public sealed partial class LrclibClient
{
    private const string UserAgent = "Needle/1.0 (https://github.com/local/needle)";
    private const double PrimaryDurationTolerance = 15.0;
    private const double RelaxedDurationTolerance = 30.0;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    [GeneratedRegex(@"\s*[\(\[].*?[\)\]]")]
    private static partial Regex BracketSuffixRegex();

    [GeneratedRegex(@"\s+-\s+.*$")]
    private static partial Regex DashSuffixRegex();

    private sealed class LrclibRecord
    {
        [JsonPropertyName("trackName")] public string? TrackName { get; set; }
        [JsonPropertyName("artistName")] public string? ArtistName { get; set; }
        [JsonPropertyName("albumName")] public string? AlbumName { get; set; }
        [JsonPropertyName("duration")] public double? Duration { get; set; }
        [JsonPropertyName("syncedLyrics")] public string? SyncedLyrics { get; set; }
    }

    private enum FetchKind { Found, NotFound, TransientError }
    private readonly record struct FetchOutcome(FetchKind Kind, SyncedLyrics? Lyrics = null);
    private sealed record CacheEntry(bool IsHit, SyncedLyrics? Lyrics);

    private readonly IHttpTransport _transport;
    private readonly ConcurrentDictionary<string, CacheEntry> _cache = new();

    public LrclibClient(IHttpTransport? transport = null)
    {
        _transport = transport ?? new HttpClientTransport();
    }

    public async Task<SyncedLyrics?> FetchLyricsAsync(TrackInfo track, CancellationToken ct = default)
    {
        if (_cache.TryGetValue(track.Id, out var cached))
        {
            return cached.IsHit ? cached.Lyrics : null;
        }

        var exact = await FetchExactAsync(track, ct).ConfigureAwait(false);
        if (exact.Kind == FetchKind.Found && exact.Lyrics is not null)
        {
            _cache[track.Id] = new CacheEntry(true, exact.Lyrics);
            return exact.Lyrics;
        }

        var strictUri = BuildUri("https://lrclib.net/api/search",
            ("track_name", track.Name),
            ("artist_name", track.Artist));
        var strict = await FetchViaSearchAsync(strictUri, track, ct).ConfigureAwait(false);
        if (strict.Kind == FetchKind.Found && strict.Lyrics is not null)
        {
            _cache[track.Id] = new CacheEntry(true, strict.Lyrics);
            return strict.Lyrics;
        }

        string cleaned = CleanTitle(track.Name);
        var broadUri = BuildUri("https://lrclib.net/api/search", ("q", $"{cleaned} {track.Artist}"));
        var broad = await FetchViaSearchAsync(broadUri, track, ct).ConfigureAwait(false);
        if (broad.Kind == FetchKind.Found && broad.Lyrics is not null)
        {
            _cache[track.Id] = new CacheEntry(true, broad.Lyrics);
            return broad.Lyrics;
        }

        if (exact.Kind == FetchKind.NotFound && strict.Kind == FetchKind.NotFound && broad.Kind == FetchKind.NotFound)
        {
            _cache[track.Id] = new CacheEntry(false, null);
        }

        return null;
    }

    private async Task<FetchOutcome> FetchExactAsync(TrackInfo track, CancellationToken ct)
    {
        var uri = BuildUri("https://lrclib.net/api/get",
            ("track_name", track.Name),
            ("artist_name", track.Artist),
            ("album_name", track.Album),
            ("duration", ((int)Math.Round(track.DurationSeconds)).ToString()));

        try
        {
            var (status, body) = await _transport.GetAsync(uri, UserAgent, ct).ConfigureAwait(false);
            if (status == HttpStatusCode.NotFound) return new FetchOutcome(FetchKind.NotFound);
            if (status != HttpStatusCode.OK) return new FetchOutcome(FetchKind.TransientError);

            var record = JsonSerializer.Deserialize<LrclibRecord>(body, JsonOptions);
            if (string.IsNullOrWhiteSpace(record?.SyncedLyrics)) return new FetchOutcome(FetchKind.NotFound);

            var parsed = LrcParser.Parse(record.SyncedLyrics, track.DurationSeconds);
            return parsed.Lines.Count == 0
                ? new FetchOutcome(FetchKind.NotFound)
                : new FetchOutcome(FetchKind.Found, parsed);
        }
        catch
        {
            return new FetchOutcome(FetchKind.TransientError);
        }
    }

    private async Task<FetchOutcome> FetchViaSearchAsync(Uri uri, TrackInfo track, CancellationToken ct)
    {
        try
        {
            var (status, body) = await _transport.GetAsync(uri, UserAgent, ct).ConfigureAwait(false);
            if (status == HttpStatusCode.NotFound) return new FetchOutcome(FetchKind.NotFound);
            if (status != HttpStatusCode.OK) return new FetchOutcome(FetchKind.TransientError);

            var records = JsonSerializer.Deserialize<List<LrclibRecord>>(body, JsonOptions);
            if (records is null || records.Count == 0) return new FetchOutcome(FetchKind.NotFound);

            string? bestRaw = SelectBestMatch(records, track);
            if (bestRaw is null) return new FetchOutcome(FetchKind.NotFound);

            var parsed = LrcParser.Parse(bestRaw, track.DurationSeconds);
            return parsed.Lines.Count == 0
                ? new FetchOutcome(FetchKind.NotFound)
                : new FetchOutcome(FetchKind.Found, parsed);
        }
        catch
        {
            return new FetchOutcome(FetchKind.TransientError);
        }
    }

    private static string? SelectBestMatch(List<LrclibRecord> records, TrackInfo track)
    {
        string targetAlbum = track.Album.Trim().ToLowerInvariant();
        string targetName = CleanTitle(track.Name).ToLowerInvariant();
        string targetArtist = track.Artist.Trim().ToLowerInvariant();

        double bestScore = double.MaxValue;
        string? bestRaw = null;

        foreach (var rec in records)
        {
            if (string.IsNullOrWhiteSpace(rec.SyncedLyrics)) continue;

            double diff = Math.Abs((rec.Duration ?? track.DurationSeconds) - track.DurationSeconds);
            string recName = CleanTitle(rec.TrackName ?? string.Empty).ToLowerInvariant();
            string recArtist = (rec.ArtistName ?? string.Empty).Trim().ToLowerInvariant();
            bool nameAndArtistMatch = !string.IsNullOrEmpty(recName) &&
                                      recName == targetName &&
                                      recArtist.Contains(targetArtist, StringComparison.Ordinal);

            double maxAllowed = nameAndArtistMatch ? RelaxedDurationTolerance : PrimaryDurationTolerance;
            if (diff > maxAllowed) continue;

            string recAlbum = (rec.AlbumName ?? string.Empty).Trim().ToLowerInvariant();
            double albumBonus = (!string.IsNullOrEmpty(targetAlbum) && recAlbum == targetAlbum) ? -2.0 : 0.0;
            double score = diff + albumBonus;
            if (score < bestScore)
            {
                bestScore = score;
                bestRaw = rec.SyncedLyrics;
            }
        }

        return bestRaw;
    }

    private static string CleanTitle(string title)
    {
        string cleaned = BracketSuffixRegex().Replace(title, string.Empty);
        cleaned = DashSuffixRegex().Replace(cleaned, string.Empty);
        return cleaned.Trim();
    }

    private static Uri BuildUri(string baseUrl, params (string Key, string Value)[] query)
    {
        var qs = string.Join("&", query.Select(q => $"{Uri.EscapeDataString(q.Key)}={Uri.EscapeDataString(q.Value)}"));
        return new Uri($"{baseUrl}?{qs}");
    }
}
