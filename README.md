# Issoku 一息

Issoku is a macOS utility for running a shell command from a floating panel. It runs short local commands and remote commands through `/usr/bin/ssh`, using your existing SSH configuration. The name, 一息 (*issoku*), means “one breath” in Japanese.

## Using Issoku

Press `Control-Command-Space` to open the panel, type a command, and press Return. Output appears below the input as the command runs, followed by its exit status. When it finishes, press Escape or click outside to dismiss the panel.

The shortcut is configurable in settings. Its default conflicts with macOS's Character Viewer shortcut, and Issoku reports when the key combination is unavailable. Settings also control the working directory: home, the last directory used, or a fixed path.

- Commands run one at a time in your shell, with the environment captured from your login shell when Issoku starts. Use Refresh Environment in settings to capture it again. Commands run non-interactively, so interactive aliases and functions are not available.
- Output supports color and carriage-return updates, with a bounded buffer. `Command-C` copies the selection, or the retained output when nothing is selected. A Copy button provides the same actions.
- While a command runs, keystrokes go to its pseudoterminal (PTY), the operating-system interface that gives a process terminal input and output. Password entry uses the running program's terminal echo settings.
- Stop or `Control-C` sends `SIGINT` to the local process group; a second Stop sends `SIGKILL`. Escape and clicking outside are inactive while a command runs.
- Open in Terminal opens a terminal at the command's working directory after completion. Terminal.app is the default; settings can select another installed terminal.
- Nine macros, `Command-1` through `Command-9`, load saved command text into the input for editing and execution. History is optional, off by default, and stored in a text file that can be cleared from settings.

## Commands

```sh
uptime
df -h
ssh server 'uptime'
ssh -tt server 'sudo true'
```

If remote sudo reports that it needs a terminal, Issoku offers to rerun the SSH command with `-tt`, which requests a remote terminal. You can also type `-tt` yourself, as in the example above. SSH configuration, keys, and agents are managed through the installed OpenSSH client.

The output model handles text, color, and carriage returns. Use a terminal for full-screen applications such as Vim, htop, and tmux, or for persistent shell sessions. Interrupting the local SSH process can leave a remote command running when SSH has not allocated a remote terminal.

## Architecture

Issoku has four components:

| Component | Responsibility |
|---|---|
| Panel | Window, shortcut, focus, run state, and dismissal |
| Run | PTY, child process, process group, captured environment, input, output, and exit status |
| Transcript | Text rendering, retained-output limit, selection, and copying |
| Memory | Settings, macros, and optional command history |

Issoku uses Swift 6 with strict concurrency. AppKit provides the panel and shortcut handling, with SwiftUI for settings; process execution uses POSIX facilities and `/usr/bin/ssh`. Swift Package Manager builds the project, and the package has no third-party dependencies.

## Installation

Issoku requires macOS 14 or later. The app is distributed as a signed and notarized `.dmg` through GitHub Releases and Payhip, with the Payhip download priced at about $3. Open the disk image, drag Issoku to Applications, and launch it.

## Development

Building from source requires Swift 6 on macOS. Formatting uses swift-format, linting uses SwiftLint, and pre-commit runs the configured checks. `IssokuCore`, the headless library, has a configured line-coverage floor of 90%.

```sh
swift build
swift test
swift test --enable-code-coverage
scripts/coverage-floor.sh
```

## Privacy

An optional update check reads the latest release information from GitHub. It is enabled by default and can be disabled in settings; Check for Updates runs it manually. Issoku does not collect telemetry or require an account, and transcripts stay in memory. Commands you run can make their own network requests.

## License

[MIT](LICENSE).

---

Andrew Todd Marcus — [atmarcus.net](https://atmarcus.net) · [sageframe.net](https://sageframe.net). Developed using the [Ho System](https://github.com/sageframe-no-kaji/ho-system). Last meaningful update: 2026-10-25.
