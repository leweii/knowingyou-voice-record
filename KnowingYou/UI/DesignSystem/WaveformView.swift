import SwiftUI

/// A wide rolling waveform: each new level reading enters on the right and
/// scrolls left, so the shape of recent speech is visible (same principle as
/// `LevelMeterView`, many more bars). Used in the popover's recording card
/// and the floating pill. When `isFrozen` (paused) the bars drain to a flat
/// gray line (M7); when idle (`isLive == false`) it shows a faint "listening"
/// ripple instead of real data.
struct WaveformView: View {
    let level: Float
    var barCount: Int = 44
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var color: Color = KYColor.accent
    var isLive: Bool = true
    var isFrozen: Bool = false
    /// Fade the oldest (leftmost) bars out, like the prototype.
    var fadesTail: Bool = true

    @State private var history: [Float] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            if isLive {
                bars(values: paddedHistory, height: height)
            } else {
                idleRipple(height: height)
            }
        }
        .onChange(of: level) { _, newValue in
            guard isLive, !isFrozen else { return }
            var next = history
            next.append(newValue)
            if next.count > barCount { next.removeFirst(next.count - barCount) }
            history = next
        }
        .onChange(of: isLive) { _, live in
            if !live { history = [] }
        }
    }

    private var paddedHistory: [Float] {
        Array(repeating: 0, count: max(0, barCount - history.count)) + history
    }

    private func bars(values: [Float], height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(values.indices, id: \.self) { index in
                let value = isFrozen ? 0 : CGFloat(min(max(values[index], 0), 1))
                Capsule()
                    .fill(isFrozen ? KYColor.text3 : color)
                    .frame(width: barWidth, height: max(2, value * height))
                    .opacity(fadesTail ? 0.3 + 0.7 * Double(index) / Double(max(1, values.count - 1)) : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: isFrozen ? .clear : color.opacity(0.5), radius: 4)
        .kyAnimation(.easeOut(duration: 0.4), value: isFrozen)
    }

    private func idleRipple(height: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let wave = (sin(t * 2.2 - Double(index) * 0.35) + 1) / 2
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: 2 + CGFloat(wave) * height * 0.12)
                        .opacity(0.25 + 0.35 * wave)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WaveformView(level: 0.6).frame(height: 56)
        WaveformView(level: 0, isLive: false).frame(height: 56)
        WaveformView(level: 0.6, isFrozen: true).frame(height: 56)
    }
    .padding()
    .frame(width: 320)
}
