import SwiftUI

/// Color tokens from 02-ui-spec.md §1.1. Light mode only for v1.
enum KYColor {
    static let bgWindow = Color(hex: "#FFFFFF")!
    static let bgSidebar = Color(hex: "#F5F4F2")!
    static let bgSidebarSelected = Color(hex: "#E8E7E4")!
    static let bgTitlebar = Color(hex: "#ECEBE8")!
    static let bgBanner = Color(hex: "#F4F4F3")!
    static let bgButtonFilledLight = Color(hex: "#F0F0EF")!

    static let textPrimary = Color(hex: "#1C1C1C")!
    static let textSecondary = Color(hex: "#8B8B8B")!
    static let textSectionHeader = Color(hex: "#6A6A6A")!
    static let textPlaceholder = Color(hex: "#B8B8B8")!
    static let textGold = Color(hex: "#B0862B")!

    static let strokeHairline = Color(hex: "#E6E6E4")!
    static let strokeButton = Color(hex: "#CFCFCD")!

    static let controlOn = Color(hex: "#111111")!
    static let controlOff = Color(hex: "#D9D9D7")!
    static let controlKnob = Color(hex: "#FFFFFF")!

    static let outlinedButtonHover = Color(hex: "#F7F7F6")!
    static let outlinedButtonPressed = Color(hex: "#EFEFEE")!
}

extension Color {
    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA`. Returns nil for anything else.
    init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }

        let hasAlpha: Bool
        switch value.count {
        case 3: hasAlpha = false
        case 6: hasAlpha = false
        case 8: hasAlpha = true
        default: return nil
        }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard let intValue = UInt64(value, radix: 16) else { return nil }

        let r, g, b, a: Double
        if hasAlpha {
            r = Double((intValue >> 24) & 0xFF) / 255
            g = Double((intValue >> 16) & 0xFF) / 255
            b = Double((intValue >> 8) & 0xFF) / 255
            a = Double(intValue & 0xFF) / 255
        } else {
            r = Double((intValue >> 16) & 0xFF) / 255
            g = Double((intValue >> 8) & 0xFF) / 255
            b = Double(intValue & 0xFF) / 255
            a = 1
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Font tokens from 02-ui-spec.md §1.2, named by usage. No explicit font family:
/// the system font falls back to PingFang SC for Chinese automatically.
enum KYFont {
    static let sectionHeader = Font.system(size: 18, weight: .light)
    static let rowTitle = Font.system(size: 14, weight: .regular)
    static let rowSubtitle = Font.system(size: 13, weight: .regular)
    static let outlinedButton = Font.system(size: 13, weight: .regular)
    static let sidebarItem = Font.system(size: 14, weight: .regular)
    static let sidebarCardTitle = Font.system(size: 14, weight: .semibold)
    static let sidebarCardSubtitle = Font.system(size: 12, weight: .regular)
    static let aboutAppName = Font.system(size: 28, weight: .light)
    static let aboutSubtitle = Font.system(size: 15, weight: .regular)
    static let popoverPrimaryButton = Font.system(size: 15, weight: .regular)
    static let popoverRecentRecordings = Font.system(size: 14, weight: .regular)
    static let popoverFooter = Font.system(size: 12, weight: .regular)
    static let notesHeaderCaption = Font.system(size: 11, weight: .regular)
    static let notesTitlePlaceholder = Font.system(size: 17, weight: .regular)
    static let notesBody = Font.system(size: 13, weight: .regular)
}
