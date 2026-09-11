import XCTest
@testable import MacBCore

final class CacheSweepTests: XCTestCase {
    private let home = "/Users/tester"

    func testOnlyCachesLogsAndBuildOutputAreEverSwept() {
        let paths = Set(CacheSource.all.map(\.path))
        XCTAssertTrue(paths.contains("Library/Caches"))
        XCTAssertTrue(paths.contains("Library/Logs"))
        XCTAssertTrue(paths.contains("Library/Developer/Xcode/DerivedData"))
        // The places an application keeps the only copy of anything are absent.
        for forbidden in ["Documents", "Library/Containers", "Library/Group Containers",
                          "Library/Preferences", "Library/Application Support", "Desktop"] {
            XCTAssertFalse(paths.contains(forbidden), "\(forbidden) is swept")
        }
    }

    func testAQueueIsNotACacheAndIsNeverOffered() {
        for name in ["CloudKit", "com.apple.containermanagerd", "com.apple.nsurlsessiond", "com.apple.appstore"] {
            XCTAssertFalse(CacheSweepRules.isSweepable(name: name), "\(name) was offered")
        }
        XCTAssertTrue(CacheSweepRules.isSweepable(name: "com.spotify.client"))
    }

    func testHiddenAndTraversingNamesAreRefused() {
        for name in ["", ".", "..", ".marker", "a/b"] {
            XCTAssertFalse(CacheSweepRules.isSweepable(name: name), "\(name) was accepted")
        }
    }

    func testTheSweepReachesExactlyOneLevelIntoAListedDirectory() {
        XCTAssertTrue(CacheSweepRules.isSweepablePath("\(home)/Library/Caches/com.spotify.client", home: home))
        XCTAssertTrue(CacheSweepRules.isSweepablePath("\(home)/Library/Logs/Claude", home: home))
        XCTAssertTrue(CacheSweepRules.isSweepablePath("\(home)/.npm/_cacache", home: home))
        // The directory itself is never a candidate, and neither is anything deeper.
        XCTAssertFalse(CacheSweepRules.isSweepablePath("\(home)/Library/Caches", home: home))
        XCTAssertFalse(CacheSweepRules.isSweepablePath("\(home)/Library/Caches/com.spotify.client/Data", home: home))
        XCTAssertFalse(CacheSweepRules.isSweepablePath("\(home)/Library/Preferences/com.spotify.client.plist", home: home))
        XCTAssertFalse(CacheSweepRules.isSweepablePath("/Library/Caches/com.spotify.client", home: home))
        XCTAssertFalse(CacheSweepRules.isSweepablePath("\(home)/Library/Caches/../Preferences/x", home: home))
        XCTAssertFalse(CacheSweepRules.isSweepablePath("\(home)/Library/Caches/x", home: ""))
    }

    func testBuildToolCachesAreReadAsDeveloperWorkNotApplications() {
        XCTAssertEqual(CacheSweepRules.group(forCacheName: "Homebrew", default: .applications), .developer)
        XCTAssertEqual(CacheSweepRules.group(forCacheName: "org.swift.swiftpm", default: .applications), .developer)
        XCTAssertEqual(CacheSweepRules.group(forCacheName: "com.spotify.client", default: .applications), .applications)
        // The name decides on its own, so the caller's fallback only applies to
        // folders the list has never heard of.
        XCTAssertEqual(CacheSweepRules.group(forCacheName: "Homebrew", default: .logs), .developer)
        XCTAssertEqual(CacheSweepRules.group(forCacheName: "SomeThing", default: .logs), .logs)
    }
}
