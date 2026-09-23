import AppKit
import KeyboardShortcuts
import Testing
@testable import KnowingYou

struct ShortcutFormattingTests {
    @Test func modifierSymbolsFollowMacOSStandardOrder() {
        // Standard order is Control, Option, Shift, Command — regardless of
        // the order the flags are listed in the input set.
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .shift, .option]
        #expect(ShortcutFormatting.modifierSymbols(modifiers) == "⌃⌥⇧⌘")
    }

    @Test func modifierSymbolsOmitAbsentModifiers() {
        #expect(ShortcutFormatting.modifierSymbols([.command, .option]) == "⌥⌘")
        #expect(ShortcutFormatting.modifierSymbols([.control]) == "⌃")
        #expect(ShortcutFormatting.modifierSymbols([]) == "")
    }

    @Test func defaultShortcutsFormatAsExpected() {
        #expect(ShortcutFormatting.string(for: .init(.r, modifiers: [.option, .command])) == "⌥⌘R")
        #expect(ShortcutFormatting.string(for: .init(.m, modifiers: [.option, .command])) == "⌥⌘M")
        #expect(ShortcutFormatting.string(for: .init(.s, modifiers: [.option, .command])) == "⌥⌘S")
    }

    @Test func fullModifierComboFormatsInStandardOrder() {
        #expect(ShortcutFormatting.string(for: .init(.k, modifiers: [.control, .option])) == "⌃⌥K")
    }

    @Test func digitKeysFormatCorrectly() {
        #expect(ShortcutFormatting.string(for: .init(.one, modifiers: .command)) == "⌘1")
    }

    @Test func requiredModifierAcceptsCommandOptionOrControl() {
        #expect(ShortcutFormatting.hasRequiredModifier(.command))
        #expect(ShortcutFormatting.hasRequiredModifier(.option))
        #expect(ShortcutFormatting.hasRequiredModifier(.control))
        #expect(ShortcutFormatting.hasRequiredModifier([.command, .shift]))
    }

    @Test func requiredModifierRejectsShiftOnlyOrNone() {
        #expect(!ShortcutFormatting.hasRequiredModifier(.shift))
        #expect(!ShortcutFormatting.hasRequiredModifier([]))
    }

    @Test func commonlyReservedShortcutsAreFlagged() {
        #expect(ShortcutFormatting.isCommonlyReservedBySystem(.init(.space, modifiers: .command)))
        #expect(ShortcutFormatting.isCommonlyReservedBySystem(.init(.q, modifiers: .command)))
        #expect(!ShortcutFormatting.isCommonlyReservedBySystem(.init(.r, modifiers: [.option, .command])))
    }
}
