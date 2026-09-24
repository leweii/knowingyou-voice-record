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
}
