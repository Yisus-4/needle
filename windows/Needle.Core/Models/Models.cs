namespace Needle.Core.Models;

public enum PlaybackState
{
    Playing,
    Paused,
    Stopped
}

public sealed record TrackInfo(
    string Id,
    string Name,
    string Artist,
    string Album,
    double DurationSeconds
);

public sealed record PlaybackSnapshot(
    PlaybackState State,
    double PositionSeconds,
    TrackInfo? Track,
    double SampledAtSeconds,
    byte[]? ArtworkBytes = null
)
{
    public static PlaybackSnapshot Stopped(double sampledAtSeconds) =>
        new(PlaybackState.Stopped, 0, null, sampledAtSeconds, null);
}

public sealed record WordTiming(
    string Text,
    double StartTime,
    double EndTime
);

public sealed record LyricLine(
    double StartTime,
    double EndTime,
    string Text,
    IReadOnlyList<WordTiming> Words
);

public sealed record SyncedLyrics(IReadOnlyList<LyricLine> Lines)
{
    public (int Index, LyricLine Line)? ActiveLine(double timeSeconds)
    {
        for (int i = 0; i < Lines.Count; i++)
        {
            var line = Lines[i];
            if (timeSeconds >= line.StartTime && timeSeconds < line.EndTime)
            {
                return (i, line);
            }
        }
        return null;
    }
}

public readonly record struct RgbColor(double R, double G, double B)
{
    public double ClampedR => Math.Clamp(R, 0.0, 1.0);
    public double ClampedG => Math.Clamp(G, 0.0, 1.0);
    public double ClampedB => Math.Clamp(B, 0.0, 1.0);

    public byte ByteR => (byte)Math.Round(ClampedR * 255.0);
    public byte ByteG => (byte)Math.Round(ClampedG * 255.0);
    public byte ByteB => (byte)Math.Round(ClampedB * 255.0);

    public double RelativeLuminance
    {
        get
        {
            static double Linear(double c) => c <= 0.03928 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
            return 0.2126 * Linear(ClampedR) + 0.7152 * Linear(ClampedG) + 0.0722 * Linear(ClampedB);
        }
    }

    public (double H, double S, double B) ToHsb()
    {
        double r = ClampedR, g = ClampedG, b = ClampedB;
        double maxC = Math.Max(r, Math.Max(g, b));
        double minC = Math.Min(r, Math.Min(g, b));
        double delta = maxC - minC;

        double hue = 0.0;
        if (delta > 0.0001)
        {
            if (Math.Abs(maxC - r) < 0.00001)
                hue = ((g - b) / delta) % 6.0;
            else if (Math.Abs(maxC - g) < 0.00001)
                hue = (b - r) / delta + 2.0;
            else
                hue = (r - g) / delta + 4.0;

            hue /= 6.0;
            if (hue < 0) hue += 1.0;
        }
        double sat = maxC > 0.0001 ? delta / maxC : 0.0;
        return (hue, sat, maxC);
    }

    public static RgbColor FromHsb(double h, double s, double b)
    {
        double hh = ((h % 1.0) + 1.0) % 1.0;
        double ss = Math.Clamp(s, 0.0, 1.0);
        double bb = Math.Clamp(b, 0.0, 1.0);

        double c = bb * ss;
        double x = c * (1.0 - Math.Abs((hh * 6.0) % 2.0 - 1.0));
        double m = bb - c;

        double sector = hh * 6.0;
        (double r1, double g1, double b1) = sector switch
        {
            < 1.0 => (c, x, 0.0),
            < 2.0 => (x, c, 0.0),
            < 3.0 => (0.0, c, x),
            < 4.0 => (0.0, x, c),
            < 5.0 => (x, 0.0, c),
            _ => (c, 0.0, x)
        };
        return new RgbColor(r1 + m, g1 + m, b1 + m);
    }
}

public sealed record AlbumPalette(
    RgbColor BackdropPrimary,
    RgbColor BackdropSecondary,
    RgbColor Accent
)
{
    public static AlbumPalette Fallback { get; } = new(
        new RgbColor(0.05, 0.07, 0.14),
        new RgbColor(0.03, 0.04, 0.09),
        new RgbColor(0.62, 0.78, 1.0)
    );
}
