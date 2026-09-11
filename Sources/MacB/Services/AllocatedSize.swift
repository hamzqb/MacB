import Foundation

/// How much disk a folder actually occupies, measured with a stopping point.
///
/// A browser profile holds a hundred thousand files and a DerivedData folder
/// holds more. Adding all of them up takes longer than anybody waits, so the
/// walk stops at a budget and says the number is a floor. A floor the user can
/// read beats a total they never see.
enum AllocatedSize {
    static let defaultBudget = 20_000

    static func of(_ url: URL, budget: Int = defaultBudget) -> (bytes: Int64, isPartial: Bool) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                              options: [.skipsHiddenFiles]) else {
            let value = try? url.resourceValues(forKeys: keys)
            return (Int64(value?.totalFileAllocatedSize ?? value?.fileAllocatedSize ?? 0), false)
        }
        var total: Int64 = 0
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited > budget { return (total, true) }
            if let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return (total, false)
    }
}
