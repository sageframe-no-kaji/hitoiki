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

### 2.2 Run

**Responsibility.** One command's life. Run is the only component that touches processes, and the only boundary a sandboxed build would ever change entitlements behind.

**Environment.** At app launch, Run executes the user's login shell once to read its environment and keeps the result. Every command then runs with that environment. Cost is a few hundred milliseconds at launch, zero per command. A manual Refresh Environment action in settings re-captures it. The SSH agent socket macOS's launchd provides is stable for the login session, so the case that matters does not go stale. **(Decides seed's Environment question.)**

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

---

## 3. Core Interaction

The user is in Claude Code and needs to restart a service on a remote host.

1. **Hotkey.** Panel appears over the current app with the input focused. Working directory is home, per the default setting.
2. **Type and Return.** `ssh koan 'sudo systemctl restart caddy'`. Panel moves to Running. Escape and click-out are inert. Stop is visible.
3. **Launch.** Run opens a PTY, spawns the user's shell non-interactively with the line and the captured environment, in a new process group. `ssh` finds `~/.ssh/config` and the agent socket because the environment is the user's own.
4. **Failure.** Remote `sudo` cannot read a password without a terminal and says so. The process exits non-zero. Transcript shows the message and the status in the alarm colour. Panel moves to Done and, because the line begins with `ssh` and the message matched, offers retry with `-tt`.
5. **Retry.** The user accepts. Run relaunches `ssh -tt koan 'sudo systemctl restart caddy'`. Panel is Running again.
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
