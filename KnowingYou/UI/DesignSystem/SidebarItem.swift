import SwiftUI

/// Settings sidebar row per 02-ui-spec.md §1.3: 188×40, 8pt corner radius,
/// 16pt icon centered at x=25, text starting at x=44, selected fill when active.
struct SidebarItem: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Icon center at x=25, text start at x=44 (spec §1.3 SidebarItem).
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textPrimary)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 17)
                Text(title)
                    .font(KYFont.sidebarItem)
                    .foregroundStyle(KYColor.textPrimary)
                    .padding(.leading, 11)
                Spacer(minLength: 0)
            }
            .frame(width: 188, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? KYColor.bgSidebarSelected : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 4) {
        SidebarItem(title: "通用", systemImage: "gearshape", isSelected: true) {}
        SidebarItem(title: "录音", systemImage: "waveform", isSelected: false) {}
    }
    .padding()
    .background(KYColor.bgSidebar)
}
