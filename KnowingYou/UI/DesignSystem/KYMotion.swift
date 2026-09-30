import AppKit
import SwiftUI

/// Motion tokens (prototype §06 table). Five tiers, each with one job:
/// micro (hover/press) · state (toggles, indicators, record-button morph) ·
/// morph (window shape changes) · narrative (one-shot story beats: launch,
/// meeting detected, saved) · ambient (loops that only run while recording).
enum KYMotion {
    static let micro = Animation.easeOut(duration: 0.18)
    static let state = Animation.spring(response: 0.4, dampingFraction: 0.7)
    static let morph = Animation.spring(response: 0.55, dampingFraction: 0.75)
    static let pageIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)

    static let breatheDuration: Double = 1.6
    static let flowDuration: Double = 3

    /// AppKit-side counterpart of `morph` for `NSAnimationContext` window
    /// frame animations (which can't take a SwiftUI spring). A slight
    /// overshoot in the control points gives the same "elastic" feel.
    static let windowMorphDuration: TimeInterval = 0.42
    static var windowMorphTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.34, 1.25, 0.64, 1)
    }

    /// System "Reduce motion". Ambient loops and narrative sequences check
    /// this and render their resting frame instead.
    @MainActor static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

extension View {
    /// Applies `animation` unless the user has asked the system to reduce motion.
    func kyAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAwareAnimation(animation: animation, value: value))
    }
}

private struct ReduceMotionAwareAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// A dot that breathes (glow pulse) — the "recording right now" signal used
/// by the popover, pill, and notes toolbar. Static when paused or when
/// reduce-motion is on.
struct BreathingDot: View {
    var color: Color = KYColor.rec
    var size: CGFloat = 8
    var isBreathing: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = isBreathing && !reduceMotion
        PhaseAnimatorIfNeeded(animate: animate) { phase in
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(phase ? 0.9 : 0.25), radius: phase ? size * 0.9 : size * 0.3)
                .scaleEffect(phase ? 1 : 0.85)
        }
    }
}

/// Runs a two-phase (false↔true) repeating animation when `animate` is on,
/// otherwise renders the `true` (resting) frame once.
struct PhaseAnimatorIfNeeded<Content: View>: View {
    let animate: Bool
    var duration: Double = KYMotion.breatheDuration
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        if animate {
            PhaseAnimator([false, true]) { phase in
                content(phase)
            } animation: { _ in
                .easeInOut(duration: duration / 2)
            }
        } else {
            content(true)
        }
    }
}
