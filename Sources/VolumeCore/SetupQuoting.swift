import Foundation

/// These are two distinct encoding boundaries: shell argument, then AppleScript string.
public enum SetupQuoting {
    public static func authorization(command: String) -> String {
        "do shell script \(appleScript(command)) with administrator privileges"
    }
    public static func shell(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    public static func appleScript(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
