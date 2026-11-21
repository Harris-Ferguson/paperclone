import AppKit

/// Owns the whole app: the menu-bar item + menu, the per-display overlay
/// windows, the Advanced window, and the current `PaperSettings`, which it
/// persists in `UserDefaults` and fans out to every overlay.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var paperItem: NSMenuItem!
    private var tuningWindow: TuningWindow?

    private var overlays: [OverlayWindow] = []
    private var pattern: NSImage?
    private var renderedKey: PaperTexture?

    private var settings = PaperSettings.load()

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        rebuildOverlays()
        refresh()

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

        paperItem = NSMenuItem()
        paperItem.image = Icons.symbol("doc")
        menu.addItem(paperItem)
        rebuildPaperMenu()

        let width: CGFloat = 244

        let strength = SliderRow(title: "Strength", value: settings.strength,
                                 range: PaperSettings.strengthRange, width: width, format: SliderRow.percent)
        strength.onChange = { [weak self] value, _ in
            guard let self else { return }
            self.settings.strength = value
            self.settings.save()
            self.refresh()
        }

        let zoom = SliderRow(title: "Zoom", value: settings.zoom,
                                   range: PaperSettings.zoomRange, logarithmic: true,
                                   width: width, format: SliderRow.times)
        zoom.onChange = { [weak self] value, dragging in
            guard let self else { return }
            self.settings.zoom = value
            if dragging { return }   // the tile re-renders on release
            self.settings.save()
            self.refresh()
        }

        let light = SliderRow(title: "Ambient light", value: settings.ambientLight,
                              range: PaperSettings.ambientLightRange, width: width, format: SliderRow.percent)
        light.onChange = { [weak self] value, _ in
            guard let self else { return }
            self.settings.ambientLight = value
            self.settings.save()
            self.refresh()
        }

        for row in [strength, zoom, light] {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let advanced = NSMenuItem(title: "Advanced…", action: #selector(showAdvanced), keyEquivalent: "")
        advanced.target = self
        advanced.image = Icons.symbol("slider.horizontal.3")
        menu.addItem(advanced)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit PaperClone", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = Icons.symbol("xmark.circle")
        menu.addItem(quit)

        return menu
    }

    private var paperTitle: String {
        settings.paper.name + (settings.isEdited ? " (edited)" : "")
    }

    /// Built-in papers, then the user's saved ones; a tick marks the unedited current paper.
    private func rebuildPaperMenu() {
        paperItem.title = "Paper: " + paperTitle

        let submenu = NSMenu()
        for (index, paper) in settings.allPapers.enumerated() {
            if index == PaperTexture.builtIn.count { submenu.addItem(.separator()) }
            let item = NSMenuItem(title: paper.name, action: #selector(pickPaper(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = paper == settings.paper ? .on : .off
            item.image = swatch(for: paper)
            submenu.addItem(item)
        }
        paperItem.submenu = submenu
    }

    private func swatch(for paper: PaperTexture) -> NSImage {
        NSImage(size: NSSize(width: 22, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            NSColor(srgbRed: CGFloat(paper.tintR) / 255, green: CGFloat(paper.tintG) / 255,
                    blue: CGFloat(paper.tintB) / 255, alpha: 1).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        toggleItem.state = settings.enabled ? .on : .off
        updateStatusIcon()
        settings.save()
        overlays.forEach { $0.setVisible(settings.enabled) }
    }

    @objc private func pickPaper(_ sender: NSMenuItem) {
        settings.paper = settings.allPapers[sender.tag]
        paperChanged()
    }

    /// The working paper was replaced wholesale: persist it and resync every view of it.
    private func paperChanged() {
        settings.save()
        rebuildPaperMenu()
        tuningWindow?.sync(paper: settings.paper, title: paperTitle, canDelete: settings.isSavedPaper)
        refresh()
    }

    @objc private func showAdvanced() {
        if tuningWindow == nil {
            let window = TuningWindow(paper: settings.paper)
            window.onEdit = { [weak self] paper, dragging in
                guard let self else { return }
                self.settings.paper = paper
                self.rebuildPaperMenu()
                window.title = self.paperTitle
                if !dragging { self.settings.save() }
                self.refresh(deferRender: dragging)
            }
            window.onRevert = { [weak self] in
                guard let self, let original = self.settings.original else { return }
                self.settings.paper = original
                self.paperChanged()
            }
            window.onSaveAs = { [weak self] name in
                guard let self else { return }
                self.settings.savePaper(as: name)
                self.paperChanged()
            }
            window.onDelete = { [weak self] in
                guard let self else { return }
                self.settings.deleteSavedPaper()
                self.paperChanged()
            }
            window.center()
            tuningWindow = window
        }
        tuningWindow?.sync(paper: settings.paper, title: paperTitle, canDelete: settings.isSavedPaper)
        NSApp.activate(ignoringOtherApps: true)
        tuningWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        renderedKey = nil   // the widest screen, and so the tile size, may have changed
        refresh()
    }

    // MARK: Overlays

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
    }

    /// One tile spans the widest screen, so the texture never visibly repeats.
    private var tilePixelEdge: Int {
        let widest = NSScreen.screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 2560
        return min(4096, Int(widest))
    }

    /// Push the current settings to every overlay. The tile is re-rendered only
    /// when something it depends on changed, and not mid-drag if `deferRender`.
    private func refresh(deferRender: Bool = false) {
        let paper = settings.effectivePaper
        if paper.renderKey != renderedKey && !deferRender {
            pattern = PaperTextureRenderer.tile(for: paper, zoom: settings.zoom, pixelEdge: tilePixelEdge)   // render once, share across displays
            renderedKey = paper.renderKey
        }
        guard let pattern else { return }
        for overlay in overlays {
            overlay.apply(patternImage: pattern, paper: paper, ambientLight: settings.ambientLight)
            overlay.setVisible(settings.enabled)
        }
    }
}
