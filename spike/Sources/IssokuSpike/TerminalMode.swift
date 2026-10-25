import Darwin

/// The harness's own stdin when it is a terminal (ho-01 Decision 4).
///
/// Raw mode with local echo off for the life of the child: `cfmakeraw`, then ISIG back on so
/// Control-C reaches the harness as SIGINT rather than as a 0x03 byte, and output processing
/// back on so the harness's own LF still returns the carriage. Restored on every exit path.
struct TerminalMode {
    private let saved: termios?

    /// Saves the state of fd 0 if it is a terminal; otherwise does nothing.
    init() {
        var state = termios()
        saved = isatty(0) == 1 && tcgetattr(0, &state) == 0 ? state : nil
    }

    /// Whether fd 0 is a terminal, and therefore whether anything is read from it.
    var isTerminal: Bool { saved != nil }

    /// Switches fd 0 to raw mode with echo off.
    func enterRaw() {
        guard var raw = saved else { return }
        cfmakeraw(&raw)
        raw.c_lflag |= tcflag_t(ISIG)
        raw.c_oflag |= tcflag_t(OPOST | ONLCR)
        tcsetattr(0, TCSAFLUSH, &raw)
    }

    /// Puts fd 0 back as it was.
    func restore() {
        guard var state = saved else { return }
        tcsetattr(0, TCSAFLUSH, &state)
    }
}
