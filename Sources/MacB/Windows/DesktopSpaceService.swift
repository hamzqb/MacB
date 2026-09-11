import Foundation
import Darwin

struct DesktopSpaceSnapshot: Sendable {
    let orderedSpaceIDs: [UInt64]
    let currentSpaceIDs: Set<UInt64>
    let memberships: [UInt32: [UInt64]]

    static let unavailable = DesktopSpaceSnapshot(orderedSpaceIDs: [], currentSpaceIDs: [], memberships: [:])
    var isAvailable: Bool { !orderedSpaceIDs.isEmpty }
}

/// Reads Mission Control's Space topology without linking MacB to private frameworks.
/// Every symbol is optional so an OS update falls back to the public window view.
final class DesktopSpaceService: @unchecked Sendable {
    private typealias ConnectionID = UInt32
    private typealias MainConnection = @convention(c) () -> ConnectionID
    private typealias CopyManagedSpaces = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

    private let handle: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let copyManagedSpaces: CopyManagedSpaces?
    private let copySpacesForWindows: CopySpacesForWindows?

    init() {
        let loaded = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        handle = loaded
        func symbol<T>(_ names: [String], as: T.Type) -> T? {
            guard let loaded else { return nil }
            for name in names {
                if let address = dlsym(loaded, name) { return unsafeBitCast(address, to: T.self) }
            }
            return nil
        }
        mainConnection = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnection.self)
        copyManagedSpaces = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: CopyManagedSpaces.self)
        copySpacesForWindows = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], as: CopySpacesForWindows.self)
    }

    deinit { if let handle { dlclose(handle) } }

    func snapshot(windowIDs: [UInt32]) -> DesktopSpaceSnapshot {
        guard let mainConnection, let copyManagedSpaces, let copySpacesForWindows else { return .unavailable }
        let connection = mainConnection()
        guard let unmanaged = copyManagedSpaces(connection) else { return .unavailable }
        let displays = unmanaged.takeRetainedValue() as NSArray
        var ordered: [UInt64] = []
        var current = Set<UInt64>()

        for case let display as NSDictionary in displays {
            if let currentSpace = display["Current Space"] as? NSDictionary,
               let id = Self.uint64(currentSpace["id64"]) { current.insert(id) }
            guard let spaces = display["Spaces"] as? [NSDictionary] else { continue }
            for space in spaces {
                guard let id = Self.uint64(space["id64"]) else { continue }
                // type 0 is a regular Mission Control desktop. Full-screen Spaces are
                // retained after them so their windows still receive a stable section.
                if !ordered.contains(id) { ordered.append(id) }
            }
        }
        guard !ordered.isEmpty else { return .unavailable }

        var memberships: [UInt32: [UInt64]] = [:]
        for windowID in windowIDs {
            let input = [NSNumber(value: windowID)] as CFArray
            guard let values = copySpacesForWindows(connection, 7, input)?.takeRetainedValue() as? [NSNumber] else { continue }
            let ids = values.map(\.uint64Value).filter { ordered.contains($0) }
            if !ids.isEmpty { memberships[windowID] = ids }
        }
        return DesktopSpaceSnapshot(orderedSpaceIDs: ordered, currentSpaceIDs: current, memberships: memberships)
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return UInt64(value) }
        return nil
    }
}
