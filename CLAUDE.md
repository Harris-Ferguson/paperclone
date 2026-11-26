# PaperClone

A macOS menu-bar app (Swift/AppKit, no dependencies) that puts a click-through paper-texture overlay over every display. See README.md for what it does and how the code is laid out.

## Build

- `bash build.sh` compiles with `swiftc` (Command Line Tools only, no Xcode) into `build/PaperClone.app` and signs it ad hoc.
- **New source files must be added to the `swiftc` list in `build.sh` by hand.** Nothing picks them up automatically.
- `build.sh` works around a Command Line Tools bug (duplicate `SwiftBridging` modulemap) with a VFS overlay, and only when it detects the bug. Keep that block. Homebrew runs this same script.
- There is no test target. To check logic, compile a small `main.swift` with only the source files it needs (e.g. `Sources/PaperSettings.swift Sources/PaperTexture.swift`). If the build printed the VFS workaround message, pass the same flags: `-vfsoverlay build/vfs-overlay.yaml -Xcc -ivfsoverlay -Xcc build/vfs-overlay.yaml`.

## Settings

- Settings are stored in `UserDefaults` under the bundle ID `io.github.harris-ferguson.paperclone`. **Don't change the bundle ID**, or everyone's saved papers disappear.
- The app was called `local.paperclone` before v0.1.0. `PaperSettings.migrateLegacyDefaults` copies the old settings over once, on first launch. If you add a stored key, add it to `PaperSettings.storedKeys` too.

## Releases and Homebrew

Users install with `brew install harris-ferguson/tap/paperclone`. The formula is in a separate repo, [Harris-Ferguson/homebrew-tap](https://github.com/Harris-Ferguson/homebrew-tap) (`Formula/paperclone.rb`). It builds from the source tarball on the user's Mac, so macOS doesn't quarantine the app and there's no Gatekeeper warning. It installs `PaperClone.app` into the Homebrew prefix plus a `paperclone` launcher.

To ship a new version:

1. Set `CFBundleShortVersionString` in `Info.plist` to the new version and increase `CFBundleVersion`. Merge to `main`.
2. Tag the release and publish it:
   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   gh release create vX.Y.Z --title vX.Y.Z --notes "..."
   ```
3. Get the tarball's checksum:
   ```bash
   curl -fsSL https://github.com/Harris-Ferguson/paperclone/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```
4. In the tap repo, update `url` and `sha256` in `Formula/paperclone.rb`, then push.
5. Verify:
   ```bash
   brew update && brew upgrade paperclone
   brew test paperclone
   brew audit --strict --online harris-ferguson/tap/paperclone
   ```

The formula's `test` block checks that the binary exists and that the bundle ID is the one above. If the bundle layout changes, update the test.
