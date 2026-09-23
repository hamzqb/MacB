import Combine
import Foundation
import MacBCore

/// What is on the desktop, and where. Written to Application Support as soon
/// as it changes, so a restart puts everything back where it was.
@MainActor final class DesktopWidgetStore: ObservableObject {
    @Published private(set) var layout = DesktopWidgetLayout()
    /// While true every widget shows its handle and can be dragged.
    @Published var isArranging = false

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB/desktop-widgets.json")
        load()
    }

    var widgets: [DesktopWidget] { layout.widgets }

    func add(_ kind: IslandWidgetKind) {
        var widget = DesktopWidget(kind: kind, size: DesktopWidgetLayout.defaultSize(for: kind))
        let position = layout.nextPosition(for: widget.size)
        widget.x = position.x
        widget.y = position.y
        layout.widgets.append(widget)
        save()
    }

    func remove(_ id: UUID) {
        layout.widgets.removeAll { $0.id == id }
        save()
    }

    func setSize(_ size: DesktopWidget.Size, for id: UUID) {
        guard let index = layout.widgets.firstIndex(where: { $0.id == id }) else { return }
        layout.widgets[index].size = size
        save()
    }

    /// Records where a drag left a widget. Called often while dragging, so it
    /// only writes to disk when the drag ends.
    func move(_ id: UUID, toX x: Double, y: Double, persist: Bool) {
        guard let index = layout.widgets.firstIndex(where: { $0.id == id }) else { return }
        layout.widgets[index].x = x
        layout.widgets[index].y = y
        if persist { save() } else { objectWillChange.send() }
    }

    func removeAll() {
        layout.widgets.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(DesktopWidgetLayout.self, from: data) else { return }
        layout = stored
    }

    private func save() {
        objectWillChange.send()
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
