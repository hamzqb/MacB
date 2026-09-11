import MacBCore
import SwiftUI

/// Quick access to the apps and folders the user pinned.
///
/// One row of tiles, plus a tile that opens the picker. No search, no
/// categories, no folders: the only thing here is what the user put here.
struct IslandLauncherView: View {
    @ObservedObject var launcher: AppLauncherStore
    var notify: (String, String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(launcher.items) { item in
                    tile(item)
                }
                addTile
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Hızlı erişim")
    }

    private func tile(_ item: LauncherItem) -> some View {
        Button {
            launcher.open(item)
            if let message = launcher.errorMessage { notify("exclamationmark", message) }
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .opacity(item.isAvailable ? 1 : 0.35)
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(item.isAvailable
                                     ? MacBDesign.IslandToken.primaryText
                                     : MacBDesign.IslandToken.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 74, height: IslandGeometry.launcherTileHeight)
            .background(MacBDesign.IslandToken.widgetFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item.isAvailable ? item.url.path : "\(item.name) bulunamadı")
        .accessibilityLabel(item.name)
        .contextMenu {
            Button("Finder'da göster") { launcher.reveal(item) }
            Button("Listeden çıkar", role: .destructive) {
                launcher.remove(item)
                notify("minus.circle", "\(item.name) listeden çıkarıldı")
            }
        }
    }

    private var addTile: some View {
        Button {
            launcher.choose()
            if let message = launcher.errorMessage { notify("exclamationmark", message) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.accent)
                    .frame(width: 34, height: 34)
                Text("Ekle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            }
            .frame(width: 74, height: IslandGeometry.launcherTileHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(MacBDesign.IslandToken.accent.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Uygulama veya klasör ekle")
    }
}
