import SwiftUI

/// Палитра и метрики из прототипа NotchClaude (Claude Design).
enum Theme {
    static let accent = Color(hex: 0xD97757)          // фирменный оранжевый Claude
    static let accentDeep = Color(hex: 0xB45F43)      // левый край градиента шкалы
    static let warning = Color(hex: 0xFF9F0A)
    static let critical = Color(hex: 0xFF5449)
    static let activeDot = Color(hex: 0x34C759)       // точка активности на островке
    static let activeDotPanel = Color(hex: 0x7FD48A)  // она же в панели и шкала недели

    static let text = Color(hex: 0xF5EFE8)            // тёплый белый
    static func text(_ opacity: Double) -> Color { text.opacity(opacity) }
    static let track = text.opacity(0.08)             // подложка шкал и полос
    static let hairline = text.opacity(0.08)          // линия под вкладками

    static let islandWidth: CGFloat = 224
    static let islandHeight: CGFloat = 30
    static let islandRadius: CGFloat = 15
    static let panelWidth: CGFloat = 440
    static let panelRadius: CGFloat = 22
    static let panelHeight: CGFloat = 268             // без плашки алерта
    static let panelHeightAlert: CGFloat = 300        // с плашкой

    static func accent(for level: AlertLevel) -> Color {
        switch level {
        case .none: accent
        case .warning: warning
        case .critical: critical
        }
    }
}

/// Заполнение в процентах. Округление одно на весь интерфейс: островок и панель
/// показывают одну и ту же величину и не должны расходиться на процент.
func pct(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }

/// Компактное представление больших чисел: 950 / 12.3k / 4.51M.
func fmt(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

extension Font {
    /// Цифры в прототипе всегда моношириной.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
