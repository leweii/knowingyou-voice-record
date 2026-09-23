import SwiftUI

/// The five sidebar destinations (F2). "私有云同步" from the reference
/// prototype is dropped entirely — see docs/02-ui-spec.md §13.
enum SettingsPage: CaseIterable, Identifiable {
    case general
    case recording
    case shortcuts
    case notifications
    case about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "通用"
        case .recording: "录音"
        case .shortcuts: "快捷键"
        case .notifications: "通知"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .recording: "waveform"
        case .shortcuts: "keyboard"
        case .notifications: "bell"
        case .about: "info.circle"
        }
    }
}
