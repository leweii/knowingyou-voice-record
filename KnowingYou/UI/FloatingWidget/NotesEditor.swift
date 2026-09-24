import AppKit
import SwiftUI

/// Wraps an `NSTextView` for E6 (02-ui-spec.md §10): the placeholder
/// ("随手记下你的灵感和重点") disappears on focus, and every edit is
/// forwarded to `NotesEditorModel` via the exact delegate hook the model was
/// designed around (`shouldChangeTextIn:replacementString:`), then mirrored
/// into `NotesStore`. Pasting an image (2026-09-24, Jakob's real-Mac
/// feedback: "要允许我...黏贴图片") is handled separately — see
/// `PasteAwareTextView` and `Coordinator.handlePastedImage`.
struct NotesEditor: NSViewRepresentable {
    let notesStore: NotesStore
    @Binding var isEmpty: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor(KYColor.textPrimary)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.onImagePaste = { [weak coordinator = context.coordinator] image in
            coordinator?.handlePastedImage(image)
        }

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

        /// A pasted image becomes its own `.pastedImage` entry with a real
        /// saved file, the same way E12's screenshot button works — it does
        /// *not* insert a visible line into the text view itself. That's a
        /// deliberate, pre-existing simplification (see S16's decision record
        /// on why E11/E12 don't sync into the editor either): reflecting an
        /// image insertion back into `NotesEditorModel`'s plain-text line
        /// model would need a whole second bidirectional-sync mechanism for
        /// something that already renders correctly in the finished `.md`.
        func handlePastedImage(_ image: NSImage) {
            guard let pngData = Self.pngData(from: image) else { return }
            let wallClock = Date.now
            let filename = Self.filename(for: wallClock)
            let assetsDir = notesStore.info.assetsDir
            do {
                try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                let fileURL = assetsDir.appendingPathComponent(filename)
                try pngData.write(to: fileURL)
                notesStore.addPastedImage(path: "\(notesStore.info.baseName)/\(filename)", at: wallClock)
            } catch {
                AppLog.storage.error("failed to save pasted image: \(error, privacy: .public)")
            }
        }

        private static func pngData(from image: NSImage) -> Data? {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return bitmap.representation(using: .png, properties: [:])
        }

        private static func filename(for date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH-mm-ss"
            return "粘贴 \(formatter.string(from: date)).png"
        }
    }
}

/// Overrides `paste(_:)` (an `NSResponder` action, not something
/// `NSTextViewDelegate` exposes a hook for) to detect an image on the
/// pasteboard before falling back to normal plain-text paste — `isRichText
/// = false` means an image could never paste as anything meaningful through
/// the default path anyway.
private final class PasteAwareTextView: NSTextView {
    var onImagePaste: ((NSImage) -> Void)?

    override func paste(_ sender: Any?) {
        if let image = NSImage(pasteboard: .general) {
            onImagePaste?(image)
        } else {
            super.paste(sender)
        }
    }
}
