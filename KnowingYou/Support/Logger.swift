import OSLog

/// One `Logger` per module directory, sharing the app's subsystem (see S00 §日志).
enum AppLog {
    static let subsystem = "com.jakobhe.knowingyou"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let meeting = Logger(subsystem: subsystem, category: "Meeting")
    static let recording = Logger(subsystem: subsystem, category: "Recording")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let system = Logger(subsystem: subsystem, category: "System")
}
