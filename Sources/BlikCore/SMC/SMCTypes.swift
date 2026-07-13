import Foundation
import IOKit

// MARK: - SMCFormat (конверсии данных)

public enum SMCFormat {
    public static func fourCharCode(_ value: String) -> UInt32 {
        var result: UInt32 = 0
        for char in value.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    public static func fourCharCodeToString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// FPE2: 14 integer bits + 2 fractional bits. Used for fan RPM.
    public static func fpe2ToDouble(_ bytes: (UInt8, UInt8)) -> Double {
        let value = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        return Double(value) / 4.0
    }

    public static func doubleToFpe2(_ value: Double) -> (UInt8, UInt8) {
        let raw = UInt16(max(0, min(value * 4.0, Double(UInt16.max))))
        return (UInt8(raw >> 8), UInt8(raw & 0xFF))
    }

    /// SP78: signed 7.8 fixed point. Used for temperatures in Celsius.
    public static func sp78ToDouble(_ bytes: (UInt8, UInt8)) -> Double {
        let value = Int16(bitPattern: (UInt16(bytes.0) << 8) | UInt16(bytes.1))
        return Double(value) / 256.0
    }

    /// FLT: 32-bit IEEE 754 float in little-endian byte order (Apple Silicon SMC).
    public static func fltToDouble(_ bytes: (UInt8, UInt8, UInt8, UInt8)) -> Double {
        let bits = UInt32(bytes.0) | (UInt32(bytes.1) << 8) | (UInt32(bytes.2) << 16) | (UInt32(bytes.3) << 24)
        let value = Double(Float(bitPattern: bits))
        guard value.isFinite else { return 0 }
        return value
    }

    public static func doubleToFlt(_ value: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        let bits = Float(value).bitPattern
        return (UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF))
    }
}

// MARK: - SMC Data Types

public typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

public let smcBytesZero: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

public struct SMCKeyData_vers_t {
    public var major: UInt8 = 0
    public var minor: UInt8 = 0
    public var build: UInt8 = 0
    public var reserved: UInt8 = 0
    public var release: UInt16 = 0

    public init() {}
}

public struct SMCKeyData_pLimitData_t {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0

    public init() {}
}

public struct SMCKeyData_keyInfo_t {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0

    public init() {}
}

// 80-byte struct matching the kernel SMC interface
public struct SMCParamStruct {
    public var key: UInt32 = 0
    public var vers: SMCKeyData_vers_t = SMCKeyData_vers_t()
    public var pLimitData: SMCKeyData_pLimitData_t = SMCKeyData_pLimitData_t()
    public var keyInfo: SMCKeyData_keyInfo_t = SMCKeyData_keyInfo_t()
    public var padding: UInt16 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: SMCBytes = smcBytesZero

    public init() {}
}

// MARK: - SMC Selectors

public enum SMCSelector: UInt8 {
    case kSMCHandleYPCEvent = 2
    case kSMCReadKey = 5
    case kSMCWriteKey = 6
    case kSMCGetKeyFromIndex = 8
    case kSMCGetKeyInfo = 9
}

// MARK: - Extensions

extension Double {
    public func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - SMC Errors

public enum SMCError: LocalizedError {
    case serviceNotFound
    case connectionFailed(kern_return_t)
    case readFailed(key: String, kern_return_t)
    case writeFailed(key: String, kern_return_t)
    case keyNotFound(String)
    case notPrivileged

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "AppleSMC сервис не найден. Возможно, это неподдерживаемый Mac."
        case .connectionFailed(let code):
            return "Не удалось подключиться к SMC (код: \(code))"
        case .readFailed(let key, let code):
            return "Ошибка чтения ключа '\(key)' (код: \(code))"
        case .writeFailed(let key, let code):
            return "Ошибка записи ключа '\(key)' (код: \(code))"
        case .keyNotFound(let key):
            return "Ключ '\(key)' не найден в SMC"
        case .notPrivileged:
            return "Недостаточно прав для записи в SMC. Запустите с sudo."
        }
    }
}
