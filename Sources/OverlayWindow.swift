import AppKit

/// Fills its bounds with a seamlessly-tiling paper-texture pattern.
private final class TextureView: NSView {
    var patternImage: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = patternImage else { return }
        NSColor(patternImage: image).setFill()
        dirtyRect.fill()
    }

    // Belt-and-suspenders click-through (the window already ignores mouse events).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A transparent, click-through, always-on-top window covering one display.
/// Layered views tone white content to the paper colour, wash it, paint the
/// grain with a `TextureView`, and shade it with uneven light; because the window
/// `ignoresMouseEvents`, all clicks and keystrokes pass straight through to
/// whatever is behind it and it never takes focus.
final class OverlayWindow: NSWindow {

    private let toneView = NSView()
    private let washView = NSView()
    private let lightView = NSView()
    private let lightLayer = CAGradientLayer()
    private let textureView = TextureView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        // Transparent, chrome-free, never casts a shadow.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false

        // Click-through: events fall through to the apps beneath us.
        ignoresMouseEvents = true

        // Above every app window on every Space, but just under the menu bar, so the
        // bar, its menus and system overlays draw over the paper.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        setFrame(screen.frame, display: true)

        // Bottom to top: tone (whites → paper colour), wash, grain, ambient light.
        toneView.wantsLayer = true
        contentView = toneView

        // Light falls from the upper left; the far corner is the dimmest.
        lightLayer.type = .radial
        lightLayer.startPoint = CGPoint(x: 0.3, y: 0.75)
        lightLayer.endPoint = CGPoint(x: 1.3, y: -0.35)
        lightLayer.locations = [0, 0.25, 1]
        lightView.layer = lightLayer
        lightView.wantsLayer = true

        washView.wantsLayer = true
        for view in [washView, textureView, lightView] {
            view.frame = toneView.bounds
            view.autoresizingMask = [.width, .height]
            toneView.addSubview(view)
        }
    }

    // Borderless windows already refuse key/main status; make it explicit.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Paint `patternImage` over the paper's tone and wash, under `ambientLight`.
    /// All of these are instant: the tile is pre-rendered, the rest are layer colours.
    func apply(patternImage: NSImage, paper: PaperTexture, ambientLight: Double) {
        let tint = [paper.tintR, paper.tintG, paper.tintB].map { CGFloat($0) / 255 }

        // A plain overlay cannot multiply by a colour, so pick the colour and alpha
        // that turn white into exactly the tint while barely lifting black.
        let toneAlpha = 1 - tint.min()!
        let tone = toneAlpha > 0 ? tint.map { ($0 - (1 - toneAlpha)) / toneAlpha } : [0, 0, 0]
        toneView.layer?.backgroundColor = NSColor(srgbRed: tone[0], green: tone[1], blue: tone[2], alpha: toneAlpha).cgColor

        washView.layer?.backgroundColor = NSColor(srgbRed: tint[0], green: tint[1], blue: tint[2],
                                                  alpha: CGFloat(paper.wash)).cgColor
        textureView.patternImage = patternImage
        textureView.alphaValue = CGFloat(paper.grain)

        let shade = NSColor(white: 0, alpha: CGFloat(0.3 * ambientLight)).cgColor
        lightLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, shade]
    }

    func setVisible(_ visible: Bool) {
        if visible { orderFrontRegardless() } else { orderOut(nil) }
    }
}
