import AppKit
import SwiftUI

/// Up to 5 recent recordings: play button (lights up on hover), name,
/// duration, reveal-in-Finder on hover. Empty state reads "还没有录音".
struct RecentRecordingsList: View {
    let recordings: [Recording]

    private var visible: [Recording] { Array(recordings.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if visible.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(KYColor.text3)
                    Text("还没有录音")
                        .font(KYFont.caption)
                        .foregroundStyle(KYColor.text2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            } else {
                ForEach(visible) { recording in
                    RecordingRow(recording: recording)
                }
            }
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                NSWorkspace.shared.open(recording.audioURL)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isHovering ? KYColor.accentInk : KYColor.text2)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isHovering ? KYColor.accent : KYColor.surface3))
                    .shadow(color: isHovering ? KYColor.accentGlow : .clear, radius: 7)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(recording.baseName)
                    .font(KYFont.caption)
                    .foregroundStyle(KYColor.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let duration = recording.duration {
                    Text(Self.durationString(duration))
                        .font(KYFont.timestamp)
                        .foregroundStyle(KYColor.text2)
                }
            }

            Spacer(minLength: 8)

            if isHovering {
                KYIconButton(systemImage: "folder", size: 26, help: "在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.audioURL])
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHovering ? KYColor.surface2 : .clear))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
    }

    private static func durationString(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    RecentRecordingsList(recordings: [])
        .frame(width: 320)
        .padding(.vertical)
}
