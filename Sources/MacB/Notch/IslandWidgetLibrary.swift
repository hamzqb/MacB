import MacBCore
import SwiftUI

/// The shelf of everything the island can show, opened by the edit button.
///
/// It sits under the strip rather than in a separate window so that adding a
/// widget and seeing where it lands are the same glance. Categories are pills,
/// the cards scroll sideways, and a widget already on the strip stays in the
/// list marked as added instead of disappearing — otherwise removing one means
/// hunting for where it went.
struct IslandWidgetLibrary: View {
    @ObservedObject var store: IslandLayoutStore
    @State private var category: IslandWidgetCategory = .essentials

    private var groups: [IslandWidgetGroup] { store.layout.groups }

    private var visible: [IslandWidget] {
        groups.first { $0.category == category }?.widgets ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandGeometry.gap) {
            IslandPillRow(values: groups.map(\.category), selected: category,
                          title: \.title) { category = $0 }
                .frame(height: IslandGeometry.filterRowHeight)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IslandGeometry.libraryCardGap) {
                    ForEach(visible) { widget in
                        card(widget)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .frame(height: IslandGeometry.libraryCardHeight)
        }
        .onAppear { if !groups.contains(where: { $0.category == category }) { category = groups.first?.category ?? .essentials } }
        .accessibilityLabel("Widget kütüphanesi")
    }

    private func card(_ widget: IslandWidget) -> some View {
        Button {
            if widget.isEnabled { store.setEnabled(id: widget.id, false) } else { store.add(id: widget.id) }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: widget.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(widget.isEnabled ? Color.black : MacBDesign.IslandToken.accent)
                    .frame(width: 26, height: 26)
                    .background(widget.isEnabled ? MacBDesign.IslandToken.accent : MacBDesign.IslandToken.navFill,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.kind.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacBDesign.IslandToken.primaryText)
                        .lineLimit(1)
                    Text(widget.kind.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                Image(systemName: widget.isEnabled ? "checkmark" : "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(widget.isEnabled ? MacBDesign.IslandToken.accent : MacBDesign.IslandToken.tertiaryText)
            }
            .padding(10)
            .frame(width: IslandGeometry.libraryCardWidth, height: IslandGeometry.libraryCardHeight,
                   alignment: .topLeading)
            .background(MacBDesign.IslandToken.widgetFill,
                        in: RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous)
                    .strokeBorder(widget.isEnabled ? MacBDesign.IslandToken.accent.opacity(0.45) : .clear,
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(widget.isEnabled ? "\(widget.kind.title) şeritte" : "\(widget.kind.title) ekle")
        .accessibilityLabel(widget.kind.title)
        .accessibilityValue(widget.isEnabled ? "Ekli" : "Ekli değil")
        .accessibilityHint(widget.kind.summary)
    }
}
