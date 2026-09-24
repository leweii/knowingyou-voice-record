import Foundation
import Testing
@testable import KnowingYou

@MainActor
struct NotesStoreTests {
    private static func makeInfo(in directory: URL) -> RecordingInfo {
        RecordingInfo(baseName: "2026-09-23 09-00-00 手动录音", directory: directory, startedAt: .now, sourceApp: "手动录音")
    }

    private static func withTempDirectory(_ body: (URL) async throws -> Void) async rethrows {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    @Test func emptyDocumentNeverWritesAFile() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.autosaveInterval = 0.05
            try await store.finish(endedAt: .now)
            #expect(!FileManager.default.fileExists(atPath: info.notesURL.path))
            #expect(store.writeCount == 0)
        }
    }

    @Test func titleOnlyProducesAFile() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.setTitle("会议标题")
            try await store.finish(endedAt: .now)
            #expect(FileManager.default.fileExists(atPath: info.notesURL.path))
        }
    }

    @Test func singleMarkProducesAFile() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.addMark(at: .now)
            try await store.finish(endedAt: .now)
            #expect(FileManager.default.fileExists(atPath: info.notesURL.path))
        }
    }

    /// Pasted images (2026-09-24) reuse `addScreenshot`'s pattern but with
    /// their own `NoteEntry.Kind` — this confirms the entry actually lands
    /// with the right kind/text and that `info` (what `NotesEditor` needs to
    /// compute the save path) is exposed correctly.
    @Test func pastedImageProducesAnEntryWithTheGivenPathAndKind() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            #expect(store.info.assetsDir == info.assetsDir)

            let path = "\(info.baseName)/粘贴 10-00-00.png"
            store.addPastedImage(path: path, at: .now)
            try await store.finish(endedAt: .now)

            let text = try String(contentsOf: info.notesURL, encoding: .utf8)
            #expect(text.contains("[图片]"))
            #expect(text.contains("![[\(path)]]"))
        }
    }

    @Test func burstOfEditsWritesAtMostOnceWithinTheDebounceWindow() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.autosaveInterval = 0.1

            let id = store.beginEntry(at: .now)
            for i in 0..<10 {
                store.updateEntry(id, text: "revision \(i)")
            }
            // Still within the debounce window: no write yet.
            #expect(store.writeCount == 0)

            try? await Task.sleep(for: .milliseconds(250))
            #expect(store.writeCount == 1)

            let content = try String(contentsOf: info.notesURL, encoding: .utf8)
            #expect(content.contains("revision 9"))
            #expect(!content.contains("revision 8"))
        }
    }

    @Test func finishWritesImmediatelyWithoutWaitingForTheDebounce() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.autosaveInterval = 10 // long enough that a passing test proves `finish` didn't wait for it

            store.addMark(at: .now)
            try await store.finish(endedAt: .now)

            #expect(FileManager.default.fileExists(atPath: info.notesURL.path))
            #expect(store.writeCount == 1)
        }
    }

    @Test func noLeftoverTmpFileAfterWriting() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.addMark(at: .now)
            try await store.finish(endedAt: .now)

            let tmpURL = info.notesURL.appendingPathExtension("tmp")
            #expect(!FileManager.default.fileExists(atPath: tmpURL.path))
        }
    }

    @Test func finishedDocumentIsFullyReadableImmediately() async throws {
        try await Self.withTempDirectory { directory in
            let info = Self.makeInfo(in: directory)
            let store = NotesStore(info: info)
            store.setTitle("完整性测试")
            store.addMark(at: .now)
            let endedAt = Date.now.addingTimeInterval(60)
            try await store.finish(endedAt: endedAt)

            let parsed = try NotesMarkdown.parse(String(contentsOf: info.notesURL, encoding: .utf8))
            #expect(parsed.title == "完整性测试")
            #expect(parsed.entries.count == 1)
            #expect(parsed.endedAt != nil)
        }
    }
}
