# PaperClone

A tiny macOS menu-bar app that lays a subtle **paper-texture overlay** over your
whole screen — softening contrast and the glossy "light source" feel of the
display. A local clone of [Paperman](https://paperman.cc/).

- Transparent, **click-through** overlay (mouse/keyboard pass straight through)
- "Vellum Mist" paper texture + an intensity slider
- Menu-bar only — no Dock icon
- Multi-monitor, static texture, ~0% CPU
- Native Swift/AppKit, single process, no dependencies

## Requirements

- macOS 13+
- Apple **Command Line Tools** (you already have these if `swiftc --version`
  works). Full Xcode is **not** required.
  Install if needed: `xcode-select --install`

## Build & run

Open **Terminal** (do **not** double-click `build.sh` in Finder — macOS will
block it with "cannot be opened because the developer cannot be verified"),
then:

```bash
cd path/to/PaperClone           # wherever you put the folder
xattr -dr com.apple.quarantine . # only needed if you received this from someone else
bash build.sh                    # compiles + assembles build/PaperClone.app
open build/PaperClone.app        # launches it
```

That's it. A 📄 icon appears in the **menu bar** (top-right of the screen) —
there is no Dock icon and no window. Click the icon for the menu.

> **Why `xattr`?** Files shared/downloaded from someone else are "quarantined"
> by macOS, which is what triggers the "developer cannot be verified" block.
> That one command clears the flag from the whole folder. (If you created the
> files yourself, you can skip it.)

> Tip: in this Claude Code session you can run these directly by typing
> `!./build.sh` and `!open build/PaperClone.app` at the prompt.

## Using it

Click the 📄 menu-bar icon:

- **Enabled** — toggle the overlay on/off (the icon shows a slash when off)
- **Intensity** — drag the slider; the live % updates as you go
- **Quit PaperClone** — exit

Your choices are remembered between launches.

## Launch at login (optional)

System Settings → General → Login Items → **＋** → choose
`~/Documents/PaperClone/build/PaperClone.app`.

## Notes

- **First launch / Gatekeeper:** the app is ad-hoc signed (not notarized).
  Launching from Terminal with `open` works. If you double-click it in Finder
  and macOS says it's from an unidentified developer, right-click the app →
  **Open** → **Open**, just once.
- **Toolchain quirk handled for you:** this machine's Command Line Tools ship a
  duplicate modulemap that otherwise breaks every `swiftc` build
  (`redefinition of module 'SwiftBridging'`). `build.sh` works around it with a
  VFS overlay (`build-support/`) — no system files are touched.

## Project layout

```
Sources/
  main.swift               app bootstrap (menu-bar-only accessory app)
  AppDelegate.swift          menu-bar item, styled menu, overlay lifecycle, prefs
  OverlayWindow.swift        transparent click-through window per display
  PaperTexture.swift         the Vellum Mist texture parameters
  PaperTextureRenderer.swift native fractal-noise texture generator
  Icons.swift                menu-bar icon loading + colour swatches
Resources/
  menubar-icon.png         menu-bar template icon (rasterized from an SVG)
Info.plist                 LSUIElement (no Dock icon), bundle metadata
build.sh                   swiftc → .app bundle → ad-hoc codesign
build-support/             VFS overlay that fixes the CLT modulemap bug
```
