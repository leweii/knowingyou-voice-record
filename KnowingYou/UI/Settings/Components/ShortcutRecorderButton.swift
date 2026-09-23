import KeyboardShortcuts
import SwiftUI

/// K3/K4/K6's shortcut display. Static appearance only for now — clicking to
/// enter a recording state and capture a new key combo lands in S17.
struct ShortcutRecorderButton: View {
    let name: KeyboardShortcuts.Name
    var isEnabled: Bool = true

    var body: some View {
        OutlinedButton(currentLabel, isEnabled: isEnabled) {
            // Recording interaction lands in S17.
        }
    }

    @MainActor
    private var currentLabel: LocalizedStringKey {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
            LocalizedStringKey(shortcut.description)
        } else {
            "未设置"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ShortcutRecorderButton(name: .screenshotMark)
        ShortcutRecorderButton(name: .quickMark, isEnabled: false)
    }
    .padding()
}
