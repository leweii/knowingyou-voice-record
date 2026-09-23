import AppKit
import SwiftUI

/// The 通用 (General) page: G1–G9. Section spacing follows 02-ui-spec.md §3;
/// `SectionHeader`/`SettingsRow` already encode the per-row heights.
struct GeneralSettingsView: View {
    @State private var launchAtLogin = Preferences.shared.launchAtLogin
    @State private var showDockIcon = Preferences.shared.showDockIcon
    @State private var appLanguage = Preferences.shared.appLanguage
    @State private var saveDirectoryPath = Preferences.shared.saveDirectoryPath
    @State private var isDirectoryWritable = true
    @State private var diskUsageText = "…"
    @State private var showRestartAlert = false
    @State private var launchAtLoginError: String?

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                systemSection
                dataAndStorageSection
                helpAndFeedbackSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .task {
            try? SaveDirectory.ensureExists(at: saveDirectoryPath)
            isDirectoryWritable = SaveDirectory.isWritable(at: saveDirectoryPath)
        }
        .task(id: saveDirectoryPath) {
            let path = saveDirectoryPath
            let bytes = await Task.detached(priority: .utility) {
                SaveDirectory.directorySize(at: path)
            }.value
            diskUsageText = SaveDirectory.formattedSize(bytes)
        }
        .alert("需要重启才能应用语言更改", isPresented: $showRestartAlert) {
            Button("立刻重启", action: restartApp)
            Button("稍后", role: .cancel) {}
        }
        .alert("开机自启设置失败", isPresented: launchAtLoginErrorBinding, actions: {
            Button("好") { launchAtLoginError = nil }
        }, message: {
            Text(launchAtLoginError ?? "")
        })
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("系统")
            VStack(spacing: 0) {
                SettingsRow(title: "开机时自动启动知鱼录音") {
                    KYToggle(isOn: launchAtLoginBinding)
                }
                SettingsRow(title: "在 Dock 中显示图标") {
                    KYToggle(isOn: dockIconBinding)
                }
                SettingsRow(title: "显示语言", subtitle: "选择知鱼录音的界面语言") {
                    BorderlessPopup(
                        selection: appLanguageBinding,
                        options: [
                            .init(value: .zhHans, title: "中文（简体）"),
                            .init(value: .en, title: "English"),
                        ]
                    )
                }
            }
        }
    }

    private var dataAndStorageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("数据与存储")
            VStack(spacing: 0) {
                SettingsRow(
                    title: "录音保存路径",
                    subtitle: isDirectoryWritable
                        ? LocalizedStringKey(SaveDirectory.displayPath(saveDirectoryPath))
                        : "无法写入此位置",
                    subtitleColor: isDirectoryWritable ? KYColor.textSecondary : .red,
                    subtitleLineLimit: 1
                ) {
                    OutlinedButton("更改…", action: chooseDirectory)
                }
                SettingsRow(title: "在 Finder 中显示") {
                    OutlinedButton("打开", action: revealInFinder)
                }
                SettingsRow(title: "磁盘占用") {
                    Text(diskUsageText)
                        .font(KYFont.rowSubtitle)
                        .foregroundStyle(KYColor.textSecondary)
                }
            }
        }
    }

    private var helpAndFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("帮助与反馈")
            VStack(spacing: 0) {
                SettingsRow(title: "使用帮助") {
                    OutlinedButton("查看帮助") {
                        MarkdownViewerWindow.show(title: String(localized: "使用帮助"), document: .help)
                    }
                }
                SettingsRow(title: "反馈") {
                    OutlinedButton("发送邮件", action: sendFeedbackEmail)
                }
                SettingsRow(title: "应用诊断") {
                    OutlinedButton("导出诊断日志", action: DiagnosticsExport.export)
                }
            }
        }
    }

    // MARK: - Bindings

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = newValue
                    Preferences.shared.launchAtLogin = newValue
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { showDockIcon },
            set: { newValue in
                showDockIcon = newValue
                Preferences.shared.showDockIcon = newValue
                DockIcon.setVisible(newValue)
            }
        )
    }

    private var launchAtLoginErrorBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginError != nil },
            set: { isPresented in if !isPresented { launchAtLoginError = nil } }
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { appLanguage },
            set: { newValue in
                guard newValue != appLanguage else { return }
                appLanguage = newValue
                Preferences.shared.appLanguage = newValue
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
                showRestartAlert = true
            }
        )
    }

    // MARK: - Actions

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "选择")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            saveDirectoryPath = url.path
            isDirectoryWritable = SaveDirectory.isWritable(at: url.path)
            if isDirectoryWritable {
                Preferences.shared.saveDirectoryPath = url.path
            }
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: saveDirectoryPath)])
    }

    private func sendFeedbackEmail() {
        let email = Bundle.main.infoDictionary?["KYFeedbackEmail"] as? String ?? ""
        // "feedback@example.invalid" is the checked-in placeholder (S21 must
        // replace it with a real address before release) — showing an alert
        // instead of opening a blank/broken mailto is more honest than
        // silently doing nothing or opening Mail to an address that bounces.
        guard email != "feedback@example.invalid", !email.isEmpty else {
            let alert = NSAlert()
            alert.messageText = String(localized: "反馈邮箱尚未配置")
            alert.informativeText = String(localized: "这是开发中的占位设置，正式发布前会替换为真实的反馈邮箱。")
            alert.addButton(withTitle: String(localized: "好"))
            alert.runModal()
            return
        }
        let subject = "知鱼录音反馈 v\(versionString)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        guard let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        NSApp.terminate(nil)
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 496, height: 520)
}
