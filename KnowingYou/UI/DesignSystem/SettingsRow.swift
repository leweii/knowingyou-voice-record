import SwiftUI

/// Uppercase-tracked label above a settings card (replaces the old 18pt
/// section header + hairline).
struct GroupLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(KYFont.overline)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(KYColor.text3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A group label + a card holding rows. Each `SettingsRow` draws its own top
/// hairline; on the first row it lands exactly on the card's 1pt border (same
/// color), so only the dividers *between* rows are visible — no need for
/// macOS 15's `Group(subviews:)` to special-case the first child.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                GroupLabel(title)
            }
            VStack(spacing: 0) {
                content
            }
            .kyCard()
        }
    }
}

/// One line in a settings card: optional tinted icon tile, title (+ subtitle),
/// trailing control. Hover lightens the row slightly.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String?
    var subtitleColor: Color = KYColor.text2
    var subtitleLineLimit: Int? = nil
    @ViewBuilder var trailing: Trailing

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KYColor.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: KYRadius.button, style: .continuous).fill(KYColor.surface3))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KYFont.body)
                    .foregroundStyle(KYColor.text)
                if let subtitle {
                    Text(subtitle)
                        .font(KYFont.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(subtitleLineLimit)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: subtitleLineLimit == nil)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
        .background(isHovering ? KYColor.surface3.opacity(0.4) : .clear)
        .overlay(alignment: .top) { Rectangle().fill(KYColor.stroke).frame(height: 1) }
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
    }
}

#Preview {
    SettingsSection("系统") {
        SettingsRow(title: "开机时自动启动知鱼录音", systemImage: "power") {
            KYToggle(isOn: .constant(true))
        }
        SettingsRow(title: "录音时显示快捷组件", subtitle: "在桌面快速查看录音状态并进行操作", systemImage: "capsule") {
            KYToggle(isOn: .constant(false))
        }
    }
    .padding()
    .frame(width: 520)
}
