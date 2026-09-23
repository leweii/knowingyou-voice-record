import AppKit
import SwiftUI

/// A document file per language pair, shown by `MarkdownViewerWindow`.
/// Real content for these lands in S19; for now the bundled files are placeholders.
struct MarkdownDocument {
    let zhHansFileName: String
    let enFileName: String

    static let help = MarkdownDocument(zhHansFileName: "帮助", enFileName: "Help")
    static let terms = MarkdownDocument(zhHansFileName: "用户协议", enFileName: "Terms")
    static let privacy = MarkdownDocument(zhHansFileName: "隐私政策", enFileName: "Privacy")
    static let thirdPartyLicenses = MarkdownDocument(zhHansFileName: "第三方许可", enFileName: "ThirdPartyLicenses")

    @MainActor
    fileprivate var currentFileName: String {
        Preferences.shared.appLanguage == .en ? enFileName : zhHansFileName
    }
}

/// Generic reader window for the local help/terms/privacy documents (G6, A13, A14).
/// Reuses one window per document instead of stacking duplicates.
@MainActor
enum MarkdownViewerWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show(title: String, document: MarkdownDocument) {
        let key = document.currentFileName
        if let existing = windows[key] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: MarkdownDocumentView(text: loadMarkdown(document)))
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[key] = window
    }

    private static func loadMarkdown(_ document: MarkdownDocument) -> String {
        guard let url = Bundle.main.url(forResource: document.currentFileName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "*文档缺失：\(document.currentFileName).md*"
        }
        return text
    }
}

private struct MarkdownDocumentView: View {
    let text: String

    private var attributed: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full)))
            ?? AttributedString(text)
    }

    var body: some View {
        ScrollView {
            Text(attributed)
                .font(.system(size: 13))
                .foregroundStyle(KYColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(KYColor.bgWindow)
    }
}
