namespace Needle.Core;

public enum ScreensaverMode
{
    FullScreen,
    Preview,
    Configure
}

public sealed record ScreensaverCommand(ScreensaverMode Mode, nint PreviewHandle = 0);

public static class ScreensaverArgs
{
    public static ScreensaverCommand Parse(string[] args)
    {
        if (args.Length == 0)
        {
            return new ScreensaverCommand(ScreensaverMode.FullScreen);
        }

        string first = args[0].Trim().ToLowerInvariant();
        string? second = args.Length > 1 ? args[1].Trim() : null;

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
