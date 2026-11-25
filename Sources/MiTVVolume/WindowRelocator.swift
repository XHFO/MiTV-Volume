import AppKit
import ApplicationServices
import VolumeCore

/// Moves other apps' windows from external displays onto the built-in screen.
/// Requires Accessibility permission. Full-screen games are skipped in v1.
@MainActor final class WindowRelocator {
    struct Snapshot {
        let pid: pid_t
        let title: String
        let role: String
        let frame: CGRect
    }

    private var snapshots: [Snapshot] = []
    private(set) var lastMessage = ""

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private var builtinScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSScreen.screens.first { $0 == NSScreen.main } ?? NSScreen.screens.first
    }

    private var externalScreens: [NSScreen] {
        guard let builtin = builtinScreen else { return [] }
        return NSScreen.screens.filter { $0 != builtin }
    }

    /// Move windows whose center is on an external display onto the built-in display.
    func moveExternalWindowsToBuiltin() {
        guard Self.isTrusted else {
            lastMessage = "需要辅助功能权限才能移动其它应用窗口"
            return
        }
        guard let builtin = builtinScreen else {
            lastMessage = "未找到内置显示器"
            return
        }
        let externals = externalScreens
        guard !externals.isEmpty else {
            lastMessage = "当前没有外接显示器上的窗口可移动"
            return
        }

        var moved = 0
        var saved: [Snapshot] = []
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != selfPID && !$0.isTerminated
        }

        for app in running {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsObject: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsObject) == .success,
                  let windows = windowsObject as? [AXUIElement] else { continue }

            for window in windows {
                guard let frame = frame(of: window) else { continue }
                if isMinimized(window) { continue }
                guard let host = externals.first(where: { WindowPlacement.window(frame, isPrimarilyOn: $0.frame) }) else { continue }
                if WindowPlacement.looksFullScreen(window: frame, screen: host.frame) { continue }
                if isFullScreenAttribute(window) { continue }

                let title = stringValue(window, kAXTitleAttribute as CFString) ?? app.localizedName ?? ""
                let role = stringValue(window, kAXRoleAttribute as CFString) ?? ""
                saved.append(Snapshot(pid: app.processIdentifier, title: title, role: role, frame: frame))

                let target = WindowPlacement.relocatedFrame(window: frame, from: host.frame, to: builtin.frame)
                if setFrame(window, target) { moved += 1 }
            }
        }

        if moved > 0 { snapshots = saved }
        lastMessage = moved > 0 ? "已将 \(moved) 个窗口移到内置屏" : "外接屏上没有可移动的普通窗口"
    }

    /// Restore windows moved by the last seize action when possible.
    func restoreMovedWindows() {
        guard Self.isTrusted else {
            lastMessage = "需要辅助功能权限才能恢复窗口位置"
            return
        }
        guard !snapshots.isEmpty else {
            lastMessage = "没有可恢复的窗口记录"
            return
        }
        var restored = 0
        for item in snapshots {
            guard let window = findWindow(pid: item.pid, title: item.title, role: item.role) else { continue }
            if isMinimized(window) || isFullScreenAttribute(window) { continue }
            if setFrame(window, item.frame) { restored += 1 }
        }
        snapshots.removeAll()
        lastMessage = restored > 0 ? "已恢复 \(restored) 个窗口位置" : "未能恢复窗口位置（应用可能已关闭）"
    }

    func clearSnapshots() { snapshots.removeAll() }

    private func findWindow(pid: pid_t, title: String, role: String) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsObject: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsObject) == .success,
              let windows = windowsObject as? [AXUIElement] else { return nil }
        let matches = windows.filter { window in
            let t = stringValue(window, kAXTitleAttribute as CFString) ?? ""
            let r = stringValue(window, kAXRoleAttribute as CFString) ?? ""
            return t == title && r == role
        }
        return matches.count == 1 ? matches[0] : matches.first
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = copyAXValue(window, kAXPositionAttribute as CFString),
              let size = copyAXValue(window, kAXSizeAttribute as CFString) else { return nil }
        var point = CGPoint.zero
        var wh = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &wh) else { return nil }
        return CGRect(origin: point, size: wh)
    }

    private func setFrame(_ window: AXUIElement, _ frame: CGRect) -> Bool {
        var origin = frame.origin
        var size = frame.size
        guard let pos = AXValueCreate(.cgPoint, &origin),
              let wh = AXValueCreate(.cgSize, &size) else { return false }
        let p = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        let s = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, wh)
        return p == .success || s == .success
    }

    private func copyAXValue(_ element: AXUIElement, _ attribute: CFString) -> AXValue? {
        var object: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &object) == .success else { return nil }
        return object as! AXValue?
    }

    private func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var object: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &object) == .success else { return nil }
        return object as? String
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        var object: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &object) == .success,
              let value = object as? Bool else { return false }
        return value
    }

    private func isFullScreenAttribute(_ window: AXUIElement) -> Bool {
        var object: AnyObject?
        // Undocumented but widely used; ignore if missing.
        let fullScreen = "AXFullScreen" as CFString
        guard AXUIElementCopyAttributeValue(window, fullScreen, &object) == .success,
              let value = object as? Bool else { return false }
        return value
    }
}
