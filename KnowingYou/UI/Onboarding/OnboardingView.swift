import SwiftUI

/// First-run 480×360 checklist: microphone, system audio (deferred to S08),
/// notifications. Screen recording isn't onboarded here — S18 requests it
/// lazily the first time the user clicks the screenshot-mark button.
struct OnboardingView: View {
    @State private var micStatus: PermissionStatus = .notDetermined
    @State private var notificationsStatus: PermissionStatus = .notDetermined
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("欢迎使用知鱼录音")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(KYColor.textPrimary)
                Text("完成以下授权后即可开始录音")
                    .font(.system(size: 13))
                    .foregroundStyle(KYColor.textSecondary)
            }

            VStack(spacing: 4) {
                PermissionRow(
                    title: "麦克风",
                    subtitle: "用于录制你自己的声音",
                    permission: .microphone,
                    status: $micStatus
                )
                SettingsRow(title: "系统音频录制", subtitle: "用于录制会议对方的声音") {
                    Text("稍后在首次录音时申请")
                        .font(.system(size: 12))
                        .foregroundStyle(KYColor.textSecondary)
                }
                PermissionRow(
                    title: "通知",
                    subtitle: "用于会议提醒与录音完成提醒",
                    permission: .notifications,
                    status: $notificationsStatus
                )
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                PrimaryButton(title: "完成", action: onFinish)
                    .frame(width: 120)
            }
        }
        .padding(32)
        .frame(width: 480, height: 360)
        .background(KYColor.bgWindow)
        .task { await refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAll() }
        }
    }

    private func refreshAll() async {
        micStatus = await Permissions.shared.status(.microphone)
        notificationsStatus = await Permissions.shared.status(.notifications)
    }
}

/// One checklist row: a "去授权" button while undetermined, a green
/// checkmark once granted, or "打开系统设置" after the user says no.
private struct PermissionRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let permission: Permission
    @Binding var status: PermissionStatus

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            case .denied:
                OutlinedButton("打开系统设置") {
                    Permissions.shared.openSystemSettings(for: permission)
                }
            case .notDetermined:
                OutlinedButton("去授权") {
                    Task { status = await Permissions.shared.request(permission) }
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
