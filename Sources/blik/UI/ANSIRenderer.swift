import Foundation

enum ANSIColor: String {
    case reset = "\u{1B}[0m"
    case bold = "\u{1B}[1m"
    case dim = "\u{1B}[2m"
    case red = "\u{1B}[31m"
    case green = "\u{1B}[32m"
    case yellow = "\u{1B}[33m"
    case blue = "\u{1B}[34m"
    case magenta = "\u{1B}[35m"
    case cyan = "\u{1B}[36m"
    case white = "\u{1B}[37m"
    case gray = "\u{1B}[90m"
    case brightGreen = "\u{1B}[92m"
    case brightYellow = "\u{1B}[93m"
    case brightRed = "\u{1B}[91m"
    case bgBlue = "\u{1B}[44m"
    case bgGray = "\u{1B}[100m"
}

enum ANSIRenderer {
    static func color(_ text: String, _ colors: ANSIColor...) -> String {
        let prefix = colors.map(\.rawValue).joined()
        return "\(prefix)\(text)\(ANSIColor.reset.rawValue)"
    }

    static func progressBar(value: Double, max: Double, width: Int = 12, filledColor: ANSIColor = .green) -> String {
        guard max > 0 else { return String(repeating: "\u{2591}", count: width) }
        let ratio = min(1.0, Swift.max(0.0, value / max))
        let filled = Int(ratio * Double(width))
        let empty = width - filled

        let filledStr = String(repeating: "\u{2588}", count: filled)
        let emptyStr = String(repeating: "\u{2591}", count: empty)

        return color(filledStr, filledColor) + color(emptyStr, .gray)
    }

    /// Get color based on temperature value.
    static func temperatureColor(_ temp: Double) -> ANSIColor {
        switch temp {
        case ..<40: return .green
        case 40..<60: return .brightGreen
        case 60..<75: return .yellow
        case 75..<85: return .brightYellow
        case 85..<95: return .brightRed
        default: return .red
        }
    }

    /// Get color based on fan speed percentage.
    static func fanSpeedColor(actual: Double, max: Double) -> ANSIColor {
        guard max > 0 else { return .gray }
        let ratio = actual / max
        switch ratio {
        case ..<0.3: return .green
        case 0.3..<0.5: return .brightGreen
        case 0.5..<0.7: return .yellow
        case 0.7..<0.85: return .brightYellow
        default: return .brightRed
        }
    }

    // Box drawing characters
    static let topLeft = "\u{250C}"
    static let topRight = "\u{2510}"
    static let bottomLeft = "\u{2514}"
    static let bottomRight = "\u{2518}"
    static let horizontal = "\u{2500}"
    static let vertical = "\u{2502}"
}
