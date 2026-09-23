import AppKit

/// G8 "导出诊断日志". This is the minimal S03 version: a settings snapshot only.
/// S19 adds the OSLog export and zips both into one file.
@MainActor
enum DiagnosticsExport {
    static func export() {
        let panel = NSSavePanel()
        panel.title = "导出诊断信息"
        panel.nameFieldStringValue = "知鱼录音诊断-\(dateStamp()).json"
        panel.allowedContentTypes = [.json]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try settingsSnapshotJSON().write(to: url)
            } catch {
                AppLog.system.error("diagnostics export failed: \(error, privacy: .public)")
            }
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    /// Home directory paths are replaced with `~` before writing — this file
    /// is meant to be shareable without leaking the user's account name.
    private static func settingsSnapshotJSON() throws -> Data {
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
}
