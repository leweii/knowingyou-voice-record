import SwiftUI

/// Settings sidebar row. The selected-row background (with its glowing accent
/// bar) is a single shape shared via `matchedGeometryEffect` across rows, so
/// changing pages makes it spring from the old row to the new one.
struct SidebarItem: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isSelected: Bool
    let indicatorNamespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? KYColor.accent : KYColor.text2)
                    .frame(width: 18)
                Text(title)
                    .font(KYFont.body)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected || isHovering ? KYColor.text : KYColor.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                if isSelected {
                    SidebarIndicator()
                        .matchedGeometryEffect(id: "sidebar-indicator", in: indicatorNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct SidebarIndicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(KYColor.surface3)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KYColor.strokeStrong, lineWidth: 1))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(KYColor.accent)
                    .frame(width: 3, height: 16)
                    .shadow(color: KYColor.accentGlow, radius: 5)
                    .padding(.leading, 1)
            }
    }
}

#Preview {
    SidebarPreview()
}

private struct SidebarPreview: View {
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 2) {
            SidebarItem(title: "通用", systemImage: "gearshape", isSelected: true, indicatorNamespace: ns) {}
            SidebarItem(title: "录音", systemImage: "waveform", isSelected: false, indicatorNamespace: ns) {}
        }
        .padding()
        .frame(width: 220)
        .background(KYColor.bg)
    }
}
