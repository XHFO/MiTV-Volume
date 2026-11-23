import XCTest
@testable import VolumeCore

final class DeviceNamingTests: XCTestCase {
    func testDefaultFollowsPhysicalOutputAndCustomOverrides() throws {
        XCTAssertEqual(DeviceNaming.resolved(custom: "", outputName: "Mi Monitor"), "Mi Monitor（音量控制）")
        XCTAssertEqual(DeviceNaming.resolved(custom: "", outputName: "HDMI"), "HDMI（音量控制）")
        let custom = try DeviceNaming.validatedCustomName("  客厅 = 电视  ")
        XCTAssertEqual(DeviceNaming.resolved(custom: custom, outputName: "HDMI"), "客厅 = 电视")
        XCTAssertEqual(try DeviceNaming.validatedCustomName("  "), "")
    }
    func testControlCharactersAndOverlongNamesRejected() {
        XCTAssertThrowsError(try DeviceNaming.validatedCustomName("电视\n音量"))
        XCTAssertThrowsError(try DeviceNaming.validatedCustomName(String(repeating: "字", count: 81)))
    }
}
