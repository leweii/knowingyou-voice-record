import SwiftUI

/// Routes the sidebar selection to a page. Page changes cross-fade (see
/// `AnyTransition.pageIn` for why there's no slide or blur).
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

extension AnyTransition {
    /// Insertion: fade in. Removal: instant fade so two pages never visibly
    /// overlap.
    ///
    /// Fade only — no blur-in and no slide-up, though the prototype has both.
    /// Measured on a 1× external display (2026-10-09, Jakob: "切换 tab 之后才会
    /// 不够 sharp"): fading and moving the page *together* (even SwiftUI's own
    /// `.opacity.combined(with: .offset)`) leaves the page's scroll-view
    /// content showing a snapshot taken mid-slide at a sub-pixel position, so
    /// its text stays blurry after the animation ends (edge contrast 68.6 vs
    /// 116.7 when sharp). Fade alone, or slide alone, stays sharp. A lingering
    /// `.blur(radius: 0)` from the old blur-in had the same kind of effect.
    static var pageIn: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity.animation(.linear(duration: 0.08))
        )
    }
}

#Preview {
    SettingsRootView()
}
