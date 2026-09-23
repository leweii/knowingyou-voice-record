import SwiftUI

/// F4: routes the sidebar selection to a page. All five pages are real as
/// of S04; onboarding/permissions flow (S05) is separate from this window.
struct SettingsRootView: View {
    @State private var selection: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .recording:
                    RecordingSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .notifications:
                    NotificationsSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 520)
        .background(KYColor.bgWindow)
    }
}

#Preview {
    SettingsRootView()
}
