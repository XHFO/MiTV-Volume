import XCTest
@testable import VolumeCore

final class SetupQuotingTests: XCTestCase {
    func testShellKeepsSpecialCharactersLiteral() throws {
        let input = "/tmp/电视 ' \" $HOME $(printf injected) `printf injected`\n.app"
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \(SetupQuoting.shell(input))"]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: data, encoding: .utf8), input)
    }
    func testAdministratorScriptCompilesWithoutExecutingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = "/bin/bash \(SetupQuoting.shell("/tmp/电视's \\\"\n.app/enable-audio.sh"))"
        let script = SetupQuoting.authorization(command: command)
        let input = directory.appendingPathComponent("input.applescript")
        try script.write(to: input, atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", directory.appendingPathComponent("output.scpt").path, input.path]
        let pipe = Pipe(); process.standardError = pipe
        try process.run(); let errors = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors, as: UTF8.self))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("output.scpt").path))
    }
}
