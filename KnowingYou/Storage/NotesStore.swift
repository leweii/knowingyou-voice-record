import Foundation

/// The in-memory notes model for one recording, with debounced autosave to
/// `<baseName>.md` (atomic write via a `.tmp` + `replaceItemAt`). Pure
/// storage/state — the notes-window UI (S16) is the only thing that calls
/// these methods.
@MainActor
@Observable
final class NotesStore {
    private(set) var document: NotesDocument
    private let markdownURL: URL

    /// Debounce window: a burst of edits within this window collapses into
    /// one write, timed from the *last* edit — not a fixed-tick poll. Var
    /// (not `let`) so tests can shrink it instead of waiting 3 real seconds.
    var autosaveInterval: TimeInterval = 3

    /// Test-observability only: how many times a write actually happened.
    private(set) var writeCount = 0

    private var hasUnsavedChanges = false
    private var autosaveTask: Task<Void, Never>?

    init(info: RecordingInfo) {
        self.markdownURL = info.notesURL
        self.document = NotesDocument(
            title: nil,
            startedAt: info.startedAt,
            endedAt: nil,
            sourceApp: info.sourceApp,
            audioFileName: info.baseName + ".m4a",
            paused: [],
            entries: []
        )
    }

    func setTitle(_ title: String) {
        document.title = title.isEmpty ? nil : title
        markDirty()
    }

    /// Called the moment the first character of a new entry lands — the
    /// entry's timestamp is fixed at this instant regardless of how long the
    /// user then spends editing it (plan §5.3).
    /// `id` defaults to a fresh UUID; `NotesEditor` (S16) passes its own
    /// `NotesEditorModel.Line.id` explicitly instead, so the editor's line
    /// identity and the store's entry identity are the same UUID and no
    /// separate mapping table is needed.
    @discardableResult
    func beginEntry(at wallClock: Date, kind: NoteEntry.Kind = .note, id: NoteEntry.ID = UUID()) -> NoteEntry.ID {
        let entry = NoteEntry(id: id, wallClock: wallClock, offset: wallClock.timeIntervalSince(document.startedAt), kind: kind, text: "")
        document.entries.append(entry)
        markDirty()
        return entry.id
    }

    func updateEntry(_ id: NoteEntry.ID, text: String) {
        guard let index = document.entries.firstIndex(where: { $0.id == id }) else { return }
        document.entries[index].text = text
        markDirty()
    }

    /// Used when the notes editor merges/removes a line (backspace on an
    /// empty entry, or the two halves of an Enter-split later getting
    /// deleted) — the on-disk `.md` should never show an entry the user no
    /// longer has text for.
    func removeEntry(_ id: NoteEntry.ID) {
        guard let index = document.entries.firstIndex(where: { $0.id == id }) else { return }
        document.entries.remove(at: index)
        markDirty()
    }

    @discardableResult
    func addMark(at wallClock: Date) -> NoteEntry.ID {
        beginEntry(at: wallClock, kind: .mark)
    }

    @discardableResult
    func addScreenshot(path: String, at wallClock: Date) -> NoteEntry.ID {
        let id = beginEntry(at: wallClock, kind: .screenshot)
        updateEntry(id, text: path)
        return id
    }

    @discardableResult
    func addEvent(_ text: String, at wallClock: Date) -> NoteEntry.ID {
        let id = beginEntry(at: wallClock, kind: .event)
        updateEntry(id, text: text)
        return id
    }

    func recordPause(_ range: ClosedRange<Date>) {
        document.paused.append(range)
        markDirty()
    }

    /// Sets `ended_at`, cancels any pending debounced write, and writes
    /// synchronously so the caller can rely on the file being complete the
    /// moment this returns.
    func finish(endedAt: Date) async throws {
        document.endedAt = endedAt
        hasUnsavedChanges = true
        autosaveTask?.cancel()
        autosaveTask = nil
        try await write()
    }

    private func markDirty() {
        hasUnsavedChanges = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.autosaveInterval))
            guard !Task.isCancelled else { return }
            try? await self.write()
        }
    }

    private func write() async throws {
        guard hasUnsavedChanges else { return }
        guard !document.isEmpty else { return }
        hasUnsavedChanges = false

        let directory = markdownURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw KYError.saveDirectoryUnwritable(directory)
            }
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw KYError.saveDirectoryUnwritable(directory)
        }

        let text = NotesMarkdown.render(document)
        let tmpURL = markdownURL.appendingPathExtension("tmp")
        do {
            try text.write(to: tmpURL, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(markdownURL, withItemAt: tmpURL)
            writeCount += 1
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            hasUnsavedChanges = true // keep retrying on the next edit/finish — don't lose the in-memory data
            throw KYError.saveDirectoryUnwritable(directory)
        }
    }
}
