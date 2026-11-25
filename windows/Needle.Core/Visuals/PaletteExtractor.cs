using Needle.Core.Models;

namespace Needle.Core.Visuals;

public static class PaletteExtractor
{
    private struct HueBucket
    {
        public double Weight;
        public double RSum;
        public double GSum;
        public double BSum;
    }

    public static AlbumPalette ExtractFromRgba(ReadOnlySpan<byte> rgbaPixels, int width, int height)
    {
        int pixelCount = Math.Min(width * height, rgbaPixels.Length / 4);
        if (pixelCount <= 0) return AlbumPalette.Fallback;

        const int bucketCount = 12;
        var buckets = new HueBucket[bucketCount];
        double totalSat = 0, rAvg = 0, gAvg = 0, bAvg = 0;
        int validPixels = 0;

        for (int i = 0; i < pixelCount; i++)
        {
            int idx = i * 4;
            double a = rgbaPixels[idx + 3] / 255.0;
            if (a <= 0.1) continue;

            double r = rgbaPixels[idx] / 255.0;
            double g = rgbaPixels[idx + 1] / 255.0;
            double b = rgbaPixels[idx + 2] / 255.0;

            validPixels++;
            rAvg += r;
            gAvg += g;
            bAvg += b;

            var hsb = new RgbColor(r, g, b).ToHsb();
            totalSat += hsb.S;

            int bucket = Math.Min(bucketCount - 1, (int)(hsb.H * bucketCount));
            double w = (0.2 + hsb.S * 1.8) * (0.25 + hsb.B * 0.75);
            buckets[bucket].Weight += w;
            buckets[bucket].RSum += r * w;
            buckets[bucket].GSum += g * w;
            buckets[bucket].BSum += b * w;
        }

        if (validPixels == 0) return AlbumPalette.Fallback;

        double avgSat = totalSat / validPixels;
        if (avgSat < 0.08)
        {
            double meanLuma = new RgbColor(rAvg / validPixels, gAvg / validPixels, bAvg / validPixels).RelativeLuminance;
            return new AlbumPalette(
                RgbColor.FromHsb(0.61, 0.22, meanLuma > 0.5 ? 0.18 : 0.11),
                RgbColor.FromHsb(0.64, 0.28, 0.08),
                RgbColor.FromHsb(0.59, 0.18, 0.94)
            );
        }

        var ranked = buckets
            .Select((bucket, index) => (Index: index, Bucket: bucket))
            .Where(x => x.Bucket.Weight > 0)
            .OrderByDescending(x => x.Bucket.Weight)
            .ToList();

        if (ranked.Count == 0) return AlbumPalette.Fallback;

        var top = ranked[0].Bucket;
        var primaryRaw = new RgbColor(top.RSum / top.Weight, top.GSum / top.Weight, top.BSum / top.Weight);
        var primaryHsb = primaryRaw.ToHsb();

        RgbColor secondaryRaw;
        var secondEntry = ranked.Skip(1).FirstOrDefault(x => Math.Abs(x.Index - ranked[0].Index) >= 2);
        if (secondEntry.Bucket.Weight > 0)
        {
            var sb = secondEntry.Bucket;
            secondaryRaw = new RgbColor(sb.RSum / sb.Weight, sb.GSum / sb.Weight, sb.BSum / sb.Weight);
        }
        else
        {
            secondaryRaw = RgbColor.FromHsb(primaryHsb.H + 0.08, primaryHsb.S, primaryHsb.B);
        }
        var secondaryHsb = secondaryRaw.ToHsb();

        var backdropPrimary = RgbColor.FromHsb(primaryHsb.H, Math.Clamp(primaryHsb.S, 0.35, 0.78), 0.20);
        var backdropSecondary = RgbColor.FromHsb(secondaryHsb.H, Math.Clamp(secondaryHsb.S, 0.30, 0.72), 0.13);
        double accentHue = secondaryHsb.S > 0.35 ? secondaryHsb.H : primaryHsb.H;
        var accent = RgbColor.FromHsb(accentHue, Math.Clamp(primaryHsb.S * 0.65, 0.28, 0.58), 0.95);

        return new AlbumPalette(backdropPrimary, backdropSecondary, accent);
    }
}
