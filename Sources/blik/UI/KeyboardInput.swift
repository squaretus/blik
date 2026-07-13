import BlikCore
import Foundation

enum KeyEvent {
    case up
    case down
    case pageUp
    case pageDown
    case preset(Int)   // 0, 25, 50, 75, 100
    case quit          // 'q' or 'Q'
    case none
}

enum KeyboardInput {
    static func readKey() -> KeyEvent {
        var buf = [UInt8](repeating: 0, count: Constants.inputBufferSize)
        let n = read(STDIN_FILENO, &buf, Constants.inputBufferSize)

        guard n > 0 else { return .none }

        if n > Constants.inputFloodThreshold { return .none }

        // Escape sequences
        if buf[0] == 0x1B {
            guard n >= 3 && buf[1] == 0x5B else { return .none }
            switch buf[2] {
            case 0x41: return .up        // ESC[A
            case 0x42: return .down      // ESC[B
            case 0x35: // ESC[5~ = Page Up
                if n >= 4 && buf[3] == 0x7E { return .pageUp }
                return .none
            case 0x36: // ESC[6~ = Page Down
                if n >= 4 && buf[3] == 0x7E { return .pageDown }
                return .none
            default: return .none
            }
        }

        // Single-byte keys
        switch buf[0] {
        case 0x31: return .preset(0)     // '1' = 0% (Авто)
        case 0x32: return .preset(25)    // '2' = 25%
        case 0x33: return .preset(50)    // '3' = 50%
        case 0x34: return .preset(75)    // '4' = 75%
        case 0x35: return .preset(100)   // '5' = 100%
        case 0x71, 0x51: return .quit    // q, Q
        default: return .none
        }
    }
}
