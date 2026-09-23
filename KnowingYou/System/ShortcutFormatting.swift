import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// Turns a `KeyboardShortcuts.Shortcut` (or a raw `NSEvent`) into the display
/// string used by `ShortcutRecorderButton` — pulled out of the view itself
/// so it's unit-testable without touching AppKit event objects or the
/// package's own `@MainActor`-only `.description`.
enum ShortcutFormatting {
    /// Modifier symbols in macOS's standard order: ⌃⌥⇧⌘.
    static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    static func string(for shortcut: KeyboardShortcuts.Shortcut) -> String {
        modifierSymbols(shortcut.modifiers) + keyLabel(for: shortcut.carbonKeyCode)
    }

    /// At least one of ⌘/⌥/⌃ is required (plain Shift-only combos are too
    /// easy to trigger by accident) — this spec's recording UI checks this
    /// before accepting a captured combo.
    static func hasRequiredModifier(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control)
    }

    /// A best-effort, hand-maintained list of well-known system shortcuts.
    /// `KeyboardShortcuts.Shortcut.isTakenBySystem` (which queries a live,
    /// accurate Carbon-derived list) exists but is `internal` to the
    /// package, not `public` — not usable from here. This is the pragmatic
    /// substitute: it won't catch everything the system reserves, but it
    /// catches the shortcuts a user is actually likely to type by accident.
    static func isCommonlyReservedBySystem(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        reservedShortcuts.contains(shortcut)
    }

    private static let reservedShortcuts: Set<KeyboardShortcuts.Shortcut> = [
        .init(.space, modifiers: .command), // Spotlight
        .init(.tab, modifiers: .command), // App switcher
        .init(.q, modifiers: .command), // Quit
        .init(.w, modifiers: .command), // Close window
        .init(.h, modifiers: .command), // Hide
        .init(.m, modifiers: .command), // Minimize
        .init(.three, modifiers: [.command, .shift]), // Screenshot: full screen
        .init(.four, modifiers: [.command, .shift]), // Screenshot: selection
        .init(.five, modifiers: [.command, .shift]), // Screenshot UI
        .init(.escape, modifiers: [.command, .option]), // Force Quit
    ]

    /// Best-effort carbon-key-code → display-character mapping. Covers
    /// letters, digits, and the handful of special keys likely to come up;
    /// anything else falls back to a placeholder rather than crashing —
    /// this is a display nicety, not safety-critical (the shortcut itself
    /// is still stored/matched by its real key code regardless of label).
    static func keyLabel(for carbonKeyCode: Int) -> String {
        letterAndDigitKeyCodes[carbonKeyCode] ?? specialKeyLabels[carbonKeyCode] ?? "?"
    }

    private static let letterAndDigitKeyCodes: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "⏎",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
