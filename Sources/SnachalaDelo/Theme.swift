import AppKit
import SwiftUI

/// Цвета и шрифты как на визитке «Сначала дело» (светлая и тёмная тема).
enum Theme {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let bg       = dyn(0xEEF0EC, 0x121614)
    static let surface  = dyn(0xFFFFFF, 0x1E2521)
    static let surface2 = dyn(0xF6F7F4, 0x252D28)
    static let fg       = dyn(0x17201B, 0xEAF0EB)
    static let fg2      = dyn(0x56605A, 0xA6B0A9)
    static let fg3      = dyn(0x8A938D, 0x717B74)
    static let line     = dyn(0xD9DDD6, 0x313A34)
    static let lock     = dyn(0xD63A4A, 0xFF5E6C)
    static let lockSoft = dyn(0xFBE4E6, 0x3A1E22)
    static let free     = dyn(0x16936B, 0x3DD39E)
    static let freeSoft = dyn(0xDDF3EA, 0x163128)
    static let warn     = dyn(0xC77A0A, 0xF0A53A)
    static let warnSoft = dyn(0xFBEFD9, 0x3A2C15)

    static let lockNS = NSColor(name: nil) { a in
        NSColor(hex: a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0xFF5E6C : 0xD63A4A)
    }
    static let freeNS = NSColor(name: nil) { a in
        NSColor(hex: a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0x3DD39E : 0x16936B)
    }
    static let warnNS = NSColor(name: nil) { a in
        NSColor(hex: a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0xF0A53A : 0xC77A0A)
    }

    // MARK: Fonts (Unbounded — заголовки, Onest — текст; если нет — системные)

    enum W { case regular, medium, semibold, bold }

    static func display(_ size: CGFloat, _ w: W = .bold) -> Font {
        let name: String
        switch w {
        case .regular: name = "Unbounded-Regular"
        case .medium: name = "Unbounded-Regular_Medium"
        case .semibold: name = "Unbounded-Regular_SemiBold"
        case .bold: name = "Unbounded-Regular_Bold"
        }
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: sysWeight(w), design: .rounded)
    }

    static func body(_ size: CGFloat, _ w: W = .regular) -> Font {
        let name: String
        switch w {
        case .regular: name = "Onest-Regular"
        case .medium: name = "Onest-Medium"
        case .semibold: name = "Onest-SemiBold"
        case .bold: name = "Onest-Bold"
        }
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: sysWeight(w))
    }

    private static func sysWeight(_ w: W) -> Font.Weight {
        switch w {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Кнопка с заливкой цветом текста, как «Добавить» на визитке.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .foregroundColor(Theme.surface)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fg))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// Обводная кнопка, как «Передышка 15 мин».
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12.5, .semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundColor(Theme.fg)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

/// Текстовая кнопка приглушённым цветом.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12.5, .medium))
            .foregroundColor(Theme.fg2)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
