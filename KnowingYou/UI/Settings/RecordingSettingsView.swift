import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The 录音 (Recording) page: auto-record, floating widget, audio, meeting
/// detection, consent notice.
struct RecordingSettingsView: View {
    @State private var showFloatingWidget = Preferences.shared.showFloatingWidget
    @State private var micSelection = Preferences.shared.micSelection
    @State private var captureSystemAudio = Preferences.shared.captureSystemAudio
    @State private var audioFormat = Preferences.shared.audioFormat
    @State private var autoRecord = Preferences.shared.autoRecord
    @State private var isMeetingAppsExpanded = true
    @State private var knownApps: [KnownApp] = []

    var body: some View {
        SettingsPageScaffold(title: "录音", lead: "会议识别、自动录制与音频输出。") {
            recordingSection
            shortcutWidgetSection
            audioSettingsSection
            meetingDetectionSection
            recordingNoticeSection
        }
        .task {
            knownApps = KnownApps.merged(stored: Preferences.shared.knownApps)
            Preferences.shared.knownApps = knownApps
        }
        .onChange(of: knownApps) { _, newValue in
            Preferences.shared.knownApps = newValue
        }
    }

    // MARK: - Sections

    private var recordingSection: some View {
        SettingsSection("录音") {
            SettingsRow(title: "自动录制", subtitle: "在会议开始和结束时自动开启与停止录音", systemImage: "bolt") {
                KYToggle(isOn: autoRecordBinding)
            }
        }
    }

    private var shortcutWidgetSection: some View {
        SettingsSection("录音快捷组件") {
            SettingsRow(title: "录音时显示快捷组件", subtitle: "在桌面快速查看录音状态并进行操作", systemImage: "capsule") {
                KYToggle(isOn: showFloatingWidgetBinding)
            }
        }
    }

    private var audioSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection("音频设置") {
                SettingsRow(title: "麦克风", systemImage: "mic") {
                    KYPopup(
                        selection: micSelectionBinding,
                        options: micOptions,
                        leadingSystemImage: micSelection == .smart ? "sparkles" : nil,
                        minWidth: 170
                    )
                }
                SettingsRow(title: "系统音频", subtitle: "录制会议对方的声音", systemImage: "speaker.wave.2") {
                    KYToggle(isOn: captureSystemAudioBinding)
                }
                SettingsRow(title: "音频格式", systemImage: "waveform") {
                    KYSegmented(
                        selection: audioFormatBinding,
                        options: [
                            .init(value: .monoMix, title: String(localized: "单轨混音")),
                            .init(value: .dualTrack, title: String(localized: "双轨（左麦克风 右系统）")),
                        ]
                    )
                }
            }
            if micSelection == .smart {
                InfoBanner(text: "知鱼录音会自动选择合适的麦克风，确保录音清晰、不中断")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .kyAnimation(KYMotion.state, value: micSelection == .smart)
    }

    private var micOptions: [KYPopup<MicSelection>.Option] {
        var options: [KYPopup<MicSelection>.Option] = [.init(value: .smart, title: String(localized: "智能选择"))]
        for device in AudioDeviceMonitor.shared.inputDevices {
            options.append(.init(value: .device(uid: device.uid), title: device.name))
        }
        return options
    }

    private var meetingDetectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel("会议识别")
            VStack(alignment: .leading, spacing: 0) {
                DisclosureRow(
                    title: "支持在以下应用中识别会议",
                    isExpanded: $isMeetingAppsExpanded,
                    font: KYFont.body,
                    color: KYColor.text
                )
                .padding(.horizontal, 16)
                .frame(height: 48)
                if isMeetingAppsExpanded {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(knownApps) { app in
                            MeetingAppChip(app: app)
                        }
                        AddAppChip(action: addApp)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .kyCard()
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "添加")
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else {
                return
            }
            guard !knownApps.contains(where: { $0.bundleIDPrefix == bundleID }) else { return }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            knownApps.append(KnownApp(bundleIDPrefix: bundleID, displayNameKey: name, kind: .native))
        }
    }

    private var recordingNoticeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel("录音须知")
            InfoBanner(
                text: "录音前，请确保所有参会者均已获悉会议将被录音，且已根据各地适用法律的规定，获得了所需的同意。知鱼录音不会代你核实同意情况。",
                systemImage: "exclamationmark.triangle",
                tone: .notice
            )
        }
    }

    // MARK: - Bindings

    private var showFloatingWidgetBinding: Binding<Bool> {
        Binding(
            get: { showFloatingWidget },
            set: { newValue in
                showFloatingWidget = newValue
                Preferences.shared.showFloatingWidget = newValue
            }
        )
    }

    private var micSelectionBinding: Binding<MicSelection> {
        Binding(
            get: { micSelection },
            set: { newValue in
                micSelection = newValue
                Preferences.shared.micSelection = newValue
            }
        )
    }

    private var captureSystemAudioBinding: Binding<Bool> {
        Binding(
            get: { captureSystemAudio },
            set: { newValue in
                captureSystemAudio = newValue
                Preferences.shared.captureSystemAudio = newValue
            }
        )
    }

    private var audioFormatBinding: Binding<AudioFormat> {
        Binding(
            get: { audioFormat },
            set: { newValue in
                audioFormat = newValue
                Preferences.shared.audioFormat = newValue
            }
        )
    }

    private var autoRecordBinding: Binding<Bool> {
        Binding(
            get: { autoRecord },
            set: { newValue in
                autoRecord = newValue
                Preferences.shared.autoRecord = newValue
            }
        )
    }

}

#Preview {
    RecordingSettingsView()
        .frame(width: 540, height: 580)
}
