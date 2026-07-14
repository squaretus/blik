import ArgumentParser
import BlikCore
import BlikXPC
import Foundation

@main
struct Blik: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Терминальный контроллер вентиляторов MacBook Pro",
        version: Constants.appVersion,
        subcommands: [ClaudeStatusline.self, MCPCommand.self]
    )

    @Flag(name: .long, help: "Только мониторинг (без управления, не требует sudo)")
    var readOnly = false

    @Flag(name: .long, help: "Однократный вывод данных и выход")
    var once = false

    @Option(name: .long, help: "Интервал опроса сенсоров в секундах")
    var interval: Double = 1.0

    @Flag(name: .long, help: "Диагностический вывод SMC-ключей")
    var diagnose = false

    @Flag(name: .long, help: "Проверить и установить обновление")
    var update = false

    mutating func run() throws {
        let isRoot = geteuid() == 0

        // Update path: проверка и установка обновления через XPC
        if update {
            let client = BlikXPCClient()
            guard client.connectAndVerify() else {
                print("⚠ Хелпер недоступен. Установите .blik через PKG-установщик.")
                throw ExitCode(1)
            }

            print("Проверка обновлений...")
            let result = UpdateService.checkAndInstall(client: client)
            switch result {
            case .available(let info):
                print("Обновление до v\(info.latestVersion) запущено. Приложение будет перезапущено.")
            case .upToDate(let version):
                print("✓ Установлена последняя версия \(version)")
            case .error(let message):
                print(message)
                throw ExitCode(1)
            }
            return
        }

        // XPC path: если не root и не read-only/once/diagnose — попытка через хелпер
        if !isRoot && !readOnly && !once && !diagnose {
            let client = BlikXPCClient()
            if client.connectAndVerify() {
                // Setup logger in current working directory
                let cwd = FileManager.default.currentDirectoryPath
                Logger.setup(directory: cwd)

                // Работа через XPC хелпер — полный TUI без sudo
                let dataSource = XPCDataSource(xpcClient: client)
                let controller = FanController(dataSource: dataSource, interval: interval)
                SignalHandler.install()
                try controller.run()
                return
            }
            // Нет хелпера и нет root
            print("⚠ Управление вентиляторами требует привилегий.")
            print("  Установите .blik через PKG-установщик или используйте: sudo blik")
            print("  Режим мониторинга: blik --read-only")
            throw ExitCode(1)
        }

        if !readOnly && !once && !diagnose && !isRoot {
            print("⚠ Управление вентиляторами требует root-прав.")
            print("  Запустите: sudo blik")
            print("  Или используйте режим мониторинга: blik --read-only")
            throw ExitCode(1)
        }

        // Setup logger in current working directory
        let cwd = FileManager.default.currentDirectoryPath
        Logger.setup(directory: cwd)

        let connection = try SMCConnection()

        if diagnose {
            Diagnostics.run(connection: connection)
            return
        }

        let reader = SMCReader(connection: connection)
        let writer = (readOnly || once) ? nil : SMCWriter(connection: connection, log: Logger.log)

        if once {
            let state = try readState(reader: reader)
            printOnce(state: state)
            return
        }

        let dataSource = SMCDataSource(reader: reader, writer: writer)
        let controller = FanController(dataSource: dataSource, interval: interval)

        SignalHandler.install()
        try controller.run()
    }

    private func readState(reader: SMCReader) throws -> AppState {
        let fans = try reader.readAllFans()
        let sensors = try reader.readAllSensors()
        return AppState(
            fans: fans,
            sensors: sensors,
            currentPreset: 0,
            isRunning: true,
            lastError: nil,
            readOnlyMode: readOnly
        )
    }

    private func printOnce(state: AppState) {
        print("Вентиляторы:")
        for fan in state.fans {
            let mode = fan.isForced ? "MANUAL" : "AUTO"
            print("  Fan \(fan.id): \(Int(fan.actualSpeed.clamped(to: 0...Constants.maxDisplayRPM))) RPM [\(Int(fan.minimumSpeed.clamped(to: 0...Constants.maxDisplayRPM)))-\(Int(fan.maximumSpeed.clamped(to: 0...Constants.maxDisplayRPM)))] \(mode)")
        }
        print()

        let grouped = Dictionary(grouping: state.sensors, by: { $0.group })
        for group in SensorGroup.allCases {
            guard let sensors = grouped[group], !sensors.isEmpty else { continue }
            print("\(group.title):")
            for sensor in sensors {
                print("  \(sensor.name): \(String(format: "%.1f", sensor.temperature))°C")
            }
            print()
        }
    }
}
