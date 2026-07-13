import XCTest
@testable import BlikCore

final class SMCTypesTests: XCTestCase {

    // MARK: - FourCharCode

    func testFourCharCode() {
        XCTAssertEqual(SMCFormat.fourCharCode("FNum"), 0x464E756D)
        XCTAssertEqual(SMCFormat.fourCharCode("F0Ac"), 0x46304163)
        XCTAssertEqual(SMCFormat.fourCharCode("FS! "), 0x46532120)
    }

    func testFourCharCodeToString() {
        XCTAssertEqual(SMCFormat.fourCharCodeToString(0x464E756D), "FNum")
        XCTAssertEqual(SMCFormat.fourCharCodeToString(0x46304163), "F0Ac")
    }

    func testFourCharCodeRoundTrip() {
        let keys = ["FNum", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "FS! ", "TC0D", "TG0D"]
        for key in keys {
            XCTAssertEqual(SMCFormat.fourCharCodeToString(SMCFormat.fourCharCode(key)), key)
        }
    }

    // MARK: - FPE2 Conversions

    func testFpe2ToDouble() {
        XCTAssertEqual(SMCFormat.fpe2ToDouble((0x00, 0x00)), 0.0)
        XCTAssertEqual(SMCFormat.fpe2ToDouble((0x0F, 0xA0)), 1000.0)
        XCTAssertEqual(SMCFormat.fpe2ToDouble((0x36, 0xB0)), 3500.0)
    }

    func testDoubleToFpe2() {
        let (h, l) = SMCFormat.doubleToFpe2(1000.0)
        XCTAssertEqual(h, 0x0F)
        XCTAssertEqual(l, 0xA0)

        let (h2, l2) = SMCFormat.doubleToFpe2(3500.0)
        XCTAssertEqual(h2, 0x36)
        XCTAssertEqual(l2, 0xB0)
    }

    func testFpe2RoundTrip() {
        let values: [Double] = [0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 5000, 6000]
        for rpm in values {
            let encoded = SMCFormat.doubleToFpe2(rpm)
            let decoded = SMCFormat.fpe2ToDouble(encoded)
            XCTAssertEqual(decoded, rpm, accuracy: 0.5, "Round-trip failed for \(rpm) RPM")
        }
    }

    func testDoubleToFpe2ClampNegative() {
        let (h, l) = SMCFormat.doubleToFpe2(-100.0)
        XCTAssertEqual(SMCFormat.fpe2ToDouble((h, l)), 0.0)
    }

    // MARK: - SP78 Conversions

    func testSp78ToDouble() {
        XCTAssertEqual(SMCFormat.sp78ToDouble((0x00, 0x00)), 0.0)
        XCTAssertEqual(SMCFormat.sp78ToDouble((0x2D, 0x00)), 45.0)
        XCTAssertEqual(SMCFormat.sp78ToDouble((0x2D, 0x80)), 45.5)
    }

    func testSp78NegativeTemperature() {
        XCTAssertEqual(SMCFormat.sp78ToDouble((0xFF, 0x00)), -1.0)
    }

    // MARK: - FLT Conversion

    func testFltToDouble() {
        let value = SMCFormat.fltToDouble((0x00, 0x00, 0x34, 0x42))
        XCTAssertEqual(value, 45.0, accuracy: 0.01)

        let battery = SMCFormat.fltToDouble((0x00, 0x00, 0x12, 0x42))
        XCTAssertEqual(battery, 36.5, accuracy: 0.01)

        let fanSpeed = SMCFormat.fltToDouble((0x2E, 0xA5, 0x10, 0x45))
        XCTAssertEqual(fanSpeed, 2314.0, accuracy: 1.0)
    }

    func testFltToDoubleZero() {
        XCTAssertEqual(SMCFormat.fltToDouble((0x00, 0x00, 0x00, 0x00)), 0.0)
    }

    func testDoubleToFlt() {
        let bytes = SMCFormat.doubleToFlt(2317.0)
        let decoded = SMCFormat.fltToDouble(bytes)
        XCTAssertEqual(decoded, 2317.0, accuracy: 0.1)
    }

    func testFltRoundTrip() {
        let values: [Double] = [0, 36.5, 45.0, 72.9, 2317.0, 7826.0]
        for val in values {
            let encoded = SMCFormat.doubleToFlt(val)
            let decoded = SMCFormat.fltToDouble(encoded)
            XCTAssertEqual(decoded, val, accuracy: 0.1, "FLT round-trip failed for \(val)")
        }
    }

    // MARK: - SensorGroup

    func testSensorGroupOrder() {
        XCTAssertTrue(SensorGroup.cpuCores < .npuECores)
        XCTAssertTrue(SensorGroup.npuECores < .gpuCores)
        XCTAssertTrue(SensorGroup.gpuCores < .other)
    }

    func testSensorGroupTitles() {
        XCTAssertEqual(SensorGroup.cpuCores.title, "CPU Ядра")
        XCTAssertEqual(SensorGroup.npuECores.title, "E-Cores")
        XCTAssertEqual(SensorGroup.gpuCores.title, "GPU")
        XCTAssertEqual(SensorGroup.other.title, "Прочие датчики")
    }
}
