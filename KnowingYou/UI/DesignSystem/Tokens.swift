import AppKit
import SwiftUI

/// Color tokens for the S22 design language ("深色专业", see
/// docs/design/ui-prototype.html §07). Every token is a dynamic light/dark
/// pair resolved by the current `NSAppearance`, so views never branch on
/// color scheme themselves. Only two accent hues exist: `accent` (cyan —
/// actionable / sound is flowing) and `rec` (red — actually recording);
/// everything else is a neutral.
enum KYColor {
    static let bg = Color.ky(light: "#F4F5F7", dark: "#161618")
    static let bgDeep = Color.ky(light: "#E9EBEF", dark: "#0E0E10")
    static let surface = Color.ky(light: "#FFFFFF", dark: "#1F1F22")
    static let surface2 = Color.ky(light: "#F6F7F9", dark: "#26262A")
    static let surface3 = Color.ky(light: "#ECEEF2", dark: "#2E2E33")

    static let stroke = Color.ky(light: "#E3E5EA", dark: "#2C2C30")
    static let strokeStrong = Color.ky(light: "#D2D5DC", dark: "#3A3A40")

    static let text = Color.ky(light: "#16171A", dark: "#F2F2F4")
    static let text2 = Color.ky(light: "#6B6E76", dark: "#8E8E96")
    static let text3 = Color.ky(light: "#A4A7AE", dark: "#5C5C64")

    static let accent = Color.ky(light: "#0FA3A1", dark: "#3DDBD9")
    /// Text/glyph color on top of a filled `accent` surface.
    static let accentInk = Color.ky(light: "#FFFFFF", dark: "#062B2B")
    static let accentSoft = Color.ky(light: "#0FA3A11A", dark: "#3DDBD91F")
    static let accentGlow = Color.ky(light: "#0FA3A159", dark: "#3DDBD973")
    /// Second stop of accent gradients (record button, progress bars).
    static let accentDeep = Color.ky(light: "#2D6CDF", dark: "#3A8BE0")

    static let rec = Color.ky(light: "#E5384A", dark: "#FF4D5E")
    static let recDeep = Color.ky(light: "#B8235A", dark: "#C62A64")
    static let recSoft = Color.ky(light: "#E5384A1A", dark: "#FF4D5E24")
    static let recGlow = Color.ky(light: "#E5384A66", dark: "#FF4D5E8C")

    static let warn = Color.ky(light: "#D99A12", dark: "#FFC857")
    static let warnInk = Color(hex: "#2A1D00")!
    static let warnSoft = Color.ky(light: "#D99A1214", dark: "#FFC85714")

    /// Tint laid over a behind-window blur for the floating panels, so text
    /// contrast doesn't depend on whatever happens to be behind the panel.
    static let glassTint = Color.ky(light: "#FFFFFFB8", dark: "#1E1E22B8")

    /// The brand mark's squircle gradient — same in both appearances.
    static let brandGradient = LinearGradient(
        colors: [Color(hex: "#3DDBD9")!, Color(hex: "#1B8FA8")!, Color(hex: "#213A6B")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let brandInk = Color(hex: "#062B2B")!
}

/// Type scale (prototype §07). No explicit family: the system font falls
/// back to PingFang SC for Chinese automatically. Numbers that tick (timers,
/// offsets) use the monospaced design so they don't jitter as digits change.
enum KYFont {
    static let display = Font.system(size: 28, weight: .bold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let headline = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13.5)
    static let bodyEmphasis = Font.system(size: 13.5, weight: .medium)
    static let control = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let small = Font.system(size: 11)
    static let overline = Font.system(size: 11, weight: .semibold)
    static let timerLarge = Font.system(size: 30, weight: .light, design: .monospaced)
    static let timer = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let timestamp = Font.system(size: 11, weight: .medium, design: .monospaced)
}

/// Corner-radius ladder: 6 inside controls · 10 buttons/cards · 14 windows ·
/// 20 floating notes window · capsule for pills.
enum KYRadius {
    static let control: CGFloat = 6
    static let button: CGFloat = 8
    static let card: CGFloat = 12
    static let window: CGFloat = 14
    static let floating: CGFloat = 20
}

extension Color {
    /// A light/dark pair resolved against the drawing appearance.
    static func ky(light: String, dark: String) -> Color {
        let lightColor = NSColor(hex: light)!
        let darkColor = NSColor(hex: dark)!
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }

    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA`. Returns nil for anything else.
    init?(hex: String) {
        guard let rgba = HexColor.parse(hex) else { return nil }
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        guard let rgba = HexColor.parse(hex) else { return nil }
        self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}

enum HexColor {
    static func parse(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }

        let hasAlpha: Bool
        switch value.count {
        case 3, 6: hasAlpha = false
        case 8: hasAlpha = true
        default: return nil
        }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard let intValue = UInt64(value, radix: 16) else { return nil }

        if hasAlpha {
            return (
                Double((intValue >> 24) & 0xFF) / 255,
                Double((intValue >> 16) & 0xFF) / 255,
                Double((intValue >> 8) & 0xFF) / 255,
                Double(intValue & 0xFF) / 255
            )
        }
        return (
            Double((intValue >> 16) & 0xFF) / 255,
            Double((intValue >> 8) & 0xFF) / 255,
            Double(intValue & 0xFF) / 255,
            1
        )
    }
}
