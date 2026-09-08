import Foundation

public struct WindowSelection: Equatable {
    public private(set) var ids: [String] = []
    public private(set) var selectedID: String?
    public init() {}

    public mutating func replace(with newIDs: [String]) {
        let oldIndex = selectedID.flatMap { ids.firstIndex(of: $0) } ?? 0
        ids = newIDs
        if let selectedID, newIDs.contains(selectedID) { return }
        selectedID = ids.isEmpty ? nil : ids[min(oldIndex, ids.count - 1)]
    }
    public mutating func select(_ id: String) {
        guard ids.contains(id) else { return }
        selectedID = id
    }
    public mutating func advance(backwards: Bool = false) {
        guard !ids.isEmpty else { selectedID = nil; return }
        let index = selectedID.flatMap { ids.firstIndex(of: $0) } ?? (backwards ? 0 : ids.count - 1)
        selectedID = ids[(index + (backwards ? ids.count - 1 : 1)) % ids.count]
    }
}
