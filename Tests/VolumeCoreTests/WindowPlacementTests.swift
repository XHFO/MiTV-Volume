import XCTest
@testable import VolumeCore

final class WindowPlacementTests: XCTestCase {
    func testRelocatesProportionallyAndClamps() {
        let from = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let to = CGRect(x: 0, y: 0, width: 800, height: 500)
        let window = CGRect(x: 1200, y: 100, width: 400, height: 300)
        let moved = WindowPlacement.relocatedFrame(window: window, from: from, to: to)
        XCTAssertTrue(to.contains(CGPoint(x: moved.minX, y: moved.minY)) || to.intersects(moved))
        XCTAssertLessThanOrEqual(moved.maxX, to.maxX + 0.5)
        XCTAssertLessThanOrEqual(moved.maxY, to.maxY + 0.5)
        XCTAssertGreaterThanOrEqual(moved.width, 200)
    }

    func testPrimaryScreenUsesCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertTrue(WindowPlacement.window(CGRect(x: 100, y: 100, width: 200, height: 200), isPrimarilyOn: screen))
        XCTAssertFalse(WindowPlacement.window(CGRect(x: 2000, y: 100, width: 200, height: 200), isPrimarilyOn: screen))
    }

    func testFullScreenDetection() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(WindowPlacement.looksFullScreen(window: screen, screen: screen))
        XCTAssertFalse(WindowPlacement.looksFullScreen(window: CGRect(x: 100, y: 100, width: 400, height: 300), screen: screen))
    }
}
