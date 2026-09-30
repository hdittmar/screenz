import XCTest
@testable import ScreenzCore

final class SavedArrangementTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private var store: ArrangementStore { ArrangementStore(url: directory.appendingPathComponent("Screenz/arrangements.json")) }
    private var displays: [Display] {
        [Display(id: 1, name: "Same name", width: 1920, height: 1080, x: 0, y: 0, isMain: true),
         Display(id: 2, name: "Same name", width: 1920, height: 1080, x: -1920, y: 0, isMain: false)]
    }
    private func saved(_ title: String = "Work") throws -> SavedArrangement {
        try SavedArrangement(title: title, displays: displays, identities: [1: "uuid-a", 2: "uuid-b"])
    }

    func testSaveSurvivesNewStoreAndKeepsSeparateArrangements() throws {
        XCTAssertEqual(try store.load(), [])
        let a = try saved("Work"), b = try saved("Home")
        try store.save(a); try store.save(b)
        let reopened = ArrangementStore(url: store.url)
        XCTAssertEqual(try reopened.load(), [b, a])
    }
    func testTitleValidationAndDuplicateProtection() throws {
        XCTAssertEqual(try saved("  Work  ").title, "Work")
        for title in [" ", "A\nB", String(repeating: "a", count: 81)] {
            XCTAssertThrowsError(try saved(title))
        }
        try store.save(saved())
        XCTAssertThrowsError(try store.save(saved("work")))
        XCTAssertEqual(try store.load().count, 1)
    }
    func testRenameAndDeletePersist() throws {
        var item = try saved()
        try store.save(item)
        item.title = "Office"
        try store.save(item)
        XCTAssertEqual(try store.load().map(\.title), ["Office"])
        try store.remove(id: item.id)
        XCTAssertEqual(try store.load(), [])
    }
    func testReconnectRemapsNumericIDsEvenWithSameDisplayNames() throws {
        let current = [Display(id: 42, name: "Same name", width: 1920, height: 1080, x: 0, y: 0, isMain: true),
                       Display(id: 99, name: "Same name", width: 1920, height: 1080, x: 1920, y: 0, isMain: false)]
        let result = try saved().resolve(displays: current, identities: [42: "uuid-a", 99: "uuid-b"])
        XCTAssertEqual(result.map(\.id), [42, 99])
        XCTAssertEqual(result.map(\.x), [0, -1920])
    }
    func testPreservesCurrentMainDisplayByTranslatingPositions() throws {
        let current = [Display(id: 2, name: "Left", width: 1920, height: 1080, x: 0, y: 0, isMain: true),
                       Display(id: 1, name: "Right", width: 1920, height: 1080, x: 1920, y: 0, isMain: false)]
        let result = try saved().resolve(displays: current, identities: [1: "uuid-a", 2: "uuid-b"])
        XCTAssertEqual(result.map(\.x), [0, 1920])
        XCTAssertTrue(result[0].isMain)
    }
    func testMissingExtraOrWrongDisplayAndResolutionRejected() throws {
        let profile = try saved()
        XCTAssertThrowsError(try profile.resolve(displays: [displays[0]], identities: [1: "uuid-a"]))
        XCTAssertThrowsError(try profile.resolve(displays: displays, identities: [1: "uuid-a", 2: "different"]))
        let changed = [displays[0], Display(id: 2, name: "Same name", width: 1280, height: 720, x: -1280, y: 0, isMain: false)]
        XCTAssertThrowsError(try profile.resolve(displays: changed, identities: [1: "uuid-a", 2: "uuid-b"]))
        let extra = displays + [Display(id: 3, name: "Extra", width: 100, height: 100, x: 1920, y: 0, isMain: false)]
        XCTAssertThrowsError(try profile.resolve(displays: extra, identities: [1: "uuid-a", 2: "uuid-b", 3: "uuid-c"]))
    }
    func testAmbiguousIdentityAndInvalidPositionsRejected() throws {
        XCTAssertThrowsError(try SavedArrangement(title: "Work", displays: displays, identities: [1: "same", 2: "same"]))
        var overlapping = displays; overlapping[1].x = 0
        XCTAssertThrowsError(try SavedArrangement(title: "Work", displays: overlapping, identities: [1: "a", 2: "b"]))
    }
    func testCorruptedOrNewerFilesAreNotOverwritten() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for original in [Data("broken".utf8), Data("{\"version\":2,\"arrangements\":[]}".utf8)] {
            try original.write(to: store.url)
            XCTAssertThrowsError(try store.save(saved()))
            XCTAssertThrowsError(try store.remove(id: UUID()))
            XCTAssertEqual(try Data(contentsOf: store.url), original)
        }
    }
}
