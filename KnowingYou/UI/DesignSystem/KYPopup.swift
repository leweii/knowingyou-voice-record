import AppKit
import SwiftUI

/// A bordered pop-up field that opens a native `NSMenu` on click (keyboard
/// navigation, correct positioning near screen edges, check mark on the
/// current value). Not SwiftUI's `Menu`: its `.borderlessButton` style
/// discards any custom label background/border and redraws the label as a
/// plain (icon, title) pair, so the field chrome can't be styled.
struct KYPopup<T: Hashable>: View {
    struct Option: Identifiable {
        let value: T
        let title: LocalizedStringKey
        /// Plain-string form for the `NSMenu` item (AppKit can't take a
        /// `LocalizedStringKey`). Callers pass `String(localized:)` for
        /// catalog strings, or a verbatim name (device names).
        let menuTitle: String
        var id: T { value }

        init(value: T, title: String) {
            self.value = value
            self.title = LocalizedStringKey(title)
            self.menuTitle = title
        }
    }

    @Binding var selection: T
    let options: [Option]
    /// e.g. the "sparkles" prefix on the microphone popup's 智能选择 option.
    var leadingSystemImage: String? = nil
    var minWidth: CGFloat = 150

    @State private var isHovering = false

    var body: some View {
        Button(action: showMenu) {
            label
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: KYRadius.button, style: .continuous)
        return HStack(spacing: 8) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(KYColor.accent)
            }
            Text(verbatim: currentTitle)
                .font(KYFont.control)
                .foregroundStyle(KYColor.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KYColor.text2)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: minWidth)
        .frame(height: 32)
        .background(shape.fill(isHovering ? KYColor.surface3 : KYColor.surface2))
        .overlay(shape.strokeBorder(isHovering ? KYColor.accent.opacity(0.6) : KYColor.strokeStrong, lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .kyAnimation(KYMotion.micro, value: isHovering)
    }

    private var currentTitle: String {
        options.first { $0.value == selection }?.menuTitle ?? ""
    }

    private func showMenu() {
        let menu = NSMenu()
        let binding = $selection
        for option in options {
            let item = ClosureMenuItem(title: option.menuTitle) { binding.wrappedValue = option.value }
            item.state = option.value == selection ? .on : .off
            menu.addItem(item)
        }
        // Screen coordinates (view: nil) — pops up right under the cursor,
        // which is where the click that opened it just happened.
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSEvent.mouseLocation, in: nil)
    }
}

/// `NSMenuItem` whose action is a Swift closure (the item is its own target).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        handler()
    }
}

/// Segmented control with a thumb that springs between segments.
struct KYSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [KYPopup<T>.Option]

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(KYFont.caption)
                        .fontWeight(isSelected ? .medium : .regular)
                        .foregroundStyle(isSelected ? KYColor.text : KYColor.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: KYRadius.control, style: .continuous)
                                    .fill(KYColor.surface3)
                                    .overlay(RoundedRectangle(cornerRadius: KYRadius.control).strokeBorder(KYColor.strokeStrong, lineWidth: 1))
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KYColor.surface2))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KYColor.stroke, lineWidth: 1))
        .kyAnimation(KYMotion.state, value: selection)
        .fixedSize()
    }
}

#Preview {
    VStack(spacing: 20) {
        KYPopup(
            selection: .constant("smart"),
            options: [.init(value: "smart", title: "智能选择"), .init(value: "built-in", title: "内置麦克风")],
            leadingSystemImage: "sparkles"
        )
        KYSegmented(
            selection: .constant("mono"),
            options: [.init(value: "mono", title: "单轨混音"), .init(value: "dual", title: "双轨（左麦克风 右系统）")]
        )
    }
    .padding()
}
