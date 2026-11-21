---
created: 2026-11-19
status: complete
type: ho-document
project: hitoiki
ho: "08"
kamae: 5
shape: ri
phase: 4 — The Ship
title: The First Launch
description: Builds v1.0.1 — a welcome window the first time Hitoiki opens and the menu bar item on by default — as one pull request with a scoped review, releases it notarised to GitHub and Payhip, and closes Phase 4 as v1.0.
model: claude-opus-5-5
opening-hash: 3b0c944
builds-on:
  - kamae-2-hitoiki-system-design
  - kamae-4-hitoiki-ho-overview
  - ho-process/hos/ho-07-the-storefront.md
---

# ho-08 — The First Launch

The last ho of Phase 4. A buyer installs Hitoiki, opens it, and sees nothing. This ho makes the first launch say what happened, turns the menu bar item on by default, releases the result as v1.0.1, and closes the phase as v1.0.

**Out of scope:** any other change to the app's behaviour; issues #1 (`-tt` retry) and #2 (panel placement); the site's design; `scripts/build_macos.sh`; any dependency in `Package.swift`.

---

## Problem

Hitoiki has no Dock icon by design, the menu bar item is off by default, and `applicationDidFinishLaunching` (`Sources/Hitoiki/App.swift`) shows nothing. After a double-click the app is running and waiting for Control-Command-Space, and nothing on screen says so. A first-time buyer has no way to tell that the app started.

---

## Solution

**Decision 1 — The welcome window.** A window built like About (`Sources/Hitoiki/AboutWindow.swift`): 360 points wide, the Theme's colours, a transparent title bar, movable by its background, centred, brought to the front with the same forcing activation call About uses. Title "Welcome to Hitoiki". Top to bottom:

- The app icon, 92 points.
- **Hitoiki is running** (the About window's name style).
- **Press ⌃⌘Space to open it from any app.** — the registered combination's symbols (`Shortcut.displayName`) in the accent colour. Under it, faint, **(Control-Command-Space)**, only while the shortcut is the default (`Settings.defaultShortcut`); a recorded shortcut shows its symbols alone.
- **Hitoiki has no Dock icon. Its icon is in the menu bar, and you can turn that off in Settings.** While the menu bar setting is off (an upgrader who turned it off), this reads instead: **Hitoiki has no Dock icon. You can show its icon in the menu bar from Settings.**
- **In the panel, ⌘, (Command-comma) opens Settings.**
- One button, **Open Hitoiki**, the default (Return).

When the launch could not register the shortcut (the launch status is not `noErr`), the two shortcut lines are replaced by **⌃⌘Space couldn't be set up. Another app or macOS may already be using it.** — the attempted combination's symbols — and there are two buttons: **Open Hitoiki** and **Change the Shortcut**, the default. The panel's existing launch notice is unchanged.

The buttons: **Open Hitoiki** closes the window and shows the panel. **Change the Shortcut** closes the window and opens Settings as the menu bar item's Settings… does. Escape and the close button close the window and show nothing.

**Decision 2 — Once.** A new stored key, `welcomeShown`, the eleventh in `Settings.Key`. The window shows at launch only when the key does not hold true. The key is written true at the moment the window is shown, so a quit with the window still open counts as seen. Nothing else in the app reopens the window. Someone upgrading from 1.0.0 has no such key and sees the window once (ruled in the Think: v1.0.0 writes nothing until a setting changes, so an upgrade cannot be told from a new install).

**Decision 3 — Never at login.** When macOS marks the launch as a login-item launch (the open-application event carries the "launched as login item" mark), Hitoiki writes `welcomeShown` true and shows nothing. Open at Login can be turned on only after a first launch, so the only person this reaches is an upgrader with Open at Login on. Whether macOS sets the mark for an `SMAppService` login item is not verified; if it does not, that upgrader sees the window once at login. No run-sheet test (ruled).

**Decision 4 — The menu bar item on by default.** `menuBarEnabled` reads true when its key is absent. A stored false — anyone who turned it off — stays off.

**Decision 5 — Documents follow the code.** README and `TECHNICAL.md` describe the welcome window, the menu bar default, and the eleventh key. Nothing else in them changes. `packaging/release-notes-1.0.1.md` is new.

**Decision 6 — Help, and About's maker line (ruled 2026-11-19, after trying the local build).** A **Hitoiki Help** item follows About Hitoiki in the menu bar item's menu, and a **Help** button follows About Hitoiki in the settings footer; both open `https://hitoiki.sageframe.net/docs/`. In About, the maker's line becomes three lines, as pālana's About has it: "by Andrew T. Marcus"; "Sageframe", linked to `https://sageframe.net`; and the "Lovingly made by hand, in collaboration with AI, using the Ho process" sentence with its link. The atmarcus.net link goes. No new tests: the two tests that list the menu's items and the footer's buttons take the new entry. README and `TECHNICAL.md` follow. ho-08x does not run again for this (ruled).

---

## Changes

### The pull request

Branch `ho-08-first-launch` from `3b0c944`. One Opus builder (`model: opus`) writes the code, the tests and the documents on it. The builder may touch only:

- `Sources/Hitoiki/WelcomeWindow.swift` (new)
- `Sources/Hitoiki/App.swift`
- `Sources/Hitoiki/Settings.swift`
- `Tests/HitoikiTests/WelcomeWindowTests.swift` (new)
- `Tests/HitoikiTests/SettingsTests.swift`, `Tests/HitoikiTests/MenuBarItemTests.swift` — only where they pin the old default or the key count
- `README.md`, `TECHNICAL.md`
- `packaging/release-notes-1.0.1.md` (new): what changed in 1.0.1, in the voice of `release-notes-1.0.0.md`, with the same privacy and README sentences

The builder never launches the app. Tests run only through `scripts/vm-test.sh`.

### What the tests establish

Each invariant is tested across every partition named.

- **Once.** For a launch with the key absent and not at login: the window shows and the key holds true. With the key absent at a login launch: no window and the key holds true. With the key true, at login or not: no window, and the key is unchanged. No other path shows the window.
- **The written key.** `welcomeShown` is in `Settings.Key`; the store writes no key outside that list.
- **The menu bar default.** Absent reads on; stored false reads off; stored true reads on.
- **The text.** Shortcut registered and default: the symbols line and the spelled-out line. Registered and recorded: the symbols line alone. Not registered: the failure line naming the attempted combination, no spelled-out line, both buttons, Change the Shortcut the default. Menu bar on and off: the two menu bar lines.
- **The buttons.** Open Hitoiki: window closed, panel shown. Change the Shortcut: window closed, settings shown. Escape and the close button: window closed, panel and settings not shown.

### Verification

`scripts/vm-test.sh`: swift-format lint, SwiftLint strict, `swift build`, `swift test`, coverage floor (≥90% on HitoikiCore), release build — all six green. The orchestrator reads the whole diff and sweeps for secrets before each commit.

### ho-08x — the scoped review

`ho-process/hos/ho-08x-review-of-the-first-launch.md`, from `ho-process/x-ho-template.md`, reviews only the branch's diff against this spec: is each decision built as written, does each test establish its invariant rather than restate the code, and does any document claim more than the code does. Codex (`gpt-6-astra`) runs it as a fresh `codex exec` session and commits only its report to `ho-process/reviews/ho-08x-report-1.md`. One run expected; a trivial finding is fixed and closed without a ruling.

### Run sheet — the release

Each outward act waits for my yes: the PR, the merge, each Apple upload, the tag push, the release.

1. The PR opened (`gh auth switch --user sageframe-no-kaji` first), reviewed, and merged to `main`.
2. From `main`: `VERSION=1.0.1 ./scripts/build_macos.sh --dmg`, notarised.
3. Before: `ps` for running Hitoiki; none may run. My settings stay as they are (ruled): they hold no `welcomeShown`, so the install is an upgrader's first launch, which shows the window.
4. I quit Hitoiki, move `/Applications/Hitoiki.app` to the Trash, open the new disk image, drag Hitoiki to Applications, and open it. Expected: the welcome window as in Decision 1. I press Open Hitoiki; the panel shows. I quit and open it again: no welcome window.
5. The orchestrator makes `release/hitoiki-1.0.1.zip` with `zip -X`, the disk image alone, and records both SHA-256 fingerprints here.
6. `git push origin main`, the `v1.0.1` tag, and the GitHub release as Latest with `packaging/release-notes-1.0.1.md` and no disk image.
7. I swap the ZIP on the Payhip listing.
8. With 1.0.1 quit, I open v1.0.0 from `release/hitoiki-1.0.0.dmg` and press the shortcut: the panel shows "Hitoiki 1.0.1 is available". I quit it; `ps` confirms no copy runs.

### Closing Phase 4

The overview's phase-closing entry for Phase 4 as v1.0. The State Memory's lifecycle moves from kamae to production.

### Commits

On the branch: `ho-08: open — the first launch, spec`; the builder's work as `ho-08: the welcome window and the menu bar default`; the x document and Codex's report. On `main` after the merge: the close. No trailers, no attribution.

---

## Results

Closed 2026-11-21.

- **Built and merged.** Branch `ho-08-first-launch`: the spec (`f927f3e`), the welcome window and the menu bar default (`45c10a1`), ho-08x and its report, N2's comment (`5add59e`), Decision 6's Help and About (`b84556d`), and the Help action renamed to `openHelp` (`02eb909`) after my run showed macOS's own "Help isn't available": `NSApplication` answers `showHelp:` before the delegate. PR #3, merged as `baaf678`. Final `scripts/vm-test.sh`: six green, 229 and 71 tests, 95.76% / 98.35%.
- **ho-08x: Pass** on run 1 (`ho-process/reviews/ho-08x-report-1.md`, `7c3f2a0`), Codex `gpt-6-astra` under `ho-antagonist-review` pinned at Ho System `552fb4a`. 0 Must-fix, 0 Should-fix. N1 (the tests call the welcome routine, not a launch) was answered by my launch of the local build; N2 (a stale comment) fixed. Decision 6 and the rename were not reviewed again, by ruling.
- **The local build.** I opened a local 1.0.1 copy, saw the welcome window, and asked for Help and About's new maker lines (Decision 6). Settings were not exported or deleted (ruled); `welcomeShown` was cleared by hand between runs.
- **Release.** `VERSION=1.0.1 ./scripts/build_macos.sh --dmg` from `baaf678`: both uploads Accepted, app and disk image stapled, Gatekeeper accepts both as Notarized Developer ID. Tag `v1.0.1`; GitHub release "Hitoiki 1.0.1", Latest, no disk image; the releases-latest endpoint answers `v1.0.1`.

  | File | SHA-256 |
  |---|---|
  | `release/hitoiki-1.0.1.zip` (holds only the disk image) | `2310ccfc329166df9c90d973ef3d4f0fa315ca2103feb0732aca29d94a9058ef` |
  | `release/hitoiki-1.0.1.dmg` | `27cc28ecb3c3cfd8e06cc799866e704f19f5ec282834c5febd867e9053987276` |

- **The site.** `sageframe-dharma/hitoiki-web` `cf47a0f`, deployed: the docs page names the welcome window, the menu bar item on by default, and Hitoiki Help. My five unpushed local commits in that repository stay unpushed, replayed on top. The menu screenshot (`assets/screens/menu.webp`) predates Hitoiki Help.
- **Payhip.** The ZIP swap is mine (run sheet step 7). Step 8, v1.0.0 showing the update line for 1.0.1, is not run.
- **Phase 4 closed as v1.0.** The lifecycle moves to production.

### Closing this ho

Closing = fill Results + flip `status: complete` + write the state-summary block to the top of `ho-process/kamae-6-hitoiki-state-memory.md`, with PROJECT LIFECYCLE moved from kamae to production + append a build-record entry to `ho-process/kamae-4-hitoiki-ho-overview.md` with the opening and closing hashes and ho-08x's verdict, then the entry that closes Phase 4 as v1.0 + regenerate `metadata/ho-status.md` and `metadata/ho-status.json`. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — ho-08: v1.0.1 with the welcome window and the menu bar default, reviewed, released on GitHub and Payhip; Phase 4 closed as v1.0
- **NEXT** — <the single pointer to what comes next>
- **ACTION ITEMS / BLOCKS** — <open items; issues #1 and #2>
- **PROJECT LIFECYCLE** — production

---

_Authored: 2026-11-19._
_Commit: 3b0c944..baaf678, and the close._
