import XCTest
@testable import VolumeCore
final class TVInputStateTests: XCTestCase {
    private func dump(active: String = "b", input: String = "com.mediatek.tvinput/.dp.DpInputService/HW10") -> String {
        """
        UserState (0):
          inputMap: inputId -> TvInputState
            com.mediatek.tvinput/.dp.DpInputService/HW10: info: Type-C; state: 0
            com.mediatek.tvinput/.hdmi.HDMIInputService/HW6: info: HDMI2; state: 0
          packageSet:
          sessionStateMap: ITvInputSession -> SessionState
            android.os.Binder@a: com.android.server.tv.TvInputManagerService$SessionState@1
              inputId: old-hdmi-session
              sessionToken: android.os.Binder@a
            android.os.Binder@b: com.android.server.tv.TvInputManagerService$SessionState@2
              inputId: \(input)
              sessionToken: android.os.Binder@b
          mCallbacks:
          mainSessionToken: \(active == "null" ? "null" : "android.os.Binder@" + active)
        """
    }
    func testUsesMainSessionInsteadOfFirstOrLastRememberedInput() throws {
        let state = try TVInputState.parse(dump())
        XCTAssertEqual(state.identifier, "com.mediatek.tvinput/.dp.DpInputService/HW10")
        XCTAssertEqual(state.label, "Type-C / DP 2")
        XCTAssertEqual(try TVInputState.parse(dump(active: "a")), .external("old-hdmi-session"))
    }
    func testDesktopIsExplicitNullSession() throws {
        XCTAssertEqual(try TVInputState.parse(dump(active: "null")), .builtIn)
    }
    func testUnknownOrFailedReadDoesNotMeanSwitchedAway() {
        XCTAssertThrowsError(try TVInputState.parse("error: device unauthorized"))
        XCTAssertThrowsError(try TVInputState.parse(dump(active: "missing")))
        XCTAssertThrowsError(try TVInputState.parse(""))
    }
    func testOnlyHardwareInputsOffered() {
        let values = TVInputState.availableInputs(dump())
        XCTAssertEqual(values.map(\.label), ["HDMI 2", "Type-C / DP 2"])
    }
    func testTransitionMustStabilizeAndFailureDropsOldEvidence() {
        var state = StableTVInput()
        let computer = TVInputState.external("typec"), game = TVInputState.external("hdmi2")
        state.observe(computer); XCTAssertNil(state.value)
        state.observe(computer); XCTAssertEqual(state.value, computer)
        state.observe(game); XCTAssertNil(state.value)
        state.observe(computer); XCTAssertNil(state.value)
        state.observe(computer); XCTAssertEqual(state.value, computer)
        state.observe(nil); XCTAssertNil(state.value)
        state.observe(game); XCTAssertNil(state.value)
        state.observe(game); XCTAssertEqual(state.value, game)
    }
    func testSourceAwayCanSwitchWithoutPhysicalUnplugAndRestore() {
        var route = OutputRecovery()
        XCTAssertFalse(route.connected(defaultUID: "proxy", proxyUID: "proxy", physicalUID: "physical"))
        XCTAssertTrue(route.disconnected(defaultUID: "proxy", proxyUID: "proxy", preferredFallbackUID: "usb"))
        route.usedFallback("usb")
        XCTAssertFalse(route.disconnected(defaultUID: "usb", proxyUID: "proxy", preferredFallbackUID: "usb"))
        XCTAssertTrue(route.connected(defaultUID: "usb", proxyUID: "proxy", physicalUID: "physical"))
        route.restored(proxyUID: "proxy"); XCTAssertFalse(route.restorePending)
    }
}
