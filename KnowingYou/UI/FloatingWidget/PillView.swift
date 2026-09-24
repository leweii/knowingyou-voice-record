import SwiftUI

/// The collapsed 70×270 floating-widget state (02-ui-spec.md §9, W1-W5).
/// Positioned with explicit `.position()` coordinates rather than stacked
/// spacing, so it matches the spec's element-center table exactly.
struct PillView: View {
    static let size = CGSize(width: 70, height: 270)

    let level: Float
    var onExpand: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        ZStack {
            Button(action: onExpand) {
                // 02-ui-spec.md §9 (W1) called for ~34pt, but Jakob found
                // that way too large against the placeholder SF Symbol logo
                // on a real Mac (2026-09-24) and asked for at least a 3x
                // reduction — see S15's decision record.
                KYBrand.logo(size: 11)
                    .foregroundStyle(KYColor.textPrimary)
            }
            .buttonStyle(.plain)
            .position(x: 35, y: 38)

            LevelMeterView(level: level)
                .position(x: 35, y: 101)

            Rectangle()
                .fill(KYColor.strokeHairline)
                .frame(width: 50, height: 1)
                .position(x: 35, y: 135)

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(KYColor.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .position(x: 35, y: 171)

            Button(action: onExpand) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 26))
                    .foregroundStyle(KYColor.textPrimary)
            }
            .buttonStyle(.plain)
            .position(x: 35, y: 238)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(KYColor.bgWindow)
    }
}

#Preview {
    PillView(level: 0.6)
        .frame(width: PillView.size.width, height: PillView.size.height)
}
