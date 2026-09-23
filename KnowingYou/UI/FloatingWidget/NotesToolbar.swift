import SwiftUI

/// E7–E12 (02-ui-spec.md §10): pause/stop/level+timer/mark/screenshot, each
/// a 56×44 rounded-8 button positioned at an exact x-range within the
/// toolbar strip (y 320–365).
struct NotesToolbar: View {
    let isPaused: Bool
    let micLevel: Float
    let displayedElapsed: TimeInterval
    var onTogglePause: () -> Void
    var onStop: () -> Void
    var onMark: () -> Void
    var onScreenshot: () -> Void

    /// Relative to this view's own `.frame(height: 44)` — not the absolute
    /// window-space y=342.5 from 02-ui-spec.md §10's table (that coordinate
    /// only made sense back when this view's positioned elements shared the
    /// whole 418×380 window's coordinate space; see `NotesView`'s decision
    /// record for why that approach was abandoned).
    private static let toolbarCenterY: CGFloat = 22

    var body: some View {
        ZStack {
            OutlinedToolbarButton(systemImage: isPaused ? "play.fill" : "pause", action: onTogglePause)
                .position(x: 45, y: Self.toolbarCenterY)

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(KYColor.bgButtonFilledLight)
                    .frame(width: 56, height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(KYColor.textPrimary)
                            .frame(width: 14, height: 14)
                    }
            }
            .buttonStyle(.plain)
            .position(x: 110, y: Self.toolbarCenterY)

            HStack(spacing: 8) {
                LevelMeterView(level: micLevel, segmentWidth: 3, segmentSpacing: 2.5, minHeight: 3, maxHeight: 12)
                Text(Self.elapsedString(displayedElapsed))
                    .font(.system(size: 13))
                    .foregroundStyle(KYColor.textPrimary)
                    .monospacedDigit()
            }
            .position(x: 240, y: Self.toolbarCenterY)

            OutlinedToolbarButton(systemImage: "flag", action: onMark)
                .position(x: 306, y: Self.toolbarCenterY)

            OutlinedToolbarButton(systemImage: "crop", action: onScreenshot)
                .position(x: 372, y: Self.toolbarCenterY)
        }
        .frame(height: 44)
    }

    private static func elapsedString(_ interval: TimeInterval) -> String {
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

private struct OutlinedToolbarButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(KYColor.strokeButton, lineWidth: 1)
                .frame(width: 56, height: 44)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(KYColor.textPrimary)
                }
        }
        .buttonStyle(.plain)
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
    .frame(width: 418, height: 60)
    .background(KYColor.bgWindow)
}
