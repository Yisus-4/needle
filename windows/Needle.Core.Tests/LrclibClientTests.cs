using System.Net;
using Needle.Core.Lyrics;
using Needle.Core.Models;
using Xunit;

namespace Needle.Core.Tests;

public sealed class LrclibClientTests
{
    private sealed class MockTransport(Func<Uri, string, Task<(HttpStatusCode, string)>> handler) : IHttpTransport
    {
        public List<Uri> Requests { get; } = [];

        public Task<(HttpStatusCode StatusCode, string Body)> GetAsync(Uri uri, string userAgent, CancellationToken ct)
        {
            Requests.Add(uri);
            return handler(uri, userAgent);
        }
    }

    [Fact]
    public async Task ExactGetReturnsLyricsAndCachesByTrackId()
    {
        var transport = new MockTransport((uri, ua) =>
        {
            Assert.Contains("Needle", ua);
            return Task.FromResult((HttpStatusCode.OK, """{"syncedLyrics":"[00:05.00] Hello world"}"""));
        });
        var client = new LrclibClient(transport);
        var track = new TrackInfo("t1", "Hello", "Artist", "Album", 214.4);

        var first = await client.FetchLyricsAsync(track);
        var second = await client.FetchLyricsAsync(track);

        Assert.NotNull(first);
        Assert.Equal(first, second);
        Assert.Single(transport.Requests);
        Assert.Contains("duration=214", transport.Requests[0].AbsoluteUri);
    }

    [Fact]
    public async Task SearchFallbackMatches9SecondDurationDifferenceAndPrefersAlbum()
    {
        var transport = new MockTransport((uri, _) =>
        {
            if (uri.AbsolutePath.EndsWith("/api/get", StringComparison.Ordinal))
                return Task.FromResult((HttpStatusCode.NotFound, string.Empty));

            const string json = """
            [
              {"trackName":"Daisy Chain","artistName":"The Neighbourhood","albumName":"Other","duration":207.0,"syncedLyrics":"[00:13.16] Other album"},
              {"trackName":"Daisy Chain","artistName":"The Neighbourhood","albumName":"(((((ultraSOUND)))))","duration":206.18,"syncedLyrics":"[00:13.16] Oh, oh, oh"}
            ]
            """;
            return Task.FromResult((HttpStatusCode.OK, json));
        });

        var client = new LrclibClient(transport);
        var track = new TrackInfo("daisy", "Daisy Chain", "The Neighbourhood", "(((((ultraSOUND)))))", 197.84);

        var lyrics = await client.FetchLyricsAsync(track);
        Assert.Equal("Oh, oh, oh", lyrics?.Lines[0].Text);
    }

    [Fact]
    public async Task TransientNetworkErrorIsNotCachedAsMiss()
    {
        int calls = 0;
        var transport = new MockTransport((_, _) =>
        {
            calls++;
            if (calls <= 3) throw new HttpRequestException("offline");
            return Task.FromResult((HttpStatusCode.OK, """{"syncedLyrics":"[00:01.00] Recovered"}"""));
        });

        var client = new LrclibClient(transport);
        var track = new TrackInfo("retry", "Retry", "Artist", "Album", 180);

        Assert.Null(await client.FetchLyricsAsync(track));
        var recovered = await client.FetchLyricsAsync(track);
        Assert.Equal("Recovered", recovered?.Lines[0].Text);
    }
}
