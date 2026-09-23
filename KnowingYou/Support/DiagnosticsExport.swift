import AppKit
import OSLog

/// G8 "导出诊断日志": bundles the last 24h of this app's own `OSLog` entries,
/// a home-directory-scrubbed settings snapshot, and basic system/permission
/// info into one zip the user can attach to a bug report.
@MainActor
enum DiagnosticsExport {
    static func export() {
        Task { await performExport() }
    }

    private static func performExport() async {
        let panel = NSSavePanel()
        panel.title = String(localized: "导出诊断信息")
        panel.nameFieldStringValue = "\(String(localized: "知鱼录音诊断"))-\(dateStamp()).zip"
        panel.allowedContentTypes = [.zip]

        let response = await panel.begin()
        guard response == .OK, let destinationURL = panel.url else { return }

        do {
            try await writeZip(to: destinationURL)
        } catch {
            AppLog.system.error("diagnostics export failed: \(error, privacy: .public)")
        }
    }

    private static func writeZip(to destinationURL: URL) async throws {
        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        try settingsSnapshotJSON().write(to: workDirectory.appendingPathComponent("settings.json"))
        try logText().write(to: workDirectory.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        try await systemInfoText().write(to: workDirectory.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try runDitto(sourceDirectory: workDirectory, destination: destinationURL)
    }

    /// `ditto`'s `-k` makes a zip archive (rather than a `.cpgz`/`.cpio`);
    /// `--sequesterRsrc` keeps resource forks out of the top-level entries —
    /// neither matters much for three plain text/json files, but it's the
    /// documented "make a clean zip of a directory" incantation. Not
    /// `private` so `DiagnosticsExportTests` can verify the zip's structure
    /// directly, without going through the NSSavePanel-driven `export()`.
    static func runDitto(sourceDirectory: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", sourceDirectory.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw KYError.encodingFailed("ditto exited with status \(process.terminationStatus)")
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: .now)
    }

    /// Home directory paths are replaced with `~` before writing — this file
    /// is meant to be shareable without leaking the user's account name. Not
    /// `private` so `DiagnosticsExportTests` can verify the redaction directly.
    static func settingsSnapshotJSON() throws -> Data {
        let prefs = Preferences.shared
        let snapshot: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "launchAtLogin": prefs.launchAtLogin,
            "showDockIcon": prefs.showDockIcon,
            "appLanguage": prefs.appLanguage.rawValue,
            "saveDirectoryPath": SaveDirectory.displayPath(prefs.saveDirectoryPath),
            "showFloatingWidget": prefs.showFloatingWidget,
            "captureSystemAudio": prefs.captureSystemAudio,
            "audioFormat": prefs.audioFormat.rawValue,
            "autoRecord": prefs.autoRecord,
            "hotkeysEnabled": prefs.hotkeysEnabled,
        ]
        return try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
    }

    /// This app isn't sandboxed (`ENABLE_APP_SANDBOX: NO`), so reading its
    /// own process's log entries via `.currentProcessIdentifier` needs no
    /// special entitlement.
    private static func logText() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date.now.addingTimeInterval(-24 * 3600))
        let entries = try store.getEntries(at: since)

        var lines: [String] = []
        for entry in entries {
            guard let log = entry as? OSLogEntryLog, log.subsystem == "com.jakobhe.knowingyou" else { continue }
            lines.append("[\(log.date.formatted(.iso8601))] [\(log.category)] [\(log.level)] \(log.composedMessage)")
        }
        return lines.isEmpty ? "(no log entries in the last 24 hours)" : lines.joined(separator: "\n")
    }

    private static func systemInfoText() async -> String {
        var lines: [String] = []
        lines.append("App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        lines.append("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Model: \(modelIdentifier())")
        for permission in [Permission.microphone, .systemAudio, .notifications, .screenRecording] {
            let status = await Permissions.shared.status(permission)
            lines.append("Permission \(permission): \(status)")
        }
        return lines.joined(separator: "\n")
    }

    private static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var model = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        if let nullIndex = model.firstIndex(of: 0) {
            model.removeSubrange(nullIndex...)
        }
        return String(decoding: model, as: UTF8.self)
    }
}
