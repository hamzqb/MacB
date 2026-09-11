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

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: IslandGeometry.gap) {
                dropCard(title: "AirDrop", icon: Self.airDropIcon,
                         symbol: "dot.radiowaves.up.forward", tint: Color(nsColor: .systemBlue)) {
                    sendToAirDrop(pendingURLs)
                }
                dropCard(title: "Dosya Rafı", icon: nil,
                         symbol: "arrow.down.document", tint: .white) {
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

    private func dropCard(title: String, icon: NSImage?, symbol: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 40, height: 40)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacBDesign.IslandToken.dropCardFill,
                        in: RoundedRectangle(cornerRadius: MacBDesign.IslandToken.dropCardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacBDesign.IslandToken.dropCardRadius, style: .continuous)
                    .strokeBorder(MacBDesign.IslandToken.accent.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
