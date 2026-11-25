using Needle.Core.Lyrics;
using Needle.Core.Models;
using Xunit;

namespace Needle.Core.Tests;

public sealed class PlaybackClockTests
{
    private static readonly TrackInfo SampleTrack = new("id1", "Instant Crush", "Daft Punk", "RAM", 337);

    [Fact]
    public void AdvancesSmoothlyWhilePlayingAndFreezesWhilePaused()
    {
        var clock = new PlaybackClock();
        clock.Sync(new PlaybackSnapshot(PlaybackState.Playing, 10.0, SampleTrack, 100.0));
        Assert.Equal(11.25, clock.CurrentPosition(101.25), 3);

        clock.Sync(new PlaybackSnapshot(PlaybackState.Paused, 12.0, SampleTrack, 102.0));
        Assert.Equal(12.0, clock.CurrentPosition(107.0), 3);
    }

    [Fact]
    public void SmallDriftPreservesAnchorLargeDriftSnaps()
    {
        var clock = new PlaybackClock();
        clock.Sync(new PlaybackSnapshot(PlaybackState.Playing, 10.0, SampleTrack, 100.0));
        clock.Sync(new PlaybackSnapshot(PlaybackState.Playing, 12.15, SampleTrack, 102.0));
        Assert.Equal(12.0, clock.CurrentPosition(102.0), 3);

        clock.Sync(new PlaybackSnapshot(PlaybackState.Playing, 45.0, SampleTrack, 103.0));
        Assert.Equal(45.5, clock.CurrentPosition(103.5), 3);
    }
}
