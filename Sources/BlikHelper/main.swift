import Foundation
import BlikXPC

// Привилегированный XPC-демон для управления кулерами через SMC.
// Запускается через launchd как Mach service (com.blik.helper).
// Требует root-привилегии для записи в SMC.

// Глобальные ссылки — NSXPCListener.delegate является weak,
// без strong-ссылки оптимизатор release-сборки деаллоцирует delegate.
private var _delegate: HelperDelegate!
private var _listener: NSXPCListener!

do {
    _delegate = try HelperDelegate.create()
    _listener = NSXPCListener(machServiceName: BlikXPCConstants.machServiceName)
    _listener.delegate = _delegate
    _listener.resume()
    HelperLogger.log("listening on \(BlikXPCConstants.machServiceName)")
    dispatchMain()
} catch {
    HelperLogger.log("failed to start: \(error)")
    exit(1)
}
