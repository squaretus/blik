import BlikCore
import Foundation

class Terminal {
    private var originalTermios: termios?

    /// Terminal size (columns, rows).
    var size: (cols: Int, rows: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (Constants.defaultTerminalCols, Constants.defaultTerminalRows)
    }

    func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        raw.c_lflag &= ~(UInt(ICANON) | UInt(ECHO) | UInt(ISIG))

        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let cc = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 1
        }

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        // Explicitly disable all mouse reporting to prevent scroll interference
        write("\u{1B}[?1000l")
        write("\u{1B}[?1002l")
        write("\u{1B}[?1003l")
        write("\u{1B}[?1006l")
    }

    func disableRawMode() {
        if var original = originalTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            originalTermios = nil
        }
    }

    func hideCursor() {
        write("\u{1B}[?25l")
    }

    func showCursor() {
        write("\u{1B}[?25h")
    }

    func enterAltScreen() {
        write("\u{1B}[?1049h")
    }

    func leaveAltScreen() {
        write("\u{1B}[?1049l")
    }

    func clearScreen() {
        write("\u{1B}[2J\u{1B}[H")
    }

    func moveTo(row: Int, col: Int) {
        write("\u{1B}[\(row);\(col)H")
    }

    func clearToEndOfLine() {
        write("\u{1B}[K")
    }

    func beginSyncUpdate() {
        write("\u{1B}[?2026h")
    }

    func endSyncUpdate() {
        write("\u{1B}[?2026l")
    }

    func write(_ text: String) {
        print(text, terminator: "")
        fflush(stdout)
    }

    deinit {
        disableRawMode()
        showCursor()
    }
}
