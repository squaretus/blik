import Foundation

public class SMCWriter {
    private let connection: SMCConnection
    private let log: (String) -> Void
    private var modifiedFans: Set<Int> = []
    private var ftstUnlocked = false

    public init(connection: SMCConnection, log: @escaping (String) -> Void = { _ in }) {
        self.connection = connection
        self.log = log
    }

    // MARK: - Unlock

    private func ensureUnlocked() throws {
        guard !ftstUnlocked else { return }

        var bytes = smcBytesZero
        bytes.0 = 1
        try connection.writeKey("Ftst", dataType: SMCFormat.fourCharCode("ui8 "), bytes: bytes, dataSize: 1)
        ftstUnlocked = true
        log("SMCWriter: Ftst=1 (unlock)")

        // 5s is needed on M4 — thermalmonitord takes time to release F{n}Md
        Thread.sleep(forTimeInterval: 5.0)
        log("SMCWriter: waited 5s for mode transition")
    }

    // MARK: - Fan Speed Control

    public func setFanSpeed(fan: Int, rpm: Double) throws {
        let key = "F\(fan)Tg"
        let (_, dataSize, dataType) = try connection.readKey(key)

        var bytes = smcBytesZero

        if dataType == SMCFormat.fourCharCode("flt ") {
            let flt = SMCFormat.doubleToFlt(rpm)
            bytes.0 = flt.0; bytes.1 = flt.1; bytes.2 = flt.2; bytes.3 = flt.3
        } else {
            let fpe2 = SMCFormat.doubleToFpe2(rpm)
            bytes.0 = fpe2.0; bytes.1 = fpe2.1
        }

        try connection.writeKey(key, dataType: dataType, bytes: bytes, dataSize: dataSize)
        modifiedFans.insert(fan)
        log("SMCWriter: \(key) = \(Int(rpm)) RPM")
    }

    public func reinforceSpeed(fan: Int, rpm: Double) {
        do {
            try setFanSpeed(fan: fan, rpm: rpm)
        } catch {
            log("SMCWriter: reinforceSpeed fan \(fan) failed: \(error)")
        }
    }

    // MARK: - Preset Speed Control

    /// Устанавливает скорость всех кулеров по проценту (0=авто, 25/50/75/100=ручной).
    /// RPM рассчитывается как min + (max - min) * percentage / 100 для каждого кулера.
    public func setAllFansSpeed(percentage: Int, fans: [FanInfo]) throws {
        if percentage == 0 {
            restoreAutoMode(fanCount: fans.count)
            return
        }

        let fraction = Double(percentage) / 100.0
        for fan in fans {
            let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * fraction
            if !fan.isForced {
                try setForcedMode(fan: fan.id, enabled: true)
            }
            try setFanSpeed(fan: fan.id, rpm: rpm)
        }
    }

    // MARK: - Fan Mode

    public func setForcedMode(fan: Int, enabled: Bool) throws {
        if enabled {
            try ensureUnlocked()

            var bytes = smcBytesZero
            bytes.0 = 1
            // Retry F{n}Md write — thermalmonitord may need extra time to release
            var lastError: Error?
            for attempt in 1...5 {
                do {
                    try connection.writeKey("F\(fan)Md", dataType: SMCFormat.fourCharCode("ui8 "), bytes: bytes, dataSize: 1)
                    modifiedFans.insert(fan)
                    log("SMCWriter: F\(fan)Md=1 (forced)")
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    log("SMCWriter: F\(fan)Md=1 attempt \(attempt)/5 failed: \(error)")
                    if attempt < 5 {
                        Thread.sleep(forTimeInterval: 2.0)
                    }
                }
            }
            if let error = lastError { throw error }
        } else {
            let bytes = smcBytesZero
            try connection.writeKey("F\(fan)Md", dataType: SMCFormat.fourCharCode("ui8 "), bytes: bytes, dataSize: 1)
            modifiedFans.remove(fan)
            log("SMCWriter: F\(fan)Md=0 (auto)")
        }
    }

    // MARK: - Restore

    public func restoreAutoMode(fanCount: Int? = nil) {
        let count = fanCount ?? (modifiedFans.max().map { $0 + 1 } ?? 2)
        log("SMCWriter: Восстановление авто-режима для \(count) вентиляторов (tracked: \(modifiedFans.count))")

        if ftstUnlocked {
            // Already unlocked — just reset F{n}Md=0 (no delay needed)
            for fan in 0..<count {
                do {
                    try connection.writeKey("F\(fan)Md", dataType: SMCFormat.fourCharCode("ui8 "), bytes: smcBytesZero, dataSize: 1)
                    log("SMCWriter: F\(fan)Md=0 (restored)")
                } catch {
                    log("SMCWriter: F\(fan)Md restore failed: \(error)")
                }
            }
        }
        // else: not unlocked = system mode, F{n}Md is already 3 (system-controlled)
        // No need to write F{n}Md — just ensure Ftst=0

        // Release control back to thermalmonitord
        do {
            try connection.writeKey("Ftst", dataType: SMCFormat.fourCharCode("ui8 "), bytes: smcBytesZero, dataSize: 1)
            ftstUnlocked = false
            log("SMCWriter: Ftst=0 (restored)")
        } catch {
            log("SMCWriter: Ftst restore failed: \(error)")
        }

        modifiedFans.removeAll()
    }

    public var modifiedFanIds: Set<Int> { modifiedFans }
}
