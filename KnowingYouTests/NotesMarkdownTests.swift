import Foundation
import Testing
@testable import KnowingYou

struct NotesMarkdownTests {
    /// Loaded relative to this source file rather than via a bundle
    /// resource lookup — simpler, and avoids any XcodeGen resource-copying
    /// configuration for a single fixture file.
    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private static let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// The exact document behind docs/01-implementation-plan.md §5.3's
    /// example, reconstructed field-for-field so `render` can be checked
    /// against a byte-for-byte copy of that example.
    private static func goldenDocument() -> NotesDocument {
        let startedAt = date(2026, 9, 23, 14, 30, 12)
        return NotesDocument(
            title: "供应商重叠问题讨论",
            startedAt: startedAt,
            endedAt: date(2026, 9, 23, 15, 17, 24),
            sourceApp: "腾讯会议",
            audioFileName: "2026-09-23 14-30-12 腾讯会议.m4a",
            paused: [],
            entries: [
                NoteEntry(id: UUID(), wallClock: date(2026, 9, 23, 14, 32, 5), offset: 113, kind: .note, text: "供应商重叠的 379 组 SKU 需要在下周前确认归属……"),
                NoteEntry(id: UUID(), wallClock: date(2026, 9, 23, 14, 40, 11), offset: 599, kind: .mark, text: ""),
                NoteEntry(id: UUID(), wallClock: date(2026, 9, 23, 14, 45, 30), offset: 918, kind: .screenshot, text: "2026-09-23 14-30-12 腾讯会议/截图 14-45-30.png"),
                NoteEntry(id: UUID(), wallClock: date(2026, 9, 23, 15, 2, 47), offset: 1955, kind: .note, text: "Action：Jay 下周三前给出 42* 与 5* 合并方案"),
            ]
        )
    }

    @Test func rendersByteForByteMatchToThePlanExample() throws {
        let fixtureURL = Self.fixturesDirectory.appendingPathComponent("notes-golden.md")
        let expected = try String(contentsOf: fixtureURL, encoding: .utf8)
        let rendered = NotesMarkdown.render(Self.goldenDocument(), timeZone: Self.shanghai)
        #expect(rendered == expected)
    }

    @Test func parsingTheGoldenFixtureRecoversAllFourEntries() throws {
        let fixtureURL = Self.fixturesDirectory.appendingPathComponent("notes-golden.md")
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let parsed = try NotesMarkdown.parse(text, timeZone: Self.shanghai)

        #expect(parsed.title == "供应商重叠问题讨论")
        #expect(parsed.sourceApp == "腾讯会议")
        #expect(parsed.audioFileName == "2026-09-23 14-30-12 腾讯会议.m4a")
        #expect(parsed.paused.isEmpty)
        #expect(parsed.entries.count == 4)
        #expect(parsed.entries[1].kind == .mark)
        #expect(parsed.entries[1].text.isEmpty)
        #expect(parsed.entries[2].kind == .screenshot)
        #expect(parsed.entries[2].text == "2026-09-23 14-30-12 腾讯会议/截图 14-45-30.png")
        #expect(parsed.entries[3].text == "Action：Jay 下周三前给出 42* 与 5* 合并方案")
    }

    @Test func emptyPausedRendersAsEmptyBrackets() {
        let doc = Self.goldenDocument()
        let rendered = NotesMarkdown.render(doc, timeZone: Self.shanghai)
        #expect(rendered.contains("paused: []\n"))
    }

    @Test func nonEmptyPausedRoundTrips() throws {
        var doc = Self.goldenDocument()
        let pauseStart = Self.date(2026, 9, 23, 14, 35, 0)
        let pauseEnd = Self.date(2026, 9, 23, 14, 35, 30)
        doc.paused = [pauseStart...pauseEnd]

        let rendered = NotesMarkdown.render(doc, timeZone: Self.shanghai)
        let parsed = try NotesMarkdown.parse(rendered, timeZone: Self.shanghai)
        #expect(parsed.paused.count == 1)
        #expect(parsed.paused[0].lowerBound == pauseStart)
        #expect(parsed.paused[0].upperBound == pauseEnd)
    }

    @Test func untitledDocumentUsesAudioBaseNameAsTitle() {
        var doc = Self.goldenDocument()
        doc.title = nil
        let rendered = NotesMarkdown.render(doc, timeZone: Self.shanghai)
        #expect(rendered.contains("title: 2026-09-23 14-30-12 腾讯会议\n"))
        #expect(rendered.contains("\n# 2026-09-23 14-30-12 腾讯会议\n"))
    }

    @Test func unfinishedDocumentLeavesEndedAtAndDurationBlank() {
        var doc = Self.goldenDocument()
        doc.endedAt = nil
        let rendered = NotesMarkdown.render(doc, timeZone: Self.shanghai)
        #expect(rendered.contains("ended_at: \n"))
        #expect(rendered.contains("duration: \n"))
    }

    /// `parse(render(doc))` round-trips every field the on-disk format
    /// actually encodes. Two fields are deliberately excluded from the
    /// comparison, both because they're outside what the format represents
    /// by design — see this spec's decision record:
    /// - `NoteEntry.id`: not written to disk at all (a fresh UUID on parse).
    /// - `NoteEntry.wallClock`'s date component: only time-of-day survives
    ///   the round trip, so entries here are constructed within the same
    ///   calendar day as `startedAt` and compared via `Calendar.isDate(_:equalTo:toGranularity:.second)`.
    @Test func roundTripsTwentyRandomEntries() throws {
        var generator = SystemRandomNumberGenerator()
        let startedAt = Self.date(2026, 9, 23, 9, 0, 0)
        let kinds: [NoteEntry.Kind] = [.note, .mark, .screenshot, .event]

        var entries: [NoteEntry] = []
        for i in 0..<20 {
            let offset = TimeInterval(Int.random(in: 1...3599, using: &generator))
            let kind = kinds[Int.random(in: 0..<kinds.count, using: &generator)]
            let text = kind == .mark ? "" : "entry #\(i) 内容"
            entries.append(NoteEntry(id: UUID(), wallClock: startedAt.addingTimeInterval(offset), offset: offset, kind: kind, text: text))
        }

        let doc = NotesDocument(
            title: "随机往返测试",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3600),
            sourceApp: "手动录音",
            audioFileName: "test.m4a",
            paused: [],
            entries: entries
        )

        let rendered = NotesMarkdown.render(doc, timeZone: Self.shanghai)
        let parsed = try NotesMarkdown.parse(rendered, timeZone: Self.shanghai)

        #expect(parsed.title == doc.title)
        #expect(parsed.sourceApp == doc.sourceApp)
        #expect(parsed.audioFileName == doc.audioFileName)
        #expect(parsed.entries.count == doc.entries.count)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.shanghai
        for (original, roundTripped) in zip(doc.entries, parsed.entries) {
            #expect(roundTripped.kind == original.kind)
            #expect(roundTripped.text == original.text)
            #expect(abs(roundTripped.offset - original.offset) < 1)
            #expect(calendar.isDate(roundTripped.wallClock, equalTo: original.wallClock, toGranularity: .second))
        }
    }
}
