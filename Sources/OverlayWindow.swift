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
/// A flat wash view carries the paper tint and hosts a `TextureView` that
/// paints the grain over it; because the window
/// `ignoresMouseEvents`, all clicks and keystrokes pass straight through to
/// whatever is behind it and it never takes focus.
final class OverlayWindow: NSWindow {

    private let washView = NSView()
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

        // Float above everything, on every Space, including over full-screen apps.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        setFrame(screen.frame, display: true)

        washView.wantsLayer = true
        contentView = washView

        textureView.frame = washView.bounds
        textureView.autoresizingMask = [.width, .height]
        washView.addSubview(textureView)
    }

    // Borderless windows already refuse key/main status; make it explicit.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Paint `patternImage` over a wash of the texture's tint. Wash and grain are
    /// both instant: the tile is pre-rendered, and each is just a layer alpha.
    func apply(patternImage: NSImage, texture: PaperTexture, settings: PaperSettings) {
        washView.layer?.backgroundColor = NSColor(srgbRed: CGFloat(texture.tintR) / 255,
                                                  green: CGFloat(texture.tintG) / 255,
                                                  blue: CGFloat(texture.tintB) / 255,
                                                  alpha: CGFloat(settings.wash)).cgColor
        textureView.patternImage = patternImage
        textureView.alphaValue = CGFloat(settings.grain)
        // Just under the menu bar, its menus and system overlays draw above the paper.
        level = settings.excludeMenuBar ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1) : .screenSaver
    }

    func setVisible(_ visible: Bool) {
        if visible { orderFrontRegardless() } else { orderOut(nil) }
    }
}
