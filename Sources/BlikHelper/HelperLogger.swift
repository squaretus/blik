import Foundation
import BlikCore

/// Thread-safe JSON-логгер для BlikHelper daemon.
/// Пишет одновременно в NSLog (syslog) и в файл `/Library/Logs/Blik/helper.log`
/// одной JSON-строкой на запись. Ротация при превышении 1 MB.
enum HelperLogger {
    private static let lock = NSLock()
    private static let logDir = "/Library/Logs/Blik"
    private static let logPath = "/Library/Logs/Blik/helper.log"
    private static let maxLogSize: UInt64 = 1_048_576 // 1 MB

    private static var fileHandle: FileHandle? = {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDir) {
            try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        return FileHandle(forWritingAtPath: logPath)
    }()

    /// Legacy API: однострочное сообщение → JSON с tag="helper", level=INFO.
    /// Существующие call-site'ы из HelperDelegate работают без изменений.
    static func log(_ message: String) {
        write(level: .info, tag: "helper", message: message, payload: [:])
    }

    /// Структурированное логирование с payload и явным уровнем.
    static func log(
        _ level: LogLevel,
        tag: String = "helper",
        message: String? = nil,
        data: [String: Any] = [:]
    ) {
        write(level: level, tag: tag, message: message, payload: data)
    }

    // MARK: - Internal

    private static func write(
        level: LogLevel,
        tag: String,
        message: String?,
        payload: [String: Any]
    ) {
        let line = JSONLogFormatter.format(
            level: level,
            tag: tag,
            message: message,
            payload: payload
        )

        // NSLog для syslog (читаемое представление — message либо короткий tag).
        if let message {
            NSLog("BlikHelper [%@]: %@", tag, message)
        } else {
            NSLog("BlikHelper [%@]", tag)
        }

        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded()
        if let data = line.data(using: .utf8) {
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(data)
        }
    }

    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }

        fileHandle?.closeFile()
        let oldPath = logPath + ".old"
        try? fm.removeItem(atPath: oldPath)
        try? fm.moveItem(atPath: logPath, toPath: oldPath)
        fm.createFile(atPath: logPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logPath)
    }
}
