import Foundation

enum Logger {
    private static var fileHandle: FileHandle?
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func setup(directory: String) {
        lock.lock()
        defer { lock.unlock() }
        let path = (directory as NSString).appendingPathComponent("blik.log")
        FileManager.default.createFile(atPath: path, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: path)
        fileHandle?.seekToEndOfFile()
        writeUnsafe("=== .blik запущен ===")
    }

    static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        writeUnsafe(message)
    }

    static func close() {
        lock.lock()
        defer { lock.unlock() }
        writeUnsafe("=== .blik завершён ===")
        fileHandle?.closeFile()
        fileHandle = nil
    }

    /// Write without acquiring the lock — caller must hold it.
    private static func writeUnsafe(_ message: String) {
        guard let fh = fileHandle else { return }
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            fh.write(data)
            fh.synchronizeFile()
        }
    }
}
