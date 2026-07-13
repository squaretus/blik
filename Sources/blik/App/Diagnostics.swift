import BlikCore
import Foundation

/// Диагностический вывод для отладки SMC-ключей.
enum Diagnostics {
    static func run(connection: SMCConnection) {
        print("=== blik диагностика SMC ===\n")

        // Get total key count
        var totalKeys = 0
        if let (bytes, _, _) = try? connection.readKey("#KEY") {
            totalKeys = Int(UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3))
            print("Всего ключей в SMC: \(totalKeys)\n")
        }

        // Scan ALL keys and show Fan (F*) and Temperature (T*) related ones
        let scanCount = totalKeys > 0 ? totalKeys : 500
        var fanKeys: [(index: Int, key: String, typeStr: String, dataSize: UInt32, bytes: SMCBytes)] = []
        var tempKeys: [(index: Int, key: String, typeStr: String, dataSize: UInt32, bytes: SMCBytes)] = []
        for i in 0..<scanCount {
            do {
                var input = SMCParamStruct()
                input.data8 = SMCSelector.kSMCGetKeyFromIndex.rawValue
                input.data32 = UInt32(i)
                let output = try connection.callSMC(input: &input)
                guard output.key != 0 else { continue }
                let key = SMCFormat.fourCharCodeToString(output.key)

                if let (bytes, dataSize, dataType) = try? connection.readKey(key), dataSize > 0 {
                    let typeStr = SMCFormat.fourCharCodeToString(dataType)
                    let entry = (index: i, key: key, typeStr: typeStr, dataSize: dataSize, bytes: bytes)

                    if key.hasPrefix("F") {
                        fanKeys.append(entry)
                    } else if key.hasPrefix("T") {
                        tempKeys.append(entry)
                    }
                }
            } catch {
                continue
            }
        }

        // Print fan keys
        print("--- Все ключи вентиляторов (F*) ---")
        for entry in fanKeys {
            let rawHex = bytesToHex(entry.bytes, count: Int(min(entry.dataSize, 4)))
            let decoded = decodeValue(bytes: entry.bytes, typeStr: entry.typeStr, dataSize: entry.dataSize)
            print("  \(entry.key): type=\(entry.typeStr) size=\(entry.dataSize) raw=[\(rawHex)] → \(decoded)")
        }

        // Print temperature keys
        print("\n--- Все температурные ключи (T*) ---")
        for entry in tempKeys {
            let rawHex = bytesToHex(entry.bytes, count: Int(min(entry.dataSize, 4)))
            let decoded = decodeValue(bytes: entry.bytes, typeStr: entry.typeStr, dataSize: entry.dataSize)
            print("  \(entry.key): type=\(entry.typeStr) size=\(entry.dataSize) raw=[\(rawHex)] → \(decoded)")
        }

        print("\n=== конец диагностики ===")
    }

    private static func readAndPrint(key: String, connection: SMCConnection) {
        do {
            let (bytes, dataSize, dataType) = try connection.readKey(key)
            guard dataSize > 0 else {
                print("\(key): пустой (size=0)")
                return
            }
            let typeStr = SMCFormat.fourCharCodeToString(dataType)
            let rawHex = bytesToHex(bytes, count: Int(min(dataSize, 8)))
            let decoded = decodeValue(bytes: bytes, typeStr: typeStr, dataSize: dataSize)
            print("\(key): type=\(typeStr) size=\(dataSize) raw=[\(rawHex)] → \(decoded)")
        } catch {
            // Silently skip not-found keys
        }
    }

    private static func scanKeys(connection: SMCConnection, count: Int) {
        for i in 0..<count {
            do {
                var input = SMCParamStruct()
                input.data8 = SMCSelector.kSMCGetKeyFromIndex.rawValue
                input.data32 = UInt32(i)
                let output = try connection.callSMC(input: &input)
                let key = SMCFormat.fourCharCodeToString(output.key)
                guard key != "\0\0\0\0" && output.key != 0 else { continue }

                // Only show T* (temperature) and F* (fan) keys
                if key.hasPrefix("T") || key.hasPrefix("F") {
                    // Try reading the value
                    if let (bytes, dataSize, dataType) = try? connection.readKey(key), dataSize > 0 {
                        let typeStr = SMCFormat.fourCharCodeToString(dataType)
                        let rawHex = bytesToHex(bytes, count: Int(min(dataSize, 4)))
                        let decoded = decodeValue(bytes: bytes, typeStr: typeStr, dataSize: dataSize)
                        print("[\(String(format: "%3d", i))] \(key): type=\(typeStr) size=\(dataSize) raw=[\(rawHex)] → \(decoded)")
                    }
                }
            } catch {
                continue
            }
        }
    }

    private static func bytesToHex(_ bytes: SMCBytes, count: Int) -> String {
        let all: [UInt8] = [
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
        ]
        return all.prefix(count).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func decodeValue(bytes: SMCBytes, typeStr: String, dataSize: UInt32) -> String {
        if typeStr == "flt " {
            return String(format: "%.2f (flt)", SMCFormat.fltToDouble((bytes.0, bytes.1, bytes.2, bytes.3)))
        } else if typeStr == "fpe2" {
            return String(format: "%.2f (fpe2)", SMCFormat.fpe2ToDouble((bytes.0, bytes.1)))
        } else if typeStr == "sp78" {
            return String(format: "%.2f (sp78)", SMCFormat.sp78ToDouble((bytes.0, bytes.1)))
        } else if typeStr == "ui8 " {
            return "\(bytes.0) (ui8)"
        } else if typeStr == "ui16" {
            return "\((UInt16(bytes.0) << 8) | UInt16(bytes.1)) (ui16)"
        } else if typeStr == "flag" {
            return "\(bytes.0) (flag)"
        }
        return "? (type=\(typeStr))"
    }
}
