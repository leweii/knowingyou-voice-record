import SwiftUI

/// The collapsed floating-widget state (originally 02-ui-spec.md §9's
/// 70×270, W1-W5). Jakob found that footprint way too large a share of a
/// real screen (2026-09-24) and asked for the whole widget shrunk, not just
/// the logo — see this spec's decision record. Since the owner has overridden
/// the spec's own pixel table, there's no longer a fixed reference coordinate
/// set to hit exactly, so this uses a plain top-down `VStack` (per CLAUDE.md's
/// general guidance) instead of the original `.position()`-per-element
/// layout — resizing later just means changing spacing/padding, not
/// recalculating five absolute coordinates by hand.
struct PillView: View {
    static let size = CGSize(width: 44, height: 175)

    let level: Float
    var onExpand: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Button(action: onExpand) {
                // 34pt (spec) -> 11pt ("shrink it 3x") -> 16pt (still looked
                // faint) -> 22pt: matches the logo size NotesView's header
                // uses in the expanded state, so the pill and the notes
                // window now show the same-size brand mark instead of a
                // third one-off value.
                KYBrand.logo(size: 22)
                    .foregroundStyle(KYColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            LevelMeterView(level: level, segmentWidth: 3, segmentSpacing: 2.5, minHeight: 3, maxHeight: 12)

            Rectangle()
                .fill(KYColor.strokeHairline)
                .frame(width: 28, height: 1)

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(KYColor.textPrimary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Button(action: onExpand) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14))
                    .foregroundStyle(KYColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(KYColor.bgWindow)
    }
}

#Preview {
    PillView(level: 0.6)
        .frame(width: PillView.size.width, height: PillView.size.height)
}
