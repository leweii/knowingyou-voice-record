import CoreGraphics
import Foundation

/// All `UserDefaults` access goes through here; key names appear nowhere else.
/// See docs/specs/S00-shared-contracts.md for the default-value table this mirrors.
@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key: String {
        case launchAtLogin
        case showDockIcon
        case appLanguage
        case saveDirectoryPath
        case showFloatingWidget
        case micSelection
        case captureSystemAudio
        case audioFormat
        case knownApps
        case autoRecord
        case hotkeysEnabled
        case notifyMeetingDetected
        case notifyMeetingEnded
        case notifyRecordingSaved
        case hasCompletedOnboarding
        case floatingWidgetTopRight
        case recentRecordingsExpanded
        case notesWindowSize
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.launchAtLogin.rawValue: true,
            Key.showDockIcon.rawValue: false,
            Key.showFloatingWidget.rawValue: true,
            Key.captureSystemAudio.rawValue: true,
            Key.autoRecord.rawValue: false,
            Key.hotkeysEnabled.rawValue: true,
            Key.notifyMeetingDetected.rawValue: true,
            Key.notifyMeetingEnded.rawValue: true,
            Key.notifyRecordingSaved.rawValue: true,
            Key.hasCompletedOnboarding.rawValue: false,
            Key.recentRecordingsExpanded.rawValue: false,
        ])
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }

    var showDockIcon: Bool {
        get { defaults.bool(forKey: Key.showDockIcon.rawValue) }
        set { defaults.set(newValue, forKey: Key.showDockIcon.rawValue) }
    }

    var showFloatingWidget: Bool {
        get { defaults.bool(forKey: Key.showFloatingWidget.rawValue) }
        set { defaults.set(newValue, forKey: Key.showFloatingWidget.rawValue) }
    }

    var captureSystemAudio: Bool {
        get { defaults.bool(forKey: Key.captureSystemAudio.rawValue) }
        set { defaults.set(newValue, forKey: Key.captureSystemAudio.rawValue) }
    }

    var autoRecord: Bool {
        get { defaults.bool(forKey: Key.autoRecord.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoRecord.rawValue) }
    }

    var hotkeysEnabled: Bool {
        get { defaults.bool(forKey: Key.hotkeysEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.hotkeysEnabled.rawValue) }
    }

    var notifyMeetingDetected: Bool {
        get { defaults.bool(forKey: Key.notifyMeetingDetected.rawValue) }
        set { defaults.set(newValue, forKey: Key.notifyMeetingDetected.rawValue) }
    }

    var notifyMeetingEnded: Bool {
        get { defaults.bool(forKey: Key.notifyMeetingEnded.rawValue) }
        set { defaults.set(newValue, forKey: Key.notifyMeetingEnded.rawValue) }
    }

    var notifyRecordingSaved: Bool {
        get { defaults.bool(forKey: Key.notifyRecordingSaved.rawValue) }
        set { defaults.set(newValue, forKey: Key.notifyRecordingSaved.rawValue) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding.rawValue) }
    }

    var recentRecordingsExpanded: Bool {
        get { defaults.bool(forKey: Key.recentRecordingsExpanded.rawValue) }
        set { defaults.set(newValue, forKey: Key.recentRecordingsExpanded.rawValue) }
    }

    /// No "follow system" option in the UI Popup (G4); the default is whichever
    /// of the two supported languages matches the system at first read, then it sticks.
    var appLanguage: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Key.appLanguage.rawValue),
                  let value = AppLanguage(rawValue: raw) else {
                return Self.systemPreferredLanguage()
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appLanguage.rawValue) }
    }

    static func systemPreferredLanguage() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        return preferred.hasPrefix("zh") ? .zhHans : .en
    }

    var micSelection: MicSelection {
        get {
            guard let data = defaults.data(forKey: Key.micSelection.rawValue),
                  let value = try? JSONDecoder().decode(MicSelection.self, from: data) else {
                return .smart
            }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.micSelection.rawValue) }
    }

    var audioFormat: AudioFormat {
        get {
            guard let raw = defaults.string(forKey: Key.audioFormat.rawValue),
                  let value = AudioFormat(rawValue: raw) else {
                return .monoMix
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.audioFormat.rawValue) }
    }

    /// Empty until Meeting/KnownApps (S12) seeds the built-in list on first launch.
    var knownApps: [KnownApp] {
        get {
            guard let data = defaults.data(forKey: Key.knownApps.rawValue),
                  let value = try? JSONDecoder().decode([KnownApp].self, from: data) else {
                return []
            }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.knownApps.rawValue) }
    }

    /// Computed from `appLanguage` on first read, then persisted so later language
    /// switches don't move the user's existing recordings (see CLAUDE.md file naming notes).
    var saveDirectoryPath: String {
        get {
            if let path = defaults.string(forKey: Key.saveDirectoryPath.rawValue) {
                return path
            }
            let computed = Self.defaultSaveDirectoryPath(for: appLanguage)
            defaults.set(computed, forKey: Key.saveDirectoryPath.rawValue)
            return computed
        }
        set { defaults.set(newValue, forKey: Key.saveDirectoryPath.rawValue) }
    }

    static func defaultSaveDirectoryPath(for language: AppLanguage) -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderName = language == .en ? "Knowing You" : "知鱼录音"
        return documents.appendingPathComponent(folderName).path
    }

    /// Where the floating widget's top-right corner was when last moved or
    /// closed (screen coordinates). The top-right, not the origin, because
    /// the widget morphs between pill and notes sizes anchored there.
    var floatingWidgetTopRight: CGPoint? {
        get {
            guard let data = defaults.data(forKey: Key.floatingWidgetTopRight.rawValue),
                  let point = try? JSONDecoder().decode(CGPoint.self, from: data) else {
                return nil
            }
            return point
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.floatingWidgetTopRight.rawValue)
                return
            }
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.floatingWidgetTopRight.rawValue)
        }
    }

    /// Remembers the notes-window size across expand/collapse and app
    /// relaunches, now that it's user-resizable (2026-09-24, Jakob's real-Mac
    /// feedback) — `nil` means "use `NotesView.size`'s default".
    var notesWindowSize: CGSize? {
        get {
            guard let data = defaults.data(forKey: Key.notesWindowSize.rawValue),
                  let size = try? JSONDecoder().decode(CGSize.self, from: data) else {
                return nil
            }
            return size
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.notesWindowSize.rawValue)
                return
            }
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.notesWindowSize.rawValue)
        }
    }
}
