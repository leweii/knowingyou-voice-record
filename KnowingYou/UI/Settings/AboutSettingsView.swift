import AppKit
import SwiftUI

/// The 关于 (About) page: animated mark (M1) on a rotating glow, version,
/// the three "local-only" promises as tilt cards, links. Bottom action bar
/// stays pinned while the content scrolls.
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
                VStack(spacing: 22) {
                    hero
                    features
                    learnMore
                }
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            bottomBar
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                RotatingGlow()
                    .frame(width: 112, height: 112)
                KYMark(size: 96, animated: true)
            }
            .frame(width: 130, height: 130)

            Text(appName)
                .font(KYFont.display)
                .foregroundStyle(KYColor.text)

            HStack(spacing: 8) {
                Text(verbatim: "v\(versionString)")
                    .font(KYFont.timestamp)
                    .foregroundStyle(KYColor.text2)
                if isPrerelease {
                    Text(verbatim: "BETA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KYColor.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient(colors: [KYColor.accent, KYColor.accentDeep], startPoint: .leading, endPoint: .trailing)))
                }
                KYButton(isEnglish ? "Check for Updates" : "检查更新", style: .ghost, size: .small, action: openReleasesPage)
            }

            Text(isEnglish
                ? "Knowing You records your online meetings and notes directly on your computer."
                : "知鱼录音可在电脑上直接录制你的线上会议与会议纪要。")
                .font(KYFont.caption)
                .foregroundStyle(KYColor.text2)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    // MARK: - Promises

    private var features: some View {
        HStack(spacing: 10) {
            FeatureCard(
                systemImage: "folder",
                title: isEnglish ? "Stays on this Mac" : "只存本机",
                detail: isEnglish ? "Recordings and notes are saved only to the folder you choose" : "所有录音和纪要只保存在你指定的本地文件夹"
            )
            FeatureCard(
                systemImage: "wifi.slash",
                title: isEnglish ? "No network" : "不联网",
                detail: isEnglish ? "No cloud, no telemetry, no auto-update" : "不上传、不联网，没有云端和遥测"
            )
            FeatureCard(
                systemImage: "person.crop.circle.badge.xmark",
                title: isEnglish ? "No account" : "无需账号",
                detail: isEnglish ? "Open it and start — no sign-up" : "打开即用，不需要注册或登录"
            )
        }
    }

    private var learnMore: some View {
        HStack(spacing: 8) {
            // Placeholder mark until a real GitHub glyph asset lands
            // (same convention as KYBrand's logo placeholder).
            KYButton("GitHub", style: .ghost, size: .small, systemImage: "chevron.left.forwardslash.chevron.right", action: openGitHubPage)
            // Not in the reference screenshots — S19 adds this as a new
            // element (its own spec's deliverable list requires a
            // third-party-licenses document; this is where it's reachable).
            KYButton(isEnglish ? "Third-Party Licenses" : "第三方许可", style: .ghost, size: .small) {
                MarkdownViewerWindow.show(
                    title: isEnglish ? "Third-Party Licenses" : "第三方许可",
                    document: .thirdPartyLicenses
                )
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            KYButton(isEnglish ? "Open Recordings Folder" : "打开录音文件夹", systemImage: "folder", action: openRecordingsFolder)
            Spacer()
            KYButton(isEnglish ? "Terms" : "用户协议", style: .ghost) {
                MarkdownViewerWindow.show(title: isEnglish ? "Terms of Use" : "用户协议", document: .terms)
            }
            KYButton(isEnglish ? "Privacy" : "隐私政策", style: .ghost) {
                MarkdownViewerWindow.show(title: isEnglish ? "Privacy Policy" : "隐私政策", document: .privacy)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(KYColor.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(KYColor.stroke).frame(height: 1)
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

/// Conic brand-color glow, blurred, slowly rotating behind the mark.
private struct RotatingGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let angle = (timeline.date.timeIntervalSinceReferenceDate / 6).truncatingRemainder(dividingBy: 1) * 360
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AngularGradient(
                    colors: [KYColor.accent, KYColor.accentDeep, KYColor.rec, KYColor.warn, KYColor.accent],
                    center: .center,
                    angle: .degrees(angle)
                ))
                .blur(radius: 18)
                .opacity(0.7)
        }
    }
}

/// A promise card that tilts toward the cursor in 3D while hovered.
private struct FeatureCard: View {
    let systemImage: String
    let title: String
    let detail: String

    @State private var tilt: CGSize = .zero
    @State private var isHovering = false
    @State private var cardSize: CGSize = CGSize(width: 150, height: 118)

    /// Max tilt in degrees at the card's edge.
    private static let maxTilt: Double = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(KYColor.accent)
            Text(verbatim: title)
                .font(KYFont.headline)
                .foregroundStyle(KYColor.text)
            Text(verbatim: detail)
                .font(KYFont.caption)
                .foregroundStyle(KYColor.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .kyCard()
        .overlay(
            RoundedRectangle(cornerRadius: KYRadius.card, style: .continuous)
                .strokeBorder(KYColor.accent.opacity(isHovering ? 0.5 : 0), lineWidth: 1)
        )
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { cardSize = proxy.size }
                .onChange(of: proxy.size) { _, newValue in cardSize = newValue }
        })
        .rotation3DEffect(.degrees(Double(tilt.width) * Self.maxTilt * 2), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(Double(-tilt.height) * Self.maxTilt * 2), axis: (x: 1, y: 0, z: 0))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                // Normalize to -0.5...0.5 across the card, clamped so a
                // stale/overshooting location can never over-rotate it.
                let x = min(max(location.x / max(cardSize.width, 1) - 0.5, -0.5), 0.5)
                let y = min(max(location.y / max(cardSize.height, 1) - 0.5, -0.5), 0.5)
                tilt = CGSize(width: x, height: y)
            case .ended:
                isHovering = false
                tilt = .zero
            }
        }
        .kyAnimation(KYMotion.state, value: tilt)
    }
}

#Preview {
    AboutSettingsView()
        .frame(width: 540, height: 580)
}
