import Foundation

/// Pure, unit-testable filename rules (plan §5.3). Flat directory, no
/// subfolders except when screenshot marks exist (S18).
enum RecordingNaming {
    /// Localized in the UI layer to "手动录音" / "Manual Recording"; kept as
    /// a stable key here since Contracts.swift doesn't have a strings table yet.
    static let manualSourceAppKey = "recording.source.manual"

    private static var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }

    /// `existing` should contain every base name (no extension) already
    /// present in the target directory, checked against `.m4a`/`.caf`/`.md`
    /// and same-named asset folders by the caller.
    static func baseName(startedAt: Date, sourceApp: String, existing: Set<String>) -> String {
        let timestamp = timestampFormatter.string(from: startedAt)
        let base = "\(timestamp) \(sanitize(sourceApp))"
        guard existing.contains(base) else { return base }

        var counter = 2
        while existing.contains("\(base) (\(counter))") {
            counter += 1
        }
        return "\(base) (\(counter))"
    }

    static func sanitize(_ appName: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?*\"<>|").union(.controlCharacters)
        var cleaned = ""
        cleaned.unicodeScalars.reserveCapacity(appName.unicodeScalars.count)
        for scalar in appName.unicodeScalars {
            cleaned.unicodeScalars.append(illegal.contains(scalar) ? "-" : scalar)
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(trimmed.prefix(60))
        return truncated.isEmpty ? "录音" : truncated
    }

    /// Inverts `baseName` for files whose name still matches the generated
    /// format. Files the user renamed in Finder fail this and get a fallback
    /// treatment in `RecordingStore` (mtime + raw name).
    static func parse(_ baseName: String) -> (startedAt: Date, sourceApp: String)? {
        let prefixLength = 19 // "yyyy-MM-dd HH-mm-ss"
        guard baseName.count > prefixLength + 1,
              let dateEndIndex = baseName.index(baseName.startIndex, offsetBy: prefixLength, limitedBy: baseName.endIndex),
              baseName[dateEndIndex] == " " else {
            return nil
        }

        let datePart = String(baseName[baseName.startIndex..<dateEndIndex])
        guard let date = timestampFormatter.date(from: datePart) else { return nil }

        let appStart = baseName.index(after: dateEndIndex)
        let sourceApp = String(baseName[appStart...])
        guard !sourceApp.isEmpty else { return nil }
        return (date, sourceApp)
    }
}
