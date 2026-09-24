import CoreGraphics
import Foundation
import Testing
@testable import KnowingYou

@MainActor
struct PreferencesTests {
    private func makePreferences(suite: String = #function) -> Preferences {
        let defaults = UserDefaults(suiteName: "com.jakobhe.knowingyou.tests.\(suite)")!
        defaults.removePersistentDomain(forName: "com.jakobhe.knowingyou.tests.\(suite)")
        return Preferences(defaults: defaults)
    }

    @Test func boolDefaultsMatchContractTable() {
        let prefs = makePreferences()
        #expect(prefs.launchAtLogin == true)
        #expect(prefs.showDockIcon == false)
        #expect(prefs.showFloatingWidget == true)
        #expect(prefs.captureSystemAudio == true)
        #expect(prefs.autoRecord == false)
        #expect(prefs.hotkeysEnabled == true)
        #expect(prefs.notifyMeetingDetected == true)
        #expect(prefs.notifyMeetingEnded == true)
        #expect(prefs.notifyRecordingSaved == true)
        #expect(prefs.hasCompletedOnboarding == false)
        #expect(prefs.recentRecordingsExpanded == false)
    }

    @Test func enumDefaultsMatchContractTable() {
        let prefs = makePreferences()
        #expect(prefs.micSelection == .smart)
        #expect(prefs.audioFormat == .monoMix)
    }

    @Test func knownAppsDefaultsToEmptyUntilSeeded() {
        let prefs = makePreferences()
        #expect(prefs.knownApps.isEmpty)
    }

    @Test func floatingWidgetOriginDefaultsToNil() {
        let prefs = makePreferences()
        #expect(prefs.floatingWidgetOrigin == nil)
    }

    @Test func notesWindowSizeDefaultsToNil() {
        let prefs = makePreferences()
        #expect(prefs.notesWindowSize == nil)
    }

    @Test func notesWindowSizeRoundTripsAndCanBeCleared() {
        let prefs = makePreferences()
        prefs.notesWindowSize = CGSize(width: 500, height: 420)
        #expect(prefs.notesWindowSize == CGSize(width: 500, height: 420))

        prefs.notesWindowSize = nil
        #expect(prefs.notesWindowSize == nil)
    }

    @Test func saveDirectoryPathDefaultsByLanguage() {
        let prefs = makePreferences()
        prefs.appLanguage = .zhHans
        let zh = Preferences.defaultSaveDirectoryPath(for: .zhHans)
        #expect(zh.hasSuffix("知鱼录音"))

        let en = Preferences.defaultSaveDirectoryPath(for: .en)
        #expect(en.hasSuffix("Knowing You"))
    }

    /// S20 edge case #13: switching the display language after
    /// `saveDirectoryPath` has already been computed/persisted must not
    /// move the user's existing recordings out from under them.
    @Test func saveDirectoryPathDoesNotChangeAfterLaterLanguageSwitch() {
        let prefs = makePreferences()
        prefs.appLanguage = .zhHans
        let originalPath = prefs.saveDirectoryPath // first read computes + persists it
        #expect(originalPath.hasSuffix("知鱼录音"))

        prefs.appLanguage = .en
        #expect(prefs.saveDirectoryPath == originalPath)
        #expect(prefs.saveDirectoryPath.hasSuffix("知鱼录音")) // still the old folder, not "Knowing You"
    }

    @Test func writtenValuesPersist() {
        let prefs = makePreferences()
        prefs.autoRecord = true
        prefs.audioFormat = .dualTrack
        prefs.micSelection = .device(uid: "abc-123")
        prefs.floatingWidgetOrigin = CGPoint(x: 10, y: 20)

        #expect(prefs.autoRecord == true)
        #expect(prefs.audioFormat == .dualTrack)
        #expect(prefs.micSelection == .device(uid: "abc-123"))
        #expect(prefs.floatingWidgetOrigin == CGPoint(x: 10, y: 20))
    }
}
