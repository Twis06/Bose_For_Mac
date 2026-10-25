import AppKit
import ServiceManagement

final class SliderRow: NSView {
    let slider: NSSlider
    let valueLabel = NSTextField(labelWithString: "")
    var action: ((Int) -> Void)?
    init(title: String, value: Int, minimum: Int, maximum: Int, enabled: Bool, endpoints: String? = nil, action: @escaping (Int) -> Void) {
        slider = NSSlider(value: Double(value), minValue: Double(minimum), maxValue: Double(maximum), target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 264, height: endpoints == nil ? 62 : 78))
        self.action = action
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 16, y: frame.height - 24, width: 185, height: 18)
        addSubview(label)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.stringValue = "\(value)"
        valueLabel.frame = NSRect(x: 209, y: frame.height - 24, width: 38, height: 18)
        addSubview(valueLabel)
        slider.frame = NSRect(x: 14, y: frame.height - 51, width: 236, height: 22)
        slider.isContinuous = false
        slider.numberOfTickMarks = maximum - minimum + 1
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isEnabled = enabled
        slider.target = self
        slider.action = #selector(change)
        slider.setAccessibilityLabel(title)
        addSubview(slider)
        if let endpoints {
            let hint = NSTextField(labelWithString: endpoints)
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .secondaryLabelColor
            hint.frame = NSRect(x: 16, y: 4, width: 232, height: 15)
            addSubview(hint)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func change() {
        let value = Int(slider.doubleValue.rounded())
        valueLabel.stringValue = "\(value)"
        action?(value)
    }
}

final class MenuAction: NSObject {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
    @objc func run() { perform() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = BoseModel(demo: CommandLine.arguments.contains("--export-demo") || CommandLine.arguments.contains("--demo"))
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var actions: [MenuAction] = []
    private var open = false
    private var rebuildScheduled = false
    private var modeRebuildTimer: Timer?
    private var header: NSMenuItem?
    private var stateItem: NSMenuItem?
    private var sliders: [String: SliderRow] = [:]
    private var presetItems: [String: NSMenuItem] = [:]
    private var eqMenuItem: NSMenuItem?
    private var modeItems: [UInt8: NSMenuItem] = [:]
    private var observerTokens: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        UserDefaults.standard.register(defaults: ["showBatteryBar": true])
        statusItem.button?.image = StatusIcon.image(battery: model.battery, showBattery: showBatteryBar)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("Bose headphone controls")
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        model.changed = { [weak self] in self?.update() }
        rebuild()
        if model.isDemo {
            if let index = CommandLine.arguments.firstIndex(of: "--export-demo"), CommandLine.arguments.count > index + 1 {
                do {
                    try DemoRenderer.export(menu: menu, to: CommandLine.arguments[index + 1])
                    NSApplication.shared.terminate(nil)
                } catch { fputs("Demo export failed: \(error)\n", stderr); exit(1) }
            }
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.model.sleep() })
        observerTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.model.connect() }
        })
        if CommandLine.arguments.contains("--diagnose") {
            model.log = { line in
                let path = "/tmp/bosebar-diagnostic.log"
                let data = Data((line + "\n").utf8)
                if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
                if let file = FileHandle(forWritingAtPath: path) { file.seekToEndOfFile(); file.write(data); try? file.close() }
            }
            model.log?("App launched via bundle; devices: " + BoseBluetooth.devices().map { "\($0.name ?? "?") connected=\($0.isConnected())" }.joined(separator: ", "))
        }
        model.start()
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.statusItem.button?.performClick(nil) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--device"), CommandLine.arguments.count > index + 1 {
            let address = CommandLine.arguments[index + 1].lowercased().replacingOccurrences(of: ":", with: "-")
            if let device = BoseBluetooth.devices().first(where: { $0.addressString == address }) { model.connect(device) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.bluetooth.disconnect() }
    func menuWillOpen(_ menu: NSMenu) { rebuild(); open = true; model.refresh() }
    func menuDidClose(_ menu: NSMenu) { open = false; scheduleRebuild() }

    private func update() {
        let battery = model.battery.map { "\($0)%" } ?? ""
        statusItem.button?.title = ""
        statusItem.button?.image = StatusIcon.image(battery: model.battery, showBattery: showBatteryBar)
        statusItem.button?.setAccessibilityLabel(model.battery.map { "Bose headphone controls, battery \($0) percent" } ?? "Bose headphone controls, battery unavailable")
        statusItem.button?.appearsDisabled = !model.ready
        statusItem.button?.toolTip = "\(model.name) · \(battery.isEmpty ? model.status : battery)"
        header?.title = title()
        header?.attributedTitle = NSAttributedString(string: title(), attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        stateItem?.title = model.status
        for (id, item) in modeItems { item.state = id == model.mode ? .on : .off; item.isEnabled = model.ready && !model.busy }
        for preset in EQPreset.all {
            presetItems[preset.id]?.state = preset.matches(model.bands) ? .on : .off
            presetItems[preset.id]?.isEnabled = model.ready && !model.busy && preset.supports(model.bands)
        }
        eqMenuItem?.title = model.currentPreset.map { "Equalizer · \($0.name)" } ?? "Equalizer · Custom"
        for band in model.bands {
            sliders[band.name]?.slider.integerValue = band.value
            sliders[band.name]?.valueLabel.stringValue = "\(band.value)"
        }
        if let audio = model.audio {
            sliders["Noise cancellation"]?.slider.integerValue = 10 - Int(audio[0])
            sliders["Noise cancellation"]?.valueLabel.stringValue = "\(10 - Int(audio[0]))"
        }
        for control in sliders.values { control.slider.isEnabled = model.ready && !model.busy }
        if open && Set(modeItems.keys) != Set(model.modes.map(\.id)) {
            // GetAll delivers each mode in a separate frame. Batch those updates
            // so a menu opened during discovery ends up with the entire list.
            modeRebuildTimer?.invalidate()
            let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in self?.rebuild() }
            RunLoop.main.add(timer, forMode: .common)
            modeRebuildTimer = timer
        }
        if !open { scheduleRebuild() }
    }

    private var showBatteryBar: Bool { model.isDemo || UserDefaults.standard.bool(forKey: "showBatteryBar") }

    private func title() -> String { model.name + (model.battery.map { "  ·  \($0)%" } ?? "") }
    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildScheduled = false
            if !self.open { self.rebuild() }
        }
    }

    @discardableResult private func item(_ title: String, in target: NSMenu? = nil, enabled: Bool = true, checked: Bool = false, key: String = "", action: (() -> Void)? = nil) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: key)
        if let action {
            let handler = MenuAction(action)
            actions.append(handler)
            row.target = handler
            row.action = #selector(MenuAction.run)
        }
        row.isEnabled = enabled && action != nil
        row.state = checked ? .on : .off
        (target ?? menu).addItem(row)
        return row
    }
    private func submenu(_ name: String) -> NSMenu {
        let child = NSMenu(title: name)
        child.autoenablesItems = false
        let row = item(name)
        row.isEnabled = true
        row.submenu = child
        return child
    }
    private func slider(_ title: String, in target: NSMenu, value: Int, min: Int, max: Int, endpoints: String? = nil, action: @escaping (Int) -> Void) {
        let row = NSMenuItem()
        let control = SliderRow(title: title, value: value, minimum: min, maximum: max, enabled: model.ready && !model.busy, endpoints: endpoints, action: action)
        row.view = control
        sliders[title] = control
        target.addItem(row)
    }

    private func rebuild() {
        menu.removeAllItems()
        actions.removeAll()
        modeItems.removeAll()
        presetItems.removeAll()
        sliders.removeAll()
        header = item(title())
        header?.attributedTitle = NSAttributedString(string: title(), attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        stateItem = item(model.status)
        if model.ready {
            menu.addItem(.separator())
            if model.modes.isEmpty { item("Reading listening modes…") }
            for mode in model.modes {
                modeItems[mode.id] = item(mode.name, enabled: !model.busy, checked: model.mode == mode.id) { [weak self] in self?.model.setMode(mode.id) }
            }
            if let audio = model.audio {
                let noise = submenu("Noise cancellation")
                slider("Noise cancellation", in: noise, value: 10 - Int(audio[0]), min: 0, max: 10,
                       endpoints: "0 · Aware                              10 · Quiet") { [weak self] in self?.model.setAudio(index: 0, value: UInt8(10 - $0)) }
                item("Wind block", in: noise, enabled: !model.busy, checked: audio[3] != 0) { [weak self] in self?.model.setAudio(index: 3, value: audio[3] == 0 ? 1 : 0) }
                if audio[3] != 0 { item("Turn off Wind block to adjust ANC.", in: noise) }
                let immersive = submenu("Immersive audio")
                for (value, name) in ["Off", "Still", "Motion"].enumerated() {
                    item(name, in: immersive, enabled: !model.busy, checked: audio[2] == value) { [weak self] in self?.model.setAudio(index: 2, value: UInt8(value)) }
                }
            }
            if !model.bands.isEmpty {
                let eq = submenu(model.currentPreset.map { "Equalizer · \($0.name)" } ?? "Equalizer · Custom")
                eqMenuItem = menu.items.last
                for band in model.bands {
                    slider(band.name, in: eq, value: band.value, min: band.minimum, max: band.maximum) { [weak self] value in self?.model.setBand(band.id, value: value) }
                }
                eq.addItem(.separator())
                item("Presets · Bass / Mid / Treble", in: eq)
                for preset in EQPreset.all {
                    let row = item("\(preset.name)    \(preset.summary)", in: eq, enabled: !model.busy && preset.supports(model.bands), checked: preset.matches(model.bands)) { [weak self] in self?.model.applyPreset(preset) }
                    row.toolTip = preset.detail
                    presetItems[preset.id] = row
                }
                eq.addItem(.separator())
                item("Undo last preset", in: eq, enabled: !model.busy && model.previousEQ != nil) { [weak self] in self?.model.undoPreset() }
                item("Preset guide & sources…", in: eq) { NSWorkspace.shared.open(URL(string: "https://github.com/Twis06/Bose_For_Mac/blob/main/docs/eq-presets.md")!) }
            }
        }
        menu.addItem(.separator())
        let devices = model.isDemo ? [] : BoseBluetooth.devices()
        if devices.count > 1 {
            let selector = submenu("Headphones")
            for device in devices {
                item(device.name ?? "Bose", in: selector, enabled: !model.busy, checked: device == model.bluetooth.device) { [weak self] in self?.model.connect(device) }
            }
        }
        item(model.ready ? "Refresh" : "Retry connection", enabled: !model.busy) { [weak self] in
            guard let self else { return }
            if self.model.ready { self.model.refresh(discover: true) } else { self.model.connect() }
        }
        item("Bluetooth Settings…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
        let settings = submenu("Settings")
        item("Show battery bar", in: settings, checked: showBatteryBar) { [weak self] in
            guard self?.model.isDemo == false else { return }
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "showBatteryBar"), forKey: "showBatteryBar")
            self?.update()
        }
        item("Launch at login", in: settings, checked: !model.isDemo && SMAppService.mainApp.status == .enabled) { [weak self] in
            guard self?.model.isDemo == false else { return }
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch {
                self?.model.status = "Login setting failed: \(error.localizedDescription)"
                self?.update()
            }
        }
        item("About Bose Bar", in: settings) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .applicationName: "Bose Bar", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0",
                .credits: NSAttributedString(string: "A tiny native controller for Bose QC Ultra.\nProtocol adapted from aaronsb/bosectl (MIT).\nNo cloud. No account. No background server.")
            ])
        }
        menu.addItem(.separator())
        item("Quit Bose Bar", key: "q") { NSApplication.shared.terminate(nil) }
    }
}
