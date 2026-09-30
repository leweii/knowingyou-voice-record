import SwiftUI

/// First-run checklist: microphone, system audio (requested lazily at the
/// first recording — S08), notifications. Screen recording isn't onboarded
/// here — S18 requests it lazily the first time the user clicks the
/// screenshot-mark button. S22: numbered steps that spring into check marks,
/// a progress bar, and a confetti burst once both requestable permissions
/// are granted.
struct OnboardingView: View {
    static let size = CGSize(width: 520, height: 520)

    @State private var micStatus: PermissionStatus = .notDetermined
    @State private var notificationsStatus: PermissionStatus = .notDetermined
    @State private var confettiTrigger = 0
    let onFinish: () -> Void

    private var grantedCount: Int {
        [micStatus, notificationsStatus].filter { $0 == .granted }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            KYMark(size: 72, animated: true)
                .padding(.top, 36)

            Text("欢迎使用知鱼录音")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(KYColor.text)
                .padding(.top, 18)
            Text("完成以下授权后即可开始录音")
                .font(KYFont.caption)
                .foregroundStyle(KYColor.text2)
                .padding(.top, 6)

            VStack(spacing: 10) {
                PermissionStep(
                    number: 1,
                    title: "麦克风",
                    subtitle: "用于录制你自己的声音",
                    permission: .microphone,
                    status: $micStatus
                )
                DeferredStep(number: 2, title: "系统音频录制", subtitle: "用于录制会议对方的声音")
                PermissionStep(
                    number: 3,
                    title: "通知",
                    subtitle: "用于会议提醒与录音完成提醒",
                    permission: .notifications,
                    status: $notificationsStatus
                )
            }
            .padding(.top, 24)

            ProgressBar(progress: Double(grantedCount) / 2)
                .padding(.top, 22)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                KYButton("完成", style: .primary, size: .large, action: onFinish)
                    .frame(width: 120)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 36)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(KYColor.surface)
        .overlay(ConfettiBurst(trigger: confettiTrigger).allowsHitTesting(false))
        .task { await refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAll() }
        }
        .onChange(of: grantedCount) { old, new in
            if new == 2 && old < 2 { confettiTrigger += 1 }
        }
    }

    private func refreshAll() async {
        micStatus = await Permissions.shared.status(.microphone)
        notificationsStatus = await Permissions.shared.status(.notifications)
    }
}

/// One checklist row: "去授权" while undetermined, a check once granted, or
/// "打开系统设置" after the user says no.
private struct PermissionStep: View {
    let number: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let permission: Permission
    @Binding var status: PermissionStatus

    var body: some View {
        StepRow(number: number, title: title, subtitle: subtitle, isDone: status == .granted) {
            switch status {
            case .granted:
                Text("已授权")
                    .font(KYFont.caption.weight(.semibold))
                    .foregroundStyle(KYColor.accent)
            case .denied:
                KYButton("打开系统设置", size: .small) {
                    Permissions.shared.openSystemSettings(for: permission)
                }
            case .notDetermined:
                KYButton("去授权", style: .primary, size: .small) {
                    Task { status = await Permissions.shared.request(permission) }
                }
            }
        }
    }
}

/// System audio can't be requested up front; say when it will be.
private struct DeferredStep: View {
    let number: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        StepRow(number: number, title: title, subtitle: subtitle, isDone: false) {
            Text("稍后在首次录音时申请")
                .font(KYFont.small)
                .foregroundStyle(KYColor.text3)
        }
    }
}

private struct StepRow<Trailing: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isDone: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isDone ? KYColor.accent : KYColor.surface3)
                    .shadow(color: isDone ? KYColor.accentGlow : .clear, radius: 8)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KYColor.accentInk)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KYColor.text2)
                }
            }
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(isDone ? 360 : 0))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KYFont.headline)
                    .foregroundStyle(KYColor.text)
                Text(subtitle)
                    .font(KYFont.caption)
                    .foregroundStyle(KYColor.text2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: KYRadius.card, style: .continuous).fill(isDone ? KYColor.accentSoft : KYColor.surface2))
        .overlay(
            RoundedRectangle(cornerRadius: KYRadius.card, style: .continuous)
                .strokeBorder(isDone ? KYColor.accent.opacity(0.45) : KYColor.stroke, lineWidth: 1)
        )
        .kyAnimation(KYMotion.state, value: isDone)
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(KYColor.surface3)
                Capsule()
                    .fill(LinearGradient(colors: [KYColor.accent, KYColor.accentDeep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * progress)
                    .shadow(color: KYColor.accentGlow, radius: 6)
            }
        }
        .frame(height: 4)
        .kyAnimation(KYMotion.pageIn, value: progress)
    }
}

/// A one-shot burst of brand-colored confetti from the center.
struct ConfettiBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let spin: Double
        let colorIndex: Int
        let delay: Double
    }

    private static let pieces: [Piece] = (0..<60).map { index in
        // Deterministic pseudo-random spread so the burst looks organic
        // without needing a random source.
        let t = Double(index)
        return Piece(
            id: index,
            angle: t * 137.5,
            distance: 120 + CGFloat((index * 53) % 170),
            spin: Double((index * 97) % 720) - 360,
            colorIndex: index % 5,
            delay: Double(index % 6) * 0.015
        )
    }

    var body: some View {
        if trigger > 0 && !reduceMotion {
            ZStack {
                ForEach(Self.pieces) { piece in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(piece.colorIndex))
                        .frame(width: 7, height: 11)
                        .keyframeAnimator(initialValue: Flight(), trigger: trigger) { view, flight in
                            view
                                .rotationEffect(.degrees(flight.rotation))
                                .offset(x: flight.x, y: flight.y)
                                .opacity(flight.opacity)
                        } keyframes: { _ in
                            let radians = piece.angle * .pi / 180
                            KeyframeTrack(\.x) {
                                LinearKeyframe(0, duration: piece.delay)
                                CubicKeyframe(cos(radians) * piece.distance, duration: 1.4)
                            }
                            KeyframeTrack(\.y) {
                                LinearKeyframe(0, duration: piece.delay)
                                CubicKeyframe(sin(radians) * piece.distance * 0.6 - 60, duration: 0.5)
                                CubicKeyframe(sin(radians) * piece.distance * 0.6 + 220, duration: 0.9)
                            }
                            KeyframeTrack(\.rotation) {
                                LinearKeyframe(0, duration: piece.delay)
                                LinearKeyframe(piece.spin, duration: 1.4)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(1, duration: piece.delay + 0.9)
                                LinearKeyframe(0, duration: 0.5)
                            }
                        }
                }
            }
        }
    }

    private func color(_ index: Int) -> Color {
        [KYColor.accent, KYColor.rec, KYColor.warn, KYColor.accentDeep, Color.white][index]
    }

    private struct Flight {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rotation: Double = 0
        var opacity: Double = 0
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
