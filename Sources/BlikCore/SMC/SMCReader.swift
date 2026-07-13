import Foundation

public class SMCReader {
    private let connection: SMCConnection

    public init(connection: SMCConnection) {
        self.connection = connection
    }

    // MARK: - Fan Reading

    public func readFanCount() throws -> Int {
        let (bytes, _, _) = try connection.readKey("FNum")
        return Int(bytes.0)
    }

    private func readFanValue(fan: Int, suffix: String) throws -> Double {
        let key = "F\(fan)\(suffix)"
        let (bytes, _, dataType) = try connection.readKey(key)
        if dataType == SMCFormat.fourCharCode("flt ") {
            return SMCFormat.fltToDouble((bytes.0, bytes.1, bytes.2, bytes.3))
        }
        return SMCFormat.fpe2ToDouble((bytes.0, bytes.1))
    }

    public func readFanSpeed(fan: Int) throws -> Double { try readFanValue(fan: fan, suffix: "Ac") }
    public func readFanMinSpeed(fan: Int) throws -> Double { try readFanValue(fan: fan, suffix: "Mn") }
    public func readFanMaxSpeed(fan: Int) throws -> Double { try readFanValue(fan: fan, suffix: "Mx") }
    public func readFanTargetSpeed(fan: Int) throws -> Double { try readFanValue(fan: fan, suffix: "Tg") }

    /// Read fan mode: F{n}Md (ui8): 0=auto, 1=forced, 3=system.
    /// Returns true only for forced=1 (user-set manual mode).
    /// F0Md=3 (system/thermalmonitord) and F0Md=0 (auto) both return false.
    public func readFanMode(fan: Int) -> Bool {
        let key = "F\(fan)Md"
        guard let (bytes, dataSize, _) = try? connection.readKey(key), dataSize > 0 else {
            return false
        }
        return bytes.0 == 1
    }

    public func readAllFans() throws -> [FanInfo] {
        let count = try readFanCount()
        var fans: [FanInfo] = []

        for i in 0..<count {
            let actual = (try? readFanSpeed(fan: i)) ?? 0
            let min = (try? readFanMinSpeed(fan: i)) ?? 0
            let max = (try? readFanMaxSpeed(fan: i)) ?? 0
            let target = (try? readFanTargetSpeed(fan: i)) ?? actual
            let isForced = readFanMode(fan: i)

            fans.append(FanInfo(
                id: i,
                actualSpeed: actual,
                minimumSpeed: min,
                maximumSpeed: max,
                targetSpeed: target,
                isForced: isForced
            ))
        }

        return fans
    }

    // MARK: - Temperature Reading

    public func readTemperature(key: String) -> Double? {
        guard let (bytes, _, dataType) = try? connection.readKey(key) else {
            return nil
        }
        if dataType == SMCFormat.fourCharCode("flt ") {
            let value = SMCFormat.fltToDouble((bytes.0, bytes.1, bytes.2, bytes.3))
            return value > 0 && value < 150 ? value : nil
        }
        let value = SMCFormat.sp78ToDouble((bytes.0, bytes.1))
        return value > 0 && value < 150 ? value : nil
    }

    /// Known temperature sensor keys for Apple Silicon M4 (and fallbacks for Intel).
    /// Keys are probed at startup — unavailable keys are silently skipped.
    public static let knownSensors: [(key: String, name: String, group: SensorGroup)] = [
        // CPU Performance Cores — all individual + aggregates
        ("TPD0", "P-Core 0", .cpuCores),
        ("TPD1", "P-Core 1", .cpuCores),
        ("TPD2", "P-Core 2", .cpuCores),
        ("TPD3", "P-Core 3", .cpuCores),
        ("TPD4", "P-Core 4", .cpuCores),
        ("TPD5", "P-Core 5", .cpuCores),
        ("TPD6", "P-Core 6", .cpuCores),
        ("TPD7", "P-Core 7", .cpuCores),
        ("TPD8", "P-Core 8", .cpuCores),
        ("TPD9", "P-Core 9", .cpuCores),
        ("TPDa", "P-Core 10", .cpuCores),
        ("TPDb", "P-Core 11", .cpuCores),
        ("TPDc", "P-Core 12", .cpuCores),
        ("TPDd", "P-Core 13", .cpuCores),
        ("TPDe", "P-Core 14", .cpuCores),
        ("TPDf", "P-Core 15", .cpuCores),
        ("TPDX", "P-Core Max", .cpuCores),
        ("TCDX", "CPU Die Max", .cpuCores),
        ("TCMz", "CPU Hotspot", .cpuCores),
        ("TCHP", "CPU Package", .cpuCores),
        // Intel fallback
        ("TC0D", "CPU Die", .cpuCores),
        ("TC0P", "CPU Package", .cpuCores),

        // E-Cores
        ("Te04", "E-Cluster 0", .npuECores),
        ("Te05", "E-Cluster 1", .npuECores),
        ("Te06", "E-Cluster 2", .npuECores),
        ("Te0R", "E-Core 0R", .npuECores),
        ("Te0S", "E-Core 0S", .npuECores),
        ("Te0T", "E-Core 0T", .npuECores),
        ("Tex0", "E-Max 0", .npuECores),
        ("Tex1", "E-Max 1", .npuECores),
        ("Tex2", "E-Max 2", .npuECores),
        ("Tex3", "E-Max 3", .npuECores),
        ("TCMb", "E-Core Max", .npuECores),

        // GPU
        ("Tg05", "GPU Hotspot", .gpuCores),
        ("Tg04", "GPU Zone 0", .gpuCores),
        ("Tg0S", "GPU Zone 1", .gpuCores),
        ("Tg0Y", "GPU Zone 2", .gpuCores),
        ("Tg0k", "GPU Zone 3", .gpuCores),
        ("Tg0z", "GPU Zone 4", .gpuCores),
        ("Tg1V", "GPU Zone 5", .gpuCores),
        ("Tg1l", "GPU Zone 6", .gpuCores),
        ("Tg2Q", "GPU Zone 7", .gpuCores),
        ("Tg2g", "GPU Zone 8", .gpuCores),
        ("Tg3a", "GPU Zone 9", .gpuCores),
        // Intel fallback
        ("TG0D", "GPU Die", .gpuCores),

        // Other sensors
        ("TB0T", "Battery", .other),
        ("TB1T", "Battery 1", .other),
        ("TB2T", "Battery 2", .other),
        ("Ts0P", "SSD", .other),
        ("Ts1P", "SSD 2", .other),
        ("TW0P", "WiFi", .other),
        ("TH0x", "Heatsink Max", .other),
        ("TH0a", "Heatsink A", .other),
        ("TH0b", "Heatsink B", .other),
        ("TAOL", "Ambient", .other),
        ("TMVR", "Memory VR", .other),
        ("TaLP", "Left Palm", .other),
        ("TaRF", "Right Palm", .other),
        ("TaTP", "Trackpad", .other),
    ]

    public func readAllSensors() throws -> [SensorInfo] {
        var sensors: [SensorInfo] = []

        for def in SMCReader.knownSensors {
            if let temp = readTemperature(key: def.key) {
                sensors.append(SensorInfo(
                    key: def.key,
                    name: def.name,
                    group: def.group,
                    temperature: temp
                ))
            }
        }

        // Sort by group order
        sensors.sort { $0.group.rawValue < $1.group.rawValue }
        return sensors
    }
}
