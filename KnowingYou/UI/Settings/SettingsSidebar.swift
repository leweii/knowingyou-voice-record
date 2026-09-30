import SwiftUI

/// The full-height sidebar: page list with a shared springy selection
/// indicator, and the app-identity card at the bottom (taps → About).
/// Traffic-light buttons float over its top-left (the window uses a
/// transparent full-size-content title bar), hence the top inset.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage

    @Namespace private var indicator
    private let width: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { page in
                    SidebarItem(
                        title: page.title,
                        systemImage: page.systemImage,
                        isSelected: selection == page,
                        indicatorNamespace: indicator
                    ) {
                        withAnimation(KYMotion.state) { selection = page }
                    }
                }
            }
            .padding(.top, 52)
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            SidebarBottomCard {
                withAnimation(KYMotion.state) { selection = .about }
            }
            .padding(10)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(KYColor.bg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(KYColor.stroke).frame(width: 1)
        }
    }
}

/// Mark + name + "本地版 · vX" with a glowing "local" dot.
private struct SidebarBottomCard: View {
    let action: () -> Void

    @State private var isHovering = false

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                KYBrand.logo(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("知鱼录音")
                        .font(KYFont.headline)
                        .foregroundStyle(KYColor.text)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(KYColor.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: KYColor.accentGlow, radius: 3)
                        Text(String(format: String(localized: "本地版 · v%@"), versionString))
                            .font(KYFont.small)
                            .foregroundStyle(KYColor.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KYColor.text3)
                    .offset(x: isHovering ? 2 : 0)
            }
            .padding(12)
            .kyCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
    }
}

#Preview {
    SettingsSidebar(selection: .constant(.general))
        .frame(height: 580)
}
