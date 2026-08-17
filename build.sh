#!/usr/bin/env bash
# Build PaperClone into a runnable .app bundle using swiftc (no Xcode required).
# Portable: works on any Mac with Command Line Tools, regardless of username.
set -eo pipefail
cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd -P)"

APP="build/PaperClone.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "Cleaning…"
rm -rf build
mkdir -p "$MACOS" "$RES"

# --- Toolchain workaround (only applied if THIS machine needs it) ------------
# Some Command Line Tools installs ship a stale duplicate modulemap
# (usr/include/swift/module.modulemap) next to bridging.modulemap; both declare
# module SwiftBridging, which makes every swiftc build fail with
# "redefinition of module 'SwiftBridging'". If we detect that here, shadow the
# stale file with an empty one via a VFS overlay (fed to BOTH the Swift frontend
# and the clang importer). If the machine is healthy, we skip this entirely.
OVERLAY_FLAGS=()
DEVDIR="$(xcode-select -p 2>/dev/null || true)"
SWIFT_INC="$DEVDIR/usr/include/swift"
if [ -f "$SWIFT_INC/module.modulemap" ] && [ -f "$SWIFT_INC/bridging.modulemap" ]; then
  echo "Detected duplicate SwiftBridging modulemap — applying VFS workaround…"
  OVERLAY="$SCRIPT_DIR/build/vfs-overlay.yaml"   # generated fresh, correct paths
  EMPTY="$SCRIPT_DIR/build-support/empty.modulemap"
  cat > "$OVERLAY" <<EOF
{
  "version": 0,
  "case-sensitive": false,
  "use-external-names": false,
  "roots": [
    {
      "type": "directory",
      "name": "$SWIFT_INC",
      "contents": [
        { "type": "file", "name": "module.modulemap", "external-contents": "$EMPTY" }
      ]
    }
  ]
}
EOF
  OVERLAY_FLAGS=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")
fi

echo "Compiling…"
swiftc -O \
  "${OVERLAY_FLAGS[@]}" \
  Sources/main.swift \
  Sources/AppDelegate.swift \
  Sources/OverlayWindow.swift \
  Sources/PaperTexture.swift \
  Sources/PaperTextureRenderer.swift \
  Sources/Icons.swift \
  -framework AppKit \
  -o "$MACOS/PaperClone"

echo "Assembling bundle…"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/menubar-icon.png "$RES/menubar-icon.png"

echo "Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run it with:  open \"$SCRIPT_DIR/$APP\""
