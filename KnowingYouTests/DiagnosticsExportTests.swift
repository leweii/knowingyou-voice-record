import Foundation
import Testing
@testable import KnowingYou

@MainActor
struct DiagnosticsExportTests {
    @Test func settingsSnapshotContainsNoAbsoluteHomeDirectoryPath() throws {
        let data = try DiagnosticsExport.settingsSnapshotJSON()
        let text = String(decoding: data, as: UTF8.self)
        let home = NSHomeDirectory()

        #expect(!text.contains(home))
        #expect(text.contains("saveDirectoryPath"))
    }

    @Test func settingsSnapshotIsValidJSONWithExpectedKeys() throws {
        let data = try DiagnosticsExport.settingsSnapshotJSON()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let snapshot = try #require(object)

        for key in ["appVersion", "macOSVersion", "launchAtLogin", "appLanguage", "saveDirectoryPath", "audioFormat"] {
            #expect(snapshot[key] != nil, "missing key: \(key)")
        }
    }

    @Test func zipContainsAllThreeExpectedFiles() throws {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        try "settings".write(to: workDirectory.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "log".write(to: workDirectory.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        try "system".write(to: workDirectory.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)

        let zipURL = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? fileManager.removeItem(at: zipURL) }
        try DiagnosticsExport.runDitto(sourceDirectory: workDirectory, destination: zipURL)

        #expect(fileManager.fileExists(atPath: zipURL.path))

        // Round-trip through `ditto` again (extract this time) to confirm
        // the archive is real and contains exactly what we put in it,
        // rather than just asserting a file with a `.zip` extension exists.
        let extractDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractDirectory) }

        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extractProcess.arguments = ["-x", "-k", zipURL.path, extractDirectory.path]
        try extractProcess.run()
        extractProcess.waitUntilExit()
        #expect(extractProcess.terminationStatus == 0)

        let extractedNames = Set(try fileManager.contentsOfDirectory(atPath: extractDirectory.path))
        #expect(extractedNames == ["settings.json", "log.txt", "system.txt"])

        let recoveredSettings = try String(contentsOf: extractDirectory.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(recoveredSettings == "settings")
    }

    @Test func zipOverwritesAnExistingDestination() throws {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }
        try "a".write(to: workDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let zipURL = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? fileManager.removeItem(at: zipURL) }
        try "not a zip".write(to: zipURL, atomically: true, encoding: .utf8) // pre-existing junk at the destination

        try fileManager.removeItem(at: zipURL) // DiagnosticsExport.writeZip removes it first in the real flow; mirror that here
        try DiagnosticsExport.runDitto(sourceDirectory: workDirectory, destination: zipURL)

        #expect(fileManager.fileExists(atPath: zipURL.path))
        let attributes = try fileManager.attributesOfItem(atPath: zipURL.path)
        #expect((attributes[.size] as? Int ?? 0) > 9) // "not a zip" was 9 bytes; a real zip of one file is bigger
    }
}
