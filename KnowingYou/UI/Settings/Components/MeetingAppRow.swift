import SwiftUI

/// One row in R9's meeting-app list: icon + name + enable toggle.
/// Uninstalled apps still show (greyed by `AppIconView`) since the user
/// may install them later.
struct MeetingAppRow: View {
    let app: KnownApp
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleIdentifier: app.bundleIDPrefix)
            Text(app.displayNameKey)
                .font(KYFont.rowTitle)
                .foregroundStyle(KYColor.textPrimary)
            Spacer(minLength: 12)
            KYToggle(isOn: $isEnabled)
        }
        .frame(height: 44)
    }
}

#Preview {
    MeetingAppRow(
        app: KnownApp(bundleIDPrefix: "com.tencent.meeting", displayNameKey: "腾讯会议", kind: .native, isEnabled: true),
        isEnabled: .constant(true)
    )
    .padding()
    .frame(width: 480)
}
