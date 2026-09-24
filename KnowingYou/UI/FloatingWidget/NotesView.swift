import AppKit
import SwiftUI

/// The expanded notes-window state (02-ui-spec.md §10, E1-E12), default size
/// 418×380 but now user-resizable (2026-09-24, Jakob's real-Mac feedback:
/// "窗口大小需要可调整") — see `FloatingWidgetPanel`'s decision record. Since
/// the window's width is no longer fixed, the header (E1-E3) and toolbar use
/// flexible `HStack`+`Spacer` layouts instead of the original spec's
/// window-absolute `.position()` coordinates, so the logo/menu/collapse
/// icons stay pinned to their respective edges and the toolbar's button
/// groups stay evenly spaced at any window width. The title/editor/toolbar
/// were already a plain top-to-bottom `VStack` (mixing an
/// `NSViewRepresentable`-backed text editor into an absolutely-positioned
/// `ZStack` alongside sibling SwiftUI views caused the editor's
/// `NSScrollView` to visually paint over everything below it regardless of
/// declared z-order or `.clipped()` — see this spec's decision record); a
/// normal top-down layout sidesteps that entirely since nothing overlaps.
struct NotesView: View {
    /// Default/initial size only — the window is resizable, see above.
    static let size = CGSize(width: 418, height: 380)

    let notesStore: NotesStore
    let isPaused: Bool
    let micLevel: Float
    let displayedElapsed: TimeInterval
    var onCollapse: () -> Void = {}
    var onRevealInFinder: () -> Void = {}
    var onHideWidget: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}
    var onMark: () -> Void = {}
    var onScreenshot: () -> Void = {}

    @State private var title: String = ""
    @State private var isEditorEmpty = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 44)

            TextField("会议标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .onChange(of: title) { _, newValue in
                    notesStore.setTitle(newValue)
                }

            editorArea
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Defensive: NotesEditor wraps a real NSScrollView/NSTextView
                // (NSViewRepresentable), which has previously been observed
                // to visually paint outside whatever space SwiftUI allocated
                // it — see this file's decision record. `.clipped()` makes
                // that a hard clip instead of relying on layout math alone
                // (doubly relevant now that the window is resizable and can
                // be squeezed toward its minimum size).
                .clipped()

            NotesToolbar(
                isPaused: isPaused,
                micLevel: micLevel,
                displayedElapsed: displayedElapsed,
                onTogglePause: onTogglePause,
                onStop: onStop,
                onMark: onMark,
                onScreenshot: onScreenshot
            )
            .frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KYColor.bgWindow)
        .onAppear { title = notesStore.document.title ?? "" }
    }

    private var header: some View {
        HStack(spacing: 12) {
            KYBrand.logo(size: 22)
                .foregroundStyle(KYColor.textPrimary)

            Spacer(minLength: 0)

            Menu {
                Button("在 Finder 中显示", action: onRevealInFinder)
                Button("隐藏浮窗（本次录音）", action: onHideWidget)
                Button("偏好设置…", action: onOpenSettings)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button(action: onCollapse) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            if isEditorEmpty {
                (Text(Image(systemName: "pencil.line")) + Text("  随手记下你的灵感和重点"))
                    .font(.system(size: 14))
                    .foregroundStyle(KYColor.textPlaceholder)
                    .allowsHitTesting(false)
            }
            NotesEditor(notesStore: notesStore, isEmpty: $isEditorEmpty)
        }
    }
}

#Preview {
    NotesView(
        notesStore: NotesStore(info: RecordingInfo(
            baseName: "预览",
            directory: FileManager.default.temporaryDirectory,
            startedAt: .now,
            sourceApp: "手动录音"
        )),
        isPaused: false,
        micLevel: 0.4,
        displayedElapsed: 25
    )
    .frame(width: NotesView.size.width, height: NotesView.size.height)
}
