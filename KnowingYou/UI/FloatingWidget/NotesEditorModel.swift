import Foundation

/// Pure entry-segmentation model behind the notes editor's `NSTextView`,
/// decoupled from AppKit entirely so it's unit-testable (this spec's
/// explicit ask). One `Line` = one `NoteEntry`. Edits are expressed exactly
/// the way `NSTextViewDelegate.textView(_:shouldChangeTextIn:replacementString:)`
/// describes them — a flat UTF-16 offset range into the current full text,
/// plus a replacement string — so `NotesEditor` can forward that delegate
/// call here almost verbatim.
@MainActor
final class NotesEditorModel {
    struct Line: Identifiable, Equatable {
        let id: UUID
        var text: String
        /// Set once this line's text first becomes non-empty. Guards
        /// against re-stamping `.began` on every subsequent keystroke, and
        /// lets a line whose content survives a split/merge keep its
        /// original timestamp instead of getting a new one.
        var hasBegun: Bool
    }

    enum Change: Equatable {
        case began(lineID: UUID, at: Date)
        case updated(lineID: UUID, text: String)
        case removed(lineID: UUID)
    }

    private(set) var lines: [Line]

    init() {
        lines = [Line(id: UUID(), text: "", hasBegun: false)]
    }

    var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// `range` is a UTF-16 offset range into the current `fullText`
    /// (`NSRange`/`NSTextView` semantics); `replacement` is what replaces it.
    @discardableResult
    func applyEdit(range: Range<Int>, replacement: String, now: Date = .now) -> [Change] {
        let utf16 = Array(fullText.utf16)
        precondition(range.lowerBound >= 0 && range.upperBound <= utf16.count, "range out of bounds")

        let startLineIndex = lineIndex(ofUTF16Offset: range.lowerBound)
        let endLineIndex = lineIndex(ofUTF16Offset: range.upperBound)

        // Re-derive every line spanning the affected range (not just the
        // edited sub-range) — the edit can change how many lines exist
        // within that span (Enter splits one into two, backspace merges two
        // into one, a multi-line paste can produce many).
        let spanStart = utf16OffsetOfLineStart(startLineIndex)
        let spanEnd = utf16OffsetOfLineEnd(endLineIndex)

        let prefix = decodeUTF16(utf16, spanStart..<range.lowerBound)
        let suffix = decodeUTF16(utf16, range.upperBound..<spanEnd)
        let newLineTexts = (prefix + replacement + suffix).components(separatedBy: "\n")

        if newLineTexts.count == 1, endLineIndex == startLineIndex {
            return applySingleLineEdit(at: startLineIndex, newText: newLineTexts[0], now: now)
        }
        return applyStructuralEdit(range: startLineIndex...endLineIndex, newLineTexts: newLineTexts, now: now)
    }

    private func applySingleLineEdit(at index: Int, newText: String, now: Date) -> [Change] {
        var line = lines[index]
        line.text = newText
        var changes: [Change] = []
        if !line.hasBegun, !newText.isEmpty {
            line.hasBegun = true
            changes.append(.began(lineID: line.id, at: now))
        }
        lines[index] = line
        changes.append(.updated(lineID: line.id, text: newText))
        return changes
    }

    /// The first resulting line always inherits the identity of
    /// `lines[range.lowerBound]` — the part of the original content that
    /// sits before the edit — so a plain "type more characters" or a
    /// "backspace an empty line into its non-empty neighbor" never looks
    /// like a brand-new entry. Every other resulting line is genuinely new.
    private func applyStructuralEdit(range: ClosedRange<Int>, newLineTexts: [String], now: Date) -> [Change] {
        var changes: [Change] = []
        let oldFirstLine = lines[range.lowerBound]

        if range.upperBound > range.lowerBound {
            for index in stride(from: range.upperBound, through: range.lowerBound + 1, by: -1) {
                changes.append(.removed(lineID: lines[index].id))
            }
        }

        var newLines: [Line] = []
        for (offset, text) in newLineTexts.enumerated() {
            if offset == 0 {
                var line = oldFirstLine
                line.text = text
                if !line.hasBegun, !text.isEmpty {
                    line.hasBegun = true
                    changes.append(.began(lineID: line.id, at: now))
                }
                changes.append(.updated(lineID: line.id, text: text))
                newLines.append(line)
            } else {
                let line = Line(id: UUID(), text: text, hasBegun: !text.isEmpty)
                if !text.isEmpty {
                    changes.append(.began(lineID: line.id, at: now))
                }
                changes.append(.updated(lineID: line.id, text: text))
                newLines.append(line)
            }
        }

        lines.removeSubrange(range)
        lines.insert(contentsOf: newLines, at: range.lowerBound)
        return changes
    }

    private func lineIndex(ofUTF16Offset offset: Int) -> Int {
        var consumed = 0
        for (index, line) in lines.enumerated() {
            let length = line.text.utf16.count
            if offset <= consumed + length { return index }
            consumed += length + 1 // +1 for the "\n" separator
        }
        return lines.count - 1
    }

    private func utf16OffsetOfLineStart(_ index: Int) -> Int {
        lines[0..<index].reduce(0) { $0 + $1.text.utf16.count + 1 }
    }

    private func utf16OffsetOfLineEnd(_ index: Int) -> Int {
        utf16OffsetOfLineStart(index) + lines[index].text.utf16.count
    }

    private func decodeUTF16(_ units: [UInt16], _ range: Range<Int>) -> String {
        guard !range.isEmpty else { return "" }
        return String(utf16CodeUnits: Array(units[range]), count: range.count)
    }
}
