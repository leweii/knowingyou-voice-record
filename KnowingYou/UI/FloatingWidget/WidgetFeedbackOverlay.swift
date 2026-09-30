import SwiftUI

/// M6 feedback layered over the floating widget. Each pulse counter change
/// plays once:
/// - mark: two gold rings burst out from `markOrigin` (the flag button in
///   the notes window, the live dot in the capsule);
/// - screenshot: viewfinder corner brackets snap inward, then a white
///   shutter flash.
/// Never intercepts clicks.
struct WidgetFeedbackOverlay: View {
    let markPulse: Int
    let screenshotPulse: Int
    let markOrigin: UnitPoint
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                markBurst
                    .position(x: proxy.size.width * markOrigin.x, y: proxy.size.height * markOrigin.y)
                shutter
            }
        }
        .allowsHitTesting(false)
    }

    private var markBurst: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .strokeBorder(KYColor.warn, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .keyframeAnimator(initialValue: Burst(), trigger: reduceMotion ? 0 : markPulse) { view, burst in
                        view.scaleEffect(burst.scale).opacity(burst.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: Double(index) * 0.1)
                            LinearKeyframe(1, duration: 0.01)
                            CubicKeyframe(0, duration: 0.6)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: Double(index) * 0.1 + 0.01)
                            CubicKeyframe(7, duration: 0.6)
                        }
                    }
            }
        }
    }

    private var shutter: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            ViewfinderBrackets()
                .stroke(KYColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .padding(6)
                .keyframeAnimator(initialValue: Brackets(), trigger: reduceMotion ? 0 : screenshotPulse) { view, brackets in
                    view.scaleEffect(brackets.scale).opacity(brackets.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1.12, duration: 0.01)
                        SpringKeyframe(1, duration: 0.25, spring: .snappy)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.01)
                        LinearKeyframe(1, duration: 0.3)
                        CubicKeyframe(0, duration: 0.25)
                    }
                }
            shape
                .fill(Color.white)
                .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : screenshotPulse) { view, opacity in
                    view.opacity(opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0, duration: 0.18)
                        LinearKeyframe(0.85, duration: 0.03)
                        CubicKeyframe(0, duration: 0.4)
                    }
                }
        }
    }

    private struct Burst {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    private struct Brackets {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}

/// Four L-shaped corners, like a camera viewfinder.
private struct ViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.18
        var path = Path()
        // top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // top-right
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // bottom-left
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}
