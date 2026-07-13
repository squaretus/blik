import Foundation

/// Универсальный JSON-форматтер логов macOS-стороны.
///
/// Контракт строки лога: один JSON-объект на строку, поля:
/// `ts` (ISO-8601 ms), `level`, `tag`, `message?`, плюс произвольные payload-ключи.
///
/// Sanitize-правила (НЕ логируем):
/// - Сырой `pat_…` Personal Access Token, JWT, refresh.
/// - Bcrypt-хеши, пароли.
/// - `JWT_SECRET`, HMAC-секреты.
///
/// Sanitize-helpers:
/// - `truncateID(_:prefix:)` — для hardware_id (8 chars + `…`).
/// - `maskEmail(_:)` — `p***@example.com` если нужно.
public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

public enum JSONLogFormatter {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Формирует JSON-строку лога. Возвращает уже с `\n` на конце, готовую к записи.
    public static func format(
        level: LogLevel,
        tag: String,
        message: String? = nil,
        payload: [String: Any] = [:]
    ) -> String {
        var dict: [String: Any] = [
            "ts": isoFormatter.string(from: Date()),
            "level": level.rawValue,
            "tag": tag,
        ]
        if let message, !message.isEmpty {
            dict["message"] = message
        }
        for (k, v) in payload {
            dict[k] = sanitize(v)
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ), let str = String(data: data, encoding: .utf8) else {
            return "{\"level\":\"\(level.rawValue)\",\"tag\":\"\(tag)\",\"message\":\"json_encode_failed\"}\n"
        }
        return str + "\n"
    }

    public static func truncateID(_ value: String?, prefix: Int = 8) -> String? {
        guard let value, !value.isEmpty else { return value }
        if value.count <= prefix { return value }
        return value.prefix(prefix) + "…"
    }

    public static func maskEmail(_ email: String?) -> String? {
        guard let email, email.contains("@") else { return email }
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return email }
        let local = parts[0]
        let domain = parts[1]
        if local.count <= 1 { return "***@\(domain)" }
        return "\(local.first!)***@\(domain)"
    }

    /// Защита от попадания сырых токенов в payload. Заменяет известные префиксы маской.
    private static func sanitize(_ value: Any) -> Any {
        if let s = value as? String {
            if s.hasPrefix("pat_") {
                return "pat_***"
            }
            if s.hasPrefix("eyJ") && s.count > 40 {
                // Похоже на JWT — обрезаем.
                return "jwt_***"
            }
            return s
        }
        return value
    }
}
