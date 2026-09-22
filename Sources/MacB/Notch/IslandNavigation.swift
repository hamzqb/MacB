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
    /// Which half to draw: beside a camera the sections go in the left ear
    /// and the tools in the right.
    enum Part { case all, sections, tools }

    let selected: NotchContent
    var part: Part = .all
    var isEditing: Bool
    var select: (NotchContent) -> Void
    var toggleEditing: () -> Void
    var cameraAction: () -> Void
    var openSettings: () -> Void

    /// Ties the white puck to whichever button is selected, so it travels
    /// between them instead of one circle fading out while another fades in.
    @Namespace private var puck

    var body: some View {
        HStack(spacing: MacBDesign.Space.tight) {
            if part != .tools {
                ForEach(NotchContent.tabs, id: \.rawValue) { section in
                    tabButton(section.symbol, label: section.title,
                              isSelected: section == selected) { select(section) }
                }
            }
            if part == .all { Spacer(minLength: 12) }
            if part != .sections {
                tabButton(isEditing ? "checkmark" : "square.grid.2x2",
                          label: isEditing ? "Düzenlemeyi bitir" : "Widget'ları düzenle",
                          isSelected: isEditing, action: toggleEditing)
                tabButton("camera.fill", label: "Kamera", isSelected: false, action: cameraAction)
                tabButton("gearshape.fill", label: "Ayarlar", isSelected: false, action: openSettings)
            }
        }
        .frame(height: part == .all ? IslandGeometry.navigationHeight : nil)
        .motion(.smooth(duration: 0.28), value: selected)
        .motion(.smooth(duration: 0.28), value: isEditing)
    }

    /// Plain white glyphs with no chrome; the selected one sits on a quiet
    /// capsule that slides from tab to tab.
    private func tabButton(_ symbol: String, label: String, isSelected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : MacBDesign.IslandToken.Ink.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: MacBDesign.IslandToken.navButton)
                .background {
                    if isSelected {
                        Capsule().fill(MacBDesign.IslandToken.navSelectedFill)
                            .matchedGeometryEffect(id: "navPuck", in: puck)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle())
        .islandFocusRing(in: Capsule())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The press every island control shares: a small dip, no colour change.
struct IslandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
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
