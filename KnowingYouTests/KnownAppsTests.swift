import Testing
@testable import KnowingYou

struct KnownAppsTests {
    @Test func helperProcessMatchesParentAppByPrefix() {
        let match = KnownApps.match(bundleID: "com.bytedance.lark.helper", in: KnownApps.defaults)
        #expect(match?.displayNameKey == "飞书")
    }

    @Test func chromeHelperProcessMatchesChrome() {
        let match = KnownApps.match(bundleID: "com.google.Chrome.helper", in: KnownApps.defaults)
        #expect(match?.displayNameKey == "Chrome")
        #expect(match?.kind == .browser)
    }

    @Test func unknownBundleIDReturnsNil() {
        #expect(KnownApps.match(bundleID: "com.example.NotAMeetingApp", in: KnownApps.defaults) == nil)
    }

    @Test func exactBundleIDMatchesWithoutHelperSuffix() {
        let match = KnownApps.match(bundleID: "us.zoom.xos", in: KnownApps.defaults)
        #expect(match?.displayNameKey == "Zoom")
    }

    @Test func doesNotMatchUnrelatedBundleIDSharingAPrefixWithoutDotSeparator() {
        // "us.zoom.xosPro" is not "us.zoom.xos" followed by a "." — must not match.
        #expect(KnownApps.match(bundleID: "us.zoom.xosPro", in: KnownApps.defaults) == nil)
    }

    @Test func longestPrefixWins() {
        let apps = [
            KnownApp(bundleIDPrefix: "com.tencent", displayNameKey: "腾讯（泛）", kind: .native),
            KnownApp(bundleIDPrefix: "com.tencent.xinWeChat", displayNameKey: "微信", kind: .native),
        ]
        let match = KnownApps.match(bundleID: "com.tencent.xinWeChat.helper", in: apps)
        #expect(match?.displayNameKey == "微信")
    }

    // MARK: - looksLikeMeetingApp (2026-09-24 keyword-heuristic fallback)

    @Test func looksLikeMeetingAppMatchesKnownKeywords() {
        #expect(KnownApps.looksLikeMeetingApp(bundleID: "com.somecompany.SuperMeetPro"))
        #expect(KnownApps.looksLikeMeetingApp(bundleID: "io.example.zoomclone"))
        #expect(KnownApps.looksLikeMeetingApp(bundleID: "com.startup.会议助手"))
    }

    @Test func looksLikeMeetingAppIsCaseInsensitive() {
        #expect(KnownApps.looksLikeMeetingApp(bundleID: "com.company.ZOOMISH"))
    }

    @Test func looksLikeMeetingAppRejectsUnrelatedBundleIDs() {
        #expect(!KnownApps.looksLikeMeetingApp(bundleID: "com.apple.Notes"))
        #expect(!KnownApps.looksLikeMeetingApp(bundleID: "com.spotify.client"))
    }

    @Test func looksLikeMeetingAppAlwaysRejectsAppleBundleIDsEvenWithAKeyword() {
        // Apple's own processes (Siri, Dictation, Control Center audio
        // helpers, etc.) shouldn't trip the heuristic no matter what's in
        // the name — FaceTime is already an exact `defaults` entry, so real
        // Apple meeting software never needs this fallback anyway.
        #expect(!KnownApps.looksLikeMeetingApp(bundleID: "com.apple.SomeMeetingHelper"))
    }
}
