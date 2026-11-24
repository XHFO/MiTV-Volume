import XCTest
@testable import VolumeCore

final class TVInputConnectionTests: XCTestCase {
    func testColdLaunchReplacesOldServerOnceAndTargetsOnlySelectedTV() async throws {
        let connection = TVInputConnection()
        var calls = [[String]]()
        func run(_ args: [String]) async throws -> String {
            calls.append(args)
            if args.contains("connect") { return "connected to 192.0.2.1:5555" }
            return "UserState (0):\n  mainSessionToken: null"
        }
        _ = try await connection.read(host: "192.0.2.1", run: run)
        _ = try await connection.read(host: "192.0.2.1", run: run)
        XCTAssertEqual(calls[0], ["-P", "5047", "kill-server"])
        XCTAssertEqual(calls.filter { $0.contains("kill-server") }.count, 1)
        XCTAssertEqual(calls.filter { $0.contains("connect") }.count, 1)
        for command in calls where command.contains("shell") {
            XCTAssertEqual(command, ["-P", "5047", "-s", "192.0.2.1:5555", "shell", "dumpsys", "tv_input"])
        }
    }
    func testFailedConnectDoesNotReadUnknownDeviceAndCanRecover() async throws {
        let connection = TVInputConnection()
        var fail = true, calls = [[String]]()
        func run(_ args: [String]) async throws -> String {
            calls.append(args)
            if args.contains("connect") {
                return fail ? "failed to connect: No route to host" : "already connected to 192.0.2.1:5555"
            }
            return "UserState (0):\n  mainSessionToken: null"
        }
        do { _ = try await connection.read(host: "192.0.2.1", run: run); XCTFail("must reject failed connection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("音量控制已暂停")) }
        XCTAssertFalse(calls.contains { $0.contains("shell") })
        fail = false
        let result = try await connection.read(host: "192.0.2.1", run: run)
        XCTAssertEqual(result.current, .builtIn)
        XCTAssertEqual(calls.filter { $0.contains("kill-server") }.count, 1)
    }
    func testInvalidHostDoesNotTouchServer() async {
        let connection = TVInputConnection()
        do {
            _ = try await connection.read(host: "not-a-tv") { _ in XCTFail("must not execute"); return "" }
            XCTFail("must reject host")
        } catch {}
    }
}
