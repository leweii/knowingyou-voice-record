import AppKit
import SwiftUI

/// Wraps an `NSTextView` for E6 (02-ui-spec.md §10): the placeholder
/// ("随手记下你的灵感和重点") disappears on focus, and every edit is
/// forwarded to `NotesEditorModel` via the exact delegate hook the model was
/// designed around (`shouldChangeTextIn:replacementString:`), then mirrored
/// into `NotesStore`.
struct NotesEditor: NSViewRepresentable {
    let notesStore: NotesStore
    @Binding var isEmpty: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor(KYColor.textPrimary)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Intentionally empty: the coordinator is the source of truth once
        // created (S16 decision record) — re-syncing `fullText` here on every
        // SwiftUI body re-evaluation would fight the user's own typing.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(notesStore: notesStore, isEmpty: $isEmpty)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let notesStore: NotesStore
        private let model = NotesEditorModel()
        private var isEmpty: Binding<Bool>
        weak var textView: NSTextView?

        init(notesStore: NotesStore, isEmpty: Binding<Bool>) {
            self.notesStore = notesStore
            self.isEmpty = isEmpty
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let replacement = replacementString ?? ""
            let range = affectedCharRange.location..<(affectedCharRange.location + affectedCharRange.length)
            let changes = model.applyEdit(range: range, replacement: replacement)
            apply(changes)
            isEmpty.wrappedValue = model.lines.count == 1 && model.lines[0].text.isEmpty
            return true
        }

        private func apply(_ changes: [NotesEditorModel.Change]) {
            for change in changes {
                switch change {
                case .began(let lineID, let at):
                    notesStore.beginEntry(at: at, id: lineID)
                case .updated(let lineID, let text):
                    notesStore.updateEntry(lineID, text: text)
                case .removed(let lineID):
                    notesStore.removeEntry(lineID)
                }
            }
        }
    }
}
