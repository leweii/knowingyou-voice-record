import SwiftUI

/// Disclosure row per 02-ui-spec.md §1.3: 14pt title + a 16pt chevron that
/// flips between down (collapsed) and up (expanded) on click.
struct DisclosureRow: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(KYFont.rowTitle)
                    .foregroundStyle(KYColor.textPrimary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DisclosureRow(title: "支持在以下应用中识别会议", isExpanded: .constant(true))
        .padding()
        .frame(width: 480)
}
