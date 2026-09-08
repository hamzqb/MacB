import SwiftUI

struct WindowCardView: View {
    let window: WindowRecord
    @ObservedObject var previewService: PreviewService
    var isSelected = false
    var isFavorite = false
    var onSelect: () -> Void
    var onMinimize: () -> Void
    var onClose: () -> Void
    var onToggleFavorite: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    @State private var hovered = false
    @FocusState private var focused: Bool
    @FocusState private var controlFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @AppStorage("interfaceDensity") private var densityValue = InterfaceDensity.balanced.rawValue
    private var emphasized: Bool { hovered || focused || controlFocused || accessibilityFocused || isSelected }
    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityValue) ?? .balanced }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            ZStack(alignment: .topTrailing) {
                Button(action: onSelect) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.045))
                        if let image = previewService.images[window.id] {
                            Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            VStack(spacing: 8) {
                                if let icon = window.appIcon { Image(nsImage: icon).resizable().frame(width: 44, height: 44) }
                                else { Image(systemName: "macwindow").font(.system(size: 32, weight: .light)) }
                                Text(window.isMinimized ? "Küçültülmüş pencere" : "Önizleme kullanılamıyor").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        if previewService.images[window.id] != nil && (window.isMinimized || previewService.staleIDs.contains(window.id)) {
                            VStack { Spacer(); HStack { Text(window.isMinimized ? "Küçültülmüş" : "Son görüntü").font(.system(size: 9, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 4).background(.ultraThinMaterial, in: Capsule()); Spacer() } }.padding(8)
                        }
                    }.frame(height: density.cardHeight).contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).focused($focused)
                    .accessibilityLabel("\(window.appName), \(window.title), pencereye geç")
                HStack(spacing: 5) {
                    actionButton(symbol: isFavorite ? "star.fill" : "star", label: isFavorite ? "Favoriden kaldır" : "Favoriye ekle", enabled: true, action: onToggleFavorite)
                    actionButton(symbol: window.isMinimized ? "arrow.up.right.and.arrow.down.left" : "minus", label: window.isMinimized ? "Geri yükle" : "Küçült", enabled: window.canMinimize, action: onMinimize)
                    actionButton(symbol: "xmark", label: "Pencereyi kapat", enabled: window.canClose, action: onClose)
                }.padding(7).opacity(emphasized ? 1 : 0.001)
                    .accessibilityHidden(false).accessibilityFocused($accessibilityFocused)
            }
            HStack(spacing: 7) {
                if let icon = window.appIcon { Image(nsImage: icon).resizable().frame(width: 18, height: 18).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 3)
        }.padding(density == .compact ? 7 : 8).frame(width: density.cardWidth)
            .background(emphasized ? Color.white.opacity(0.065) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isSelected ? MacBDesign.accent.opacity(0.9) : Color.white.opacity(emphasized ? 0.12 : 0.025), lineWidth: isSelected ? 2 : 1))
            .onHover { hovered = $0; onHover($0) }
            .animation(animationsEnabled && !reduceMotion ? .easeOut(duration: 0.16) : nil, value: emphasized)
    }

    private func actionButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 26, height: 26).background(.ultraThinMaterial, in: Circle()) }
            .buttonStyle(.plain).focused($controlFocused).disabled(!enabled).help(label).accessibilityLabel(label)
    }
}
