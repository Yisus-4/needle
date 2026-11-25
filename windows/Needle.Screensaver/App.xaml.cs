using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Needle.Core;
using Needle.Core.Lyrics;
using Needle.Core.Models;
using Needle.Screensaver.Player;
using Needle.Screensaver.UI;

namespace Needle.Screensaver;

public partial class App : System.Windows.Application
{
    private readonly SmtcSpotifyProvider _spotify = new();
    private readonly LrclibClient _lrclib = new();
    private readonly List<ConstellationWindow> _windows = [];
    private readonly DispatcherTimer _pollTimer = new() { Interval = TimeSpan.FromSeconds(2.5) };

    private CancellationTokenSource? _trackCts;
    private string? _loadedTrackId;
    private PlaybackSnapshot? _latestSnapshot;
    private SyncedLyrics? _currentLyrics;
    private AlbumPalette _currentPalette = AlbumPalette.Fallback;
    private BitmapImage? _currentArtwork;
    private long _refreshGeneration;
    private bool _isExiting;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var command = ScreensaverArgs.Parse(e.Args);

        switch (command.Mode)
        {
            case ScreensaverMode.Configure:
                ShowConfigWindow();
                return;

            case ScreensaverMode.Preview:
                if (command.PreviewHandle == 0)
                {
                    Shutdown();
                    return;
                }
                await StartScreensaverAsync(previewHandle: command.PreviewHandle);
                return;

            case ScreensaverMode.FullScreen:
            default:
                await StartScreensaverAsync(previewHandle: 0);
                return;
        }
    }

    private void ShowConfigWindow()
    {
        var config = new ConfigWindow();
        config.PreviewRequested += async () =>
        {
            config.Hide();
            await StartScreensaverAsync(previewHandle: 0);
        };
        config.Closed += (_, _) =>
        {
            if (_windows.Count == 0 && !_isExiting) Shutdown();
        };
        config.Show();
    }

    private async Task StartScreensaverAsync(nint previewHandle)
    {
        if (previewHandle != 0)
        {
            var previewWin = new ConstellationWindow(exitOnInput: false, previewParentHwnd: previewHandle);
            previewWin.Closed += (_, _) => ExitAll();
            _windows.Add(previewWin);
            previewWin.Show();
        }
        else
        {
            foreach (var screen in System.Windows.Forms.Screen.AllScreens)
            {
                var win = new ConstellationWindow(exitOnInput: true, targetPhysicalBounds: screen.Bounds);
                win.WindowStartupLocation = WindowStartupLocation.Manual;
                win.WindowState = WindowState.Normal;
                win.ExitRequested += ExitAll;
                _windows.Add(win);
                win.Show();
            }
        }

        await _spotify.InitializeAsync();
        if (_isExiting) return;

        _spotify.PlaybackChanged += () => Dispatcher.InvokeAsync(async () => await RefreshPlaybackAsync());
        _pollTimer.Tick += async (_, _) => await RefreshPlaybackAsync();
        _pollTimer.Start();

        await RefreshPlaybackAsync();
    }

    private async Task RefreshPlaybackAsync()
    {
        if (_isExiting) return;
        long gen = Interlocked.Increment(ref _refreshGeneration);
        var snapshot = await _spotify.FetchSnapshotAsync();
        if (_isExiting || gen != Interlocked.Read(ref _refreshGeneration)) return;

        _latestSnapshot = snapshot;

        if (snapshot.Track is not null && snapshot.Track.Id != _loadedTrackId)
        {
            _loadedTrackId = snapshot.Track.Id;
            _currentLyrics = null;
            var (img, pal) = ConstellationWindow.DecodeArtworkAndPalette(snapshot.ArtworkBytes);
            _currentArtwork = img;
            _currentPalette = pal;

            BroadcastState(snapshot);
            FetchLyricsForTrack(snapshot.Track);
            return;
        }

        if (snapshot.Track is null)
        {
            _loadedTrackId = null;
            _currentLyrics = null;
            _currentArtwork = null;
            _currentPalette = AlbumPalette.Fallback;
        }

        BroadcastState(snapshot);
    }

    private void FetchLyricsForTrack(TrackInfo track)
    {
        _trackCts?.Cancel();
        _trackCts?.Dispose();
        _trackCts = new CancellationTokenSource();
        var ct = _trackCts.Token;

        _ = Task.Run(async () =>
        {
            var lyrics = await _lrclib.FetchLyricsAsync(track, ct).ConfigureAwait(false);
            if (ct.IsCancellationRequested) return;
            await Dispatcher.InvokeAsync(() =>
            {
                if (_isExiting || _loadedTrackId != track.Id) return;
                _currentLyrics = lyrics;
                if (_latestSnapshot is { } latest && latest.Track?.Id == track.Id)
                {
                    BroadcastState(latest);
                }
            });
        }, ct);
    }

    private void BroadcastState(PlaybackSnapshot snapshot)
    {
        foreach (var win in _windows)
        {
            win.UpdateState(snapshot, _currentLyrics, _currentPalette, _currentArtwork);
        }
    }

    private void ExitAll()
    {
        if (_isExiting) return;
        _isExiting = true;
        _pollTimer.Stop();
        _trackCts?.Cancel();
        _trackCts?.Dispose();
        _spotify.Dispose();
        foreach (var win in _windows.ToList())
        {
            win.Close();
        }
        _windows.Clear();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _isExiting = true;
        _pollTimer.Stop();
        _trackCts?.Cancel();
        _trackCts?.Dispose();
        _spotify.Dispose();
        base.OnExit(e);
    }
}
