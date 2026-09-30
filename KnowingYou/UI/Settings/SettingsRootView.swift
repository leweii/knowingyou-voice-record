import SwiftUI

/// Routes the sidebar selection to a page. Page changes cross-fade with a
/// small upward slide + blur-in (prototype §04).
struct SettingsRootView: View {
    static let size = CGSize(width: 760, height: 580)

    @State private var selection: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)

            ZStack {
                page(for: selection)
                    .id(selection)
                    .transition(.pageIn)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(KYColor.surface)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func page(for page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralSettingsView()
        case .recording: RecordingSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .notifications: NotificationsSettingsView()
        case .about: AboutSettingsView()
        }
    }
}

/// Shared page scaffold: large title + lead line, then sections.
struct SettingsPageScaffold<Content: View>: View {
    let title: LocalizedStringKey
    let lead: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(KYFont.title)
                        .foregroundStyle(KYColor.text)
                    Text(lead)
                        .font(KYFont.caption)
                        .foregroundStyle(KYColor.text2)
                }
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PageInModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .offset(y: active ? 10 : 0)
            .blur(radius: active ? 4 : 0)
    }
}

extension AnyTransition {
    /// Insertion: fade + rise + unblur. Removal: instant fade so two pages
    /// never visibly overlap.
    static var pageIn: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PageInModifier(active: true), identity: PageInModifier(active: false)),
            removal: .opacity.animation(.linear(duration: 0.08))
        )
    }
}

#Preview {
    SettingsRootView()
}
