import KeyboardShortcuts
import SwiftUI

/// The 快捷键 (Shortcuts) page: K1–K6. Recording a new combo is S17's job;
/// this page only reads/resets/displays.
struct ShortcutsSettingsView: View {
    @State private var hotkeysEnabled = Preferences.shared.hotkeysEnabled

    var body: some View {
        SettingsPageScaffold(title: "快捷键", lead: "点击组合键录制新快捷键；Esc 取消，⌫ 清除。") {
            SettingsSection("全局快捷键") {
                SettingsRow(title: "全局快捷键", subtitle: "开启后，知鱼录音在后台运行时依然有效", systemImage: "command") {
                    KYToggle(isOn: hotkeysEnabledBinding)
                }
            }
            SettingsSection("操作") {
                SettingsRow(title: "开始 / 停止录音", systemImage: "record.circle") {
                    ShortcutRecorderButton(name: .toggleRecording, isEnabled: hotkeysEnabled)
                }
                SettingsRow(title: "截屏标记", subtitle: "快速截取并保存会议中的画面", systemImage: "camera.viewfinder") {
                    ShortcutRecorderButton(name: .screenshotMark, isEnabled: hotkeysEnabled)
                }
                SettingsRow(title: "快速标记", subtitle: "实时标记重要时刻，便于后续回顾", systemImage: "flag") {
                    ShortcutRecorderButton(name: .quickMark, isEnabled: hotkeysEnabled)
                }
            }
            HStack {
                Spacer()
                KYButton("恢复默认", style: .ghost, size: .small, systemImage: "arrow.counterclockwise") {
                    KeyboardShortcuts.reset(.toggleRecording, .quickMark, .screenshotMark)
                }
            }
        }
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
        .frame(width: 540, height: 580)
}
