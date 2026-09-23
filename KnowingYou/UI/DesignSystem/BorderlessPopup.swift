import SwiftUI

/// Borderless popup per 02-ui-spec.md §1.3: 13pt text + a gray 11pt
/// up/down-chevron affordance, opening a system menu on click.
struct BorderlessPopup<T: Hashable>: View {
    struct Option: Identifiable {
        let value: T
        let title: LocalizedStringKey
        var id: T { value }
    }

    @Binding var selection: T
    let options: [Option]
    /// e.g. the "sparkles" prefix on R4's microphone popup.
    var leadingSystemImage: String? = nil

    var body: some View {
        // A single `Text` concatenation, not an `HStack` of `Text` + `Image`s:
        // `Menu`'s borderless style treats a multi-view label as (icon, title)
        // and always draws the first `Image` it finds leading, regardless of
        // the HStack's declared order. Concatenated `Text` is one leaf view,
        // so every icon stays exactly where we put it in the chain.
        Menu {
            ForEach(options) { option in
                Button(option.title) { selection = option.value }
            }
        } label: {
            labelText
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var labelText: Text {
        let title = Text(currentTitle)
            .font(.system(size: 13))
            .foregroundStyle(KYColor.textPrimary)
        let chevron = Text("  ")
            + Text(Image(systemName: "chevron.up.chevron.down"))
                .font(.system(size: 11))
                .foregroundStyle(KYColor.textSecondary)

        guard let leadingSystemImage else {
            return title + chevron
        }
        let leading = Text(Image(systemName: leadingSystemImage))
            .font(.system(size: 13))
            .foregroundStyle(KYColor.textSecondary)
        return leading + Text(" ") + title + chevron
    }

    private var currentTitle: LocalizedStringKey {
        options.first { $0.value == selection }?.title ?? ""
    }
}

#Preview {
    BorderlessPopup(
        selection: .constant("smart"),
        options: [
            .init(value: "smart", title: "智能选择"),
            .init(value: "built-in", title: "内置麦克风"),
        ]
    )
    .padding()
}
