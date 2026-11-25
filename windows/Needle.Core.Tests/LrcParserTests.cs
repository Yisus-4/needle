using Needle.Core.Lyrics;
using Xunit;

namespace Needle.Core.Tests;

public sealed class LrcParserTests
{
    [Fact]
    public void StandardLrcDistributesWordsProportionally()
    {
        const string raw = "[00:10.00] Hello beautiful world\n[00:13.00] Next line";
        var lyrics = LrcParser.Parse(raw, trackDuration: 180);

        Assert.Equal(2, lyrics.Lines.Count);
        var words = lyrics.Lines[0].Words;
        Assert.Equal(["Hello", "beautiful", "world"], words.Select(w => w.Text).ToArray());
        Assert.InRange(words[0].StartTime, 9.99, 10.01);
        Assert.True((words[1].EndTime - words[1].StartTime) > (words[0].EndTime - words[0].StartTime));
        Assert.True(words[^1].EndTime <= 13.001);
    }

    [Fact]
    public void EnhancedLrcUsesExactWordTimestampsAndPreservesLeadingText()
    {
        const string raw = "[00:05.00] First <00:05.40> línea <00:06.10> brilla\n[00:14.00] <00:14.00>\n[00:20.00] Third";
        var lyrics = LrcParser.Parse(raw, trackDuration: 60);

        Assert.Equal(2, lyrics.Lines.Count);
        var words = lyrics.Lines[0].Words;
        Assert.Equal(["First", "línea", "brilla"], words.Select(w => w.Text).ToArray());
        Assert.InRange(words[0].StartTime, 4.99, 5.01);
        Assert.InRange(words[1].StartTime, 5.39, 5.41);
        Assert.InRange(words[2].StartTime, 6.09, 6.11);
        Assert.Equal("Third", lyrics.Lines[1].Text);
    }

    [Fact]
    public void InstrumentalGapCapsWindowAndRapidLinesDoNotOverlap()
    {
        const string raw = "[00:10.00] QuickA\n[00:10.15] QuickB\n[00:14.00]\n[00:40.00] After solo";
        var lyrics = LrcParser.Parse(raw, trackDuration: 120);

        Assert.Equal(3, lyrics.Lines.Count);
        Assert.True(lyrics.Lines[0].EndTime <= lyrics.Lines[1].StartTime + 0.0001);
        Assert.Equal("QuickB", lyrics.ActiveLine(10.16)?.Line.Text);
        Assert.Null(lyrics.ActiveLine(25.0));
        Assert.Equal("After solo", lyrics.ActiveLine(40.5)?.Line.Text);
    }
}
