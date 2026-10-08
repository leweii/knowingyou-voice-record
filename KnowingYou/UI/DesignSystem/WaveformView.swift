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

    /// How often a new bar is taken from `level` — matches
    /// `RecordingSession`'s ~20 Hz level events.
    nonisolated static let samplePeriod: TimeInterval = 0.05

    @State private var history = WaveformHistory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            if isLive {
                // Redrawn every display frame and scrolled by a fraction of a
                // bar between samples, instead of jumping one whole bar left
                // per level update — which at ~20 Hz read as a choppy,
                // "refreshing" meter (Jakob, 2026-10-08: "波形图的帧数太低了").
                TimelineView(.animation(paused: isFrozen)) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let phase = isFrozen ? 0 : history.advance(to: now, level: level, capacity: barCount, period: Self.samplePeriod)
                    bars(values: history.padded(to: barCount) + [level], phase: reduceMotion ? 0 : phase, height: height)
                }
            } else {
                idleRipple(height: height)
            }
        }
        .onChange(of: isFrozen) { _, frozen in
            // Don't backfill the paused stretch with bars on resume.
            if !frozen { history.restartClock() }
        }
        .onChange(of: isLive) { _, live in
            if !live { history.reset() }
        }
    }

    /// `values` holds `barCount + 1` bars (the last is the live edge, still
    /// sliding in); `phase` (0..<1) is how far the row has scrolled toward
    /// the next sample, so it moves continuously rather than in steps.
    private func bars(values: [Float], phase: Double, height: CGFloat) -> some View {
        let step = barWidth + spacing
        let lastIndex = Double(max(1, values.count - 2))
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(values.indices, id: \.self) { index in
                let value = isFrozen ? 0 : CGFloat(min(max(values[index], 0), 1))
                let position = min(max((Double(index) - phase) / lastIndex, 0), 1)
                Capsule()
                    .fill(isFrozen ? KYColor.text3 : color)
                    .frame(width: barWidth, height: max(2, value * height))
                    .opacity(fadesTail ? 0.3 + 0.7 * position : 1)
            }
        }
        .offset(x: step * (1 - phase))
        // A window exactly `barCount` bars wide: the live edge enters from
        // the right, the oldest bar slides out on the left.
        .frame(width: CGFloat(barCount) * step - spacing, alignment: .trailing)
        .clipped()
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

/// Fixed-rate bar history for `WaveformView`, sampled from the timeline's
/// clock rather than on each level change, so bars stay evenly spaced in
/// time even when level updates arrive unevenly. A plain reference type held
/// in `@State` (not observed): mutating it while drawing doesn't trigger
/// another render, the `TimelineView` already redraws every frame.
final class WaveformHistory {
    private(set) var values: [Float] = []
    private var lastSampleTime: TimeInterval?

    /// Appends one bar per whole `period` elapsed since the last sample and
    /// returns how far (0..<1) into the next period `now` is.
    func advance(to now: TimeInterval, level: Float, capacity: Int, period: TimeInterval) -> Double {
        guard let last = lastSampleTime else {
            lastSampleTime = now
            return 0
        }
        let steps = Int((now - last) / period)
        if steps > 0 {
            values.append(contentsOf: repeatElement(level, count: min(steps, capacity)))
            if values.count > capacity { values.removeFirst(values.count - capacity) }
            lastSampleTime = last + Double(steps) * period
        }
        return min(max((now - (lastSampleTime ?? now)) / period, 0), 0.999)
    }

    func padded(to capacity: Int) -> [Float] {
        Array(repeating: 0, count: max(0, capacity - values.count)) + values
    }

    func restartClock() {
        lastSampleTime = nil
    }

    func reset() {
        values = []
        lastSampleTime = nil
    }
}
