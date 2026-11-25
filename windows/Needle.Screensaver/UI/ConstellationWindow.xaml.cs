using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Needle.Core.Lyrics;
using Needle.Core.Models;
using Needle.Core.Visuals;
using Needle.Screensaver.Native;
using Needle.Screensaver.Player;

namespace Needle.Screensaver.UI;

public partial class ConstellationWindow : Window
{
    private readonly bool _exitOnInput;
    private readonly nint _previewParentHwnd;
    private readonly System.Drawing.Rectangle? _targetPhysicalBounds;
    private readonly DateTime _openedAt = DateTime.UtcNow;
    private System.Windows.Point? _initialMousePos;

    private PlaybackSnapshot? _snapshot;
    private SyncedLyrics? _syncedLyrics;
    private AlbumPalette _palette = AlbumPalette.Fallback;
    private readonly PlaybackClock _clock = new();

    private string? _cachedTrackId;
    private int _cachedLineIndex = -1;
    private int _cachedRevealedCount = -1;
    private double _cachedWidth;
    private double _cachedHeight;
    private IReadOnlyList<ConstellationNode> _cachedNodes = [];

    public event Action? ExitRequested;

    public ConstellationWindow(
        bool exitOnInput,
        nint previewParentHwnd = 0,
        System.Drawing.Rectangle? targetPhysicalBounds = null)
    {
        InitializeComponent();
        _exitOnInput = exitOnInput;
        _previewParentHwnd = previewParentHwnd;
        _targetPhysicalBounds = targetPhysicalBounds;

        if (_previewParentHwnd != 0)
        {
            Topmost = false;
            ShowActivated = false;
        }

        if (_exitOnInput)
        {
            Cursor = System.Windows.Input.Cursors.None;
            KeyDown += (_, _) => RequestExit();
            MouseDown += (_, _) => RequestExit();
            MouseMove += OnScreensaverMouseMove;
        }

        SourceInitialized += OnSourceInitialized;
        Loaded += (_, _) => CompositionTarget.Rendering += OnRenderFrame;
        Closed += (_, _) => CompositionTarget.Rendering -= OnRenderFrame;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var helper = new WindowInteropHelper(this);
        nint hwnd = helper.Handle;

        if (_previewParentHwnd != 0)
        {
            int style = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_STYLE);
            style = (style & ~NativeMethods.WS_POPUP) | NativeMethods.WS_CHILD;
            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_STYLE, style);
            NativeMethods.SetParent(hwnd, _previewParentHwnd);

            if (NativeMethods.GetClientRect(_previewParentHwnd, out var rect))
            {
                int w = Math.Max(1, rect.Right - rect.Left);
                int h = Math.Max(1, rect.Bottom - rect.Top);
                NativeMethods.SetWindowPos(
                    hwnd,
                    nint.Zero,
                    0,
                    0,
                    w,
                    h,
                    NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_FRAMECHANGED);
            }
            return;
        }

        if (_targetPhysicalBounds is { } bounds)
        {
            // Position and size in physical screen pixels to avoid multi-monitor DPI drift
            NativeMethods.SetWindowPos(
                hwnd,
                nint.Zero,
                bounds.Left,
                bounds.Top,
                bounds.Width,
                bounds.Height,
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_FRAMECHANGED);
        }
    }

    private void OnScreensaverMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        // Ignore stray synthetic mouse moves in the first 400ms after launch
        if ((DateTime.UtcNow - _openedAt).TotalMilliseconds < 400) return;

        var pos = e.GetPosition(this);
        if (_initialMousePos is null)
        {
            _initialMousePos = pos;
            return;
        }

        double dx = pos.X - _initialMousePos.Value.X;
        double dy = pos.Y - _initialMousePos.Value.Y;
        if (dx * dx + dy * dy > 144.0) // > 12px deliberate movement
        {
            RequestExit();
        }
    }

    private void RequestExit()
    {
        ExitRequested?.Invoke();
    }

    public void UpdateState(PlaybackSnapshot snapshot, SyncedLyrics? lyrics, AlbumPalette palette, BitmapImage? artwork)
    {
        _snapshot = snapshot;
        _syncedLyrics = lyrics;
        _palette = palette;
        _clock.Sync(snapshot);

        BackdropStop1.Color = ToWpfColor(palette.BackdropPrimary);
        BackdropStop2.Color = ToWpfColor(palette.BackdropSecondary);

        if (artwork is not null)
        {
            ArtworkImage.Source = artwork;
            ArtworkImage.Opacity = 1.0;
        }
        else
        {
            ArtworkImage.Source = null;
            ArtworkImage.Opacity = 0.0;
        }

        if (snapshot.Track is not null)
        {
            TrackCaption.Text = $"{snapshot.Track.Name}  ·  {snapshot.Track.Artist}";
            FallbackTitle.Text = snapshot.Track.Name;
            FallbackTitle.Foreground = new SolidColorBrush(ToWpfColor(palette.Accent));
            FallbackArtist.Text = snapshot.Track.Artist;
        }
        else
        {
            TrackCaption.Text = string.Empty;
            FallbackTitle.Text = "Needle";
            FallbackTitle.Foreground = new SolidColorBrush(ToWpfColor(AlbumPalette.Fallback.Accent));
            FallbackArtist.Text = "Reproduce una canción en Spotify para ver las constelaciones";
        }

        // Force visual refresh on state update
        _cachedRevealedCount = -1;
    }

    private void OnRenderFrame(object? sender, EventArgs e)
    {
        double width = StarsCanvas.ActualWidth;
        double height = StarsCanvas.ActualHeight;
        if (width < 40 || height < 40) return;

        bool hasLyrics = _syncedLyrics is not null && _snapshot?.State == PlaybackState.Playing;
        if (!hasLyrics)
        {
            StarsCanvas.Children.Clear();
            FallbackPanel.Visibility = Visibility.Visible;
            TrackCaption.Visibility = Visibility.Collapsed;
            _cachedLineIndex = -1;
            _cachedRevealedCount = -1;
            return;
        }

        FallbackPanel.Visibility = Visibility.Collapsed;
        TrackCaption.Visibility = Visibility.Visible;

        double now = _clock.CurrentPosition(SmtcSpotifyProvider.CurrentUptimeSeconds());
        var active = _syncedLyrics!.ActiveLine(now);
        if (active is null)
        {
            if (StarsCanvas.Children.Count > 0)
            {
                StarsCanvas.Children.Clear();
                _cachedLineIndex = -1;
                _cachedRevealedCount = -1;
            }
            return;
        }

        string trackId = _snapshot?.Track?.Id ?? string.Empty;
        bool layoutChanged = trackId != _cachedTrackId ||
                             active.Value.Index != _cachedLineIndex ||
                             Math.Abs(width - _cachedWidth) > 1.0 ||
                             Math.Abs(height - _cachedHeight) > 1.0;

        if (layoutChanged)
        {
            ulong trackHash = ComputeStableHash(trackId);
            ulong seed = trackHash ^ ((ulong)(active.Value.Index + 1) * 0x9E3779B97F4A7C15UL);
            _cachedNodes = ConstellationLayout.Generate(active.Value.Line, seed, width, height);
            _cachedTrackId = trackId;
            _cachedLineIndex = active.Value.Index;
            _cachedWidth = width;
            _cachedHeight = height;
            _cachedRevealedCount = -1;
        }

        int revealed = Math.Max(1, _cachedNodes.Count(n => now >= n.StartTime));
        if (revealed == _cachedRevealedCount) return;
        _cachedRevealedCount = revealed;

        DrawConstellation(revealed, width, height);
    }

    private void DrawConstellation(int revealedCount, double width, double height)
    {
        StarsCanvas.Children.Clear();
        int count = Math.Min(revealedCount, _cachedNodes.Count);
        if (count == 0) return;

        int activeIdx = count - 1;
        var accent = ToWpfColor(_palette.Accent);
        double previewScale = width < 400 ? Math.Max(0.32, width / 1100.0) : 1.0;

        // 1. Connecting lines
        for (int i = 1; i < count; i++)
        {
            var prev = _cachedNodes[i - 1];
            var curr = _cachedNodes[i];
            bool isNewest = i == activeIdx;

            var line = new Line
            {
                X1 = prev.X * width,
                Y1 = prev.Y * height,
                X2 = curr.X * width,
                Y2 = curr.Y * height,
                Stroke = new SolidColorBrush(System.Windows.Media.Color.FromArgb(
                    (byte)(isNewest ? 170 : 95), accent.R, accent.G, accent.B)),
                StrokeThickness = (isNewest ? 1.3 : 0.9) * previewScale,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round
            };
            StarsCanvas.Children.Add(line);
        }

        // 2. 4-point sparkle stars, active halo ring, and variable-size word labels
        for (int i = 0; i < count; i++)
        {
            var node = _cachedNodes[i];
            bool isActive = i == activeIdx;
            double cx = node.X * width;
            double cy = node.Y * height;

            double starR = (isActive ? 11.0 : 5.0) * previewScale;
            var star = BuildFourPointStar(cx, cy, starR, starR * 0.22);
            star.Fill = new SolidColorBrush(System.Windows.Media.Color.FromArgb(
                (byte)(isActive ? 250 : 185), 255, 255, 255));
            StarsCanvas.Children.Add(star);

            if (isActive)
            {
                double ringR = 19.0 * previewScale;
                var ring = new Ellipse
                {
                    Width = ringR * 2,
                    Height = ringR * 2,
                    Stroke = new SolidColorBrush(System.Windows.Media.Color.FromArgb(170, accent.R, accent.G, accent.B)),
                    StrokeThickness = 1.0 * previewScale
                };
                Canvas.SetLeft(ring, cx - ringR);
                Canvas.SetTop(ring, cy - ringR);
                StarsCanvas.Children.Add(ring);
            }

            double fontSize = isActive
                ? Math.Clamp(node.BaseFontSize * 1.42, 26.0, ConstellationLayout.MaxFontSize) * previewScale
                : node.BaseFontSize * previewScale;

            var label = new TextBlock
            {
                Text = node.Text,
                FontFamily = new System.Windows.Media.FontFamily("Segoe UI Variable Display, Segoe UI"),
                FontSize = Math.Max(7.0, fontSize),
                FontWeight = isActive ? FontWeights.Bold : FontWeights.Medium,
                Foreground = new SolidColorBrush(isActive
                    ? accent
                    : System.Windows.Media.Color.FromArgb(196, 255, 255, 255)),
                Effect = new DropShadowEffect
                {
                    Color = isActive ? accent : Colors.Black,
                    BlurRadius = isActive ? 14 : 5,
                    ShadowDepth = 1,
                    Opacity = isActive ? 0.6 : 0.7
                }
            };

            label.Measure(new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity));
            double labelOffsetY = (isActive ? ConstellationLayout.ActiveLabelOffsetY : ConstellationLayout.InactiveLabelOffsetY) * previewScale;
            Canvas.SetLeft(label, cx - label.DesiredSize.Width / 2.0);
            Canvas.SetTop(label, cy + labelOffsetY - label.DesiredSize.Height / 2.0);
            StarsCanvas.Children.Add(label);
        }
    }

    private static Polygon BuildFourPointStar(double cx, double cy, double outerR, double innerR)
    {
        var pts = new PointCollection(8);
        for (int i = 0; i < 8; i++)
        {
            double angle = i * (Math.PI / 4.0) - (Math.PI / 2.0);
            double r = (i % 2 == 0) ? outerR : innerR;
            pts.Add(new System.Windows.Point(cx + Math.Cos(angle) * r, cy + Math.Sin(angle) * r));
        }
        return new Polygon { Points = pts };
    }

    private static System.Windows.Media.Color ToWpfColor(RgbColor c) =>
        System.Windows.Media.Color.FromRgb(c.ByteR, c.ByteG, c.ByteB);

    private static ulong ComputeStableHash(string text)
    {
        ulong hash = 14695981039346656037UL;
        foreach (char ch in text)
        {
            hash ^= ch;
            hash *= 1099511628211UL;
        }
        return hash;
    }

    public static (BitmapImage? Image, AlbumPalette Palette) DecodeArtworkAndPalette(byte[]? bytes)
    {
        if (bytes is null || bytes.Length == 0)
            return (null, AlbumPalette.Fallback);

        try
        {
            using var ms = new MemoryStream(bytes);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = ms;
            bitmap.EndInit();
            bitmap.Freeze();

            const int sampleSize = 32;
            var scaled = new TransformedBitmap(
                bitmap,
                new ScaleTransform(sampleSize / (double)bitmap.PixelWidth, sampleSize / (double)bitmap.PixelHeight));
            var converted = new FormatConvertedBitmap(scaled, PixelFormats.Bgra32, null, 0);

            int stride = converted.PixelWidth * 4;
            byte[] bgra = new byte[stride * converted.PixelHeight];
            converted.CopyPixels(bgra, stride, 0);

            // Convert BGRA -> RGBA for PaletteExtractor
            for (int i = 0; i < bgra.Length; i += 4)
            {
                (bgra[i], bgra[i + 2]) = (bgra[i + 2], bgra[i]);
            }

            var palette = PaletteExtractor.ExtractFromRgba(bgra, converted.PixelWidth, converted.PixelHeight);
            return (bitmap, palette);
        }
        catch
        {
            return (null, AlbumPalette.Fallback);
        }
    }
}
