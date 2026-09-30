import AppKit
import SwiftUI

/// Behind-window blur for the borderless floating panels (popover, prompt
/// cards, floating widget). SwiftUI's `Material` only blends within its own
/// window, which over a transparent panel reads as flat translucency rather
/// than glass — `NSVisualEffectView` with `.behindWindow` blurs whatever is
/// actually behind the panel on screen.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension View {
    /// Glass panel chrome: behind-window blur + a tint for text contrast +
    /// a hairline inner border, clipped to `cornerRadius`.
    func kyGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            ZStack {
                VisualEffectBackground()
                KYColor.glassTint
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(KYColor.strokeStrong, lineWidth: 1))
        .clipShape(shape)
    }

    /// The standard grouped-settings card surface.
    func kyCard(cornerRadius: CGFloat = KYRadius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(KYColor.surface2))
            .overlay(shape.strokeBorder(KYColor.stroke, lineWidth: 1))
            .clipShape(shape)
    }
}
