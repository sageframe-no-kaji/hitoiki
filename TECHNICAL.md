# Hitoiki — Technical Description

This document describes how Hitoiki works. It names the files that do each job. It is true of the code in this repository at the commit that adds or changes it.

## How Hitoiki was made

Hitoiki was made with the [Ho process](https://hosystem.sageframe.net/). The work started from a seed document, [`ho-process/kamae-1-hitoiki-seed.md`](ho-process/kamae-1-hitoiki-seed.md), which states the problem and the limits the app must keep. The seed uses the project's first name, Issoku. A system design, a build plan and a record of each working session followed; they are in `ho-process/`. You do not need them to read this document.

## The four components

Hitoiki is one Swift package, `Package.swift`, with two products:

- `HitoikiCore`, a library with no user interface. It holds Run and the Transcript model.
- `Hitoiki`, the app. It holds everything on screen.

The package has no dependencies. It uses Swift 6 language mode with strict concurrency and needs macOS 14 or later.

In this document a capitalised name (Panel, Run, Transcript, Memory) is a component. "The panel" is the floating window on screen. "The command" is the text the user submits. "The child" is the process that runs it.

### Panel

Panel is the only surface the user works in. It registers the global shortcut, shows and hides the panel, and holds the state: Composing (no command), Running, or Done. It decides what each key and each control does.

| File | Job |
|---|---|
| `Sources/Hitoiki/Panel.swift` | The controller: the three states, the Escape ladder, submission, Stop, keystrokes, macros, Open in Terminal, the update line, the recall keys, and the last command shown in grey in the empty input |
| `Sources/Hitoiki/PanelWindow.swift` | The window: layout, placement, height, the strip of status and buttons at the foot, the update line, and the Command-key equivalents |
| `Sources/Hitoiki/Keystrokes.swift` | What a key pressed while a command runs becomes |
| `Sources/Hitoiki/Hotkey.swift` | Registration of the global shortcut with the Carbon event manager |
| `Sources/Hitoiki/Shortcut.swift` | A shortcut's key and modifiers, the checks a new shortcut must pass, and its displayed name |
| `Sources/Hitoiki/Terminals.swift` | The terminals Open in Terminal can use |
| `Sources/Hitoiki/MenuBarItem.swift` | The optional menu bar item and its menu |

The panel is a borderless, non-activating floating window. It takes the keyboard while the app underneath stays frontmost. The app has no Dock icon. The menu bar item is on by default.

The shortcut is registered through `RegisterEventHotKey`. This needs no Accessibility permission. If the registration fails, the panel and settings show the reason. The default shortcut is Control-Command-Space. To change it, Hitoiki registers the new combination first and releases the old one only after the new one succeeds. If the shortcut never works, open Hitoiki again from Applications: the app shows the panel.

**The welcome window.** `Sources/Hitoiki/WelcomeWindow.swift`. The first launch shows a window that says Hitoiki is running and names the shortcut that opens the panel, with "(Control-Command-Space)" under it while that is the shortcut. It says the app has no Dock icon and that its icon is in the menu bar, or, with the menu bar item off, that settings can show the icon there. It also says that `Command-comma` in the panel opens settings. Open Hitoiki, the default button, closes the window and shows the panel. If the launch could not register the shortcut, the window says so in place of the shortcut's lines and adds a second button, Change the Shortcut, which is then the default: it closes the window and opens settings. Escape and the close button close the window and show nothing. The launch writes `welcomeShown` as the window shows, so the window shows once, even if Hitoiki quits while it is open. Version 1.0.0 wrote no such key, so the first launch after an upgrade from it counts as a first launch. A launch whose open-application event carries macOS's login-item mark writes the key and shows nothing. Nothing else opens the window.

### Run

Run lives one command's life. It is the only component that starts or signals a process.

| File | Job |
|---|---|
| `Sources/HitoikiCore/Run/Run.swift` | The actor: start, output, keystrokes in, interrupt, kill, exit |
| `Sources/HitoikiCore/Run/PTY.swift` | `forkpty` and the child's steps between fork and exec |
| `Sources/HitoikiCore/Run/LoginEnvironment.swift` | Reads the user's environment from their login shell |
| `Sources/HitoikiCore/Run/Retry.swift` | The `-tt` retry offer and the scan for sudo's message |

Run holds one child at a time. A second start while a child is alive fails with `RunError.alreadyRunning`.

Run starts each command under a pseudoterminal because ordinary pipes give the child no terminal. The pseudoterminal is the child's controlling terminal, so a program that reads a password from its terminal, such as `sudo`, can read it there, and keys typed in the panel reach the program as terminal input. A program that turns off echo for a password works as it does in a terminal: Run never echoes, so the password never appears in the transcript. `forkpty` also makes the child the leader of a new session and process group, so Stop and `Control-C` signal the shell and every process in its group. The child sees a terminal of a known size, with `TERM` set, so a program that checks for a terminal can send colour sequences, which the Transcript model reads.

### Transcript

Transcript shows what the child sent, within fixed limits.

| File | Job |
|---|---|
| `Sources/HitoikiCore/Transcript/Transcript.swift` | The model: bytes in, styled lines out |
| `Sources/Hitoiki/TranscriptView.swift` | The view: draws the lines, the block cursor while a command runs, selection and copy |

The model handles a small set of terminal controls:

- Colour and weight: SGR `0` (reset), `1` (bold), `22` (regular), `30`–`37` (the eight basic colours) and `39` (default colour). Other SGR parameters are ignored.
- Carriage return moves to column zero, so a progress bar overwrites itself. Line feed ends the line. Tab is kept as a character.
- Every other escape sequence is removed. A sequence longer than 256 bytes is abandoned.

It is not a terminal emulator. Full-screen programs such as `vim`, `htop` and `tmux` do not work in it.

The model keeps at most 10,000 lines and 10 MiB in all. It drops the oldest lines first. The line in progress keeps its last 1 MiB. `Command-C` and the Copy button copy the selection, or the whole transcript when nothing is selected.

### Memory

Memory is what persists: settings, the nine macros, and the command history.

| File | Job |
|---|---|
| `Sources/Hitoiki/Settings.swift` | The settings and macros in user defaults |
| `Sources/Hitoiki/History.swift` | The session's commands and the history file |
| `Sources/Hitoiki/RecallList.swift` | The list of past commands under the input |
| `Sources/Hitoiki/SettingsWindow.swift` | The settings window and its footer, and the window's own keys and clicks |
| `Sources/Hitoiki/SettingsView.swift` | The settings form |
| `Sources/Hitoiki/ShortcutRecorder.swift` | The control that records a new shortcut |
| `Sources/Hitoiki/TerminalPopUp.swift` | The terminal pop-up in settings |
| `Sources/Hitoiki/WindowCloseWatch.swift` | Tells the form when the settings window closes |
| `Sources/Hitoiki/UpdateCheck.swift` | The update check (see [The update check](#the-update-check)) |
| `Sources/Hitoiki/LoginItem.swift` | Open at Login (see [About and Open at Login](#about-and-open-at-login)) |

Settings are eleven keys in the app's user defaults: `shortcutKeyCode`, `shortcutModifiers`, `directoryMode`, `directoryPath`, `terminal`, `appearance`, `historyEnabled`, `menuBarEnabled`, `updateCheckEnabled`, `macros` and `welcomeShown`, which records that the welcome window has shown. A key that is absent reads as its default. A new install writes nothing until the user changes a setting, except `welcomeShown`, which the first launch writes. Every change is written at once; there is no Apply button.

- **Working directory.** Home (the default), or a fixed folder. If the fixed folder does not exist when the user presses Return, the command runs in home and the strip says so.
- **Macros.** Nine strings. `Command-1` to `Command-9` put a macro's text in the input. Nothing runs until Return.
- **History.** Off by default. Hitoiki always keeps the commands run since launch in memory. With history on, it also appends them to `~/Library/Application Support/Hitoiki/history.txt`, one command per line. The folder is made with mode 0700 and the file with mode 0600. The file keeps the newest 5,000 lines. A command of several lines is kept line by line. A line that starts with a space, or is blank, is kept nowhere; the other lines of the same command are kept. Clear History deletes the file and forgets the session's commands.
- **Recall.** Down-arrow opens a list of past commands, newest first, filtered by what is typed. A grey suggestion after the cursor completes the newest command that starts with the typed text; Right-arrow takes it. Neither runs anything.

The gear in the panel and `Command-comma` open settings. Settings opened from the panel hide the panel; closing settings shows it again.

The settings window handles some keys itself, because the app has no Edit menu:

- While a text box has the keyboard, `Command-X`, `Command-C`, `Command-V`, `Command-A`, `Command-Z` and `Shift-Command-Z` cut, copy, paste, select all, undo and redo in that box. At other times these keys go where they went before, so the shortcut recorder still records them.
- Return or keypad Enter in a text box takes the keyboard out of the box. A click on the window's background does the same; the background is any place that is not a control, text or the shortcut recorder. The box keeps its value, because every change is stored as it is made.
- Escape closes the window, except while the shortcut recorder records or an input method composes text.
- `Command-1` to `Command-9` put the keyboard in that macro's box. `Command-Q` quits.

### Shared files

| File | Job |
|---|---|
| `Sources/Hitoiki/App.swift` | The application: makes one of each part at launch and connects them; handles reopen and Quit |
| `Sources/Hitoiki/Theme.swift` | The colour tokens, each with a light and a dark value |
| `Sources/Hitoiki/AboutWindow.swift` | The About window |
| `Sources/Hitoiki/WelcomeWindow.swift` | The welcome window the first launch shows |
| `Sources/Hitoiki/Resources/MenuBarIcon.svg` | The menu bar item's image |

## One command, from the shortcut to the exit status

1. **Launch.** `App.swift` makes one Run with the app's own environment. It then starts a capture of the login environment. The capture runs `<login shell> -l -c 'env -0'` once, with input from `/dev/null`. The login shell comes from the user's entry in the password database. The capture has five seconds. It drops `_`, `SHLVL`, `OLDPWD` and `PWD`, and adds `TERM=xterm-256color` if `TERM` is absent. If the capture fails, the panel says so, and commands run with the app's own environment. To read a changed shell environment again, quit and open Hitoiki.
2. **Shortcut.** The Carbon event manager calls the handler. If the panel is hidden, Panel places it on the screen that holds the mouse pointer and shows it, with the keyboard in the input. If the panel is visible without the keyboard, Panel gives it the keyboard. If the panel has the keyboard, Panel hides it, unless a command runs or is starting.
3. **Return.** `PanelWindow.swift` sends the input's text to `Panel.submit`. Shift-Return and Option-Return add a line break instead. Panel reads the working directory now. It sets the terminal size from the transcript's width and the panel's height limit. It waits for the environment capture to end, and for any command that Escape killed to end. Then it calls `Run.start`.
4. **Start.** `PTY.swift` calls `forkpty`. The child gets a new pseudoterminal as its controlling terminal, and leads a new session and process group. Before `execve`, the child sets every signal to its default action, clears its signal mask, and closes every file descriptor above 2. It then changes to the working directory and runs `<login shell> -c <command>` with exactly the captured environment. If the directory cannot be entered, the child exits with status 127. The shell is not interactive, so aliases and shell functions are not available.
5. **Running.** Run reports `.running(pid:)`. Panel clears the transcript and gives the command to `History.swift`, which keeps it by the history rule under Memory. A command is kept when it starts running, and at no other time. The input empties, and the command shows in it as grey placeholder text, which is never part of the input's value. The input cannot be edited. The keyboard goes to the transcript view, which draws a block cursor.
6. **Output.** Run reads the pseudoterminal in pieces of up to 16 KiB on its own serial queue. It passes each piece on unchanged and scans it for sudo's message. When 1 MiB has been read and not yet taken by Panel, Run stops reading until Panel takes more; the child then waits on its terminal. Panel feeds each piece to the Transcript model, and the view draws the change. The panel grows with the output until the whole panel is about half the screen's height. Then the transcript scrolls.
7. **Keys.** While a command runs, `Keystrokes.swift` turns each key into an action. Return and keypad Enter write a carriage return. Delete writes DEL. Printable characters are written as UTF-8. `Command-V` writes the clipboard's text. `Control-C` stops. Escape goes to the Escape ladder. Every other key, the arrow keys included, is ignored. `Run.write` writes all bytes in order and holds what the terminal cannot take yet. Hitoiki draws nothing typed. The transcript shows only what the child sends back, so a password prompt that turns off echo shows no password.
8. **Stop.** Stop, `Control-C` and Escape stop a running command. The first stop sends `SIGINT` to the child's process group. Each later Stop or `Control-C` sends `SIGKILL`. After the first stop, Panel draws no more output but still takes it, so Done arrives. Escape on a stopped command clears the panel and kills the group. A click outside the panel never hides a running command.
9. **Exit.** A dispatch process source reports the child's exit, and Run reaps it with `waitpid`. Run reports `.done` only when three things are true: the child is reaped, the pseudoterminal has reached end of output and is closed, and Panel has taken every piece. Run then checks the retry rule (below).
10. **Done.** The strip shows `exit <status>` or `signal <number>`. Any result other than `exit 0` shows in the alarm colour. Open in Terminal appears. It opens a new window of the chosen terminal at the directory the command ran in. It never runs the command again.
11. **After.** Escape takes one layer at a time: it closes an open recall list; it clears a result or typed text and leaves the panel on screen; on a clean panel it hides the panel. A click outside hides the panel and keeps everything on it for the next shortcut. The grey command stays in the input through Running and Done, and through hiding and showing. Escape's clear removes it, and the next command's Running replaces it. Return on an empty input never runs it; it runs only a `-tt` offer (below).

**Quit.** `Command-Q`, or Quit in the menu bar item. If a command runs, Hitoiki sends `SIGKILL` to its process group and waits up to one second for Done, then quits.

**The `-tt` retry rule.** Run never changes a command, with one exception. `Retry.swift` offers a retry only when all four of these are true:

1. The exit is not `exit 0`.
2. The output contained `sudo: a terminal is required to read the password`. The scan finds it across piece boundaries.
3. The command, after leading whitespace, starts with `ssh ` (four bytes).
4. No word after `ssh` already asks for a terminal. A word asks for a terminal when it starts with `-` and its letters, up to the first character that is not a letter, include `t`.

The offer is the command with `-tt ` inserted after the leading `ssh `. The rest stays byte for byte. The strip shows `Return or Retry runs <offer>`. Return on an empty input, or the Retry button, runs it.

## The update check

`Sources/Hitoiki/UpdateCheck.swift` is the app's only network request.

**What is sent.** One HTTPS GET, with no body and no query:

```
GET https://api.github.com/repos/sageframe-no-kaji/hitoiki/releases/latest
User-Agent: Hitoiki/<version>
Accept: application/vnd.github+json
Accept-Language: (set to an empty value)
```

`<version>` is the app's version from its `Info.plist`, for example `Hitoiki/1.0.0`. The code sets these headers and no others. The networking library fills `Accept-Language` from the user's language list unless the request sets it, so the code sets it to an empty value. The request goes through an ephemeral session that keeps no cookies, sends no cookies and caches no reply. The session's request timeout is eight seconds. Nothing about the user, the Mac or any command is sent. GitHub sees the request's network address.

**When it is sent.**

- At launch, if the switch "Check for updates automatically" is on. The switch is on when its key is absent.
- Every 24 hours after launch while Hitoiki runs. At each of these times the check reads the switch again and sends nothing if it is off.
- When the user chooses Check for Updates, in the settings footer or in the menu bar item. This check runs whatever the switch says. One manual check runs at a time.

A bare executable from `swift build` has no `Info.plist` and so no version. It never sends the request. Its manual check answers "Couldn't check for updates."

**What is done with the reply.** The check reads one field, `tag_name`. No reply, a status outside 200–299, or a body without that field is a failure. A tag is newer when, after an optional leading `v`, it is one to three whole numbers joined by dots and is greater number by number than the running version; a missing number counts as 0. Any other tag is never newer. A newer release shows the update line under the input, "Hitoiki <version> is available". A click on it opens `https://hitoiki.sageframe.net`. The update line changes nothing else on the panel and does not touch a running command.

A manual check also answers under the switch: "Hitoiki is up to date.", "Hitoiki <version> is available." (a link to the site), or "Couldn't check for updates." with a link to the site. The answer goes when the settings window closes. A reply that arrives after its window closed is not shown. An automatic check that fails shows nothing.

The last-checked time and the newest release found stay in memory. Nothing about the check is written to disk.

## About and Open at Login

**About.** `Sources/Hitoiki/AboutWindow.swift`. About Hitoiki in the settings footer, or in the menu bar item, opens it. It shows the app icon, the name, the version ("Development build" when there is none), the maker's line, three links (Website, GitHub, Support), a note on the update check, and OK. OK, Return, Escape and the close button hide the window. The next About Hitoiki shows the same window. The window sends nothing; a link opens in the browser when clicked.

**Open at Login.** `Sources/Hitoiki/LoginItem.swift`. The switch in settings is off by default. It registers or unregisters the app with macOS's login-item service, `SMAppService.mainApp`. macOS keeps the state, so Hitoiki writes no user-defaults key for it. Hitoiki reads the state again each time settings is shown, so a change made in System Settings › General › Login Items shows in the switch. If macOS waits for the user's approval, the switch is on and a line under it says where to approve. If macOS refuses, the line gives macOS's reason. A bare executable from `swift build` has no bundle identifier, so there the switch is off and disabled.

## Build and release

`scripts/build_macos.sh` builds the app. `RELEASING.md` gives the full release sequence, the verification list and the signing rules.

| Form | Result |
|---|---|
| `./scripts/build_macos.sh` | A universal (arm64 and x86_64) `dist/Hitoiki.app` |
| `ARCH_FLAGS="" ./scripts/build_macos.sh` | A native-only app, a quick local build |
| `./scripts/build_macos.sh --dmg` | The app and `dist/hitoiki-<version>.dmg`, notarised when the signing values are set |
| `./scripts/build_macos.sh --clean` | Deletes `dist/` only |

`VERSION` sets the version and defaults to `1.0.0`. The script:

1. Builds with `swift build -c release`. For the universal app it builds each architecture and joins them with `lipo`.
2. Assembles `dist/Hitoiki.app`: the program, the resource bundle `Hitoiki_Hitoiki.bundle` in `Contents/Resources`, `hitoiki.icns` made from `packaging/hitoiki.png`, and an `Info.plist` with the bundle identifier `com.sageframe.hitoiki`, `LSUIElement` (no Dock icon) and a minimum of macOS 14.0.
3. Signs the program, then the bundle, with the hardened runtime and the empty entitlements in `scripts/entitlements.plist`. It never uses `--deep`.
4. With `--dmg`: notarises and staples the app, builds the disk image from the stapled app with `hdiutil create`, signs the disk image, then notarises and staples it. Signing needs `CODESIGN_IDENTITY`; notarisation needs `NOTARIZE_KEYCHAIN_PROFILE` as well.

The two signing values, `CODESIGN_IDENTITY` and `NOTARIZE_KEYCHAIN_PROFILE`, come from `scripts/.env`. Git ignores that file; `scripts/.env.example` shows its form. The script reads only those two keys and does not run the file. A value already set in the environment wins. Without the values, the app is signed ad hoc for local use, and Gatekeeper on another Mac refuses it.

A release is published as GitHub's normal Latest release, with a tag `v` followed by one to three whole numbers joined by dots. A prerelease, or a tag the check cannot read, such as `v1.1-beta`, gives users no update line.

## How the tests run

There are two test targets: `Tests/HitoikiCoreTests` and `Tests/HitoikiTests`. The Panel tests open real windows and make them key. So the tests run in a macOS guest machine under Tart, where the windows open on the guest's screen.

`scripts/vm-test.sh` runs them. It takes no arguments. It:

1. Finds the Tart guest `hitoiki-test` (set `HITOIKI_VM` to change it), which must be stopped, and starts it without a window.
2. Waits up to two minutes for SSH, as user `admin` (set `HITOIKI_VM_USER` to change it), by key only.
3. Copies the working tree in with `rsync`, without `.build`, `.swiftpm`, `.git` and `spike/captures`.
4. Runs six commands in the guest, each in its own SSH session:
   - `swift-format lint --recursive --strict Sources Tests`
   - `swiftlint lint --strict`
   - `swift build`
   - `swift test`
   - `swift test --enable-code-coverage && scripts/coverage-floor.sh`
   - `swift build -c release`
5. Counts a test step as passed only when every test target in `Package.swift` reports a passing run. `swift test` can exit 0 when the test process ends early, so its exit status alone is not enough.
6. Shuts the guest down from inside, then runs `tart stop`, on every exit path.
7. Saves the output to `.build/vm-test/<UTC time>.log` and exits 0 only when all six commands pass.

The comment at the top of the script records how the guest was made.

**The coverage floor.** `scripts/coverage-floor.sh` reads the coverage data from `swift test --enable-code-coverage`. It checks two sets, each against a floor of 90% line coverage (the first argument changes the floor):

- `HitoikiCore`, all of it.
- `Sources/Hitoiki`, without nine files that cannot be driven without a screen and a user: `App.swift`, `PanelWindow.swift`, `TranscriptView.swift`, `SettingsWindow.swift`, `SettingsView.swift`, `TerminalPopUp.swift`, `WindowCloseWatch.swift`, `ShortcutRecorder.swift` and `AboutWindow.swift`. The script gives the reason for each.

The script fails if either set is under the floor or if it measures no files.

The pre-commit hooks in `.pre-commit-config.yaml` run `swift-format`, SwiftLint and `swift build` before each commit, with general checks that include a private-key scan.

## Known limits

- **Two update checks answered out of order.** If two checks are in flight and a release is published between them, the later reply can be for the older of two new releases. The update line then names that older release until the next check. The line still opens the site, which shows the newest release.
- **Temporary folders after a failed build.** If `build_macos.sh` fails or is stopped, it leaves its `mktemp` folders in the system's temporary directory. macOS clears them.
- **`hdiutil create`.** The build script makes the disk image with `hdiutil create`, which prints a deprecation warning. It stays until it stops working.
- **One unbroken line over 1 MiB.** A line that grows past 1 MiB without a line feed streams slowly while it runs, because the view lays out the whole long line again for each piece. Lines that end stream at full speed. The transcript keeps the last 1 MiB of such a line.
- **The `-tt` retry runs the whole command again.** The offer assumes that sudo refused before anything else in the remote command ran. That is not always true. With `ssh server 'echo x >> log; sudo true'`, the write happens before sudo refuses, and the retry writes again. The offer shows the full command before it runs. This is an open issue: whether the offer should say so, or the rule should change.
