import SwiftUI

/// 38×22 pill toggle per 02-ui-spec.md §1.3. Not `.toggleStyle(.switch)` —
/// this app never uses system control styles, since the UI must pixel-match
/// the reference screenshots.
struct KYToggle: View {
    @Binding var isOn: Bool

    private let width: CGFloat = 38
    private let height: CGFloat = 22
    private let knobSize: CGFloat = 18
    private let knobInset: CGFloat = 2

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(isOn ? KYColor.controlOn : KYColor.controlOff)
                Circle()
                    .fill(KYColor.controlKnob)
                    .frame(width: knobSize, height: knobSize)
                    .padding(.horizontal, knobInset)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

#Preview {
    VStack(spacing: 16) {
        KYToggle(isOn: .constant(true))
        KYToggle(isOn: .constant(false))
    }
    .padding()
}
