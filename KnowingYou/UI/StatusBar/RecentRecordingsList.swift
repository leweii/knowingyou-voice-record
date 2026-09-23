import AppKit
import SwiftUI

/// P7's expanded state (02-ui-spec.md §8): up to 5 rows, filename + duration,
/// hover reveals folder/play icons, empty state reads "还没有录音".
struct RecentRecordingsList: View {
    let recordings: [Recording]

    private var visible: [Recording] { Array(recordings.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty {
                Text("还没有录音")
                    .font(KYFont.popoverRecentRecordings)
                    .foregroundStyle(KYColor.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
        HStack(spacing: 8) {
            Text(recording.baseName)
                .font(KYFont.popoverRecentRecordings)
                .foregroundStyle(KYColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if isHovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.audioURL])
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(KYColor.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(recording.audioURL)
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundStyle(KYColor.textSecondary)
                }
                .buttonStyle(.plain)
            } else if let duration = recording.duration {
                Text(Self.durationString(duration))
                    .font(.system(size: 12))
                    .foregroundStyle(KYColor.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
        .frame(width: 280)
        .padding(.vertical)
}
