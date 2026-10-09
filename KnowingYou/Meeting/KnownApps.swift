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
        // Browsers: detection can only prove "the browser is using the mic,"
        // not which site/tab — so these only ever justify a confirmation
        // prompt, never a silent auto-record (S13's job to enforce via `kind`).
        KnownApp(bundleIDPrefix: "com.google.Chrome", displayNameKey: "Chrome", kind: .browser),
        KnownApp(bundleIDPrefix: "com.apple.Safari", displayNameKey: "Safari", kind: .browser),
        KnownApp(bundleIDPrefix: "org.mozilla.firefox", displayNameKey: "Firefox", kind: .browser),
        KnownApp(bundleIDPrefix: "com.microsoft.edgemac", displayNameKey: "Edge", kind: .browser),
        KnownApp(bundleIDPrefix: "company.thebrowser.Browser", displayNameKey: "Arc", kind: .browser),
    ]

    /// Former `defaults` entries that turned out to cause false prompts.
    /// WeChat (2026-10-08): it takes the mic for voice-to-text typing far more
    /// often than for calls, so "微信开始使用麦克风" kept prompting while
    /// Jakob was just typing. Bump `retirementVersion` when adding one.
    static let retiredDefaultPrefixes: Set<String> = ["com.tencent.xinWeChat"]
    static let retirementVersion = 1

    /// Settings persists a snapshot of the merged list, so a retired default
    /// would survive in it (and come back through `merged`). Drops those
    /// once per `retirementVersion` — once only, so if the user deliberately
    /// re-adds the app afterwards via "添加应用…", it stays.
    @MainActor static func applyRetirements(to prefs: Preferences) {
        guard prefs.knownAppsRetirementVersion < retirementVersion else { return }
        prefs.knownApps = prefs.knownApps.filter { !retiredDefaultPrefixes.contains($0.bundleIDPrefix) }
        prefs.knownAppsRetirementVersion = retirementVersion
    }

    /// The list actually used for detection and shown in settings: the
    /// built-in `defaults` plus anything the user added themselves. Persisted
    /// lists are a snapshot from whenever they were first seeded, so relying
    /// on them alone silently drops entries added to `defaults` later (e.g.
    /// the browsers — Google Meet in Chrome was never detected because of it)
    /// and yields an empty list if settings were never opened.
    static func merged(stored: [KnownApp]) -> [KnownApp] {
        let defaultPrefixes = Set(defaults.map(\.bundleIDPrefix))
        return defaults + stored.filter { !defaultPrefixes.contains($0.bundleIDPrefix) }
    }

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

    /// Fallback for a process whose bundle ID doesn't match anything in
    /// `defaults`/the user's added-apps list (2026-09-24, Jakob: "应该跟 app
    /// 解耦" — detection shouldn't be limited to a hand-maintained list).
    /// Case-insensitive substring match against the bundle ID only (no
    /// display-name resolution — `MeetingDetector` only has a bundle ID to
    /// work with per active process, see its decision record for why that's
    /// an acceptable scope limit for now). `com.apple.*` is excluded
    /// entirely: the system's own processes (Siri, Dictation, Control
    /// Center's various audio helpers, etc.) shouldn't be treated as
    /// meeting software no matter what a keyword match says — Apple's own
    /// real meeting app, FaceTime, is already an exact `defaults` entry, so
    /// it never needs this fallback anyway.
    static let meetingKeywords = ["meet", "zoom", "webex", "teams", "conference", "会议", "voov"]

    static func looksLikeMeetingApp(bundleID: String) -> Bool {
        guard !bundleID.hasPrefix("com.apple.") else { return false }
        // Input methods (e.g. WeType, com.tencent.inputmethod.wetype) use the
        // mic for dictation, never for meetings.
        guard !bundleID.lowercased().contains(".inputmethod.") else { return false }
        let lowercased = bundleID.lowercased()
        return meetingKeywords.contains { lowercased.contains($0.lowercased()) }
    }
}
