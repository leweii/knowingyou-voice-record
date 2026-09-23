import SwiftUI

/// The 5-segment level meter from 02-ui-spec.md §9 W2: each segment is a
/// `segmentWidth`-wide rounded bar that sits at `minHeight` (a "dot") when
/// silent and rises to `maxHeight` once `level` crosses its own threshold.
/// Parameterized so S16's notes-window header can reuse it at a smaller size.
struct LevelMeterView: View {
    /// 0...1, already smoothed (`LevelSmoother`) by the caller — this view
    /// is a pure function of its input, no internal state/timers.
    let level: Float
    var segmentWidth: CGFloat = 4
    var segmentSpacing: CGFloat = 5
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 16
    var color: Color = KYColor.textPrimary

    /// Per-segment activation thresholds (02-ui-spec.md §9 W2): segment `i`
    /// rises to `maxHeight` once `level >= thresholds[i]`. `nonisolated`
    /// because `LevelMeterView: View` otherwise pulls this (and
    /// `litSegmentCount`) onto `@MainActor` by inference — a runtime-checked
    /// isolation crash (not a compile error, since it crosses `@testable
    /// import` module boundaries) when a non-`@MainActor` test calls it
    /// directly, which is exactly what `LevelMeterViewTests` wants to do
    /// without dragging SwiftUI into a unit test.
    nonisolated static let thresholds: [Float] = [0.1, 0.3, 0.5, 0.7, 0.85]

    /// Pure segment-count mapping, factored out of `body` so it's testable
    /// without instantiating a SwiftUI view.
    nonisolated static func litSegmentCount(for level: Float) -> Int {
        thresholds.filter { level >= $0 }.count
    }

    var body: some View {
        HStack(alignment: .center, spacing: segmentSpacing) {
            ForEach(Self.thresholds.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: segmentWidth / 2)
                    .fill(color)
                    .frame(width: segmentWidth, height: level >= Self.thresholds[index] ? maxHeight : minHeight)
            }
        }
        .frame(height: maxHeight)
        .animation(.linear(duration: 0.05), value: level)
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
