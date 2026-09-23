import SwiftUI

/// F1–F3: the 203pt-wide sidebar, its 5-item list, and the bottom
/// app-identity card (which replaces the reference's account/membership card).
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage

    private let width: CGFloat = 203

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(SettingsPage.allCases) { page in
                    SidebarItem(title: page.title, systemImage: page.systemImage, isSelected: selection == page) {
                        selection = page
                    }
                }
            }
            .padding(.top, 38)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            SidebarBottomCard {
                selection = .about
            }
            .padding(.bottom, 16)
        }
        .frame(width: width)
        .background(KYColor.bgSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(KYColor.strokeHairline)
                .frame(width: 1)
        }
    }
}

/// F3: circular app icon + app name + version, standing in for the
/// reference's avatar/membership card. Tapping it jumps to the About page.
private struct SidebarBottomCard: View {
    let action: () -> Void

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(KYColor.bgSidebarSelected)
                    .frame(width: 40, height: 40)
                    .overlay {
                        KYBrand.logo(size: 22)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("知鱼录音")
                        .font(KYFont.sidebarCardTitle)
                        .foregroundStyle(KYColor.textPrimary)
                    Text(String(format: String(localized: "本地版 · v%@"), versionString))
                        .font(KYFont.sidebarCardSubtitle)
                        .foregroundStyle(KYColor.textGold)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(KYColor.textSecondary)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsSidebar(selection: .constant(.general))
        .frame(height: 520)
}
