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
/// It hosts a `TextureView` that paints the paper grain; because the window
/// `ignoresMouseEvents`, all clicks and keystrokes pass straight through to
/// whatever is behind it and it never takes focus.
final class OverlayWindow: NSWindow {

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

        textureView.frame = NSRect(origin: .zero, size: screen.frame.size)
        textureView.autoresizingMask = [.width, .height]
        contentView = textureView
    }

    // Borderless windows already refuse key/main status; make it explicit.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Paint `patternImage` at `intensity` opacity. Both are instant: the tile is
    /// pre-rendered, and intensity is just the window's compositing alpha.
    func apply(patternImage: NSImage, intensity: Double) {
        textureView.patternImage = patternImage
        alphaValue = CGFloat(intensity)
    }

    func setVisible(_ visible: Bool) {
        if visible { orderFrontRegardless() } else { orderOut(nil) }
    }
}
