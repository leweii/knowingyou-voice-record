import AppKit
import SwiftUI

/// The 280×188(+) borderless popover content, P1–P10 per 02-ui-spec.md §8.
struct PopoverView: View {
    static let width: CGFloat = 280
    /// A computed property, not a `static let` — `MarqueeText.text` and
    /// `NSPasteboard.setString` both take plain `String`, which (unlike
    /// `Text`/`LocalizedStringKey`) never auto-localizes a literal passed
    /// through a stored value. `String(localized:)` needs the literal
    /// visible at *this* call site to extract the right catalog key, so
    /// this has to be resolved fresh each time it's read, not cached as a
    /// stored constant (found via S20's screenshot QA — see its decision
    /// record; S19 populated a catalog entry for this string that this
    /// property is what actually makes take effect).
    static var disclaimer: String {
        String(localized: "开始录音即代表你确认所有参会者均已获悉本次会议将被录音")
    }

    let appState: AppState
    var store: RecordingStore = .shared
    var onOpenSaveDirectory: () -> Void
    var onOpenSettings: () -> Void

    @State private var isExpanded = Preferences.shared.recentRecordingsExpanded
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(KYColor.strokeHairline)
            primaryButtonArea
            Divider().foregroundStyle(KYColor.strokeHairline)
            DisclosureRow(title: "最近录音", isExpanded: $isExpanded)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onChange(of: isExpanded) { _, newValue in
                    Preferences.shared.recentRecordingsExpanded = newValue
                }
            if isExpanded {
                RecentRecordingsList(recordings: store.recordings)
                    .padding(.bottom, 8)
            }
            footer
        }
        .frame(width: Self.width)
        .background(KYColor.bgWindow)
    }

    // MARK: P1-P4 header

    private var header: some View {
        HStack {
            KYBrand.logo(size: 16)
            Spacer()
            Button(action: onOpenSaveDirectory) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textPrimary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 49)
    }

    // MARK: P5 primary button + current filename

    private var primaryButtonArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.isRecording, let info = currentRecordingInfo {
                Text(info.baseName)
                    .font(.system(size: 12))
                    .foregroundStyle(KYColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let signal = meetingActiveSignal {
                // S20 edge case #14: a visible fallback for when the
                // MEETING_DETECTED system notification either got denied or
                // just isn't the kind of thing the user noticed — the orange
                // status-bar dot led them here, so give them the same choice
                // the notification would have.
                Text(String(format: String(localized: "检测到%@开始使用麦克风"), signal.app.displayNameKey))
                    .font(.system(size: 12))
                    .foregroundStyle(KYColor.textSecondary)
            }

            if appState.isRecording {
                PrimaryButton(
                    title: LocalizedStringKey(String(format: String(localized: "停止录音  %@"), Self.elapsedString(appState.elapsed))),
                    style: .recording,
                    leadingSystemImage: "stop.fill"
                ) {
                    Task { await appState.stopRecording() }
                }
            } else {
                PrimaryButton(title: "开始录音") {
                    Task { await appState.startManualRecording() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var meetingActiveSignal: MeetingSignal? {
        if case .meetingActive(let signal) = appState.phase { return signal }
        return nil
    }

    private var currentRecordingInfo: RecordingInfo? {
        if case .recording(let info) = appState.phase { return info }
        if case .finalizing(let info) = appState.phase { return info }
        return nil
    }

    private static func elapsedString(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: P8-P10 footer

    private var footer: some View {
        HStack(spacing: 8) {
            MarqueeText(text: Self.disclaimer, font: KYFont.popoverFooter, color: KYColor.textSecondary)

            Button {
                copyDisclaimer()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(KYColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(KYColor.bgSidebar)
        .overlay(alignment: .top) {
            Divider().foregroundStyle(KYColor.strokeHairline)
        }
    }

    private func copyDisclaimer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.disclaimer, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}

#Preview {
    PopoverView(appState: AppState(), onOpenSaveDirectory: {}, onOpenSettings: {})
}
