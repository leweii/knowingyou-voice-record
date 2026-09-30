import SwiftUI

/// Horizontally auto-scrolling text for P9's disclaimer line (02-ui-spec.md
/// §8, P9): scrolls only when the text is wider than the available space,
/// at a constant speed, looping.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var height: CGFloat = 16
    /// Points per second.
    var speed: Double = 40

    @State private var textWidth: CGFloat = 0

    private var gap: CGFloat { 40 }

    var body: some View {
        GeometryReader { proxy in
            let needsScroll = textWidth > proxy.size.width
            TimelineView(.animation) { timeline in
                let cycleDistance = textWidth + gap
                let offset: CGFloat = needsScroll && cycleDistance > 0
                    ? -((timeline.date.timeIntervalSinceReferenceDate * speed)
                        .truncatingRemainder(dividingBy: cycleDistance))
                    : 0

                HStack(spacing: gap) {
                    label
                    if needsScroll {
                        label
                    }
                }
                .offset(x: offset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        .frame(height: height)
        .background(widthMeasurer)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .fixedSize()
    }

    /// Measures the text's natural width once, off-screen, so we know
    /// whether scrolling is needed without guessing from character count.
    private var widthMeasurer: some View {
        label
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { textWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newValue in textWidth = newValue }
                }
            )
    }
}

#Preview {
    MarqueeText(
        text: "开始录音即代表你确认所有参会者均已获悉本次会议将被录音",
        font: KYFont.small,
        color: KYColor.text3
    )
    .frame(width: 200)
    .padding()
}
