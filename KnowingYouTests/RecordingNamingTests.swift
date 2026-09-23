import Foundation
import Testing
@testable import KnowingYou

struct RecordingNamingTests {
    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter.date(from: string)!
    }

    @Test func normalNaming() {
        let name = RecordingNaming.baseName(startedAt: date("2026-09-23 14-30-12"), sourceApp: "腾讯会议", existing: [])
        #expect(name == "2026-09-23 14-30-12 腾讯会议")
    }

    @Test func collisionAppendsIncrementingSuffix() {
        let started = date("2026-09-23 14-30-12")
        let first = RecordingNaming.baseName(startedAt: started, sourceApp: "腾讯会议", existing: ["2026-09-23 14-30-12 腾讯会议"])
        #expect(first == "2026-09-23 14-30-12 腾讯会议 (2)")

        let second = RecordingNaming.baseName(
            startedAt: started,
            sourceApp: "腾讯会议",
            existing: ["2026-09-23 14-30-12 腾讯会议", "2026-09-23 14-30-12 腾讯会议 (2)"]
        )
        #expect(second == "2026-09-23 14-30-12 腾讯会议 (3)")
    }

    @Test func sanitizeReplacesIllegalCharacters() {
        #expect(RecordingNaming.sanitize("A/B:C\\D?E*F\"G<H>I|J") == "A-B-C-D-E-F-G-H-I-J")
    }

    @Test func sanitizeReplacesControlCharactersWithDash() {
        // Control characters are replaced with "-" (like the other illegal
        // characters), not stripped outright; only real whitespace at the
        // ends gets trimmed afterwards.
        #expect(RecordingNaming.sanitize("Zoom\n\t") == "Zoom--")
    }

    @Test func sanitizeTrimsSurroundingWhitespace() {
        #expect(RecordingNaming.sanitize("  Zoom  ") == "Zoom")
    }

    @Test func sanitizeTruncatesTo60Characters() {
        let long = String(repeating: "A", count: 100)
        let result = RecordingNaming.sanitize(long)
        #expect(result.count == 60)
    }

    @Test func sanitizeOfEmptyStringFallsBackToDefault() {
        #expect(RecordingNaming.sanitize("") == "录音")
        #expect(RecordingNaming.sanitize("   ") == "录音")
    }

    @Test func parseRoundTripsWithBaseName() {
        let started = date("2026-09-23 14-30-12")
        let name = RecordingNaming.baseName(startedAt: started, sourceApp: "Zoom", existing: [])
        let parsed = RecordingNaming.parse(name)
        #expect(parsed?.startedAt == started)
        #expect(parsed?.sourceApp == "Zoom")
    }

    @Test func parseRoundTripsCollisionSuffix() {
        let started = date("2026-09-23 14-30-12")
        let name = RecordingNaming.baseName(startedAt: started, sourceApp: "Zoom", existing: ["2026-09-23 14-30-12 Zoom"])
        let parsed = RecordingNaming.parse(name)
        #expect(parsed?.startedAt == started)
        #expect(parsed?.sourceApp == "Zoom (2)")
    }

    @Test func parseFailsOnUnrecognizedFormat() {
        #expect(RecordingNaming.parse("我的录音") == nil)
        #expect(RecordingNaming.parse("") == nil)
        #expect(RecordingNaming.parse("2026-09-23 14-30-12") == nil) // no app name
    }
}
