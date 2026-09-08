import Foundation
import Combine

struct LocalTaskItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var isPinned: Bool
    let createdAt: Date
}

@MainActor final class TaskStore: ObservableObject {
    @Published private(set) var items: [LocalTaskItem] = []
    @Published var errorMessage: String?
    private let fileURL: URL
    private var storageReadable = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB/tasks.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do { items = try JSONDecoder().decode([LocalTaskItem].self, from: Data(contentsOf: self.fileURL)) }
            catch { storageReadable = false; errorMessage = "Görevler okunamadı. Mevcut kayıtlar korunuyor." }
        }
        sortItems()
    }

    func add(title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var updated = items
        updated.append(LocalTaskItem(id: UUID(), title: String(title.prefix(1000)), isCompleted: false,
                                     isPinned: false, createdAt: Date()))
        save(updated)
    }
    func toggleComplete(id: UUID) {
        var updated = items
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isCompleted.toggle()
        save(updated)
    }
    func togglePin(id: UUID) {
        var updated = items
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isPinned.toggle()
        save(updated)
    }
    func remove(id: UUID) { save(items.filter { $0.id != id }) }

    private func save(_ updated: [LocalTaskItem]) {
        guard storageReadable else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            items = updated
            sortItems()
            errorMessage = nil
        } catch { errorMessage = "Görevler kaydedilemedi: \(error.localizedDescription)" }
    }
    private func sortItems() {
        items.sort {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }
}
