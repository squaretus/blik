import SwiftUI

/// Логотип `.blik` — orb-точка + mono-надпись "blik".
/// Orb визуально подменяет точку перед "blik" (как в web `Logo.tsx`).
///
/// По умолчанию без размытого glow-halo (для desktop UI). Если нужен
/// hero-вариант для лендингов — передать `glow: true`.
public struct BlikLogo: View {
    public enum Size {
        case sm, md, lg, xl
        /// Размер orb — мельче font размера (~0.55), чтобы читался как «точка».
        var orb: CGFloat {
            switch self {
            case .sm: 9
            case .md: 12
            case .lg: 18
            case .xl: 22
            }
        }
        var font: Font {
            switch self {
            case .sm: .system(size: 14, design: .monospaced).weight(.medium)
            case .md: .system(size: 18, design: .monospaced).weight(.medium)
            case .lg: .system(size: 26, design: .monospaced).weight(.medium)
            case .xl: .system(size: 34, design: .monospaced).weight(.medium)
            }
        }
        var spacing: CGFloat {
            switch self {
            case .sm: 4
            case .md: 5
            case .lg: 7
            case .xl: 9
            }
        }
    }

    public let size: Size
    public let glow: Bool

    public init(size: Size = .md, glow: Bool = false) {
        self.size = size
        self.glow = glow
    }

    public var body: some View {
        HStack(spacing: size.spacing) {
            orb
            Text("blik").font(size.font).tracking(-0.5)
        }
        .fixedSize()
    }

    private var orb: some View {
        ZStack {
            if glow {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color(red: 47/255, green: 179/255, blue: 184/255).opacity(0.85), location: 0.0),
                                .init(color: Color(red: 0, green: 116/255, blue: 121/255).opacity(0.42), location: 0.30),
                                .init(color: Color(red: 0, green: 116/255, blue: 121/255).opacity(0.14), location: 0.60),
                                .init(color: Color(red: 0, green: 116/255, blue: 121/255).opacity(0), location: 1.0),
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: size.orb * 1.3
                        )
                    )
                    .frame(width: size.orb * 2.6, height: size.orb * 2.6)
                    .blur(radius: size.orb * 0.13)
            }
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 203/255, green: 243/255, blue: 242/255), location: 0.0),
                            .init(color: Color(red: 127/255, green: 220/255, blue: 222/255), location: 0.22),
                            .init(color: Color(red: 47/255, green: 179/255, blue: 184/255), location: 0.50),
                            .init(color: Color(red: 10/255, green: 122/255, blue: 126/255), location: 0.78),
                            .init(color: Color(red: 0, green: 60/255, blue: 64/255), location: 1.0),
                        ]),
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: size.orb * 0.55
                    )
                )
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(red: 0, green: 8/255, blue: 20/255).opacity(0.38), location: 0.0),
                                    .init(color: Color(red: 0, green: 8/255, blue: 20/255).opacity(0), location: 0.65),
                                ]),
                                center: UnitPoint(x: 0.78, y: 0.84),
                                startRadius: 0,
                                endRadius: size.orb * 0.55
                            )
                        )
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .frame(width: size.orb, height: size.orb)
        }
    }
}
