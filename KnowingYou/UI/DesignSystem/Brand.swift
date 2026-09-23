import SwiftUI
import AppKit

/// Every place the logo appears goes through here, so the real logo (still
/// unreleased — see docs/01-implementation-plan.md §12.11) is a one-file swap.
enum KYBrand {
    static let placeholderSymbolName = "waveform.circle"

    static func logo(size: CGFloat) -> some View {
        Image(systemName: placeholderSymbolName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    static var statusBarTemplateImage: NSImage? {
        let image = NSImage(systemSymbolName: placeholderSymbolName, accessibilityDescription: "知鱼录音")
        image?.isTemplate = true
        return image
    }
}
