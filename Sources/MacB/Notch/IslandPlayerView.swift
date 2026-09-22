import AppKit
import MacBCore
import SwiftUI

/// The home section: the player, large, the way Atoll opens. A big cover with
/// the playing app's icon on its corner; beside it the title, the artist in
/// the cover's colour, a progress bar that can be dragged, and the transport.
/// With nothing playing it keeps its shape and says so, so the island does
/// not jump when music starts.
struct IslandPlayerView: View {
    @ObservedObject var media: MediaService
    var width: CGFloat

    @State private var scrub: Double?
    @State private var hoveringPlay = false

    private var hasTrack: Bool { !media.title.isEmpty && media.source != .none }
    /// The browser reader offers play and pause only.
    private var hasSkip: Bool { media.source != .browser }

    /// The cover's colour lifted until it reads on black.
    private var tint: Color {
        guard let base = media.tint else { return .white.opacity(0.6) }
        let color = NSColor(base).usingColorSpace(.deviceRGB) ?? .white
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation, 0.75), brightness: max(brightness, 0.82))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            cover
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 8)
                progress
                Spacer(minLength: 6)
                transport
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: IslandGeometry.playerHeight)
    }

    // MARK: - Cover

    private var cover: some View {
        let side = IslandGeometry.playerHeight - 8
        return Button(action: openPlayingApp) {
            ZStack {
                if let artwork = media.artwork, hasTrack {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Rectangle().fill(Color.white.opacity(0.07))
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .scaleEffect(media.isPlaying || !hasTrack ? 1 : 0.94)
            .motion(.spring(response: 0.45, dampingFraction: 0.72), value: media.isPlaying)
            .overlay(alignment: .bottomTrailing) {
                if let icon = media.appIcon, hasTrack {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        .offset(x: 7, y: 7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(IslandPressStyle())
        .disabled(!hasTrack)
        .motion(MacBDesign.Motion.gentle, value: media.artwork != nil)
        .help(hasTrack ? "Çalan uygulamayı aç" : "")
        .accessibilityLabel(hasTrack ? "\(media.title) kapağı. Çalan uygulamayı aç" : "Kapak yok")
    }

    private func openPlayingApp() {
        if let bundle = media.nowPlaying.bundleID, media.source == .system,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Title

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hasTrack ? media.title : "Çalan bir şey yok")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(hasTrack ? 1 : 0.55))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text(hasTrack ? (media.artist.isEmpty ? media.source.title : media.artist)
                              : "Spotify, Müzik ya da tarayıcıda bir şey çal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hasTrack ? tint : .white.opacity(0.35))
                    .lineLimit(1)
                    .motion(MacBDesign.Motion.gentle, value: media.tint)
            }
            Spacer(minLength: 0)
            if hasTrack {
                EqualizerBars(tint: tint, isPlaying: media.isPlaying, height: 16)
                    .padding(.top, 4)
                    .opacity(media.isPlaying ? 1 : 0.35)
                    .accessibilityHidden(true)
            }
        }
        .motion(MacBDesign.Motion.gentle, value: media.title)
    }

    // MARK: - Progress

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = max(0, media.duration)
            let position = min(duration, max(0, scrub ?? media.livePosition))
            let fraction = duration > 0 ? position / duration : 0
            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Color.white.opacity(hasTrack ? 0.9 : 0))
                            .frame(width: max(0, proxy.size.width * fraction))
                    }
                    .frame(height: scrub == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard media.canSeek, proxy.size.width > 0 else { return }
                            scrub = min(1, max(0, value.location.x / proxy.size.width)) * duration
                        }
                        .onEnded { _ in
                            if let target = scrub { media.seek(to: target) }
                            scrub = nil
                        })
                    .motion(.spring(response: 0.25, dampingFraction: 0.8), value: scrub == nil)
                }
                .frame(height: 10)
                HStack {
                    Text(hasTrack && duration > 0 ? TimerService.format(position) : "--:--")
                    Spacer()
                    Text(hasTrack && duration > 0 ? TimerService.format(duration) : "--:--")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(duration > 0
                ? "\(TimerService.format(position)) / \(TimerService.format(duration))"
                : "Süre bilinmiyor")
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 30) {
            transportButton("backward.fill", label: "Önceki", size: 19, action: media.previousTrack)
                .disabled(!hasTrack || !hasSkip)
            Button(action: media.playPause) {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(hoveringPlay && hasTrack ? 0.12 : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(IslandPressStyle())
            .onHover { hoveringPlay = $0 }
            .motion(.smooth(duration: 0.18), value: hoveringPlay)
            .disabled(!hasTrack)
            .accessibilityLabel(media.isPlaying ? "Duraklat" : "Oynat")
            transportButton("forward.fill", label: "Sonraki", size: 19, action: media.nextTrack)
                .disabled(!hasTrack || !hasSkip)
        }
        .foregroundStyle(.white.opacity(hasTrack ? 0.95 : 0.3))
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ symbol: String, label: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
