import SwiftUI

/// Иконки приложения на базе SF Symbols.
public enum AppIcons {
    public struct GridIcon: View {
        public init() {}
        public var body: some View {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14, weight: .regular))
        }
    }

    public struct ThermometerIcon: View {
        public init() {}
        public var body: some View {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 14, weight: .regular))
        }
    }

    public struct SettingsIcon: View {
        public init() {}
        public var body: some View {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .regular))
        }
    }

    public struct SidebarIcon: View {
        public init() {}
        public var body: some View {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .regular))
        }
    }

    public struct FanIcon: View {
        public init() {}
        public var body: some View {
            Image(systemName: "fanblades")
                .font(.system(size: 12, weight: .regular))
        }
    }
}
