import AVFoundation
import Foundation
import Testing
@testable import KnowingYou

@MainActor
struct RecordingStoreTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KYRecordingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func scansAndPairsNotesFiles() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let names = [
            "2026-09-23 09-00-00 腾讯会议",
            "2026-09-23 10-00-00 Zoom",
            "我改过名字的会议",
        ]
        for name in names {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name + ".m4a").path, contents: Data())
        }
        FileManager.default.createFile(atPath: dir.appendingPathComponent(names[0] + ".md").path, contents: Data())
        // The renamed file falls back to its mtime, which defaults to "now" -
        // pin it to the past so sort order is deterministic regardless of
        // when "now" happens to be relative to the two fixed 2026 timestamps.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: dir.appendingPathComponent(names[2] + ".m4a").path
        )

        let store = RecordingStore(rootDirectory: dir, watchFileSystem: false)

        #expect(store.recordings.count == 3)
        // Newest (parsed) start time first.
        #expect(store.recordings[0].baseName == names[1])
        #expect(store.recordings[1].baseName == names[0])
        #expect(store.recordings[1].notesURL != nil)
        #expect(store.recordings[0].notesURL == nil)

        let renamed = store.recordings.first { $0.baseName == names[2] }
        #expect(renamed != nil)
        #expect(renamed?.sourceApp == names[2]) // fallback: whole name, since parse() failed
    }

    @Test func recoveryCandidatesFindsLeftoverCAFFiles() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        FileManager.default.createFile(atPath: dir.appendingPathComponent("a.caf").path, contents: Data())
        FileManager.default.createFile(atPath: dir.appendingPathComponent("b.m4a").path, contents: Data())

        let store = RecordingStore(rootDirectory: dir, watchFileSystem: false)
        #expect(store.recoveryCandidates.count == 1)
        #expect(store.recoveryCandidates[0].lastPathComponent == "a.caf")
    }

    @Test func ensureWritableThrowsForReadOnlyDirectory() throws {
        let dir = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        let store = RecordingStore(rootDirectory: dir, watchFileSystem: false)
        #expect(throws: KYError.self) { try store.ensureWritable() }
    }

    @Test func recoverTranscodesLeftoverCAFAndDeletesIt() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cafURL = dir.appendingPathComponent("2026-09-23 09-00-00 手动录音.caf")
        try Self.writeSilentCAF(to: cafURL, seconds: 0.5)

        let store = RecordingStore(rootDirectory: dir, watchFileSystem: false)
        #expect(store.recoveryCandidates.count == 1)

        let m4aURL = try await store.recover(cafURL, format: .monoMix)

        #expect(FileManager.default.fileExists(atPath: m4aURL.path))
        #expect(!FileManager.default.fileExists(atPath: cafURL.path))
        #expect(store.recoveryCandidates.isEmpty)
        // Compare by basename, not full path/URL equality: `contentsOfDirectory`
        // resolves `/var/...` to `/private/var/...` (a real symlink on macOS)
        // while our own constructed URL doesn't, so the two URLs legitimately
        // point at the same file without being string-equal.
        #expect(m4aURL.lastPathComponent == "2026-09-23 09-00-00 手动录音.m4a")
        #expect(store.recordings.contains { $0.baseName == "2026-09-23 09-00-00 手动录音" })
    }

    private static func writeSilentCAF(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frameCount = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        try file.write(from: buffer)
    }
}
