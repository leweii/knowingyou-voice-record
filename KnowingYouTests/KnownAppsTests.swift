import Foundation
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

    // MARK: - merged(stored:)

    @Test func mergedAddsDefaultsMissingFromAStaleStoredList() {
        // A list persisted before the browser entries existed.
        let stale = KnownApps.defaults.filter { $0.kind == .native }
        let merged = KnownApps.merged(stored: stale)
        #expect(KnownApps.match(bundleID: "com.google.Chrome.helper", in: merged)?.kind == .browser)
    }

    @Test func mergedKeepsUserAddedAppsAndDoesNotDuplicateDefaults() {
        let custom = KnownApp(bundleIDPrefix: "com.example.MyCall", displayNameKey: "MyCall", kind: .native)
        let merged = KnownApps.merged(stored: KnownApps.defaults + [custom])
        #expect(merged.count == KnownApps.defaults.count + 1)
        #expect(merged.contains(custom))
    }

    @Test func mergedOfEmptyStoredIsDefaults() {
        #expect(KnownApps.merged(stored: []) == KnownApps.defaults)
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

    // MARK: - Retired defaults (WeChat, 2026-10-08)

    @MainActor private func freshPreferences(_ suite: String = #function) -> Preferences {
        let name = "com.jakobhe.knowingyou.tests.KnownApps.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults)
    }

    @Test func weChatIsNoLongerADefault() {
        #expect(KnownApps.match(bundleID: "com.tencent.xinWeChat", in: KnownApps.defaults) == nil)
    }

    @MainActor @Test func retirementRemovesAPersistedWeChatEntryOnce() {
        let prefs = freshPreferences()
        let weChat = KnownApp(bundleIDPrefix: "com.tencent.xinWeChat", displayNameKey: "微信", kind: .native)
        prefs.knownApps = KnownApps.defaults + [weChat]

        KnownApps.applyRetirements(to: prefs)
        #expect(!prefs.knownApps.contains(weChat))
        #expect(KnownApps.match(bundleID: "com.tencent.xinWeChat", in: KnownApps.merged(stored: prefs.knownApps)) == nil)

        // Re-added by the user afterwards: stays.
        prefs.knownApps.append(weChat)
        KnownApps.applyRetirements(to: prefs)
        #expect(prefs.knownApps.contains(weChat))
    }

    @Test func inputMethodsAreNeverInferredAsMeetingApps() {
        #expect(!KnownApps.looksLikeMeetingApp(bundleID: "com.example.inputmethod.meetkeyboard"))
        #expect(KnownApps.looksLikeMeetingApp(bundleID: "com.example.meetnow"))
    }
}
