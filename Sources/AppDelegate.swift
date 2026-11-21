import AppKit

/// One menu slider: which setting it edits, its range, and how to show it.
private struct SliderSpec {
    let title: String
    let keyPath: WritableKeyPath<PaperSettings, Double>
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let rerendersTile: Bool
    var logarithmic = false   // equal slider travel multiplies the value instead of adding

    /// Slider position in 0...1 for a setting value, and back.
    func position(for value: Double) -> Double {
        logarithmic
            ? log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
            : (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    func value(at position: Double) -> Double {
        logarithmic
            ? range.lowerBound * pow(range.upperBound / range.lowerBound, position)
            : range.lowerBound + position * (range.upperBound - range.lowerBound)
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func times(_ value: Double) -> String { String(format: "%.1f×", value) }
    static func pixels(_ value: Double) -> String { String(format: "%.1f px", value) }
}

/// Owns the whole app: the menu-bar item + menu, the per-display overlay
/// windows, and the current `PaperSettings`, which it persists in
/// `UserDefaults` and fans out to every overlay. The texture is fixed to
/// `PaperTexture.vellumMist`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var menuBarItem: NSMenuItem!
    private var sliderRows: [(slider: NSSlider, valueLabel: NSTextField)] = []

    private var overlays: [OverlayWindow] = []
    private var pattern: NSImage?

    // Tiles larger than this re-render on slider release instead of every drag tick.
    private let liveRenderMaxPixelEdge = 1920

    private let texture = PaperTexture.vellumMist

    private var settings = PaperSettings.load(texture: .vellumMist)

    private let sliderSpecs = [
        SliderSpec(title: "Wash", keyPath: \.wash, range: PaperSettings.washRange, format: SliderSpec.percent, rerendersTile: false),
        SliderSpec(title: "Grain strength", keyPath: \.grain, range: PaperSettings.grainRange, format: SliderSpec.percent, rerendersTile: false),
        SliderSpec(title: "Texture size", keyPath: \.textureSize, range: PaperSettings.textureSizeRange, format: SliderSpec.times, rerendersTile: true, logarithmic: true),
        SliderSpec(title: "Grain size", keyPath: \.grainSize, range: PaperSettings.grainSizeRange, format: SliderSpec.pixels, rerendersTile: true, logarithmic: true),
        SliderSpec(title: "Formation", keyPath: \.formation, range: PaperSettings.formationRange, format: SliderSpec.percent, rerendersTile: true),
        SliderSpec(title: "Fibres", keyPath: \.fibre, range: PaperSettings.fibreRange, format: SliderSpec.percent, rerendersTile: true),
        SliderSpec(title: "Relief", keyPath: \.relief, range: PaperSettings.reliefRange, format: SliderSpec.percent, rerendersTile: true),
        SliderSpec(title: "Highlights", keyPath: \.highlights, range: PaperSettings.highlightsRange, format: SliderSpec.percent, rerendersTile: true),
    ]

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        rebuildOverlays()
        renderPattern()
        applyToAll()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = buildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = Icons.statusBar(enabled: settings.enabled)
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
        toggleItem.state = settings.enabled ? .on : .off
        toggleItem.image = Icons.symbol("power")
        menu.addItem(toggleItem)

        menuBarItem = NSMenuItem(title: "Exclude Menu Bar", action: #selector(toggleExcludeMenuBar), keyEquivalent: "")
        menuBarItem.target = self
        menuBarItem.state = settings.excludeMenuBar ? .on : .off
        menuBarItem.image = Icons.symbol("menubar.rectangle")
        menu.addItem(menuBarItem)

        for (index, spec) in sliderSpecs.enumerated() {
            let row = buildSliderRow(spec, tag: index)
            sliderRows.append((row.slider, row.valueLabel))
            let item = NSMenuItem()
            item.view = row.view
            menu.addItem(item)
        }

        let reset = NSMenuItem(title: "Reset Texture", action: #selector(resetTexture), keyEquivalent: "")
        reset.target = self
        reset.image = Icons.symbol("arrow.counterclockwise")
        menu.addItem(reset)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit PaperClone", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = Icons.symbol("xmark.circle")
        menu.addItem(quit)

        return menu
    }

    private func buildSliderRow(_ spec: SliderSpec, tag: Int) -> (view: NSView, slider: NSSlider, valueLabel: NSTextField) {
        let value = settings[keyPath: spec.keyPath]
        let width: CGFloat = 244
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 56))

        let titleLabel = NSTextField(labelWithString: spec.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 14, y: 33, width: 120, height: 16)
        container.addSubview(titleLabel)

        let valueLabel = NSTextField(labelWithString: spec.format(value))
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - 74, y: 33, width: 60, height: 16)
        container.addSubview(valueLabel)

        let rowSlider = NSSlider(value: spec.position(for: value),
                                 minValue: 0,
                                 maxValue: 1,
                                 target: self,
                                 action: #selector(sliderChanged(_:)))
        rowSlider.tag = tag
        rowSlider.isContinuous = true
        rowSlider.controlSize = .small
        rowSlider.frame = NSRect(x: 14, y: 9, width: width - 28, height: 20)
        container.addSubview(rowSlider)

        return (container, rowSlider, valueLabel)
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        toggleItem.state = settings.enabled ? .on : .off
        updateStatusIcon()
        settings.save()
        overlays.forEach { $0.setVisible(settings.enabled) }
    }

    @objc private func toggleExcludeMenuBar() {
        settings.excludeMenuBar.toggle()
        menuBarItem.state = settings.excludeMenuBar ? .on : .off
        settings.save()
        applyToAll()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let spec = sliderSpecs[sender.tag]
        let value = spec.value(at: sender.doubleValue)
        settings[keyPath: spec.keyPath] = value
        sliderRows[sender.tag].valueLabel.stringValue = spec.format(value)
        if spec.rerendersTile {
            textureShapeChanged()
        } else {
            settings.save()
            applyToAll()
        }
    }

    private func textureShapeChanged() {
        let dragging = NSApp.currentEvent?.type == .leftMouseDragged
        if dragging && PaperTextureRenderer.pixelEdge(for: settings) > liveRenderMaxPixelEdge { return }
        settings.save()
        renderPattern()
        applyToAll()
    }

    @objc private func resetTexture() {
        settings.resetTexture(to: texture)
        for (spec, row) in zip(sliderSpecs, sliderRows) {
            let value = settings[keyPath: spec.keyPath]
            row.slider.doubleValue = spec.position(for: value)
            row.valueLabel.stringValue = spec.format(value)
        }
        settings.save()
        renderPattern()
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

    private func renderPattern() {
        pattern = PaperTextureRenderer.tile(for: texture, settings: settings)   // render once, share across displays
    }

    private func applyToAll() {
        guard let pattern else { return }
        for overlay in overlays {
            overlay.apply(patternImage: pattern, texture: texture, settings: settings)
            overlay.setVisible(settings.enabled)
        }
    }
}
