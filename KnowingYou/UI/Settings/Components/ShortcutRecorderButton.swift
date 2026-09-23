import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// K3/K4/K6's shortcut display and recording interaction (02-ui-spec.md
/// §11 "快捷键录制态"). Not `KeyboardShortcuts.Recorder` — its built-in style
/// doesn't match this app's outlined-button look — just the package's
/// storage/registration/conflict-check APIs underneath a custom button.
struct ShortcutRecorderButton: View {
    let name: KeyboardShortcuts.Name
    var isEnabled: Bool = true

    @State private var isRecording = false
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var keyMonitor: Any?
    @State private var clickMonitor: Any?

    var body: some View {
        Group {
            if isRecording {
                recordingLabel
            } else {
                OutlinedButton(displayLabel, isEnabled: isEnabled, action: startRecording)
            }
        }
        .onAppear { currentShortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear { stopRecording() }
    }

    private var displayLabel: LocalizedStringKey {
        if let currentShortcut {
            LocalizedStringKey(ShortcutFormatting.string(for: currentShortcut))
        } else {
            "未设置"
        }
    }

    private var recordingLabel: some View {
        Text("按下快捷键…")
            .font(KYFont.outlinedButton)
            .foregroundStyle(KYColor.textPrimary)
            .padding(.horizontal, 20)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(KYColor.bgWindow))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KYColor.controlOn, lineWidth: 1.5))
    }

    private func startRecording() {
        guard isEnabled, !isRecording else { return }
        isRecording = true
        // Prevent the combo the user is about to press from also firing the
        // *current* global handler mid-capture (most obviously an issue when
        // re-recording ⌥⌘R itself).
        KeyboardShortcuts.disable(.toggleRecording, .quickMark, .screenshotMark)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow every key while recording — including ones we reject
        }
        // "点其他地方取消" (§11): approximated as "any click cancels", including
        // a click back on this same button — precisely distinguishing
        // "inside this button" from "elsewhere" via a raw NSEvent monitor
        // would need extra view-geometry bookkeeping for an interaction that
        // can't be verified with real clicks in this environment anyway (see
        // this spec's decision record).
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            Task { @MainActor in stopRecording() }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if Preferences.shared.hotkeysEnabled {
            KeyboardShortcuts.enable(.toggleRecording, .quickMark, .screenshotMark)
        }
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            stopRecording() // cancel — value unchanged
            return
        case kVK_Delete, kVK_ForwardDelete:
            KeyboardShortcuts.setShortcut(nil, for: name)
            currentShortcut = nil
            stopRecording()
            return
        default:
            break
        }

        guard ShortcutFormatting.hasRequiredModifier(event.modifierFlags) else {
            return // held a bare letter with no modifier — keep waiting
        }
        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            return
        }

        if ShortcutFormatting.isCommonlyReservedBySystem(shortcut) {
            stopRecording()
            showReservedShortcutAlert()
            return
        }

        KeyboardShortcuts.setShortcut(shortcut, for: name)
        currentShortcut = shortcut
        stopRecording()
    }

    private func showReservedShortcutAlert() {
        let alert = NSAlert()
        alert.messageText = "这个快捷键已被系统占用"
        alert.informativeText = "请换一个组合键。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

#Preview {
    VStack(spacing: 12) {
        ShortcutRecorderButton(name: .screenshotMark)
        ShortcutRecorderButton(name: .quickMark, isEnabled: false)
    }
    .padding()
}
