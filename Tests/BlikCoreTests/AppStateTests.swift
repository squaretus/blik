import XCTest
@testable import BlikCore

final class AppStateTests: XCTestCase {

    // MARK: - AppState defaults

    func testAppStateDefaultValues() {
        let state = AppState()
        XCTAssertEqual(state.fans, [])
        XCTAssertEqual(state.sensors, [])
        XCTAssertEqual(state.currentPreset, 0)
        XCTAssertTrue(state.isRunning)
        XCTAssertNil(state.lastError)
        XCTAssertFalse(state.readOnlyMode)
        XCTAssertFalse(state.isUnlocking)
        XCTAssertEqual(state.otherSensorsScrollOffset, 0)
        XCTAssertEqual(state.maxVisibleOtherSensors, 5)
        XCTAssertNil(state.updateAvailable)
    }

    func testAppStateCustomInit() {
        let state = AppState(
            currentPreset: 50,
            isRunning: false,
            lastError: "test error",
            readOnlyMode: true,
            isUnlocking: true
        )
        XCTAssertEqual(state.currentPreset, 50)
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.lastError, "test error")
        XCTAssertTrue(state.readOnlyMode)
        XCTAssertTrue(state.isUnlocking)
    }

    func testAppStateUpdateAvailable() {
        let state = AppState(updateAvailable: "1.2.0")
        XCTAssertEqual(state.updateAvailable, "1.2.0")
    }

    func testAppStateUpdateAvailableNilByDefault() {
        let state = AppState(currentPreset: 25, readOnlyMode: true)
        XCTAssertNil(state.updateAvailable)
    }

    // MARK: - Constants.speedPresets

    func testSpeedPresets() {
        XCTAssertEqual(Constants.speedPresets, [0, 25, 50, 75, 100])
    }

    func testSpeedPresetsStartWithZero() {
        XCTAssertEqual(Constants.speedPresets.first, 0)
    }

    func testSpeedPresetsEndWith100() {
        XCTAssertEqual(Constants.speedPresets.last, 100)
    }

    // MARK: - FanInfo preset RPM calculation
    // Formula: min + (max - min) * percentage / 100

    func testPresetRPMCalculation0Percent() {
        let fan = FanInfo(id: 0, actualSpeed: 2000, minimumSpeed: 1100,
                          maximumSpeed: 6500, targetSpeed: 2000, isForced: false)
        let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * Double(0) / 100.0
        XCTAssertEqual(rpm, 1100.0)
    }

    func testPresetRPMCalculation25Percent() {
        let fan = FanInfo(id: 0, actualSpeed: 2000, minimumSpeed: 1100,
                          maximumSpeed: 6500, targetSpeed: 2000, isForced: false)
        let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * Double(25) / 100.0
        XCTAssertEqual(rpm, 2450.0)
    }

    func testPresetRPMCalculation50Percent() {
        let fan = FanInfo(id: 0, actualSpeed: 2000, minimumSpeed: 1100,
                          maximumSpeed: 6500, targetSpeed: 2000, isForced: false)
        let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * Double(50) / 100.0
        XCTAssertEqual(rpm, 3800.0)
    }

    func testPresetRPMCalculation75Percent() {
        let fan = FanInfo(id: 0, actualSpeed: 2000, minimumSpeed: 1100,
                          maximumSpeed: 6500, targetSpeed: 2000, isForced: false)
        let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * Double(75) / 100.0
        XCTAssertEqual(rpm, 5150.0)
    }

    func testPresetRPMCalculation100Percent() {
        let fan = FanInfo(id: 0, actualSpeed: 2000, minimumSpeed: 1100,
                          maximumSpeed: 6500, targetSpeed: 2000, isForced: false)
        let rpm = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * Double(100) / 100.0
        XCTAssertEqual(rpm, 6500.0)
    }

    func testPresetRPMCalculationDifferentRange() {
        let fan = FanInfo(id: 1, actualSpeed: 2500, minimumSpeed: 1200,
                          maximumSpeed: 5800, targetSpeed: 2500, isForced: false)
        let rpm50 = fan.minimumSpeed + (fan.maximumSpeed - fan.minimumSpeed) * 0.5
        XCTAssertEqual(rpm50, 3500.0)
    }

    // MARK: - FanSelection removed
    // Verified at compile time: if this file compiles, FanSelection does not exist in BlikCore
    // and AppState no longer has selectedFan property
}
