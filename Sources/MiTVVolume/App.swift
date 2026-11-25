import AppKit
import ServiceManagement
import CoreAudio
import VolumeCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let preferences = RuntimePreferences()
    private let statusItem = NSMenuItem(title: "未配置 · 请选择电视和输出设备", action: nil, keyEquivalent: "")
    private var worker: Task<Void, Never>?
    private var discovery: Task<Void, Never>?
    private var activation: Task<Void, Never>?
    private var lockFD: Int32 = -1
    private var activating = false
    private var searching = false
    private var menuOpen = false
    private var menuMessage = ""
    private var televisions: [DiscoveredTV] = []
    private var outputs: [ProxyDevice.Output] = []
    private var selectedTV: DiscoveredTV?
    private var selectedOutputUID: String?
    private let quietIntervals: [TimeInterval] = [0, 0.3, 0.5, 1, 1.5, 2]
    private var sourceWorker: Task<Void, Never>?
    private let sourceReader = TVInputReader()
    private var sourceObservedAt = Date.distantPast
    private var sourceState: TVInputState?
    private var sourceInputs: [TVInputState] = []
    private var sourceMessage = "信号源由电视端 XH 光流提供…"
    private let windowRelocator = WindowRelocator()
    private var lastComputerInputActive: Bool?
    private var windowMoveMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiTVVolume")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFD = open(directory.appendingPathComponent("bridge.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        let defaults = UserDefaults.standard
        selectedOutputUID = defaults.string(forKey: "OutputUID")
        if let host = defaults.string(forKey: "TVHost"), let name = defaults.string(forKey: "TVName") {
            selectedTV = .init(host: host, name: name, identity: defaults.string(forKey: "TVIdentity"))
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "小米电视音量")
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        item.menu = menu
        // A first launch must always offer an entry point, even with old hidden preferences.
        item.isVisible = preferences.showMenuBarIcon || selectedTV == nil || selectedOutputUID == nil || defaults.bool(forKey: "PendingActivation")
        rebuildMenu()
        if selectedTV != nil && !defaults.bool(forKey: "PendingActivation") &&
            (AudioSetup.isReady || !ProxyDevice.isConnected(selectedOutputUID ?? "")) {
            start(activate: ProxyDevice.currentOutputUID == selectedOutputUID)
        }
        search()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferences.showMenuBarIcon = true; item.isVisible = true
        rebuildMenu(); item.button?.performClick(nil)
        return false
    }
    func menuNeedsUpdate(_ menu: NSMenu) { if menu === item.menu { rebuildMenu() } }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector? = nil,
                                       checked: Bool = false, value: Any? = nil, enabled: Bool = true) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self; row.representedObject = value; row.state = checked ? .on : .off
        row.isEnabled = enabled && action != nil && !activating
        menu.addItem(row); return row
    }
    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(); child.autoenablesItems = false
        row.submenu = child; row.isEnabled = !activating; menu.addItem(row); return child
    }
    private func rebuildMenu() {
        guard let menu = item.menu else { return }
        outputs = (try? ProxyDevice.outputs()) ?? []
        menu.removeAllItems(); statusItem.isEnabled = false; menu.addItem(statusItem)
        if !menuMessage.isEmpty { add(menuMessage, to: menu) }
        menu.addItem(.separator())
        let tvMenu = submenu("电视：\(selectedTV?.name ?? "未选择")", in: menu)
        var choices = televisions
        if let selectedTV, !choices.contains(selectedTV) { choices.insert(selectedTV, at: 0) }
        for tv in choices {
            add(tv.label, to: tvMenu, action: #selector(selectTV(_:)), checked: tv == selectedTV, value: tv)
        }
        if choices.isEmpty { add(searching ? "正在搜索局域网…" : "未发现电视，请检查局域网授权", to: tvMenu) }
        tvMenu.addItem(.separator())
        add(searching ? "正在搜索…" : "重新搜索电视", to: tvMenu, action: #selector(search), enabled: !searching)
        let outputName = outputs.first { $0.uid == selectedOutputUID }?.name
        let outputMenu = submenu("输出设备：\(outputName ?? (selectedOutputUID == nil ? "未选择" : "未连接"))", in: menu)
        for output in outputs {
            add(output.name, to: outputMenu, action: #selector(selectOutput(_:)), checked: output.uid == selectedOutputUID, value: output.uid)
        }
        if outputs.isEmpty { add("没有可用的输出设备", to: outputMenu) }
        add(activating ? "正在启用…" : "启用所选电视和设备", to: menu, action: #selector(save),
            enabled: selectedTV != nil && outputName != nil)
        menu.addItem(.separator())
        let delay = submenu("停止调整后同步", in: menu)
        for value in quietIntervals {
            add(value == 0 ? "立即同步" : "等待 \(String(format: "%g", value)) 秒", to: delay,
                action: #selector(selectDelay(_:)), checked: value == preferences.volumeQuietInterval, value: value)
        }
        let source = submenu("电视信号源切换", in: menu)
        add(sourceMessage, to: source)
        let paired = preferences.xhflowToken != nil
        add(paired ? "重新配对 XH 光流…" : "配对电视端 XH 光流…", to: source, action: #selector(pairXHFlow))
        if paired { add("清除 XH 光流配对", to: source, action: #selector(clearXHFlowPairing)) }
        add("切走时自动切换音频", to: source, action: #selector(toggleSourceSwitch),
            checked: preferences.sourceSwitchEnabled, enabled: paired && preferences.computerInputID != nil)
        let inputs = submenu("电脑使用的电视输入", in: source)
        var sourceChoices = sourceInputs
        if let id = preferences.computerInputID, !sourceChoices.contains(where: { $0.identifier == id }) {
            sourceChoices.append(.external(id))
        }
        for input in sourceChoices {
            add(input.label, to: inputs, action: #selector(selectSource(_:)),
                checked: input.identifier == preferences.computerInputID, value: input.identifier, enabled: paired)
        }
        if sourceChoices.isEmpty {
            add(paired ? "等待 XH 光流返回输入列表…" : "请先配对电视端 XH 光流", to: inputs)
        }
        let fallback = submenu("切走后的音频设备", in: source)
        add("Mac 内置扬声器（默认）", to: fallback, action: #selector(selectFallback(_:)), checked: preferences.fallbackOutputUID == nil)
        for output in outputs where output.uid != selectedOutputUID {
            add(output.name, to: fallback, action: #selector(selectFallback(_:)), checked: output.uid == preferences.fallbackOutputUID, value: output.uid)
        }
        if let uid = preferences.fallbackOutputUID, !outputs.contains(where: { $0.uid == uid }) {
            add("未连接的备用设备（保留选择）", to: fallback, checked: true)
        }
        add("切回电脑输入后自动恢复", to: source)
        source.addItem(.separator())
        let canWindow = paired && preferences.computerInputID != nil
        let windowTitle = WindowRelocator.isTrusted
            ? "主机抢占电视输入时移到内置屏"
            : "主机抢占电视输入时移到内置屏（需辅助功能）"
        add(windowTitle, to: source, action: #selector(toggleWindowMove),
            checked: preferences.windowMoveOnSeize, enabled: canWindow)
        add("切离电脑输入后恢复窗口位置", to: source, action: #selector(toggleWindowRestore),
            checked: preferences.windowRestoreOnLeave,
            enabled: canWindow && preferences.windowMoveOnSeize)
        if preferences.windowMoveOnSeize && !WindowRelocator.isTrusted {
            add("在系统设置中允许辅助功能…", to: source, action: #selector(openAccessibilitySettings))
        }
        if !windowMoveMessage.isEmpty { add(windowMoveMessage, to: source) }
        let device = submenu("音频设备外观", in: menu)
        add("自定义设备名称…", to: device, action: #selector(renameDevice))
        add("恢复原设备名 +（音量控制）", to: device, action: #selector(resetDeviceName), checked: preferences.customDeviceName.isEmpty)
        let icons = submenu("设备图标", in: device)
        for style in DeviceIconStyle.menuChoices(retaining: preferences.deviceIconStyle) {
            let row = add(style.menuTitle, to: icons, action: #selector(selectIcon(_:)), checked: style == preferences.deviceIconStyle, value: style.rawValue)
            row.image = style.image
            row.toolTip = "仅更改设备外观；保留自定义名称及实际输出设备。"
        }
        if !ProxyDevice.supportsDeviceIcons {
            icons.addItem(.separator())
            add("更新音频图标支持…", to: icons, action: #selector(updateAudioComponent))
        }
        menu.addItem(.separator())
        let login = preferences.loginStatus
        let loginRow = add("登录 Mac 后自动启动", to: menu, action: #selector(toggleLogin), checked: login == .enabled)
        if login == .requiresApproval { loginRow.state = .mixed }
        if login == .requiresApproval { add("在系统设置中允许自动启动…", to: menu, action: #selector(openLoginSettings)) }
        add("隐藏菜单栏图标", to: menu, action: #selector(hideTray)).toolTip = "应用继续运行；再次打开应用即可恢复菜单栏图标。"
        menu.addItem(.separator())
        add("退出小米电视音量", to: menu, action: #selector(quit)).keyEquivalent = "q"
    }
    @objc private func selectTV(_ sender: NSMenuItem) {
        selectedTV = sender.representedObject as? DiscoveredTV
        menuMessage = "选择已暂存，点“启用所选电视和设备”应用"
    }
    @objc private func selectOutput(_ sender: NSMenuItem) {
        selectedOutputUID = sender.representedObject as? String
        menuMessage = "选择已暂存，点“启用所选电视和设备”应用"
    }
    @objc private func selectDelay(_ sender: NSMenuItem) {
        guard let delay = sender.representedObject as? TimeInterval else { return }
        preferences.volumeQuietInterval = delay; menuMessage = ""
    }
    @objc private func selectSource(_ sender: NSMenuItem) { preferences.computerInputID = sender.representedObject as? String }
    @objc private func toggleSourceSwitch() { preferences.sourceSwitchEnabled.toggle() }
    @objc private func pairXHFlow() {
        let alert = NSAlert()
        alert.messageText = "配对电视端 XH 光流"
        alert.informativeText = "在电视打开 XH 光流，开启配置后台，将二维码链接或 32 位配对码粘贴到下方。信号源读取不再使用 ADB / 网络调试。"
        let field = NSTextField(string: preferences.xhflowToken ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 26)
        field.placeholderString = "http://电视IP:8768/?token=… 或配对码"
        field.setAccessibilityLabel("XH 光流配对")
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            preferences.xhflowToken = try XHFlowClient.validatedToken(field.stringValue)
            menuMessage = "已保存 XH 光流配对"
            startSourceMonitor()
        } catch {
            menuMessage = error.localizedDescription
        }
    }
    @objc private func clearXHFlowPairing() {
        preferences.xhflowToken = nil
        preferences.sourceSwitchEnabled = false
        sourceState = nil
        sourceInputs = []
        sourceMessage = "已清除配对，请重新配对电视端 XH 光流"
        menuMessage = sourceMessage
        startSourceMonitor()
    }

    @objc private func toggleWindowMove() {
        if !preferences.windowMoveOnSeize && !WindowRelocator.isTrusted {
            _ = WindowRelocator.requestTrust()
        }
        preferences.windowMoveOnSeize.toggle()
        if !preferences.windowMoveOnSeize {
            lastComputerInputActive = nil
            windowRelocator.clearSnapshots()
            windowMoveMessage = ""
        } else if !WindowRelocator.isTrusted {
            windowMoveMessage = "请在系统设置 → 隐私与安全性 → 辅助功能中允许“小米电视音量”"
        } else {
            windowMoveMessage = "已开启：电视切到电脑输入并稳定后，外接屏普通窗口会移到内置屏"
            applyWindowPolicy(for: sourceState, force: true)
        }
        menuMessage = windowMoveMessage
    }
    @objc private func toggleWindowRestore() { preferences.windowRestoreOnLeave.toggle() }
    @objc private func openAccessibilitySettings() { WindowRelocator.openAccessibilitySettings() }

    private func applyWindowPolicy(for state: TVInputState?, force: Bool = false) {
        guard preferences.windowMoveOnSeize,
              let computer = preferences.computerInputID,
              let state else { return }
        let active = state.identifier == computer
        if !force, lastComputerInputActive == active { return }
        lastComputerInputActive = active
        if active {
            guard WindowRelocator.isTrusted else {
                windowMoveMessage = "主机已在电脑输入，但缺少辅助功能权限"
                return
            }
            windowRelocator.moveExternalWindowsToBuiltin()
            windowMoveMessage = windowRelocator.lastMessage
        } else if preferences.windowRestoreOnLeave {
            guard WindowRelocator.isTrusted else { return }
            windowRelocator.restoreMovedWindows()
            windowMoveMessage = windowRelocator.lastMessage
        }
    }
    @objc private func selectFallback(_ sender: NSMenuItem) { preferences.fallbackOutputUID = sender.representedObject as? String }
    @objc private func selectIcon(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int, let style = DeviceIconStyle(rawValue: raw) else { return }
        preferences.deviceIconStyle = style
        // Name is independently owned by customDeviceName / renameDevice.
        // Never derive it from a style title or reset it during reclassification.
        do { try ProxyDevice.setIcon(style); menuMessage = style.systemHint }
        catch { menuMessage = error.localizedDescription }
    }
    @objc private func updateAudioComponent() {
        guard !activating else { return }
        activating = true
        activation = Task { [weak self] in
            guard let self else { return }
            defer { self.activating = false }
            do {
                try await AudioSetup.ensureReady { self.statusItem.title = $0 }
                try ProxyDevice.setIcon(self.preferences.deviceIconStyle)
                self.menuMessage = self.preferences.deviceIconStyle.systemHint
            } catch { self.menuMessage = error.localizedDescription }
        }
    }
    @objc private func resetDeviceName() { preferences.customDeviceName = ""; menuMessage = "" }
    @objc private func renameDevice() {
        let alert = NSAlert(); alert.messageText = "自定义音频设备名称"
        alert.informativeText = "留空使用原设备名 +（音量控制）。"
        let field = NSTextField(string: preferences.customDeviceName)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 26)
        field.setAccessibilityLabel("音频设备名称")
        alert.accessoryView = field; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field; NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            do { preferences.customDeviceName = try DeviceNaming.validatedCustomName(field.stringValue); menuMessage = "" }
            catch { menuMessage = error.localizedDescription }
        }
    }
    @objc private func hideTray() { preferences.showMenuBarIcon = false; item.isVisible = false }
    @objc private func toggleLogin() {
        do { try preferences.setLoginEnabled(preferences.loginStatus != .enabled && preferences.loginStatus != .requiresApproval); menuMessage = "" }
        catch { menuMessage = "无法修改自动启动：\(error.localizedDescription)" }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func search() {
        guard !activating else { return }
        discovery?.cancel(); searching = true
        discovery = Task { [weak self] in
            let devices = await TVDiscovery.discover(preferredHost: UserDefaults.standard.string(forKey: "TVHost"))
            guard !Task.isCancelled, let self else { return }
            self.televisions = devices; self.searching = false
            if let previous = self.selectedTV,
               let found = TVDiscovery.matching(devices, identity: previous.identity, previousHost: previous.host, previousName: previous.name) {
                self.selectedTV = found
            } else if self.selectedTV == nil && devices.count == 1 { self.selectedTV = devices.first }
            if !self.menuOpen { self.rebuildMenu() }
        }
    }
    @objc private func save() {
        guard !activating, let tv = selectedTV, let uid = selectedOutputUID,
              let output = ((try? ProxyDevice.outputs()) ?? []).first(where: { $0.uid == uid }) else { return }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "TVIdentity") != tv.identity || defaults.string(forKey: "TVName") != tv.name {
            preferences.sourceSwitchEnabled = false; preferences.computerInputID = nil
        }
        if preferences.fallbackOutputUID == output.uid { preferences.fallbackOutputUID = nil }
        defaults.set(tv.host, forKey: "TVHost"); defaults.set(tv.name, forKey: "TVName")
        defaults.set(tv.identity, forKey: "TVIdentity"); defaults.set(output.uid, forKey: "OutputUID")
        defaults.set(true, forKey: "PendingActivation")
        activating = true; menuMessage = ""; statusItem.title = "正在启用…"
        discovery?.cancel(); searching = false; worker?.cancel(); sourceWorker?.cancel()
        let previousWorker = worker
        activation = Task { [weak self] in
            await previousWorker?.value
            guard let self else { return }
            defer { self.activating = false }
            do {
                try await AudioSetup.ensureReady { self.statusItem.title = $0 }
                try ProxyDevice.configure(outputUID: output.uid)
                try ProxyDevice.setIcon(self.preferences.deviceIconStyle)
                try ProxyDevice.setName(DeviceNaming.resolved(custom: self.preferences.customDeviceName, outputName: output.name))
                guard let live = await TVDiscovery.probe(host: tv.host, session: TVDiscovery.session()),
                      TVDiscovery.matching([live], identity: tv.identity, previousHost: tv.host, previousName: tv.name) != nil else {
                    throw VolumeError("无法连接所选电视，请检查连接后重试或重新搜索")
                }
                let sync = VolumeSync(device: ProxyDevice(), tv: MiTVClient(host: tv.host))
                await sync.tick()
                guard sync.connected else { throw VolumeError(sync.status) }
                if !self.preferences.sourceSwitchEnabled { try ProxyDevice.makeDefault(ProxyDevice.uid) }
                defaults.set(false, forKey: "PendingActivation")
                self.statusItem.title = sync.status
                self.start(activate: self.preferences.sourceSwitchEnabled)
            } catch {
                self.statusItem.title = "未启用 · 请重试"
                self.menuMessage = error.localizedDescription
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        activating ? .terminateCancel : .terminateNow
    }
    private func startSourceMonitor() {
        let previous = sourceWorker; previous?.cancel(); sourceState = nil
        sourceWorker = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            var stable = StableTVInput()
            var verifiedHost: String?; var verificationTime = Date.distantPast
            var nextDiscovery = Date.distantPast
            let defaults = UserDefaults.standard
            while !Task.isCancelled {
                let wantsStatus = self.preferences.sourceSwitchEnabled || self.menuOpen || self.preferences.xhflowToken != nil
                if !wantsStatus {
                    stable.observe(nil); self.sourceState = nil
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                    continue
                }
                do {
                    guard let token = self.preferences.xhflowToken else {
                        throw VolumeError("请先配对电视端 XH 光流（菜单 → 电视信号源切换）")
                    }
                    guard var host = defaults.string(forKey: "TVHost") else { break }
                    if verifiedHost != host || Date().timeIntervalSince(verificationTime) > 15 {
                        let identity = defaults.string(forKey: "TVIdentity")
                        let name = defaults.string(forKey: "TVName") ?? ""
                        let probe = await TVDiscovery.probe(host: host, session: TVDiscovery.session())
                        if let probe, TVDiscovery.matching([probe], identity: identity, previousHost: host, previousName: name) != nil {
                            verifiedHost = host; verificationTime = Date()
                        } else {
                            if Date() >= nextDiscovery {
                                nextDiscovery = Date().addingTimeInterval(10)
                                let devices = await TVDiscovery.discover(preferredHost: host)
                                if let found = TVDiscovery.matching(devices, identity: identity, previousHost: host, previousName: name) {
                                    host = found.host; defaults.set(host, forKey: "TVHost")
                                    verifiedHost = host; verificationTime = Date()
                                } else { throw VolumeError("电视离线，等待重新连接") }
                            } else { throw VolumeError("正在重新查找电视") }
                        }
                    }
                    let reading = try await self.sourceReader.read(host: host, token: token)
                    guard !Task.isCancelled else { break }
                    stable.observe(reading.current); self.sourceState = stable.value; self.sourceObservedAt = Date()
                    self.sourceInputs = reading.inputs
                    self.sourceMessage = stable.value.map { "电视当前：\($0.label) · 经 XH 光流" } ?? "电视正在切换信号源…"
                    if let confirmed = stable.value {
                        self.applyWindowPolicy(for: confirmed)
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    stable.observe(nil); self.sourceState = nil
                    self.sourceMessage = error.localizedDescription
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
            }
        }
    }
    private func start(activate: Bool) {
        startSourceMonitor()
        worker?.cancel()
        let defaults = UserDefaults.standard
        guard let initialHost = defaults.string(forKey: "TVHost"), let name = defaults.string(forKey: "TVName"),
              let outputUID = defaults.string(forKey: "OutputUID") else { return }
        let identity = defaults.string(forKey: "TVIdentity")
        let oldWorker = worker
        worker = Task { [weak self] in
            await oldWorker?.value
            guard !Task.isCancelled, let self else { return }
            var host = initialHost
            var engine: VolumeSync?
            var shouldActivate = activate
            var configuredID: UInt32?
            var configuredName: String?
            var recovery = OutputRecovery()
            var nextDiscovery = Date.distantPast
            let probeSession = TVDiscovery.session()
            while !Task.isCancelled {
                do {
                    let physicalConnected = ProxyDevice.isConnected(outputUID)
                    let currentOutput = ProxyDevice.currentOutputUID
                    if shouldActivate && currentOutput != outputUID && currentOutput != ProxyDevice.uid {
                        shouldActivate = false
                    }
                    let sourceEnabled = self.preferences.sourceSwitchEnabled && self.preferences.computerInputID != nil
                    if physicalConnected && sourceEnabled && (self.sourceState == nil || Date().timeIntervalSince(self.sourceObservedAt) > 3.5) {
                        engine?.invalidate()
                        self.statusItem.title = "音量控制已暂停 · \(self.sourceMessage)"
                        self.item.button?.toolTip = self.statusItem.title
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    let sourceAway = sourceEnabled && self.sourceState.map { $0.identifier != self.preferences.computerInputID } == true
                    // A source change is independent of the Mac's physical audio connection.
                    guard physicalConnected && !sourceAway else {
                        var missingFallback = false
                        let ownedOutput = shouldActivate && currentOutput == outputUID ? ProxyDevice.uid : currentOutput
                        if recovery.disconnected(defaultUID: ownedOutput, proxyUID: ProxyDevice.uid,
                            preferredFallbackUID: self.preferences.fallbackOutputUID) {
                            if let fallback = try ProxyDevice.useFallback(preferredUID: self.preferences.fallbackOutputUID) {
                                recovery.usedFallback(fallback)
                            } else { missingFallback = true }
                        }
                        engine?.invalidate(); configuredID = nil
                        self.statusItem.title = missingFallback ? "备用音频设备未连接" :
                            sourceAway ? "电视已切走 · 使用备用音频设备" : "输出设备已断开 · 等待重新连接"
                        self.item.button?.toolTip = self.statusItem.title
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    let restore = recovery.connected(defaultUID: ProxyDevice.currentOutputUID,
                        proxyUID: ProxyDevice.uid, physicalUID: outputUID)
                    let proxyID = try ProxyDevice.lookup(ProxyDevice.uid)
                    if configuredID != proxyID {
                        try ProxyDevice.configure(outputUID: outputUID)
                        if ProxyDevice.supportsDeviceIcons { try ProxyDevice.setIcon(self.preferences.deviceIconStyle) }
                        configuredID = proxyID; configuredName = nil; engine?.invalidate()
                    }
                    let outputName = try ProxyDevice.string(ProxyDevice.lookup(outputUID), kAudioObjectPropertyName)
                    let deviceName = DeviceNaming.resolved(custom: self.preferences.customDeviceName, outputName: outputName)
                    if configuredName != deviceName {
                        try ProxyDevice.setName(deviceName); configuredName = deviceName
                    }
                    if engine == nil && Date() >= nextDiscovery {
                        self.statusItem.title = "正在自动查找电视…"
                        var found: DiscoveredTV?
                        if let candidate = await TVDiscovery.probe(host: host, session: probeSession) {
                            found = TVDiscovery.matching([candidate], identity: identity, previousHost: host, previousName: name)
                        }
                        if found == nil {
                            let candidates = await TVDiscovery.discover(preferredHost: host)
                            found = TVDiscovery.matching(candidates, identity: identity, previousHost: host, previousName: name)
                        }
                        guard !Task.isCancelled else { break }
                        if let found {
                            host = found.host; defaults.set(host, forKey: "TVHost")
                            engine = VolumeSync(device: ProxyDevice(), tv: MiTVClient(host: host))
                        } else {
                            self.statusItem.title = "未找到所选电视 · 请在菜单中重新选择"
                            nextDiscovery = Date().addingTimeInterval(10)
                        }
                    }
                    if let sync = engine {
                        sync.quietInterval = self.preferences.volumeQuietInterval
                        await sync.tick()
                        guard !Task.isCancelled else { break }
                        if (shouldActivate || restore) && sync.connected {
                            try ProxyDevice.makeDefault(ProxyDevice.uid); shouldActivate = false
                            recovery.restored(proxyUID: ProxyDevice.uid)
                        }
                        self.statusItem.title = sync.status
                        if !sync.connected {
                            engine = nil; nextDiscovery = Date().addingTimeInterval(2)
                        }
                    }
                } catch {
                    engine?.invalidate(); configuredID = nil
                    self.statusItem.title = "未同步 · \(error.localizedDescription)"
                }
                self.item.button?.toolTip = self.statusItem.title
                do {
                    let delay = engine?.nextTickDelay ?? 1
                    if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    else { await Task.yield() }
                }
                catch { break }
            }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        worker?.cancel(); discovery?.cancel(); sourceWorker?.cancel()
        if let proxy = try? ProxyDevice.lookup(ProxyDevice.uid), (try? ProxyDevice.defaultOutput()) == proxy,
           let uid = UserDefaults.standard.string(forKey: "OutputUID") { try? ProxyDevice.makeDefault(uid) }
        if lockFD >= 0 { close(lockFD) }
    }
}

@main struct Main {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--list-outputs") {
            for output in try ProxyDevice.outputs() { print("\(output.name)\t\(output.uid)") }
        } else if CommandLine.arguments.contains("--prepare-audio") {
            // Runs the same in-app authorization flow without changing TV or routing selections.
            let app = NSApplication.shared; app.setActivationPolicy(.accessory)
            Task {
                do {
                    try await AudioSetup.ensureReady { print($0); fflush(stdout) }
                    print("Audio component ready"); exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            app.run()
        } else if CommandLine.arguments.contains("--discover") {
            Task {
                let devices = await TVDiscovery.discover()
                for device in devices { print(device.label) }
                print("发现 \(devices.count) 台支持音量读取的电视")
                exit(0)
            }
            dispatchMain()
        } else {
            let app = NSApplication.shared; app.setActivationPolicy(.accessory)
            let delegate = AppDelegate(); app.delegate = delegate; app.run()
        }
    }
}
