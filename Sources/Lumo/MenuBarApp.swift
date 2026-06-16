import AppKit

/// Coalesces slider updates into sequential DDC writes: while one write is in
/// flight, newer values overwrite `pending` so drags never queue up behind
/// the slow (~10ms+) I2C bus.
final class BrightnessController {
    let display: ExternalDisplay
    private var pending: UInt16?
    private var writing = false
    private let lock = NSLock()

    init(display: ExternalDisplay) {
        self.display = display
    }

    func set(_ value: UInt16) {
        lock.lock()
        pending = value
        if writing {
            lock.unlock()
            return
        }
        writing = true
        lock.unlock()
        DispatchQueue.global(qos: .userInteractive).async { self.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let value = pending else {
                writing = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            _ = display.write(vcp: VCP.brightness, value: value)
        }
    }
}

final class DisplayRowView: NSView {
    let controller: BrightnessController
    private let slider: NSSlider
    private let valueLabel: NSTextField

    init(controller: BrightnessController) {
        self.controller = controller
        slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
        valueLabel = NSTextField(labelWithString: "--")
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 52))

        let nameLabel = NSTextField(labelWithString: controller.display.name)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.frame = NSRect(x: 14, y: 30, width: 190, height: 16)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 204, y: 30, width: 42, height: 16)

        slider.frame = NSRect(x: 12, y: 6, width: 236, height: 22)
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.isContinuous = true

        addSubview(nameLabel)
        addSubview(valueLabel)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = UInt16(sender.integerValue)
        valueLabel.stringValue = "\(value)"
        controller.set(value)
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = self.controller.display.read(vcp: VCP.brightness) else { return }
            DispatchQueue.main.async {
                self.slider.maxValue = Double(max(result.max, 1))
                self.slider.integerValue = Int(result.current)
                self.valueLabel.stringValue = "\(result.current)"
            }
        }
    }
}

/// Darkroom controls for one screen: software brightness + warmth sliders, each
/// with a live value readout. Gamma writes are instant (no I2C), so we apply
/// directly on every continuous tick.
final class GammaRowView: NSView {
    let screenID: CGDirectDisplayID
    private let brightnessSlider: NSSlider
    private let warmthSlider: NSSlider
    private let brightnessValue = GammaRowView.makeValueLabel()
    private let warmthValue = GammaRowView.makeValueLabel()

    init(screenID: CGDirectDisplayID, name: String) {
        self.screenID = screenID
        let setting = GammaManager.shared.setting(for: screenID)
        brightnessSlider = NSSlider(value: Double(setting.brightness * 100), minValue: 20, maxValue: 100, target: nil, action: nil)
        warmthSlider = NSSlider(value: Double(setting.warmth * 100), minValue: 0, maxValue: 100, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 78))

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.frame = NSRect(x: 14, y: 56, width: 252, height: 16)
        addSubview(nameLabel)

        configure(slider: brightnessSlider, caption: "Brightness", value: brightnessValue, y: 30)
        configure(slider: warmthSlider, caption: "Warmth", value: warmthValue, y: 6)
        refreshLabels()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    private func configure(slider: NSSlider, caption: String, value: NSTextField, y: CGFloat) {
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.frame = NSRect(x: 14, y: y + 2, width: 44, height: 14)
        addSubview(captionLabel)

        slider.frame = NSRect(x: 58, y: y, width: 176, height: 20)
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        addSubview(slider)

        value.frame = NSRect(x: 238, y: y + 2, width: 38, height: 14)
        addSubview(value)
    }

    private func refreshLabels() {
        // At neutral (brightness 100 / warmth 0), show "Off" to make clear darkroom is disabled.
        brightnessValue.stringValue = brightnessSlider.integerValue >= 100 ? "Off" : "\(brightnessSlider.integerValue)"
        warmthValue.stringValue = warmthSlider.integerValue <= 0 ? "Off" : "\(warmthSlider.integerValue)"
    }

    @objc private func changed() {
        refreshLabels()
        let setting = GammaManager.Setting(
            brightness: Float(brightnessSlider.doubleValue / 100),
            warmth: Float(warmthSlider.doubleValue / 100)
        )
        GammaManager.shared.apply(setting, to: screenID)
    }
}

enum MenuBarApp {
    static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct DisplaySection {
        let row: DisplayRowView
        let inputParent: NSMenuItem
        let inputItems: [NSMenuItem]
    }

    private var statusItem: NSStatusItem!
    private var sections: [DisplaySection] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Lumo")

        rebuildMenu()

        // Displays come and go (sleep, cable plug/unplug); the IOAVService handles
        // go stale with them, so re-enumerate. The delay lets the DCP services
        // re-register after a configuration change.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                // Display reconfig wipes gamma tables, so re-assert darkroom first.
                GammaManager.shared.reapplyAll()
                self?.rebuildMenu()
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        sections = []

        let displays = ExternalDisplay.enumerate()
        if displays.isEmpty {
            menu.addItem(withTitle: "No external displays", action: nil, keyEquivalent: "")
        } else {
            for (index, display) in displays.enumerated() {
                if index > 0 { menu.addItem(.separator()) }

                let row = DisplayRowView(controller: BrightnessController(display: display))
                let rowItem = NSMenuItem()
                rowItem.view = row
                menu.addItem(rowItem)

                let inputParent = NSMenuItem(title: "Input source", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                var inputItems: [NSMenuItem] = []
                for input in InputSource.known {
                    let item = NSMenuItem(title: input.label, action: #selector(selectInput(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = Int(input.code)
                    item.representedObject = display
                    submenu.addItem(item)
                    inputItems.append(item)
                }
                inputParent.submenu = submenu
                menu.addItem(inputParent)

                sections.append(DisplaySection(row: row, inputParent: inputParent, inputItems: inputItems))
            }
        }

        menu.addItem(.separator())
        let darkroomParent = NSMenuItem(title: "🌙 Darkroom", action: nil, keyEquivalent: "")
        let darkroomMenu = NSMenu()
        for screen in Screen.all() {
            let item = NSMenuItem()
            item.view = GammaRowView(screenID: screen.id, name: screen.name)
            darkroomMenu.addItem(item)
        }
        darkroomParent.submenu = darkroomMenu
        menu.addItem(darkroomParent)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let display = sender.representedObject as? ExternalDisplay else { return }
        let code = UInt16(sender.tag)
        // Switching to another device's input makes this Mac lose the screen — that's expected.
        // When the monitor disappears, didChangeScreenParameters rebuilds the menu.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = display.write(vcp: VCP.inputSource, value: code)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        for section in sections {
            section.row.refresh()
            let display = section.row.controller.display
            DispatchQueue.global(qos: .userInitiated).async {
                guard let result = display.read(vcp: VCP.inputSource) else { return }
                let code = UInt8(result.current & 0xFF)
                DispatchQueue.main.async {
                    // Some monitors (LG etc.) report the current input as a non-standard value like 0x00.
                    // In that case, don't show a bogus current value — keep the plain menu title.
                    if let known = InputSource.known.first(where: { $0.code == code }) {
                        section.inputParent.title = "Input source: \(known.label)"
                    } else {
                        section.inputParent.title = "Input source"
                    }
                    for item in section.inputItems {
                        item.state = item.tag == Int(code) ? .on : .off
                    }
                }
            }
        }
    }
}
