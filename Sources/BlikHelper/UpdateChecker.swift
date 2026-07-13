import Foundation
import BlikCore

/// Проверка обновлений через GitHub Releases API и установка PKG.
enum UpdateChecker {

    // MARK: - Errors

    enum UpdateError: LocalizedError {
        case invalidURL
        case httpError(statusCode: Int)
        case noPKGAsset
        case invalidVersion(String)
        case downloadFailed(String)
        case installFailed(exitCode: Int32)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Некорректный URL"
            case .httpError(let code):
                return "HTTP ошибка: \(code)"
            case .noPKGAsset:
                return "PKG файл не найден в релизе"
            case .invalidVersion(let v):
                return "Некорректная версия: \(v)"
            case .downloadFailed(let reason):
                return "Ошибка скачивания: \(reason)"
            case .installFailed(let code):
                return "Установка завершилась с кодом \(code)"
            }
        }
    }

    // MARK: - GitHub API models

    /// Структура для парсинга GitHub API response.
    struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let assets: [GitHubAsset]
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
    }

    // MARK: - Paths

    /// URL GitHub API для последнего релиза.
    static let latestReleaseURL = "https://api.github.com/repos/\(Constants.githubOwner)/\(Constants.githubRepo)/releases/latest"

    /// Каталог для скачанного PKG. Создаётся helper'ом под root с правами 0700,
    /// чтобы исключить TOCTOU-подмену файла из user-mode процессов между
    /// скачиванием и `installer -pkg`.
    static let updatesDirectory = "/var/db/blik/updates"

    /// Создаёт `updatesDirectory` если его нет; принудительно ставит 0700.
    /// Вызывается перед скачиванием PKG из помойки `/tmp`.
    static func ensureUpdatesDirectory() throws {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: updatesDirectory)
        if !fm.fileExists(atPath: updatesDirectory) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } else {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: updatesDirectory)
        }
    }

    // MARK: - Check

    /// Проверяет наличие нового релиза.
    static func checkLatestRelease(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        guard let url = URL(string: latestReleaseURL) else {
            completion(.failure(UpdateError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                completion(.failure(UpdateError.httpError(statusCode: httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(UpdateError.downloadFailed("Пустой ответ")))
                return
            }

            completion(parseRelease(data: data))
        }.resume()
    }

    // MARK: - Parse

    /// Парсит ответ GitHub API и создает UpdateInfo.
    /// Эта функция не private для возможности тестирования.
    static func parseRelease(data: Data) -> Result<UpdateInfo, Error> {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            return .failure(error)
        }

        // Убрать "v" префикс из tag_name (например "v1.2.0" -> "1.2.0")
        let versionString = release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst())
            : release.tag_name

        guard let latestVersion = SemanticVersion(string: versionString) else {
            return .failure(UpdateError.invalidVersion(release.tag_name))
        }

        guard let currentVersion = SemanticVersion(string: Constants.appVersion) else {
            return .failure(UpdateError.invalidVersion(Constants.appVersion))
        }

        // Найти asset с расширением .pkg
        let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
        let downloadURL = pkgAsset?.browser_download_url ?? ""

        let isNewer = currentVersion < latestVersion

        let info = UpdateInfo(
            currentVersion: Constants.appVersion,
            latestVersion: versionString,
            downloadURL: downloadURL,
            releaseNotes: release.body,
            isNewer: isNewer
        )

        return .success(info)
    }

    // MARK: - Download

    /// Скачивает PKG файл в `updatesDirectory` (root-only, 0700).
    static func downloadPKG(from urlString: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(UpdateError.invalidURL))
            return
        }

        do {
            try ensureUpdatesDirectory()
        } catch {
            completion(.failure(UpdateError.downloadFailed("Не удалось создать \(updatesDirectory): \(error.localizedDescription)")))
            return
        }

        let destinationPath = "\(updatesDirectory)/blik-update.pkg"

        // Удалить предыдущий файл, если остался
        try? FileManager.default.removeItem(atPath: destinationPath)

        URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                completion(.failure(UpdateError.httpError(statusCode: httpResponse.statusCode)))
                return
            }

            guard let tempURL = tempURL else {
                completion(.failure(UpdateError.downloadFailed("Нет временного файла")))
                return
            }

            do {
                let destination = URL(fileURLWithPath: destinationPath)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                // Только root читает/пишет PKG до момента `installer -pkg`.
                try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                      ofItemAtPath: destinationPath)

                guard FileManager.default.fileExists(atPath: destinationPath) else {
                    completion(.failure(UpdateError.downloadFailed("Файл не найден после перемещения")))
                    return
                }

                completion(.success(destinationPath))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Install

    /// Запускает silent install PKG через macOS installer.
    static func installPKG(atPath path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        process.arguments = ["-pkg", path, "-target", "/"]

        try process.run()
        process.waitUntilExit()

        let exitCode = process.terminationStatus
        // Удалить PKG после установки (независимо от результата)
        try? FileManager.default.removeItem(atPath: path)

        guard exitCode == 0 else {
            throw UpdateError.installFailed(exitCode: exitCode)
        }
    }
}
