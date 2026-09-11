import XCTest
@testable import MacBCore

final class AppLeftoverTests: XCTestCase {
    private let spotify = AppIdentity(bundleIdentifier: "com.spotify.client", name: "Spotify",
                                      executableName: "Spotify", teamIdentifier: "2FNC3A47ZF",
                                      helperIdentifiers: ["com.spotify.client.helper"])

    func testIdentifierNamedFilesAreExact() {
        for (name, kind) in [("com.spotify.client", AppLeftoverKind.support),
                             ("com.spotify.client.plist", .preference),
                             ("com.spotify.client.savedState", .savedState),
                             ("com.spotify.client.binarycookies", .cookie),
                             ("com.spotify.client", .container)] {
            XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: name, kind: kind, identity: spotify),
                           .exact, "\(name) was not matched exactly")
        }
    }

    func testTeamPrefixedGroupContainerIsExact() {
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "2FNC3A47ZF.com.spotify.client",
                                                     kind: .groupContainer, identity: spotify), .exact)
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "group.com.spotify.client",
                                                     kind: .groupContainer, identity: spotify), .exact)
    }

    func testHelpersAndByHostFilesAreLikely() {
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "com.spotify.client.helper",
                                                     kind: .launchAgent, identity: spotify), .exact)
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "com.spotify.client.updater.plist",
                                                     kind: .preference, identity: spotify), .likely)
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "Spotify_2026-01-04-120000_Mac.ips",
                                                     kind: .crashReport, identity: spotify), .likely)
    }

    func testANameMatchIsOnlyEverPossible() {
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "Spotify", kind: .support, identity: spotify),
                       .possible)
        XCTAssertTrue(AppLeftoverConfidence.possible.isSelectedByDefault == false)
    }

    func testNameMatchingIsRefusedWhereNamesAreNeverUsed() {
        for kind in [AppLeftoverKind.container, .groupContainer, .application] {
            XCTAssertNil(AppLeftoverMatcher.confidence(fileName: "Spotify", kind: kind, identity: spotify),
                         "a name match leaked into \(kind)")
        }
    }

    func testSharedVendorFoldersAreNeverOfferedByName() {
        let chrome = AppIdentity(bundleIdentifier: "com.google.Chrome", name: "Google",
                                 executableName: "Google Chrome")
        XCTAssertNil(AppLeftoverMatcher.confidence(fileName: "Google", kind: .support, identity: chrome))
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "com.google.Chrome", kind: .support, identity: chrome),
                       .exact)
    }

    func testGenericAndShortNamesAreNeverOfferedByName() {
        let generic = AppIdentity(bundleIdentifier: "com.example.notes", name: "Notes")
        XCTAssertNil(AppLeftoverMatcher.confidence(fileName: "Notes", kind: .support, identity: generic))
        let short = AppIdentity(bundleIdentifier: "com.example.ab", name: "Ab")
        XCTAssertNil(AppLeftoverMatcher.confidence(fileName: "Ab", kind: .support, identity: short))
    }

    func testAnUnrelatedNeighbourIsNeverMatched() {
        for name in ["com.spotify.clienthelper", "com.spotifyx.client", "org.spotify.client",
                     "SpotifyDeluxe", "com.apple.Safari", "Discord"] {
            XCTAssertNil(AppLeftoverMatcher.confidence(fileName: name, kind: .support, identity: spotify),
                         "\(name) was matched against Spotify")
        }
    }

    func testAnUnsignedApplicationStillMatchesItsOwnIdentifier() {
        let unsigned = AppIdentity(bundleIdentifier: "com.example.tool", name: "Tooling")
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "com.example.tool", kind: .cache, identity: unsigned),
                       .exact)
        // Without a signature the team prefix cannot be confirmed, so its own
        // group container is likely rather than exact.
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "TEAMID.com.example.tool",
                                                     kind: .groupContainer, identity: unsigned), .likely)
        XCTAssertNil(AppLeftoverMatcher.confidence(fileName: "TEAMID.com.example.toolkit",
                                                   kind: .groupContainer, identity: unsigned))
    }

    func testSystemLibraryLocationsAreMarkedAsNeedingAnAdministrator() {
        let system = AppLeftoverLocation.all.filter { $0.root == .systemLibrary }
        XCTAssertFalse(system.isEmpty)
        XCTAssertTrue(system.allSatisfy(\.requiresAdministrator))
        XCTAssertTrue(AppLeftoverLocation.all.filter { $0.root == .userLibrary }
            .allSatisfy { !$0.requiresAdministrator })
    }

    func testTheScanCoversTheDirectoriesAnApplicationActuallyWritesTo() {
        let covered = Set(AppLeftoverLocation.all.map(\.kind))
        for kind in AppLeftoverKind.allCases where kind != .application {
            XCTAssertTrue(covered.contains(kind), "\(kind) has no directory to scan")
        }
        let paths = Set(AppLeftoverLocation.all.filter { $0.root == .userLibrary }.map(\.path))
        for expected in ["Application Support", "Caches", "Containers", "Group Containers",
                         "Preferences", "Preferences/ByHost", "Saved Application State",
                         "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Application Scripts"] {
            XCTAssertTrue(paths.contains(expected), "\(expected) is not scanned")
        }
    }

    func testAVendorFolderIsLookedIntoOnceAndNeverOfferedItself() {
        let chrome = AppIdentity(bundleIdentifier: "com.google.Chrome", name: "Chrome",
                                 executableName: "Google Chrome", teamIdentifier: "EQHXZ8M8AV")
        XCTAssertTrue(AppLeftoverMatcher.isVendorContainer(fileName: "Google", identity: chrome))
        XCTAssertNil(AppLeftoverMatcher.confidence(fileName: "Google", kind: .support, identity: chrome))
        XCTAssertEqual(AppLeftoverMatcher.confidence(fileName: "Chrome", kind: .support, identity: chrome), .possible)
        XCTAssertFalse(AppLeftoverMatcher.isVendorContainer(fileName: "Mozilla", identity: chrome))
        let spotify = AppIdentity(bundleIdentifier: "com.spotify.client", name: "Spotify")
        XCTAssertNil(AppLeftoverMatcher.vendorToken(of: spotify))
        XCTAssertNil(AppLeftoverMatcher.vendorToken(of: AppIdentity(bundleIdentifier: "com.ab.tool", name: "Tooling")))
    }
}
