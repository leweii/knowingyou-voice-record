import SwiftUI

/// The popover's primary start/stop control (M2, "录音键变形"): cyan with a
/// round glyph when idle, red with the glyph sprung into a rounded square
/// (the stop symbol) while recording. Starting fires three expanding pulse
/// rings; idle shows a slow light sweep across the face.
struct RecordButton: View {
    let isRecording: Bool
    let title: LocalizedStringKey
    let action: () -> Void

    @State private var pulseTrigger = 0
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: isRecording ? 3 : 7, style: .continuous)
                    .fill(isRecording ? Color.white : KYColor.accentInk)
                    .frame(width: isRecording ? 12 : 14, height: isRecording ? 12 : 14)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isRecording ? Color.white : KYColor.accentInk)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(face)
            .overlay(pulseRings)
            .scaleEffect(isHovering ? 1.01 : 1)
            .shadow(color: (isRecording ? KYColor.recGlow : KYColor.accentGlow).opacity(isHovering ? 0.9 : 0.6), radius: isHovering ? 16 : 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressSquashStyle())
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.state, value: isRecording)
        .kyAnimation(KYMotion.micro, value: isHovering)
        .onChange(of: isRecording) { _, recording in
            if recording && !reduceMotion { pulseTrigger += 1 }
        }
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(
                colors: isRecording ? [KYColor.rec, KYColor.recDeep] : [KYColor.accent, KYColor.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            if !isRecording && !reduceMotion {
                ShineSweep().clipShape(shape)
            }
        }
    }

    private var pulseRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(KYColor.rec, lineWidth: 2)
                    .keyframeAnimator(initialValue: PulseState(), trigger: pulseTrigger) { view, state in
                        view.scaleEffect(x: state.scaleX, y: state.scaleY).opacity(state.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: Double(index) * 0.18)
                            LinearKeyframe(0.9, duration: 0.02)
                            CubicKeyframe(0, duration: 0.7)
                        }
                        KeyframeTrack(\.scaleX) {
                            LinearKeyframe(1, duration: Double(index) * 0.18 + 0.02)
                            CubicKeyframe(1.12, duration: 0.7)
                        }
                        KeyframeTrack(\.scaleY) {
                            LinearKeyframe(1, duration: Double(index) * 0.18 + 0.02)
                            CubicKeyframe(1.6, duration: 0.7)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private struct PulseState {
        var opacity: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }
}

/// A diagonal highlight that sweeps across every few seconds.
private struct ShineSweep: View {
    var body: some View {
        GeometryReader { proxy in
            PhaseAnimator([false, true]) { phase in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * 0.5)
                .rotationEffect(.degrees(15))
                .offset(x: phase ? proxy.size.width * 1.2 : -proxy.size.width * 0.7)
            } animation: { phase in
                phase ? .easeInOut(duration: 1.4).delay(2.2) : .linear(duration: 0)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Press → squash to 97%, spring back on release.
struct PressSquashStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(KYMotion.micro, value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 20) {
        RecordButton(isRecording: false, title: "开始录音") {}
        RecordButton(isRecording: true, title: "停止录音  00:12:34") {}
    }
    .padding(24)
    .frame(width: 340)
}
