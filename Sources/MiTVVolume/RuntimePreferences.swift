import AppKit
import ServiceManagement
import VolumeCore

@MainActor final class RuntimePreferences {
    private let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: ["ShowMenuBarIcon": true, "StartInBackground": true, "VolumeQuietInterval": 0.5])
        migrateLegacySourceSelection()
    }
    private func migrateLegacySourceSelection() {
        if TVInputState.isLegacyADBIdentifier(defaults.string(forKey: "ComputerInputID")) {
            defaults.removeObject(forKey: "ComputerInputID")
            defaults.set(false, forKey: "SourceSwitchEnabled")
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

    /// When this Mac seizes the TV computer input, move external-display windows to the built-in screen.
    var windowMoveOnSeize: Bool {
        get { defaults.bool(forKey: "WindowMoveOnSeize") }
        set { defaults.set(newValue, forKey: "WindowMoveOnSeize") }
    }
    /// After a seize-move, restore saved frames when the TV leaves the computer input.
    var windowRestoreOnLeave: Bool {
        get {
            if defaults.object(forKey: "WindowRestoreOnLeave") == nil { return true }
            return defaults.bool(forKey: "WindowRestoreOnLeave")
        }
        set { defaults.set(newValue, forKey: "WindowRestoreOnLeave") }
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
