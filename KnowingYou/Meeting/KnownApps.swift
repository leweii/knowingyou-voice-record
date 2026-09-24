import Foundation

/// The built-in meeting-app whitelist and the bundle-ID matching rule that
/// both `MeetingDetector` (S12) and the Recording settings page (S04) share.
///
/// Bundle ID verification status (from the S06 spike, see
/// docs/spikes/2026-09-23-process-tap-spike.md): only Slack, Discord,
/// WeChat, and Chrome were confirmed with `mdls` against a real installed
/// app on this machine. Everything else below is an educated guess from
/// public app-ID references and needs a real install to verify — see this
/// spec's decision record.
enum KnownApps {
    static let defaults: [KnownApp] = [
        KnownApp(bundleIDPrefix: "com.tencent.meeting", displayNameKey: "腾讯会议", kind: .native),
        KnownApp(bundleIDPrefix: "com.bytedance.lark", displayNameKey: "飞书", kind: .native),
        KnownApp(bundleIDPrefix: "com.alibaba.DingTalkMac", displayNameKey: "钉钉", kind: .native),
        KnownApp(bundleIDPrefix: "com.tencent.WeWorkMac", displayNameKey: "企业微信", kind: .native),
        KnownApp(bundleIDPrefix: "us.zoom.xos", displayNameKey: "Zoom", kind: .native),
        KnownApp(bundleIDPrefix: "com.microsoft.teams", displayNameKey: "Microsoft Teams", kind: .native),
        KnownApp(bundleIDPrefix: "com.apple.FaceTime", displayNameKey: "FaceTime", kind: .native),
        KnownApp(bundleIDPrefix: "com.tinyspeck.slackmacgap", displayNameKey: "Slack", kind: .native),
        KnownApp(bundleIDPrefix: "com.hnc.Discord", displayNameKey: "Discord", kind: .native),
        KnownApp(bundleIDPrefix: "Cisco-Systems.Spark", displayNameKey: "Webex", kind: .native),
        KnownApp(bundleIDPrefix: "com.tencent.xinWeChat", displayNameKey: "微信", kind: .native),
        // Browsers: detection can only prove "the browser is using the mic,"
        // not which site/tab — so these only ever justify a confirmation
        // prompt, never a silent auto-record (S13's job to enforce via `kind`).
        KnownApp(bundleIDPrefix: "com.google.Chrome", displayNameKey: "Chrome", kind: .browser),
        KnownApp(bundleIDPrefix: "com.apple.Safari", displayNameKey: "Safari", kind: .browser),
        KnownApp(bundleIDPrefix: "org.mozilla.firefox", displayNameKey: "Firefox", kind: .browser),
        KnownApp(bundleIDPrefix: "com.microsoft.edgemac", displayNameKey: "Edge", kind: .browser),
        KnownApp(bundleIDPrefix: "company.thebrowser.Browser", displayNameKey: "Arc", kind: .browser),
    ]

    /// Longest-prefix match: a running process' bundle ID (e.g.
    /// `com.bytedance.lark.helper`, a Chromium/Electron helper process)
    /// matches a `KnownApp` if it equals the app's bundle ID or has it as a
    /// dot-separated prefix. Ties (shouldn't happen with this list, but
    /// could with user-added entries) go to the longest, most specific prefix.
    static func match(bundleID: String, in apps: [KnownApp]) -> KnownApp? {
        apps
            .filter { bundleID == $0.bundleIDPrefix || bundleID.hasPrefix($0.bundleIDPrefix + ".") }
            .max { $0.bundleIDPrefix.count < $1.bundleIDPrefix.count }
    }
}
