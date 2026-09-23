import SwiftUI

/// Banner per 02-ui-spec.md §1.3 / §4 R5: 38pt tall, 8pt corner radius,
/// 16pt leading icon, 8pt gap, 13pt text.
struct InfoBanner: View {
    let text: LocalizedStringKey
    var systemImage: String = "sparkles"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#3B82F6")!, Color(hex: "#8B5CF6")!],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(KYColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 8).fill(KYColor.bgBanner))
    }
}

#Preview {
    InfoBanner(text: "知鱼录音会自动选择合适的麦克风，确保录音清晰、不中断")
        .padding()
        .frame(width: 480)
}
