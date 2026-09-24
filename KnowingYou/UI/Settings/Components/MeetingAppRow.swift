import SwiftUI

/// One row in R9's meeting-app list: icon + name, purely informational.
/// Uninstalled apps still show (greyed by `AppIconView`) since the user may
/// install them later. Used to have a per-app enable/disable toggle, but
/// Jakob found that "configuration" bizarre for a list of apps the product
/// already claims to support out of the box (2026-09-24) — see
/// `KnownApps`'s decision record. Every listed app is always detected now;
/// there's nothing left here to switch on or off.
struct MeetingAppRow: View {
    let app: KnownApp

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleIdentifier: app.bundleIDPrefix)
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
