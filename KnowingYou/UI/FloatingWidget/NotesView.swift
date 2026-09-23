import AppKit
import SwiftUI

/// The expanded 418×380 notes-window state (02-ui-spec.md §10, E1-E12).
/// The header icons (E1-E3) use the spec's absolute `.position()`
/// coordinates like `PillView` does; the title/editor/toolbar are a plain
/// top-to-bottom `VStack` instead — mixing an NSViewRepresentable-backed
/// text editor into an absolutely-positioned `ZStack` alongside sibling
/// SwiftUI views caused the editor's `NSScrollView` to visually paint over
/// everything below it regardless of declared z-order or `.clipped()` (see
/// this spec's decision record); a normal top-down layout sidesteps that
/// entirely since nothing overlaps.
struct NotesView: View {
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

            Text("纪要仅保存在本机")
                .font(.system(size: 11))
                .foregroundStyle(KYColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            TextField("会议标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .onChange(of: title) { _, newValue in
                    notesStore.setTitle(newValue)
                }

            editorArea
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(width: Self.size.width, height: Self.size.height)
        .background(KYColor.bgWindow)
        .onAppear { title = notesStore.document.title ?? "" }
    }

    private var header: some View {
        ZStack {
            KYBrand.logo(size: 22)
                .foregroundStyle(KYColor.textPrimary)
                .position(x: 28, y: 22)

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
            .position(x: 355, y: 22)

            Button(action: onCollapse) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 16))
                    .foregroundStyle(KYColor.textSecondary)
            }
            .buttonStyle(.plain)
            .position(x: 394, y: 22)
        }
    }

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            if isEditorEmpty {
                (Text(Image(systemName: "pencil.line")) + Text("  随手记下你的灵感和重点"))
                    .font(.system(size: 13))
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
}
