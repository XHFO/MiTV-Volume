import AppKit
import ServiceManagement
import VolumeCore

@MainActor final class RuntimePreferences {
    private let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: [
            "ShowMenuBarIcon": true,
            "StartInBackground": true,
            "VolumeQuietInterval": 0.5,
            "WindowRestoreOnReturn": true
        ])
        migrateLegacySourceSelection()
        migrateWindowMovePreferences()
    }
    private func migrateLegacySourceSelection() {
        if TVInputState.isLegacyADBIdentifier(defaults.string(forKey: "ComputerInputID")) {
            defaults.removeObject(forKey: "ComputerInputID")
            defaults.set(false, forKey: "SourceSwitchEnabled")
        }
    }
    private func migrateWindowMovePreferences() {
        // 0.8.0 used seize→builtin; 0.8.1+ uses away→chosen display.
        if defaults.object(forKey: "WindowMoveOnAway") == nil, defaults.bool(forKey: "WindowMoveOnSeize") {
            defaults.set(true, forKey: "WindowMoveOnAway")
        }
        if defaults.object(forKey: "WindowRestoreOnReturn") == nil,
           defaults.object(forKey: "WindowRestoreOnLeave") != nil {
            defaults.set(defaults.bool(forKey: "WindowRestoreOnLeave"), forKey: "WindowRestoreOnReturn")
        }
    }
    var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: "ShowMenuBarIcon") }
        set { defaults.set(newValue, forKey: "ShowMenuBarIcon") }
    }
    var startInBackground: Bool {
        get { defaults.bool(forKey: "StartInBackground") }
        set { defaults.set(newValue, forKey: "StartInBackground") }
    }
    var sourceSwitchEnabled: Bool {
        get { defaults.bool(forKey: "SourceSwitchEnabled") }
        set { defaults.set(newValue, forKey: "SourceSwitchEnabled") }
    }
    var computerInputID: String? {
        get {
            let value = defaults.string(forKey: "ComputerInputID")
            return TVInputState.isLegacyADBIdentifier(value) ? nil : value
        }
        set { defaults.set(newValue, forKey: "ComputerInputID") }
    }
    var fallbackOutputUID: String? {
        get { defaults.string(forKey: "FallbackOutputUID") }
        set { defaults.set(newValue, forKey: "FallbackOutputUID") }
    }
    /// Pairing token for the television XHFlow configuration server. Never log this value.
    var xhflowToken: String? {
        get {
            let value = defaults.string(forKey: "XHFlowToken")?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { defaults.set(trimmed, forKey: "XHFlowToken") }
            else { defaults.removeObject(forKey: "XHFlowToken") }
        }
    }
    var deviceIconStyle: DeviceIconStyle {
        get { DeviceIconStyle(rawValue: defaults.integer(forKey: "DeviceIconStyle")) ?? .display }
        set { defaults.set(newValue.rawValue, forKey: "DeviceIconStyle") }
    }
    var customDeviceName: String {
        get { defaults.string(forKey: "CustomDeviceName") ?? "" }
        set { defaults.set(newValue, forKey: "CustomDeviceName") }
    }
    /// When the TV leaves the computer input, move windows onto the chosen display.
    var windowMoveOnAway: Bool {
        get { defaults.bool(forKey: "WindowMoveOnAway") }
        set { defaults.set(newValue, forKey: "WindowMoveOnAway") }
    }
    /// Target CGDirectDisplayID. nil selects the built-in display at runtime.
    var windowMoveTargetDisplayID: UInt32? {
        get {
            guard defaults.object(forKey: "WindowMoveTargetDisplayID") != nil else { return nil }
            return UInt32(bitPattern: Int32(truncatingIfNeeded: defaults.integer(forKey: "WindowMoveTargetDisplayID")))
        }
        set {
            if let newValue { defaults.set(Int(newValue), forKey: "WindowMoveTargetDisplayID") }
            else { defaults.removeObject(forKey: "WindowMoveTargetDisplayID") }
        }
    }
    /// After an away-move, restore saved frames when the TV returns to the computer input.
    var windowRestoreOnReturn: Bool {
        get { defaults.bool(forKey: "WindowRestoreOnReturn") }
        set { defaults.set(newValue, forKey: "WindowRestoreOnReturn") }
    }
    var volumeQuietInterval: TimeInterval {
        get { defaults.double(forKey: "VolumeQuietInterval") }
        set { defaults.set(newValue, forKey: "VolumeQuietInterval") }
    }
    var loginStatus: SMAppService.Status { SMAppService.mainApp.status }
    func setLoginEnabled(_ enabled: Bool) throws {
        if enabled {
            if loginStatus != .enabled { try SMAppService.mainApp.register() }
        } else if loginStatus != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
