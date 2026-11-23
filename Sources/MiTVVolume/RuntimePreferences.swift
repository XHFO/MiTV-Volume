import AppKit
import ServiceManagement

@MainActor final class RuntimePreferences {
    private let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: ["ShowMenuBarIcon": true, "StartInBackground": true, "VolumeQuietInterval": 0.5])
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
        get { defaults.string(forKey: "ComputerInputID") }
        set { defaults.set(newValue, forKey: "ComputerInputID") }
    }
    var fallbackOutputUID: String? {
        get { defaults.string(forKey: "FallbackOutputUID") }
        set { defaults.set(newValue, forKey: "FallbackOutputUID") }
    }
    var customDeviceName: String {
        get { defaults.string(forKey: "CustomDeviceName") ?? "" }
        set { defaults.set(newValue, forKey: "CustomDeviceName") }
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
