import Foundation

public struct FanInfo: Equatable, Codable {
    public let id: Int
    public var actualSpeed: Double
    public var minimumSpeed: Double
    public var maximumSpeed: Double
    public var targetSpeed: Double
    public var isForced: Bool

    public init(id: Int, actualSpeed: Double, minimumSpeed: Double,
                maximumSpeed: Double, targetSpeed: Double, isForced: Bool) {
        self.id = id
        self.actualSpeed = actualSpeed
        self.minimumSpeed = minimumSpeed
        self.maximumSpeed = maximumSpeed
        self.targetSpeed = targetSpeed
        self.isForced = isForced
    }
}
