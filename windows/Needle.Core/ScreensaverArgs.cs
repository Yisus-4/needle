namespace Needle.Core;

public enum ScreensaverMode
{
    FullScreen,
    Preview,
    Configure,
    Tray
}

public sealed record ScreensaverCommand(ScreensaverMode Mode, nint PreviewHandle = 0);

public static class ScreensaverArgs
{
    public static ScreensaverCommand Parse(string[] args, string? executablePath = null)
    {
        if (args.Length == 0)
        {
            bool isScr = executablePath is not null &&
                         executablePath.EndsWith(".scr", StringComparison.OrdinalIgnoreCase);
            return new ScreensaverCommand(isScr ? ScreensaverMode.FullScreen : ScreensaverMode.Tray);
        }

        string first = args[0].Trim().ToLowerInvariant();
        string? second = args.Length > 1 ? args[1].Trim() : null;

        if (first is "--tray" or "/tray" or "-tray")
        {
            return new ScreensaverCommand(ScreensaverMode.Tray);
        }

        if (first.StartsWith("/c", StringComparison.Ordinal) || first.StartsWith("-c", StringComparison.Ordinal))
        {
            return new ScreensaverCommand(ScreensaverMode.Configure);
        }

        if (first.StartsWith("/p", StringComparison.Ordinal) || first.StartsWith("-p", StringComparison.Ordinal))
        {
            string? handleStr = null;
            if (first.Length > 3 && first[2] == ':')
            {
                handleStr = first[3..];
            }
            else if (!string.IsNullOrEmpty(second))
            {
                handleStr = second;
            }

            nint handle = long.TryParse(handleStr, out long parsed) ? (nint)parsed : 0;
            return new ScreensaverCommand(ScreensaverMode.Preview, handle);
        }

        return new ScreensaverCommand(ScreensaverMode.FullScreen);
    }
}
