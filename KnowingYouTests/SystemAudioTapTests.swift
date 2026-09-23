import CoreAudio
import Foundation
import Testing
@testable import KnowingYou

/// Real end-to-end SystemAudioTap capture (create tap → aggregate device →
/// IOProc → AudioDeviceStart, then verify actual non-silent audio) was
/// verified manually and via the standalone S06 spike tool — see
/// docs/spikes/2026-09-23-process-tap-spike.md and S08's decision record.
///
/// That verification deliberately isn't repeated as an automated test here:
/// repeated Process Tap creation in a short window triggers what looks like
/// a macOS anti-abuse throttle (observed delays growing from instant to
/// 90-180s across repeated attempts in the same session). That makes a
/// "create a real tap every test run" unsuitable for `make test`, which
/// needs to stay fast and reliable for every other spec's workflow. Use the
/// Debug menu's "录 10 秒系统音频到桌面" for manual on-demand verification.
///
/// What's tested here instead: the read-only Core Audio queries `ProcessTap`
/// depends on, which don't create/destroy anything and so don't trip the
/// throttle.
struct SystemAudioTapTests {
    @Test func ownProcessObjectIDResolves() {
        #expect(CoreAudioUtils.ownProcessObjectID() != nil)
    }

    @Test func defaultOutputDeviceResolvesToAValidUID() {
        guard let deviceID = CoreAudioUtils.defaultOutputDeviceID() else {
            Issue.record("no default output device on this machine")
            return
        }
        let uid = CoreAudioUtils.deviceUID(deviceID)
        #expect(uid != nil)
        #expect(uid?.isEmpty == false)
    }

    @Test func invalidateWithoutActivateIsANoOp() {
        let tap = ProcessTap()
        tap.invalidate() // must not crash even though activate() was never called
        tap.invalidate() // and must be idempotent
        #expect(tap.tapID == AudioObjectID(kAudioObjectUnknown))
        #expect(tap.aggregateDeviceID == AudioObjectID(kAudioObjectUnknown))
    }
}
