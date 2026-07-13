import Foundation
@preconcurrency import BlikCore
import BlikXPC
import os

/// Lazy-инициализированные shared resources (XPC client / прямой SMC reader-writer)
/// для всего VM-слоя. Создаётся один раз в `AppCoordinator.init`, передаётся VM'ам по ссылке.
/// Изолирует bootstrap от наблюдаемых VM, чтобы их init был тонким и тестируемым.
public final class BlikRuntime {
    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "Runtime")

    /// XPC-клиент к привилегированному хелперу. Nil, если хелпер не отвечает (read-only режим).
    public let xpcClient: BlikXPCClient?

    /// Прямой SMC reader (read-only fallback, когда XPC недоступен).
    public let reader: SMCReader?

    /// Прямой SMC writer (используется только в sudo-режиме без XPC).
    public let writer: SMCWriter?

    /// Хелпер поддерживает объединённый `readState` (прочитан асинхронно после connect).
    /// Доступ из main actor через ассоциированный VM.
    public private(set) var supportsReadState: Bool = false

    /// Хелпер поддерживает локальную историю метрик (`queryHistory`/`listHistoryMetrics`).
    /// Если false — range-режим графиков недоступен (empty-state вместо зависания).
    public private(set) var helperSupportsHistory: Bool = false

    /// True, если работаем без XPC (только direct SMC чтение).
    public var isReadOnly: Bool { xpcClient == nil }

    /// Стартовая ошибка подключения, если SMC и XPC оба недоступны.
    public let startupError: String?

    public init() {
        let client = BlikXPCClient()
        if client.connectAndVerify() {
            self.xpcClient = client
            self.reader = nil
            self.writer = nil
            self.startupError = nil
            Self.logger.info("Connected via XPC helper")

            // Определяем поддержку объединённого readState по версии daemon'а.
            // Кэшируем в свойстве, читается из FanControlVM.
            if let helper = client.helper() {
                helper.getHelperVersion { [weak self] version in
                    guard let self,
                          let hv = SemanticVersion(string: version),
                          let minV = SemanticVersion(string: Constants.minHelperVersionForReadState) else { return }
                    let supports = hv >= minV
                    let supportsHistory = SemanticVersion(string: Constants.minHelperVersionForHistory)
                        .map { hv >= $0 } ?? false
                    Task { @MainActor in
                        self.supportsReadState = supports
                        self.helperSupportsHistory = supportsHistory
                        Self.logger.info("helper version \(version), supportsReadState=\(supports ? 1 : 0, privacy: .public), supportsHistory=\(supportsHistory ? 1 : 0, privacy: .public)")
                    }
                }
            }
        } else {
            // Fallback: прямой SMC (read-only)
            self.xpcClient = nil
            do {
                let connection = try SMCConnection()
                self.reader = SMCReader(connection: connection)
                self.writer = nil // direct write требует sudo и SMCWriter с retry — в GUI не используется
                self.startupError = nil
                Self.logger.info("XPC helper unavailable, direct SMC read-only mode")
            } catch {
                self.reader = nil
                self.writer = nil
                self.startupError = "Не удалось подключиться к SMC: \(error.localizedDescription)"
                Self.logger.error("SMC connection failed: \(error)")
            }
        }
    }

    /// Test-only init: прямая инъекция зависимостей (mock XPC-клиент / SMC) в
    /// обход реального bootstrap'а. `internal` — доступен только через
    /// `@testable import BlikShared`, в проде не используется.
    init(xpcClient: BlikXPCClient?, reader: SMCReader? = nil, writer: SMCWriter? = nil,
         supportsReadState: Bool = false, helperSupportsHistory: Bool = false,
         startupError: String? = nil) {
        self.xpcClient = xpcClient
        self.reader = reader
        self.writer = writer
        self.supportsReadState = supportsReadState
        self.helperSupportsHistory = helperSupportsHistory
        self.startupError = startupError
    }

    /// Корректное завершение: восстановить auto и закрыть XPC.
    /// Вызывается из `AppCoordinator` на `applicationWillTerminate`.
    public func cleanup(currentFanCount: Int) {
        if let client = xpcClient {
            // Sync вариант — даём daemon'у успеть выполнить restoreAutoMode до выхода процесса.
            _ = client.restoreAutoModeSync()
            client.disconnect()
        }
        Self.logger.info("runtime cleanup: fans restored, xpc disconnected")
    }
}
