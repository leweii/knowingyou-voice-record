import AppKit
import SwiftUI

/// Clips an `NSHostingView`'s content to a rounded rect — used by every
/// borderless/transparent `NSPanel` in this app (`PopoverPanel`,
/// `FloatingWidgetPanel`) since the panel itself has no native corner
/// radius of its own.
final class RoundedHostingView<Content: View>: NSHostingView<Content> {
    var cornerRadius: CGFloat = 14 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureLayer()
    }

    convenience init(rootView: Content, cornerRadius: CGFloat) {
        self.init(rootView: rootView)
        self.cornerRadius = cornerRadius
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }
}
