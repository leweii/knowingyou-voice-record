import Foundation
import Testing
@testable import KnowingYou

struct SaveDirectoryTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KYSaveDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func ensureExistsCreatesMissingDirectory() throws {
        let parent = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let target = parent.appendingPathComponent("知鱼录音", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: target.path))

        try SaveDirectory.ensureExists(at: target.path)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func ensureExistsIsIdempotent() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try SaveDirectory.ensureExists(at: dir.path)
        try SaveDirectory.ensureExists(at: dir.path)
    }

    @Test func writableDirectoryReportsTrue() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(SaveDirectory.isWritable(at: dir.path))
    }

    @Test func readOnlyDirectoryReportsFalse() {
        let dir = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        try! FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        #expect(!SaveDirectory.isWritable(at: dir.path))
    }

    @Test func directorySizeSumsRegularFiles() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(repeating: 0, count: 100).write(to: dir.appendingPathComponent("a.m4a"))
        try Data(repeating: 0, count: 250).write(to: dir.appendingPathComponent("a.md"))

        let subdirectory = dir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 50).write(to: subdirectory.appendingPathComponent("b.png"))

        #expect(SaveDirectory.directorySize(at: dir.path) == 400)
    }

    @Test func directorySizeOfEmptyDirectoryIsZero() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(SaveDirectory.directorySize(at: dir.path) == 0)
    }

    @Test func displayPathReplacesHomeDirectoryWithTilde() {
        let path = NSHomeDirectory() + "/Documents/知鱼录音"
        #expect(SaveDirectory.displayPath(path) == "~/Documents/知鱼录音")
    }

    @MainActor
    @Test func defaultPathIsLanguageSpecific() {
        #expect(Preferences.defaultSaveDirectoryPath(for: .zhHans).hasSuffix("知鱼录音"))
        #expect(Preferences.defaultSaveDirectoryPath(for: .en).hasSuffix("Knowing You"))
    }
}
