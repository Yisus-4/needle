using System.Diagnostics;
using System.IO;
using Needle.Core.Models;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace Needle.Screensaver.Player;

public sealed class SmtcSpotifyProvider : IDisposable
{
    private static readonly Stopwatch Uptime = Stopwatch.StartNew();
    private readonly object _sync = new();
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _currentSession;
    private string? _lastArtworkTrackId;
    private byte[]? _lastArtworkBytes;
    private bool _disposed;

    public event Action? PlaybackChanged;

    public static double CurrentUptimeSeconds() => Uptime.Elapsed.TotalSeconds;

    public async Task InitializeAsync()
    {
        try
        {
            var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            lock (_sync)
            {
                if (_disposed) return;
                _manager = manager;
                _manager.SessionsChanged += OnSessionsChanged;
            }
            AttachSpotifySession();
        }
        catch
        {
            // SMTC unavailable
        }
    }

    private void OnSessionsChanged(GlobalSystemMediaTransportControlsSessionManager sender, SessionsChangedEventArgs args)
    {
        AttachSpotifySession();
        PlaybackChanged?.Invoke();
    }

    private void AttachSpotifySession()
    {
        lock (_sync)
        {
            if (_disposed || _manager is null) return;

            var spotify = _manager.GetSessions()
                .FirstOrDefault(s => s.SourceAppUserModelId?.Contains("spotify", StringComparison.OrdinalIgnoreCase) == true);

            if (ReferenceEquals(spotify, _currentSession)) return;

            if (_currentSession is not null)
            {
                _currentSession.MediaPropertiesChanged -= OnSessionChanged;
                _currentSession.PlaybackInfoChanged -= OnSessionChanged;
                _currentSession.TimelinePropertiesChanged -= OnSessionChanged;
            }

            _currentSession = spotify;

            if (_currentSession is not null)
            {
                _currentSession.MediaPropertiesChanged += OnSessionChanged;
                _currentSession.PlaybackInfoChanged += OnSessionChanged;
                _currentSession.TimelinePropertiesChanged += OnSessionChanged;
            }
        }
    }

    private void OnSessionChanged(GlobalSystemMediaTransportControlsSession sender, object args)
    {
        PlaybackChanged?.Invoke();
    }

    public async Task<PlaybackSnapshot> FetchSnapshotAsync()
    {
        double now = CurrentUptimeSeconds();
        GlobalSystemMediaTransportControlsSession? session;
        lock (_sync)
        {
            if (_disposed) return PlaybackSnapshot.Stopped(now);
            session = _currentSession;
        }

        if (session is null)
        {
            AttachSpotifySession();
            lock (_sync) { session = _currentSession; }
        }

        if (session is null)
        {
            return PlaybackSnapshot.Stopped(now);
        }

        try
        {
            var info = session.GetPlaybackInfo();
            if (info is null) return PlaybackSnapshot.Stopped(now);

            var state = info.PlaybackStatus switch
            {
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing => PlaybackState.Playing,
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused => PlaybackState.Paused,
                _ => PlaybackState.Stopped
            };

            var props = await session.TryGetMediaPropertiesAsync();
            if (props is null || string.IsNullOrWhiteSpace(props.Title))
            {
                return PlaybackSnapshot.Stopped(now);
            }

            var timeline = session.GetTimelineProperties();
            double duration = timeline is not null ? Math.Max(0.0, timeline.EndTime.TotalSeconds) : 0.0;
            double position = timeline is not null ? Math.Max(0.0, timeline.Position.TotalSeconds) : 0.0;

            if (state == PlaybackState.Playing && timeline is not null && timeline.LastUpdatedTime > DateTimeOffset.MinValue)
            {
                double elapsed = (DateTimeOffset.UtcNow - timeline.LastUpdatedTime).TotalSeconds;
                if (elapsed is > 0 and < 600)
                {
                    position += elapsed;
                }
            }
            if (duration > 0)
            {
                position = Math.Min(position, duration);
            }

            string trackId = $"{props.Artist}::{props.Title}::{props.AlbumTitle}";
            byte[]? artwork = null;
            bool cacheHit = false;
            lock (_sync)
            {
                if (trackId == _lastArtworkTrackId)
                {
                    artwork = _lastArtworkBytes;
                    cacheHit = _lastArtworkBytes is not null;
                }
            }

            if (!cacheHit && props.Thumbnail is not null)
            {
                artwork = await ReadThumbnailBytesAsync(props.Thumbnail).ConfigureAwait(false);
                lock (_sync)
                {
                    _lastArtworkTrackId = trackId;
                    _lastArtworkBytes = artwork;
                }
            }

            var track = new TrackInfo(
                Id: trackId,
                Name: props.Title,
                Artist: props.Artist ?? string.Empty,
                Album: props.AlbumTitle ?? string.Empty,
                DurationSeconds: duration
            );

            return new PlaybackSnapshot(state, position, track, CurrentUptimeSeconds(), artwork);
        }
        catch
        {
            return PlaybackSnapshot.Stopped(now);
        }
    }

    private static async Task<byte[]?> ReadThumbnailBytesAsync(IRandomAccessStreamReference thumbnail)
    {
        try
        {
            using var stream = await thumbnail.OpenReadAsync();
            using var netStream = stream.AsStreamForRead();
            using var ms = new MemoryStream();
            await netStream.CopyToAsync(ms).ConfigureAwait(false);
            return ms.Length > 0 ? ms.ToArray() : null;
        }
        catch
        {
            return null;
        }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            if (_manager is not null)
            {
                _manager.SessionsChanged -= OnSessionsChanged;
                _manager = null;
            }
            if (_currentSession is not null)
            {
                _currentSession.MediaPropertiesChanged -= OnSessionChanged;
                _currentSession.PlaybackInfoChanged -= OnSessionChanged;
                _currentSession.TimelinePropertiesChanged -= OnSessionChanged;
                _currentSession = null;
            }
        }
    }
}
