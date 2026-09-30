#if DEBUG
import AppKit
import SwiftUI

/// Every control in one window, states side by side — a live copy of the
/// prototype's §07 design-system page. Debug-only, never shipped.
struct DesignSystemGallery: View {
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var popupSelection = "smart"
    @State private var segmentSelection = "mono"
    @State private var isExpanded = true
    @State private var sidebarSelection = 0
    @State private var isRecording = false
    @State private var level: Float = 0.5
    @State private var markPulse = 0
    @State private var screenshotPulse = 0
    @Namespace private var sidebarIndicator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                group("Brand · M1") {
                    HStack(spacing: 20) {
                        KYMark(size: 28)
                        KYMark(size: 72, animated: true).id(markPulse)
                        KYButton("重播", style: .ghost, size: .small) { markPulse += 1 }
                    }
                }

                group("KYToggle") {
                    HStack(spacing: 24) {
                        KYToggle(isOn: $toggleOn)
                        KYToggle(isOn: $toggleOff)
                        KYToggle(isOn: .constant(true), isEnabled: false)
                    }
                }

                group("KYButton") {
                    HStack(spacing: 10) {
                        KYButton("开始使用", style: .primary) {}
                        KYButton("查看帮助", systemImage: "questionmark.circle") {}
                        KYButton("检查更新", style: .ghost) {}
                        KYButton("停止", style: .danger) {}
                        KYButton("已停用", isEnabled: false) {}
                    }
                }

                group("RecordButton · M2") {
                    VStack(spacing: 10) {
                        RecordButton(isRecording: isRecording, title: isRecording ? "停止录音  00:12:34" : "开始录音") {
                            isRecording.toggle()
                        }
                        .frame(width: 316)
                    }
                }

                group("KYPopup / KYSegmented") {
                    HStack(spacing: 16) {
                        KYPopup(
                            selection: $popupSelection,
                            options: [
                                .init(value: "smart", title: "智能选择"),
                                .init(value: "built-in", title: "内置麦克风"),
                            ],
                            leadingSystemImage: "sparkles"
                        )
                        KYSegmented(
                            selection: $segmentSelection,
                            options: [.init(value: "mono", title: "单轨混音"), .init(value: "dual", title: "双轨")]
                        )
                    }
                }

                group("SettingsSection / SettingsRow") {
                    SettingsSection("系统") {
                        SettingsRow(title: "开机时自动启动知鱼录音", systemImage: "power") {
                            KYToggle(isOn: $toggleOn)
                        }
                        SettingsRow(title: "录音时显示快捷组件", subtitle: "在桌面快速查看录音状态并进行操作", systemImage: "capsule") {
                            KYButton("更改…") {}
                        }
                    }
                }

                group("DisclosureRow / InfoBanner") {
                    DisclosureRow(title: "最近录音", isExpanded: $isExpanded)
                    InfoBanner(text: "知鱼录音会自动选择合适的麦克风，确保录音清晰、不中断")
                    InfoBanner(text: "录音前，请确保所有参会者均已获悉会议将被录音。", systemImage: "exclamationmark.triangle", tone: .notice)
                }

                group("SidebarItem") {
                    VStack(spacing: 2) {
                        SidebarItem(title: "通用", systemImage: "gearshape", isSelected: sidebarSelection == 0, indicatorNamespace: sidebarIndicator) {
                            withAnimation(KYMotion.state) { sidebarSelection = 0 }
                        }
                        SidebarItem(title: "录音", systemImage: "waveform", isSelected: sidebarSelection == 1, indicatorNamespace: sidebarIndicator) {
                            withAnimation(KYMotion.state) { sidebarSelection = 1 }
                        }
                    }
                    .padding(10)
                    .frame(width: 220)
                    .background(KYColor.bg)
                }

                group("LevelMeter / Waveform / BreathingDot") {
                    VStack(alignment: .leading, spacing: 12) {
                        Slider(value: $level, in: 0...1)
                            .frame(width: 240)
                        HStack(spacing: 20) {
                            LevelMeterView(level: level)
                            BreathingDot()
                            BreathingDot(color: KYColor.warn, isBreathing: false)
                            PingDot()
                        }
                        WaveformView(level: level).frame(width: 300, height: 48)
                    }
                }

                group("Floating widget · M3 / M6") {
                    VStack(alignment: .leading, spacing: 12) {
                        PillView(level: level, displayedElapsed: 754, isPaused: false)
                            .overlay(WidgetFeedbackOverlay(markPulse: markPulse, screenshotPulse: screenshotPulse, markOrigin: UnitPoint(x: 0.08, y: 0.5), cornerRadius: 24))
                        PillView(level: level, displayedElapsed: 754, isPaused: true)
                        HStack {
                            KYButton("标记冲击波", size: .small) { markPulse += 1 }
                            KYButton("截屏快门", size: .small) { screenshotPulse += 1 }
                        }
                    }
                }

                group("AppIconView") {
                    HStack(spacing: 12) {
                        AppIconView(bundleIdentifier: "com.apple.FaceTime")
                        AppIconView(bundleIdentifier: "com.example.not-installed")
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 640)
        .background(KYColor.surface)
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(KYFont.overline)
                .tracking(0.8)
                .foregroundStyle(KYColor.text3)
            content()
        }
    }
}

@MainActor
enum DesignSystemGalleryWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: DesignSystemGallery())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "DesignSystem Gallery"
        newWindow.setContentSize(NSSize(width: 600, height: 1000))
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.setFrameTopLeftPoint(NSPoint(x: 20, y: NSScreen.main?.frame.height ?? 1080))
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }
}

#Preview {
    DesignSystemGallery()
}
#endif
