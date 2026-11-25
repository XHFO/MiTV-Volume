import XCTest
@testable import VolumeCore

final class TVInputStateTests: XCTestCase {
    private func status(
        id: Any? = "30",
        label: String = "USB-C",
        known: Bool = true,
        inputs: [[String: Any]] = [
            ["id": "23", "label": "HDMI 1"],
            ["id": "24", "label": "HDMI 2"],
            ["id": "29", "label": "DP"],
            ["id": "30", "label": "USB-C"],
            ["id": "34", "label": "内置系统画面"]
        ],
        displayError: String = ""
    ) -> [String: Any] {
        var source: [String: Any] = ["label": label, "known": known]
        if let id { source["id"] = id } else { source["id"] = NSNull() }
        return [
            "running": false,
            "serverRunning": true,
            "inputSource": source,
            "inputsSupported": inputs,
            "displayError": displayError
        ]
    }

    func testParsesXHFlowUSBCurrentAndHardwareList() throws {
        let reading = try TVInputState.parseStatus(status())
        XCTAssertEqual(reading.current.identifier, "30")
        XCTAssertEqual(reading.current.label, "USB-C")
        XCTAssertEqual(reading.inputs.map(\.label), ["DP", "HDMI 1", "HDMI 2", "USB-C"])
        XCTAssertFalse(reading.inputs.contains { $0.identifier == "34" })
    }

    func testBuiltInSystemPictureMapsToDesktop() throws {
        let reading = try TVInputState.parseStatus(status(id: "34", label: "内置系统画面"))
        XCTAssertEqual(reading.current, .builtIn)
        XCTAssertEqual(reading.current.label, TVInputState.builtIn.label)
    }

    func testNumericIDsAndUnknownListStillCompareByID() throws {
        let reading = try TVInputState.parseStatus(status(id: 30, label: "未知", known: false, inputs: []))
        XCTAssertEqual(reading.current.identifier, "30")
        XCTAssertEqual(reading.current.label, "USB-C / Type-C")
    }

    func testMissingOrNullSourceDoesNotGuessAway() {
        XCTAssertThrowsError(try TVInputState.parseStatus(status(id: nil)))
        XCTAssertThrowsError(try TVInputState.parseStatus(["serverRunning": true]))
        XCTAssertThrowsError(try TVInputState.parseStatus(status(id: nil, displayError: "当前选中接口未知")))
    }

    func testLegacyADBIdentifiersAreRejectedForSelection() {
        XCTAssertTrue(TVInputState.isLegacyADBIdentifier("com.mediatek.tvinput/.dp.DpInputService/HW10"))
        XCTAssertFalse(TVInputState.isLegacyADBIdentifier("30"))
        XCTAssertFalse(TVInputState.isLegacyADBIdentifier(nil))
    }

    func testTokenValidationAcceptsURLOrHex() throws {
        let token = "0123456789abcdef0123456789abcdef"
        XCTAssertEqual(try XHFlowClient.validatedToken(token), token)
        XCTAssertEqual(
            try XHFlowClient.validatedToken("http://192.0.2.10:8768/?token=\(token)"),
            token
        )
        XCTAssertThrowsError(try XHFlowClient.validatedToken("short"))
    }

    func testTransitionMustStabilizeAndFailureDropsOldEvidence() {
        var state = StableTVInput()
        let computer = TVInputState.external("30"), game = TVInputState.external("24")
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
