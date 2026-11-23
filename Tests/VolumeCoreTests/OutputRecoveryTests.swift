import XCTest
@testable import VolumeCore
final class OutputRecoveryTests: XCTestCase {
    func testUnplugFallsBackAndReplugRestoresPreviousProxy() {
        var state = OutputRecovery()
        XCTAssertFalse(state.connected(defaultUID: "proxy", proxyUID: "proxy", physicalUID: "display"))
        XCTAssertTrue(state.disconnected(defaultUID: "proxy", proxyUID: "proxy"))
        state.usedFallback("speakers")
        XCTAssertFalse(state.disconnected(defaultUID: "speakers", proxyUID: "proxy"))
        XCTAssertTrue(state.connected(defaultUID: "speakers", proxyUID: "proxy", physicalUID: "display"))
        state.restored(proxyUID: "proxy")
        XCTAssertFalse(state.restorePending)
    }
    func testUserOutputChangeWhileDisconnectedCancelsRestore() {
        var state = OutputRecovery()
        _ = state.connected(defaultUID: "proxy", proxyUID: "proxy", physicalUID: "display")
        _ = state.disconnected(defaultUID: "speakers", proxyUID: "proxy")
        _ = state.disconnected(defaultUID: "headphones", proxyUID: "proxy")
        XCTAssertFalse(state.connected(defaultUID: "headphones", proxyUID: "proxy", physicalUID: "display"))
    }
    func testUnselectedProxyDoesNotTakeOverOnReconnect() {
        var state = OutputRecovery()
        _ = state.connected(defaultUID: "headphones", proxyUID: "proxy", physicalUID: "display")
        XCTAssertFalse(state.disconnected(defaultUID: "headphones", proxyUID: "proxy"))
        XCTAssertFalse(state.connected(defaultUID: "headphones", proxyUID: "proxy", physicalUID: "display"))
    }
    func testMissingAtLaunchDoesNotInventPriorSelection() {
        var state = OutputRecovery()
        XCTAssertFalse(state.disconnected(defaultUID: "speakers", proxyUID: "proxy"))
        XCTAssertFalse(state.connected(defaultUID: "speakers", proxyUID: "proxy", physicalUID: "display"))
    }
    func testSystemChoosesPhysicalDisplayDuringReconnect() {
        var state = OutputRecovery()
        _ = state.connected(defaultUID: "proxy", proxyUID: "proxy", physicalUID: "display")
        _ = state.disconnected(defaultUID: "speakers", proxyUID: "proxy")
        XCTAssertTrue(state.connected(defaultUID: "display", proxyUID: "proxy", physicalUID: "display"))
    }
    func testPreferredFallbackReplacesSystemChoiceAndRestores() {
        var state = OutputRecovery()
        _ = state.connected(defaultUID: "proxy", proxyUID: "proxy", physicalUID: "display")
        XCTAssertTrue(state.disconnected(defaultUID: "speakers", proxyUID: "proxy", preferredFallbackUID: "usb"))
        state.usedFallback("usb")
        XCTAssertFalse(state.disconnected(defaultUID: "usb", proxyUID: "proxy", preferredFallbackUID: "usb"))
        XCTAssertTrue(state.connected(defaultUID: "usb", proxyUID: "proxy", physicalUID: "display"))
    }
    func testMissingPreferredFallbackRetriesUntilManualChange() {
        var state = OutputRecovery()
        _ = state.connected(defaultUID: "proxy", proxyUID: "proxy", physicalUID: "display")
        XCTAssertTrue(state.disconnected(defaultUID: "speakers", proxyUID: "proxy", preferredFallbackUID: "usb"))
        XCTAssertTrue(state.disconnected(defaultUID: "speakers", proxyUID: "proxy", preferredFallbackUID: "usb"))
        XCTAssertFalse(state.disconnected(defaultUID: "headphones", proxyUID: "proxy", preferredFallbackUID: "usb"))
        XCTAssertFalse(state.connected(defaultUID: "headphones", proxyUID: "proxy", physicalUID: "display"))
    }

}
