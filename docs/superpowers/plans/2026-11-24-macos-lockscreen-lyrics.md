# macOS Lock Screen Synced Lyrics (Needle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, privacy-first macOS menu bar app that displays Spotify's real-time synchronized lyrics as a *Stars* word-by-word constellation colored by the album cover on the real macOS Lock Screen.

**Architecture:** Split into a pure, unit-testable Swift library (`NeedleCore`) for LRC parsing, word-timing derivation, monotonic clock sync, LRCLIB networking/caching, album-art palette extraction, collision-free constellation layout, and visibility state logic; and a thin macOS app target (`NeedleApp`) for local Spotify AppleScript/notification bridging, `SkyLight` lock-screen overlay windows, display sleep/wake handling, SwiftUI *Stars* rendering, and the menu bar shell.

**Tech Stack:** Swift 6.3, SwiftPM (`swift-tools-version: 6.0`), macOS 14+ (arm64), AppKit, SwiftUI, CoreGraphics/CoreImage, XCTest, `SkyLight.framework` (dynamic `dlopen`/`dlsym`), LRCLIB HTTPS API.

**Spec:** `docs/superpowers/specs/2026-11-24-macos-lockscreen-lyrics-design.md`

## Global Constraints

- Minimum platform: macOS 14+ on Apple Silicon (`arm64`), compiled with Swift 6.3 toolchain.
- Zero external third-party Swift package dependencies (standard Apple frameworks only).
- Allowed network traffic strictly limited to `https://lrclib.net/api/get`, `https://lrclib.net/api/search`, and the Spotify-provided album artwork HTTPS URL.
- Only macOS Automation permission (`NSAppleEventsUsageDescription`); zero camera, mic, screen recording, location, calendar, or input monitoring APIs.
- Lock screen overlay windows must be passive (`ignoresMouseEvents = true`, `canBecomeKey = false`, `canBecomeMain = false`, `canBecomeVisibleWithoutLogin = true`, `level = Int32.max - 2`) attached to `SkyLight` space level `400`.
- Full-screen dark translucent album-tinted backdrop (Option A), **no Beat Glow / no screen-edge light**.
- Do not prevent display sleep; suspend animations and Spotify polling while display sleeps (`screensDidSleepNotification` / `screensDidWakeNotification`).
- No Launch at Login (`SMAppService`) in Phase 1.

## Review Focus

1. **Instrumental gaps & empty LRC lines:** Standard LRCLIB tracks often contain empty `[mm:ss.xx]` markers or 15–30s gaps between lines; word timing must cap per-line singing duration and skip blank lines so the final word never hangs awkwardly. *(Pinned in Task 1)*
2. **Spotify millisecond duration vs. LRCLIB second duration & special characters:** Spotify reports duration in ms while `player position` and LRCLIB use seconds; titles/artists with quotes, accents, or `&` must be URL-encoded cleanly and matched within ±5s on `/api/search` fallback. *(Pinned in Task 2 & Task 5)*
3. **Extreme monochrome album covers (pure black or pure white):** Palette extraction must clamp backdrop luminance dark and accent luminance bright so white/accent lyrics always remain high-contrast. *(Pinned in Task 3)*
4. **Long lyric lines (12+ words) staying readable and collision-free in the safe central band:** Word nodes must never overlap each other or intrude into the top clock (`y < 0.26`) or bottom Touch ID/password (`y > 0.72`) zones, while keeping font sizes above the readable floor (`>= 15pt`). *(Pinned in Task 4)*
5. **Lock/sleep/pause state races:** Locking while paused, pausing via headphones while locked, or display sleep while locked must immediately hide the overlay or suspend polling/rendering, and unlocking must always guarantee zero visible overlay windows. *(Pinned in Task 6)*

---

## File Map

- `Package.swift`, `.gitignore` — SwiftPM workspace (`NeedleCore`, `NeedleApp`, `NeedleCoreTests`)
- `Sources/NeedleCore/Models/TrackInfo.swift` — `TrackInfo`, `PlaybackState`, `PlaybackSnapshot`
- `Sources/NeedleCore/Models/LyricsModels.swift` — `WordTiming`, `LyricLine`, `SyncedLyrics`
- `Sources/NeedleCore/Models/AlbumPalette.swift` — `RGBColor`, `AlbumPalette`
- `Sources/NeedleCore/Lyrics/LRCParser.swift` — LRC & enhanced-LRC parser + proportional word timing
- `Sources/NeedleCore/Lyrics/PlaybackClock.swift` — monotonic position interpolation & drift correction
- `Sources/NeedleCore/Lyrics/LRCLIBClient.swift` — `HTTPTransport` protocol, `/api/get` + `/api/search` fallback, in-memory cache
- `Sources/NeedleCore/Visuals/PaletteExtractor.swift` — local pixel clustering + contrast clamping
- `Sources/NeedleCore/Visuals/ConstellationLayout.swift` — seeded collision-free *Stars* node layout & variable readable sizing
- `Sources/NeedleCore/Player/MediaPlayerProvider.swift` — player abstraction protocol
- `Sources/NeedleCore/State/OverlayVisibilityPolicy.swift` — pure state machine for show/hide & polling/animation suspension
- `Sources/NeedleApp/Player/SpotifyProvider.swift` — `DistributedNotificationCenter` + AppleScript Spotify bridge
- `Sources/NeedleApp/System/SkyLightBridge.swift` — isolated `dlopen`/`dlsym` `SkyLight` wrapper
- `Sources/NeedleApp/System/LockAndSleepMonitor.swift` — lock/unlock + screen sleep/wake observer
- `Sources/NeedleApp/System/PassiveOverlayWindow.swift` — passive lock-screen `NSWindow`
- `Sources/NeedleApp/UI/ConstellationLyricsView.swift` — SwiftUI *Stars* constellation view + dark album wash + fallback
- `Sources/NeedleApp/App/LockScreenCoordinator.swift` — orchestrates player, lyrics, palette, clock, multi-monitor windows, preview
- `Sources/NeedleApp/App/NeedleAppMain.swift` — `.accessory` menu bar app entry point
- `scripts/build-app.sh`, `README.md` — `Needle.app` bundle assembly, optional `CODESIGN_IDENTITY`, setup notes

---

### Task 1: Project Scaffold, Core Models & LRC Word-Timing Parser

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `Sources/NeedleCore/Models/TrackInfo.swift`
- Create: `Sources/NeedleCore/Models/LyricsModels.swift`
- Create: `Sources/NeedleCore/Lyrics/LRCParser.swift`
- Test: `Tests/NeedleCoreTests/LRCParserTests.swift`

**Interfaces:**
- Produces:
  - `public enum PlaybackState: String, Sendable, Equatable { case playing, paused, stopped }`
  - `public struct TrackInfo: Sendable, Equatable { public let id: String; public let name: String; public let artist: String; public let album: String; public let durationSeconds: Double; public let artworkURL: URL? }`
  - `public struct PlaybackSnapshot: Sendable, Equatable { public let state: PlaybackState; public let positionSeconds: Double; public let track: TrackInfo?; public let sampledAt: TimeInterval }`
  - `public struct WordTiming: Sendable, Equatable { public let text: String; public let startTime: TimeInterval; public let endTime: TimeInterval }`
  - `public struct LyricLine: Sendable, Equatable { public let startTime: TimeInterval; public let endTime: TimeInterval; public let text: String; public let words: [WordTiming] }`
  - `public struct SyncedLyrics: Sendable, Equatable { public let lines: [LyricLine]; public func activeLine(at time: TimeInterval) -> (index: Int, line: LyricLine)? }`
  - `public enum LRCParser { public static func parse(_ raw: String, trackDuration: TimeInterval? = nil) -> SyncedLyrics }`

- [ ] **Step 1: Initialize git repo, `.gitignore`, and `Package.swift`**

Initialize git in `/Users/jesus/proyects/needle`, commit the existing design doc `docs/superpowers/specs/2026-11-24-macos-lockscreen-lyrics-design.md`, and create `.gitignore` (`.build/`, `build/`, `.swiftpm/`, `.DS_Store`) and `Package.swift` with `swift-tools-version: 6.0`, `.macOS(.v14)`, library target `NeedleCore`, executable target `NeedleApp` depending on `NeedleCore`, and test target `NeedleCoreTests` depending on `NeedleCore`.

- [ ] **Step 2: Write the failing tests in `Tests/NeedleCoreTests/LRCParserTests.swift`**

```swift
import XCTest
@testable import NeedleCore

final class LRCParserTests: XCTestCase {
    func testStandardLRCDistributesWordsProportionally() {
        let raw = """
        [00:10.00] Hello beautiful world
        [00:13.00] Next line
        """
        let lyrics = LRCParser.parse(raw, trackDuration: 180)
        XCTAssertEqual(lyrics.lines.count, 2)
        let words = lyrics.lines[0].words
        XCTAssertEqual(words.map(\.text), ["Hello", "beautiful", "world"])
        XCTAssertEqual(words[0].startTime, 10.0, accuracy: 0.01)
        XCTAssertGreaterThan(words[1].endTime - words[1].startTime, words[0].endTime - words[0].startTime)
        XCTAssertLessThanOrEqual(words.last!.endTime, 13.0)
    }

    func testEnhancedLRCUsesExactWordTimestamps() {
        let raw = "[00:05.00] <00:05.00> Esta <00:05.40> línea <00:06.10> brilla"
        let lyrics = LRCParser.parse(raw, trackDuration: 60)
        let words = lyrics.lines[0].words
        XCTAssertEqual(words.map(\.text), ["Esta", "línea", "brilla"])
        XCTAssertEqual(words[0].startTime, 5.0, accuracy: 0.01)
        XCTAssertEqual(words[1].startTime, 5.4, accuracy: 0.01)
        XCTAssertEqual(words[2].startTime, 6.1, accuracy: 0.01)
    }

    func testInstrumentalGapCapsLineWindowAndSkipsBlankLines() {
        let raw = """
        [00:10.00] Short phrase
        [00:14.00]
        [00:40.00] After solo
        """
        let lyrics = LRCParser.parse(raw, trackDuration: 120)
        XCTAssertEqual(lyrics.lines.count, 2)
        // Blank line at 14.00 closes previous line; even without it, line window is capped.
        XCTAssertLessThanOrEqual(lyrics.lines[0].endTime, 14.0)
        XCTAssertNil(lyrics.activeLine(at: 25.0))
        XCTAssertEqual(lyrics.activeLine(at: 40.5)?.line.text, "After solo")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter LRCParserTests`
Expected: FAIL (missing `NeedleCore` types / `LRCParser`).

- [ ] **Step 4: Implement `TrackInfo.swift`, `LyricsModels.swift`, and `LRCParser.swift`**

Implement the exact public types in `Interfaces`. In `LRCParser.parse`:
- Parse `[mm:ss.xx]` / `[mm:ss.xxx]` timestamps; treat blank lines as explicit end markers for the preceding lyric line (not emitted as `LyricLine`s).
- Support `<mm:ss.xx>` / `<mm:ss.xxx>` enhanced word tags when present.
- For standard lines, cap the singing window to `min(nextTimestamp - startTime, Double(words.count) * 0.85, 8.0)` and distribute proportionally by `max(word.count, 2)` characters.
- `activeLine(at:)` returns the line where `startTime <= time && time < endTime`, else `nil`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LRCParserTests`
Expected: PASS (3/3 tests).

- [ ] **Step 6: Commit**

```bash
git add .gitignore Package.swift Sources/NeedleCore Tests/NeedleCoreTests/LRCParserTests.swift docs/
git commit -m "feat: scaffold NeedleCore and add LRC word-timing parser"
```

---

### Task 2: Playback Clock & LRCLIB Client with Cache

**Files:**
- Create: `Sources/NeedleCore/Lyrics/PlaybackClock.swift`
- Create: `Sources/NeedleCore/Lyrics/LRCLIBClient.swift`
- Test: `Tests/NeedleCoreTests/PlaybackClockTests.swift`
- Test: `Tests/NeedleCoreTests/LRCLIBClientTests.swift`

**Interfaces:**
- Consumes: `TrackInfo`, `PlaybackSnapshot`, `PlaybackState`, `SyncedLyrics`, `LRCParser`
- Produces:
  - `public struct PlaybackClock: Sendable { public init(); public mutating func sync(with snapshot: PlaybackSnapshot); public func currentPosition(at now: TimeInterval) -> TimeInterval }`
  - `public protocol HTTPTransport: Sendable { func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
  - `public actor LRCLIBClient { public init(transport: any HTTPTransport = URLSessionHTTPTransport()); public func fetchLyrics(for track: TrackInfo) async -> SyncedLyrics? }`

- [ ] **Step 1: Write failing tests for `PlaybackClockTests` and `LRCLIBClientTests`**

In `PlaybackClockTests.swift`:
- `testAdvancesSmoothlyWhilePlaying`: sync playing at `pos = 10.0, sampledAt = 100.0`, assert `currentPosition(at: 101.25) == 11.25`.
- `testFreezesPositionWhilePaused`: sync paused at `pos = 10.0, sampledAt = 100.0`, assert `currentPosition(at: 105.0) == 10.0`.
- `testSmallDriftPreservesSmoothClockLargeDriftSnaps`: drift `0.15s` (<= `0.35s` threshold) keeps smooth anchor; drift `2.5s` (> `0.35s`) snaps immediately to new sample.

In `LRCLIBClientTests.swift` (using a mock `HTTPTransport`):
- `testExactGetReturnsParsedLyricsAndCachesByTrackID`: returns JSON with `syncedLyrics`, asserts second call makes `0` extra HTTP requests and verifies `User-Agent` header is set and `duration` query param is rounded seconds (not milliseconds).
- `testFallsBackToSearchAndPicksClosestDurationWithin5Seconds`: `/api/get` returns 404, `/api/search` returns 2 candidates (one 20s off, one 2s off with `syncedLyrics`); asserts the 2s-off candidate is chosen and non-ASCII/special characters (`&`, quotes, accents) are properly percent-encoded.
- `testReturnsNilGracefullyOnNetworkFailure`: mock throws `URLError(.notConnectedToInternet)`, asserts `nil` returned without crashing.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "PlaybackClockTests|LRCLIBClientTests"`
Expected: FAIL (missing `PlaybackClock` and `LRCLIBClient`).

- [ ] **Step 3: Implement `PlaybackClock.swift` and `LRCLIBClient.swift`**

- `PlaybackClock`: anchors `(basePosition, anchorTime, state, trackID)`; on `sync(with:)`, if same track and both playing and `abs(predicted - snapshot.positionSeconds) <= 0.35`, preserve current anchor to prevent visual jitter; otherwise snap to `snapshot`.
- `LRCLIBClient`: builds `URLComponents` for `https://lrclib.net/api/get` (`track_name`, `artist_name`, `album_name`, `duration` as integer seconds) with `User-Agent: Needle/1.0 (https://github.com/local/needle)`; falls back once to `/api/search` picking the entry with non-empty `syncedLyrics` closest to `track.durationSeconds` within `5.0` seconds. Caches results (including negative misses via enum `.hit(SyncedLyrics)` / `.miss`) in memory by `track.id`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "PlaybackClockTests|LRCLIBClientTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedleCore/Lyrics/PlaybackClock.swift Sources/NeedleCore/Lyrics/LRCLIBClient.swift Tests/NeedleCoreTests/PlaybackClockTests.swift Tests/NeedleCoreTests/LRCLIBClientTests.swift
git commit -m "feat: add drift-corrected PlaybackClock and cached LRCLIBClient"
```

---

### Task 3: Album-Art Color Palette Extractor

**Files:**
- Create: `Sources/NeedleCore/Models/AlbumPalette.swift`
- Create: `Sources/NeedleCore/Visuals/PaletteExtractor.swift`
- Test: `Tests/NeedleCoreTests/PaletteExtractorTests.swift`

**Interfaces:**
- Produces:
  - `public struct RGBColor: Sendable, Equatable { public let r: Double; public let g: Double; public let b: Double; public var relativeLuminance: Double }`
  - `public struct AlbumPalette: Sendable, Equatable { public let backdropPrimary: RGBColor; public let backdropSecondary: RGBColor; public let accent: RGBColor; public static let fallback: AlbumPalette }`
  - `public enum PaletteExtractor { public static func extract(from rgbaPixels: [UInt8], width: Int, height: Int) -> AlbumPalette; public static func extract(from imageData: Data) -> AlbumPalette }`

- [ ] **Step 1: Write failing tests in `Tests/NeedleCoreTests/PaletteExtractorTests.swift`**

- `testExtractsDominantHueFromVibrantImage`: 16×16 RGBA buffer filled with rich purple `(120, 40, 210)` + teal accent `(30, 190, 200)` produces dark backdrop (`backdropPrimary.relativeLuminance <= 0.14`) and bright accent (`accent.relativeLuminance >= 0.35`) retaining high blue/purple dominance.
- `testPureBlackAndPureWhiteCoversClampToReadablePalette`:
  - All-black `(0,0,0)` buffer still yields bright legible `accent.relativeLuminance >= 0.45` and dark backdrop.
  - All-white `(255,255,255)` buffer clamps `backdropPrimary.relativeLuminance <= 0.14` so white/accent lyrics remain high-contrast.
- `testInvalidImageDataReturnsFallback`: `extract(from: Data("bad".utf8)) == .fallback`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PaletteExtractorTests`
Expected: FAIL.

- [ ] **Step 3: Implement `AlbumPalette.swift` and `PaletteExtractor.swift`**

- Quantize/bucket downsampled pixels (e.g., 32×32 via CoreGraphics `CGImageSource` + `CGContext` RGBA bitmap for `Data` overload) into hue/saturation buckets to find dominant primary and secondary/accent colors.
- Clamp `backdropPrimary` and `backdropSecondary` to dark atmospheric HSB brightness (`0.10...0.24`) and moderate saturation so the full-screen translucent wash stays moody and high-contrast.
- Clamp `accent` to high HSB brightness (`0.78...0.98`) and readable saturation (`0.25...0.75`) so 4-point stars, connecting lines, and the active bold word always pop clearly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PaletteExtractorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedleCore/Models/AlbumPalette.swift Sources/NeedleCore/Visuals/PaletteExtractor.swift Tests/NeedleCoreTests/PaletteExtractorTests.swift
git commit -m "feat: add album-art PaletteExtractor with readability clamping"
```

---

### Task 4: Collision-Free *Stars* Constellation Layout Engine

**Files:**
- Create: `Sources/NeedleCore/Visuals/ConstellationLayout.swift`
- Test: `Tests/NeedleCoreTests/ConstellationLayoutTests.swift`

**Interfaces:**
- Consumes: `LyricLine`, `WordTiming`
- Produces:
  - `public struct ConstellationNode: Sendable, Equatable { public let id: Int; public let text: String; public let x: Double; public let y: Double; public let baseFontSize: Double; public let startTime: TimeInterval; public let endTime: TimeInterval }`
  - `public enum ConstellationLayout { public static let safeMinY: Double = 0.26; public static let safeMaxY: Double = 0.72; public static let minFontSize: Double = 15.0; public static let maxFontSize: Double = 34.0; public static func generate(for line: LyricLine, seed: UInt64, canvasWidth: Double, canvasHeight: Double) -> [ConstellationNode] }`

- [ ] **Step 1: Write failing tests in `Tests/NeedleCoreTests/ConstellationLayoutTests.swift`**

- `testDeterministicForSameSeedAndRespectsSafeZone`: generating twice with the same `seed` yields identical nodes; every node satisfies `0.08 <= x <= 0.92`, `safeMinY <= y <= safeMaxY`, and `minFontSize <= baseFontSize <= maxFontSize`.
- `testLongLine14WordsHasZeroBoundingBoxOverlaps`: a 14-word line on `1440×900` canvas produces 14 nodes whose estimated text bounding rects (with padding) do not intersect each other.
- `testFontSizesVaryAcrossLineWhileStayingReadable`: a mixed-length 8-word line produces at least 2 distinct font sizes (`Set(nodes.map(\.baseFontSize)).count >= 2`) and all `>= 15.0`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConstellationLayoutTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ConstellationLayout.swift`**

- Use a deterministic `SplitMix64` PRNG seeded from `seed`.
- Distribute words roughly left-to-right across the canvas with organic vertical wave/zigzag offsets (matching the Needle *Stars* reference geometry so consecutive edges form a clean, readable constellation rather than a tangled web).
- Vary `baseFontSize` organically between `15.0` and `26.0` (longer/emphasized content words larger, short connector words slightly smaller, always `>= 15.0`; the SwiftUI view scales the *active* word up to `~34pt` bold).
- Run bounded repulsion / candidate search so estimated word bounding boxes (`text.count * fontSize * 0.62 + 24`, `fontSize * 1.9`) never overlap and stay strictly within `[0.08, 0.92] × [0.26, 0.72]`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConstellationLayoutTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedleCore/Visuals/ConstellationLayout.swift Tests/NeedleCoreTests/ConstellationLayoutTests.swift
git commit -m "feat: add seeded collision-free Stars ConstellationLayout"
```

---

### Task 5: MediaPlayerProvider Protocol, OverlayVisibilityPolicy & Spotify Local Bridge

**Files:**
- Create: `Sources/NeedleCore/Player/MediaPlayerProvider.swift`
- Create: `Sources/NeedleCore/State/OverlayVisibilityPolicy.swift`
- Create: `Sources/NeedleApp/Player/SpotifyProvider.swift`
- Test: `Tests/NeedleCoreTests/OverlayVisibilityPolicyTests.swift`

**Interfaces:**
- Consumes: `TrackInfo`, `PlaybackSnapshot`, `PlaybackState`
- Produces:
  - `public protocol MediaPlayerProvider: Sendable { var playerName: String { get }; func startObserving(_ onChange: @escaping @Sendable () -> Void); func stopObserving(); func fetchSnapshot() async -> PlaybackSnapshot }`
  - `public struct OverlayInputs: Sendable, Equatable { public var isEnabled: Bool; public var isScreenLocked: Bool; public var isDisplayAsleep: Bool; public var isPreviewOpen: Bool; public var playbackState: PlaybackState }`
  - `public struct OverlayDecision: Sendable, Equatable { public let showLockScreenOverlay: Bool; public let shouldPollPlayer: Bool; public let shouldAnimate: Bool }`
  - `public enum OverlayVisibilityPolicy { public static func evaluate(_ inputs: OverlayInputs) -> OverlayDecision }`
  - `public enum SpotifyOutputParser { public static func parse(delimitedOutput: String, sampledAt: TimeInterval) -> PlaybackSnapshot }` (in `NeedleCore` so AppleScript parsing is unit-tested!)
  - `final class SpotifyProvider: MediaPlayerProvider` (in `NeedleApp`)

- [ ] **Step 1: Write failing tests in `Tests/NeedleCoreTests/OverlayVisibilityPolicyTests.swift`**

- `testShowsOverlayOnlyWhenEnabledLockedAwakeAndPlaying`: verifies `showLockScreenOverlay == true`, `shouldPollPlayer == true`, `shouldAnimate == true`.
- `testHidesAndSuspendsWhenDisplaySleepsOrPausedOrUnlocked`:
  - Display asleep while locked & playing → `showLockScreenOverlay == false`, `shouldPollPlayer == false`, `shouldAnimate == false`.
  - Paused while locked → `showLockScreenOverlay == false`, `shouldPollPlayer == false`, `shouldAnimate == false`.
  - Unlocked while playing → `showLockScreenOverlay == false`, `shouldPollPlayer == false`, `shouldAnimate == false`.
  - Preview open while unlocked & playing → `showLockScreenOverlay == false`, `shouldPollPlayer == true`, `shouldAnimate == true`.
- `testSpotifyOutputParserConvertsDurationMsToSecondsAndHandlesSpecialChars`: parses tab/unit-separator delimited output (`playing\u{1F}42.5\u{1F}spotify:track:1\u{1F}Rock & Roll "Live"\u{1F}AC/DC\u{1F}Álbum\u{1F}214000\u{1F}https://i.scdn.co/image/abc`) and asserts `durationSeconds == 214.0` and exact track fields.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverlayVisibilityPolicyTests`
Expected: FAIL.

- [ ] **Step 3: Implement `MediaPlayerProvider.swift`, `OverlayVisibilityPolicy.swift`, and `SpotifyProvider.swift`**

- `SpotifyProvider`:
  - Checks `NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")` first so it never launches Spotify if Spotify is closed.
  - Observes `DistributedNotificationCenter.default()` for `"com.spotify.client.PlaybackStateChanged"`.
  - Runs a single compact AppleScript returning fields joined by ASCII Unit Separator (`character id 31`), parsed via `SpotifyOutputParser.parse`.

- [ ] **Step 4: Run tests and build check**

Run: `swift test --filter OverlayVisibilityPolicyTests && swift build --target NeedleCore`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedleCore/Player Sources/NeedleCore/State Sources/NeedleApp/Player Tests/NeedleCoreTests/OverlayVisibilityPolicyTests.swift
git commit -m "feat: add OverlayVisibilityPolicy and local SpotifyProvider"
```

---

### Task 6: SkyLight Lock Screen Overlay, *Stars* SwiftUI View, Menu Bar App & `.app` Bundle

**Files:**
- Create: `Sources/NeedleApp/System/SkyLightBridge.swift`
- Create: `Sources/NeedleApp/System/LockAndSleepMonitor.swift`
- Create: `Sources/NeedleApp/System/PassiveOverlayWindow.swift`
- Create: `Sources/NeedleApp/UI/ConstellationLyricsView.swift`
- Create: `Sources/NeedleApp/App/LockScreenCoordinator.swift`
- Create: `Sources/NeedleApp/App/NeedleAppMain.swift`
- Create: `scripts/build-app.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: All `NeedleCore` types (`TrackInfo`, `PlaybackSnapshot`, `SyncedLyrics`, `AlbumPalette`, `PlaybackClock`, `LRCLIBClient`, `PaletteExtractor`, `ConstellationLayout`, `MediaPlayerProvider`, `OverlayVisibilityPolicy`) and `SpotifyProvider`.
- Produces: Runnable `build/Needle.app` bundle.

- [ ] **Step 1: Implement macOS system layer (`SkyLightBridge.swift`, `LockAndSleepMonitor.swift`, `PassiveOverlayWindow.swift`)**

- `SkyLightBridge`: dynamically loads `SkyLight.framework`, resolves `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, creates space at level `400`, attaches windows; returns `nil` gracefully without crashing if symbols are unavailable.
- `LockAndSleepMonitor`: observes `com.apple.screenIsLocked`, `com.apple.screenIsUnlocked` on `DistributedNotificationCenter`, plus `NSWorkspace.screensDidSleepNotification` and `NSWorkspace.screensDidWakeNotification` on `NSWorkspace.shared.notificationCenter`.
- `PassiveOverlayWindow`: borderless transparent `NSWindow` with `ignoresMouseEvents = true`, `canBecomeKey = false`, `canBecomeMain = false`, `canBecomeVisibleWithoutLogin = true`, `level = Int32.max - 2`, `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`.

- [ ] **Step 2: Implement `ConstellationLyricsView.swift`**

- Full-screen dark translucent wash tinted with `palette.backdropPrimary` / `palette.backdropSecondary` (Option A, **no edge glow**).
- Driven by `TimelineView(.animation(paused: !state.shouldAnimate))`:
  - Computes active line & active word index from `PlaybackClock.currentPosition(at:)`.
  - Uses `ConstellationLayout.generate(...)` for the active line; draws crisp thin luminous connecting lines and 4-point sparkle stars at each revealed node in `Canvas`, plus a brighter 4-point star + thin circular halo ring directly above the currently active word.
  - Renders revealed words with variable sizes (`node.baseFontSize`, scaling the active word up boldly in `palette.accent` with soft glow), smoothly fading constellations between lines.
  - If `syncedLyrics == nil` (no lyrics found / offline), renders an understated track title & artist display centered in the safe band over the album wash.
  - Renders a subtle track title · artist caption near the bottom of the safe band.

- [ ] **Step 3: Implement `LockScreenCoordinator.swift` and `NeedleAppMain.swift`**

- `LockScreenCoordinator` (`@MainActor`):
  - Coordinates `SpotifyProvider`, `LockAndSleepMonitor`, `LRCLIBClient`, `PaletteExtractor`, `PlaybackClock`, and `OverlayVisibilityPolicy`.
  - Manages one `PassiveOverlayWindow` per connected `NSScreen` (rebuilding on `NSApplication.didChangeScreenParametersNotification`) and attaches each via `SkyLightBridge`.
  - Runs a 2.5s drift-correction polling task **only** when `decision.shouldPollPlayer == true`; cancels it immediately otherwise.
  - Provides `openPreviewWindow()` (regular dismissible desktop window supporting `Esc` to close) so the user can test the *Stars* look & Spotify sync without locking.
- `NeedleAppMain`: `@main` `.accessory` menu bar app (`NSStatusBar.system.statusItem`) with SF Symbol `"sparkles"` icon and menu items: Track Status (disabled info line), **Enable on Lock Screen** (toggle, on by default), **Preview Overlay**, separator, **Quit**.

- [ ] **Step 4: Create `scripts/build-app.sh` and `README.md`**

- `scripts/build-app.sh`: runs `swift build -c release`, creates `build/Needle.app/Contents/{MacOS,Resources}`, writes `Info.plist` (`CFBundleIdentifier = com.local.needle`, `LSUIElement = true`, `NSAppleEventsUsageDescription = "Needle reads the currently playing track from Spotify to display synchronized lyrics on your Lock Screen."`), and runs `codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" build/Needle.app`.
- `README.md`: brief build/run guide, privacy summary (zero telemetry, only LRCLIB + album art), and optional 3-line instructions for creating a local self-signed Keychain cert (`CODESIGN_IDENTITY="Needle Local"`) so Spotify Automation permission persists across rebuilds.

- [ ] **Step 5: Run full test suite and build `Needle.app`**

Run: `swift test && chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: All `NeedleCoreTests` PASS and `build/Needle.app` is created and signed cleanly (`codesign --verify build/Needle.app` exits 0).

- [ ] **Step 6: Commit**

```bash
git add Sources/NeedleApp scripts/build-app.sh README.md
git commit -m "feat: add SkyLight Stars overlay, menu bar app, and Needle.app build script"
```
