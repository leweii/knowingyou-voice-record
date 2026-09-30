import SwiftUI

/// The one button component for ordinary actions. Styles map to intent:
/// `.secondary` (default, bordered surface), `.primary` (accent fill — one per
/// view at most), `.ghost` (text-only, for low-emphasis actions), `.danger`
/// (recording red). Lifts 1pt on hover, squashes on press.
struct KYButton: View {
    enum Style {
        case primary
        case secondary
        case ghost
        case danger
    }

    enum Size {
        case regular
        case small
        case large

        var height: CGFloat {
            switch self {
            case .small: 26
            case .regular: 32
            case .large: 40
            }
        }

        var font: Font {
            switch self {
            case .small: KYFont.caption
            case .regular: KYFont.control
            case .large: Font.system(size: 14, weight: .semibold)
            }
        }
    }

    let title: LocalizedStringKey
    var style: Style = .secondary
    var size: Size = .regular
    var systemImage: String?
    var isEnabled: Bool = true
    var fillsWidth: Bool = false
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        style: Style = .secondary,
        size: Size = .regular,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.size = size
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: size == .small ? 11 : 12, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(size.font)
            .fontWeight(style == .primary || style == .danger ? .semibold : nil)
            .padding(.horizontal, size == .small ? 10 : 14)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(KYButtonStyle(style: style, isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

struct KYButtonStyle: ButtonStyle {
    let style: KYButton.Style
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        KYButtonBody(configuration: configuration, style: style, isEnabled: isEnabled)
    }
}

/// Hover state needs a real View's identity to survive across renders;
/// a `ButtonStyle` itself gets recreated too often for `@State` to stick.
private struct KYButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: KYButton.Style
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KYRadius.button, style: .continuous)
        configuration.label
            .foregroundStyle(foreground)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .shadow(color: glow, radius: isHovering ? 12 : 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: isHovering && !configuration.isPressed && isEnabled ? -1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
            .kyAnimation(KYMotion.micro, value: isHovering)
            .kyAnimation(KYMotion.micro, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch style {
        case .primary: KYColor.accentInk
        case .danger: .white
        case .secondary: KYColor.text
        case .ghost: isHovering ? KYColor.text : KYColor.text2
        }
    }

    private var fill: Color {
        switch style {
        case .primary: KYColor.accent
        case .danger: KYColor.rec
        case .secondary: isHovering ? KYColor.surface3 : KYColor.surface2
        case .ghost: isHovering ? KYColor.surface2 : .clear
        }
    }

    private var border: Color {
        style == .secondary ? KYColor.strokeStrong : .clear
    }

    private var glow: Color {
        guard isEnabled else { return .clear }
        switch style {
        case .primary: return KYColor.accentGlow.opacity(0.7)
        case .danger: return KYColor.recGlow.opacity(0.7)
        case .secondary, .ghost: return .clear
        }
    }
}

/// A square icon-only button (popover header, notes-window header).
struct KYIconButton: View {
    let systemImage: String
    var size: CGFloat = 30
    var help: LocalizedStringKey?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(isHovering ? KYColor.text : KYColor.text2)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: KYRadius.button).fill(isHovering ? KYColor.surface2 : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
    }
}

#Preview {
    VStack(spacing: 16) {
        KYButton("开始使用", style: .primary) {}
        KYButton("查看帮助", systemImage: "questionmark.circle") {}
        KYButton("检查更新", style: .ghost, size: .small) {}
        KYButton("已停用", isEnabled: false) {}
        KYButton("停止", style: .danger) {}
        KYIconButton(systemImage: "gearshape") {}
    }
    .padding()
}
