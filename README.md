# Issoku 一息

*Run one shell command from a floating panel. Read the result. Dismiss it.*

*Runs local commands and `ssh` commands with your existing SSH keys, config, and agent. Remote `sudo` prompts work.*

> Issoku is a macOS utility that runs a single shell command without opening a terminal. Press a global shortcut, type a command, press Return. Output appears under the input as it arrives. When the command exits, press Escape or click away and the panel is gone. Commands run in your own shell with your own environment, so `ssh` uses your existing config, keys, and agent. Remote `sudo` works, including the password prompt. Nothing runs in the background after the panel closes.

**Status:** In design as of October 2026. The architecture is committed. No code yet. The build begins with a working experiment on the process model, then the panel.

## What Issoku does

- **Global shortcut.** Default `Control-Command-Space`, configurable. The panel appears over whatever you are doing and takes keyboard focus.
- **One command.** Type a line, press Return. The line runs in your shell, non-interactively, with the environment your login shell would have. Local commands and complete `ssh` commands both work.
- **Live output.** Output streams into the panel as the process writes it. Exit status is shown when the process ends. Non-zero exits are marked.
- **Interactive input while running.** Keystrokes go to the running process. When remote `sudo` asks for a password, type or paste it. Issoku never echoes what you type; what appears is only what the process sends back. sudo does not echo passwords, so they do not appear anywhere.
- **Retry with a terminal.** If a remote `sudo` fails because it has no terminal, Issoku offers a one-key retry that reruns the same `ssh` line with `-tt`. That is the only change it ever makes to a command, and only when you accept.
- **Stop.** While a command runs, Escape and clicking away do nothing. Stop or `Control-C` interrupts the process and everything it started. A second Stop kills it.
- **Copy.** Select text and press `Command-C`, or press `Command-C` with nothing selected to copy the whole transcript. A Copy button does the same.
- **Open in Terminal.** When a command has finished, a button opens a terminal at the same working directory. Terminal.app by default; settings can select another installed terminal.
- **Macros.** Nine slots, `Command-1` through `Command-9`. Each holds a command and an optional name. Pressing the key loads the command into the input. Nothing runs until you press Return, so a macro can be a host prefix or a path you finish typing.
- **History.** Off by default. When on, previous commands are recalled in the input and the history is a plain text file you can read, search, or delete. A Clear button deletes it.
- **Working directory.** Home by default. Settings can change it to the last directory used or a fixed path.
- **Updates.** An optional check against GitHub Releases, on by default, with a manual Check for Updates. No other network traffic originates from the app.

## Using it

1. Press `Control-Command-Space`.
2. Type `ssh koan 'sudo systemctl restart caddy'` and press Return.
3. sudo asks for a password. Type it. It does not appear.
4. The command finishes. Read the output.
5. Press Escape.

For a local command, steps 3 and 4 are shorter: `df -h`, read, Escape.

## What Issoku is not

- Not a terminal emulator. Full-screen programs such as vim, htop, and tmux do not belong in the panel. Use Open in Terminal.
- Not a terminal multiplexer or session manager. Nothing persists after the panel closes.
- Not an SSH client or connection manager. It runs `/usr/bin/ssh` with your configuration and stores no hosts or credentials.
- Not a command library, launcher, or plugin platform.
- Not a server dashboard, log viewer, or AI assistant.
- Not a replacement for your terminal. It exists for the commands that do not need one.

## Naming

一息 (*issoku*) is Japanese for one breath. One command, one result, done.

## Architecture

| Part | Does |
|---|---|
| Panel | The floating window, the global shortcut, focus, the running and done states, dismissal |
| Run | One command's life: a pseudoterminal, one child process in its own process group, streaming output, forwarding keystrokes, interrupt, kill, exit status |
| Transcript | Rendering output as it arrives with colour and carriage-return handling, selection, copy, a fixed memory ceiling |
| Memory | Settings and macros in user defaults, history in a text file |

Run is the only part that touches processes. It captures your login shell's environment once when the app starts and uses it for every command.

## Tech stack

Swift 6 with strict concurrency. AppKit for the panel and the global shortcut. SwiftUI inside AppKit for settings. POSIX for the pseudoterminal and process control. `/usr/bin/ssh` for SSH. Built with Swift Package Manager; the app bundle is assembled by script, no Xcode project. No third-party dependencies.

## Current state

| | |
|---|---|
| Now | System design complete. Project scaffold next. |
| Next | A throwaway experiment proving the pseudoterminal process model: remote sudo with a password, interrupt and kill without orphans, bounded memory on large output, minimal terminal-control handling against real commands. Then Run, Panel, Transcript, Memory, in that order. |
| Later | Signed and notarised release on GitHub Releases and Payhip. Icon. |

## Installation

*Not yet. A signed and notarised `.dmg` will appear on the releases page when the first version ships.*

The built app will be available on Payhip for about three dollars. The purchase unlocks nothing; it is a way to pay for the work. Building from source is free at every version.

## Requirements

- macOS 14 or later.
- OpenSSH as shipped with macOS. Issoku uses your `~/.ssh/config`, keys, and agent as they are.

Repeated commands to the same host are faster with `ControlMaster` and `ControlPersist` in your SSH config, which reuse one connection instead of opening a new one each time. This is an SSH setting, not an Issoku one.

## Development

*Build instructions appear here with the first code.* The project builds with `swift build` and tests with `swift test`. Formatting is swift-format, linting is SwiftLint, both run as pre-commit hooks.

## Privacy

No telemetry, analytics, accounts, or command reporting. The optional update check requests the latest release from GitHub and sends no command text, hostnames, or identifiers. Commands you run may use the network on their own.

## License

MIT. The full source is public. Anyone can inspect, modify, fork, and compile it.

---

Andrew Todd Marcus — [atmarcus.net](https://atmarcus.net) · [sageframe.net](https://sageframe.net). Developed using the [Ho System](https://github.com/sageframe-no-kaji/ho-system). Last meaningful update: 2026-10-24.
