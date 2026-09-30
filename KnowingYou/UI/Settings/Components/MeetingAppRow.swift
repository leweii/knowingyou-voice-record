import SwiftUI

/// One chip in the meeting-app grid: name only, purely informational.
/// Used to have an app icon + a per-app enable/disable toggle; both are
/// gone now (2026-09-24, Jakob's feedback — see `KnownApps`'s decision
/// record). Every listed app is always detected; this is just telling the
/// user what's supported, not something to configure.
struct MeetingAppChip: View {
    let app: KnownApp

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.kind == .browser ? KYColor.warn : KYColor.accent)
                .frame(width: 6, height: 6)
            Text(app.displayNameKey)
                .font(KYFont.caption)
                .foregroundStyle(KYColor.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KYColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KYColor.stroke, lineWidth: 1))
        .help(app.kind == .browser ? Text("浏览器会议只提示，不自动录音") : Text(verbatim: app.displayNameKey))
    }
}

/// Dashed "＋ 添加应用…" chip at the end of the grid.
struct AddAppChip: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("添加应用…")
                    .font(KYFont.caption)
            }
            .foregroundStyle(isHovering ? KYColor.accent : KYColor.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHovering ? KYColor.accent : KYColor.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
    }
}

#Preview {
    HStack {
        MeetingAppChip(app: KnownApp(bundleIDPrefix: "com.tencent.meeting", displayNameKey: "腾讯会议", kind: .native))
        AddAppChip {}
    }
    .padding()
    .frame(width: 360)
}
