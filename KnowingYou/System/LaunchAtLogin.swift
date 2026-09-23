import ServiceManagement

/// Wraps `SMAppService.mainApp` (G2). Debug/ad-hoc-signed builds can fail to
/// register — callers should catch and surface the error rather than assume success.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
