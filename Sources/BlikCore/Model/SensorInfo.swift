import Foundation

public enum SensorGroup: Int, CaseIterable, Comparable, Codable {
    case cpuCores = 0
    case npuECores = 1
    case gpuCores = 2
    case other = 3

    public var title: String {
        switch self {
        case .cpuCores: return "CPU Ядра"
        case .npuECores: return "E-Cores"
        case .gpuCores: return "GPU"
        case .other: return "Прочие датчики"
        }
    }

    public static func < (lhs: SensorGroup, rhs: SensorGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SensorInfo: Equatable, Codable {
    public let key: String
    public let name: String
    public let group: SensorGroup
    public var temperature: Double

    public init(key: String, name: String, group: SensorGroup, temperature: Double) {
        self.key = key
        self.name = name
        self.group = group
        self.temperature = temperature
    }
}

public struct AppState: Equatable {
    public var fans: [FanInfo]
    public var sensors: [SensorInfo]
    public var currentPreset: Int
    public var isRunning: Bool
    public var lastError: String?
    public var readOnlyMode: Bool
    public var isUnlocking: Bool
    public var otherSensorsScrollOffset: Int
    public var maxVisibleOtherSensors: Int
    public var updateAvailable: String?

    public init(fans: [FanInfo] = [], sensors: [SensorInfo] = [],
                currentPreset: Int = 0, isRunning: Bool = true,
                lastError: String? = nil, readOnlyMode: Bool = false,
                isUnlocking: Bool = false,
                otherSensorsScrollOffset: Int = 0, maxVisibleOtherSensors: Int = 5,
                updateAvailable: String? = nil) {
        self.fans = fans
        self.sensors = sensors
        self.currentPreset = currentPreset
        self.isRunning = isRunning
        self.lastError = lastError
        self.readOnlyMode = readOnlyMode
        self.isUnlocking = isUnlocking
        self.otherSensorsScrollOffset = otherSensorsScrollOffset
        self.maxVisibleOtherSensors = maxVisibleOtherSensors
        self.updateAvailable = updateAvailable
    }
}
