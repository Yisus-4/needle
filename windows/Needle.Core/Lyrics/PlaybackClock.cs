using Needle.Core.Models;

namespace Needle.Core.Lyrics;

public sealed class PlaybackClock
{
    private const double DriftThresholdSeconds = 0.35;

    private double _basePosition;
    private double _anchorTime;
    private PlaybackState _state = PlaybackState.Stopped;
    private string? _trackId;

    public void Sync(PlaybackSnapshot snapshot)
    {
        bool sameTrack = snapshot.Track is not null && snapshot.Track.Id == _trackId;
        if (sameTrack && _state == PlaybackState.Playing && snapshot.State == PlaybackState.Playing)
        {
            double predicted = CurrentPosition(snapshot.SampledAtSeconds);
            if (Math.Abs(predicted - snapshot.PositionSeconds) <= DriftThresholdSeconds)
            {
                return;
            }
        }

        _basePosition = Math.Max(0.0, snapshot.PositionSeconds);
        _anchorTime = snapshot.SampledAtSeconds;
        _state = snapshot.State;
        _trackId = snapshot.Track?.Id;
    }

    public double CurrentPosition(double nowSeconds)
    {
        if (_state != PlaybackState.Playing) return _basePosition;
        return Math.Max(0.0, _basePosition + Math.Max(0.0, nowSeconds - _anchorTime));
    }
}
