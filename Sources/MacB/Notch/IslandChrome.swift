import SwiftUI
import MacBCore

struct IslandGlassShelf<Content: View>: View {
    var isSelected = false
    var tint: Color = MacBDesign.IslandToken.accent
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(shellFill, in: Capsule())
            .overlay(Capsule().strokeBorder(shellStroke, lineWidth: 0.8))
            .shadow(color: tint.opacity(isSelected ? 0.22 : 0.08), radius: isSelected ? 12 : 7, y: 5)
    }

    private var shellFill: some ShapeStyle {
        LinearGradient(colors: [
            Color.white.opacity(isSelected ? 0.16 : 0.08),
            Color.black.opacity(isSelected ? 0.34 : 0.46),
            Color.black.opacity(0.62)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shellStroke: some ShapeStyle {
        LinearGradient(colors: [.white.opacity(isSelected ? 0.34 : 0.18), .white.opacity(0.045)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct IslandLivePill<Leading: View, Trailing: View>: View {
    var title: String
    var detail: String?
    var tint: Color = MacBDesign.IslandToken.accent
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            leading.frame(width: 18, height: 18)
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            trailing
        }
        .padding(.horizontal, MacBDesign.Space.regular)
        .frame(height: 30)
        .background {
            Capsule().fill(LinearGradient(colors: [tint.opacity(0.18), .white.opacity(0.065), .white.opacity(0.035)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [tint.opacity(0.36), .white.opacity(0.08)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .shadow(color: tint.opacity(0.12), radius: 9, y: 4)
    }
}

extension MacBDesign.Motion {
    /// Heavier than the old island snap: the panel feels like it has mass, while
    /// still ending quickly enough to track the notch hover.
    static let atollFluid = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)
}
