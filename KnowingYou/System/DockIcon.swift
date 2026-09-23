import AppKit

/// Backs G3. Takes effect immediately — no restart needed.
@MainActor
enum DockIcon {
    static func setVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
