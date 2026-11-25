import Foundation

public struct TVInputState: Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    public var identifier: String { id }

    public static let builtIn = TVInputState(id: "__builtin__", label: "电视桌面 / 内置应用")

    public static func external(_ id: String, label: String? = nil) -> TVInputState {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "34" || trimmed == "__builtin__" {
            return .builtIn
        }
        let cleaned = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TVInputState(id: trimmed, label: (cleaned?.isEmpty == false ? cleaned! : nil)
            ?? Self.fallbackLabel(for: trimmed))
    }

    public static func == (lhs: TVInputState, rhs: TVInputState) -> Bool {
        lhs.id == rhs.id
    }

    /// Legacy ADB hardware IDs cannot be compared with XHFlow source numbers.
    public static func isLegacyADBIdentifier(_ id: String?) -> Bool {
        guard let id, !id.isEmpty else { return false }
        return id.contains("/") || id.hasPrefix("com.") || id.lowercased().contains("mediatek") || id.lowercased().contains("tvinput")
    }

    public static func fallbackLabel(for id: String) -> String {
        switch id {
        case "23": return "HDMI 1"
        case "24": return "HDMI 2"
        case "29": return "DP"
        case "30": return "USB-C / Type-C"
        case "34", "__builtin__": return builtIn.label
        default: return "输入 \(id)"
        }
    }

    /// Parse XHFlow `GET /api/status` JSON body.
    public static func parseStatus(_ root: [String: Any]) throws -> (current: TVInputState, inputs: [TVInputState]) {
        let inputs = availableInputs(root)
        guard let source = root["inputSource"] as? [String: Any] else {
            throw VolumeError("XH 光流尚未提供信号源，请在电视打开 XH 光流并保持配置后台开启")
        }
        let rawID: String?
        if source["id"] is NSNull { rawID = nil }
        else if let value = source["id"] as? String { rawID = value }
        else if let value = source["id"] as? Int { rawID = String(value) }
        else if let value = source["id"] as? NSNumber { rawID = value.stringValue }
        else { rawID = nil }
        guard let rawID, !rawID.isEmpty else {
            let detail = (root["displayError"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                throw VolumeError(detail)
            }
            throw VolumeError("电视当前信号源未知")
        }
        let known = source["known"] as? Bool ?? false
        let reported = (source["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = inputs.first { $0.id == rawID }
        let label: String
        if let matched { label = matched.label }
        else if known, let reported, !reported.isEmpty, reported != "未知" { label = reported }
        else { label = fallbackLabel(for: rawID) }
        let current = external(rawID, label: label)
        return (current, inputs)
    }

    public static func availableInputs(_ root: [String: Any]) -> [TVInputState] {
        guard let rows = root["inputsSupported"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var values: [TVInputState] = []
        for row in rows {
            let raw: String?
            if let value = row["id"] as? String { raw = value }
            else if let value = row["id"] as? Int { raw = String(value) }
            else if let value = row["id"] as? NSNumber { raw = value.stringValue }
            else { raw = nil }
            guard let raw, !raw.isEmpty, raw != "34" else { continue }
            guard seen.insert(raw).inserted else { continue }
            let label = (row["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            values.append(.external(raw, label: label))
        }
        return values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
