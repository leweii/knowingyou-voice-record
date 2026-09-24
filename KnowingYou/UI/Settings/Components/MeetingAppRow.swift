import SwiftUI

/// One row in R9's meeting-app list: name only, purely informational.
/// Used to have an app icon + a per-app enable/disable toggle; both are
/// gone now (2026-09-24, Jakob's feedback — see `KnownApps`'s decision
/// record). Every listed app is always detected; this is just telling the
/// user what's supported, not something to configure.
struct MeetingAppRow: View {
    let app: KnownApp

    var body: some View {
        HStack(spacing: 12) {
            Text(app.displayNameKey)
                .font(KYFont.rowTitle)
                .foregroundStyle(KYColor.textPrimary)
            Spacer(minLength: 12)
        }
        .frame(height: 44)
    }
}

#Preview {
    MeetingAppRow(app: KnownApp(bundleIDPrefix: "com.tencent.meeting", displayNameKey: "腾讯会议", kind: .native))
        .padding()
        .frame(width: 480)
}
