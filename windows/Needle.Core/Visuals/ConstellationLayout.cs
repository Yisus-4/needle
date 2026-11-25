using Needle.Core.Models;

namespace Needle.Core.Visuals;

public sealed record ConstellationNode(
    int Id,
    string Text,
    double X,
    double Y,
    double BaseFontSize,
    double StartTime,
    double EndTime
);

public static class ConstellationLayout
{
    public const double SafeMinX = 0.08;
    public const double SafeMaxX = 0.92;
    public const double SafeMinY = 0.20;
    public const double SafeMaxY = 0.78;
    public const double MinFontSize = 15.0;
    public const double MaxFontSize = 34.0;
    public const double ActiveLabelOffsetY = 32.0;
    public const double InactiveLabelOffsetY = 18.0;

    private struct SplitMix64(ulong seed)
    {
        private ulong _state = seed == 0 ? 0x9E3779B97F4A7C15UL : seed;

        public ulong Next()
        {
            _state += 0x9E3779B97F4A7C15UL;
            ulong z = _state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }

        public double NextUnit() => (Next() >> 11) / (double)(1UL << 53);
    }

    private readonly record struct Box(double MinX, double MaxX, double MinY, double MaxY)
    {
        public bool Intersects(Box other) =>
            MinX < other.MaxX && MaxX > other.MinX && MinY < other.MaxY && MaxY > other.MinY;
    }

    public static IReadOnlyList<ConstellationNode> Generate(
        LyricLine line,
        ulong seed,
        double canvasWidth,
        double canvasHeight)
    {
        if (line.Words.Count == 0) return [];

        double w = Math.Max(canvasWidth, 640.0);
        double h = Math.Max(canvasHeight, 480.0);
        var rng = new SplitMix64(seed);
        double densityScale = line.Words.Count > 10 ? 0.85 : 1.0;

        var placed = new List<Box>(line.Words.Count);
        var nodes = new List<ConstellationNode>(line.Words.Count);

        for (int i = 0; i < line.Words.Count; i++)
        {
            var word = line.Words[i];
            double lengthFactor = Math.Clamp((word.Text.Length - 2) / 7.0, 0.0, 1.0);
            double jitter = rng.NextUnit() * 4.5;
            double fontSize = Math.Clamp((15.5 + lengthFactor * 7.5 + jitter) * densityScale, MinFontSize, 26.0);

            double activeDisplaySize = Math.Clamp(fontSize * 1.42, 26.0, MaxFontSize);
            double estW = word.Text.Length * Math.Max(fontSize, activeDisplaySize * 0.82) * 0.62 + 24.0;
            const double topExtent = 20.0;
            double bottomExtent = ActiveLabelOffsetY + activeDisplaySize * 0.65;
            double halfNormW = Math.Min((estW / 2.0) / w, 0.16);

            double clampMinX = Math.Max(SafeMinX, halfNormW + 0.02);
            double clampMaxX = Math.Min(SafeMaxX, 1.0 - halfNormW - 0.02);
            double clampMinY = Math.Max(SafeMinY, SafeMinY + topExtent / h);
            double clampMaxY = Math.Min(SafeMaxY, (SafeMaxY * h - bottomExtent) / h);

            Box MakeBox(double nx, double ny)
            {
                double cx = nx * w;
                double cy = ny * h;
                return new Box(cx - estW / 2.0, cx + estW / 2.0, cy - topExtent, cy + bottomExtent);
            }

            double chosenX = clampMinX + rng.NextUnit() * (clampMaxX - clampMinX);
            double chosenY = clampMinY + rng.NextUnit() * (clampMaxY - clampMinY);
            var chosenBox = MakeBox(chosenX, chosenY);

            if (nodes.Count > 0)
            {
                var prev = nodes[^1];
                bool found = false;

                for (int attempt = 0; attempt < 140; attempt++)
                {
                    double cx, cy;
                    if (attempt < 80)
                    {
                        double angle = rng.NextUnit() * 2.0 * Math.PI;
                        double distX = 0.14 + rng.NextUnit() * 0.18;
                        double distY = 0.09 + rng.NextUnit() * 0.15;
                        cx = Math.Clamp(prev.X + Math.Cos(angle) * distX, clampMinX, clampMaxX);
                        cy = Math.Clamp(prev.Y + Math.Sin(angle) * distY, clampMinY, clampMaxY);
                    }
                    else
                    {
                        cx = clampMinX + rng.NextUnit() * (clampMaxX - clampMinX);
                        cy = clampMinY + rng.NextUnit() * (clampMaxY - clampMinY);
                    }

                    var candidate = MakeBox(cx, cy);
                    if (!placed.Any(b => b.Intersects(candidate)))
                    {
                        chosenX = cx;
                        chosenY = cy;
                        chosenBox = candidate;
                        found = true;
                        break;
                    }
                }

                if (!found)
                {
                    for (int row = 0; row < 5 && !found; row++)
                    {
                        for (int col = 0; col < 8 && !found; col++)
                        {
                            double gx = clampMinX + (col / 7.0) * (clampMaxX - clampMinX);
                            double gy = clampMinY + (row / 4.0) * (clampMaxY - clampMinY);
                            var candidate = MakeBox(gx, gy);
                            if (!placed.Any(b => b.Intersects(candidate)))
                            {
                                chosenX = gx;
                                chosenY = gy;
                                chosenBox = candidate;
                                found = true;
                            }
                        }
                    }
                }
            }

            placed.Add(chosenBox);
            nodes.Add(new ConstellationNode(i, word.Text, chosenX, chosenY, fontSize, word.StartTime, word.EndTime));
        }

        return nodes;
    }
}
