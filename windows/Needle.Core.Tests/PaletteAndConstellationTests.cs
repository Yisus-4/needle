using Needle.Core.Models;
using Needle.Core.Visuals;
using Xunit;

namespace Needle.Core.Tests;

public sealed class PaletteAndConstellationTests
{
    private static byte[] SolidRgba(byte r, byte g, byte b, int count = 64)
    {
        var bytes = new byte[count * 4];
        for (int i = 0; i < count; i++)
        {
            bytes[i * 4] = r;
            bytes[i * 4 + 1] = g;
            bytes[i * 4 + 2] = b;
            bytes[i * 4 + 3] = 255;
        }
        return bytes;
    }

    [Fact]
    public void MonochromeCoversClampToReadablePalette()
    {
        var black = PaletteExtractor.ExtractFromRgba(SolidRgba(0, 0, 0), 8, 8);
        Assert.True(black.BackdropPrimary.RelativeLuminance <= 0.14);
        Assert.True(black.Accent.RelativeLuminance >= 0.45);

        var white = PaletteExtractor.ExtractFromRgba(SolidRgba(255, 255, 255), 8, 8);
        Assert.True(white.BackdropPrimary.RelativeLuminance <= 0.14);
        Assert.True(white.Accent.RelativeLuminance >= 0.45);
    }

    [Fact]
    public void ConstellationMovesOrganicallyWithoutOverlaps()
    {
        var line = Lyrics.LrcParser.Parse("[00:10.00] When it was real it is all that I could feel tonight", 60).Lines[0];
        int multiDir = 0;
        for (ulong seed = 1; seed <= 10; seed++)
        {
            var nodes = ConstellationLayout.Generate(line, seed, 1440, 900);
            Assert.Equal(line.Words.Count, nodes.Count);
            bool hasLeft = false, hasRight = false;
            for (int i = 1; i < nodes.Count; i++)
            {
                if (nodes[i].X < nodes[i - 1].X) hasLeft = true;
                if (nodes[i].X > nodes[i - 1].X) hasRight = true;
            }
            if (hasLeft && hasRight) multiDir++;

            foreach (var n in nodes)
            {
                Assert.InRange(n.BaseFontSize, ConstellationLayout.MinFontSize, ConstellationLayout.MaxFontSize);
                Assert.InRange(n.X, ConstellationLayout.SafeMinX, ConstellationLayout.SafeMaxX);
                Assert.InRange(n.Y, ConstellationLayout.SafeMinY, ConstellationLayout.SafeMaxY);
            }
        }
        Assert.True(multiDir >= 8);
    }

    [Fact]
    public void ScreensaverArgsParsesAllWindowsModes()
    {
        Assert.Equal(ScreensaverMode.Tray, ScreensaverArgs.Parse([], "Needle.exe").Mode);
        Assert.Equal(ScreensaverMode.Tray, ScreensaverArgs.Parse([]).Mode);
        Assert.Equal(ScreensaverMode.Tray, ScreensaverArgs.Parse(["--tray"]).Mode);
        Assert.Equal(ScreensaverMode.FullScreen, ScreensaverArgs.Parse([], "Needle.scr").Mode);
        Assert.Equal(ScreensaverMode.FullScreen, ScreensaverArgs.Parse(["/s"]).Mode);
        Assert.Equal(ScreensaverMode.Configure, ScreensaverArgs.Parse(["/c"]).Mode);
        Assert.Equal(ScreensaverMode.Configure, ScreensaverArgs.Parse(["/c:12345"]).Mode);

        var p1 = ScreensaverArgs.Parse(["/p", "98765"]);
        Assert.Equal(ScreensaverMode.Preview, p1.Mode);
        Assert.Equal((nint)98765, p1.PreviewHandle);

        var p2 = ScreensaverArgs.Parse(["/p:54321"]);
        Assert.Equal(ScreensaverMode.Preview, p2.Mode);
        Assert.Equal((nint)54321, p2.PreviewHandle);
    }
}
