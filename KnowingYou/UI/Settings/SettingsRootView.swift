import SwiftUI

/// F4: routes the sidebar selection to a page. Only 通用 has real content
/// until S04/S05 build the rest.
struct SettingsRootView: View {
    @State private var selection: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .recording, .shortcuts, .notifications, .about:
                    SettingsPagePlaceholder(page: selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 520)
        .background(KYColor.bgWindow)
    }
}

private struct SettingsPagePlaceholder: View {
    let page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title)
                .font(KYFont.sectionHeader)
                .foregroundStyle(KYColor.textSectionHeader)
            Text("待实现")
                .font(KYFont.rowSubtitle)
                .foregroundStyle(KYColor.textSecondary)
        }
        .padding(24)
    }
}

#Preview {
    SettingsRootView()
}
