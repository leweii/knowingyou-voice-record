import SwiftUI

/// 40×24 pill toggle. Not `.toggleStyle(.switch)`: the design language needs
/// the accent fill + glow when on, and a springy knob.
struct KYToggle: View {
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    private let width: CGFloat = 40
    private let height: CGFloat = 24
    private let knobSize: CGFloat = 18

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? KYColor.accent : KYColor.surface3)
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : KYColor.strokeStrong, lineWidth: 1))
                    .shadow(color: isOn ? KYColor.accentGlow : .clear, radius: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(.horizontal, 3)
            }
            .frame(width: width, height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .kyAnimation(KYMotion.state, value: isOn)
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
