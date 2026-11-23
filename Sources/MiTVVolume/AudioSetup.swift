import AppKit
import VolumeCore

/// The optional system component travels inside this one application bundle.
/// Authorization is requested only after the user presses “启用音量控制”.
@MainActor enum AudioSetup {
    static var isReady: Bool { (try? ProxyDevice().read()) != nil }

    static func ensureReady(progress: (String) -> Void) async throws {
        if isReady { return }
        guard let resources = Bundle.main.resourceURL else { throw VolumeError("应用文件不完整，请重新打开完整的应用。") }
        let script = resources.appendingPathComponent("enable-audio.sh")
        let driver = resources.appendingPathComponent("MiTVVolumeDriver.driver")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: driver.appendingPathComponent("Contents/Info.plist").path) else {
            throw VolumeError("应用内置组件缺失，请重新解压完整应用后重试。")
        }
        progress("请在系统弹窗中授权，完成后会自动继续。")
        let command = "/bin/bash \(SetupQuoting.shell(script.path)) \(SetupQuoting.shell(driver.path))"
        let appleScript = SetupQuoting.authorization(command: command)
        try await runAuthorization(appleScript)
        progress("正在连接系统音量控制，请稍候…")
        for _ in 0..<80 {
            try Task.checkCancellation()
            if isReady { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw VolumeError("系统音频服务尚未就绪。请稍后点“重试启用”；仍未恢复时重启 Mac，再打开本应用即可继续。")
    }
    private static func runAuthorization(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            // Use a file rather than a pipe so a verbose child cannot fill its pipe
            // while macOS is displaying the password prompt.
            let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("MiTV-enable-\(UUID().uuidString).log")
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            guard let handle = try? FileHandle(forWritingTo: logURL) else {
                continuation.resume(throwing: VolumeError("无法准备首次启用，请重试。")); return
            }
            process.standardOutput = handle; process.standardError = handle
            process.terminationHandler = { process in
                try? handle.close()
                let detail = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: logURL)
                if process.terminationStatus == 0 { continuation.resume() }
                else if detail.contains("(-128)") {
                    continuation.resume(throwing: VolumeError("已取消授权，选择已保留。点击“重试启用”可继续。"))
                } else {
                    continuation.resume(throwing: VolumeError("系统未能完成启用，选择已保留。请点“重试启用”。\n\(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))"))
                }
            }
            do { try process.run() }
            catch {
                try? handle.close(); try? FileManager.default.removeItem(at: logURL)
                continuation.resume(throwing: VolumeError("无法打开系统授权窗口，请重试。"))
            }
        }
    }
}
