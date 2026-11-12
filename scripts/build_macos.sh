#!/usr/bin/env bash
# build_macos.sh — build Hitoiki.app and (optionally) a signed, notarized .dmg
#
# Usage:
#   ./scripts/build_macos.sh            # build the universal .app
#   ./scripts/build_macos.sh --dmg      # build .app + .dmg (+ notarize if creds set)
#   ./scripts/build_macos.sh --clean    # wipe dist/ only
#
# Adapted from pālana's script. Hitoiki is pure Swift on SwiftPM. Package.swift
# stays canonical — this script wraps the `swift build` product in a proper .app
# bundle by hand, signs it, and packages a .dmg. No Xcode project required.
#
# For a signed + notarized release build, the script needs two values:
#   CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (YOURTEAMID)"
#   NOTARIZE_KEYCHAIN_PROFILE="<notarytool profile name stored in keychain>"
# It reads them from scripts/.env when that file exists (ignored by git; see
# scripts/.env.example). A variable already set in the environment wins over the
# file. Without them the app is signed for local use only.
#
# Icon: packaging/hitoiki.png (1024x1024, made from packaging/hitoiki-icon.svg by
# scripts/make_icon.swift). This script builds hitoiki.icns from it every time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Hitoiki"                      # .app filename, Finder name, disk image title
BUNDLE_ID="com.sageframe.hitoiki"
VERSION="${VERSION:-1.0.0}"             # CFBundleShortVersionString and CFBundleVersion
MIN_MACOS="14.0"
RESOURCE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"   # SwiftPM's resource bundle for the Hitoiki target
ICON_PNG="packaging/hitoiki.png"
ICON_KEY="hitoiki"
DMG_NAME="hitoiki-${VERSION}.dmg"

# ── Credentials ───────────────────────────────────────────────────────────────
# Read only the two known keys from scripts/.env; the file is parsed, not run.
# A key already set in the environment is left as it is.
load_env_file() {
    local file="$1" key value
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            CODESIGN_IDENTITY|NOTARIZE_KEYCHAIN_PROFILE) ;;
            *) continue ;;
        esac
        if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
            value="${value:1:${#value}-2}"
        fi
        if [[ -z "${!key+x}" ]]; then
            export "$key=$value"
        fi
    done < "$file"
}
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo "==> Reading signing values from scripts/.env"
    load_env_file "$SCRIPT_DIR/.env"
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
BUILD_DMG=false
CLEAN_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --dmg)   BUILD_DMG=true ;;
        --clean) CLEAN_ONLY=true ;;
    esac
done

if $BUILD_DMG && [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" && -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "ERROR: NOTARIZE_KEYCHAIN_PROFILE is set but CODESIGN_IDENTITY is not."
    echo "       Notarization needs a Developer ID signature; nothing was uploaded."
    exit 1
fi

# ── Clean ─────────────────────────────────────────────────────────────────────
echo "==> Cleaning dist/"
rm -rf dist
if $CLEAN_ONLY; then
    echo "==> Clean done."
    exit 0
fi

if [[ ! -f "$ICON_PNG" ]]; then
    echo "ERROR: $ICON_PNG not found. Make it with:"
    echo "       swift scripts/make_icon.swift packaging/hitoiki-icon.svg $ICON_PNG"
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────
# Build each architecture through the ordinary SwiftPM path, then merge the
# executables, as pālana does. Each architecture's program is copied out as soon
# as it is built: SwiftPM's build system on this toolchain can put every
# architecture's release product in the same folder (.build/out/Products/Release),
# so the second build may replace the first. Set ARCH_FLAGS="" for a fast native
# single-arch build; any other explicit value is passed to SwiftPM.
#
# The resource bundle holds no code (only the menu bar glyph's SVG), so it is the
# same for both architectures. It is taken from the arm64 build and checked
# against the x86_64 build's copy.
MERGE_DIR="$(mktemp -d)"
if [[ -z "${ARCH_FLAGS+x}" ]]; then
    echo "==> Building ${APP_NAME}  (version ${VERSION}, universal arm64 + x86_64)"
    swift build -c release --arch arm64
    ARM_BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
    cp "$ARM_BIN_DIR/$APP_NAME" "$MERGE_DIR/${APP_NAME}-arm64"
    if [[ ! -d "$ARM_BIN_DIR/$RESOURCE_BUNDLE" ]]; then
        echo "ERROR: resource bundle not found at $ARM_BIN_DIR/$RESOURCE_BUNDLE"
        exit 1
    fi
    ditto "$ARM_BIN_DIR/$RESOURCE_BUNDLE" "$MERGE_DIR/$RESOURCE_BUNDLE"

    swift build -c release --arch x86_64
    INTEL_BIN_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"
    cp "$INTEL_BIN_DIR/$APP_NAME" "$MERGE_DIR/${APP_NAME}-x86_64"
    if ! diff -rq "$MERGE_DIR/$RESOURCE_BUNDLE" "$INTEL_BIN_DIR/$RESOURCE_BUNDLE"; then
        echo "ERROR: the arm64 and x86_64 builds produced different resource bundles"
        exit 1
    fi

    BIN="$MERGE_DIR/$APP_NAME"
    lipo -create "$MERGE_DIR/${APP_NAME}-arm64" "$MERGE_DIR/${APP_NAME}-x86_64" -output "$BIN"
    BUNDLE_SRC="$MERGE_DIR/$RESOURCE_BUNDLE"
else
    echo "==> Building ${APP_NAME}  (version ${VERSION}, archs: ${ARCH_FLAGS:-native})"
    # shellcheck disable=SC2086  # ARCH_FLAGS is a list of SwiftPM flags, split on purpose
    swift build -c release $ARCH_FLAGS
    # shellcheck disable=SC2086  # as above
    BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"
    BIN="$BIN_DIR/$APP_NAME"
    BUNDLE_SRC="$BIN_DIR/$RESOURCE_BUNDLE"
fi

if [[ ! -x "$BIN" ]]; then
    echo "ERROR: built executable not found at $BIN"
    exit 1
fi
if [[ ! -d "$BUNDLE_SRC" ]]; then
    echo "ERROR: resource bundle not found at $BUNDLE_SRC"
    exit 1
fi
echo "    Built: $BIN"
ARCHS="$(lipo -archs "$BIN")"
echo "    Architectures: $ARCHS"
if [[ -z "${ARCH_FLAGS+x}" ]]; then
    if [[ " $ARCHS " != *" arm64 "* || " $ARCHS " != *" x86_64 "* ]]; then
        echo "ERROR: executable is not universal (arm64 + x86_64)"
        exit 1
    fi
    echo "    Verified universal2"
fi

# ── Assemble the .app bundle ──────────────────────────────────────────────────
APP_PATH="dist/${APP_NAME}.app"
echo "==> Assembling ${APP_PATH}"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"

# The resource bundle goes in Contents/Resources: SwiftPM's generated
# Bundle.module looks in Bundle.main.resourceURL first, which in an app is
# Contents/Resources. Inside the bundle it is sealed by the app's signature.
# ditto, not cp -r — preserves the bundle's structure.
ditto "$BUNDLE_SRC" "$APP_PATH/Contents/Resources/$RESOURCE_BUNDLE"
echo "    Copied $RESOURCE_BUNDLE"
rm -rf "$MERGE_DIR"

# Icon: built from the 1024x1024 PNG at every build.
echo "    Building ${ICON_KEY}.icns from $ICON_PNG"
ICONSET="$(mktemp -d)/${ICON_KEY}.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 64 128 256 512; do
    sips -z "$sz" "$sz"       "$ICON_PNG" --out "$ICONSET/icon_${sz}x${sz}.png"   >/dev/null
    sips -z "$((sz*2))" "$((sz*2))" "$ICON_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/${ICON_KEY}.icns"
rm -rf "$(dirname "$ICONSET")"

# Info.plist (version single-sourced from $VERSION above). LSUIElement keeps
# the app out of the Dock from the first moment, before the code's .accessory call.
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>       <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>        <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${VERSION}</string>
    <key>CFBundleIconFile</key>          <string>${ICON_KEY}</string>
    <key>LSMinimumSystemVersion</key>    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>  <string>Andrew Todd Marcus — MIT</string>
</dict>
</plist>
PLIST
echo "    Wrote Info.plist"

# ── Codesign ──────────────────────────────────────────────────────────────────
# Native Swift: one executable, no framework tree. Sign the executable, then the
# bundle. Never --deep (signs inner code in the wrong order, invalidating it).
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "==> Signing with identity: $CODESIGN_IDENTITY"
    ENTITLEMENTS="$SCRIPT_DIR/entitlements.plist"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_PATH/Contents/MacOS/$APP_NAME"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_PATH"
    # A plain command, not `verify && echo`: under set -e a failure on the left
    # of && does not stop the script, and nothing may be notarized after a failure.
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    echo "==> Signature verified OK"
else
    echo "==> Ad-hoc signing (local use only — will not pass Gatekeeper on other Macs)"
    codesign --force --sign - "$APP_PATH"
fi

# ── DMG (+ notarization) ──────────────────────────────────────────────────────
# Correct order: notarize + staple the APP first, then build the dmg from the
# stapled app, then notarize + staple the dmg. This way the app the user drags
# to /Applications carries its own ticket and validates offline — not just the
# dmg. Two notarytool round-trips; each keyed to its own cdhash.
if $BUILD_DMG; then
    if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
        echo "==> Notarizing the app bundle (profile: $NOTARIZE_KEYCHAIN_PROFILE)…"
        APP_ZIP_DIR="$(mktemp -d)"
        ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_DIR/${APP_NAME}.zip"
        xcrun notarytool submit "$APP_ZIP_DIR/${APP_NAME}.zip" \
            --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" --wait
        xcrun stapler staple "$APP_PATH"
        rm -rf "$APP_ZIP_DIR"
        echo "    App notarized and stapled."
    fi

    echo "==> Creating $DMG_NAME"
    STAGING="$(mktemp -d)"
    # ditto, not cp -r — preserves bundle structure and code signatures.
    ditto "$APP_PATH" "$STAGING/$(basename "$APP_PATH")"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "dist/$DMG_NAME"
    rm -rf "$STAGING"
    echo "==> DMG: dist/$DMG_NAME"

    # Sign the dmg itself, after it is made and before it is notarized, so the
    # notarization covers the signature (signing after stapling would break the
    # staple). Unsigned, Gatekeeper's check on the dmg reports "no usable signature".
    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "dist/$DMG_NAME"
        codesign --verify --strict --verbose=2 "dist/$DMG_NAME"
        echo "    DMG signed."
    fi

    if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
        echo "==> Notarizing the dmg…"
        xcrun notarytool submit "dist/$DMG_NAME" \
            --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" --wait
        xcrun stapler staple "dist/$DMG_NAME"
        echo "==> Notarization complete and stapled (app + dmg)."
        xcrun stapler validate "dist/$DMG_NAME"
    else
        echo "==> NOTE: NOTARIZE_KEYCHAIN_PROFILE unset — .dmg is NOT notarized."
        echo "          It will hit Gatekeeper on other Macs until notarized."
    fi
fi

echo ""
echo "==> Done. Output:"
ls -lh dist/
