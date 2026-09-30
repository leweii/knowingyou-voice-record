import SwiftUI

/// Tinted inline banner. `.info` (accent) explains a setting; `.notice`
/// (amber) is for things the user must take responsibility for, like the
/// recording-consent reminder.
struct InfoBanner: View {
    enum Tone {
        case info
        case notice
    }

    let text: LocalizedStringKey
    var systemImage: String = "sparkles"
    var tone: Tone = .info

    var body: some View {
        let tint = tone == .info ? KYColor.accent : KYColor.warn
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
            Text(text)
                .font(KYFont.caption)
                .foregroundStyle(KYColor.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: KYRadius.card, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: KYRadius.card, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    VStack {
        InfoBanner(text: "知鱼录音会自动选择合适的麦克风，确保录音清晰、不中断")
        InfoBanner(text: "录音前，请确保所有参会者均已获悉会议将被录音。", systemImage: "exclamationmark.triangle", tone: .notice)
    }
    .padding()
    .frame(width: 480)
}
