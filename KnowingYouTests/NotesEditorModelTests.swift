import Foundation
import Testing
@testable import KnowingYou

@MainActor
struct NotesEditorModelTests {
    @Test func firstCharacterStampsBeganExactlyOnce() {
        let model = NotesEditorModel()
        let lineID = model.lines[0].id
        let now = Date(timeIntervalSince1970: 1000)

        let firstEdit = model.applyEdit(range: 0..<0, replacement: "h", now: now)
        #expect(firstEdit == [.began(lineID: lineID, at: now), .updated(lineID: lineID, text: "h")])

        let later = now.addingTimeInterval(5)
        let secondEdit = model.applyEdit(range: 1..<1, replacement: "i", now: later)
        #expect(secondEdit == [.updated(lineID: lineID, text: "hi")]) // no second `.began`
    }

    @Test func enterSplitsIntoTwoEntriesPreservingTheFirstsIdentity() {
        let model = NotesEditorModel()
        let firstLineID = model.lines[0].id
        let t0 = Date(timeIntervalSince1970: 0)

        model.applyEdit(range: 0..<0, replacement: "第一条", now: t0)
        #expect(model.lines.map(\.text) == ["第一条"])

        let splitTime = t0.addingTimeInterval(2)
        let changes = model.applyEdit(range: 3..<3, replacement: "\n", now: splitTime) // "第一条" is 3 UTF-16 units
        #expect(model.lines.map(\.text) == ["第一条", ""])
        #expect(model.lines[0].id == firstLineID) // first half keeps its original identity/timestamp
        // Second half is a brand-new, still-empty line: no `.began` yet.
        #expect(changes.contains(.updated(lineID: firstLineID, text: "第一条")))
        #expect(!changes.contains { if case .began(let id, _) = $0 { return id == firstLineID } else { return false } })

        let secondLineID = model.lines[1].id
        let typeSecond = model.applyEdit(range: 4..<4, replacement: "第二条", now: t0.addingTimeInterval(4))
        #expect(typeSecond == [.began(lineID: secondLineID, at: t0.addingTimeInterval(4)), .updated(lineID: secondLineID, text: "第二条")])
        #expect(model.lines.map(\.text) == ["第一条", "第二条"])
    }

    @Test func backspaceOnAnEmptyLineMergesWithoutCreatingANewEntry() {
        let model = NotesEditorModel()
        let firstLineID = model.lines[0].id
        model.applyEdit(range: 0..<0, replacement: "第一条")
        // Press Enter to create an empty second line, then backspace it away.
        model.applyEdit(range: 3..<3, replacement: "\n")
        #expect(model.lines.count == 2)

        // Backspace at the start of the empty second line deletes the "\n".
        let changes = model.applyEdit(range: 3..<4, replacement: "")
        #expect(model.lines.map(\.text) == ["第一条"])
        #expect(model.lines[0].id == firstLineID) // merge, not replace
        #expect(changes.contains { if case .removed = $0 { return true } else { return false } })
        // No spurious `.began` for the surviving line — it already began earlier.
        #expect(!changes.contains { if case .began = $0 { return true } else { return false } })
    }

    @Test func pastingMultipleLinesCreatesOneEntryPerLine() {
        let model = NotesEditorModel()
        let firstLineID = model.lines[0].id
        let now = Date(timeIntervalSince1970: 42)

        let changes = model.applyEdit(range: 0..<0, replacement: "line1\nline2\nline3", now: now)
        #expect(model.lines.map(\.text) == ["line1", "line2", "line3"])
        #expect(model.lines[0].id == firstLineID)

        let beganIDs = changes.compactMap { change -> UUID? in
            if case .began(let id, _) = change { return id }
            return nil
        }
        #expect(Set(beganIDs) == Set(model.lines.map(\.id))) // all three began, all at `now`
        for change in changes {
            if case .began(_, let at) = change { #expect(at == now) }
        }
    }

    @Test func clearingALinesTextKeepsItsOriginalTimestamp() {
        // Once an entry has `.began`, that's its timestamp for good — clearing
        // the text back to empty (e.g. select-all + delete within the same
        // line) and retyping doesn't get a second `.began`. `beginEntry` on
        // the `NotesStore` side is a one-time call by design; this mirrors it.
        let model = NotesEditorModel()
        let lineID = model.lines[0].id
        model.applyEdit(range: 0..<0, replacement: "abc")
        let changes = model.applyEdit(range: 0..<3, replacement: "")
        #expect(model.lines.map(\.text) == [""])
        #expect(model.lines[0].id == lineID)
        #expect(changes == [.updated(lineID: lineID, text: "")])

        let restarted = model.applyEdit(range: 0..<0, replacement: "x")
        #expect(restarted == [.updated(lineID: lineID, text: "x")]) // no `.began` again
    }

    @Test func fullTextRoundTripsThroughLineJoins() {
        let model = NotesEditorModel()
        model.applyEdit(range: 0..<0, replacement: "a\nb\nc")
        #expect(model.fullText == "a\nb\nc")
    }
}
