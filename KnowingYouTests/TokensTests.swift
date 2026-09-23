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

    @Test func tokensAreDistinctWhereSpecRequires() {
        #expect(KYColor.controlOn != KYColor.controlOff)
        #expect(KYColor.textPrimary != KYColor.textSecondary)
        #expect(KYColor.bgSidebar != KYColor.bgSidebarSelected)
    }
}
