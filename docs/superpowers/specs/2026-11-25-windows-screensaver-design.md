# Windows Lock Screen Synced Lyrics (`Needle.scr`) — Design Document

**Date:** 2026-11-25  
**Scope:** Phase 2 — Native Windows 10/11 `.scr` screensaver (Spotify local via SMTC, Stars constellation + album artwork backdrop) + GitHub Actions release pipeline for both macOS and Windows.

---

## 1. Intent & Why

Bring the exact same minimalist, 100% private **Stars** synced lyrics experience built in Phase 1 (macOS) to Windows 10 and Windows 11, using a native Windows screensaver (`.scr`) that locks the session with Windows' built-in *"On resume, display logon screen"* option.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- Native Windows `.scr` executable (`Needle.scr`) built with **C# / .NET 8 WPF** targeting `net8.0-windows10.0.19041.0` (works identically on Windows 10 2004+ and Windows 11).
- Read Spotify locally with **zero login / zero Spotify API app** via Windows **SMTC** (`GlobalSystemMediaTransportControlsSessionManager`), filtering for Spotify sessions (`Spotify.exe` / `SpotifyAB.SpotifyMusic`).
- Render the **actual album artwork** full-screen (from SMTC's embedded thumbnail stream) with a subtle dark scrim + **Stars** word-by-word organic constellation (4-point sparkle stars, thin luminous connecting lines, circular halo ring on the active word, variable readable font sizes `>= 15pt`, no screen-edge glow).
- Fetch synchronized lyrics from **LRCLIB** with the exact same matching strategy as macOS (`/api/get` → `/api/search` ±15s/±30s with album preference → `?q=` cleaned-title fallback + in-memory cache, never caching transient network errors).
- Standard Windows screensaver CLI contract:
  - `/s` (or no args): full-screen across all connected monitors, hides cursor, exits cleanly on mouse movement (> 12px threshold to ignore tiny sensor jitter), mouse click, or any key press.
  - `/p <HWND>`: embedded mini preview inside Windows Screen Saver Settings dialog.
  - `/c` (or `/c:<HWND>`): simple read-only Settings/About dialog showing Spotify status, privacy summary, and a "Test Preview" button.
- Packaging & distribution:
  - `windows/build-windows.ps1` script producing a single self-contained `Needle.scr` (`win-x64`, zero .NET install required on target PC).
  - `.github/workflows/release.yml` workflow building both `Needle-macOS.zip` (`Needle.app`) and `Needle-Windows.scr` automatically on GitHub Releases / manual dispatch.

### Non-Goals
- No interactive playback controls on the screensaver.
- No Beat Glow / system audio capture, no telemetry, no camera, no location, no background tray app required.

### Anti-Goals
- Never leak any data beyond LRCLIB queries (track title, artist, album, duration).
- Never trap the user on the screensaver: any key press, click, or deliberate mouse move must exit immediately so Windows' logon/password screen appears.

---

## 3. Architecture (`windows/`)

```text
windows/
├── Needle.sln
├── build-windows.ps1
├── Needle.Core/                     # Pure net8.0 library (unit-testable on any OS)
│   ├── Models/                      # TrackInfo, PlaybackState, WordTiming, LyricLine, AlbumPalette
│   ├── Lyrics/                      # LrcParser, PlaybackClock, LrclibClient (+ IHttpTransport)
│   └── Visuals/                     # PaletteExtractor, ConstellationLayout (organic random walk)
├── Needle.Core.Tests/               # xUnit test suite mirroring all macOS NeedleCoreTests
└── Needle.Screensaver/              # net8.0-windows10.0.19041.0 WPF app -> published as Needle.scr
    ├── Player/SmtcSpotifyProvider.cs
    ├── UI/ConstellationWindow.xaml(.cs)
    ├── UI/ConfigWindow.xaml(.cs)
    ├── System/ScreensaverArgs.cs    # /s, /p <HWND>, /c parser
    └── App.xaml(.cs)
```

---

## 4. Distribution Notes

- **Windows (`Needle.scr`):** Single self-contained executable. Right-click → **Install** (or copy to `C:\Windows\System32` / select in Screen Saver Settings) and check *"On resume, display logon screen"*. Unsigned builds may trigger Windows SmartScreen (*More info → Run anyway*) once.
- **macOS (`Needle-macOS.zip`):** Contains `Needle.app`. Drag to `/Applications`. Unsigned builds downloaded from the internet may require right-click → Open or `xattr -cr /Applications/Needle.app` once.
