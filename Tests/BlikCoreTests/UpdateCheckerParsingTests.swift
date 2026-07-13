import XCTest
@testable import BlikCore

/// Тесты парсинга GitHub Release JSON — имитация логики UpdateChecker.parseRelease.
/// UpdateChecker находится в target BlikHelper и недоступен из BlikCoreTests,
/// поэтому здесь тестируем парсинг JSON и интеграцию с моделями BlikCore.
final class UpdateCheckerParsingTests: XCTestCase {

    // MARK: - GitHub Release JSON structures (как в UpdateChecker)

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
    }

    // MARK: - Парсинг полного релиза

    func testGitHubReleaseJSONParsing() throws {
        let json = """
        {
            "tag_name": "v1.2.0",
            "body": "Bug fixes",
            "assets": [
                {"name": "Blik-1.2.0.pkg", "browser_download_url": "https://example.com/pkg", "size": 1234},
                {"name": "source.zip", "browser_download_url": "https://example.com/zip", "size": 5678}
            ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)

        // Парсинг tag_name с удалением префикса "v"
        let versionString = release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst())
            : release.tag_name
        XCTAssertEqual(versionString, "1.2.0")

        // Нахождение PKG asset
        let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
        XCTAssertNotNil(pkgAsset)
        XCTAssertEqual(pkgAsset?.browser_download_url, "https://example.com/pkg")

        // Сравнение версий через SemanticVersion
        let latest = SemanticVersion(string: versionString)!
        let current = SemanticVersion(string: "1.0.0")!
        XCTAssertTrue(current < latest)

        // Формирование UpdateInfo
        let info = UpdateInfo(
            currentVersion: current.description,
            latestVersion: latest.description,
            downloadURL: pkgAsset!.browser_download_url,
            releaseNotes: release.body,
            isNewer: current < latest
        )
        XCTAssertEqual(info.latestVersion, "1.2.0")
        XCTAssertEqual(info.downloadURL, "https://example.com/pkg")
        XCTAssertEqual(info.releaseNotes, "Bug fixes")
        XCTAssertTrue(info.isNewer)
    }

    // MARK: - JSON без PKG asset

    func testGitHubReleaseNoPkgAsset() throws {
        let json = """
        {
            "tag_name": "v1.0.0",
            "body": "Source only",
            "assets": [
                {"name": "source.tar.gz", "browser_download_url": "https://example.com/tar", "size": 999}
            ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
        XCTAssertNil(pkgAsset)
    }

    // MARK: - tag_name без префикса "v"

    func testGitHubReleaseTagWithoutVPrefix() throws {
        let json = """
        {
            "tag_name": "2.0.0",
            "body": null,
            "assets": [
                {"name": "Blik-2.0.0.pkg", "browser_download_url": "https://example.com/pkg2", "size": 2000}
            ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        let versionString = release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst())
            : release.tag_name
        XCTAssertEqual(versionString, "2.0.0")

        let version = SemanticVersion(string: versionString)
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 2)
    }

    // MARK: - body = null

    func testGitHubReleaseNullBody() throws {
        let json = """
        {
            "tag_name": "v1.0.1",
            "body": null,
            "assets": []
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertNil(release.body)
    }

    // MARK: - Невалидный JSON

    func testInvalidJSONThrows() {
        let badJSON = "not a json".data(using: .utf8)!
        XCTAssertThrowsError(
            try JSONDecoder().decode(GitHubRelease.self, from: badJSON)
        )
    }

    // MARK: - Одинаковые версии

    func testSameVersionNotNewer() {
        let current = SemanticVersion(string: "1.2.0")!
        let latest = SemanticVersion(string: "1.2.0")!
        XCTAssertFalse(current < latest)
    }

    // MARK: - Текущая версия новее

    func testCurrentVersionNewerThanLatest() {
        let current = SemanticVersion(string: "2.0.0")!
        let latest = SemanticVersion(string: "1.5.0")!
        XCTAssertFalse(current < latest)
        XCTAssertTrue(latest < current)
    }

    // MARK: - Пустой массив assets

    func testGitHubReleaseEmptyAssets() throws {
        let json = """
        {
            "tag_name": "v1.0.0",
            "body": "No binaries",
            "assets": []
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertTrue(release.assets.isEmpty)
        let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
        XCTAssertNil(pkgAsset)
    }

    // MARK: - Несколько PKG assets — берётся первый

    func testGitHubReleaseMultiplePkgAssets() throws {
        let json = """
        {
            "tag_name": "v1.3.0",
            "body": "Multiple packages",
            "assets": [
                {"name": "Blik-1.3.0.pkg", "browser_download_url": "https://example.com/first.pkg", "size": 100},
                {"name": "Blik-1.3.0-arm64.pkg", "browser_download_url": "https://example.com/second.pkg", "size": 200}
            ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
        XCTAssertNotNil(pkgAsset)
        XCTAssertEqual(pkgAsset?.browser_download_url, "https://example.com/first.pkg")
    }
}
