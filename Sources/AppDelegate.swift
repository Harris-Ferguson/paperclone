import AppKit

/// Owns the whole app: the menu-bar item + menu, the per-display overlay
/// windows, and the current state (enabled / intensity), which it persists in
/// `UserDefaults` and fans out to every overlay. The texture is fixed to
/// `PaperTexture.vellumMist`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var slider: NSSlider!
    private var intensityValueLabel: NSTextField!

    private var overlays: [OverlayWindow] = []

    private let texture = PaperTexture.vellumMist

    private let defaults = UserDefaults.standard
    private var enabled = true
    private var intensity = PaperTexture.vellumMist.defaultOpacity   // 0...1

    private let minIntensity = 0.03
    private let maxIntensity = 0.40

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPrefs()
        buildStatusItem()
        rebuildOverlays()
        applyToAll()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    private func loadPrefs() {
        if defaults.object(forKey: "enabled") != nil { enabled = defaults.bool(forKey: "enabled") }
        if defaults.object(forKey: "intensity") != nil { intensity = defaults.double(forKey: "intensity") }
        intensity = min(max(intensity, minIntensity), maxIntensity)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = buildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = Icons.statusBar(enabled: enabled)
        button.toolTip = "PaperClone — paper texture overlay"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Header — app name + paper glyph, not selectable.
        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(string: "PaperClone", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        header.image = Icons.statusBar(enabled: true)
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = enabled ? .on : .off
        toggleItem.image = Icons.symbol("power")
        menu.addItem(toggleItem)

        let intensityItem = NSMenuItem()
        intensityItem.view = buildIntensityView()
        menu.addItem(intensityItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit PaperClone", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = Icons.symbol("xmark.circle")
        menu.addItem(quit)

        return menu
    }

    private func percentString() -> String {
        "\(Int((intensity * 100).rounded()))%"
    }

    private func buildIntensityView() -> NSView {
        let width: CGFloat = 244
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 56))

        let title = NSTextField(labelWithString: "Intensity")
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.textColor = .labelColor
        title.frame = NSRect(x: 14, y: 33, width: 120, height: 16)
        container.addSubview(title)

        intensityValueLabel = NSTextField(labelWithString: percentString())
        intensityValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        intensityValueLabel.textColor = .secondaryLabelColor
        intensityValueLabel.alignment = .right
        intensityValueLabel.frame = NSRect(x: width - 62, y: 33, width: 48, height: 16)
        container.addSubview(intensityValueLabel)

        slider = NSSlider(value: intensity,
                          minValue: minIntensity,
                          maxValue: maxIntensity,
                          target: self,
                          action: #selector(intensityChanged(_:)))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.frame = NSRect(x: 14, y: 9, width: width - 28, height: 20)
        container.addSubview(slider)

        return container
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        enabled.toggle()
        toggleItem.state = enabled ? .on : .off
        updateStatusIcon()
        defaults.set(enabled, forKey: "enabled")
        overlays.forEach { $0.setVisible(enabled) }
    }

    @objc private func intensityChanged(_ sender: NSSlider) {
        intensity = sender.doubleValue
        intensityValueLabel?.stringValue = percentString()
        defaults.set(intensity, forKey: "intensity")
        applyToAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        applyToAll()
    }

    // MARK: Overlays

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
    }

    private func applyToAll() {
        let pattern = PaperTextureRenderer.tile(for: texture)   // render once, share across displays
        for overlay in overlays {
            overlay.apply(patternImage: pattern, intensity: intensity)
            overlay.setVisible(enabled)
        }
    }
}
