import Foundation
import Darwin

/// Path-based whitelist для XPC-клиентов helper'а.
///
/// **Контекст:** проект не подписан Apple Developer ID, поэтому полноценная
/// проверка через `SecCodeCheckValidity` с requirement-строкой неприменима
/// (нечего проверять — нет team-id). До появления подписи используем
/// path-based проверку: резолвим PID клиента → путь к executable через
/// `proc_pidpath` → сравниваем с белым списком.
///
/// **Threat model:** отсекает неавторизованных user-mode клиентов, которые
/// могли бы вызвать `setFanSpeedPreset`, `performUpdate`, `uninstallAll`.
/// НЕ защищает от root-процессов: root может пересоздать любой бинарник по
/// whitelist-пути. Достаточно для текущей фазы — без root противник не
/// получит выгоды через XPC (только потеряет преимущество компрометации
/// сравнительно с прямым доступом к SMC).
///
/// Когда появится Apple Developer ID — заменить `isAuthorized(pid:)` на
/// `SecCodeCheckValidity` с requirement-string на team-id.
enum ClientAuthorization {

    /// Каноничные пути установленных бинарников (PKG installer кладёт их сюда).
    static let installedPaths: [String] = [
        "/Applications/Blik.app/Contents/MacOS/BlikApp",
        "/Applications/Blik.app/Contents/MacOS/BlikMenuBar",
        "/usr/local/bin/blik",
    ]

    /// Префиксы для DEBUG-сборок (когда `swift run` или `.build/debug/...`).
    /// Активны только если `#if DEBUG` — в release-PKG этого кода нет.
    static let debugPathSuffixes: [String] = [
        "/.build/debug/BlikApp",
        "/.build/debug/BlikMenuBar",
        "/.build/debug/blik",
        "/.build/release/BlikApp",
        "/.build/release/BlikMenuBar",
        "/.build/release/blik",
        // Xcode build products
        "/Build/Products/Debug/BlikApp",
        "/Build/Products/Debug/BlikMenuBar",
        "/Build/Products/Debug/blik",
    ]

    /// Возвращает путь к executable процесса с указанным PID.
    /// `nil` если PID не найден или путь не резолвится.
    ///
    /// `PROC_PIDPATHINFO_MAXSIZE` (= `4 * MAXPATHLEN` = `4 * 1024`) не экспортируется
    /// в Swift как символ (в SDK помечен `unavailable: structure not supported`),
    /// поэтому используем литерал 4096 — это и есть зафиксированное значение.
    static func executablePath(forPID pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }

    /// `true` если PID соответствует установленному Blik-бинарнику.
    /// В DEBUG-сборке дополнительно разрешает `.build/...` и Xcode-derived
    /// пути для разработческого workflow.
    static func isAuthorized(pid: pid_t) -> Bool {
        guard let path = executablePath(forPID: pid) else { return false }
        if installedPaths.contains(path) { return true }
        #if DEBUG
        if debugPathSuffixes.contains(where: { path.hasSuffix($0) }) { return true }
        #endif
        return false
    }
}
