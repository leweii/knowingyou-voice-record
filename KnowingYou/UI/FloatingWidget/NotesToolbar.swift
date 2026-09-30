import SwiftUI

/// Notes-window toolbar: pause/stop on the left, live dot + timer + meter in
/// the middle, mark/screenshot on the right. Flexible `HStack`+`Spacer`
/// layout since the notes window is user-resizable (2026-09-24, Jakob's
/// real-Mac feedback) — the middle group stays centered between the two
/// button groups at any width.
struct NotesToolbar: View {
    let isPaused: Bool
    let micLevel: Float
    let displayedElapsed: TimeInterval
    var onTogglePause: () -> Void
    var onStop: () -> Void
    var onMark: () -> Void
    var onScreenshot: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ToolbarButton(systemImage: isPaused ? "play.fill" : "pause.fill", help: isPaused ? "继续" : "暂停", action: onTogglePause)
            ToolbarButton(systemImage: "stop.fill", help: "停止并保存", tint: KYColor.rec, action: onStop)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                BreathingDot(color: isPaused ? KYColor.warn : KYColor.rec, size: 7, isBreathing: !isPaused)
                Text(PillView.elapsedString(displayedElapsed))
                    .font(KYFont.timer)
                    .foregroundStyle(isPaused ? KYColor.text2 : KYColor.text)
                    .contentTransition(.numericText())
                LevelMeterView(
                    level: isPaused ? 0 : micLevel,
                    segmentWidth: 3,
                    segmentSpacing: 2,
                    minHeight: 3,
                    maxHeight: 12,
                    color: isPaused ? KYColor.text3 : nil
                )
            }
            .allowsHitTesting(false) // purely informational — let a drag started here move the window

            Spacer(minLength: 8)

            ToolbarButton(systemImage: "flag", help: "标记 ⌥⌘M", action: onMark)
            ToolbarButton(systemImage: "camera.viewfinder", help: "截屏标记 ⌥⌘S", action: onScreenshot)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(KYColor.surface.opacity(0.35))
        .overlay(alignment: .top) { Rectangle().fill(KYColor.stroke).frame(height: 1) }
    }
}

/// 38×38 rounded square; lifts on hover. `tint` (if set) fills it on hover —
/// used for the red stop button.
private struct ToolbarButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    var tint: Color?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint != nil && isHovering ? .clear : KYColor.stroke, lineWidth: 1))
                .shadow(color: tint != nil && isHovering ? KYColor.recGlow : .clear, radius: 9)
                .offset(y: isHovering ? -2 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressSquashStyle())
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
        .help(Text(help))
    }

    private var foreground: Color {
        if let tint { return isHovering ? .white : tint }
        return KYColor.text
    }

    private var background: Color {
        if let tint, isHovering { return tint }
        return isHovering ? KYColor.surface3 : KYColor.surface2
    }
}

#Preview {
    NotesToolbar(
        isPaused: false,
        micLevel: 0.5,
        displayedElapsed: 25,
        onTogglePause: {},
        onStop: {},
        onMark: {},
        onScreenshot: {}
    )
    .frame(width: 440)
}
