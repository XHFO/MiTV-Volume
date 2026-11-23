import Foundation

public enum TVInputState: Equatable {
    case external(String)
    case builtIn
    public var identifier: String {
        switch self { case .external(let id): return id; case .builtIn: return "__builtin__" }
    }
    public var label: String {
        switch self {
        case .builtIn: return "电视桌面 / 内置应用"
        case .external(let id):
            if id == "com.mediatek.tvinput/.dp.DpInputService/HW10" { return "Type-C / DP 2" }
            if id == "com.mediatek.tvinput/.dp.DpInputService/HW9" { return "DP" }
            if id == "com.mediatek.tvinput/.hdmi.HDMIInputService/HW5" { return "HDMI 1" }
            if id == "com.mediatek.tvinput/.hdmi.HDMIInputService/HW6" { return "HDMI 2" }
            let suffix = id.components(separatedBy: "/").last ?? id
            if id.lowercased().contains(".dp.") { return "DP / Type-C（\(suffix)）" }
            if id.lowercased().contains(".hdmi.") { return "HDMI（\(suffix)）" }
            return suffix
        }
    }
    public static func availableInputs(_ dump: String) -> [TVInputState] {
        guard let start = dump.range(of: "inputMap: inputId -> TvInputState"),
              let end = dump.range(of: "  packageSet:", range: start.upperBound..<dump.endIndex) else { return [] }
        let section = String(dump[start.upperBound..<end.lowerBound])
        let pattern = #"(?m)^    ([^\s:]+/HW[0-9]+):"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: section, range: NSRange(section.startIndex..., in: section)).compactMap {
            guard let range = Range($0.range(at: 1), in: section) else { return nil }
            let id = String(section[range])
            guard id.contains(".dp.") || id.contains(".hdmi.") else { return nil }
            return .external(id)
        }.sorted { $0.label < $1.label }
    }
    /// Use the television's active session, never a remembered last-input setting or CEC history.
    public static func parse(_ dump: String) throws -> TVInputState {
        guard dump.contains("UserState ("),
              let tokenRange = dump.range(of: #"(?m)^\s*mainSessionToken: ([^\r\n]+)"#, options: .regularExpression) else {
            throw VolumeError("无法读取电视当前信号源，请检查电视的网络调试授权")
        }
        let token = dump[tokenRange].components(separatedBy: ": ").last!.trimmingCharacters(in: .whitespacesAndNewlines)
        if token == "null" { return .builtIn }
        guard let sessionStart = dump.range(of: "  sessionStateMap:"),
              let callbacks = dump.range(of: "  mCallbacks:", range: sessionStart.upperBound..<dump.endIndex) else {
            throw VolumeError("电视未提供有效的信号源会话")
        }
        let sessions = String(dump[sessionStart.upperBound..<callbacks.lowerBound])
        let pattern = #"(?m)^    "# + NSRegularExpression.escapedPattern(for: token) + #": [^\n]*\n      inputId: ([^\r\n]+)"#
        let expression = try NSRegularExpression(pattern: pattern)
        guard let match = expression.firstMatch(in: sessions, range: NSRange(sessions.startIndex..., in: sessions)),
              let range = Range(match.range(at: 1), in: sessions) else {
            throw VolumeError("电视正在切换信号源，等待稳定")
        }
        let id = String(sessions[range]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id != "null" else { throw VolumeError("电视当前信号源未知") }
        return .external(id)
    }
}

public struct StableTVInput {
    private var candidate: TVInputState?
    private var count = 0
    public private(set) var value: TVInputState?
    public init() {}
    public mutating func observe(_ next: TVInputState?) {
        guard let next else { candidate = nil; count = 0; value = nil; return }
        if candidate == next { count += 1 } else { candidate = next; count = 1; value = nil }
        if count >= 2 { value = next }
    }
}
