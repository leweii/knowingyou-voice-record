import KeyboardShortcuts
import SwiftUI

/// The 快捷键 (Shortcuts) page: K1–K6. Recording a new combo is S17's job;
/// this page only reads/resets/displays.
struct ShortcutsSettingsView: View {
    @State private var hotkeysEnabled = Preferences.shared.hotkeysEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("快捷键")
            VStack(spacing: 0) {
                SettingsRow(title: "全局快捷键", subtitle: "开启后，知鱼录音在后台运行时依然有效") {
                    KYToggle(isOn: hotkeysEnabledBinding)
                }
                SettingsRow(title: "开始 / 停止录音") {
                    ShortcutRecorderButton(name: .toggleRecording, isEnabled: hotkeysEnabled)
                }
                SettingsRow(title: "截屏标记", subtitle: "快速截取并保存会议中的画面") {
                    ShortcutRecorderButton(name: .screenshotMark, isEnabled: hotkeysEnabled)
                }
                SettingsRow(title: "快速标记", subtitle: "实时标记重要时刻，便于后续回顾") {
                    ShortcutRecorderButton(name: .quickMark, isEnabled: hotkeysEnabled)
                }
            }

            HStack {
                Spacer()
                OutlinedButton("恢复默认", height: 30) {
                    KeyboardShortcuts.reset(.toggleRecording, .quickMark, .screenshotMark)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var hotkeysEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeysEnabled },
            set: { newValue in
                hotkeysEnabled = newValue
                Preferences.shared.hotkeysEnabled = newValue
            }
        )
    }
}

#Preview {
    ShortcutsSettingsView()
        .frame(width: 496, height: 520)
}
