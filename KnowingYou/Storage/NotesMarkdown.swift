import Foundation

/// Exact-byte Markdown serialization for `NotesDocument`, per
/// docs/01-implementation-plan.md §5.3. `parse` is the inverse, used mainly
/// by tests to round-trip `render`'s own output — it's deliberately not a
/// robust general-purpose Markdown/YAML parser (see this spec's decision
/// record).
enum NotesMarkdown {
    enum ParseError: Error, Equatable {
        case invalidFrontmatter
        case invalidEntry(String)
    }

    // MARK: - Render

    /// `timeZone` controls how `started_at`/`ended_at`/entry timestamps are
    /// displayed. Defaults to the system's current zone (what a user reading
    /// their own notes wants); tests pin it to a fixed zone so the golden
    /// fixture doesn't depend on the machine's local timezone.
    static func render(_ doc: NotesDocument, timeZone: TimeZone = .current) -> String {
        let title = displayTitle(for: doc)
        var lines: [String] = []

        lines.append("---")
        lines.append("title: \(title)")
        lines.append("started_at: \(iso8601String(doc.startedAt, timeZone: timeZone))")
        lines.append("ended_at: \(doc.endedAt.map { iso8601String($0, timeZone: timeZone) } ?? "")")
        lines.append("duration: \(doc.endedAt.map { durationString($0.timeIntervalSince(doc.startedAt)) } ?? "")")
        lines.append("source_app: \(doc.sourceApp)")
        lines.append("audio: \(doc.audioFileName)")
        lines.append("paused: \(renderPaused(doc.paused, timeZone: timeZone))")
        lines.append("---")
        lines.append("")
        lines.append("# \(title)")

        for entry in doc.entries {
            lines.append("")
            lines.append(renderHeading(entry, timeZone: timeZone))
            if let body = renderBody(entry), !body.isEmpty {
                lines.append(body)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func displayTitle(for doc: NotesDocument) -> String {
        doc.title ?? fallbackTitle(fromAudioFileName: doc.audioFileName)
    }

    private static func fallbackTitle(fromAudioFileName audioFileName: String) -> String {
        (audioFileName as NSString).deletingPathExtension
    }

    private static func renderHeading(_ entry: NoteEntry, timeZone: TimeZone) -> String {
        var heading = "## \(timeOfDayString(entry.wallClock, timeZone: timeZone)) · \(offsetString(entry.offset))"
        switch entry.kind {
        case .note: break
        case .mark: heading += " · [标记]"
        case .screenshot: heading += " · [截图]"
        case .event: heading += " · [事件]"
        case .pastedImage: heading += " · [图片]"
        }
        return heading
    }

    private static func renderBody(_ entry: NoteEntry) -> String? {
        switch entry.kind {
        case .screenshot, .pastedImage:
            return entry.text.isEmpty ? nil : "![[\(entry.text)]]"
        case .note, .mark, .event:
            return entry.text.isEmpty ? nil : entry.text
        }
    }

    private static func renderPaused(_ paused: [ClosedRange<Date>], timeZone: TimeZone) -> String {
        guard !paused.isEmpty else { return "[]" }
        let ranges = paused.map { range in
            "[\"\(iso8601String(range.lowerBound, timeZone: timeZone))\",\"\(iso8601String(range.upperBound, timeZone: timeZone))\"]"
        }
        return "[\(ranges.joined(separator: ", "))]"
    }

    // MARK: - Parse

    static func parse(_ text: String, timeZone: TimeZone = .current) throws -> NotesDocument {
        var lines = text.components(separatedBy: "\n")

        guard lines.first == "---" else { throw ParseError.invalidFrontmatter }
        lines.removeFirst()

        var frontmatter: [String: String] = [:]
        while let line = lines.first, line != "---" {
            lines.removeFirst()
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex])
            var value = String(line[line.index(after: colonIndex)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            frontmatter[key] = value
        }
        guard lines.first == "---" else { throw ParseError.invalidFrontmatter }
        lines.removeFirst()

        guard let startedAtRaw = frontmatter["started_at"], let startedAt = parseISO8601(startedAtRaw),
              let sourceApp = frontmatter["source_app"], let audio = frontmatter["audio"] else {
            throw ParseError.invalidFrontmatter
        }
        let title = frontmatter["title"]
        let endedAt = frontmatter["ended_at"].flatMap { $0.isEmpty ? nil : parseISO8601($0) }
        let paused = try parsePaused(frontmatter["paused"] ?? "[]")

        var body = lines
        while body.first == "" { body.removeFirst() }
        if body.first?.hasPrefix("# ") == true { body.removeFirst() }
        while body.first == "" { body.removeFirst() }

        var entries: [NoteEntry] = []
        var index = 0
        while index < body.count {
            let line = body[index]
            guard line.hasPrefix("## ") else {
                index += 1
                continue
            }
            let entry = try parseEntry(line, remaining: body, index: &index, startedAt: startedAt, timeZone: timeZone)
            entries.append(entry)
        }

        return NotesDocument(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            sourceApp: sourceApp,
            audioFileName: audio,
            paused: paused,
            entries: entries
        )
    }

    private static func parseEntry(
        _ headingLine: String,
        remaining body: [String],
        index: inout Int,
        startedAt: Date,
        timeZone: TimeZone
    ) throws -> NoteEntry {
        let content = String(headingLine.dropFirst(3)) // "## "
        let parts = content.components(separatedBy: " · ")
        guard parts.count >= 2,
              let wallClock = parseTimeOfDay(parts[0], referenceDate: startedAt, timeZone: timeZone),
              let offset = parseOffset(parts[1]) else {
            throw ParseError.invalidEntry(headingLine)
        }

        var kind: NoteEntry.Kind = .note
        if parts.count >= 3 {
            switch parts[2] {
            case "[标记]": kind = .mark
            case "[截图]": kind = .screenshot
            case "[事件]": kind = .event
            case "[图片]": kind = .pastedImage
            default: break
            }
        }

        index += 1
        var text = ""
        if index < body.count, !body[index].isEmpty, !body[index].hasPrefix("## ") {
            text = body[index]
            if (kind == .screenshot || kind == .pastedImage), text.hasPrefix("![["), text.hasSuffix("]]") {
                text = String(text.dropFirst(3).dropLast(2))
            }
            index += 1
        }
        if index < body.count, body[index].isEmpty {
            index += 1
        }

        return NoteEntry(id: UUID(), wallClock: wallClock, offset: offset, kind: kind, text: text)
    }

    private static func parsePaused(_ raw: String) throws -> [ClosedRange<Date>] {
        var value = raw.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("["), value.hasSuffix("]") else { throw ParseError.invalidFrontmatter }
        value.removeFirst()
        value.removeLast()
        guard !value.isEmpty else { return [] }

        var ranges: [ClosedRange<Date>] = []
        // Each pair looks like ["<iso>","<iso>"] — split on "], [" boundaries.
        let pairPattern = value.components(separatedBy: "], [").map { $0.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "") }
        for pair in pairPattern {
            let dates = pair.components(separatedBy: "\",\"").map { $0.replacingOccurrences(of: "\"", with: "") }
            guard dates.count == 2, let start = parseISO8601(dates[0]), let end = parseISO8601(dates[1]), start <= end else {
                throw ParseError.invalidFrontmatter
            }
            ranges.append(start...end)
        }
        return ranges
    }

    // MARK: - Formatting helpers

    private static func iso8601Formatter(timeZone: TimeZone) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter
    }

    private static func iso8601String(_ date: Date, timeZone: TimeZone) -> String {
        iso8601Formatter(timeZone: timeZone).string(from: date)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        // The timezone is embedded in the string itself, so the formatter's
        // own `timeZone` doesn't matter for parsing.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func timeOfDayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    private static func timeOfDayString(_ date: Date, timeZone: TimeZone) -> String {
        timeOfDayFormatter(timeZone: timeZone).string(from: date)
    }

    /// Reconstructs a `Date` from just a time-of-day string, anchored to
    /// `referenceDate`'s calendar day in `timeZone`. The on-disk format only
    /// ever stores time-of-day for entries (matching plan §5.3's example),
    /// so a `parse`'d entry's date component is only as good as "same day as
    /// `started_at`" — seeing this cross midnight is out of scope (see
    /// decision record).
    private static func parseTimeOfDay(_ string: String, referenceDate: Date, timeZone: TimeZone) -> Date? {
        let components = string.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        dateComponents.hour = components[0]
        dateComponents.minute = components[1]
        dateComponents.second = components[2]
        return calendar.date(from: dateComponents)
    }

    private static func offsetString(_ offset: TimeInterval) -> String {
        "+" + hoursMinutesSeconds(offset)
    }

    private static func parseOffset(_ string: String) -> TimeInterval? {
        guard string.hasPrefix("+") else { return nil }
        return parseHoursMinutesSeconds(String(string.dropFirst()))
    }

    private static func durationString(_ interval: TimeInterval) -> String {
        hoursMinutesSeconds(interval)
    }

    private static func hoursMinutesSeconds(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func parseHoursMinutesSeconds(_ string: String) -> TimeInterval? {
        let components = string.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
    }
}
