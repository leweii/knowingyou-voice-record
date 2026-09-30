import SwiftUI

/// A 5-bar live level meter, styled like a real audio waveform: each bar
/// shows a different recent level reading (a short rolling history), so the
/// bars vary independently as sound comes in — not a single shared VU-style
/// threshold ladder where every bar snaps between exactly two heights in
/// lockstep (the old design; see this file's decision record — Jakob found
/// on a real Mac, 2026-09-24, that all-bars-move-together doesn't read as a
/// waveform at all, "很不好的用户体验"). Parameterized so the notes-window
/// toolbar can reuse it at a smaller size.
struct LevelMeterView: View {
    /// 0...1, already smoothed (`LevelSmoother`) by the caller.
    let level: Float
    var segmentWidth: CGFloat = 4
    var segmentSpacing: CGFloat = 5
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 16
    /// nil → S22's height-graded color (accent → amber → red as a bar gets
    /// louder), so clipping-level peaks are visible at a glance.
    var color: Color? = nil

    nonisolated static let segmentCount = 5

    /// Continuous 0...1 → bar-height mapping (no thresholds/steps), pure and
    /// testable without instantiating a SwiftUI view. `nonisolated` because
    /// `LevelMeterView: View` otherwise pulls `static` members onto
    /// `@MainActor` by inference on this toolchain — a runtime-checked
    /// isolation crash (not a compile error, since it crosses `@testable
    /// import` module boundaries) when a non-`@MainActor` test calls it
    /// directly, which is exactly what `LevelMeterViewTests` wants to do
    /// without dragging SwiftUI into a unit test.
    nonisolated static func barHeight(for level: Float, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(max(level, 0), 1))
        return minHeight + clamped * (maxHeight - minHeight)
    }

    /// Which color band a bar's level falls into: 0 accent, 1 amber, 2 red.
    nonisolated static func band(for level: Float) -> Int {
        if level >= 0.85 { return 2 }
        if level >= 0.6 { return 1 }
        return 0
    }

    static func gradedColor(for level: Float) -> Color {
        switch band(for: level) {
        case 2: KYColor.rec
        case 1: KYColor.warn
        default: KYColor.accent
        }
    }

    /// Most recent reading is last (rightmost bar); shifted left as new
    /// readings arrive, like a tiny scrolling waveform history.
    @State private var history: [Float] = Array(repeating: 0, count: LevelMeterView.segmentCount)

    var body: some View {
        HStack(alignment: .center, spacing: segmentSpacing) {
            ForEach(history.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: segmentWidth / 2)
                    .fill(color ?? Self.gradedColor(for: history[index]))
                    .frame(width: segmentWidth, height: Self.barHeight(for: history[index], minHeight: minHeight, maxHeight: maxHeight))
            }
        }
        .frame(height: maxHeight)
        // No easing here on purpose (see this file's decision record,
        // 2026-09-24): a 0.12s ease-out on top of a 50ms update tick meant
        // each bar was still animating toward its *previous* target when the
        // next update arrived, which read as the meter lagging behind the
        // actual sound rather than tracking it live. Snapping immediately
        // makes the display match what RecordingSession just measured.
        .onChange(of: level) { _, newValue in
            history.removeFirst()
            history.append(newValue)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        LevelMeterView(level: 0)
        LevelMeterView(level: 0.4)
        LevelMeterView(level: 0.9)
    }
    .padding()
}
