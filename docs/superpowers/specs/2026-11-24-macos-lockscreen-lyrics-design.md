# macOS Lock Screen Synced Lyrics (Needle) — Design Document

**Date:** 2026-11-24  
**Scope:** Phase 1 — macOS native app (Spotify only, display-only)  
**Future Scope (separate project):** Windows `.scr` screensaver sharing the same visual language and lyrics protocol.

---

## 1. Intent & Why

The user wants the aesthetic experience of seeing real-time synchronized song lyrics colored by the current album's artwork on their Mac's lock screen (inspired by `needlemac.com`), **without** any of the privacy risks or bloat: no camera access / Face Unlock, no location or weather requests, no keyboard listeners, no telemetry, no accounts, and no third-party login.

The tool should be minimal, trustworthy, and auditable: it only reads what Spotify is playing locally and fetches public lyrics (and the album cover image) over HTTPS.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- Display real-time **word-by-word connected-node lyrics** (constellation style: `word₁ → word₂ → word₃` appearing organically across the screen) on the **real macOS Lock Screen** (`Ctrl+Cmd+Q` or inactivity) whenever Spotify is actively playing.
- Dynamically color the lock screen full-screen translucent backdrop and glowing node connections using a palette extracted locally from the current track's album artwork.
- Work with **Spotify desktop app locally** without requiring a Spotify developer app, OAuth login, or user credentials.
- Stay 100% passive on the lock screen (`ignoresMouseEvents = true`, never steals keyboard focus) so password entry and Touch ID always work normally.
- Respect macOS display sleep normally (no wake-lock / power assertions) and suspend rendering and polling while the display is asleep.
- Run unobtrusively from the macOS menu bar with minimal CPU/RAM overhead.
- Design the media-source layer behind a clean abstraction so other players (e.g., Apple Music) can be added in Phase 2.

### Non-Goals (Phase 1)
- No interactive playback controls (play/pause/next/previous) on the lock screen.
- No Dynamic Island / notch player, no Beat Glow audio capture, no live wallpapers, no mechanical keyboard sounds, no calendar/weather widgets.
- No Launch at Login (`SMAppService`) in Phase 1.
- No multiple lyric style switcher in v1 (v1 ships with the connected-node word-by-word style).
- No Windows implementation in this phase (Windows `.scr` will be designed and built as a separate sibling project later).
- No Mac App Store distribution (incompatible with `SkyLight` private APIs).

### Anti-Goals (Failure Conditions)
- **Any privacy leak:** never request camera, microphone, screen recording, location, calendar, or input monitoring permissions; never send analytics, hardware hashes, or user identifiers anywhere.
- **Blocking unlock:** the overlay must never intercept clicks, block keyboard input, or hide/break Touch ID or password entry.
- **Stale/stuck overlay:** must never remain stuck on screen after unlocking or when Spotify stops/closes.
- **Battery drain while asleep:** must not prevent display sleep or keep polling/rendering after macOS turns off the display.

---

## 3. Constraints

- **Target environment:** macOS 26.6.2 (Apple Silicon, arm64), Swift 6.3 toolchain already installed. Minimum target macOS 14+ (Apple Silicon).
- **Lock screen rendering (`SkyLight`):** Standard Cocoa `NSWindow` levels cannot render above `loginwindow`. A throwaway spike on this exact Mac (macOS 26.6.2, SIP enabled) confirmed that dynamically loading `/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight` and calling:
  - `SLSMainConnectionID()`
  - `SLSSpaceCreate(conn, 1, 0)`
  - `SLSSpaceSetAbsoluteLevel(conn, space, 400)` (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`)
  - `SLSShowSpaces(conn, [space])`
  - `SLSSpaceAddWindowsAndRemoveFromSpaces(conn, space, [windowNumber], 7)`
  successfully renders a SwiftUI `NSWindow` (`canBecomeVisibleWithoutLogin = true`, `ignoresMouseEvents = true`, `canBecomeKey = false`, `canBecomeMain = false`, `level = Int32.max - 2`) on the real lock screen and hides cleanly on unlock.
- **Permissions:** Only standard **Automation** permission (`NSAppleEventsUsageDescription`) for reading Spotify's playback state via Apple Events. No other macOS TCC permissions.
- **Allowed network traffic (strictly limited to):**
  1. `https://lrclib.net/api/get` (and `/api/search` fallback) — sends only track title, artist, album, and duration.
  2. Album artwork HTTPS URL provided by Spotify's local track metadata (typically `https://i.scdn.co/...`).

---

## 4. Approaches Considered

### Approach 1 — Native Swift + SwiftUI + SkyLight *(Picked)*
- Pure Swift/SwiftUI menu bar app compiled with Swift 6.3 (`Package.swift` + `.app` bundle script).
- Local Spotify bridge via `DistributedNotificationCenter` (`com.spotify.client.PlaybackStateChanged`) + AppleScript (`NSAppleScript`) for metadata, artwork URL, and playback position.
- CoreImage / local Swift color extraction from album art; SwiftUI `Canvas` + Metal rendering for the glowing word-node constellation on a `SkyLight` space.
- **Trade-offs:** macOS-only codebase (Windows `.scr` will be a separate project later); relies on private `SkyLight` symbols that may require maintenance across future major macOS releases (mitigated by isolating all `SkyLight` calls in one small module with graceful failure if symbols are missing).
- **Why picked:** Lowest RAM/CPU footprint, zero external runtime dependencies, native macOS transparency/rendering on the lock screen, and already validated via spike on macOS 26.6.2.

### Approach 2 — Tauri (Rust + WebView) + Native SkyLight Bridge *(Rejected)*
- HTML/CSS/JS frontend rendered inside WebKit, reusable for a future Windows WebView `.scr`, mounted on macOS via a native Swift/Obj-C `SkyLight` shim.
- **Trade-offs:** Higher memory usage, WebKit transparency/GPU quirks inside private `SkyLight` spaces, and requires Rust + Node toolchains. Rejected in favor of native stability and simplicity.

---

## 5. System Design

### 5.1 Architecture & Modules

```
┌──────────────────────────────────────────────────────────┐
│                     Menu Bar App Shell                   │
│         (Status, Enable/Disable, Preview, Quit)          │
└──────────────┬───────────────────────────┬───────────────┘
               │                           │
               ▼                           ▼
┌──────────────────────────┐   ┌───────────────────────────┐
│   MediaPlayerProvider    │   │   Lock & Sleep Monitor    │
│  (Protocol; Phase 1:     │   │  screenIsLocked/Unlocked  │
│   SpotifyProvider)       │   │  screensDidSleep/DidWake  │
└──────┬───────────────┬───┘   └─────────────┬─────────────┘
       │               │                     │
       ▼               ▼                     │
┌─────────────┐ ┌────────────────┐           │
│ LyricsClient│ │ PaletteExtractor│          │
│ (LRCLIB +   │ │ (Album art ->   │          │
│  word timing│ │  3-color aura) │          │
└──────┬──────┘ └───────┬────────┘           │
       │                │                    │
       └────────┬───────┘                    │
                ▼                            ▼
┌──────────────────────────────────────────────────────────┐
│                  LockScreenCoordinator                   │
│  - Smooth position clock (drift-corrected vs Spotify)    │
│  - Suspends animation & polling while display sleeps     │
│  - Shows/hides PassiveOverlayWindow(s) via SkyLightBridge│
└──────────────────────────┬───────────────────────────────┘
                           ▼
┌──────────────────────────────────────────────────────────┐
│              ConstellationLyricsView (SwiftUI)           │
│  - Full-screen translucent album-color backdrop          │
│  - Word-by-word connected nodes + fallback track info    │
└──────────────────────────────────────────────────────────┘
```

### 5.2 Decided Behaviors & Agent Calls

*(Items marked **[Agent call]** are sensible defaults settled by the designer and open to user adjustment.)*

1. **Spotify Local Integration (Phase 1):**
   - Subscribe to `DistributedNotificationCenter` notification `com.spotify.client.PlaybackStateChanged` for instant track-change and play/pause detection.
   - Query Spotify via AppleScript (`tell application "Spotify"`) for `player state`, `player position`, and current track `id`, `name`, `artist`, `album`, `duration`, `artwork url`.
   - **[Agent call]** Only poll Spotify periodically (every 2–3 seconds) *while locked (or in Preview), display is awake, and Spotify is playing* to correct clock drift (e.g., scrubbing or skipping via headphones); do zero polling when unlocked/idle, when display is asleep, or when Spotify is not running.
   - Between polls, advance playback position smoothly using a monotonic clock anchored to the last Spotify sample so word reveals stay frame-accurate without hammering AppleScript.

2. **Lyrics Fetching & Word-by-Word Timing:**
   - Fetch from `https://lrclib.net/api/get?track_name=...&artist_name=...&album_name=...&duration=...` with a descriptive `User-Agent` header.
   - **[Agent call]** If `/api/get` returns 404 or lacks `syncedLyrics`, fall back once to `/api/search?track_name=...&artist_name=...` and pick the closest duration match (±5s) that has `syncedLyrics`.
   - Parse standard LRC line timestamps (`[mm:ss.xx]` / `[mm:ss.xxx]`) and enhanced LRC word timestamps (`<mm:ss.xx>`) when present.
   - **Word timing derivation:** When a line only has a line-level timestamp (standard LRCLIB), derive per-word reveal times by distributing the active line's singing window (`min(nextLineTime - currentLineTime, cappedLineDuration)`) proportionally across its words weighted by character length, so words illuminate naturally in rhythm (`esta` → `línea` → `brilla` → …) without dragging across long instrumental pauses.
   - **[Agent call]** Keep an in-memory cache keyed by Spotify track ID for the app session so replaying or locking/unlocking mid-song is instant.

3. **Album-Art Color Palette Extraction:**
   - Download the artwork image from Spotify's `artwork url` (cached in memory per track ID).
   - Extract a 3-color palette locally (primary backdrop, secondary aura, bright accent for active node/edges) and clamp luminance/saturation so white/accent word nodes remain high-contrast and legible.
   - Smoothly cross-fade colors when changing tracks.

4. **Lock Screen Overlay, Display Sleep & Visual Style (Stars Constellation):**
   - **Backdrop (Decided: Option A, dark album-tinted wash, no edge glow):** Full-screen dark translucent wash subtly tinted by the album's primary color so the whole lock screen adopts the album's mood while keeping native macOS clock and password/Touch ID visible underneath and maximizing contrast for the constellation. **No Beat Glow / no screen-edge light.**
   - **Stars Constellation (Word-by-Word Connected Nodes):**
     - Inspired by Needle's *Stars* visual style: words of the active lyric line (or short phrase window) appear sequentially in time at organic pseudo-random positions across the **safe central canvas** (leaving generous top margin for the native macOS clock and bottom margin for the avatar/password/Touch ID prompt, with collision avoidance so words never overlap).
     - Each word node is anchored by a small **4-point sparkle star** connected to the previous node by a crisp thin luminous line in the album's bright accent color.
     - The **currently active word** features a brighter 4-point star surrounded by a thin **circular halo ring** directly above it, with the word rendered large, bold, and brightly tinted in the album's accent color.
     - **Variable readable sizing:** Word sizes vary organically across the constellation (active and prominent words larger/bolder, surrounding words varied in scale), with a strict minimum readable font size so primary and surrounding lyrics are always effortless to read.
     - When the next line begins, the previous constellation gently fades out as the new constellation forms.
     - Subtle small track title + artist caption sits unobtrusively near the bottom of the safe zone.
   - **Display sleep (Decided: Option B):** Do **not** prevent display sleep. Observe `NSWorkspace.screensDidSleepNotification` and `screensDidWakeNotification` to pause the SwiftUI animation loop and Spotify drift polling while the screen is asleep, resuming immediately on wake if still locked and playing.
   - **When Spotify is paused or closed:** **[Agent call]** Hide the overlay (`orderOut`) so macOS shows its normal lock screen. Fade out if paused while locked; fade back in if resumed while locked.
   - **No synced lyrics fallback:** **[Agent call]** If LRCLIB has no synced lyrics (or offline), show the full-screen translucent album-color wash with a clean, understated track title & artist display in the center safe zone.
   - **Multi-monitor:** **[Agent call]** Create one passive overlay window per connected `NSScreen` and update when displays are connected/disconnected.

5. **Menu Bar App & Packaging:**
   - **[Agent call]** Runs as `.accessory` (`LSUIElement = true`, no Dock icon) with a minimal SF Symbol menu bar icon.
   - Menu items:
     - Current track status (read-only info line)
     - **Enable on Lock Screen** (toggle, on by default)
     - **Preview Overlay** (opens the same SwiftUI view in a dismissible desktop window with `Esc`/close button so the user can test lyrics & constellations without locking)
     - **Quit**
   - **[Agent call]** No Launch at Login in Phase 1.
   - **[Agent call]** Build script (`scripts/build-app.sh`) assembles `Needle.app` (SwiftPM release binary + `Info.plist` with `LSUIElement` and `NSAppleEventsUsageDescription`). Supports optional `CODESIGN_IDENTITY` env var (defaulting to ad-hoc `-` when unset), with a short README note on creating a local self-signed Keychain cert so macOS Automation permission persists across rebuilds.

---

## 6. Left to the Builder

- Exact typography scale, node halo blur radii, edge curvature/glow styling, and collision-free seeded layout algorithm for word nodes.
- Exact color-clustering algorithm (e.g., downsampled k-means vs. quantized histogram) and contrast clamping math.
- Unit test structure for LRC + enhanced-LRC parsing, word-timing distribution, clock interpolation/drift correction, LRCLIB response decoding/matching, collision-free node placement, and color extraction.
- Swift 6 concurrency isolation details (`@MainActor` boundaries, `Sendable` models).
- Repository layout (`Package.swift`, `Sources/`, `Tests/`, `scripts/build-app.sh`).
