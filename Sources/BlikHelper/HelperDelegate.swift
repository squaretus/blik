import Foundation
import BlikCore
import BlikXPC

/// Делегат привилегированного XPC-хелпера.
/// Реализует BlikHelperProtocol и управляет жизненным циклом XPC-подключений.
/// Все SMC-операции выполняются на serial queue для thread safety.
class HelperDelegate: NSObject, BlikHelperProtocol, NSXPCListenerDelegate {

    // MARK: - SMC

    private let connection: SMCConnection
    private let reader: SMCReader
    private let writer: SMCWriter
    private let resourceReader = ResourceReader()
    private let smcQueue = DispatchQueue(label: "com.blik.helper.smc")

    // MARK: - Connection tracking

    private let connectionLock = NSLock()
    /// Идентификаторы активных XPC-соединений. Считаем по идентичности, а не
    /// счётчиком: `invalidationHandler` и `interruptionHandler` могут оба
    /// сработать для одного соединения — множество делает учёт идемпотентным.
    private var activeConnectionIDs = Set<ObjectIdentifier>()

    // MARK: - History

    /// SQLite-хранилище истории метрик. Nil, если инициализация не удалась
    /// (SMC-сервис не должен умирать из-за истории).
    private var historyStore: HistoryStore?
    /// Рекордер истории (две serial-очереди: sampling + db). Nil при ошибке init.
    private var recorder: HistoryRecorder?

    // MARK: - Reinforce

    /// Целевые RPM для каждого кулера (заполняется при setFanSpeedPreset).
    private var targetSpeeds: [Int: Double] = [:]
    private var reinforceTimer: DispatchSourceTimer?

    // MARK: - Auto-Update

    private var cachedUpdate: UpdateInfo?
    private var isUpdating: Bool = false
    private var updateTimer: DispatchSourceTimer?

    /// Таймер отложенного восстановления auto-режима после отключения всех клиентов.
    private var restoreWorkItem: DispatchWorkItem?

    /// Флаг: app существовал при старте daemon.
    /// Самоочистка при удалении app из Finder выполняется только если true.
    private var appExistedOnStart: Bool = false

    // MARK: - Init

    /// Фабричный метод -- NSObject.init() не может быть throwing.
    static func create() throws -> HelperDelegate {
        let smcConnection = try SMCConnection()
        let delegate = HelperDelegate(smcConnection: smcConnection)
        return delegate
    }

    private init(smcConnection: SMCConnection) {
        self.connection = smcConnection
        self.reader = SMCReader(connection: smcConnection)
        self.writer = SMCWriter(connection: smcConnection, log: { message in
            HelperLogger.log(message)
        })

        super.init()
        self.appExistedOnStart = FileManager.default.fileExists(atPath: "/Applications/Blik.app")
        startReinforceTimer()
        startUpdateTimer()
        setupHistory()
        HelperLogger.log("initialized, SMC connection established (appExisted=\(appExistedOnStart ? 1 : 0))")
    }

    /// Создаёт хранилище истории и рекордер. При ошибке — лог и `recorder = nil`
    /// (SMC-сервис продолжает работать без истории).
    private func setupHistory() {
        let dbPath = Constants.historyDBPath
        let dir = (dbPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            let store = try HistoryStore(path: dbPath)
            let recorder = HistoryRecorder(store: store) { [weak self] in
                guard let self else { return nil }
                // SMC-чтение строго на smcQueue — дисциплина сохраняется.
                return self.smcQueue.sync {
                    do {
                        let fans = try self.reader.readAllFans()
                        let sensors = try self.reader.readAllSensors()
                        return (fans, sensors)
                    } catch {
                        HelperLogger.log("history sample read error: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            self.historyStore = store
            self.recorder = recorder
            HelperLogger.log("history store initialized at \(dbPath)")
        } catch {
            self.historyStore = nil
            self.recorder = nil
            HelperLogger.log("history store init failed (history disabled): \(error.localizedDescription)")
        }
    }

    // MARK: - NSXPCListenerDelegate

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let clientPID = newConnection.processIdentifier
        let clientPath = ClientAuthorization.executablePath(forPID: clientPID) ?? "<unknown>"
        guard ClientAuthorization.isAuthorized(pid: clientPID) else {
            HelperLogger.log("rejected connection from pid=\(clientPID) path=\(clientPath)")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: BlikHelperProtocol.self)
        newConnection.exportedObject = self

        let connectionID = ObjectIdentifier(newConnection)
        newConnection.invalidationHandler = { [weak self] in
            self?.handleClientDisconnected(connectionID)
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.handleClientDisconnected(connectionID)
        }

        newConnection.resume()

        connectionLock.lock()
        activeConnectionIDs.insert(connectionID)
        let count = activeConnectionIDs.count
        connectionLock.unlock()

        // Клиент подключился -- отменяем отложенное восстановление auto-режима
        restoreWorkItem?.cancel()
        restoreWorkItem = nil

        // Пока открыт хотя бы один клиент — пишем историю (идемпотентно).
        recorder?.setActive(true)

        HelperLogger.log("accepted connection pid=\(clientPID) path=\(clientPath) (active: \(count))")
        return true
    }

    // MARK: - Client disconnect handling

    private func handleClientDisconnected(_ connectionID: ObjectIdentifier) {
        connectionLock.lock()
        // invalidation и interruption могут оба сработать для одного соединения —
        // `remove` вернёт nil на повторном вызове, декремент считаем один раз.
        let wasActive = activeConnectionIDs.remove(connectionID) != nil
        let count = activeConnectionIDs.count
        connectionLock.unlock()

        guard wasActive else { return }

        HelperLogger.log("client disconnected (active: \(count))")

        if count == 0 {
            // Все клиенты закрыты — останавливаем запись истории.
            recorder?.setActive(false)
            scheduleAutoRestoreIfNeeded()
        }
    }

    /// Откладывает восстановление auto-режима на 5 секунд,
    /// чтобы клиент успел переподключиться.
    private func scheduleAutoRestoreIfNeeded() {
        restoreWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.connectionLock.lock()
            let count = self.activeConnectionIDs.count
            self.connectionLock.unlock()

            // Если за время ожидания клиент переподключился -- не трогаем кулеры
            guard count == 0 else { return }

            self.smcQueue.sync {
                guard !self.writer.modifiedFanIds.isEmpty else { return }
                HelperLogger.log("no active connections, restoring auto mode")
                self.writer.restoreAutoMode()
                self.targetSpeeds.removeAll()
            }
        }

        restoreWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    // MARK: - Reinforce timer

    private func startReinforceTimer() {
        let timer = DispatchSource.makeTimerSource(queue: smcQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.reinforceAllFans()
        }
        timer.resume()
        reinforceTimer = timer
    }

    private func reinforceAllFans() {
        // Вызывается уже на smcQueue
        let modifiedIds = writer.modifiedFanIds
        if !modifiedIds.isEmpty {
            for fanId in modifiedIds {
                guard let rpm = targetSpeeds[fanId] else { continue }
                writer.reinforceSpeed(fan: fanId, rpm: rpm)
            }
        }

        // Самоочистка: если app удалён из Finder и нет активных клиентов
        if appExistedOnStart {
            connectionLock.lock()
            let count = activeConnectionIDs.count
            connectionLock.unlock()

            if count == 0 && !FileManager.default.fileExists(atPath: "/Applications/Blik.app") {
                HelperLogger.log("app удалён из Finder, выполняю самоочистку")
                writer.restoreAutoMode()
                targetSpeeds.removeAll()
                performUninstall(removeApp: false)
            }
        }
    }

    // MARK: - Update timer

    private func startUpdateTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + Constants.updateCheckInitialDelay,
            repeating: Constants.updateCheckInterval
        )
        timer.setEventHandler { [weak self] in
            self?.performUpdateCheck()
        }
        timer.resume()
        updateTimer = timer
    }

    private func performUpdateCheck() {
        UpdateChecker.checkLatestRelease { [weak self] result in
            switch result {
            case .success(let info):
                self?.cachedUpdate = info
                HelperLogger.log("update check: current=\(info.currentVersion), latest=\(info.latestVersion), isNewer=\(info.isNewer)")
            case .failure(let error):
                HelperLogger.log("update check failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - BlikHelperProtocol

    func readAllFans(reply: @escaping (Data?, String?) -> Void) {
        smcQueue.async { [weak self] in
            guard let self else {
                reply(nil, "Helper deallocated")
                return
            }
            do {
                let fans = try self.reader.readAllFans()
                let data = try JSONEncoder().encode(fans)
                reply(data, nil)
            } catch {
                HelperLogger.log("readAllFans error: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    func readAllSensors(reply: @escaping (Data?, String?) -> Void) {
        smcQueue.async { [weak self] in
            guard let self else {
                reply(nil, "Helper deallocated")
                return
            }
            do {
                let sensors = try self.reader.readAllSensors()
                let data = try JSONEncoder().encode(sensors)
                reply(data, nil)
            } catch {
                HelperLogger.log("readAllSensors error: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    func readState(reply: @escaping (Data?, String?) -> Void) {
        smcQueue.async { [weak self] in
            guard let self else {
                reply(nil, "Helper deallocated")
                return
            }
            do {
                let fans = try self.reader.readAllFans()
                let sensors = try self.reader.readAllSensors()
                let snapshot = StateSnapshot(fans: fans, sensors: sensors)
                let data = try JSONEncoder().encode(snapshot)
                reply(data, nil)
            } catch {
                HelperLogger.log("readState error: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    func readResources(reply: @escaping (Data?, String?) -> Void) {
        smcQueue.async { [weak self] in
            guard let self else {
                reply(nil, "Helper deallocated")
                return
            }
            do {
                let snapshot = self.resourceReader.read()
                let data = try JSONEncoder().encode(snapshot)
                reply(data, nil)
            } catch {
                HelperLogger.log("readResources error: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    func setFanSpeedPreset(percentage: Int, reply: @escaping (String?) -> Void) {
        smcQueue.async { [weak self] in
            guard let self else {
                reply("Helper deallocated")
                return
            }
            do {
                let fans = try self.reader.readAllFans()
                try self.writer.setAllFansSpeed(percentage: percentage, fans: fans)

                if percentage == 0 {
                    self.targetSpeeds.removeAll()
                } else {
                    let fraction = Double(percentage) / 100.0
                    for fan in fans {
                        let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * fraction
                        self.targetSpeeds[fan.id] = rpm
                    }
                }

                HelperLogger.log("preset set to \(percentage)%")
                reply(nil)
            } catch {
                HelperLogger.log("setFanSpeedPreset error: \(error.localizedDescription)")
                reply(error.localizedDescription)
            }
        }
    }

    func restoreAutoMode(reply: @escaping (String?) -> Void) {
        smcQueue.async { [weak self] in
            guard let self else {
                reply("Helper deallocated")
                return
            }
            self.writer.restoreAutoMode()
            self.targetSpeeds.removeAll()
            HelperLogger.log("auto mode restored by client request")
            reply(nil)
        }
    }

    func uninstallAll(reply: @escaping (String?) -> Void) {
        smcQueue.async { [self] in
            // 1. Восстановить авто-режим кулеров
            writer.restoreAutoMode()
            targetSpeeds.removeAll()

            // 2. Ответить клиенту ДО удаления (иначе XPC connection оборвётся)
            reply(nil)

            // 3. Дать время reply дойти до клиента
            Thread.sleep(forTimeInterval: 0.5)

            // 4. Очистка файлов и сервисов
            performUninstall(removeApp: true)
        }
    }

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply(BlikXPCConstants.protocolVersion)
    }

    // MARK: - Auto-Update protocol

    func checkForUpdate(reply: @escaping (Data?, String?) -> Void) {
        if let cached = cachedUpdate {
            do {
                let data = try JSONEncoder().encode(cached)
                reply(data, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
            return
        }

        fetchUpdateFromGitHub(reply: reply)
    }

    func checkForUpdateForced(reply: @escaping (Data?, String?) -> Void) {
        fetchUpdateFromGitHub(reply: reply)
    }

    private func fetchUpdateFromGitHub(reply: @escaping (Data?, String?) -> Void) {
        UpdateChecker.checkLatestRelease { [weak self] result in
            switch result {
            case .success(let info):
                self?.cachedUpdate = info
                HelperLogger.log("update check: current=\(info.currentVersion), latest=\(info.latestVersion), isNewer=\(info.isNewer)")
                do {
                    let data = try JSONEncoder().encode(info)
                    reply(data, nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            case .failure(let error):
                reply(nil, error.localizedDescription)
            }
        }
    }

    func performUpdate(reply: @escaping (String?) -> Void) {
        guard !isUpdating else {
            reply("Обновление уже выполняется")
            return
        }
        guard let update = cachedUpdate, update.isNewer, !update.downloadURL.isEmpty else {
            reply("Нет доступного обновления")
            return
        }

        isUpdating = true
        // Отвечаем клиенту сразу -- обновление начато
        reply(nil)

        // Скачиваем и устанавливаем на background queue
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            HelperLogger.log("начинаю скачивание обновления v\(update.latestVersion) с \(update.downloadURL)")

            UpdateChecker.downloadPKG(from: update.downloadURL) { result in
                switch result {
                case .success(let path):
                    HelperLogger.log("PKG скачан в \(path), запуск установки")
                    do {
                        try UpdateChecker.installPKG(atPath: path)
                        // Мы сюда можем не дойти -- installer убьёт daemon через preinstall
                    } catch {
                        HelperLogger.log("ошибка установки: \(error.localizedDescription)")
                        self?.isUpdating = false
                    }
                case .failure(let error):
                    HelperLogger.log("ошибка скачивания: \(error.localizedDescription)")
                    self?.isUpdating = false
                }
            }
        }
    }

    // MARK: - History protocol

    func queryHistory(request: Data, reply: @escaping (Data?, String?) -> Void) {
        guard let recorder else {
            reply(nil, "History unavailable")
            return
        }
        do {
            let req = try JSONDecoder().decode(HistoryQueryRequest.self, from: request)
            let response = recorder.query(req)
            let data = try JSONEncoder().encode(response)
            reply(data, nil)
        } catch {
            HelperLogger.log("queryHistory error: \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

    func listHistoryMetrics(reply: @escaping (Data?, String?) -> Void) {
        guard let recorder else {
            reply(nil, "History unavailable")
            return
        }
        do {
            let metrics = recorder.availableMetrics()
            let data = try JSONEncoder().encode(metrics)
            reply(data, nil)
        } catch {
            HelperLogger.log("listHistoryMetrics error: \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

    // MARK: - Uninstall

    private func performUninstall(removeApp: Bool) {
        HelperLogger.log("начало полного удаления (removeApp=\(removeApp))")

        let fm = FileManager.default

        // ── Сначала удаляем все файлы (мгновенно, не зависит от Process) ──

        // 1. Удалить CLI
        try? fm.removeItem(atPath: "/usr/local/bin/blik")
        HelperLogger.log("удалён CLI")

        // 2. Удалить LaunchAgent plist
        try? fm.removeItem(atPath: "/Library/LaunchAgents/com.blik.app.plist")

        // 3. Удалить app (если нужно)
        if removeApp {
            try? fm.removeItem(atPath: "/Applications/Blik.app")
        }

        // 4. Очистка пользовательских данных
        cleanupUserData()

        // 4a-history. Удалить БД истории метрик (+ WAL/SHM).
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: Constants.historyDBPath + suffix)
        }
        HelperLogger.log("удалена БД истории метрик")

        // 4a. Удалить legacy-каталог /Library/Application Support/blik (если остался от
        // прошлой инсталляции с key-based license — больше не используется).
        let legacyDir = "/Library/Application Support/blik"
        if fm.fileExists(atPath: legacyDir) {
            try? fm.removeItem(atPath: legacyDir)
            HelperLogger.log("удалён legacy-каталог: \(legacyDir)")
        }

        // 5. Удалить LaunchDaemon plist (чтобы launchd не перезапустил после bootout)
        try? fm.removeItem(atPath: "/Library/LaunchDaemons/com.blik.helper.plist")

        // 6. Удалить свой binary
        try? fm.removeItem(atPath: "/Library/PrivilegedHelperTools/com.blik.helper")

        HelperLogger.log("файлы удалены")

        // ── Затем Process-вызовы (могут прервать процесс) ──

        // 7. Остановить LaunchAgent для всех пользователей.
        // Динамически определяем UID каждого пользователя через owner home-директории
        // (раньше был хардкод 501...510, не покрывал кастомные UID и migrated-аккаунты).
        let homes = (try? fm.contentsOfDirectory(atPath: "/Users")) ?? []
        for user in homes where !user.hasPrefix(".") && user != "Shared" {
            guard let attrs = try? fm.attributesOfItem(atPath: "/Users/\(user)"),
                  let uid = attrs[.ownerAccountID] as? NSNumber else { continue }
            let bootout = Process()
            bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootout.arguments = ["bootout", "gui/\(uid.intValue)/com.blik.app"]
            try? bootout.run()
            bootout.waitUntilExit()
        }

        // 8. Сброс TCC-разрешений
        let tccReset = Process()
        tccReset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccReset.arguments = ["reset", "All", "com.blik.app"]
        try? tccReset.run()
        tccReset.waitUntilExit()

        // 9. Удалить PKG receipt
        let pkgForget = Process()
        pkgForget.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        pkgForget.arguments = ["--forget", "com.blik.pkg"]
        try? pkgForget.run()
        pkgForget.waitUntilExit()

        // 10. Остановить себя — после этого процесс завершится
        let bootoutSelf = Process()
        bootoutSelf.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootoutSelf.arguments = ["bootout", "system/com.blik.helper"]
        try? bootoutSelf.run()

        HelperLogger.log("полное удаление завершено")
    }

    /// Удаляет логи, preferences, кэши для всех пользователей.
    private func cleanupUserData() {
        let fm = FileManager.default

        // Найти все домашние директории пользователей
        let usersDir = "/Users"
        guard let users = try? fm.contentsOfDirectory(atPath: usersDir) else { return }

        for user in users {
            let home = "\(usersDir)/\(user)"

            // ~/Library/Logs/Blik/
            try? fm.removeItem(atPath: "\(home)/Library/Logs/Blik")
            try? fm.removeItem(atPath: "\(home)/Library/Logs/blik")

            // ~/Library/Preferences/com.blik.* (UserDefaults)
            if let prefs = try? fm.contentsOfDirectory(atPath: "\(home)/Library/Preferences") {
                for pref in prefs where pref.hasPrefix("com.blik.") {
                    try? fm.removeItem(atPath: "\(home)/Library/Preferences/\(pref)")
                }
            }

            // ~/Library/Caches/com.blik.*
            if let caches = try? fm.contentsOfDirectory(atPath: "\(home)/Library/Caches") {
                for cache in caches where cache.hasPrefix("com.blik.") {
                    try? fm.removeItem(atPath: "\(home)/Library/Caches/\(cache)")
                }
            }
        }

        HelperLogger.log("пользовательские данные очищены")
    }
}
