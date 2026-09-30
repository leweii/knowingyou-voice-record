import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// K3/K4/K6's shortcut display and recording interaction (02-ui-spec.md
/// §11 "快捷键录制态"). Not `KeyboardShortcuts.Recorder` — its built-in style
/// doesn't match this app's keycap look — just the package's
/// storage/registration/conflict-check APIs underneath a custom button.
struct ShortcutRecorderButton: View {
    let name: KeyboardShortcuts.Name
    var isEnabled: Bool = true

    @State private var isRecording = false
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var keyMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var isHovering = false

    var body: some View {
        Button(action: startRecording) {
            Group {
                if isRecording {
                    Text("按下快捷键…")
                        .font(KYFont.caption)
                        .foregroundStyle(KYColor.accent)
                        .padding(.horizontal, 8)
                } else if let currentShortcut {
                    HStack(spacing: 4) {
                        ForEach(Array(Self.keycaps(for: currentShortcut).enumerated()), id: \.offset) { _, key in
                            Keycap(text: key)
                        }
                    }
                } else {
                    Text("未设置")
                        .font(KYFont.caption)
                        .foregroundStyle(KYColor.text3)
                        .padding(.horizontal, 8)
                }
            }
            .frame(minWidth: 112, minHeight: 32)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KYColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isRecording || isHovering ? KYColor.accent : KYColor.strokeStrong, lineWidth: isRecording ? 1.5 : 1)
            )
            .shadow(color: isRecording ? KYColor.accentGlow : .clear, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.state, value: isRecording)
        .kyAnimation(KYMotion.state, value: currentShortcut)
        .onAppear { currentShortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear { stopRecording() }
    }

    /// "⌥⌘R" → ["⌥", "⌘", "R"]: modifier glyphs are single characters, the
    /// key label is whatever follows them (may be multi-character, e.g. "F5").
    private static func keycaps(for shortcut: KeyboardShortcuts.Shortcut) -> [String] {
        let string = ShortcutFormatting.string(for: shortcut)
        let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var caps: [String] = []
        var rest = Substring(string)
        while let first = rest.first, modifierGlyphs.contains(first) {
            caps.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { caps.append(String(rest)) }
        return caps
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
        alert.messageText = String(localized: "这个快捷键已被系统占用")
        alert.informativeText = String(localized: "请换一个组合键。")
        alert.addButton(withTitle: String(localized: "好"))
        alert.runModal()
    }
}

/// One raised key, like a physical keycap.
private struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(KYColor.text)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, text.count > 1 ? 5 : 0)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(KYColor.surface3))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(KYColor.strokeStrong, lineWidth: 1))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5).fill(KYColor.strokeStrong).frame(height: 1.5).padding(.horizontal, 1)
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
