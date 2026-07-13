import Foundation
import Darwin

/// Управление LaunchAgent пользователя (`com.blik.app`).
/// plist ставится PKG'ом в `/Library/LaunchAgents/com.blik.app.plist`,
/// загружается/выгружается через `launchctl` в user-домене (без sudo).
public enum LaunchAgentController {
    public static let plistPath = "/Library/LaunchAgents/com.blik.app.plist"
    public static let serviceName = "com.blik.app"

    /// true, если plist установлен в системе (PKG прогнан).
    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// true, если агент сейчас загружен в текущий user-домен.
    public static var isEnabled: Bool {
        guard isInstalled else { return false }
        return runLaunchctl(args: ["print", "gui/\(currentUID)/\(serviceName)"])
    }

    @discardableResult
    public static func enable() -> Bool {
        guard isInstalled else { return false }
        return runLaunchctl(args: ["bootstrap", "gui/\(currentUID)", plistPath])
    }

    @discardableResult
    public static func disable() -> Bool {
        runLaunchctl(args: ["bootout", "gui/\(currentUID)/\(serviceName)"])
    }

    // MARK: - Private

    private static var currentUID: uid_t { getuid() }

    private static func runLaunchctl(args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
