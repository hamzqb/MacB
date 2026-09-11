import AppKit
import MacBCore
import SwiftUI
import UniformTypeIdentifiers

/// Shown while files are over the island: two large targets plus the recent window targets.
struct IslandDropView: View {
    @ObservedObject var recentTargets: RecentTargetStore
    let pendingURLs: [URL]
    var sendToAirDrop: ([URL]) -> Void
    var addToShelf: ([URL]) -> Void
    var openTarget: (RecentTargetItem) -> Void

    @State private var hovered: String?

    /// What is waiting to be dropped, so the cards say what they would take.
    private var pendingLabel: String {
        pendingURLs.count == 1
            ? pendingURLs[0].lastPathComponent
            : "\(pendingURLs.count) öğe"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: IslandGeometry.gap) {
                dropCard(title: "AirDrop", icon: Self.airDropIcon,
                         symbol: "dot.radiowaves.up.forward", tint: Color(nsColor: .systemBlue)) {
                    sendToAirDrop(pendingURLs)
                }
                dropCard(title: "Dosya Rafı", icon: nil,
                         symbol: "arrow.down.document", tint: MacBDesign.IslandToken.accent) {
                    addToShelf(pendingURLs)
                }
            }
            if !recentTargets.items.isEmpty {
                HStack(spacing: 8) {
                    Text("Son hedefler")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    ForEach(recentTargets.items.prefix(5)) { target in
                        Button { openTarget(target) } label: {
                            HStack(spacing: 5) {
                                if let icon = applicationIcon(for: target) {
                                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                                }
                                Text(target.appName).font(.system(size: 11)).lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(MacBDesign.IslandToken.navFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(target.appName) penceresine getir")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func applicationIcon(for target: RecentTargetItem) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The real AirDrop application icon, so the card matches what the system shows elsewhere.
    private static let airDropIcon: NSImage? = {
        let path = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }()

    /// One target, which has to look like it wants the files.
    ///
    /// A static outline gives no answer to "will this one take them". The dashes
    /// march all the time so the card reads as a live target, and the one under
    /// the pointer lifts, brightens and names what it would receive.
    private func dropCard(title: String, icon: NSImage?, symbol: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        let isHovered = hovered == title
        return Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 38, height: 38)
                .offset(y: isHovered ? -2 : 0)
                .shadow(color: tint.opacity(isHovered ? 0.55 : 0), radius: 10)
                VStack(spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(isHovered ? pendingLabel : "buraya bırak")
                        .font(.system(size: 9))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHovered ? tint.opacity(0.14) : MacBDesign.IslandToken.dropCardFill,
                        in: RoundedRectangle(cornerRadius: MacBDesign.IslandToken.dropCardRadius, style: .continuous))
            .overlay(MarchingDashes(cornerRadius: MacBDesign.IslandToken.dropCardRadius,
                                    tint: tint.opacity(isHovered ? 1 : 0.6),
                                    lineWidth: isHovered ? 1.6 : 1,
                                    isFast: isHovered))
            .scaleEffect(isHovered ? 1.03 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? title : (hovered == title ? nil : hovered) }
        .accessibilityLabel("\(title): \(pendingLabel)")
    }
}

/// A dashed border whose dashes travel around the shape.
///
/// The movement is the whole point: a still dashed line is decoration, a moving
/// one is an invitation. It runs at a walk normally and a jog under the pointer.
struct MarchingDashes: View {
    let cornerRadius: CGFloat
    let tint: Color
    var lineWidth: CGFloat = 1
    var isFast = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceMotion {
            shape.strokeBorder(tint, style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let speed: Double = isFast ? 26 : 11
                let phase = context.date.timeIntervalSinceReferenceDate * speed
                shape.strokeBorder(tint, style: StrokeStyle(lineWidth: lineWidth,
                                                            dash: [6, 4],
                                                            dashPhase: -phase.truncatingRemainder(dividingBy: 10)))
            }
        }
    }
}

enum AirDropSender {
    /// Uses the public sharing service. Returns false when AirDrop cannot accept the files.
    @MainActor static func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        guard service.canPerform(withItems: urls) else { return false }
        service.perform(withItems: urls)
        return true
    }
}
