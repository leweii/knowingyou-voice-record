import SwiftUI

/// The collapsed floating widget (S22, prototype §02): a horizontal
/// "dynamic island" capsule — breathing dot · timer · live waveform · stop ·
/// expand. Replaces the 44×175 vertical strip (which itself replaced the
/// spec's 70×270 after Jakob found that too large, 2026-09-24); the capsule
/// keeps a similarly small footprint while giving the timer and waveform
/// room to read at a glance. The whole background drags the window
/// (`isMovableByWindowBackground` is on in the pill state).
struct PillView: View {
    static let size = CGSize(width: 264, height: 48)

    let level: Float
    let displayedElapsed: TimeInterval
    let isPaused: Bool
    var onExpand: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            BreathingDot(color: isPaused ? KYColor.warn : KYColor.rec, size: 9, isBreathing: !isPaused)
                .frame(width: 12)

            Text(Self.elapsedString(displayedElapsed))
                .font(KYFont.timer)
                .foregroundStyle(isPaused ? KYColor.text2 : KYColor.text)
                .contentTransition(.numericText())
                .fixedSize()

            WaveformView(
                level: level,
                barCount: 22,
                barWidth: 2.5,
                spacing: 2,
                color: KYColor.accent,
                isFrozen: isPaused,
                fadesTail: true
            )
            .frame(height: 24)
            .allowsHitTesting(false)

            PillCircleButton(help: "停止并保存", tint: KYColor.rec, hoverInk: .white, action: onStop) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .frame(width: 11, height: 11)
            }

            PillCircleButton(help: "展开笔记", tint: KYColor.accent, hoverInk: KYColor.accentInk, action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(width: Self.size.width, height: Self.size.height)
        .kyGlass(cornerRadius: Self.size.height / 2)
    }

    static func elapsedString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// 32pt round button: neutral at rest, fills with `tint` and glows on hover.
private struct PillCircleButton<Glyph: View>: View {
    let help: LocalizedStringKey
    let tint: Color
    let hoverInk: Color
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(isHovering ? hoverInk : tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isHovering ? tint : KYColor.surface3))
                .shadow(color: isHovering ? tint.opacity(0.5) : .clear, radius: 8)
                .scaleEffect(isHovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressSquashStyle())
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
        .help(Text(help))
    }
}

#Preview {
    VStack(spacing: 16) {
        PillView(level: 0.6, displayedElapsed: 754, isPaused: false)
        PillView(level: 0.6, displayedElapsed: 754, isPaused: true)
    }
    .padding(30)
}
