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
    private const double WordRevealDuration = 0.28;
    private const double WordSettleDuration = 0.28;
    private const double LineFadeOutDuration = 0.30;

    private sealed class NodeVisual
    {
        public required ConstellationNode Node { get; init; }
        public required double CenterX { get; init; }
        public required double CenterY { get; init; }
        public required double PrevX { get; init; }
        public required double PrevY { get; init; }
        public required double InactiveScale { get; init; }
        public required double LabelHalfHeight { get; init; }
        public required double ActiveOffsetY { get; init; }
        public required double InactiveOffsetY { get; init; }

        public Line? IncomingLine { get; init; }
        public SolidColorBrush? LineBrush { get; init; }
        public required Polygon Star { get; init; }
        public required ScaleTransform StarScale { get; init; }
        public required Ellipse HaloRing { get; init; }
        public required ScaleTransform HaloScale { get; init; }
        public required TextBlock Label { get; init; }
        public required ScaleTransform LabelScale { get; init; }
        public required SolidColorBrush LabelBrush { get; init; }
        public required DropShadowEffect LabelShadow { get; init; }
    }

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
    private double _cachedWidth;
    private double _cachedHeight;
    private AlbumPalette _cachedPalette = AlbumPalette.Fallback;
    private readonly List<NodeVisual> _nodeVisuals = [];

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
    }

    private void OnRenderFrame(object? sender, EventArgs e)
    {
        double width = StarsCanvas.ActualWidth;
        double height = StarsCanvas.ActualHeight;
        if (width < 40 || height < 40) return;

        bool hasLyrics = _syncedLyrics is not null && _snapshot?.State == PlaybackState.Playing;
        if (!hasLyrics)
        {
            ClearLineVisuals();
            FallbackPanel.Visibility = Visibility.Visible;
            TrackCaption.Visibility = Visibility.Collapsed;
            return;
        }

        FallbackPanel.Visibility = Visibility.Collapsed;
        TrackCaption.Visibility = Visibility.Visible;

        double now = _clock.CurrentPosition(SmtcSpotifyProvider.CurrentUptimeSeconds());
        var active = _syncedLyrics!.ActiveLine(now);
        if (active is null)
        {
            ClearLineVisuals();
            return;
        }

        string trackId = _snapshot?.Track?.Id ?? string.Empty;
        bool layoutChanged = trackId != _cachedTrackId ||
                             active.Value.Index != _cachedLineIndex ||
                             Math.Abs(width - _cachedWidth) > 1.0 ||
                             Math.Abs(height - _cachedHeight) > 1.0 ||
                             _palette != _cachedPalette;

        if (layoutChanged)
        {
            ulong trackHash = ComputeStableHash(trackId);
            ulong seed = trackHash ^ ((ulong)(active.Value.Index + 1) * 0x9E3779B97F4A7C15UL);
            var nodes = ConstellationLayout.Generate(active.Value.Line, seed, width, height);
            RebuildLineVisuals(nodes, width, height);
            _cachedTrackId = trackId;
            _cachedLineIndex = active.Value.Index;
            _cachedWidth = width;
            _cachedHeight = height;
            _cachedPalette = _palette;
        }

        AnimateConstellation(active.Value.Line, now);
    }

    private void ClearLineVisuals()
    {
        if (_nodeVisuals.Count > 0 || StarsCanvas.Children.Count > 0)
        {
            StarsCanvas.Children.Clear();
            _nodeVisuals.Clear();
            _cachedLineIndex = -1;
        }
        StarsCanvas.Opacity = 1.0;
    }

    private void RebuildLineVisuals(IReadOnlyList<ConstellationNode> nodes, double width, double height)
    {
        StarsCanvas.Children.Clear();
        _nodeVisuals.Clear();
        if (nodes.Count == 0) return;

        var accent = ToWpfColor(_palette.Accent);
        double previewScale = width < 400 ? Math.Max(0.32, width / 1100.0) : 1.0;

        // First pass: create connecting lines behind stars & labels
        var lines = new (Line? Line, SolidColorBrush? Brush)[nodes.Count];
        for (int i = 1; i < nodes.Count; i++)
        {
            var prev = nodes[i - 1];
            double px = prev.X * width;
            double py = prev.Y * height;
            var lineBrush = new SolidColorBrush(accent);
            var line = new Line
            {
                X1 = px,
                Y1 = py,
                X2 = px,
                Y2 = py,
                Stroke = lineBrush,
                StrokeThickness = 1.15 * previewScale,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                Opacity = 0.0
            };
            StarsCanvas.Children.Add(line);
            lines[i] = (line, lineBrush);
        }

        // Second pass: create stars, halo rings, and word labels (all reused smoothly every frame)
        for (int i = 0; i < nodes.Count; i++)
        {
            var node = nodes[i];
            double cx = node.X * width;
            double cy = node.Y * height;
            double prevX = i > 0 ? nodes[i - 1].X * width : cx;
            double prevY = i > 0 ? nodes[i - 1].Y * height : cy;

            double starR = 11.0 * previewScale;
            var starScale = new ScaleTransform(0.5, 0.5, cx, cy);
            var star = BuildFourPointStar(cx, cy, starR, starR * 0.22);
            star.Fill = new SolidColorBrush(Colors.White);
            star.RenderTransform = starScale;
            star.Opacity = 0.0;
            StarsCanvas.Children.Add(star);

            double ringR = 19.0 * previewScale;
            var haloScale = new ScaleTransform(0.8, 0.8, ringR, ringR);
            var halo = new Ellipse
            {
                Width = ringR * 2,
                Height = ringR * 2,
                Stroke = new SolidColorBrush(accent),
                StrokeThickness = 1.0 * previewScale,
                RenderTransform = haloScale,
                Opacity = 0.0
            };
            Canvas.SetLeft(halo, cx - ringR);
            Canvas.SetTop(halo, cy - ringR);
            StarsCanvas.Children.Add(halo);

            double activeFontSize = Math.Clamp(node.BaseFontSize * 1.42, 26.0, ConstellationLayout.MaxFontSize) * previewScale;
            double inactiveFontSize = node.BaseFontSize * previewScale;
            double inactiveScale = activeFontSize > 0.01 ? inactiveFontSize / activeFontSize : 0.75;

            var labelBrush = new SolidColorBrush(accent);
            var labelShadow = new DropShadowEffect
            {
                Color = accent,
                BlurRadius = 14,
                ShadowDepth = 1,
                Opacity = 0.6
            };
            var labelScale = new ScaleTransform(0.85, 0.85);
            var label = new TextBlock
            {
                Text = node.Text,
                FontFamily = new System.Windows.Media.FontFamily("Segoe UI Variable Display, Segoe UI"),
                FontSize = Math.Max(7.0, activeFontSize),
                FontWeight = FontWeights.Bold,
                Foreground = labelBrush,
                Effect = labelShadow,
                RenderTransformOrigin = new System.Windows.Point(0.5, 0.5),
                RenderTransform = labelScale,
                Opacity = 0.0
            };

            label.Measure(new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity));
            double halfW = label.DesiredSize.Width / 2.0;
            double halfH = label.DesiredSize.Height / 2.0;
            double activeOffsetY = ConstellationLayout.ActiveLabelOffsetY * previewScale;
            double inactiveOffsetY = ConstellationLayout.InactiveLabelOffsetY * previewScale;

            Canvas.SetLeft(label, cx - halfW);
            Canvas.SetTop(label, cy + activeOffsetY - halfH);
            StarsCanvas.Children.Add(label);

            _nodeVisuals.Add(new NodeVisual
            {
                Node = node,
                CenterX = cx,
                CenterY = cy,
                PrevX = prevX,
                PrevY = prevY,
                InactiveScale = inactiveScale,
                LabelHalfHeight = halfH,
                ActiveOffsetY = activeOffsetY,
                InactiveOffsetY = inactiveOffsetY,
                IncomingLine = lines[i].Line,
                LineBrush = lines[i].Brush,
                Star = star,
                StarScale = starScale,
                HaloRing = halo,
                HaloScale = haloScale,
                Label = label,
                LabelScale = labelScale,
                LabelBrush = labelBrush,
                LabelShadow = labelShadow
            });
        }
    }

    private void AnimateConstellation(LyricLine line, double now)
    {
        // Smooth fade-out during the final 300ms of the lyric line
        double remaining = line.EndTime - now;
        double lineOpacity = remaining < LineFadeOutDuration
            ? EaseOutCubic(Math.Clamp(remaining / LineFadeOutDuration, 0.0, 1.0))
            : 1.0;
        StarsCanvas.Opacity = lineOpacity;

        var accent = ToWpfColor(_palette.Accent);
        int count = _nodeVisuals.Count;

        for (int i = 0; i < count; i++)
        {
            var nv = _nodeVisuals[i];
            // First word always begins fading in right as the line starts
            double start = i == 0 ? Math.Min(nv.Node.StartTime, line.StartTime) : nv.Node.StartTime;
            double rawReveal = Math.Clamp((now - start) / WordRevealDuration, 0.0, 1.0);
            if (rawReveal <= 0.001)
            {
                if (nv.IncomingLine is not null) nv.IncomingLine.Opacity = 0.0;
                nv.Star.Opacity = 0.0;
                nv.HaloRing.Opacity = 0.0;
                nv.Label.Opacity = 0.0;
                continue;
            }

            double reveal = EaseOutCubic(rawReveal);

            // Smoothly transition from active -> settled once the next word starts
            double nextStart = (i + 1 < count) ? _nodeVisuals[i + 1].Node.StartTime : double.PositiveInfinity;
            double settle = double.IsInfinity(nextStart)
                ? 0.0
                : EaseOutCubic(Math.Clamp((now - nextStart) / WordSettleDuration, 0.0, 1.0));
            double activeWeight = 1.0 - settle;

            // 1. Connecting line draws smoothly from previous star to current star
            if (nv.IncomingLine is not null)
            {
                nv.IncomingLine.X2 = Lerp(nv.PrevX, nv.CenterX, reveal);
                nv.IncomingLine.Y2 = Lerp(nv.PrevY, nv.CenterY, reveal);
                nv.IncomingLine.Opacity = reveal * Lerp(0.36, 0.68, activeWeight);
            }

            // 2. 4-point star scales in softly and relaxes to subtle size when settled
            double starScaleVal = Lerp(0.46, 1.0, activeWeight) * Lerp(0.55, 1.0, reveal);
            nv.StarScale.ScaleX = starScaleVal;
            nv.StarScale.ScaleY = starScaleVal;
            nv.Star.Opacity = reveal * Lerp(0.72, 0.98, activeWeight);

            // 3. Target halo ring blooms in while active and fades smoothly when moving on
            double haloScaleVal = Lerp(0.75, 1.0, reveal) * Lerp(1.18, 1.0, activeWeight);
            nv.HaloScale.ScaleX = haloScaleVal;
            nv.HaloScale.ScaleY = haloScaleVal;
            nv.HaloRing.Opacity = reveal * activeWeight * 0.68;

            // 4. Word fades in, scales up smoothly, and settles into readable white
            double targetLabelScale = Lerp(nv.InactiveScale, 1.0, activeWeight);
            double currentLabelScale = targetLabelScale * Lerp(0.86, 1.0, reveal);
            nv.LabelScale.ScaleX = currentLabelScale;
            nv.LabelScale.ScaleY = currentLabelScale;
            nv.Label.Opacity = reveal * Lerp(0.76, 1.0, activeWeight);

            nv.LabelBrush.Color = LerpColor(
                System.Windows.Media.Color.FromRgb(255, 255, 255),
                accent,
                activeWeight);
            nv.LabelShadow.Opacity = Lerp(0.45, 0.62, activeWeight);
            nv.LabelShadow.BlurRadius = Lerp(5.0, 14.0, activeWeight);

            double yOffset = Lerp(nv.InactiveOffsetY, nv.ActiveOffsetY, activeWeight);
            Canvas.SetTop(nv.Label, nv.CenterY + yOffset - nv.LabelHalfHeight);
        }
    }

    private static double EaseOutCubic(double t)
    {
        double inv = 1.0 - t;
        return 1.0 - inv * inv * inv;
    }

    private static double Lerp(double a, double b, double t) => a + (b - a) * t;

    private static System.Windows.Media.Color LerpColor(System.Windows.Media.Color a, System.Windows.Media.Color b, double t) =>
        System.Windows.Media.Color.FromRgb(
            (byte)Math.Round(Lerp(a.R, b.R, t)),
            (byte)Math.Round(Lerp(a.G, b.G, t)),
            (byte)Math.Round(Lerp(a.B, b.B, t)));

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
