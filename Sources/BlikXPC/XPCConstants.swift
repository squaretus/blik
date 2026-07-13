import Foundation

public enum BlikXPCConstants {
    public static let machServiceName = "com.blik.helper"

    /// Версия XPC-протокола хелпера. Развязана с маркетинговой версией приложения
    /// (`Constants.appVersion`): `build.sh` её НЕ подставляет. Бампается вручную
    /// только при изменении XPC-поверхности (новые методы/контракты) — capability-гейты
    /// клиента (`Constants.minHelperVersionFor*`) сравниваются именно с ней.
    public static let protocolVersion = "2.11.0"
}
