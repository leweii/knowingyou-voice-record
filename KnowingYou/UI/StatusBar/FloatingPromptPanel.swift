import AppKit
import SwiftUI

/// A floating card just below the menu bar that stays until the user
/// explicitly dismisses it (no timeout) — used instead of system notification
/// banners, which auto-hide and are easy to miss, for the "会议检测到" and
/// "录音已保存" prompts. Like every borderless panel here it's built lazily on
/// first `show` (see CLAUDE.md's S15 note on `NSPanel` construction under
/// `xctest`). One card at a time: showing a new one replaces the current one.
@MainActor
final class FloatingPromptPanel {
    static let shared = FloatingPromptPanel()

    private static let width: CGFloat = 380
    private static let topMargin: CGFloat = 8

    private static let arrowHeight: CGFloat = 8
    private static let arrowWidth: CGFloat = 18
    private static let cornerRadius: CGFloat = 14

    private var panel: NSPanel?

    /// Screen-coordinates frame of the menu-bar status icon, installed by
    /// `StatusBarController`. The card hangs under it with a small arrow
    /// pointing at the icon; without a usable one (icon hidden by a menu-bar
    /// manager, or not resolvable) it sits at the main screen's top-right with
    /// no arrow.
    var anchorFrameProvider: () -> NSRect? = { nil }

    /// `content` is responsible for calling `hide()` (via the closure it's
    /// given) when the user is done with the card.
    func show<Content: View>(@ViewBuilder content: (_ dismiss: @escaping () -> Void) -> Content) {
        let ensured = ensurePanel()
        // A menu-bar manager (Ice, Bartender…) or an overflowing menu bar
        // parks a hidden status item's window far off every screen (e.g.
        // x = -3948). That frame can't be pointed at, so only trust it when
        // its center is actually on a screen; otherwise fall back to the
        // top-right corner of the main screen (where status icons live),
        // with no arrow.
        let anchorScreen = anchorFrameProvider().flatMap { rect in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }.map { (rect: rect, screen: $0) }
        }
        let anchor = anchorScreen?.rect
        let screen = anchorScreen?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame

        // Panel x is clamped to the screen, so the arrow's offset within the
        // card is computed from where the panel actually ends up, keeping it
        // pointed at the icon even when the card is pushed inward.
        var originX: CGFloat
        if let anchor {
            originX = anchor.midX - Self.width / 2
        } else {
            originX = (visible?.maxX ?? Self.width) - Self.width - 12
        }
        if let visible { originX = min(max(originX, visible.minX + 8), visible.maxX - Self.width - 8) }
        let arrowX: CGFloat? = anchor.map { $0.midX - originX }

        let card = PromptChrome(arrowX: arrowX, arrowHeight: Self.arrowHeight, arrowWidth: Self.arrowWidth, cornerRadius: Self.cornerRadius) {
            content { [weak self] in self?.hide() }
        }
        let hosting = RoundedHostingView(rootView: card, cornerRadius: 0)
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: 10)
        let size = NSSize(width: Self.width, height: hosting.fittingSize.height)
        hosting.frame = NSRect(origin: .zero, size: size)
        ensured.contentView = hosting
        ensured.setContentSize(size)

        let topY = anchor.map { $0.minY - 2 } ?? ((visible?.maxY ?? 0) - Self.topMargin)
        let finalOrigin = NSPoint(x: originX, y: topY - size.height)
        let wasVisible = ensured.isVisible
        if wasVisible || KYMotion.reduceMotion {
            ensured.setFrameOrigin(finalOrigin)
            ensured.alphaValue = 1
        } else {
            // Drop in from just above its resting spot (M4's card entrance).
            ensured.alphaValue = 0
            ensured.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 14))
        }
        ensured.orderFrontRegardless() // never makeKey: must not steal focus from the meeting app
        ensured.invalidateShadow()
        if !wasVisible && !KYMotion.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = KYMotion.windowMorphTiming
                ensured.animator().alphaValue = 1
                ensured.animator().setFrameOrigin(finalOrigin)
            }
        }
    }

    /// "检测到会议，要开始录音吗？" — `onAction` fires exactly once.
    func showMeetingDetected(appName: String, onAction: @escaping (NotificationAction) -> Void) {
        show { dismiss in
            MeetingPromptView(appName: appName) { action in
                dismiss()
                onAction(action)
            }
        }
    }

    /// "录音已保存" with copy-path / open-folder. Copying leaves the card up
    /// (it flips to "已拷贝" as feedback); opening the folder closes it.
    func showRecordingSaved(audioURL: URL) {
        show { dismiss in
            RecordingSavedPromptView(
                fileName: audioURL.lastPathComponent,
                onCopyPath: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(audioURL.path, forType: .string)
                },
                onOpenFolder: {
                    NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                    dismiss()
                },
                onClose: dismiss
            )
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

/// Glass card with an optional arrow on its top edge pointing up at `arrowX`
/// (in the card's own coordinates) — one continuous shape, so the blur,
/// tint and hairline border flow around the arrow without a seam.
private struct PromptChrome<Content: View>: View {
    let arrowX: CGFloat?
    let arrowHeight: CGFloat
    let arrowWidth: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let shape = PromptShape(
            arrowX: arrowX.map { min(max($0, cornerRadius + arrowWidth / 2), 380 - cornerRadius - arrowWidth / 2) },
            arrowHeight: arrowX == nil ? 0 : arrowHeight,
            arrowWidth: arrowWidth,
            cornerRadius: cornerRadius
        )
        content
            .padding(.top, arrowX == nil ? 0 : arrowHeight)
            .background {
                ZStack {
                    VisualEffectBackground()
                    KYColor.glassTint
                }
                .clipShape(shape)
            }
            .overlay(shape.stroke(KYColor.strokeStrong, lineWidth: 1))
            .clipShape(shape)
    }
}

private struct PromptShape: Shape {
    let arrowX: CGFloat?
    let arrowHeight: CGFloat
    let arrowWidth: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + arrowHeight, width: rect.width, height: rect.height - arrowHeight)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        if let arrowX {
            var arrow = Path()
            arrow.move(to: CGPoint(x: arrowX - arrowWidth / 2, y: body.minY + 0.5))
            arrow.addLine(to: CGPoint(x: arrowX, y: rect.minY))
            arrow.addLine(to: CGPoint(x: arrowX + arrowWidth / 2, y: body.minY + 0.5))
            arrow.closeSubpath()
            path = path.union(arrow)
        }
        return path
    }
}

/// Close ✕ in the card's top-right corner.
private struct PromptCloseButton: View {
    let action: () -> Void

    var body: some View {
        KYIconButton(systemImage: "xmark", size: 22, help: "忽略", action: action)
    }
}

/// "检测到 X 开始使用麦克风 / 要开始录音吗？" (M4): the app's initial on an
/// accent squircle, emitting sonar rings.
struct MeetingPromptView: View {
    let appName: String
    let onAction: (NotificationAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SonarBadge(text: String(appName.prefix(1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: String(format: String(localized: "检测到%@开始使用麦克风"), appName))
                    .font(KYFont.headline)
                    .foregroundStyle(KYColor.text)
                    .fixedSize(horizontal: false, vertical: true) // wrap fully; the card grows to fit
                Text("要开始录音吗？")
                    .font(KYFont.caption)
                    .foregroundStyle(KYColor.text2)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                KYButton("开始录音", style: .primary, systemImage: "record.circle", fillsWidth: true) {
                    onAction(.startRecording)
                }
                KYButton("忽略", style: .ghost, fillsWidth: true) {
                    onAction(.ignore)
                }
            }
            // Sized by the longest label (English "Start Recording" is much
            // wider than "开始录音"), never truncated.
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// Initial-letter badge with three sonar rings pulsing outward, repeating.
private struct SonarBadge: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<3, id: \.self) { index in
                    PhaseAnimator([false, true]) { phase in
                        Circle()
                            .strokeBorder(KYColor.accent, lineWidth: 1.5)
                            .frame(width: 40, height: 40)
                            .scaleEffect(phase ? 1.9 : 1)
                            .opacity(phase ? 0 : 0.8)
                    } animation: { phase in
                        phase ? .easeOut(duration: 1.8).delay(Double(index) * 0.35) : .linear(duration: 0)
                    }
                }
            }
            Text(verbatim: text)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(KYColor.accentInk)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LinearGradient(colors: [KYColor.accent, KYColor.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: KYColor.accentGlow, radius: 8)
        }
        .frame(width: 56, height: 56)
    }
}

/// "录音已保存" (M5): the waveform squeezes into an .m4a and an .md that drop
/// into a folder, which bounces and gets a check mark.
struct RecordingSavedPromptView: View {
    let fileName: String
    let onCopyPath: () -> Void
    let onOpenFolder: () -> Void
    let onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                SaveAnimationView()
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("录音已保存")
                        .font(KYFont.headline)
                        .foregroundStyle(KYColor.text)
                    Text(verbatim: fileName)
                        .font(KYFont.caption)
                        .foregroundStyle(KYColor.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                PromptCloseButton(action: onClose)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                KYButton(copied ? "已拷贝" : "拷贝路径", systemImage: copied ? "checkmark" : "doc.on.doc", fillsWidth: true) {
                    onCopyPath()
                    copied = true
                }
                KYButton("打开文件夹", style: .primary, systemImage: "folder", fillsWidth: true) {
                    onOpenFolder()
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// The M5 narrative, played once on appear, all in one centered spot so the
/// resting frame is just the folder + check (also what reduce-motion shows):
/// waveform squeezes to a sliver (0–0.6s) → an .m4a and an .md pop out
/// (0.6s) → they drop into a folder that springs up in their place
/// (1.0–1.4s) → check mark (1.5s).
private struct SaveAnimationView: View {
    @State private var trigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bars: [CGFloat] = [0.35, 0.7, 0.5, 0.9, 0.6, 0.3, 0.75, 0.45]

    private struct Wave { var scaleX: CGFloat = 1; var opacity: Double = 1 }
    private struct Files { var scale: CGFloat = 0; var y: CGFloat = 0; var opacity: Double = 0 }

    var body: some View {
        let still = reduceMotion
        ZStack {
            HStack(spacing: 3) {
                ForEach(Self.bars.indices, id: \.self) { index in
                    Capsule().fill(KYColor.rec).frame(width: 3.5, height: 34 * Self.bars[index])
                }
            }
            .keyframeAnimator(initialValue: Wave(scaleX: 1, opacity: still ? 0 : 1), trigger: trigger) { view, wave in
                view.scaleEffect(x: wave.scaleX, anchor: .center).opacity(wave.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scaleX) {
                    LinearKeyframe(1, duration: 0.35)
                    CubicKeyframe(0.08, duration: 0.25)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.58)
                    LinearKeyframe(0, duration: 0.04)
                }
            }

            ZStack(alignment: .topTrailing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(KYColor.accent)
                    .shadow(color: KYColor.accentGlow, radius: 8)
                    .keyframeAnimator(initialValue: CGFloat(still ? 1 : 0), trigger: trigger) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0, duration: 0.95)
                            SpringKeyframe(1.18, duration: 0.2)
                            SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                        }
                    }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KYColor.accentInk, KYColor.accent)
                    .background(Circle().fill(KYColor.accentInk).padding(2))
                    .offset(x: 7, y: -7)
                    .keyframeAnimator(initialValue: CGFloat(still ? 1 : 0), trigger: trigger) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0, duration: 1.5)
                            SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                        }
                    }
            }

            ZStack {
                FileChip(ext: "m4a", color: KYColor.accent).offset(x: -8, y: -2).rotationEffect(.degrees(-8))
                FileChip(ext: "md", color: KYColor.text2).offset(x: 8, y: 2).rotationEffect(.degrees(8))
            }
            .keyframeAnimator(initialValue: Files(), trigger: trigger) { view, files in
                view
                    .scaleEffect(files.scale)
                    .offset(y: files.y)
                    .opacity(files.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0, duration: 0.58)
                    SpringKeyframe(1, duration: 0.25, spring: .bouncy)
                    LinearKeyframe(1, duration: 0.2)
                    CubicKeyframe(0.35, duration: 0.3)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: 0.95)
                    CubicKeyframe(-10, duration: 0.12)
                    CubicKeyframe(6, duration: 0.18)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.58)
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.56)
                    LinearKeyframe(0, duration: 0.1)
                }
            }
        }
        .onAppear { if !reduceMotion { trigger += 1 } }
    }
}

private struct FileChip: View {
    let ext: String
    let color: Color

    var body: some View {
        Text(verbatim: ".\(ext)")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 26, height: 32)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(KYColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(KYColor.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}
