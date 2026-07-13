import Foundation

public struct StateSnapshot: Equatable, Codable {
    public let fans: [FanInfo]
    public let sensors: [SensorInfo]

    public init(fans: [FanInfo], sensors: [SensorInfo]) {
        self.fans = fans
        self.sensors = sensors
    }
}
