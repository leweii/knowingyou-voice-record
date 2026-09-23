import SwiftUI
import AppKit

/// 20×20 rounded app icon for meeting-app rows (§4 R9). Grays out apps that
/// aren't installed rather than hiding them — the user may install them later.
struct AppIconView: View {
    let bundleIdentifier: String
    var size: CGFloat = 20

    private var nsImage: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var isInstalled: Bool { nsImage != nil }

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .padding(3)
                    .foregroundStyle(KYColor.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 4 / 20))
        .opacity(isInstalled ? 1 : 0.4)
    }
}

#Preview {
    HStack(spacing: 12) {
        AppIconView(bundleIdentifier: "com.apple.FaceTime")
        AppIconView(bundleIdentifier: "com.example.not-installed")
    }
    .padding()
}
