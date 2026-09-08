import XCTest
@testable import MacBCore

final class ShelfPersistenceTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture() throws -> URL {
        let url = directory.appendingPathComponent("example.txt")
        try Data("fixture".utf8).write(to: url)
        return url
    }

    func testRestartPreservesReferenceAndDeduplicates() throws {
        let source = try fixture()
        let location = directory.appendingPathComponent("shelf.json")
        let first = try ShelfPersistence(fileURL: location)
        try first.add(urls: [source, source])
        let restored = try ShelfPersistence(fileURL: location)
        XCTAssertEqual(restored.records.count, 1)
        XCTAssertEqual(restored.records.first?.id, first.records.first?.id)
        XCTAssertTrue(try XCTUnwrap(restored.resolve().first).isAvailable)
        XCTAssertEqual(try Data(contentsOf: source), Data("fixture".utf8))
    }

    func testMissingFileRemainsInShelf() throws {
        let source = try fixture()
        let shelf = try ShelfPersistence(fileURL: directory.appendingPathComponent("shelf.json"))
        try shelf.add(urls: [source])
        try FileManager.default.removeItem(at: source)
        let restored = try ShelfPersistence(fileURL: shelf.fileURL)
        XCTAssertEqual(restored.records.count, 1)
        XCTAssertFalse(try XCTUnwrap(restored.resolve().first).isAvailable)
    }

    func testRemovingReferenceDoesNotDeleteSource() throws {
        let source = try fixture()
        let shelf = try ShelfPersistence(fileURL: directory.appendingPathComponent("shelf.json"))
        try shelf.add(urls: [source])
        try shelf.remove(id: XCTUnwrap(shelf.records.first?.id))
        XCTAssertTrue(shelf.records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try ShelfPersistence(fileURL: shelf.fileURL).records.isEmpty)
    }

    func testCorruptStorageIsNotSilentlyDiscarded() throws {
        let location = directory.appendingPathComponent("shelf.json")
        let invalid = Data("invalid".utf8)
        try invalid.write(to: location)
        XCTAssertThrowsError(try ShelfPersistence(fileURL: location))
        XCTAssertEqual(try Data(contentsOf: location), invalid)
    }

    func testWebURLsAreNotAdded() throws {
        let shelf = try ShelfPersistence(fileURL: directory.appendingPathComponent("shelf.json"))
        try shelf.add(urls: [XCTUnwrap(URL(string: "https://example.com/image.png"))])
        XCTAssertTrue(shelf.records.isEmpty)
    }
}
