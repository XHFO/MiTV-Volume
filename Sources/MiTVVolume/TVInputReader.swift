import Foundation
import VolumeCore

/// The ADB executable is bundled; no separate desktop or television app is installed.
actor TVInputReader {
    private let connection = TVInputConnection()
    private func run(_ arguments: [String], timeout: TimeInterval = 4) async throws -> String {
        guard let executable = Bundle.main.url(forResource: "adb", withExtension: nil) else {
            throw VolumeError("应用内缺少电视信号源组件")
        }
        let home = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiTVVolume/adb", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let existingKey = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".android/adbkey")
        let result = try await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = executable; process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["ANDROID_USER_HOME"] = home.path
            if FileManager.default.fileExists(atPath: existingKey.path) { environment["ADB_VENDOR_KEYS"] = existingKey.path }
            process.environment = environment
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); deadline.cancel()
            guard process.terminationStatus == 0 else {
                throw VolumeError("无法读取电视信号源，请在电视开启网络调试并允许此 Mac")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
        try Task.checkCancellation()
        return result
    }
    func read(host: String) async throws -> (current: TVInputState, inputs: [TVInputState]) {
        try await connection.read(host: host) { arguments in
            try await self.run(arguments)
        }
    }
}
