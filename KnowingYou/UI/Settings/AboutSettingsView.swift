import AppKit
import SwiftUI

/// The 关于 (About) page: A1–A14. A11's bottom bar spans only the content
/// area (x 203–720 in the spec, i.e. everything to the right of the sidebar
/// divider) and stays fixed while A1–A10 scroll behind it.
struct AboutSettingsView: View {
    private var isEnglish: Bool { Preferences.shared.appLanguage == .en }

    private var appName: String { isEnglish ? "Knowing You" : "知鱼录音" }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var isPrerelease: Bool {
        Bundle.main.infoDictionary?["KYIsPrerelease"] as? Bool ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider().overlay(KYColor.strokeHairline)
                    introSection
                    Divider().overlay(KYColor.strokeHairline)
                    learnMoreSection
                }
                .padding(24)
            }
            bottomBar
        }
    }

    // MARK: - A1–A4

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(KYColor.bgWindow)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KYColor.strokeButton, lineWidth: 1))
                    .overlay(KYBrand.logo(size: 34))
                    .frame(width: 60, height: 60)
                Spacer()
                OutlinedButton(isEnglish ? "Check for Updates" : "检查更新", height: 30, action: openReleasesPage)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(appName)
                    .font(KYFont.aboutAppName)
                    .foregroundStyle(KYColor.textPrimary)
                HStack(spacing: 4) {
                    Text("v\(versionString)")
                        .font(.system(size: 13))
                        .foregroundStyle(KYColor.textSecondary)
                    if isPrerelease {
                        Text("Beta")
                            .font(.system(size: 12))
                            .foregroundStyle(KYColor.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(KYColor.strokeButton, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - A6–A7

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isEnglish ? "Knowing You keeps your meeting records on this Mac" : "知鱼录音让你的会议记录留在本机")
                .font(KYFont.aboutSubtitle)
                .foregroundStyle(KYColor.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text(isEnglish
                    ? "Knowing You records your online meetings and notes directly on your computer."
                    : "知鱼录音可在电脑上直接录制你的线上会议与会议纪要。")
                Text(isEnglish
                    ? "All recordings and notes are saved only to the local folder you choose - no upload, no network, no account required."
                    : "所有录音和纪要只保存在你指定的本地文件夹，不上传、不联网、不需要账号。")
            }
            .font(.system(size: 13))
            .foregroundStyle(KYColor.textSecondary)
        }
    }

    // MARK: - A9–A10

    private var learnMoreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEnglish ? "Learn more" : "了解更多")
                .font(KYFont.aboutSubtitle)
                .foregroundStyle(KYColor.textPrimary)
            HStack(spacing: 16) {
                Button(action: openGitHubPage) {
                    // Placeholder mark until a real GitHub glyph asset lands
                    // (same convention as KYBrand's logo placeholder).
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 18))
                        .foregroundStyle(KYColor.textPrimary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                // Not in the reference screenshots — S19 adds this as a new
                // element (its own spec's deliverable list requires a
                // third-party-licenses document; this is where it's reachable).
                Button {
                    MarkdownViewerWindow.show(
                        title: isEnglish ? "Third-Party Licenses" : "第三方许可",
                        document: .thirdPartyLicenses
                    )
                } label: {
                    Text(isEnglish ? "Third-Party Licenses" : "第三方许可")
                        .font(.system(size: 13))
                        .foregroundStyle(KYColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - A11–A14

    private var bottomBar: some View {
        HStack {
            OutlinedButton(isEnglish ? "Open Recordings Folder" : "打开录音文件夹", systemImage: "folder", action: openRecordingsFolder)
            Spacer()
            OutlinedButton(isEnglish ? "Terms" : "用户协议") {
                MarkdownViewerWindow.show(title: isEnglish ? "Terms of Use" : "用户协议", document: .terms)
            }
            OutlinedButton(isEnglish ? "Privacy" : "隐私政策") {
                MarkdownViewerWindow.show(title: isEnglish ? "Privacy Policy" : "隐私政策", document: .privacy)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(KYColor.bgSidebar)
        .overlay(alignment: .top) {
            Rectangle().fill(KYColor.strokeHairline).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func openReleasesPage() {
        openInfoPlistURL(key: "KYReleasesURL")
    }

    private func openGitHubPage() {
        openInfoPlistURL(key: "KYGitHubURL")
    }

    private func openInfoPlistURL(key: String) {
        guard let string = Bundle.main.infoDictionary?[key] as? String, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openRecordingsFolder() {
        let url = URL(fileURLWithPath: Preferences.shared.saveDirectoryPath)
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    AboutSettingsView()
        .frame(width: 496, height: 520)
}
