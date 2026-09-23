import AppKit
import KeyboardShortcuts

/// Registers the three global hotkeys (`Support/Contracts.swift`'s
/// `KeyboardShortcuts.Name` constants, declared back in S04) against
/// `AppState`, seeds their default combos on first launch, and keeps them
/// enabled/disabled in sync with `Preferences.hotkeysEnabled`.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let allNames: [KeyboardShortcuts.Name] = [.toggleRecording, .quickMark, .screenshotMark]

    private weak var appState: AppState?
    private var isConfigured = false
    private var preferencesObserver: NSObjectProtocol?

    private init() {}

    func configure(appState: AppState) {
        self.appState = appState
        guard !isConfigured else { return }
        isConfigured = true

        seedDefaultsIfNeeded()
        applyEnabledState()
        observePreferenceChanges()
        registerHandlers()
    }

    private func seedDefaultsIfNeeded() {
        seedDefaultIfNeeded(.toggleRecording, KeyboardShortcuts.Shortcut(.r, modifiers: [.option, .command]))
        seedDefaultIfNeeded(.quickMark, KeyboardShortcuts.Shortcut(.m, modifiers: [.option, .command]))
        seedDefaultIfNeeded(.screenshotMark, KeyboardShortcuts.Shortcut(.s, modifiers: [.option, .command]))
    }

    private func seedDefaultIfNeeded(_ name: KeyboardShortcuts.Name, _ shortcut: KeyboardShortcuts.Shortcut) {
        guard KeyboardShortcuts.getShortcut(for: name) == nil else { return }
        KeyboardShortcuts.setShortcut(shortcut, for: name)
    }

    private func registerHandlers() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { await self?.handleToggleRecording() }
        }
        KeyboardShortcuts.onKeyUp(for: .quickMark) { [weak self] in
            self?.appState?.quickMark()
        }
        KeyboardShortcuts.onKeyUp(for: .screenshotMark) { [weak self] in
            self?.appState?.captureScreenshotMark()
        }
    }

    private func handleToggleRecording() async {
        guard let appState else { return }
        if appState.isRecording {
            await appState.stopRecording()
        } else {
            await appState.startManualRecording()
        }
    }

    private func observePreferenceChanges() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyEnabledState() }
        }
    }

    private func applyEnabledState() {
        if Preferences.shared.hotkeysEnabled {
            KeyboardShortcuts.enable(Self.allNames)
        } else {
            KeyboardShortcuts.disable(Self.allNames)
        }
    }
}
