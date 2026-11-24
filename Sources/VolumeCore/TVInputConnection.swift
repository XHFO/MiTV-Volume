import Foundation

/// Owns the application's dedicated ADB service (port 5047), not the default
/// development server. Replace a surviving daemon once at application startup:
/// an application update can otherwise leave the old executable running.
public actor TVInputConnection {
    private var prepared = false
    private var connectedHost: String?
    private let port = "5047"
    public init() {}

    public func read(host: String, run: ([String]) async throws -> String) async throws
        -> (current: TVInputState, inputs: [TVInputState]) {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { throw VolumeError("电视地址无效") }
        do {
            if !prepared {
                _ = try await run(["-P", port, "kill-server"])
                try Task.checkCancellation()
                prepared = true
            }
            if connectedHost != host {
                let result = try await run(["-P", port, "connect", "\(host):5555"])
                try Task.checkCancellation()
                guard result.split(separator: "\n").contains(where: {
                    $0.hasPrefix("connected to \(host):5555") || $0.hasPrefix("already connected to \(host):5555")
                }) else {
                    throw VolumeError("电视信号源连接失败，音量控制已暂停；请检查电视网络调试和本机局域网权限")
                }
                connectedHost = host
            }
            let dump = try await run(["-P", port, "-s", "\(host):5555", "shell", "dumpsys", "tv_input"])
            try Task.checkCancellation()
            return (try TVInputState.parse(dump), TVInputState.availableInputs(dump))
        } catch { connectedHost = nil; throw error }
    }
}
