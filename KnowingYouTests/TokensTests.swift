import AppKit
import SwiftUI
import Testing
@testable import KnowingYou

struct TokensTests {
    private let allTokenHexValues = [
        "#FFFFFF", "#F5F4F2", "#E8E7E4", "#ECEBE8", "#F4F4F3", "#F0F0EF",
        "#1C1C1C", "#8B8B8B", "#6A6A6A", "#B8B8B8", "#B0862B",
        "#E6E6E4", "#CFCFCD",
        "#111111", "#D9D9D7", "#FFFFFF",
    ]

    @Test func allSpecColorsParse() {
        for hex in allTokenHexValues {
            #expect(Color(hex: hex) != nil, "expected \(hex) to parse")
        }
    }

    @Test func parsesWithoutHashPrefix() {
        #expect(Color(hex: "1C1C1C") != nil)
    }

    @Test func parsesShorthandThreeDigit() {
        #expect(Color(hex: "#FFF") != nil)
    }

    @Test func parsesEightDigitWithAlpha() {
        #expect(Color(hex: "#1C1C1CFF") != nil)
    }

    @Test func rejectsInvalidHex() {
        #expect(Color(hex: "not-a-color") == nil)
        #expect(Color(hex: "#12345") == nil)
        #expect(Color(hex: "#GGGGGG") == nil)
        #expect(Color(hex: "") == nil)
    }

    /// S22: every surface/text/accent token is a light/dark pair. Resolving
    /// the same token under each appearance must give different colors —
    /// otherwise the token isn't actually dynamic and one theme is broken.
    @Test func dynamicTokensDifferBetweenLightAndDark() {
        let tokens: [(String, Color)] = [
            ("bg", KYColor.bg), ("surface", KYColor.surface), ("surface2", KYColor.surface2),
            ("stroke", KYColor.stroke), ("text", KYColor.text), ("text2", KYColor.text2),
            ("accent", KYColor.accent), ("rec", KYColor.rec), ("warn", KYColor.warn),
        ]
        for (name, token) in tokens {
            let light = resolve(token, in: .aqua)
            let dark = resolve(token, in: .darkAqua)
            #expect(light != dark, "\(name) should resolve differently in light vs dark")
        }
    }

    @Test func accentAndRecordingRedAreDistinct() {
        #expect(resolve(KYColor.accent, in: .darkAqua) != resolve(KYColor.rec, in: .darkAqua))
        #expect(resolve(KYColor.text, in: .darkAqua) != resolve(KYColor.text2, in: .darkAqua))
        #expect(resolve(KYColor.surface, in: .darkAqua) != resolve(KYColor.surface2, in: .darkAqua))
    }

    @Test func darkThemeMatchesPrototypePalette() {
        #expect(hex(resolve(KYColor.accent, in: .darkAqua)) == "3DDBD9")
        #expect(hex(resolve(KYColor.rec, in: .darkAqua)) == "FF4D5E")
        #expect(hex(resolve(KYColor.bg, in: .darkAqua)) == "161618")
    }

    private func resolve(_ color: Color, in name: NSAppearance.Name) -> NSColor {
        let dynamic = NSColor(color)
        var resolved = NSColor.clear
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            resolved = dynamic.usingColorSpace(.sRGB) ?? dynamic
        }
        return resolved
    }

    private func hex(_ color: NSColor) -> String {
        String(
            format: "%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
