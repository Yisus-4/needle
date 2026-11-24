import Foundation
import NeedleCore
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var track: TrackInfo?
    @Published var syncedLyrics: SyncedLyrics?
    @Published var palette: AlbumPalette = .fallback
    @Published var shouldAnimate: Bool = false
    @Published var isVisible: Bool = false

    private var clock = PlaybackClock()

    func updateClock(with snapshot: PlaybackSnapshot) {
        clock.sync(with: snapshot)
    }

    func currentPlaybackPosition() -> TimeInterval {
        clock.currentPosition(at: ProcessInfo.processInfo.systemUptime)
    }
}

private extension NeedleCore.RGBColor {
    var swiftUIColor: Color {
        Color(red: r, green: g, blue: b)
    }
}

struct ConstellationLyricsView: View {
    @ObservedObject var model: OverlayViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Option A: Full-screen dark translucent wash tinted by album art (no edge glow)
                LinearGradient(
                    colors: [
                        model.palette.backdropPrimary.swiftUIColor.opacity(0.78),
                        model.palette.backdropSecondary.swiftUIColor.opacity(0.84)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.9), value: model.palette)

                if let lyrics = model.syncedLyrics {
                    TimelineView(.animation(paused: !model.shouldAnimate)) { _ in
                        constellationStage(lyrics: lyrics, size: geo.size)
                    }
                } else if let track = model.track {
                    fallbackTrackView(track: track)
                }

                // Subtle caption at bottom of safe zone (above macOS password/Touch ID)
                if let track = model.track, model.syncedLyrics != nil {
                    VStack {
                        Spacer()
                        Text("\(track.name)  ·  \(track.artist)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .padding(.horizontal, 40)
                            .padding(.bottom, geo.size.height * 0.19)
                    }
                }
            }
            .opacity(model.isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: model.isVisible)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func constellationStage(lyrics: SyncedLyrics, size: CGSize) -> some View {
        let now = model.currentPlaybackPosition()
        if let active = lyrics.activeLine(at: now) {
            let trackHash = UInt64(bitPattern: Int64(model.track?.id.hashValue ?? 0))
            let seed = trackHash ^ UInt64(active.index &+ 1) &* 0x9E3779B97F4A7C15
            let nodes = ConstellationLayout.generate(
                for: active.line,
                seed: seed,
                canvasWidth: Double(size.width),
                canvasHeight: Double(size.height)
            )
            let revealedCount = max(1, nodes.filter { now >= $0.startTime }.count)
            let activeWordIndex = min(revealedCount - 1, nodes.count - 1)
            let accentColor = model.palette.accent.swiftUIColor

            ZStack {
                // Luminous lines + 4-point sparkle stars + active circular target halo
                Canvas { ctx, canvasSize in
                    let points = nodes.prefix(revealedCount).map { node in
                        CGPoint(x: node.x * canvasSize.width, y: node.y * canvasSize.height)
                    }

                    // Connecting lines
                    if points.count >= 2 {
                        for i in 1..<points.count {
                            var path = Path()
                            path.move(to: points[i - 1])
                            path.addLine(to: points[i])
                            let isNewest = (i == points.count - 1)
                            ctx.stroke(
                                path,
                                with: .color(accentColor.opacity(isNewest ? 0.65 : 0.36)),
                                style: StrokeStyle(lineWidth: isNewest ? 1.25 : 0.9, lineCap: .round)
                            )
                        }
                    }

                    // 4-point sparkle stars at each revealed node
                    for (idx, pt) in points.enumerated() {
                        let isActive = (idx == activeWordIndex)
                        let starRadius: CGFloat = isActive ? 11.0 : 5.0
                        let starPath = fourPointStarPath(center: pt, outerRadius: starRadius, innerRadius: starRadius * 0.22)
                        ctx.fill(starPath, with: .color(.white.opacity(isActive ? 0.98 : 0.72)))

                        if isActive {
                            // Thin circular target halo ring around the active star (matching Needle Stars reference)
                            let ringRadius: CGFloat = 19.0
                            let ringRect = CGRect(
                                x: pt.x - ringRadius,
                                y: pt.y - ringRadius,
                                width: ringRadius * 2,
                                height: ringRadius * 2
                            )
                            ctx.stroke(
                                Path(ellipseIn: ringRect),
                                with: .color(accentColor.opacity(0.65)),
                                lineWidth: 1.0
                            )
                        }
                    }
                }

                // Word labels anchored cleanly below each star node
                ForEach(Array(nodes.prefix(revealedCount).enumerated()), id: \.element.id) { idx, node in
                    let isActive = (idx == activeWordIndex)
                    let displaySize = isActive
                        ? min(max(node.baseFontSize * 1.42, 26.0), ConstellationLayout.maxFontSize)
                        : node.baseFontSize

                    Text(node.text)
                        .font(.system(size: displaySize, weight: isActive ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isActive ? accentColor : Color.white.opacity(0.76))
                        .shadow(color: isActive ? accentColor.opacity(0.55) : .black.opacity(0.6), radius: isActive ? 12 : 4, y: 2)
                        .position(
                            x: node.x * size.width,
                            y: node.y * size.height + (isActive ? 34 : 18)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .id("\(model.track?.id ?? "")-\(active.index)")
            .transition(.opacity)
            .animation(.easeOut(duration: 0.28), value: activeWordIndex)
        }
    }

    private func fallbackTrackView(track: TrackInfo) -> some View {
        VStack(spacing: 10) {
            Text(track.name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(model.palette.accent.swiftUIColor)
                .shadow(color: model.palette.accent.swiftUIColor.opacity(0.4), radius: 12)
                .multilineTextAlignment(.center)
            Text(track.artist)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 60)
    }

    private func fourPointStarPath(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> Path {
        var path = Path()
        for i in 0..<8 {
            let angle = CGFloat(i) * (.pi / 4.0) - (.pi / 2.0)
            let radius = (i % 2 == 0) ? outerRadius : innerRadius
            let pt = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        return path
    }
}
