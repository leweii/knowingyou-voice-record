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
            KnownApp(bundleIDPrefix: "com.tencent", displayNameKey: "腾讯（泛）", kind: .native, isEnabled: true),
            KnownApp(bundleIDPrefix: "com.tencent.xinWeChat", displayNameKey: "微信", kind: .native, isEnabled: true),
        ]
        let match = KnownApps.match(bundleID: "com.tencent.xinWeChat.helper", in: apps)
        #expect(match?.displayNameKey == "微信")
    }

    @Test func disabledAppsCanStillBeMatchedIfCallerPassesThemIn() {
        // `match` itself is pure prefix matching; filtering by `isEnabled` is
        // the caller's (MeetingDetector's) job, not this function's.
        let disabled = KnownApp(bundleIDPrefix: "us.zoom.xos", displayNameKey: "Zoom", kind: .native, isEnabled: false)
        #expect(KnownApps.match(bundleID: "us.zoom.xos", in: [disabled]) != nil)
    }
}
