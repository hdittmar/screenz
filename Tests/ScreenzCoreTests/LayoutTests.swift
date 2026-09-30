import XCTest
import CoreGraphics
@testable import ScreenzCore

final class LayoutTests: XCTestCase {
    func display(_ id: UInt32, width: Double = 1920, height: Double = 1080, x: Double = 0, y: Double = 0, main: Bool = false) -> Display {
        Display(id: id, name: "Display \(id)", width: width, height: height, x: x, y: y, isMain: main)
    }
    func marker(_ id: UInt32, _ x: Double, _ y: Double, size: Double = 345.6) -> Marker {
        Marker(id: id, center: CGPoint(x: x, y: y), size: size)
    }
    func testLeftAndRightOfMain() throws {
        let result = try Layout.infer(displays: [display(1, main: true), display(2), display(3)], markers: [marker(1, 2200, 800), marker(2, 200, 800), marker(3, 4200, 800)])
        XCTAssertEqual(result.map(\.x), [0, -1920, 1920])
        XCTAssertEqual(result.map(\.y), [0, 0, 0])
        XCTAssertNoThrow(try Layout.validate(result))
    }
    func testVerticalPhotoUsesTopLeftCoordinates() throws {
        let result = try Layout.infer(displays: [display(1, main: true), display(2)], markers: [marker(1, 1000, 1500), marker(2, 1000, 300)])
        XCTAssertEqual(result[1].x, 0)
        XCTAssertEqual(result[1].y, -1080)
        XCTAssertNoThrow(try Layout.validate(result))
    }
    func testDifferentLogicalSizesCenterAlign() throws {
        let result = try Layout.infer(displays: [display(1, main: true), display(2, width: 1080, height: 1920)], markers: [marker(1, 1000, 1200), marker(2, 2600, 1200)])
        XCTAssertEqual(result[1].x, 1920)
        XCTAssertEqual(result[1].y, -420)
        XCTAssertNoThrow(try Layout.validate(result))
    }
    func testGrid() throws {
        let ds = [display(1, main: true), display(2), display(3), display(4)]
        let result = try Layout.infer(displays: ds, markers: [marker(1, 1000, 600), marker(2, 3000, 600), marker(3, 1000, 1800), marker(4, 3000, 1800)])
        XCTAssertEqual(result.map(\.x), [0, 1920, 0, 1920])
        XCTAssertEqual(result.map(\.y), [0, 0, 1080, 1080])
        XCTAssertNoThrow(try Layout.validate(result))
    }
    func testMissingAndDuplicateMarkersRejected() {
        let ds = [display(1, main: true), display(2)]
        XCTAssertThrowsError(try Layout.infer(displays: ds, markers: [marker(1, 0, 0)]))
        XCTAssertThrowsError(try Layout.infer(displays: ds, markers: [marker(1, 0, 0), marker(1, 10, 0)]))
    }
    func testTinyAndInvalidObservationsRejected() {
        let ds = [display(1, main: true), display(2)]
        XCTAssertThrowsError(try Layout.infer(displays: ds, markers: [marker(1, 0, 0), marker(2, 300, 0, size: 3)]))
        XCTAssertThrowsError(try Layout.infer(displays: ds, markers: [marker(1, .nan, 0), marker(2, 300, 0)]))
    }
    func testRejectsOverlapGapAndCornerOnlyContact() {
        XCTAssertThrowsError(try Layout.validate([display(1, main: true), display(2, x: 100)]))
        XCTAssertThrowsError(try Layout.validate([display(1, main: true), display(2, x: 2000)]))
        XCTAssertThrowsError(try Layout.validate([display(1, main: true), display(2, x: 1920, y: 1080)]))
    }
    func testMainDisplayRemainsOriginAndSnapClosesGap() throws {
        XCTAssertThrowsError(try Layout.validate([display(1, x: 100, main: true)]))
        let main = display(1, main: true)
        let next = Layout.snap(display(2, x: 1960, y: 30), to: [main])
        XCTAssertEqual(next.x, 1920); XCTAssertEqual(next.y, 0)
        XCTAssertNoThrow(try Layout.validate([main, next]))
    }
}
