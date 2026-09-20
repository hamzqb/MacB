import MacBCore
import SwiftUI

extension NotchContent {
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .apps: return "square.grid.2x2.fill"
        case .files: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .timer: return "timer"
        case .assistant: return "waveform"
        case .briefing: return "sun.horizon.fill"
        case .agent: return "checklist"
        }
    }

    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .apps: return "Uygulamalar"
        case .files: return "Dosyalar"
        case .clipboard: return "Pano"
        case .timer: return "Zamanlayıcı"
        case .assistant: return "MacB"
        case .briefing: return "Brifing"
        case .agent: return "Arka plan işi"
        }
    }
}

/// The icon row at the top of the expanded panel: sections on the left, tools on the right.
struct IslandNavigation: View {
    let selected: NotchContent
    var isEditing: Bool
    var select: (NotchContent) -> Void
    var toggleEditing: () -> Void
    var cameraAction: () -> Void
    var openSettings: () -> Void

    /// Ties the white puck to whichever button is selected, so it travels
    /// between them instead of one circle fading out while another fades in.
    @Namespace private var puck

    var body: some View {
        HStack(spacing: MacBDesign.Space.close) {
            ForEach(NotchContent.tabs, id: \.rawValue) { section in
                circleButton(section.symbol, label: section.title,
                             isSelected: section == selected) { select(section) }
            }
            Spacer(minLength: 12)
            circleButton("square.grid.2x2", label: isEditing ? "Düzenlemeyi bitir" : "Widget'ları düzenle",
                         isSelected: isEditing, action: toggleEditing)
            circleButton("camera.fill", label: "Kamera", isSelected: false, action: cameraAction)
            circleButton("gearshape.fill", label: "Ayarlar", isSelected: false, action: openSettings)
        }
        .frame(height: IslandGeometry.navigationHeight)
        .motion(MacBDesign.Motion.snap, value: selected)
    }

    private func circleButton(_ symbol: String, label: String, isSelected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(isSelected ? Color.black : MacBDesign.IslandToken.primaryText)
                .frame(width: MacBDesign.IslandToken.navButton, height: MacBDesign.IslandToken.navButton)
                .background {
                    // One puck for the whole row. Only the selected button owns
                    // it, so SwiftUI moves the same circle rather than drawing a
                    // second one, and the selection reads as a thing that slid
                    // rather than two things that blinked.
                    if isSelected {
                        Circle().fill(MacBDesign.IslandToken.navSelectedFill)
                            .matchedGeometryEffect(id: "navPuck", in: puck)
                    } else {
                        Circle().fill(MacBDesign.IslandToken.navFill)
                    }
                }
        }
        .buttonStyle(.plain)
        .islandFocusRing(in: Circle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A filter pill row. The selected pill inverts to white, as in the reference clipboard.
struct IslandPillRow<Value: Hashable>: View {
    let values: [Value]
    let selected: Value
    let title: (Value) -> String
    var select: (Value) -> Void

    var body: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            ForEach(values, id: \.self) { value in
                Button { select(value) } label: {
                    Text(title(value))
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                        .foregroundStyle(value == selected ? Color.black : MacBDesign.IslandToken.primaryText)
                        .padding(.horizontal, MacBDesign.Space.comfortable)
                        .frame(height: MacBDesign.IslandToken.pillHeight)
                        .background(value == selected ? MacBDesign.IslandToken.navSelectedFill : MacBDesign.IslandToken.navFill,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .islandFocusRing(in: Capsule())
                .accessibilityLabel(title(value))
                .accessibilityAddTraits(value == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
