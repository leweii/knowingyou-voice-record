#if DEBUG
import AppKit
import SwiftUI

/// Every control in one window, states side by side, for measuring against
/// 02-ui-spec.md §1.3 with Xcode's view debugger. Debug-only, never shipped.
struct DesignSystemGallery: View {
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var popupSelection = "smart"
    @State private var isExpanded = true
    @State private var sidebarSelection = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                group("KYToggle") {
                    HStack(spacing: 24) {
                        KYToggle(isOn: $toggleOn)
                        KYToggle(isOn: $toggleOff)
                    }
                }

                group("OutlinedButton") {
                    HStack(spacing: 12) {
                        OutlinedButton("查看帮助") {}
                        OutlinedButton("恢复默认", height: 30) {}
                        OutlinedButton("已停用", isEnabled: false) {}
                    }
                }

                group("PrimaryButton") {
                    VStack(alignment: .leading, spacing: 12) {
                        PrimaryButton(title: "开始录音") {}
                        PrimaryButton(title: "停止录音  00:12:34", style: .recording, leadingSystemImage: "stop.fill") {}
                    }
                    .frame(width: 248)
                }

                group("SectionHeader") {
                    SectionHeader("系统")
                        .frame(width: 480)
                }

                group("SettingsRow") {
                    VStack(spacing: 0) {
                        SettingsRow(title: "开机时自动启动知鱼录音") {
                            KYToggle(isOn: $toggleOn)
                        }
                        SettingsRow(title: "录音时显示快捷组件", subtitle: "在桌面快速查看录音状态并进行操作") {
                            KYToggle(isOn: $toggleOn)
                        }
                    }
                    .frame(width: 480)
                }

                group("BorderlessPopup") {
                    BorderlessPopup(
                        selection: $popupSelection,
                        options: [
                            .init(value: "smart", title: "智能选择"),
                            .init(value: "built-in", title: "内置麦克风"),
                        ]
                    )
                }

                group("DisclosureRow") {
                    DisclosureRow(title: "支持在以下应用中识别会议", isExpanded: $isExpanded)
                        .frame(width: 480)
                }

                group("InfoBanner") {
                    InfoBanner(text: "知鱼录音会自动选择合适的麦克风，确保录音清晰、不中断")
                        .frame(width: 480)
                }

                group("SidebarItem") {
                    VStack(spacing: 4) {
                        SidebarItem(title: "通用", systemImage: "gearshape", isSelected: sidebarSelection == 0) {
                            sidebarSelection = 0
                        }
                        SidebarItem(title: "录音", systemImage: "waveform", isSelected: sidebarSelection == 1) {
                            sidebarSelection = 1
                        }
                    }
                    .padding(8)
                    .background(KYColor.bgSidebar)
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
        .background(KYColor.bgWindow)
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
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
