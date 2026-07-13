import Foundation

/// Signal handler using only async-signal-safe operations.
/// Sets a volatile flag; the main run loop checks it and performs cleanup.
enum SignalHandler {
    nonisolated(unsafe) static var shouldTerminate = false

    static func install() {
        signal(SIGINT) { _ in
            SignalHandler.shouldTerminate = true
        }
        signal(SIGTERM) { _ in
            SignalHandler.shouldTerminate = true
        }
    }
}
