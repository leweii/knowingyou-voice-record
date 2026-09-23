import SwiftUI

/// Section title + hairline divider per 02-ui-spec.md §1.3: 18pt light title,
/// divider ~14pt below the title baseline, spanning the full content width.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(KYFont.sectionHeader)
                .foregroundStyle(KYColor.textSectionHeader)
            Rectangle()
                .fill(KYColor.strokeHairline)
                .frame(height: 1)
        }
    }
}

#Preview {
    SectionHeader("系统")
        .padding()
        .frame(width: 480)
}
