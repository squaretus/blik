import Foundation
import IOKit

public class SMCConnection {
    private var connection: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else {
            throw SMCError.serviceNotFound
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == kIOReturnSuccess else {
            throw SMCError.connectionFailed(result)
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public func callSMC(input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCSelector.kSMCHandleYPCEvent.rawValue),
            &input,
            MemoryLayout<SMCParamStruct>.size,
            &output,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(
                key: SMCFormat.fourCharCodeToString(input.key),
                result
            )
        }

        return output
    }

    /// Read an SMC key's info (data size and type).
    public func readKeyInfo(key: UInt32) throws -> SMCKeyData_keyInfo_t {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = SMCSelector.kSMCGetKeyInfo.rawValue

        let output = try callSMC(input: &input)
        return output.keyInfo
    }

    /// Read raw bytes from an SMC key.
    public func readKey(_ keyStr: String) throws -> (bytes: SMCBytes, dataSize: UInt32, dataType: UInt32) {
        let key = SMCFormat.fourCharCode(keyStr)

        // First get key info
        let info = try readKeyInfo(key: key)

        // Then read the value
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCSelector.kSMCReadKey.rawValue

        let output = try callSMC(input: &input)
        return (output.bytes, info.dataSize, info.dataType)
    }

    /// Write raw bytes to an SMC key.
    /// Must read keyInfo first to get dataAttributes — without it, SMC silently ignores writes.
    public func writeKey(_ keyStr: String, dataType: UInt32, bytes: SMCBytes, dataSize: UInt32) throws {
        let key = SMCFormat.fourCharCode(keyStr)

        // Get full key info including dataAttributes (critical for writes)
        let info = try readKeyInfo(key: key)

        var input = SMCParamStruct()
        input.key = key
        input.data8 = SMCSelector.kSMCWriteKey.rawValue
        input.keyInfo.dataSize = info.dataSize
        input.keyInfo.dataType = info.dataType
        input.keyInfo.dataAttributes = info.dataAttributes
        input.bytes = bytes

        let output = try callSMC(input: &input)
        if output.result != 0 {
            throw SMCError.writeFailed(key: keyStr, kern_return_t(output.result))
        }
    }
}
