import SwiftUI

/// One titled group on a settings page.
///
/// Lives on its own so every page draws the same card. The heading carries a
/// glyph in a tinted tile, which is what turns a page of stacked grey boxes
/// into a list somebody can scan; the glyph is passed in rather than looked up
/// from the title, so a renamed section cannot quietly lose it.
struct SettingsCard<Content: View>: View {
    let title: String
    var symbol: String = "square.grid.2x2"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            HStack(spacing: MacBDesign.Space.close) {
                Image(systemName: symbol)
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                    .foregroundStyle(MacBDesign.accent)
                    .frame(width: 22, height: 22)
                    .background(MacBDesign.accent.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MacBDesign.Space.loose)
                .background(MacBDesign.cardFill,
                            in: RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous))
                // A light fall from the top edge, the same idea as the island
                // cards, so the two halves of MacB read as one product.
                .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.05), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false))
                .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                    .strokeBorder(MacBDesign.cardStroke))
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
