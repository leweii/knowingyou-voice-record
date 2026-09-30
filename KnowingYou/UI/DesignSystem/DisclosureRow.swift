import SwiftUI

/// A tappable header with a chevron that rotates between collapsed (→) and
/// expanded (↓). Callers wrap the state change in `KYMotion.state` so the
/// revealed content springs open in step with the chevron.
struct DisclosureRow: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    var font: Font = KYFont.caption
    var color: Color = KYColor.text2

    var body: some View {
        Button {
            withAnimation(KYMotion.state) { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(font)
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KYColor.text2)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DisclosureRow(title: "最近录音", isExpanded: .constant(true))
        .padding()
        .frame(width: 320)
}
