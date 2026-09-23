import SwiftUI

/// Outlined button per 02-ui-spec.md §1.3: 32pt tall by default (30 for
/// "恢复默认" / "检查更新"), 6pt corner radius, 1pt border, hover/pressed fills.
struct OutlinedButton: View {
    let title: LocalizedStringKey
    var height: CGFloat = 32
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        height: CGFloat = 32,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.height = height
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(KYFont.outlinedButton)
            .foregroundStyle(isEnabled ? KYColor.textPrimary : KYColor.textSecondary)
            .padding(.horizontal, 20)
            .frame(height: height)
        }
        .buttonStyle(OutlinedButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

private struct OutlinedButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        OutlinedButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

/// Hover state needs a real View's identity to survive across renders;
/// a `ButtonStyle` itself gets recreated too often for `@State` to stick.
private struct OutlinedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(KYColor.strokeButton, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovering = $0 }
    }

    private func fillColor(pressed: Bool) -> Color {
        guard isEnabled else { return KYColor.bgWindow }
        if pressed { return KYColor.outlinedButtonPressed }
        if isHovering { return KYColor.outlinedButtonHover }
        return KYColor.bgWindow
    }
}

#Preview {
    VStack(spacing: 16) {
        OutlinedButton("恢复默认", height: 30) {}
        OutlinedButton("查看帮助", systemImage: "questionmark.circle") {}
        OutlinedButton("已停用", isEnabled: false) {}
    }
    .padding()
}
