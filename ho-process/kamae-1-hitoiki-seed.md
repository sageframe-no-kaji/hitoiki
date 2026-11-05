# Issoku (一息) — Project Seed

**Ho Kamae 1 — Seed Collaborator**
**October 24, 2026**
**Decision: Proceed**
**Canonical filename:** `ho-process/kamae-1-issoku-seed.md`

## 1. The Problem

I am constantly opening a terminal to run one command.

Usually I don't need a terminal session. I don't need to manage a window, navigate a shell, or keep anything running.

I need to execute something, see the result, and go back to what I was doing.

Opening Ghostty isn't difficult. But I shouldn't have to open and close a terminal window for something that takes five seconds.

Most of these commands are remote. I have roughly twelve machines, and probably 75% of my one-off commands run over SSH.

I already have SSH keys, aliases, and a working environment. I don't want another application managing any of that.

I want something like Spotlight, except it executes a shell command and shows me the answer.

That's it.

## 2. The Landscape

The idea is not new.

Research conducted October 24, 2026 identified several standalone applications, command palettes, and floating terminals that address parts of this problem.

The distinction between documented features and demonstrated functionality matters. A published repository doesn't necessarily establish that an application is mature, dependable, or even readily installable.

### Mini-Terminal

https://github.com/uniplanck/Mini-Terminal

An unusually close match to the original concept.

Native Swift, global shortcut, freeform command input, output display, history, and clipboard integration.

But the repository was created October 7, 2026, with one initial commit, no GitHub Releases, no recorded GitHub Actions runs, and no declared license at the time of investigation.

Its shell runner uses standard output pipes, reads stdout and stderr to completion, and provides no interactive input.

It cannot support the required remote `sudo` interaction in its current form.

It is a relevant prototype, not an established solution that I can confidently adopt.

### QuickTerm

https://github.com/AlexGustafsson/quickterm

A 2020-era Swift implementation with Spotlight-like command entry and small output windows.

MIT licensed.

Its architecture includes multiple application components and an XPC broker. The examined execution paths use ordinary process pipes rather than interactive terminal input.

Last repository push: July 2021.

This is substantial prior art, but reviving it would mean taking ownership of an aging implementation whose architecture exceeds Issoku's needs.

### QuickCMD

https://www.quickcmd.app/

A small native command runner with saved commands and output.

QuickCMD explicitly directs users to Terminal.app for commands requiring interactive SSH or password prompts.

That leaves the central problem unsolved.

### SpotTerminal

https://github.com/MorCherlf/SpotTerminal

The strongest technical precedent.

Its implementation uses a pseudoterminal and supports interactive input in a floating command panel.

That is important evidence that the desired interaction can be built with native macOS facilities.

However, SpotTerminal is also a full terminal application with tabs, sessions, background tasks, and other functionality.

The examined quick-panel implementation accepts interactive text through a normal text field. Secure handling of password prompts is not established by that design alone.

SpotTerminal is worth studying selectively, not adopting wholesale.

### Pounce / Hausfold

https://github.com/hausfold/pounce
https://github.com/hausfold

Pounce is a native macOS command palette organized around applications, registered commands, and executable scripts.

It isn't a freeform one-off shell command runner.

Its central abstraction—every custom command is a file—is coherent, but it solves a different problem.

The wider Hausfold ecosystem is far larger than Issoku's intended scope.

Pounce is also a useful precedent for developer-facing documentation and native release distribution. Its quality should be evaluated through code and testing, not its appearance or the degree of AI assistance.

### Other alternatives

ConsoleLauncher supports arbitrary shell passthrough but includes a much larger launcher feature set and uses pipe-based command execution.

Relay is a command library and workflow system.

SpotTerm is a floating interactive terminal built with SwiftTerm.

Alfred's Run Command workflow approaches the original interaction, but requires the Alfred ecosystem and paid Powerpack.

Raycast likewise makes command execution part of a much larger launcher.

Scuttlarr is broader still and can delegate commands to Ghostty.

### Alternatives considered

Three possible approaches emerged:

**Adopt an existing application.** Rejected because no investigated candidate was verified to provide the complete small, SSH-oriented interaction.

**Revive or fork an existing implementation.** Possible, but the strongest candidates either lack an appropriate license, have unnecessary architecture, or require replacing their process-execution model.

**Build a narrowly scoped native utility.** Preferred because the desired behavior is specific and there is a credible way to keep the implementation small.

### Conclusion from the landscape

Small graphical shell-command runners already exist.

What has not been found in a verified, appropriately minimal implementation is the combination of:

- Freeform command entry.
- Inline output.
- Existing SSH configuration and keys.
- Interactive remote `sudo`.
- No separate terminal window.
- No session management.
- A single-command lifecycle.

This is sufficient differentiation to justify a small personal and open-source utility.

It is not a claim of broad novelty or guaranteed commercial demand.

## 3. The Vision

**Issoku is a temporary interface to the shell.**

Press `Control-Command-Space`.

A small input bar appears.

Type a command.

Press Return.

Output appears beneath the input as the command executes.

When the command finishes, read or copy the result. Press Escape or click outside to dismiss the panel.

The application disappears, and I'm back where I started.

The terminal was never opened.

The name captures that interaction: Issoku, 一息, one breath.

One command. One result. Done.

## 4. Audience

First, me.

I have multiple local and remote machines, know the commands I want to execute, and regularly need to run them while doing something else.

The broader audience is macOS users who are comfortable with the command line and frequently run short local or SSH commands.

Issoku is not intended to teach shell commands, manage servers, configure SSH, or provide a beginner-friendly abstraction over command-line tools.

It assumes the user knows what they are executing.

## 5. Identity

**Issoku — 一息**

The interface should be quiet, immediate, and almost invisible.

The icon is a black rounded square dominated by a large pixel-rendered `息` character in monochrome terminal green.

It should feel like an early monochrome display rather than a contemporary illustration of a terminal.

No glow, gradients, decorative terminal frames, or unnecessary graphic elements.

The character should remain legible at normal macOS icon sizes.

The command panel should be similarly restrained: minimal chrome, readable monospaced text, compact controls, and a natural expansion for output.

## 6. Project Nature and Intent

Issoku is a small native macOS utility.

It will be open source under the MIT license.

The entire source is public. Anyone can inspect, modify, fork, and compile it for free.

A signed and notarized compiled application will be available through Payhip for approximately $3.

That purchase is a convenience and a way to support the work. It doesn't unlock functionality.

No activation, subscription, account, licensing server, or proprietary premium edition.

A free Mac App Store release may be considered, but only if sandboxing doesn't compromise the application. App Store distribution is optional, not a requirement.

### Privacy

Issoku has no telemetry, analytics, user account, or command-reporting service.

The only application-initiated network communication is an optional update check against GitHub Releases.

Automatic update checks are enabled by default, clearly disclosed, and can be disabled.

There is also a manual Check for Updates command.

The update request does not intentionally transmit command text, SSH hosts, usage data, or generated identifiers. Ordinary network metadata visible to GitHub remains outside Issoku's control.

Commands initiated by the user may independently access the network.

## 7. Architectural Direction

The application should use native macOS facilities.

**Language:** Swift.

**Interface:** AppKit for the floating window and global keyboard behavior, with SwiftUI where it genuinely simplifies the implementation.

**Command execution:** The user's existing shell and macOS process facilities.

**SSH:** The installed OpenSSH client, using existing keys, `~/.ssh/config`, host aliases, and the configured SSH agent.

No custom SSH library, connection manager, host inventory, or credential storage.

### The PTY question

A basic process runner with stdout and stderr pipes is not sufficient for the primary workflow.

Remote `sudo` may require interactive terminal behavior.

Issoku should investigate a pseudoterminal-backed execution path that allows normal SSH interaction without a visible terminal application.

The PTY must support:

- Displaying output as it arrives.
- Receiving interactive input.
- Respecting terminal echo suppression.
- Delivering cancellation signals.
- Reporting process completion.
- Handling failed connections and process exits predictably.

A full terminal emulator is not automatically required. Whether lightweight ANSI and terminal-control handling is sufficient must be established through implementation tests.

### Password entry

When a remote `sudo` command requests a password, the user must be able to type or paste it.

Password characters must not appear in the input field, transcript, history, or logs when terminal echo is disabled.

The interface must not use a normal visible command text field to buffer password input.

Input should be forwarded to the terminal process without recording it.

The implementation must correctly handle standard `sudo` echo-suppression behavior. It cannot assume arbitrary remote programs will protect secrets if those programs deliberately echo input.

SSH-key authentication remains the default for login. Issoku is not a password manager.

### Remote terminal allocation

Some remote `sudo` operations require `ssh -tt`.

Issoku should recognize simple SSH invocations containing remote `sudo` and, where safe, request a remote terminal automatically.

The transformation must be precise and testable.

Do not use naive text replacement against arbitrary shell commands.

When the invocation is too complicated to understand reliably, leave it unchanged and provide a clear way to retry with remote PTY allocation or type `ssh -tt` explicitly.

Do not require a machine selector.

The user types the complete SSH command, including its destination.

## 8. Constraints

The code needs to be **tight**.

Tighter than my recent projects.

That means using the simplest implementation that correctly handles the actual requirements, rather than building infrastructure for hypothetical future needs.

Avoid:

- Unnecessary dependencies.
- Generic service layers.
- Abstractions with one implementation.
- Premature plugin architecture.
- Multiple execution engines without a demonstrated need.
- Unnecessary configuration formats.
- State-management frameworks for a simple window.
- Duplicate representations of the same state.
- Large generated files that nobody has carefully reviewed.

The goal isn't the smallest possible line count. Compressed, clever code can be harder to understand and maintain.

The goal is a small amount of clear, well-structured code whose behavior is easy to inspect.

### Other constraints

The application must use very little CPU while idle.

Global invocation must be responsive.

Output must have a bounded memory footprint, even when a command produces a large amount of text.

The shortcut `Control-Command-Space` conflicts with macOS's default Character Viewer shortcut. Issoku should offer the desired default while clearly handling this conflict and allowing customization.

A GUI application's environment differs from the environment inside Ghostty. Shell initialization, Homebrew paths, working directory, and SSH agent access must be handled deliberately.

Signing and notarization are part of distribution, not an afterthought.

## 9. Scope Boundaries

### First version

**Invocation**

- Global keyboard shortcut, default `Control-Command-Space`.
- Small floating panel.
- Automatic keyboard focus.
- Configurable shortcut.

**Execution**

- Arbitrary one-line shell commands.
- Local commands and complete SSH commands.
- Existing SSH keys, aliases, and agent.
- Remote `sudo` interaction with no password echo.
- Live output, errors, and exit status.
- One command active at a time.

**Command lifecycle**

- While a command is running, Escape or clicking outside cannot dismiss the window.
- A visible Stop button and `Control-C` can interrupt execution.
- A force-termination option is available if graceful interruption fails.
- After completion, Escape or clicking outside dismisses the panel.
- No command continues as a managed background session after dismissal.

**Output**

- Readable, scrollable output.
- Standard text selection.
- `Command-C` copies a selection or the complete displayed transcript when nothing is selected.
- Visible mouse-accessible Copy control.
- Clear presentation of command failure and exit status.

**Convenience**

- Local command history.
- History recall and clearing.
- Nine configurable macros, accessible with `Command-1` through `Command-9`.
- Each macro holds a user-defined command and optional name.
- Simple settings interface.
- Optional GitHub update checks.

History stores command text, not interactive responses. Completed transcripts need not be permanently stored in the first version.

Because users can include secrets in command-line arguments, history must be optional or easily disabled, inspected, and cleared.

### Explicitly excluded

Issoku is not:

- A terminal emulator for general interactive work.
- A terminal multiplexer.
- An SSH connection manager.
- A server dashboard.
- A persistent session manager.
- A log-monitoring application.
- A command library or plugin platform.
- An AI assistant.
- A workflow orchestrator.
- A replacement for Ghostty.

Full-screen applications such as Vim, htop, or tmux are outside the intended interaction.

A future version could improve output inspection or add other small conveniences. These possibilities do not justify adding architecture to the MVP.

## 10. Success Criteria

The product succeeds when these behaviors can be demonstrated on actual machines.

**Ordinary local command:** Invoke Issoku, run `uptime`, read the response, and dismiss it without opening another application.

**Remote command:** Run `ssh butch 'uptime'` through the user's existing key-based authentication and inspect the result.

**Remote administration:** Run a remote command requiring `sudo`, enter or paste the password without echo, and complete the operation. Verify that the password does not appear in history, output, or diagnostic logs.

**Cancellation:** Run a command that takes time, confirm that the panel cannot be accidentally dismissed, interrupt it, and verify that the relevant process is terminated rather than silently left running.

**Output:** Run a command producing substantial stdout and stderr. Verify incremental display, reasonable memory behavior, copy functionality, and accurate exit status.

**Reliability:** Test missing hosts, unreachable hosts, rejected SSH authentication, incorrect sudo passwords, unexpected process exits, and commands that ignore interruption.

**Performance:** Measure actual shortcut responsiveness, startup behavior, idle memory, and CPU usage on supported Macs.

**Code quality:** The implementation remains understandable to its owner. Important choices can be explained, and the code has no large subsystem that exists without a clear requirement.

**Distribution:** The application can be built reproducibly, signed, notarized, installed, launched, updated, and removed without unnecessary manual intervention.

## 11. Where I'm Starting

I understand the workflow and have extensive experience with the shell, SSH, multiple machines, and developer tools.

I also bring substantial experience in design, interactive systems, and software development.

What I know less well is the native macOS infrastructure involved in building this kind of application: AppKit floating panels, process control, PTYs, terminal line discipline, and Swift concurrency around subprocesses.

These are areas I want to understand rather than hide behind generated code.

## 12. What I Want to Learn

I want to become more disciplined in how I develop software with AI.

The goal isn't simply to ship an application faster.

I want to write less unnecessary code, understand more of what exists, and maintain tighter control over changes.

The development process should make the code visible and comprehensible.

AI collaborators may propose, research, explain, implement, test, and critique.

But I control the architecture, language, feature decisions, dependencies, and acceptance of code.

Changes should be small enough to review meaningfully.

Every significant change should come with its diff, its purpose, and an explanation of non-obvious behavior.

No autonomous broad refactors, large opaque code dumps, unnecessary abstraction layers, or undocumented architectural changes.

No claims of correctness without corresponding evidence.

No tests whose only purpose is to validate assumptions made by the generated implementation.

The project should be an exercise in careful software authorship, not just software generation.

This is part of the reason to build it.

## 13. Open Questions

These questions remain for System Design and targeted technical experiments.

**PTY implementation:** Which native macOS process-launching approach provides the simplest reliable terminal behavior without introducing unsafe process-management assumptions?

**Terminal input:** What is the smallest correct approach to forwarding interactive input while respecting echo suppression?

**SSH transformation:** Under what narrowly defined conditions can Issoku safely arrange remote PTY allocation without rewriting arbitrary shell expressions?

**Terminal output:** How much terminal-control interpretation is required for readable output, and when would a dependency become justified?

**Environment:** How do we reproduce the important parts of the user's login-shell environment without excessive launch latency or surprising side effects?

**Process ownership:** How should cancellation handle subprocesses and process groups, particularly remote SSH commands?

**Distribution:** What differences would a sandboxed free Mac App Store version introduce, and are they acceptable?

These questions should be answered through small, measurable experiments, not speculative infrastructure.

## Seed Decision

**Proceed with Issoku.**

The landscape investigation establishes that the basic command-launcher idea is not original.

Mini-Terminal and QuickTerm are substantial precedents for the interface. QuickCMD addresses a similar convenience problem. SpotTerminal demonstrates useful PTY-related techniques.

But none of the examined solutions has been verified to combine the exact small, freeform interaction with reliable interactive remote administration and without the overhead of a larger terminal or launcher.

The personal need is frequent and concrete.

The likely application is small enough to justify developing as a focused native macOS utility, provided the PTY and authentication requirements can be implemented without turning it into a significantly larger program.

The next phase is System Design.

Its first task is to establish the minimal correct SSH/PTY process model through a working technical experiment. If that experiment exposes an unreasonable architectural cost, revise the approach before building a polished interface.

The decision to proceed is not a mandate to implement every imagined feature.

**Keep the interaction simple. Keep the code tight. Make the claims demonstrable.**

The application exists to eliminate an unnecessary terminal window.

Everything else should serve that purpose.

## Research References

- [Mini-Terminal](https://github.com/uniplanck/Mini-Terminal)
- [QuickTerm](https://github.com/AlexGustafsson/quickterm)
- [QuickCMD](https://www.quickcmd.app/)
- [SpotTerminal](https://github.com/MorCherlf/SpotTerminal)
- [Pounce](https://github.com/hausfold/pounce)
- [Hausfold](https://github.com/hausfold)
- [ConsoleLauncher](https://github.com/nickymitnick/ConsoleLauncher)
- [Relay](https://github.com/siveesh/Relay)
- [SpotTerm](https://github.com/mfajri11/spotterm)
- [Alfred Run Command](https://alfred.app/workflows/vitor/run-command/)

The assessment is based on published documentation, repository evidence, and selected source-code review through October 24, 2026. It does not claim that every candidate has been installed or comprehensively tested.
