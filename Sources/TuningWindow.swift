import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The Advanced window: every value of the current paper, for building a new
/// one. The swatch strip is plain colour; the real overlay sits above this
/// window, so the strip shows the paper on dark, mid, coloured and light
/// content without hunting for other windows.
final class TuningWindow: NSPanel {

    /// The edited paper, and whether the slider is still being dragged.
    var onEdit: ((PaperTexture, Bool) -> Void)?
    var onRevert: (() -> Void)?
    var onSaveAs: ((String) -> Void)?
    var onDelete: (() -> Void)?

    private var paper: PaperTexture
    private var rows: [(row: SliderRow, keyPath: WritableKeyPath<PaperTexture, Double>)] = []
    private var deleteButton: NSButton!
    private let colourWell = NSColorWell()

    init(paper: PaperTexture) {
        self.paper = paper

        let sliders: [(String, WritableKeyPath<PaperTexture, Double>, ClosedRange<Double>, Bool, (Double) -> String)] = [
            ("Wash", \.wash, 0.0...0.4, false, SliderRow.percent),
            ("Grain strength", \.grain, 0.0...1.0, false, SliderRow.percent),
            ("Grain size", \.grainSize, PaperSettings.minGrainSize...12.0, true, SliderRow.pixels),
            ("Relief", \.relief, 0.0...1.0, false, SliderRow.percent),
            ("Highlights", \.highlights, 0.0...1.0, false, SliderRow.percent),
            ("Formation", \.formation, 0.0...1.0, false, SliderRow.percent),
            ("Fibres", \.fibre, 0.0...1.0, false, SliderRow.percent),
        ]

        let width: CGFloat = 440
        let stripTop: CGFloat = 14
        let stripHeight: CGFloat = 56
        let colourTop = stripTop + stripHeight + 30
        let rowsTop = colourTop + 36
        let buttonsTop = rowsTop + CGFloat(sliders.count) * SliderRow.height + 8
        let height = buttonsTop + 28 + 16

        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.titled, .closable],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentView = content

        let swatches: [NSColor] = [
            NSColor(white: 0.11, alpha: 1),
            NSColor(white: 0.53, alpha: 1),
            NSColor(srgbRed: 0.15, green: 0.31, blue: 0.04, alpha: 1),
            NSColor(white: 0.95, alpha: 1),
        ]
        let swatchWidth = (width - 28) / CGFloat(swatches.count)
        for (index, colour) in swatches.enumerated() {
            let swatch = NSView(frame: NSRect(x: 14 + CGFloat(index) * swatchWidth, y: stripTop,
                                              width: swatchWidth, height: stripHeight))
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = colour.cgColor
            content.addSubview(swatch)
        }

        let caption = NSTextField(labelWithString: "Your paper on dark, mid, colour and light")
        caption.font = NSFont.systemFont(ofSize: 11)
        caption.textColor = .tertiaryLabelColor
        caption.frame = NSRect(x: 14, y: stripTop + stripHeight + 4, width: width - 28, height: 14)
        content.addSubview(caption)

        let colourLabel = NSTextField(labelWithString: "Paper colour")
        colourLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        colourLabel.frame = NSRect(x: 14, y: colourTop + 6, width: 140, height: 16)
        content.addSubview(colourLabel)

        colourWell.frame = NSRect(x: width - 14 - 60, y: colourTop, width: 60, height: 28)
        colourWell.target = self
        colourWell.action = #selector(colourChanged)
        content.addSubview(colourWell)

        for (index, slider) in sliders.enumerated() {
            let (title, keyPath, range, logarithmic, format) = slider
            let row = SliderRow(title: title, value: paper[keyPath: keyPath], range: range,
                                logarithmic: logarithmic, width: width, format: format)
            row.setFrameOrigin(NSPoint(x: 0, y: rowsTop + CGFloat(index) * SliderRow.height))
            row.onChange = { [weak self] value, dragging in
                guard let self else { return }
                self.paper[keyPath: keyPath] = value
                self.onEdit?(self.paper, dragging)
            }
            content.addSubview(row)
            rows.append((row, keyPath))
        }

        let save = NSButton(title: "Save as Paper…", target: self, action: #selector(saveAs))
        save.frame = NSRect(x: width - 14 - 140, y: buttonsTop, width: 140, height: 28)
        content.addSubview(save)

        let revert = NSButton(title: "Revert", target: self, action: #selector(revert))
        revert.frame = NSRect(x: width - 14 - 140 - 8 - 90, y: buttonsTop, width: 90, height: 28)
        content.addSubview(revert)

        deleteButton = NSButton(title: "Delete Paper…", target: self, action: #selector(deletePaper))
        deleteButton.frame = NSRect(x: 14, y: buttonsTop, width: 130, height: 28)
        content.addSubview(deleteButton)
    }

    /// Show `paper` in the sliders, e.g. after another paper was picked. Only
    /// papers the user saved can be deleted.
    func sync(paper: PaperTexture, title: String, canDelete: Bool) {
        self.paper = paper
        self.title = title
        deleteButton.isEnabled = canDelete
        colourWell.color = NSColor(srgbRed: CGFloat(paper.tintR) / 255, green: CGFloat(paper.tintG) / 255,
                                   blue: CGFloat(paper.tintB) / 255, alpha: 1)
        for (row, keyPath) in rows {
            row.value = paper[keyPath: keyPath]
        }
    }

    @objc private func colourChanged() {
        guard let colour = colourWell.color.usingColorSpace(.sRGB) else { return }
        paper.tintR = Int((colour.redComponent * 255).rounded())
        paper.tintG = Int((colour.greenComponent * 255).rounded())
        paper.tintB = Int((colour.blueComponent * 255).rounded())
        onEdit?(paper, false)
    }

    @objc private func revert() {
        onRevert?()
    }

    @objc private func deletePaper() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(paper.name)”?"
        alert.informativeText = "This saved paper is removed from the Paper menu. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { onDelete?() }
    }

    @objc private func saveAs() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = paper.name

        let alert = NSAlert()
        alert.messageText = "Save as paper"
        alert.informativeText = "Name this paper. It appears in the Paper menu."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { onSaveAs?(name) }
    }
}
