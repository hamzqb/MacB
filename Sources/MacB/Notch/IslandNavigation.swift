import MacBCore
import SwiftUI

extension NotchContent {
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .stats: return "chart.xyaxis.line"
        case .apps: return "square.grid.3x3.fill"
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
        case .widgets: return "Widget'lar"
        case .stats: return "İstatistikler"
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

/// The row at the top of the open island, as Atoll lays it out: sections
/// on the left, tools and the battery on the right. Beside a camera each half
/// sits in one of its ears.
struct IslandNavigation: View {
    enum Part { case all, sections, tools }

    let selected: NotchContent
    var part: Part = .all
    var isEditing: Bool
    var battery: (percent: Double, isCharging: Bool)?
    var select: (NotchContent) -> Void
    var toggleEditing: () -> Void
    var cameraAction: () -> Void
    var openSettings: () -> Void

    /// Ties the puck to whichever button is selected, so it travels between
    /// them instead of one fading out while another fades in.
    @Namespace private var puck

    var body: some View {
        HStack(spacing: 4) {
            if part != .tools {
                ForEach(NotchContent.tabs, id: \.rawValue) { section in
                    tabButton(section.symbol, label: section.title,
                              isSelected: section == selected) { select(section) }
                }
                if selected == .widgets {
                    tabButton(isEditing ? "checkmark" : "slider.horizontal.3",
                              label: isEditing ? "Düzenlemeyi bitir" : "Widget'ları düzenle",
                              isSelected: false, action: toggleEditing)
                        .transition(.blurReplace)
                }
            }
            if part == .all { Spacer(minLength: 12) }
            if part != .sections {
                ForEach(NotchContent.toolTabs, id: \.rawValue) { section in
                    tabButton(section.symbol, label: section.title,
                              isSelected: section == selected) { select(section) }
                }
                tabButton("camera.fill", label: "Kamera", isSelected: false, action: cameraAction)
                tabButton("gearshape.fill", label: "Ayarlar", isSelected: false, action: openSettings)
                if let battery {
                    BatteryGauge(percent: battery.percent, isCharging: battery.isCharging)
                        .padding(.leading, 6)
                }
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
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: MacBDesign.IslandToken.navButton)
                .background {
                    if isSelected {
                        Capsule().fill(Color.white.opacity(0.14))
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

/// The battery at the end of the row: the percentage and a small battery
/// that fills, green with a bolt while charging, red when low.
struct BatteryGauge: View {
    let percent: Double
    let isCharging: Bool

    private var level: Double { min(1, max(0, percent / 100)) }
    private var fill: Color {
        if isCharging { return Color(red: 0.30, green: 0.85, blue: 0.39) }
        if percent <= 20 { return Color(red: 1, green: 0.27, blue: 0.23) }
        return .white
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fill)
                            .frame(width: max(2, (proxy.size.width - 4) * level))
                            .padding(2)
                    }
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 25, height: 12)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(.white.opacity(0.45))
                    .frame(width: 1.5, height: 4.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pil yüzde \(Int(percent.rounded()))\(isCharging ? ", şarj oluyor" : "")")
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
