import AVFoundation
import AppKit
import CoreMedia
import Foundation

/// Scans the save directory for recordings, pairs `.md` notes, surfaces
/// leftover `.caf` files for crash recovery, and stays in sync with both
/// Finder (via a directory `DispatchSource`) and Preferences (via
/// `UserDefaults.didChangeNotification`).
@MainActor
@Observable
final class RecordingStore {
    static let shared = RecordingStore()

    private(set) var rootDirectory: URL
    private(set) var recordings: [Recording] = []
    private(set) var recoveryCandidates: [URL] = []

    private let watchesFileSystem: Bool
    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var preferencesObserver: NSObjectProtocol?

    /// `watchFileSystem: false` for tests — avoids DispatchSource/UserDefaults
    /// notification side effects touching real system state.
    init(rootDirectory: URL? = nil, watchFileSystem: Bool = true) {
        self.rootDirectory = rootDirectory ?? URL(fileURLWithPath: Preferences.shared.saveDirectoryPath)
        self.watchesFileSystem = watchFileSystem
        refresh()
        if watchFileSystem {
            startWatchingDirectory()
            startObservingPreferences()
        }
    }

    // No deinit: `deinit` runs nonisolated even on a `@MainActor` class, so it
    // can't touch these actor-isolated properties. Not an issue in
    // practice — `.shared` lives for the process lifetime, and test
    // instances are created with `watchFileSystem: false`.

    func ensureWritable() throws {
        try SaveDirectory.ensureExists(at: rootDirectory.path)
        guard SaveDirectory.isWritable(at: rootDirectory.path) else {
            throw KYError.saveDirectoryUnwritable(rootDirectory)
        }
    }

    func updateRootDirectory(_ url: URL) {
        guard url != rootDirectory else { return }
        rootDirectory = url
        if watchesFileSystem {
            stopWatchingDirectory()
            startWatchingDirectory()
        }
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            recordings = []
            recoveryCandidates = []
            return
        }

        let m4aFiles = items.filter { $0.pathExtension.lowercased() == "m4a" }
        let mdBaseNames = Set(
            items.filter { $0.pathExtension.lowercased() == "md" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )

        recordings = m4aFiles.map { url -> Recording in
            let baseName = url.deletingPathExtension().lastPathComponent
            let parsed = RecordingNaming.parse(baseName)
            let startedAt = parsed?.startedAt ?? modificationDate(of: url) ?? .distantPast
            let sourceApp = parsed?.sourceApp ?? baseName
            let notesURL = mdBaseNames.contains(baseName)
                ? rootDirectory.appendingPathComponent(baseName + ".md")
                : nil
            return Recording(
                baseName: baseName,
                startedAt: startedAt,
                sourceApp: sourceApp,
                audioURL: url,
                notesURL: notesURL,
                duration: nil
            )
        }
        .sorted { $0.startedAt > $1.startedAt }

        recoveryCandidates = items.filter { $0.pathExtension.lowercased() == "caf" }
    }

    func duration(for recording: Recording) async -> TimeInterval? {
        let asset = AVURLAsset(url: recording.audioURL)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }

    /// Transcodes a leftover `.caf` (from a crash/force-quit mid-recording)
    /// back into a playable `.m4a`, then deletes the `.caf`.
    @discardableResult
    func recover(_ cafURL: URL, format: AudioFormat? = nil) async throws -> URL {
        let baseName = cafURL.deletingPathExtension().lastPathComponent
        let m4aURL = rootDirectory.appendingPathComponent(baseName + ".m4a")
        try await Encoder.encode(caf: cafURL, to: m4aURL, format: format ?? Preferences.shared.audioFormat)
        try? FileManager.default.removeItem(at: cafURL)
        refresh()
        return m4aURL
    }

    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.audioURL])
    }

    func revealRootInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([rootDirectory])
    }

    func diskUsage() async -> Int64 {
        let path = rootDirectory.path
        return await Task.detached(priority: .utility) {
            SaveDirectory.directorySize(at: path)
        }.value
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func startWatchingDirectory() {
        let fd = open(rootDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directoryMonitorSource = source
    }

    private func stopWatchingDirectory() {
        directoryMonitorSource?.cancel()
        directoryMonitorSource = nil
    }

    private func startObservingPreferences() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newPath = Preferences.shared.saveDirectoryPath
                if newPath != self.rootDirectory.path {
                    self.updateRootDirectory(URL(fileURLWithPath: newPath))
                }
            }
        }
    }
}
