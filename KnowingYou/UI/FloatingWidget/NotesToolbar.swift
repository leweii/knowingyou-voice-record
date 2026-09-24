import SwiftUI

/// E7–E12 (02-ui-spec.md §10): pause/stop/level+timer/mark/screenshot, each
/// a 56×44 rounded-8 button. Uses a flexible `HStack`+`Spacer` layout rather
/// than the original spec's window-absolute `.position()` x-ranges, since
/// the notes window is now user-resizable (2026-09-24, Jakob's real-Mac
/// feedback) — pause/stop stay grouped on the left, flag/crop stay grouped
/// on the right, and the level+timer group is centered in the space between
/// them by two equal `Spacer()`s, which keeps both gaps equal automatically
/// at any window width instead of needing a hand-picked center coordinate.
struct NotesToolbar: View {
    let isPaused: Bool
    let micLevel: Float
    let displayedElapsed: TimeInterval
    var onTogglePause: () -> Void
    var onStop: () -> Void
    var onMark: () -> Void
    var onScreenshot: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            OutlinedToolbarButton(systemImage: isPaused ? "play.fill" : "pause", action: onTogglePause)

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

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                LevelMeterView(level: micLevel, segmentWidth: 3, segmentSpacing: 2.5, minHeight: 3, maxHeight: 12)
                Text(Self.elapsedString(displayedElapsed))
                    .font(.system(size: 14))
                    .foregroundStyle(KYColor.textPrimary)
                    .monospacedDigit()
            }

            Spacer(minLength: 12)

            OutlinedToolbarButton(systemImage: "flag", action: onMark)
            OutlinedToolbarButton(systemImage: "crop", action: onScreenshot)
        }
        .padding(.horizontal, 16)
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
