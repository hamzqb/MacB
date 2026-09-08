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
    private var hasPreview: Bool { previewService.images[window.id] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            ZStack(alignment: .topTrailing) {
                Button(action: onSelect) {
                    ZStack {
                        if let image = previewService.images[window.id] {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            WindowPreviewPlaceholder(window: window, compact: density == .compact)
                        }
                        if hasPreview && (window.isMinimized || previewService.staleIDs.contains(window.id)) {
                            VStack {
                                Spacer()
                                HStack {
                                    Text(window.isMinimized ? "Küçültülmüş" : "Son görüntü")
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                    Spacer()
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(height: density.cardHeight)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(hasPreview ? 0.05 : 0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
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

struct WindowPreviewPlaceholder: View {
    let window: WindowRecord
    var compact = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.025), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 76 : 92, height: compact ? 76 : 92)
                    .opacity(0.14)
                    .blur(radius: 10)
                    .offset(x: 48, y: 18)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                HStack(spacing: 6) {
                    Circle().fill(.red.opacity(0.7)).frame(width: 6, height: 6)
                    Circle().fill(.yellow.opacity(0.7)).frame(width: 6, height: 6)
                    Circle().fill(.green.opacity(0.7)).frame(width: 6, height: 6)
                    Spacer()
                    if let icon = window.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                    } else {
                        Image(systemName: "macwindow").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.42))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(window.appName)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                    Text(window.title)
                        .font(.system(size: compact ? 9 : 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    placeholderLine(width: 0.82, opacity: 0.22)
                    placeholderLine(width: 0.58, opacity: 0.15)
                    HStack(spacing: 5) {
                        placeholderPill(width: 0.28)
                        placeholderPill(width: 0.22)
                        Spacer()
                    }
                }
                Text(window.isMinimized ? "Küçültülmüş pencere" : "Canlı önizleme hazırlanıyor")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
            }
            .padding(compact ? 10 : 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func placeholderLine(width: CGFloat, opacity: Double) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(opacity))
                .frame(width: proxy.size.width * width, height: 5)
        }
        .frame(height: 5)
    }

    private func placeholderPill(width: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 5)
                .fill(.white.opacity(0.13))
                .frame(width: max(18, proxy.size.width * width), height: 10)
        }
        .frame(height: 10)
    }
}
