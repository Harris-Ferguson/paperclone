import AppKit

// Menu-bar-only app: no dock icon, no standard app menu (see LSUIElement in
// Info.plist). `.accessory` keeps it out of the Dock and app switcher.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()   // retained for the process lifetime
app.delegate = delegate

app.run()
