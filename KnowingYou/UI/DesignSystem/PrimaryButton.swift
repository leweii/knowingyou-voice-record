import SwiftUI

/// Popover primary button per 02-ui-spec.md §1.3 / §8 P5: 40pt tall, 10pt
/// corner radius. `.recording` is the red "停止录音 hh:mm:ss" state (S11/S13).
struct PrimaryButton: View {
    enum Style {
        case normal
        case recording

        var fill: Color {
            switch self {
            case .normal: KYColor.controlOn
            case .recording: Color(hex: "#DD3333")!
            }
        }
    }

    let title: LocalizedStringKey
    var style: Style = .normal
    var leadingSystemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let leadingSystemImage {
                    Image(systemName: leadingSystemImage)
                }
                Text(title)
            }
            .font(KYFont.popoverPrimaryButton)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(style.fill))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "开始录音") {}
        PrimaryButton(title: "停止录音  00:12:34", style: .recording, leadingSystemImage: "stop.fill") {}
    }
    .padding()
    .frame(width: 280)
}
