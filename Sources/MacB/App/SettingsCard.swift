import SwiftUI

/// One titled group on a settings page.
///
/// The heading sits above the group in quiet type, and the controls sit in one
/// flat container: no tinted glyph tile, no gradient, no shadow. A page of
/// settings is a list to be scanned, and every box that decorates itself is
/// one more thing between somebody and the switch they came for.
struct SettingsCard<Content: View>: View {
    let title: String
    var symbol: String = "square.grid.2x2"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(MacBDesign.muted)
                .textCase(.uppercase)
                .kerning(0.4)
                .padding(.leading, MacBDesign.Space.tight)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MacBDesign.Space.loose)
                .background(MacBDesign.groupFill,
                            in: RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                    .strokeBorder(MacBDesign.groupStroke))
        }
    }
}

/// A section's explanation: two lines, and the rest on request.
///
/// The settings window had a paragraph at the top of every card. None of them
/// is wrong and most are worth reading once, but a window that opens on eight
/// paragraphs is a window where the switches are hard to find. Clamped to two
/// lines it reads as a subtitle; one click and it is the paragraph again.
struct SettingsIntro: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
            Text(text)
                .font(.system(size: MacBDesign.TypeScale.body))
                .foregroundStyle(MacBDesign.muted)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Button(isExpanded ? "Daha az" : "Devamı") {
                isExpanded.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
            .foregroundStyle(MacBDesign.accent)
            .accessibilityLabel(isExpanded ? "Açıklamayı kapat" : "Açıklamanın devamını göster")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
        .motion(MacBDesign.Motion.quick, value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
