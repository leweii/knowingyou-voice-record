import AVFoundation
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusBarController: StatusBarController?
    private var meetingCoordinator: MeetingCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Preferences.shared.showDockIcon ? .regular : .accessory)
        configureStatusItem()
        AppLog.app.info("KnowingYou launched")
        if !Preferences.shared.hasCompletedOnboarding {
            OnboardingWindow.show()
        }
        checkForRecoverableRecordings()
        Permissions.shared.systemAudioProbe = { await SystemAudioTap.probePermission() }
        configureMeetingDetection()
        FloatingWidgetPanel.shared.configure(
            onStop: { [weak appState] in
                Task { await appState?.stopRecording() }
            },
            onTogglePause: { [weak appState] in
                Task { await appState?.togglePause() }
            },
            onMark: { [weak appState] in
                appState?.addMark()
            },
            onScreenshot: { [weak appState] in
                appState?.captureScreenshotMark()
            },
            onRevealInFinder: { [weak appState] in
                guard let phase = appState?.phase, case .recording(let info) = phase else { return }
                NSWorkspace.shared.activateFileViewerSelecting([info.audioURL])
            },
            onOpenSettings: {
                SettingsWindowController.show()
            }
        )
    }

    private func configureMeetingDetection() {
        Notifier.shared.registerCategories()
        let detector = MeetingDetector(apps: { await MainActor.run { Preferences.shared.knownApps } })
        let coordinator = MeetingCoordinator(detector: detector, appState: appState)
        meetingCoordinator = coordinator
        Task { await coordinator.start() }
    }

    private func checkForRecoverableRecordings() {
        let candidates = RecordingStore.shared.recoveryCandidates
        guard !candidates.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "发现上次未完成的录音"
        alert.informativeText = "知鱼录音上次可能没有正常退出，是否把它恢复为可播放的录音文件？"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "稍后")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for url in candidates {
                Task {
                    do {
                        try await RecordingStore.shared.recover(url)
                    } catch {
                        AppLog.storage.error("recovery failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                    }
                }
            }
        case .alertSecondButtonReturn:
            for url in candidates {
                try? FileManager.default.removeItem(at: url)
            }
            RecordingStore.shared.refresh()
        default:
            break
        }
    }

    /// Builds the right-click/⌃-click context menu only — `StatusBarController`
    /// owns the actual `NSStatusItem` and routes left-click to the custom
    /// popover instead of this menu (see S11's decision record).
    private func configureStatusItem() {
        let menu = NSMenu()
        menu.addItem(withTitle: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        #if DEBUG
        menu.addItem(debugMenuItem())
        menu.addItem(.separator())
        #endif
        menu.addItem(withTitle: "退出知鱼录音", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }

        statusBarController = StatusBarController(appState: appState, contextMenu: menu)
    }

    #if DEBUG
    private func debugMenuItem() -> NSMenuItem {
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(withTitle: "控件画廊", action: #selector(showDesignSystemGallery), keyEquivalent: "")
        submenu.addItem(withTitle: "重新引导", action: #selector(restartOnboarding), keyEquivalent: "")
        submenu.addItem(withTitle: "录 5 秒麦克风到桌面", action: #selector(debugRecordMicToDesktop), keyEquivalent: "")
        submenu.addItem(withTitle: "录 10 秒系统音频到桌面", action: #selector(debugRecordSystemAudioToDesktop), keyEquivalent: "")
        submenu.addItem(withTitle: "完整录 30 秒（双源）到桌面", action: #selector(debugRecordFullSessionToDesktop), keyEquivalent: "")
        for menuItem in submenu.items {
            menuItem.target = self
        }
        debugItem.submenu = submenu
        return debugItem
    }

    @objc private func showDesignSystemGallery() {
        DesignSystemGalleryWindow.show()
    }

    @objc private func restartOnboarding() {
        Preferences.shared.hasCompletedOnboarding = false
        OnboardingWindow.show()
    }

    @objc private func debugRecordMicToDesktop() {
        Task {
            let capture = MicCapture(config: .init(selection: .smart))
            do {
                try capture.start()
                let format = capture.format
                let outputURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("knowingyou-mic-test.caf")
                let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                capture.onBuffer = { buffer, _ in
                    try? file.write(from: buffer)
                }
                AppLog.recording.info("debug mic recording started -> \(outputURL.path, privacy: .public)")
                try await Task.sleep(for: .seconds(5))
                capture.stop()
                AppLog.recording.info("debug mic recording finished")
            } catch {
                capture.stop()
                AppLog.recording.error("debug mic recording failed: \(error, privacy: .public)")
            }
        }
    }

    @objc private func debugRecordSystemAudioToDesktop() {
        Task {
            let tap = SystemAudioTap()
            let outputURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("knowingyou-system-audio-test.caf")
            let fileBox = DebugAudioFileBox()
            tap.onBuffer = { buffer, _ in
                try? fileBox.file?.write(from: buffer)
            }
            do {
                try tap.start()
                for await event in tap.events {
                    if case .started(let format) = event {
                        fileBox.file = try? AVAudioFile(
                            forWriting: outputURL,
                            settings: format.settings,
                            commonFormat: .pcmFormatFloat32,
                            interleaved: format.isInterleaved
                        )
                        AppLog.recording.info("debug system-audio recording started -> \(outputURL.path, privacy: .public)")
                    }
                    break
                }
                try await Task.sleep(for: .seconds(10))
                tap.stop()
                AppLog.recording.info("debug system-audio recording finished")
            } catch {
                tap.stop()
                AppLog.recording.error("debug system-audio recording failed: \(error, privacy: .public)")
            }
        }
    }
    /// End-to-end `RecordingSession` smoke test: mic + system audio, mixed,
    /// written to `.caf`, then transcoded to `.m4a` on stop, exactly as a
    /// real recording would be. Not run automatically in this environment —
    /// see S07/S08's decision records (mic TCC misattribution, Process Tap
    /// creation throttle) for why this can only be verified by hand, on a
    /// real Mac, by whoever has this build.
    @objc private func debugRecordFullSessionToDesktop() {
        Task {
            let directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let info = RecordingInfo(
                baseName: "knowingyou-full-session-test",
                directory: directory,
                startedAt: .now,
                sourceApp: "Debug"
            )
            let session = RecordingSession(config: .init(
                info: info,
                mic: .smart,
                captureSystemAudio: true,
                format: .monoMix
            ))
            let watcher = Task {
                for await event in session.events {
                    AppLog.recording.info("debug full-session event: \(String(describing: event), privacy: .public)")
                }
            }
            do {
                try await session.start()
                try await Task.sleep(for: .seconds(30))
                let finalURL = try await session.stop()
                AppLog.recording.info("debug full-session recording finished -> \(finalURL.path, privacy: .public)")
            } catch {
                AppLog.recording.error("debug full-session recording failed: \(error, privacy: .public)")
            }
            watcher.cancel()
        }
    }
    #endif

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

#if DEBUG
/// Lets the realtime `onBuffer` closure hold a mutable `AVAudioFile?`
/// without the compiler flagging a captured `var` across concurrency
/// boundaries — this is debug-only scaffolding, not app code.
private final class DebugAudioFileBox: @unchecked Sendable {
    var file: AVAudioFile?
}
#endif
