import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The 录音 (Recording) page: R1–R14 (from both the 02 and 03 reference
/// screenshots stitched together — this page scrolls).
struct RecordingSettingsView: View {
    @State private var showFloatingWidget = Preferences.shared.showFloatingWidget
    @State private var micSelection = Preferences.shared.micSelection
    @State private var captureSystemAudio = Preferences.shared.captureSystemAudio
    @State private var audioFormat = Preferences.shared.audioFormat
    @State private var autoRecord = Preferences.shared.autoRecord
    @State private var isMeetingAppsExpanded = true
    @State private var knownApps: [KnownApp] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                shortcutWidgetSection
                audioSettingsSection
                meetingDetectionSection
                recordingSection
                recordingNoticeSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .task {
            let stored = Preferences.shared.knownApps
            if stored.isEmpty {
                knownApps = Self.placeholderKnownApps
                Preferences.shared.knownApps = knownApps
            } else {
                knownApps = stored
            }
        }
        .onChange(of: knownApps) { _, newValue in
            Preferences.shared.knownApps = newValue
        }
    }

    // MARK: - R1–R2

    private var shortcutWidgetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("录音快捷组件")
            SettingsRow(title: "录音时显示快捷组件", subtitle: "在桌面快速查看录音状态并进行操作") {
                KYToggle(isOn: showFloatingWidgetBinding)
            }
        }
    }

    // MARK: - R3–R6, R14

    private var audioSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("音频设置")
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(title: "麦克风") {
                    BorderlessPopup(selection: micSelectionBinding, options: micOptions, leadingSystemImage: "sparkles")
                }
                if micSelection == .smart {
                    InfoBanner(text: "知鱼录音会自动选择合适的麦克风，确保录音清晰、不中断")
                        .padding(.vertical, 8)
                }
                SettingsRow(title: "系统音频") {
                    KYToggle(isOn: captureSystemAudioBinding)
                }
                SettingsRow(title: "音频格式") {
                    BorderlessPopup(
                        selection: audioFormatBinding,
                        options: [
                            .init(value: .monoMix, title: "单轨混音"),
                            .init(value: .dualTrack, title: "双轨（左麦克风 右系统）"),
                        ]
                    )
                }
            }
        }
    }

    private var micOptions: [BorderlessPopup<MicSelection>.Option] {
        var options: [BorderlessPopup<MicSelection>.Option] = [.init(value: .smart, title: "智能选择")]
        for device in AudioDeviceMonitor.shared.inputDevices {
            options.append(.init(value: .device(uid: device.uid), title: LocalizedStringKey(device.name)))
        }
        return options
    }

    // MARK: - R7–R9

    private var meetingDetectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("会议识别")
            DisclosureRow(title: "支持在以下应用中识别会议", isExpanded: $isMeetingAppsExpanded)
            if isMeetingAppsExpanded {
                VStack(spacing: 0) {
                    ForEach($knownApps) { $app in
                        MeetingAppRow(app: app, isEnabled: $app.isEnabled)
                    }
                    HStack {
                        Spacer()
                        OutlinedButton("添加应用…", action: addApp)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加"
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
            knownApps.append(KnownApp(bundleIDPrefix: bundleID, displayNameKey: name, kind: .native, isEnabled: true))
        }
    }

    // MARK: - R10–R11

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("录音")
            SettingsRow(title: "自动录制", subtitle: "在会议开始和结束时自动开启与停止录音") {
                KYToggle(isOn: autoRecordBinding)
            }
        }
    }

    // MARK: - R12–R13

    private var recordingNoticeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("录音须知")
            Text("录音前，请确保所有参会者均已获悉会议将被录音，且已根据各地适用法律的规定，获得了所需的同意。知鱼录音不会代你核实同意情况。")
                .font(.system(size: 13))
                .foregroundStyle(KYColor.textSecondary)
                .lineSpacing(5)
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

    /// Guessed bundle ID prefixes, matching docs/specs/S12's default table.
    /// S06's spike results will correct these; S12 formally owns this list.
    static let placeholderKnownApps: [KnownApp] = [
        KnownApp(bundleIDPrefix: "com.tencent.meeting", displayNameKey: "腾讯会议", kind: .native, isEnabled: true),
        KnownApp(bundleIDPrefix: "com.bytedance.lark", displayNameKey: "飞书", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.alibaba.DingTalkMac", displayNameKey: "钉钉", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.tencent.WeWorkMac", displayNameKey: "企业微信", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "us.zoom.xos", displayNameKey: "Zoom", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.microsoft.teams", displayNameKey: "Microsoft Teams", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.apple.FaceTime", displayNameKey: "FaceTime", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.tinyspeck.slackmacgap", displayNameKey: "Slack", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.hnc.Discord", displayNameKey: "Discord", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "Cisco-Systems.Spark", displayNameKey: "Webex", kind: .native, isEnabled: false),
        KnownApp(bundleIDPrefix: "com.tencent.xinWeChat", displayNameKey: "微信", kind: .native, isEnabled: false),
    ]
}

#Preview {
    RecordingSettingsView()
        .frame(width: 496, height: 520)
}
