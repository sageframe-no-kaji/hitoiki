# Releasing Hitoiki

How a signed, notarized `.dmg` gets built and published. Hitoiki is pure Swift on
SwiftPM — `Package.swift` stays canonical and `scripts/build_macos.sh` wraps the
build product in a `.app` by hand. No Xcode project. The script and this document
are adapted from pālana's.

## The sequence

1. **Build + sign + notarize** — run the build script locally, test the DMG
2. **Push the tag + GitHub Release** — attach the DMG and publish it as Latest
3. **The site** — the Download button and the release notes point at the release

> The in-app update check reads GitHub's latest-release endpoint, so publish as
> GitHub's normal Latest release, never as a prerelease. The tag must be `v`
> followed by one to three whole numbers separated by dots (`v1.1`, `v1.0.1`).
> A tag in any other form, such as `v1.1-beta`, gives users no notice.

---

## Prerequisites

- macOS with the Xcode command-line tools (Swift, `codesign`, `notarytool`,
  `stapler`, `lipo`, `sips`, `iconutil`, `hdiutil`)
- A **Developer ID Application** certificate in the login keychain
- A **notarytool keychain profile** holding the App Store Connect credentials.
  Create it once:
  ```bash
  xcrun notarytool store-credentials "<profile-name>" \
      --apple-id "<apple-id>" --team-id "<team-id>"
  # (prompts for an app-specific password)
  ```
  **Do not pass `--password` on that command line.** Omit it and notarytool
  prompts for the value, so it never lands in shell history. Passing it inline
  writes an app-specific password in the clear to the shell's history file, where
  it stays until someone notices.
- **`scripts/.env`**, ignored by git, holding the two signing values. Copy
  `scripts/.env.example` and fill it in. The real values are in `scripts/.env`
  on the release Mac; this document uses placeholders only.
- The app icon at `packaging/hitoiki.png` (1024×1024, committed). The script
  builds the `.icns` from it at every build.

### When the icon changes

The source is `packaging/hitoiki-icon.svg`. Remake the PNG, which places the
square on Apple's icon grid (1024 canvas, 824 body, continuous corners):

```bash
swift scripts/make_icon.swift packaging/hitoiki-icon.svg packaging/hitoiki.png
```

Look at the PNG before committing it: not clipped, not soft, the right colours.

---

## Step 1 — Build, sign, notarize

```bash
# scripts/.env supplies CODESIGN_IDENTITY and NOTARIZE_KEYCHAIN_PROFILE:
#   CODESIGN_IDENTITY="Developer ID Application: <name> (<team-id>)"
#   NOTARIZE_KEYCHAIN_PROFILE="<profile-name>"
# A variable exported in the shell wins over the file.

# VERSION defaults to 1.0.0. Override per release, e.g.:
#   VERSION=1.1.0 ./scripts/build_macos.sh --dmg
./scripts/build_macos.sh --dmg
```

The script builds arm64 and x86_64 separately and merges them into one universal
program, assembles `dist/Hitoiki.app`, copies the resource bundle
`Hitoiki_Hitoiki.bundle` into `Contents/Resources`, builds `hitoiki.icns`, writes
the Info.plist (`com.sageframe.hitoiki`, `LSUIElement`, macOS 14.0 minimum), signs
inside-out (executable then bundle, never `--deep`), notarizes and staples the
app, packages `dist/hitoiki-<version>.dmg` from the stapled app with `ditto`, signs
the DMG, then notarizes and staples the DMG.

Other forms:

```bash
./scripts/build_macos.sh                    # universal .app only, no DMG
ARCH_FLAGS="" ./scripts/build_macos.sh      # native-only .app, a quick local build
./scripts/build_macos.sh --clean            # wipe dist/ only
```

Without `scripts/.env` (and nothing exported), the app is signed ad hoc, for local
use only, and the script says so. It will not pass Gatekeeper on another Mac.

**The Intel copy is built and signed but not run by us.** The release Mac and the
test guest are both Apple silicon. The x86_64 slice is checked only by `lipo` and
by notarization.

### Verify after it finishes

The app bundle holds exactly `Contents/Info.plist`, `Contents/MacOS/Hitoiki`,
`Contents/Resources/hitoiki.icns`, `Contents/Resources/Hitoiki_Hitoiki.bundle`
and its contents, `Contents/_CodeSignature/CodeResources`, and, after stapling,
`Contents/CodeResources`:

```bash
find dist/Hitoiki.app | sort
lipo -archs dist/Hitoiki.app/Contents/MacOS/Hitoiki        # arm64 and x86_64
codesign --verify --deep --strict --verbose=2 dist/Hitoiki.app
codesign -dv dist/Hitoiki.app 2>&1 | grep flags            # runtime (hardened)
codesign -d --entitlements - dist/Hitoiki.app              # empty
spctl --assess --type execute -v dist/Hitoiki.app
spctl --assess --type open --context context:primary-signature -v dist/hitoiki-*.dmg
xcrun stapler validate dist/Hitoiki.app
xcrun stapler validate dist/hitoiki-*.dmg
```

The DMG holds the app and the Applications shortcut, nothing else:

```bash
hdiutil attach -nobrowse -readonly dist/hitoiki-*.dmg      # prints the mount point
ls -la "/Volumes/Hitoiki"
hdiutil detach "/Volumes/Hitoiki"
```

Open the DMG, drag Hitoiki to Applications, launch it, and click through before
publishing. A DMG built on the same Mac carries no download mark, so Gatekeeper
does not check it. To test as a downloader would, mark it first:

```bash
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" dist/hitoiki-*.dmg
```

### Signing rules that must not change

- **Never use `codesign --deep`** — it signs nested code in the wrong order and
  invalidates it. The script signs the executable, then the bundle.
- **Use `ditto` for DMG staging, not `cp -r`** — `cp -r` follows symlinks and
  corrupts the bundle, breaking the signature and notarization.
- **Notarize both layers** — notarize and staple the app before placing it in
  the DMG, then notarize and staple the DMG.
- **Sign the DMG before notarizing it** — after `hdiutil create`, before
  `notarytool submit`. Unsigned, `spctl --assess` on the DMG reports "no usable
  signature"; signed after stapling, the staple breaks.
- **Hardened runtime, empty entitlements** — `scripts/entitlements.plist` is
  deliberately empty (pure Swift, no dynamically-loaded code; running the shell
  and `ssh` under a pseudoterminal needs no entitlement). Add an entitlement only
  when a concrete capability needs it, with a comment saying why.
- **The resource bundle lives in `Contents/Resources`** — SwiftPM's generated
  `Bundle.module` looks there first, and there it is sealed by the app's
  signature. Without it the app stops when the menu bar item is turned on.
- **No credential in the repository** — no signing identity, Apple ID, team
  number, profile name or password in any committed file. They live in the
  keychain and in `scripts/.env`.

---

## Step 2 — Tag and publish

```bash
git push origin main
git tag -a v<version> -m "Hitoiki <version>"    # e.g. v1.0.0
git push origin v<version>
gh release create v<version> \
    dist/hitoiki-<version>.dmg \
    --verify-tag \
    --latest \
    --title "Hitoiki <version>" \
    --notes-file packaging/release-notes-<version>.md
```

Do not pass `--prerelease`. GitHub excludes prereleases from the latest-release
endpoint that Hitoiki checks.

## Step 3 — The site

`hitoiki.sageframe.net` carries the download, the Payhip button and what changed.
Point its Download button directly at the versioned GitHub DMG asset, and its
release notes at the exact GitHub release page. The panel's update line and the
settings answer line both link to the site, so nothing is released before the
site exists.
