import Combine
import Foundation
import MacBCore

/// Persists the home strip order, sizes and enabled set.
@MainActor final class IslandLayoutStore: ObservableObject {
    @Published private(set) var layout: IslandWidgetLayout
    @Published var isEditing = false

    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("widgets.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(IslandWidgetLayout.self, from: data) {
            layout = stored.merging()
        } else {
            layout = .standard
        }
    }

    func rows(columns: Int) -> [IslandWidgetRow] { layout.rows(columns: columns) }

    var enabledUnitCount: Int {
        layout.enabledWidgets.reduce(0) { $0 + $1.size.columns }
    }

    func isActive(_ kind: IslandWidgetKind) -> Bool { layout.activeKinds.contains(kind) }

    func move(id: UUID, to index: Int) {
        var updated = layout
        updated.move(id: id, to: index)
        apply(updated)
    }

    func resize(id: UUID, to size: IslandWidgetSize) {
        var updated = layout
        updated.resize(id: id, to: size)
        apply(updated)
    }

    func moveVisible(id: UUID, by offset: Int) {
        var updated = layout
        updated.moveVisible(id: id, by: offset)
        apply(updated)
    }

    /// Adds a widget from the library at its intended size, at the end of the strip.
    func add(id: UUID) {
        var updated = layout
        updated.add(id: id)
        apply(updated)
    }

    func setEnabled(id: UUID, _ isEnabled: Bool) {
        var updated = layout
        updated.setEnabled(id: id, isEnabled)
        apply(updated)
    }

    func reset() { apply(.standard) }

    private func apply(_ updated: IslandWidgetLayout) {
        guard updated != layout else { return }
        layout = updated
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
