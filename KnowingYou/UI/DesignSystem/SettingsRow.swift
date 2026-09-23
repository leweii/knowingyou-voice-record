import SwiftUI

/// A settings line per 02-ui-spec.md §1.3: title-only rows are 46pt tall;
/// title+subtitle rows are 60pt, with the subtitle 20pt below the title.
/// Left text, right control, control vertically centered on the row.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var subtitleColor: Color = KYColor.textSecondary
    var subtitleLineLimit: Int? = nil
    @ViewBuilder var trailing: Trailing

    private var rowHeight: CGFloat { subtitle == nil ? 46 : 60 }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(KYFont.rowTitle)
                    .foregroundStyle(KYColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(KYFont.rowSubtitle)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(subtitleLineLimit)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .frame(height: rowHeight)
    }
}

#Preview {
    VStack(spacing: 0) {
        SettingsRow(title: "开机时自动启动知鱼录音") {
            KYToggle(isOn: .constant(true))
        }
        SettingsRow(title: "录音时显示快捷组件", subtitle: "在桌面快速查看录音状态并进行操作") {
            KYToggle(isOn: .constant(true))
        }
    }
    .padding()
    .frame(width: 480)
}
