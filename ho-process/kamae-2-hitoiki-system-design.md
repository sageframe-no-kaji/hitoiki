---
created: 2026-10-24
status: complete
type: system-design
project: issoku
stage: kamae-2
kamae-chain: seed → **system-design** → readme → ho-overview
builds-on: kamae-1-issoku-seed
next: kamae-3-issoku-readme
---

# Issoku 一息 — System Design (Kamae 2)

**One command. One result. Done.**

> Issoku is a temporary interface to the shell. Press a key, type a command, read the result, dismiss it. The command runs in your own shell with your own SSH keys and config. Nothing stays open, nothing runs in the background, and the terminal was never opened.

---

## 0. What this document decides

The seed left seven open questions and one directive: establish the minimal correct SSH/PTY process model before building a polished interface. This document commits the architecture around that directive. It fixes the component shape, the lifecycle, the process model, the data model, the stack, and the distribution path. It assigns what it cannot decide from the desk to the first ho, an experiment, with the criteria that will decide it.

Decisions made in the Kamae 2 conversation that changed or sharpened the seed are marked **(revises seed)** where they occur.

---

## 1. Architecture Overview

Four components, sliced by what the user experiences.

```text
                    Control-Command-Space
                            │
                            ▼
   ┌─────────────────────────────────────────────────┐
   │  PANEL                                           │
   │  appears · takes focus · running/done states     │
   │  dismiss rules · Stop · Open in Terminal · gear  │
   │                                                  │
   │   ┌──────────────────────┐                       │
   │   │ input (Composing)    │  ◀── MEMORY           │
   │   └──────────┬───────────┘      macros ⌘1–9      │
   │              │ Return            history recall  │
   │              ▼                   settings        │
   │   ┌──────────────────────┐                       │
   │   │ TRANSCRIPT           │                       │
   │   │ streamed output      │                       │
   │   │ exit status · copy   │                       │
   │   └──────────▲───────────┘                       │
   └──────────────┼───────────────────────────────────┘
                  │ bytes out        keystrokes in (Running)
                  │                        │
   ┌──────────────┴────────────────────────▼──────────┐
   │  RUN                                              │
   │  one PTY · one child · one process group          │
   │  $SHELL -c <line> with the captured environment   │
   │  interrupt · force-kill · exit status             │
   └───────────────────────────┬───────────────────────┘
                               │
                 local binary, or /usr/bin/ssh → remote host
                 (user's ~/.ssh/config, keys, launchd agent)
```

| Component | Does | Owns | Talks to |
|---|---|---|---|
| **Panel** | Appears on the hotkey, takes focus, enforces the lifecycle rule, dismisses | The window, hotkey registration, the Composing/Running/Done state | Run (start, stop, kill), Transcript (shows it), Memory (reads settings and macros) |
| **Run** | Lives one command's life: launch, stream, forward keystrokes, interrupt, report exit | The PTY, the child process and its process group, the environment captured at launch | Panel (state changes, exit), Transcript (bytes) |
| **Transcript** | Renders output as it arrives, selection, copy, exit status, bounded memory | The rendered text and the minimal terminal-control handling | Run (receives bytes), Panel (hosted in it) |
| **Memory** | Settings, the nine macros, command history | User defaults and the history file | Panel (settings UI, macro load, history recall) |

A fifth component, Hand-off, was proposed and dissolved during the conversation. Retry-with-`-tt` is a relaunch and belongs to Run. Open in Terminal is a button and belongs to Panel. The update check is a setting and belongs to Memory.

---

## 2. Component Breakdown

### 2.1 Panel

**Responsibility.** The only visible surface. It registers the global hotkey, shows a floating, non-activating panel on invocation, places keyboard focus in the input, and moves between three states:

- **Composing** — input focused, Transcript empty or showing the previous result. Escape or click-out hides the panel.
- **Running** — a command is alive. Escape and click-out do nothing. Stop is visible. Keystrokes forward to Run. Nothing typed is drawn locally.
- **Done** — the process exited. Exit status is shown. Escape or click-out hides the panel. Return in the input starts a new command.

**The lifecycle rule.** Nothing survives the panel. Escape and click-out never kill a running process; they are the accident paths and are inert while Running. The deliberate paths kill: Stop or Control-C sends an interrupt to the process group, a second Stop forces termination, and quitting Issoku terminates everything, exactly as closing a terminal window would. There is no background mode and no managed session. **(Confirms seed.)**

**Hotkey.** Registered through the system's hotkey registration call directly, without a dependency. No Accessibility permission is required. Registration can fail silently when another app or macOS already owns the combination; Panel detects the failure and reports it in the panel and in settings. The default `Control-Command-Space` collides with macOS's Character Viewer where that shortcut is still enabled; the conflict is reported, not worked around.

**Recovery.** Issoku runs without a Dock icon and, by default, without a menu bar item. Relaunching the app from Applications while it is already running brings the panel up. That is the way in if the hotkey ever fails.

**Open in Terminal.** A button in Done state opens a terminal at the command's working directory. macOS has no system-wide default-terminal setting an app can query, so Issoku defaults to Terminal.app, which every Mac has, and a setting selects another installed terminal (Ghostty, iTerm2, Kitty, WezTerm, Alacritty detected when present). It never re-runs the command. Carrying the transcript into the new terminal is a nice-to-have, dropped if it costs anything. **(Revises seed: new scope, agreed in conversation.)**

**Settings access.** A gear in the panel reaches settings, Check for Updates, and Quit. A menu bar item exists as a setting, off by default.

**Interface to Run.** `start(line, cwd)`, `interrupt()`, `kill()`. Receives `stateChanged(.running | .done(status))`.

**Amendment, 2026-11-05 (ho-04.6).** The text above stands as written. ho-04.6 (`ho-process/hos/ho-04.6-escape-ladder-and-click-out.md`) revises the three states' exits, by the practitioner's rulings of 2026-11-04 and 2026-11-05. Escape is a deliberate path that peels one layer at a time: while Running it stops the command as Stop does; a stopped, Done or typed panel it clears to a clean panel still on screen, killing anything alive; a clean panel it hides. Click-out hides the panel and keeps everything on it, and the next summons brings it back as it was; it never hides a running command, which stays on screen without the keyboard. The hotkey shows a hidden panel, gives the keyboard to a visible one without it, and hides one with it, except while Running, where it never hides. "Nothing survives the panel" and "there is no background mode" stand. "Escape and click-out never kill a running process; they are the accident paths and are inert while Running" is superseded for Escape and confirmed for click-out. Escape never reaches the command as a key.

**Amendment, 2026-11-10 (ho-05.1 run sheet).** "A gear in the panel reaches settings, Check for Updates, and Quit" is kept in effect and changed in shape: the gear opens the settings window directly, with no menu; Quit is a button at the foot of settings, and Check for Updates joins it there at ho-06; Command-Q on the panel quits, through the same path as Quit. The menu bar item keeps its own menu. Document: `ho-process/hos/ho-05.1-settings-and-macros.md`, Decision 18.

### 2.2 Run

**Responsibility.** One command's life. Run is the only component that touches processes, and the only boundary a sandboxed build would ever change entitlements behind.

**Environment.** At app launch, Run executes the user's login shell once to read its environment and keeps the result. Every command then runs with that environment. Cost is a few hundred milliseconds at launch, zero per command. A manual Refresh Environment action in settings re-captures it. The SSH agent socket macOS's launchd provides is stable for the login session, so the case that matters does not go stale. **(Decides seed's Environment question.)**

**Amendment, 2026-11-10 (ho-05.1 run sheet).** The manual Refresh Environment action is dropped from settings: relaunching the app re-reads the environment the same way and the app loses nothing by relaunching, so the button was a second way to do one thing. The capture at launch stands; Run keeps its re-capture for it. The README says to relaunch to pick up a changed shell environment. Document: `ho-process/hos/ho-05.1-settings-and-macros.md`, Decision 17.

**Launch.** Each command runs as the user's shell, non-interactively, with the typed line as its argument, under a pseudoterminal, in its own process group, with the working directory from settings. Non-interactive means aliases and shell functions do not resolve; this is accepted. The trade is startup speed and predictability against alias support, and one-off commands are mostly `ssh` and system binaries. An alias that fails is an honest failure corrected by typing the real command.

**Streaming.** Bytes from the PTY go to Transcript as they arrive.

**Input.** While Running, keystrokes from Panel go to the PTY and nowhere else. Run never echoes locally. What appears in Transcript is only what the process sends back. When remote `sudo` reads a password it disables echo on its own terminal, so the password is never sent back and never appears. No echo-flag detection and no special password field is needed. **(Revises seed: simpler than the seed's password-entry section, satisfying the same requirements.)**

**Termination.** Interrupt sends `SIGINT` to the process group. Force sends `SIGKILL` to the process group. Exit is reported with the status. The first ho verifies that no orphans remain in either path, including the remote `ssh` case.

**The `-tt` retry rule.** Run does not rewrite commands. When a command exits non-zero and its output contains sudo's exact message that a terminal is required to read the password, and the typed line begins with `ssh ` and does not already carry `-t`, Panel offers a one-keystroke retry. Accepting relaunches the same line with `-tt` inserted after `ssh`. That insertion is the entire transformation. It is safe because sudo refused before running anything. Typing `-tt` by hand continues to work and never triggers the offer. **(Revises seed: replaces the proposed command parser.)**

**Interface.** Exposes `start`, `interrupt`, `kill`, a byte stream, and a state stream. Depends on nothing else in the app.

### 2.3 Transcript

**Responsibility.** Show what the process sent, readably, with a fixed memory ceiling.

**Rendering.** Monospaced text. Minimal terminal-control handling: colour sequences, carriage-return overwrite for progress bars, and stripping of other control sequences. Full terminal emulation is not built. The first ho runs the user's real command set through this minimal handling and records any command that renders unreadably. That list, and only that list, justifies an emulator later. **(Decides seed's Terminal Output question, pending ho-01 evidence.)**

**Bounded memory.** A fixed ceiling of retained lines, oldest dropped first. The number is implementation tuning and belongs to ho-04.

**Copy.** Standard text selection. `Command-C` copies the selection, or the whole transcript when nothing is selected. A visible Copy control does the same.

**Status.** Exit status is shown in Done state. Non-zero and signal exits are visually distinct in the design system's alarm colour, used for nothing else.

### 2.4 Memory

**Responsibility.** The three things that persist.

- **Settings** in user defaults: shortcut, working-directory mode (home, last used, fixed path), terminal for Open in Terminal (Terminal.app default), history on/off, menu bar item on/off, automatic update check on/off.
- **Macros** in user defaults: nine slots, each a command and an optional name. `Command-1` through `Command-9` load the macro into the input. Nothing runs until Return. Macros therefore double as path and host templates. **(Revises seed: load, not execute.)**
- **History** as a plain text file, one command per line, in the app's Application Support folder. Off by default, with a visible toggle. When on: recall in the input, and a Clear action that deletes the file. Plain text so it can be read, searched, and removed outside the app. **(Decides seed's history requirement.)**

Transcripts are not stored. **(Confirms seed.)**

**Amendment, 2026-11-08 (replan checkpoint after ho-04x, ruling 5).** The text above stands. The automatic update check's switch is one of these settings, built in ho-05.1, reading as on when its key is absent. The check keeps its last-checked time in memory only; no key is persisted for it. The request it makes is fixed in §6's amendment of the same date. Document: `ho-process/hos/replan-after-ho-04x.md`.

**Amendment, 2026-11-09 (ho-05.1 Think).** An appearance override joins the settings: system, light or dark, system the default and read as system when its key is absent; one value, set on `NSApp.appearance`, since every colour token already carries a light and a dark value (pālana's ho-15 pattern). Built in ho-05.1. Document: `ho-process/hos/ho-05.1-settings-and-macros.md`.

**Amendment, 2026-11-09 (ho-05.1 Think).** The working-directory mode has two values, home and a fixed path, not three. "Last used" has no meaning here: every command runs in its own shell and nothing typed moves the app's directory, so a last-used folder could only ever equal home or the fixed path. Home is the default. A fixed path that no longer exists at launch or at Return is replaced by home for that command and the strip says so. Document: `ho-process/hos/ho-05.1-settings-and-macros.md`.

**Amendment, 2026-11-10 (ho-05.1 run sheet).** A macro is a command and nothing else; the optional name is dropped. It was shown nowhere but the settings window, and two unlabelled boxes a row made the practitioner type commands into the name. §4's row reads: nine macros, user defaults, an array of nine strings. Document: `ho-process/hos/ho-05.1-settings-and-macros.md`, Decision 16.

**Amendment, 2026-11-10 (ho-05.2 Think).** The text above stands; the history bullet is sharpened and extended by the practitioner's rulings. Recall works with history off, from the commands run since launch, and with history on from those and then the file. Recall is a list that Down-arrow drops below the input, newest first, filtered by what is typed, and a grey suggestion after the cursor that Right-arrow takes; neither runs anything, and there is no control on the bar. The file holds what ran, one line each, at most 5,000 lines, trimmed at Return. A line that starts with a space is kept nowhere. Clear deletes the file and forgets the session's commands too. §2.1's note of 2026-11-10 put a Quit button at settings' foot; it is removed, and Command-Q quits from the settings window as from the panel. §4's history row stands, with the folder named Hitoiki since ho-04.5. Document: `ho-process/hos/ho-05.2-history.md`.

**Amendment, 2026-11-12 (ho-06.1 run sheet).** The text above stands. An Open at Login switch joins the settings, off by default. Its state is kept by macOS's login-item service for the app (`SMAppService.mainApp`), not in user defaults, so no key is added and the switch shows a change made in System Settings. It is disabled in a build from source. Document: `ho-process/hos/ho-06.1-the-build.md`, Decision 20.

**Amendment, 2026-11-19 (ho-08).** The menu bar item is on by default: its setting reads on when its key is absent, and a stored off stays off. This supersedes "off by default" in §2.1's Recovery and Settings access and in §7. The first launch shows a welcome window that says the app is running, names the shortcut, and offers to change it when the shortcut could not be registered; a launch macOS marks as a login item's shows nothing. One key, `welcomeShown`, joins the settings, written by the first launch. Document: `ho-process/hos/ho-08-the-first-launch.md`.

---

## 3. Core Interaction

The user is in Claude Code and needs to restart a service on a remote host.

1. **Hotkey.** Panel appears over the current app with the input focused. Working directory is home, per the default setting.
2. **Type and Return.** `ssh host-a 'sudo systemctl restart caddy'`. Panel moves to Running. Escape and click-out are inert. Stop is visible.
3. **Launch.** Run opens a PTY, spawns the user's shell non-interactively with the line and the captured environment, in a new process group. `ssh` finds `~/.ssh/config` and the agent socket because the environment is the user's own.
4. **Failure.** Remote `sudo` cannot read a password without a terminal and says so. The process exits non-zero. Transcript shows the message and the status in the alarm colour. Panel moves to Done and, because the line begins with `ssh` and the message matched, offers retry with `-tt`.
5. **Retry.** The user accepts. Run relaunches `ssh -tt host-a 'sudo systemctl restart caddy'`. Panel is Running again.
6. **Password.** sudo prompts. The user presses the keyboard macro key that types their password. Keystrokes go to the PTY. Nothing is drawn locally, and sudo does not echo, so the transcript shows the prompt and nothing else.
7. **Done.** The service restarts, the process exits zero, Panel moves to Done. The user reads the result, presses `Command-C` if they want it, and presses Escape. The panel is gone. The terminal was never opened.

The local variant is the same path with fewer steps: hotkey, `df -h`, read, Escape.

If the user wants to keep going, Open in Terminal puts their terminal at the working directory and the session continues there. Issoku does not grow a terminal because one is a button away.

---

## 4. Data Model

| What | Where | Format | Why |
|---|---|---|---|
| Settings | User defaults | Standard macOS preferences | Settings UI binds directly; nothing to invent |
| Nine macros | User defaults | Array of `{name?, command}` | Same store as settings; small, structured |
| Command history | `~/Library/Application Support/Issoku/history.txt` | One command per line, UTF-8 | Inspectable and clearable with ordinary tools; off by default |
| Captured environment | Process memory only | Key/value | Re-read at launch or on Refresh; never written to disk |
| Transcripts | Nowhere | — | Not stored in v1 |

Nothing else persists. There is no database, no custom configuration format, and no cache.

---

## 5. Technology Stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Swift 6, strict concurrency | Native macOS, the practitioner's current language, and the one that reaches AppKit and POSIX directly |
| Window and hotkey | AppKit | A non-activating floating panel and system hotkey registration are AppKit facilities; SwiftUI cannot do either cleanly |
| Settings and small views | SwiftUI, hosted in AppKit | Simplifies forms; used only where it removes code |
| Process and PTY | POSIX via Foundation | The PTY must be the child's controlling terminal; the exact spawn call is decided in ho-01 |
| SSH | `/usr/bin/ssh` | The user's config, keys, and agent, unchanged. No SSH library, ever |
| Terminal output | Minimal in-house handling | Colours and carriage returns; emulator only on ho-01 evidence |
| Build | SwiftPM only, no Xcode project | `Package.swift` is canonical; the app bundle is assembled by script, as palana does it |
| Lint and format | swift-format, SwiftLint, pre-commit | From the practitioner's Swift baselines in `~/.claude/templates/` |
| Tests | swift-testing, with XCTest where needed | Coverage floor 90%, UI views excluded with a comment naming which |
| Dependencies | None at v1 | Every candidate was evaluated and rejected below |

### Evaluations

**Swift and AppKit, against Tauri or Electron.** A floating non-activating panel, a system hotkey, a PTY, and a sub-200 ms appearance are all direct AppKit and POSIX calls. A web shell would add a runtime larger than the whole app to reach the same calls through a bridge. Rejected on weight alone, which is the seed's first constraint.

**SwiftUI alone, against AppKit for the window.** SwiftUI has no non-activating panel and no hotkey registration. AppKit owns the window; SwiftUI is allowed inside it for settings where it shortens code. Decided.

**Shortcut library, against direct registration.** The well-known Swift package wraps the same system call and adds a recorder view. The call is about forty lines. The recorder is the real work and is small. Rejected to avoid a dependency for forty lines.

**State-management framework, against plain state.** Three states and one window. The seed forbids a framework for a simple window. Rejected.

**SwiftTerm or libghostty, against minimal handling.** Both are full emulators. The user's commands finish within thirty seconds and are read and copied, not interacted with as full-screen programs. The profile needs colours and carriage returns. Deferred to ho-01's evidence; adopted only if a real command renders unreadably, and libghostty considered first for weight if that happens.

**Login shell per command, against one capture at launch.** Per-command login shells carry aliases but pay startup files and their side effects on every command. One capture at launch is near-zero cost because the app is resident anyway. Decided: capture at launch, with manual refresh.

**Automatic `-tt` rewriting, against sudo's own error.** The seed proposed recognising `ssh … sudo` and rewriting. sudo fails before running anything when it lacks a terminal, with a fixed message. Recognising the message and offering a retry has no parser, no guessing, and a safe relaunch. Decided: no rewriting.

---

## 6. Deployment Model

**Distribution.** A signed and notarised `.app` inside a `.dmg`, published on GitHub Releases and sold through Payhip for approximately three dollars as a convenience. The source is MIT licensed and builds free at every version. No activation, account, or licensing server.

**Build pipeline.** Inherited from palana: SwiftPM release build, bundle assembled by script, Developer ID signing with hardened runtime, notarisation of the app, stapling, then the `.dmg` notarised and stapled in turn. The script and `RELEASING.md` are adapted, not rewritten.

**Updates.** An optional check against the GitHub Releases latest endpoint, on by default, disclosed in settings, with a manual Check for Updates. The 99-line update checker from palana is ported. No telemetry, no identifiers, no command text leaves the machine.

**Amendment, 2026-11-08 (replan checkpoint after ho-04x, ruling 5).** The text above stands and is made exact. What is sent: one GET to GitHub's releases-latest endpoint for the Hitoiki repository, no body, no query, no account, no identifier; the User-Agent header is set explicitly to `Hitoiki/<version>` and nothing more, since GitHub requires one and the system's default names the networking library and OS versions. How often: at launch, and once a day while the app is running; the last-checked time is held in memory only. The default: on, with the switch in settings (§2.4). The README's Privacy section quotes the request in full and the ship review reads the code against it word for word. Built in ho-06. Document: `ho-process/hos/replan-after-ho-04x.md`.

**Amendment, 2026-11-12 (ho-06.1 Think).** The amendment above stands, with three changes by the practitioner's rulings. The README's Privacy section states the check in plain words (the name and version only, nothing about the user or their commands, GitHub sees the address, the switch turns it off) and does not quote the request; no test captures it from the wire; the review reads the code. The request also carries `Accept: application/vnd.github+json`, carries no `Accept-Language`, and goes from a memory-only session, so no cookie is kept and no reply is cached. A newer release shows a line in the panel and an answer in settings, and both open the project's site, `hitoiki.sageframe.net`, not GitHub. The pipeline above is built in ho-06.1; distribution through Payhip and the site is ho-07's. Document: `ho-process/hos/ho-06.1-the-build.md`.

**Amendment, 2026-11-14 (ho-06.3, Decisions 2 and 12).** Distribution follows pālana's model at 1.0: the signed, notarised `.dmg` is sold through the site and Payhip, and is not attached to the GitHub release; the source is MIT and builds free at every version. GitHub Releases carries each version's tag and notes, which the update check reads. v1.0.0 is published on GitHub in ho-06.3; the sale opens with ho-07's site. The README names no price. Document: `ho-process/hos/ho-06.3-the-documents.md`.

**Amendment, 2026-11-17 (ho-07).** The app sells for $6 on Payhip (`https://payhip.com/b/2Tgu0`), linked from the site's Buy button. Payhip refuses `.dmg` files, so the listing delivers a ZIP that holds the notarised, stapled disk image and nothing else (`hitoiki-<version>.zip`). The site is the public repository `sageframe-dharma/hitoiki-web`: static pages with no build step, published to Cloudflare Pages from `public/` only, by a workflow that runs on every push to `main`. Document: `ho-process/hos/ho-07-the-storefront.md`.

**Requirements.** macOS 14 or later, matching palana. OpenSSH as shipped with macOS. No other software; Open in Terminal uses Terminal.app unless another terminal is selected in settings.

**Mac App Store.** Not at v1 and not before 1.0. A sandboxed build cannot read `~/.ssh/config`, cannot reach the SSH agent, cannot write known-hosts, and cannot run the user's shell with the user's environment. What the sandbox would permit is a free, local-only build with no SSH. Review outcome for an arbitrary-command runner is unknown. The architecture is prepared for it only in that Run is the single boundary; a sandboxed build changes entitlements and disables features and adds nothing. **(Revises seed: from "may be considered" to "deferred past 1.0, prepared, not built.")**

**Design.** Issoku inherits the pālana design system as written in `palana/design/palana-design-system.md`: warm ground, near-black ink, one moss accent, rust for failure only, system font with monospace rationed to where the literal record is shown. The eight colour tokens are copied into Issoku's own Theme file, not shared as a package. The Transcript is the one monospace zone. The app icon is open; the practitioner is leaning toward a digitised terminal symbol and will design it later.

---

## 7. Scope Boundaries

### MVP architectural commitments

- **One process at a time.** Run holds one PTY and one child. A second command waits for Done.
- **Nothing survives the panel.** No background sessions, no managed jobs, no reconnect. Quitting kills.
- **No shell session.** Each command is one process. Completion is process exit. There is no prompt detection because there is no prompt.
- **No SSH of its own.** `/usr/bin/ssh` and the user's config, keys, and agent. No host inventory, no connection manager, no credential storage.
- **No command rewriting.** The only transformation is inserting `-tt` after `ssh`, on an explicit retry, after sudo's own error.
- **No terminal emulation** beyond colours and carriage returns, pending ho-01 evidence.
- **No persistence beyond settings, macros, and an optional history file.** No transcripts, no database.
- **No menu bar item and no Dock icon by default.** The panel is the UI.
- **No dependencies.** The package graph is empty at v1.
- **No App Store build.**

### Architecturally prepared for, not built

- **A sandboxed, local-only App Store build.** Run is the single process boundary. Entitlements change, SSH-dependent features switch off, nothing is added.
- **An emulator behind Transcript.** Transcript receives bytes and renders; swapping the renderer does not touch Run or Panel.
- **Transcript carry-over into Open in Terminal.** The transcript exists as text; handing it to the terminal is a button's implementation detail, if it ever proves cheap.
- **Finder-folder working directory.** The working-directory setting is an enum; a frontmost-Finder mode is one more case, not a new mechanism.

### Explicitly out, restated from the seed

Not a terminal emulator, multiplexer, SSH manager, server dashboard, session manager, log monitor, command library, plugin platform, AI assistant, workflow tool, or terminal replacement. Full-screen programs such as vim, htop, and tmux are outside the interaction; Open in Terminal is where they go.

---

## Identity Statement

**Tagline:** One command. One result. Done.

**Hero:** Issoku is a temporary interface to the shell. Press a key, type a command, read the result, dismiss it. The command runs in your own shell with your own SSH keys and config. Nothing stays open, nothing runs in the background, and the terminal was never opened.

Both are the seed's words, unchanged. Every decision above was tested against them: does it keep the interface temporary, and does it keep the code small.

---

## Provisional Ho Sequence

| Ho | Title | Purpose |
|---|---|---|
| ho-00 | Orientation | Scaffold from the Swift baselines: SwiftPM only, swift-format, SwiftLint, pre-commit, project CLAUDE.md, Theme tokens copied from palana |
| ho-01 | The Spike | The PTY experiment, throwaway code, against the criteria in Deferred Decisions. Replan checkpoint after |
| ho-02 | Run | The production process model, headless and fully tested |
| ho-03 | Panel | Hotkey with conflict detection, floating panel, states, dismiss rules, Open in Terminal |
| ho-04 | Transcript | Rendering, minimal terminal-control handling, bounded buffer, copy, status |
| ho-05 | Memory | Settings with shortcut recorder, macros, history file |
| ho-06 | The Ship | Icon, signing and notarisation, update checker, Payhip, README |

Six build hos after orientation. The Ho Overview (Kamae 4) refines this into phases and may split or reorder.

---

## Deferred Decisions

Each is assigned to the ho that resolves it, with the criteria it must meet.

**ho-01, The Spike.**

- **Spawn mechanism.** Which POSIX path gives a PTY that is the child's controlling terminal, in a new process group, with the captured environment, from Swift with strict concurrency. Criterion: `ssh -tt <host> 'sudo true'` prompts, the password is answered by keystroke, nothing echoes, the command completes.
- **Process ownership.** Interrupt reaches the whole group; a process that ignores it yields to force-kill; no orphans remain afterwards, verified in the process table, for both local and remote commands.
- **Failure legibility.** Unreachable host, rejected key, and wrong password each end with a readable status.
- **Memory ceiling.** Fifty megabytes of output stays within a fixed ceiling.
- **Latency.** Measured hotkey-to-panel and Return-to-first-byte for local and remote `uptime`.
- **Terminal-control depth.** The user's real command set through minimal handling; a recorded list of anything unreadable. Empty list means no emulator.

**ho-02, Run.**

- Environment capture: which shell invocation, which variables are kept, how Refresh Environment behaves while a command is running (it waits).
- The exact sudo message matched for the retry offer, with a test fixture of sudo's output.

**ho-03, Panel.**

- Hotkey failure presentation and the Character Viewer conflict message.
- Whether transcript carry-over into the terminal is cheap. If it is not, it is dropped without discussion.
- How installed terminals are detected for the picker, and how Terminal.app is opened at a directory.

**ho-04, Transcript.**

- The line ceiling for the buffer.
- Which control sequences are stripped versus honoured, from the ho-01 list.

**ho-05, Memory.**

- History file write timing (on Return) and what counts as a duplicate for recall.
- The shortcut recorder's handling of modifier-only and system-reserved combinations.

**Not tied to a v1 ho.**

- **App icon.** Open. Leaning toward a digitised terminal symbol. The practitioner designs it; ho-06 ships whatever exists.
- **App Store build.** After 1.0, if ever.
- **ControlMaster in the user's SSH config.** Not an app decision. The README's Requirements section may mention it as the way to make repeated remote commands fast.
