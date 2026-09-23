import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Captures the frontmost window of the meeting app (or, for a manual
/// recording with no detected source app, the frontmost window overall) as
/// a PNG next to the recording, on demand (E12 / ⌥⌘S).
actor ScreenshotMarker {
    enum CaptureError: Error, Equatable {
        case noMatchingWindow
        case pngEncodingFailed
    }

    /// Returns the path (relative to the save directory) to embed as
    /// `![[<path>]]` in the notes: `"<baseName>/截图 HH-mm-ss.png"`.
    func capture(for info: RecordingInfo, sourceBundleIDPrefix: String?, at wallClock: Date) async throws -> String {
        try await ensurePermission()

        let content = try await SCShareableContent.current
        let window = try Self.selectWindow(from: content.windows, sourceBundleIDPrefix: sourceBundleIDPrefix)

        let image = try await captureImage(of: window)

        let directory = info.assetsDir
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = Self.filename(for: wallClock)
        let fileURL = directory.appendingPathComponent(filename)
        try Self.writePNG(image, to: fileURL)

        return "\(info.baseName)/\(filename)"
    }

    private func ensurePermission() async throws {
        let status = await Permissions.shared.status(.screenRecording)
        guard status != .granted else { return }
        let requested = await Permissions.shared.request(.screenRecording)
        guard requested == .granted else {
            throw KYError.permissionDenied(.screenRecording)
        }
    }

    private func captureImage(of window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // `SCStreamConfiguration`, not the macOS-26-only `SCScreenshotConfiguration`
        // — this app's deployment target is 14.4, and this overload of
        // `captureImage` has been available since 14.0.
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Picks the on-screen, non-desktop, non-self window that best matches
    /// `sourceBundleIDPrefix` — the largest such window if several processes
    /// under that prefix have one (Electron/multi-window apps), or the
    /// frontmost window overall if there's no source app to match (a manual
    /// recording) or nothing matched. "Frontmost" is real on-screen z-order
    /// from `CGWindowListCopyWindowInfo` (`SCWindow` itself doesn't expose
    /// ordering), not just "first in whatever order SCShareableContent
    /// happens to return."
    static func selectWindow(from windows: [SCWindow], sourceBundleIDPrefix: String?) throws -> SCWindow {
        let ownPID = getpid()
        let zOrder = onScreenWindowIDsFrontToBack()

        let candidates = windows
            .filter { window in
                window.isOnScreen
                    && window.windowLayer == 0
                    && window.owningApplication?.processID != ownPID
                    && zOrder[window.windowID] != nil
            }
            .sorted { (zOrder[$0.windowID] ?? .max) < (zOrder[$1.windowID] ?? .max) }

        if let prefix = sourceBundleIDPrefix {
            let matched = candidates.filter { $0.owningApplication?.bundleIdentifier.hasPrefix(prefix) == true }
            if matched.count > 1 {
                // Multiple windows under the same app: prefer the largest
                // (a video-call app's main window vs. small toolbars/panels).
                if let largest = matched.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
                    return largest
                }
            } else if let onlyMatch = matched.first {
                return onlyMatch
            }
        }

        guard let frontmost = candidates.first else {
            throw CaptureError.noMatchingWindow
        }
        return frontmost
    }

    /// `kCGWindowListOptionOnScreenOnly` returns windows in real front-to-back
    /// z-order — this is how `selectWindow` knows what "frontmost" means.
    private static func onScreenWindowIDsFrontToBack() -> [CGWindowID: Int] {
        guard let infoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[CFString: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in infoList.enumerated() {
            guard let number = info[kCGWindowNumber] as? CGWindowID else { continue }
            order[number] = index
        }
        return order
    }

    private static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH-mm-ss"
        return "截图 \(formatter.string(from: date)).png"
    }

    /// PNG via `CGImageDestination` directly — not `NSImage`'s TIFF
    /// representation round-tripped through a PNG bitmap rep, which loses
    /// fidelity and is slower for no benefit here.
    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.pngEncodingFailed
        }
    }
}
