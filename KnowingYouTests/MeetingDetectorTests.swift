import Foundation
import Testing
@testable import KnowingYou

/// Stands in for `CoreAudioProcessObjectReader` so these tests never touch
/// real Core Audio — `activeInputProcesses()` just returns whatever the test
/// last `set()`.
private final class FakeProcessObjectReader: ProcessObjectReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [(pid: pid_t, bundleID: String)] = []

    func set(_ results: [(pid: pid_t, bundleID: String)]) {
        lock.lock()
        defer { lock.unlock() }
        self.results = results
    }

    func activeInputProcesses() -> [(pid: pid_t, bundleID: String)] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

struct MeetingDetectorTests {
    @Test func snapshotReflectsCurrentActiveProcesses() async {
        let reader = FakeProcessObjectReader()
        let detector = MeetingDetector(apps: { KnownApps.defaults }, reader: reader)

        #expect(await detector.snapshot().isEmpty)

        reader.set([(pid: 100, bundleID: "us.zoom.xos")])
        let afterZoom = await detector.snapshot()
        #expect(afterZoom.map(\.app.displayNameKey) == ["Zoom"])

        reader.set([(pid: 100, bundleID: "us.zoom.xos"), (pid: 200, bundleID: "com.google.Chrome")])
        let afterChrome = await detector.snapshot()
        #expect(Set(afterChrome.map(\.app.displayNameKey)) == ["Zoom", "Chrome"])

        reader.set([])
        let afterEnd = await detector.snapshot()
        #expect(afterEnd.isEmpty)
    }

    @Test func updatesStreamEmitsOnlyOnChange() async {
        let reader = FakeProcessObjectReader()
        let detector = MeetingDetector(apps: { KnownApps.defaults }, reader: reader)

        // Runs the state changes on a separate Task so the test body itself
        // can iterate `detector.updates` directly below — appending to a
        // local `var` from inside a second, independently-scheduled Task
        // closure would be exactly the kind of unsynchronized-capture the
        // Swift 6 compiler (rightly) rejects.
        let driver = Task {
            _ = await detector.snapshot() // [] -> [], already empty: no emission
            reader.set([(pid: 1, bundleID: "us.zoom.xos")])
            _ = await detector.snapshot() // -> [Zoom]: emits
            _ = await detector.snapshot() // repeat: no emission
            reader.set([(pid: 1, bundleID: "us.zoom.xos"), (pid: 2, bundleID: "com.google.Chrome")])
            _ = await detector.snapshot() // -> [Zoom, Chrome]: emits
            reader.set([])
            _ = await detector.snapshot() // -> []: emits
        }

        var received: [[MeetingDetector.ActiveMicUser]] = []
        for await update in detector.updates {
            received.append(update)
            if received.count == 3 { break }
        }

        await driver.value
        #expect(received.count == 3)
        #expect(received[0].map(\.app.displayNameKey) == ["Zoom"])
        #expect(Set(received[1].map(\.app.displayNameKey)) == ["Zoom", "Chrome"])
        #expect(received[2].isEmpty)
    }

    @Test func multiplePIDsForSameAppAreGroupedTogether() async {
        let reader = FakeProcessObjectReader()
        let detector = MeetingDetector(apps: { KnownApps.defaults }, reader: reader)
        reader.set([
            (pid: 1, bundleID: "com.bytedance.lark"),
            (pid: 2, bundleID: "com.bytedance.lark.helper"),
        ])
        let snapshot = await detector.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.pids.sorted() == [1, 2])
    }

    @Test func unmatchedBundleIDsAreIgnored() async {
        let reader = FakeProcessObjectReader()
        let detector = MeetingDetector(apps: { KnownApps.defaults }, reader: reader)
        reader.set([(pid: 1, bundleID: "com.example.RandomApp")])
        let snapshot = await detector.snapshot()
        #expect(snapshot.isEmpty)
    }
}
