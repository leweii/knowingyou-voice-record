import AppKit
import SwiftUI

/// The menu-bar popover content (prototype §01): header, meeting-detected
/// banner, a live "recording card" (waveform + timer + mic/system meters,
/// with a flowing red border while recording), the M2 record button, recent
/// recordings, and the consent disclaimer.
struct PopoverView: View {
    static let width: CGFloat = 340
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
            if let signal = meetingActiveSignal {
                // S20 edge case #14: a visible fallback for when the
                // MEETING_DETECTED system notification either got denied or
                // just isn't the kind of thing the user noticed — the orange
                // status-bar dot led them here, so give them the same choice
                // the notification would have.
                DetectedBanner(appName: signal.app.displayNameKey)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            RecordingCard(appState: appState, info: currentRecordingInfo)
                .padding(.horizontal, 12)
            RecordButton(isRecording: appState.isRecording, title: primaryTitle) {
                if appState.isRecording {
                    Task { await appState.stopRecording() }
                } else {
                    Task { await appState.startManualRecording() }
                }
            }
            .padding(12)

            recentSection
            footer
        }
        .frame(width: Self.width)
        .kyGlass(cornerRadius: 16)
        .kyAnimation(KYMotion.state, value: meetingActiveSignal != nil)
    }

    private var primaryTitle: LocalizedStringKey {
        appState.isRecording
            ? LocalizedStringKey(String(format: String(localized: "停止录音  %@"), Self.elapsedString(appState.elapsed)))
            : "开始录音"
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            KYBrand.logo(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("知鱼录音")
                    .font(KYFont.headline)
                    .foregroundStyle(KYColor.text)
                HStack(spacing: 5) {
                    Circle()
                        .fill(KYColor.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: KYColor.accentGlow, radius: 3)
                    Text("本地 · 离线运行")
                        .font(KYFont.small)
                        .foregroundStyle(KYColor.text2)
                }
            }
            Spacer()
            KYIconButton(systemImage: "folder", help: "打开录音文件夹", action: onOpenSaveDirectory)
            KYIconButton(systemImage: "gearshape", help: "偏好设置", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Recent recordings

    private var recentSection: some View {
        VStack(spacing: 0) {
            DisclosureRow(title: "最近录音", isExpanded: $isExpanded)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .onChange(of: isExpanded) { _, newValue in
                    Preferences.shared.recentRecordingsExpanded = newValue
                }
            if isExpanded {
                RecentRecordingsList(recordings: store.recordings)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(KYColor.stroke).frame(height: 1) }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 11))
                .foregroundStyle(KYColor.text3)
            MarqueeText(text: Self.disclaimer, font: KYFont.small, color: KYColor.text3)

            Button {
                copyDisclaimer()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(didCopy ? KYColor.accent : KYColor.text3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .overlay(alignment: .top) { Rectangle().fill(KYColor.stroke).frame(height: 1) }
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

    // MARK: State helpers

    private var meetingActiveSignal: MeetingSignal? {
        if case .meetingActive(let signal) = appState.phase { return signal }
        return nil
    }

    private var currentRecordingInfo: RecordingInfo? {
        if case .recording(let info) = appState.phase { return info }
        if case .finalizing(let info) = appState.phase { return info }
        return nil
    }

    static func elapsedString(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// "检测到 X 开始使用麦克风" with a pinging dot.
private struct DetectedBanner: View {
    let appName: String

    var body: some View {
        HStack(spacing: 10) {
            PingDot()
            Text(String(format: String(localized: "检测到%@开始使用麦克风"), appName))
                .font(KYFont.caption)
                .foregroundStyle(KYColor.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KYColor.accentSoft))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KYColor.accent.opacity(0.35), lineWidth: 1))
    }
}

/// A dot with a ring that expands and fades, sonar-style.
struct PingDot: View {
    var color: Color = KYColor.accent
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if !reduceMotion {
                    PhaseAnimator([false, true]) { phase in
                        Circle()
                            .fill(color)
                            .scaleEffect(phase ? 3 : 1)
                            .opacity(phase ? 0 : 0.8)
                    } animation: { phase in
                        phase ? .easeOut(duration: 1.3) : .linear(duration: 0)
                    }
                }
            }
    }
}

/// Waveform + big timer + state line + two meters. While recording, a red
/// highlight runs around the border (the "流光" ambient loop).
private struct RecordingCard: View {
    let appState: AppState
    let info: RecordingInfo?

    var body: some View {
        let isRecording = appState.isRecording
        let tint = isRecording ? KYColor.rec : KYColor.accent
        VStack(alignment: .leading, spacing: 10) {
            WaveformView(
                level: max(appState.micLevel, appState.systemLevel),
                barCount: 52,
                barWidth: 3,
                spacing: 2,
                color: tint,
                isLive: isRecording,
                isFrozen: appState.isPaused
            )
            .frame(height: 56)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PopoverView.elapsedString(appState.displayedElapsed))
                        .font(KYFont.timerLarge)
                        .foregroundStyle(isRecording ? KYColor.text : KYColor.text2)
                        .contentTransition(.numericText())
                    HStack(spacing: 6) {
                        if isRecording {
                            BreathingDot(color: appState.isPaused ? KYColor.warn : KYColor.rec, size: 7, isBreathing: !appState.isPaused)
                        } else {
                            Circle().fill(KYColor.text3).frame(width: 7, height: 7)
                        }
                        Text(stateLine)
                            .font(KYFont.small)
                            .foregroundStyle(KYColor.text2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    meterRow(systemImage: "mic", level: appState.micLevel)
                    meterRow(systemImage: "speaker.wave.2", level: appState.systemLevel)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KYColor.surface2))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isRecording ? KYColor.rec.opacity(0.35) : KYColor.stroke, lineWidth: 1)
        )
        .overlay {
            if isRecording && !appState.isPaused {
                FlowingBorder(color: KYColor.rec, cornerRadius: 14)
            }
        }
    }

    private var stateLine: String {
        guard let info else { return String(localized: "待命中") }
        if appState.isPaused { return String(localized: "已暂停") }
        return info.baseName
    }

    private func meterRow(systemImage: String, level: Float) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(KYColor.text2)
                .frame(width: 12)
            LevelMeterView(level: level, segmentWidth: 3, segmentSpacing: 2, minHeight: 3, maxHeight: 12)
        }
    }
}

/// A short bright arc that travels around a rounded rect forever.
struct FlowingBorder: View {
    let color: Color
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let progress = (timeline.date.timeIntervalSinceReferenceDate / KYMotion.flowDuration).truncatingRemainder(dividingBy: 1)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.7),
                                .init(color: color, location: 0.85),
                                .init(color: .clear, location: 1),
                            ],
                            center: .center,
                            angle: .degrees(progress * 360)
                        ),
                        lineWidth: 1.5
                    )
                    .shadow(color: color.opacity(0.6), radius: 3)
            }
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    PopoverView(appState: AppState(), onOpenSaveDirectory: {}, onOpenSettings: {})
        .padding()
}
