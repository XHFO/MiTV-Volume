import AppKit
import ServiceManagement
import CoreAudio
import VolumeCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private var item: NSStatusItem!
    private let preferences = RuntimePreferences()
    private var deviceNameField: NSTextField!
    private var sourceToggle: NSButton!
    private var sourcePicker: NSPopUpButton!
    private var sourceLabel: NSTextField!
    private var sourceWorker: Task<Void, Never>?
    private let sourceReader = TVInputReader()
    private var sourceObservedAt = Date.distantPast
    private var sourceState: TVInputState?
    private var sourceInputs: [TVInputState] = []
    private var sourceMessage = "正在读取电视信号源…"
    private var fallbackPicker: NSPopUpButton!
    private var delayPicker: NSPopUpButton!
    private let quietIntervals: [TimeInterval] = [0, 0.3, 0.5, 1, 1.5, 2]
    private var loginToggle: NSButton!
    private var backgroundToggle: NSButton!
    private var trayToggle: NSButton!
    private var preferenceNote: NSTextField!
    private var loginSettingsButton: NSButton!
    private let statusItem = NSMenuItem(title: "未配置", action: nil, keyEquivalent: "")
    private var worker: Task<Void, Never>?
    private var discovery: Task<Void, Never>?
    private var lockFD: Int32 = -1
    private var activating = false
    private var activation: Task<Void, Never>?
    private var setupLabel: NSTextField!
    private var progress: NSProgressIndicator!
    private var cancelButton: NSButton!
    private var window: NSWindow?
    private var tvPicker: NSPopUpButton!
    private var outputPicker: NSPopUpButton!
    private var searchLabel: NSTextField!
    private var searchButton: NSButton!
    private var saveButton: NSButton!
    private var televisions: [DiscoveredTV] = []
    private var outputs: [ProxyDevice.Output] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiTVVolume")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFD = open(directory.appendingPathComponent("bridge.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "小米电视音量")
        let menu = NSMenu(); menu.addItem(statusItem); menu.addItem(.separator())
        let settings = NSMenuItem(title: "连接设置…", action: #selector(configure), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu
        item.isVisible = preferences.showMenuBarIcon
        if UserDefaults.standard.string(forKey: "TVHost") != nil && !UserDefaults.standard.bool(forKey: "PendingActivation") && (AudioSetup.isReady || !ProxyDevice.isConnected(UserDefaults.standard.string(forKey: "OutputUID") ?? "")) {
            // At login, macOS may have restored the physical display output after
            // the previous session ended. Resume its proxy without taking over headphones.
            let selectedOutput = UserDefaults.standard.string(forKey: "OutputUID")
            start(activate: ProxyDevice.currentOutputUID == selectedOutput)
            if !preferences.startInBackground { configure() }
        }
        else { configure() }
    }
    @objc func configure() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panelHeight = min(CGFloat(840), (NSScreen.main?.visibleFrame.height ?? 920) - 70)
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: panelHeight),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "小米电视音量"; panel.isReleasedWhenClosed = false; panel.delegate = self
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 840))
        scroll.documentView = content; panel.contentView!.addSubview(scroll)
        content.scroll(NSPoint(x: 0, y: 840 - panelHeight))
        func label(_ text: String, y: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: 24, y: y, width: 372, height: 20); content.addSubview(field); return field
        }
        _ = label("电视", y: 800)
        tvPicker = NSPopUpButton(frame: NSRect(x: 20, y: 766, width: 290, height: 30))
        tvPicker.target = self; tvPicker.action = #selector(selectionChanged)
        tvPicker.setAccessibilityLabel("自动发现的电视")
        searchButton = NSButton(title: "重新搜索", target: self, action: #selector(search))
        searchButton.bezelStyle = .rounded; searchButton.frame = NSRect(x: 312, y: 766, width: 88, height: 30)
        searchLabel = label("正在搜索局域网…", y: 736)
        searchLabel.font = .systemFont(ofSize: 11); searchLabel.textColor = .secondaryLabelColor
        _ = label("输出音频设备", y: 700)
        outputPicker = NSPopUpButton(frame: NSRect(x: 20, y: 666, width: 380, height: 30))
        outputPicker.setAccessibilityLabel("手动选择输出音频设备")
        outputPicker.target = self; outputPicker.action = #selector(selectionChanged)
        outputPicker.addItem(withTitle: "请选择输出设备")
        outputs = (try? ProxyDevice.outputs()) ?? []
        for output in outputs { outputPicker.addItem(withTitle: output.name) }
        if let uid = UserDefaults.standard.string(forKey: "OutputUID"), let index = outputs.firstIndex(where: { $0.uid == uid }) {
            outputPicker.selectItem(at: index + 1)
        }
        _ = label("系统音频设备名称", y: 632)
        deviceNameField = NSTextField(frame: NSRect(x: 24, y: 602, width: 372, height: 26))
        deviceNameField.stringValue = preferences.customDeviceName
        deviceNameField.delegate = self
        deviceNameField.setAccessibilityLabel("自定义音频设备名称")
        content.addSubview(deviceNameField)
        let nameHint = label("留空使用原设备名 +（音量控制）；编辑完成自动保存。", y: 578)
        nameHint.font = .systemFont(ofSize: 11); nameHint.textColor = .secondaryLabelColor
        _ = label("停止调整后再同步", y: 544)
        delayPicker = NSPopUpButton(frame: NSRect(x: 20, y: 512, width: 380, height: 30))
        delayPicker.addItems(withTitles: ["立即同步", "等待 0.3 秒", "等待 0.5 秒（默认）", "等待 1 秒", "等待 1.5 秒", "等待 2 秒"])
        delayPicker.selectItem(at: quietIntervals.firstIndex(of: preferences.volumeQuietInterval) ?? 2)
        delayPicker.target = self; delayPicker.action = #selector(delayChanged)
        delayPicker.setAccessibilityLabel("音量同步等待时间")
        content.addSubview(delayPicker)
        let delayHint = label("连续按音量键会重新计时，只发送最后的目标音量。", y: 488)
        delayHint.font = .systemFont(ofSize: 11); delayHint.textColor = .secondaryLabelColor
        sourceToggle = NSButton(checkboxWithTitle: "电视切换信号源时自动切换音频", target: self, action: #selector(toggleSourceSwitch))
        sourceToggle.frame = NSRect(x: 24, y: 444, width: 372, height: 26)
        sourceToggle.state = preferences.sourceSwitchEnabled ? .on : .off
        content.addSubview(sourceToggle)
        _ = label("电脑使用的电视输入", y: 412)
        sourcePicker = NSPopUpButton(frame: NSRect(x: 20, y: 378, width: 380, height: 30))
        sourcePicker.setAccessibilityLabel("电脑使用的电视输入")
        sourcePicker.target = self; sourcePicker.action = #selector(sourceSelectionChanged)
        content.addSubview(sourcePicker)
        sourceLabel = label(sourceMessage, y: 350)
        sourceLabel.font = .systemFont(ofSize: 11); sourceLabel.textColor = .secondaryLabelColor
        refreshSourceControls()
        _ = label("切走后的备用音频设备", y: 320)
        fallbackPicker = NSPopUpButton(frame: NSRect(x: 20, y: 286, width: 380, height: 30))
        fallbackPicker.target = self; fallbackPicker.action = #selector(fallbackChanged)
        fallbackPicker.setAccessibilityLabel("切走后的备用音频设备")
        content.addSubview(fallbackPicker)
        let fallbackHint = label("切回电脑输入后自动恢复；也适用于连接线断开。", y: 260)
        fallbackHint.font = .systemFont(ofSize: 11); fallbackHint.textColor = .secondaryLabelColor
        updateNamePlaceholder(); refreshFallbackOptions()
        let cancel = NSButton(title: "关闭", target: self, action: #selector(closeSettings))
        cancel.bezelStyle = .rounded; cancel.frame = NSRect(x: 190, y: 24, width: 86, height: 32); cancel.keyEquivalent = "\u{1b}"
        cancelButton = cancel
        saveButton = NSButton(title: "启用音量控制", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded; saveButton.frame = NSRect(x: 280, y: 24, width: 120, height: 32)
        saveButton.keyEquivalent = "\r"
        for view in [tvPicker!, searchButton!, outputPicker!, cancel, saveButton!] { content.addSubview(view) }
        setupLabel = NSTextField(wrappingLabelWithString: AudioSetup.isReady
            ? "选好电视和输出设备后，即可启用系统音量控制。"
            : "首次启用需要系统管理员授权，声音会短暂中断。应用会自动完成准备。")
        setupLabel.frame = NSRect(x: 24, y: 230, width: 372, height: 26)
        setupLabel.font = .systemFont(ofSize: 12); setupLabel.textColor = .secondaryLabelColor
        content.addSubview(setupLabel)
        let separator = NSBox(frame: NSRect(x: 24, y: 222, width: 372, height: 1))
        separator.boxType = .separator; content.addSubview(separator)
        trayToggle = NSButton(checkboxWithTitle: "显示菜单栏图标", target: self, action: #selector(toggleTray))
        trayToggle.frame = NSRect(x: 24, y: 184, width: 280, height: 26)
        trayToggle.state = preferences.showMenuBarIcon ? .on : .off
        loginToggle = NSButton(checkboxWithTitle: "登录 Mac 后自动启动", target: self, action: #selector(toggleLogin))
        loginToggle.frame = NSRect(x: 24, y: 152, width: 280, height: 26)
        backgroundToggle = NSButton(checkboxWithTitle: "启动后在后台运行", target: self, action: #selector(toggleBackground))
        backgroundToggle.frame = NSRect(x: 24, y: 120, width: 280, height: 26)
        backgroundToggle.state = preferences.startInBackground ? .on : .off
        preferenceNote = NSTextField(wrappingLabelWithString: "隐藏图标后，再次打开应用即可进入设置。")
        preferenceNote.font = .systemFont(ofSize: 11); preferenceNote.textColor = .secondaryLabelColor
        preferenceNote.frame = NSRect(x: 24, y: 69, width: 372, height: 44)
        loginSettingsButton = NSButton(title: "登录项设置…", target: self, action: #selector(openLoginSettings))
        loginSettingsButton.bezelStyle = .rounded
        loginSettingsButton.frame = NSRect(x: 280, y: 150, width: 120, height: 30)
        for view in [trayToggle!, loginToggle!, backgroundToggle!, preferenceNote!, loginSettingsButton!] { content.addSubview(view) }
        refreshLoginStatus()
        cancel.title = "隐藏到后台"
        cancel.frame = NSRect(x: 160, y: 24, width: 116, height: 32)
        progress = NSProgressIndicator(frame: NSRect(x: 24, y: 30, width: 18, height: 18))
        progress.style = .spinning; progress.isDisplayedWhenStopped = false; content.addSubview(progress)
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        search()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        configure(); return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if window != nil { refreshLoginStatus() }
    }
    private func refreshSourceControls() {
        guard window != nil || sourcePicker != nil else { return }
        guard sourcePicker != nil else { return }
        let currentIDs = sourcePicker.itemArray.dropFirst().compactMap { $0.representedObject as? String }
        var choices = sourceInputs
        if let saved = preferences.computerInputID, !choices.contains(where: { $0.identifier == saved }) {
            choices.append(.external(saved))
        }
        if sourcePicker.numberOfItems == 0 || currentIDs != choices.map(\.identifier) {
            sourcePicker.removeAllItems(); sourcePicker.addItem(withTitle: "请选择电脑所接的电视输入")
            for input in choices {
                sourcePicker.addItem(withTitle: input.label); sourcePicker.lastItem?.representedObject = input.identifier
            }
        }
        if let saved = preferences.computerInputID,
           let item = sourcePicker.itemArray.first(where: { $0.representedObject as? String == saved }) {
            sourcePicker.select(item)
        }
        sourceLabel.stringValue = sourceMessage
    }
    @objc private func sourceSelectionChanged() {
        preferences.computerInputID = sourcePicker.selectedItem?.representedObject as? String
    }
    @objc private func toggleSourceSwitch() {
        if sourceToggle.state == .on && preferences.computerInputID == nil {
            sourceToggle.state = .off
            sourceLabel.stringValue = "请先选择电脑使用的电视输入。"
            return
        }
        preferences.sourceSwitchEnabled = sourceToggle.state == .on
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
                if !self.preferences.sourceSwitchEnabled && self.window == nil {
                    stable.observe(nil); self.sourceState = nil
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                    continue
                }
                do {
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
                    let reading = try await self.sourceReader.read(host: host)
                    guard !Task.isCancelled else { break }
                    stable.observe(reading.current); self.sourceState = stable.value; self.sourceObservedAt = Date()
                    self.sourceInputs = reading.inputs
                    self.sourceMessage = stable.value.map { "电视当前：\($0.label)" } ?? "电视正在切换信号源…"
                } catch {
                    guard !Task.isCancelled else { break }
                    stable.observe(nil); self.sourceState = nil
                    self.sourceMessage = error.localizedDescription
                }
                if self.window != nil { self.refreshSourceControls() }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
            }
        }
    }
    private func refreshFallbackOptions() {
        guard fallbackPicker != nil else { return }
        let selectedIndex = outputPicker.indexOfSelectedItem - 1
        let primary = outputs.indices.contains(selectedIndex) ? outputs[selectedIndex].uid : nil
        fallbackPicker.removeAllItems(); fallbackPicker.addItem(withTitle: "Mac 内置扬声器（默认）")
        for output in outputs where output.uid != primary {
            fallbackPicker.addItem(withTitle: output.name)
            fallbackPicker.lastItem?.representedObject = output.uid
        }
        if let uid = preferences.fallbackOutputUID {
            if let item = fallbackPicker.itemArray.first(where: { $0.representedObject as? String == uid }) {
                fallbackPicker.select(item)
            } else if uid == primary {
                preferences.fallbackOutputUID = nil
            } else {
                fallbackPicker.addItem(withTitle: "未连接的备用设备（保留选择）")
                fallbackPicker.lastItem?.representedObject = uid
                fallbackPicker.select(fallbackPicker.lastItem)
            }
        }
    }
    @objc private func fallbackChanged() {
        preferences.fallbackOutputUID = fallbackPicker.selectedItem?.representedObject as? String
    }
    private func updateNamePlaceholder() {
        let index = outputPicker.indexOfSelectedItem - 1
        let name = outputs.indices.contains(index) ? outputs[index].name : "原设备名称"
        deviceNameField?.placeholderString = DeviceNaming.resolved(custom: "", outputName: name)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        _ = persistDeviceName()
    }
    @discardableResult private func persistDeviceName() -> Bool {
        do {
            let name = try DeviceNaming.validatedCustomName(deviceNameField.stringValue)
            preferences.customDeviceName = name; deviceNameField.stringValue = name
            return true
        } catch {
            setupLabel.stringValue = error.localizedDescription
            return false
        }
    }
    @objc private func delayChanged() {
        preferences.volumeQuietInterval = quietIntervals[delayPicker.indexOfSelectedItem]
    }
    @objc private func toggleTray() {
        preferences.showMenuBarIcon = trayToggle.state == .on
        item.isVisible = preferences.showMenuBarIcon
        preferenceNote.stringValue = "隐藏图标后，再次打开应用即可进入设置。"
    }
    @objc private func toggleBackground() {
        preferences.startInBackground = backgroundToggle.state == .on
    }
    @objc private func toggleLogin() {
        do {
            try preferences.setLoginEnabled(loginToggle.state == .on)
            refreshLoginStatus()
            preferenceNote.stringValue = preferences.loginStatus == .requiresApproval
                ? "请在系统登录项中允许本应用，返回后会自动更新状态。"
                : "登录时自动启动设置已保存。"
        } catch {
            refreshLoginStatus()
            preferenceNote.stringValue = "无法修改自动启动：\(error.localizedDescription)"
        }
    }
    private func refreshLoginStatus() {
        guard loginToggle != nil else { return }
        let status = preferences.loginStatus
        loginToggle.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        loginSettingsButton.isHidden = status != .requiresApproval
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func search() {
        guard !activating else { return }
        discovery?.cancel(); televisions = []
        tvPicker.removeAllItems(); tvPicker.addItem(withTitle: "正在自动发现电视…")
        tvPicker.isEnabled = false; searchButton.isEnabled = false; saveButton.isEnabled = false
        searchLabel.stringValue = "正在搜索局域网，无需填写 IP…"
        discovery = Task { [weak self] in
            let devices = await TVDiscovery.discover(preferredHost: UserDefaults.standard.string(forKey: "TVHost"))
            guard !Task.isCancelled, let self, self.window != nil else { return }
            self.televisions = devices; self.tvPicker.removeAllItems()
            self.tvPicker.addItem(withTitle: devices.isEmpty ? "未发现可用电视" : "请选择电视")
            for device in devices { self.tvPicker.addItem(withTitle: device.label) }
            let defaults = UserDefaults.standard
            let previous = TVDiscovery.matching(devices, identity: defaults.string(forKey: "TVIdentity"),
                previousHost: defaults.string(forKey: "TVHost") ?? "", previousName: defaults.string(forKey: "TVName") ?? "")
            if let previous, let index = devices.firstIndex(of: previous) { self.tvPicker.selectItem(at: index + 1) }
            else if devices.count == 1 { self.tvPicker.selectItem(at: 1) }
            self.tvPicker.isEnabled = !devices.isEmpty; self.searchButton.isEnabled = true
            self.searchLabel.stringValue = devices.isEmpty
                ? "未发现：请允许局域网访问，并检查电视连接。"
                : "已发现 \(devices.count) 台电视，IP 已自动获取。"
            self.selectionChanged()
        }
    }
    @objc private func selectionChanged() {
        updateNamePlaceholder(); refreshFallbackOptions()
        saveButton.isEnabled = !activating && tvPicker.indexOfSelectedItem > 0 && outputPicker.indexOfSelectedItem > 0
        if !activating { saveButton.title = "启用音量控制" }
    }
    @objc private func save() {
        guard !activating, tvPicker.indexOfSelectedItem > 0, outputPicker.indexOfSelectedItem > 0 else { return }
        guard persistDeviceName() else { return }
        let tv = televisions[tvPicker.indexOfSelectedItem - 1]
        let output = outputs[outputPicker.indexOfSelectedItem - 1]
        let defaults = UserDefaults.standard
        // Save the selection before asking for authorization. Cancellation must never
        // force the user to discover and select everything again.
        if defaults.string(forKey: "TVIdentity") != tv.identity || defaults.string(forKey: "TVName") != tv.name {
            preferences.sourceSwitchEnabled = false; preferences.computerInputID = nil
            sourceToggle.state = .off
        }
        defaults.set(tv.host, forKey: "TVHost"); defaults.set(tv.name, forKey: "TVName")
        defaults.set(tv.identity, forKey: "TVIdentity"); defaults.set(output.uid, forKey: "OutputUID")
        defaults.set(true, forKey: "PendingActivation")
        activating = true
        discovery?.cancel(); worker?.cancel()
        tvPicker.isEnabled = false; outputPicker.isEnabled = false; searchButton.isEnabled = false
        saveButton.isEnabled = false; cancelButton.isEnabled = false; progress.startAnimation(nil)
        saveButton.title = "正在启用…"
        let previousWorker = worker
        activation = Task { [weak self] in
            await previousWorker?.value
            guard let self else { return }
            do {
                try await AudioSetup.ensureReady { message in
                    self.setupLabel.stringValue = message; self.statusItem.title = message
                }
                self.setupLabel.stringValue = "正在读取电视音量并连接所选输出设备…"
                // Core Audio IDs may have changed when its service restarted: resolve UIDs again.
                try ProxyDevice.configure(outputUID: output.uid)
                try ProxyDevice.setName(DeviceNaming.resolved(custom: self.preferences.customDeviceName, outputName: output.name))
                guard let live = await TVDiscovery.probe(host: tv.host, session: TVDiscovery.session()),
                      TVDiscovery.matching([live], identity: tv.identity, previousHost: tv.host, previousName: tv.name) != nil else {
                    throw VolumeError("暂时无法连接所选电视。请确认电视在线后重试，或重新搜索。")
                }
                let sync = VolumeSync(device: ProxyDevice(), tv: MiTVClient(host: tv.host))
                await sync.tick()
                guard sync.connected else { throw VolumeError(sync.status) }
                if !self.preferences.sourceSwitchEnabled || self.sourceState?.identifier == self.preferences.computerInputID {
                    try ProxyDevice.makeDefault(ProxyDevice.uid)
                }
                defaults.set(false, forKey: "PendingActivation")
                self.setupLabel.stringValue = "已启用。现在可使用 macOS 音量滑块或音量键控制电视。"
                self.statusItem.title = sync.status
                self.start(activate: false)
                self.finishActivation(success: true)
            } catch {
                self.setupLabel.stringValue = error.localizedDescription
                self.statusItem.title = "未启用 · 可在连接设置中重试"
                self.finishActivation(success: false)
            }
        }
    }
    private func finishActivation(success: Bool) {
        activating = false; progress.stopAnimation(nil)
        tvPicker.isEnabled = !televisions.isEmpty; outputPicker.isEnabled = true
        searchButton.isEnabled = true; cancelButton.isEnabled = true
        saveButton.title = success ? "已启用" : "重试启用"
        saveButton.isEnabled = !success
    }
    @objc private func closeSettings() { if !activating && persistDeviceName() { window?.close(); NSApp.hide(nil) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !activating && persistDeviceName() }
    func windowWillClose(_ notification: Notification) { discovery?.cancel(); window = nil }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        activating ? .terminateCancel : .terminateNow
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
                        self.statusItem.title = "等待电视信号源确认 · 已暂停音量控制"
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
                            self.statusItem.title = "未找到所选电视 · 可在连接设置中重新选择"
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
                do { try await Task.sleep(nanoseconds: engine?.connected == true ? 100_000_000 : 1_000_000_000) }
                catch { break }
            }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        worker?.cancel(); discovery?.cancel(); sourceWorker?.cancel()
        if let executable = Bundle.main.url(forResource: "adb", withExtension: nil) {
            let stop = Process(); stop.executableURL = executable; stop.arguments = ["-P", "5047", "kill-server"]
            stop.standardOutput = FileHandle.nullDevice; stop.standardError = FileHandle.nullDevice
            try? stop.run()
        }
        if let proxy = try? ProxyDevice.lookup(ProxyDevice.uid), (try? ProxyDevice.defaultOutput()) == proxy,
           let uid = UserDefaults.standard.string(forKey: "OutputUID") { try? ProxyDevice.makeDefault(uid) }
        if lockFD >= 0 { close(lockFD) }
    }
}

@main struct Main {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--list-outputs") {
            for output in try ProxyDevice.outputs() { print("\(output.name)\t\(output.uid)") }
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
