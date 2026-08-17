import AppKit

/// Small drawn assets for the menu-bar item and menu.
enum Icons {

    /// The menu-bar glyph. Loads the pre-rasterized "filter_vintage" flower
    /// (`menubar-icon.png`, a black+alpha template) from the bundle and sizes it
    /// for the menu bar; the system tints it to match the bar (black on light,
    /// white on dark). When disabled, a diagonal slash is drawn over it. Falls
    /// back to a code-drawn paper glyph if the image is missing.
    static func statusBar(enabled: Bool) -> NSImage {
        let edge: CGFloat = 19
        let size = NSSize(width: edge, height: edge)

        guard let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
              let base = NSImage(contentsOf: url) else {
            return drawnFallback(enabled: enabled)
        }
        base.size = size
        base.isTemplate = true

        if enabled { return base }

        let composed = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            let inset = edge * 0.14
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: inset, y: inset))
            slash.line(to: NSPoint(x: edge - inset, y: edge - inset))
            slash.lineWidth = 1.8
            slash.lineCapStyle = .round
            NSColor.black.setStroke()
            slash.stroke()
            return true
        }
        composed.isTemplate = true
        return composed
    }

    /// Code-drawn paper glyph used only if `menubar-icon.png` isn't bundled.
    private static func drawnFallback(enabled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let l: CGFloat = 3.5, r: CGFloat = 14.5, b: CGFloat = 2.5, t: CGFloat = 15.5
            let fold: CGFloat = 4.5

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Sheet body with the top-right corner cut off (the fold).
            let sheet = NSBezierPath()
            sheet.move(to: NSPoint(x: l, y: b))
            sheet.line(to: NSPoint(x: r, y: b))
            sheet.line(to: NSPoint(x: r, y: t - fold))
            sheet.line(to: NSPoint(x: r - fold, y: t))
            sheet.line(to: NSPoint(x: l, y: t))
            sheet.close()
            sheet.lineJoinStyle = .round
            sheet.lineWidth = 1.4
            sheet.stroke()

            // The folded-over corner.
            let crease = NSBezierPath()
            crease.move(to: NSPoint(x: r - fold, y: t))
            crease.line(to: NSPoint(x: r - fold, y: t - fold))
            crease.line(to: NSPoint(x: r, y: t - fold))
            crease.lineJoinStyle = .round
            crease.lineWidth = 1.2
            crease.stroke()

            // Two ruled lines → reads as a page.
            for y in [CGFloat(5.6), 7.8] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: l + 1.8, y: y))
                line.line(to: NSPoint(x: r - 1.8, y: y))
                line.lineWidth = 1.0
                line.lineCapStyle = .round
                line.stroke()
            }

            // Grain specks → the whole point of the app.
            for p in [NSPoint(x: 5.4, y: 10.6), NSPoint(x: 8.2, y: 11.8)] {
                NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: 1.1, height: 1.1)).fill()
            }

            if !enabled {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2.6, y: 2.6))
                slash.line(to: NSPoint(x: 15.4, y: 15.4))
                slash.lineWidth = 1.7
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// An SF Symbol sized for a menu row (template so it tints with the text).
    static func symbol(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = true
        return image
    }
}
