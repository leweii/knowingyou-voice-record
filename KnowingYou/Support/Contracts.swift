import Foundation
import KeyboardShortcuts

// Shared types used across modules. See docs/specs/S00-shared-contracts.md.
// Add new cross-module types here first; keep this file free of implementation logic.

// MARK: - State machine and recording state

/// MeetingCoordinator's application-level state (plan §5.1).
enum AppPhase: Sendable, Equatable {
    case idle
    case meetingActive(MeetingSignal)
    case recording(RecordingInfo)
    case finalizing(RecordingInfo)
}

struct MeetingSignal: Sendable, Equatable {
    let app: KnownApp
    let pids: [pid_t]
    let since: Date
}

/// RecordingSession's internal state.
enum RecordingSessionState: Sendable, Equatable {
    case preparing
    case recording
    case paused
    case stopping
    case finished(URL)
    case failed(KYError)
}

// MARK: - Meeting apps

struct KnownApp: Sendable, Hashable, Codable, Identifiable {
    var id: String { bundleIDPrefix }
    let bundleIDPrefix: String
    let displayNameKey: String
    let kind: Kind
    var isEnabled: Bool

    enum Kind: String, Codable, Sendable {
        case native
        case browser
    }
}

// MARK: - Recording and notes

struct RecordingInfo: Sendable, Equatable {
    let baseName: String
    let directory: URL
    let startedAt: Date
    let sourceApp: String
    /// The triggering `KnownApp.bundleIDPrefix`, when a whitelisted app (not
    /// a manual "手动录音") started this recording — S18's `ScreenshotMarker`
    /// uses it to pick which app's window to capture. `nil` for manual
    /// recordings and any recording started before S18 added this field.
    var sourceBundleIDPrefix: String? = nil

    var audioURL: URL { directory.appendingPathComponent(baseName + ".m4a") }
    var cafURL: URL { directory.appendingPathComponent(baseName + ".caf") }
    var notesURL: URL { directory.appendingPathComponent(baseName + ".md") }
    var assetsDir: URL { directory.appendingPathComponent(baseName, isDirectory: true) }
}

/// A directory scan result (popover "recent recordings" list item).
struct Recording: Sendable, Identifiable, Equatable {
    var id: String { baseName }
    let baseName: String
    let startedAt: Date
    let sourceApp: String
    let audioURL: URL
    let notesURL: URL?
    var duration: TimeInterval?
}

struct NoteEntry: Sendable, Equatable, Codable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case note
        case mark
        case screenshot
        case event
    }

    let id: UUID
    let wallClock: Date
    let offset: TimeInterval
    let kind: Kind
    var text: String
}

struct NotesDocument: Sendable, Equatable {
    var title: String?
    let startedAt: Date
    var endedAt: Date?
    let sourceApp: String
    let audioFileName: String
    var paused: [ClosedRange<Date>]
    var entries: [NoteEntry]

    var isEmpty: Bool { title == nil && entries.isEmpty }
}

// MARK: - Settings

enum AudioFormat: String, Codable, Sendable {
    case monoMix
    case dualTrack
}

enum MicSelection: Codable, Sendable, Equatable, Hashable {
    case smart
    case device(uid: String)
}

enum AppLanguage: String, Codable, Sendable {
    case zhHans = "zh-Hans"
    case en = "en"
}

// MARK: - Notifications

enum NotificationCategory: String, Sendable {
    case meetingDetected = "MEETING_DETECTED"
    case meetingEnded = "MEETING_ENDED"
    case recordingSaved = "RECORDING_SAVED"
}

enum NotificationAction: String, Sendable {
    case startRecording = "START_RECORDING"
    case ignore = "IGNORE"
    case ignoreThisMeeting = "IGNORE_THIS_MEETING"
}

// MARK: - Errors and permissions

enum Permission: Sendable, Equatable {
    case microphone
    case systemAudio
    case notifications
    case screenRecording
}

enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

enum KYError: Error, Sendable, Equatable {
    case permissionDenied(Permission)
    case audioDeviceUnavailable(String)
    case systemAudioTapFailed(OSStatus)
    case saveDirectoryUnwritable(URL)
    case diskFull
    case encodingFailed(String)
}

// MARK: - Global hotkeys

/// Declared here (not in System/HotkeyManager.swift) because the shortcuts
/// settings page (S04) needs to read/reset them before S17 exists to own
/// registration. S17 sets the actual default combos at first launch via
/// `KeyboardShortcuts.setShortcut(_:for:)` rather than redeclaring these.
extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
    static let quickMark = Self("quickMark")
    static let screenshotMark = Self("screenshotMark")
}
