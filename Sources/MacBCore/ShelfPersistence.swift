import Foundation

public struct ShelfRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public var bookmark: Data
    public var path: String
    public var name: String
    public var isDirectory: Bool
}

public struct ResolvedShelfRecord {
    public let record: ShelfRecord
    public let url: URL?
    public let isAvailable: Bool
}

/// Stores references only. Removing an entry never mutates its source file.
public final class ShelfPersistence {
    public private(set) var records: [ShelfRecord] = []
    public let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            records = try JSONDecoder().decode([ShelfRecord].self, from: Data(contentsOf: fileURL))
        }
    }

    public func add(urls: [URL]) throws {
        var updated = records
        let existingPaths = Set(resolve().compactMap { $0.url?.standardizedFileURL.resolvingSymlinksInPath().path })
        var paths = existingPaths.union(records.map(\.path))
        for input in urls {
            guard input.isFileURL, input.host == nil || input.host == "" || input.host == "localhost" else { continue }
            let url = input.standardizedFileURL.resolvingSymlinksInPath()
            guard !paths.contains(url.path) else { continue }
            let properties = try url.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: [.nameKey, .isDirectoryKey], relativeTo: nil)
            updated.append(ShelfRecord(id: UUID(), bookmark: bookmark, path: url.path,
                                       name: properties.name ?? url.lastPathComponent,
                                       isDirectory: properties.isDirectory ?? false))
            paths.insert(url.path)
        }
        try save(updated)
    }

    public func remove(id: UUID) throws {
        try save(records.filter { $0.id != id })
    }

    public func resolve() -> [ResolvedShelfRecord] {
        records.map { record in
            var stale = false
            let resolved = try? URL(resolvingBookmarkData: record.bookmark, options: [.withoutUI, .withoutMounting],
                                    relativeTo: nil, bookmarkDataIsStale: &stale)
            // A missing bookmark target remains visible, but cannot be dragged or opened.
            let candidate = resolved ?? URL(fileURLWithPath: record.path)
            let available = candidate.isFileURL && FileManager.default.fileExists(atPath: candidate.path)
            return ResolvedShelfRecord(record: record, url: candidate, isAvailable: available)
        }
    }

    public func refreshBookmarks() throws {
        var updated = records
        for index in updated.indices {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: updated[index].bookmark,
                                     options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                     bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            if stale || url.path != updated[index].path {
                updated[index].bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                updated[index].path = url.path
                updated[index].name = url.lastPathComponent
            }
        }
        if updated != records { try save(updated) }
    }

    private func save(_ updated: [ShelfRecord]) throws {
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        records = updated
    }
}
