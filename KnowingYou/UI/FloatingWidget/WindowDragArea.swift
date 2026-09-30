import AppKit
import SwiftUI

/// Lets the user drag the window by grabbing any part of the SwiftUI content
/// this sits behind that isn't itself interactive. Used instead of
/// `isMovableByWindowBackground`, which the notes window must keep off (with
/// it on, clicks meant for the borderless title field/editor were read as
/// window drags — see `FloatingWidgetPanel.expand()`). Here the drag is
/// explicit: only a mouse-down that actually lands on this view moves the
/// window, and controls/text inputs layered above it keep their clicks.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
