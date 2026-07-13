import XCTest
import BlikCore
@testable import BlikXPC

// MARK: - Mock

/// Мок привилегированного хелпера для тестирования UpdateService.
/// Реализует весь @objc протокол BlikHelperProtocol.
final class MockBlikHelper: NSObject, BlikHelperProtocol {

    // Настраиваемое поведение checkForUpdate
    var checkForUpdateHandler: ((@escaping (Data?, String?) -> Void) -> Void)?

    // Настраиваемое поведение checkForUpdateForced
    var checkForUpdateForcedHandler: ((@escaping (Data?, String?) -> Void) -> Void)?

    // Настраиваемое поведение performUpdate
    var performUpdateHandler: ((@escaping (String?) -> Void) -> Void)?

    func checkForUpdate(reply: @escaping (Data?, String?) -> Void) {
        if let handler = checkForUpdateHandler {
            handler(reply)
        } else {
            reply(nil, "Not configured")
        }
    }

    func checkForUpdateForced(reply: @escaping (Data?, String?) -> Void) {
        if let handler = checkForUpdateForcedHandler {
            handler(reply)
        } else {
            // По умолчанию делегирует в checkForUpdate
            checkForUpdate(reply: reply)
        }
    }

    func performUpdate(reply: @escaping (String?) -> Void) {
        if let handler = performUpdateHandler {
            handler(reply)
        } else {
            reply("Not configured")
        }
    }

    // Неиспользуемые методы протокола — пустые реализации

    func readAllFans(reply: @escaping (Data?, String?) -> Void) {
        reply(nil, "Not implemented")
    }

    func readAllSensors(reply: @escaping (Data?, String?) -> Void) {
        reply(nil, "Not implemented")
    }

    func readState(reply: @escaping (Data?, String?) -> Void) {
        reply(nil, "Not implemented")
    }

    func readResources(reply: @escaping (Data?, String?) -> Void) {
        reply(nil, "Not implemented")
    }

    func setFanSpeedPreset(percentage: Int, reply: @escaping (String?) -> Void) {
        reply("Not implemented")
    }

    func restoreAutoMode(reply: @escaping (String?) -> Void) {
        reply("Not implemented")
    }

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply("0.0.0")
    }

    func uninstallAll(reply: @escaping (String?) -> Void) {
        reply("Not implemented")
    }

    func queryHistory(request: Data, reply: @escaping (Data?, String?) -> Void) {
        reply(nil, "Not implemented")
    }

    func listHistoryMetrics(reply: @escaping (Data?, String?) -> Void) {
        reply(nil, "Not implemented")
    }
}

// MARK: - Tests

final class UpdateServiceTests: XCTestCase {

    private var mockHelper: MockBlikHelper!

    override func setUp() {
        super.setUp()
        mockHelper = MockBlikHelper()
    }

    override func tearDown() {
        mockHelper = nil
        super.tearDown()
    }

    // MARK: - Вспомогательные

    /// Создает UpdateInfo и кодирует в JSON Data.
    private func encodeUpdateInfo(
        currentVersion: String = "1.0.0",
        latestVersion: String = "1.2.0",
        downloadURL: String = "https://example.com/Blik-1.2.0.pkg",
        releaseNotes: String? = "Bug fixes",
        isNewer: Bool = true
    ) -> Data {
        let info = UpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadURL: downloadURL,
            releaseNotes: releaseNotes,
            isNewer: isNewer
        )
        return try! JSONEncoder().encode(info)
    }

    // MARK: - check: обновление доступно

    func testCheckReturnsAvailableWhenUpdateIsNewer() {
        let expectedInfo = UpdateInfo(
            currentVersion: "1.0.0",
            latestVersion: "1.2.0",
            downloadURL: "https://example.com/Blik-1.2.0.pkg",
            releaseNotes: "Bug fixes",
            isNewer: true
        )

        mockHelper.checkForUpdateHandler = { reply in
            let data = try! JSONEncoder().encode(expectedInfo)
            reply(data, nil)
        }

        let expectation = expectation(description: "check completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.check(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .available(let info) = receivedResult else {
            XCTFail("Ожидался .available, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(info, expectedInfo)
        XCTAssertTrue(info.isNewer)
    }

    // MARK: - check: версия актуальна

    func testCheckReturnsUpToDateWhenVersionIsCurrent() {
        mockHelper.checkForUpdateHandler = { [self] reply in
            let data = encodeUpdateInfo(
                currentVersion: "1.2.0",
                latestVersion: "1.2.0",
                isNewer: false
            )
            reply(data, nil)
        }

        let expectation = expectation(description: "check completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.check(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .upToDate(let currentVersion) = receivedResult else {
            XCTFail("Ожидался .upToDate, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(currentVersion, "1.2.0")
    }

    // MARK: - check: helper возвращает ошибку

    func testCheckReturnsErrorWhenHelperFails() {
        mockHelper.checkForUpdateHandler = { reply in
            reply(nil, "Connection lost")
        }

        let expectation = expectation(description: "check completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.check(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .error(let message) = receivedResult else {
            XCTFail("Ожидался .error, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(message, "Connection lost")
    }

    // MARK: - check: невалидные данные

    func testCheckReturnsErrorWhenDataIsInvalid() {
        mockHelper.checkForUpdateHandler = { reply in
            let invalidData = "not json".data(using: .utf8)!
            reply(invalidData, nil)
        }

        let expectation = expectation(description: "check completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.check(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .error(let message) = receivedResult else {
            XCTFail("Ожидался .error, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(message, "Не удалось декодировать данные обновления")
    }

    // MARK: - check: nil data без ошибки

    func testCheckReturnsErrorWhenDataIsNilWithoutError() {
        mockHelper.checkForUpdateHandler = { reply in
            reply(nil, nil)
        }

        let expectation = expectation(description: "check completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.check(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .error(let message) = receivedResult else {
            XCTFail("Ожидался .error, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(message, "Не удалось декодировать данные обновления")
    }

    // MARK: - install: успех

    func testInstallReturnsStartedOnSuccess() {
        mockHelper.performUpdateHandler = { reply in
            reply(nil)
        }

        let expectation = expectation(description: "install completion")
        var receivedResult: UpdateService.InstallResult?

        UpdateService.install(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .started = receivedResult else {
            XCTFail("Ожидался .started, получен \(String(describing: receivedResult))")
            return
        }
    }

    // MARK: - install: ошибка

    func testInstallReturnsErrorOnFailure() {
        mockHelper.performUpdateHandler = { reply in
            reply("Installation failed: permission denied")
        }

        let expectation = expectation(description: "install completion")
        var receivedResult: UpdateService.InstallResult?

        UpdateService.install(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .error(let message) = receivedResult else {
            XCTFail("Ожидался .error, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(message, "Installation failed: permission denied")
    }

    // MARK: - checkForced: всегда запрашивает GitHub

    func testCheckForcedReturnsAvailable() {
        let expectedInfo = UpdateInfo(
            currentVersion: "1.0.0",
            latestVersion: "1.3.0",
            downloadURL: "https://example.com/Blik-1.3.0.pkg",
            releaseNotes: "New features",
            isNewer: true
        )

        mockHelper.checkForUpdateForcedHandler = { reply in
            let data = try! JSONEncoder().encode(expectedInfo)
            reply(data, nil)
        }

        let expectation = expectation(description: "checkForced completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.checkForced(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .available(let info) = receivedResult else {
            XCTFail("Ожидался .available, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(info, expectedInfo)
    }

    func testCheckForcedReturnsUpToDate() {
        mockHelper.checkForUpdateForcedHandler = { [self] reply in
            let data = encodeUpdateInfo(
                currentVersion: "1.3.0",
                latestVersion: "1.3.0",
                isNewer: false
            )
            reply(data, nil)
        }

        let expectation = expectation(description: "checkForced completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.checkForced(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .upToDate(let version) = receivedResult else {
            XCTFail("Ожидался .upToDate, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(version, "1.3.0")
    }

    func testCheckForcedUsesSeperateHandler() {
        // checkForUpdate возвращает "нет обновления"
        mockHelper.checkForUpdateHandler = { [self] reply in
            let data = encodeUpdateInfo(
                currentVersion: "1.0.0",
                latestVersion: "1.0.0",
                isNewer: false
            )
            reply(data, nil)
        }

        // checkForUpdateForced возвращает "есть обновление"
        mockHelper.checkForUpdateForcedHandler = { [self] reply in
            let data = encodeUpdateInfo(
                currentVersion: "1.0.0",
                latestVersion: "2.0.0",
                isNewer: true
            )
            reply(data, nil)
        }

        // check (cached) должен вернуть upToDate
        let cachedExp = expectation(description: "cached check")
        UpdateService.check(helper: mockHelper) { result in
            guard case .upToDate = result else {
                XCTFail("Ожидался .upToDate от check, получен \(result)")
                return
            }
            cachedExp.fulfill()
        }

        // checkForced должен вернуть available
        let forcedExp = expectation(description: "forced check")
        UpdateService.checkForced(helper: mockHelper) { result in
            guard case .available(let info) = result else {
                XCTFail("Ожидался .available от checkForced, получен \(result)")
                return
            }
            XCTAssertEqual(info.latestVersion, "2.0.0")
            forcedExp.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - check: обновление с nil releaseNotes

    func testCheckAvailableWithNilReleaseNotes() {
        let expectedInfo = UpdateInfo(
            currentVersion: "1.0.0",
            latestVersion: "2.0.0",
            downloadURL: "https://example.com/Blik-2.0.0.pkg",
            releaseNotes: nil,
            isNewer: true
        )

        mockHelper.checkForUpdateHandler = { reply in
            let data = try! JSONEncoder().encode(expectedInfo)
            reply(data, nil)
        }

        let expectation = expectation(description: "check completion")
        var receivedResult: UpdateService.CheckResult?

        UpdateService.check(helper: mockHelper) { result in
            receivedResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard case .available(let info) = receivedResult else {
            XCTFail("Ожидался .available, получен \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(info, expectedInfo)
        XCTAssertNil(info.releaseNotes)
    }
}
