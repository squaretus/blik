import Foundation

/// Семантическая версия (major.minor.patch) с поддержкой сравнения.
public struct SemanticVersion: Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(string: String) {
        let parts = string.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Информация о доступном обновлении.
public struct UpdateInfo: Codable, Equatable {
    public let currentVersion: String
    public let latestVersion: String
    public let downloadURL: String
    public let releaseNotes: String?
    public let isNewer: Bool

    public init(currentVersion: String, latestVersion: String, downloadURL: String, releaseNotes: String?, isNewer: Bool) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
        self.isNewer = isNewer
    }
}
