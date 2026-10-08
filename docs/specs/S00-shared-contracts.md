---
id: S00
title: 共享类型与契约
milestone: —
status: done
depends_on: []
estimate_days: 0.5
plan_refs: [§4, §5.1, §5.3, §8]
ui_refs: []
---

# S00 共享类型与契约

## 目标
把多个 spec 都会用到的模型、枚举、偏好键、通知标识、日志分类定死在一处，让并行开发的 spec 不会各自造一套。本 spec 的产物是 `KnowingYou/Support/Contracts.swift`（在 S01 建工程时一并落地）以及本文；后续 spec 需要新类型时**先改这里**。

## 范围
### 做
- 定义下列类型与常量（签名可微调，语义不可变）。
### 不做
- 任何实现逻辑。

## 契约

### 状态机与录音状态

```swift
/// MeetingCoordinator 的应用级状态（计划 §5.1）。
enum AppPhase: Sendable, Equatable {
    case idle
    case meetingActive(MeetingSignal)      // 白名单进程用麦克风已持续 ≥3s
    case recording(RecordingInfo)
    case finalizing(RecordingInfo)         // 正在转码 / 落盘
}

struct MeetingSignal: Sendable, Equatable {
    let app: KnownApp
    let pids: [pid_t]
    let since: Date
}

/// RecordingSession 内部状态。
enum RecordingSessionState: Sendable, Equatable {
    case preparing, recording, paused, stopping
    case finished(URL)      // 最终 .m4a
    case failed(KYError)
}
```

### 会议应用

```swift
struct KnownApp: Sendable, Hashable, Codable, Identifiable {
    var id: String { bundleIDPrefix }
    let bundleIDPrefix: String          // 前缀匹配；Electron Helper 归并到父应用
    let displayNameKey: String          // 本地化 key；文件名用运行时 CFBundleDisplayName
    let kind: Kind                      // .native 可自动录；.browser 永远只询问
    var isEnabled: Bool
    enum Kind: String, Codable, Sendable { case native, browser }
}
```

### 录音与纪要

```swift
struct RecordingInfo: Sendable, Equatable {
    let baseName: String            // "2026-09-23 14-30-12 腾讯会议"
    let directory: URL              // 保存根目录
    let startedAt: Date
    let sourceApp: String           // 应用显示名或 "手动录音"
    var audioURL: URL { directory.appendingPathComponent(baseName + ".m4a") }
    var cafURL:   URL { directory.appendingPathComponent(baseName + ".caf") }
    var notesURL: URL { directory.appendingPathComponent(baseName + ".md") }
    var assetsDir: URL { directory.appendingPathComponent(baseName, isDirectory: true) }
}

/// 目录扫描得到的列表项（弹窗"最近录音"）。
struct Recording: Sendable, Identifiable, Equatable {
    var id: String { baseName }
    let baseName: String
    let startedAt: Date
    let sourceApp: String
    let audioURL: URL
    let notesURL: URL?
    var duration: TimeInterval?     // 懒加载
}

struct NoteEntry: Sendable, Equatable, Codable, Identifiable {
    enum Kind: String, Codable, Sendable { case note, mark, screenshot, event }
    let id: UUID
    let wallClock: Date
    let offset: TimeInterval        // 距 startedAt 的真实时钟差，不扣暂停
    let kind: Kind
    var text: String                // screenshot 时为相对路径
}

struct NotesDocument: Sendable, Equatable {
    var title: String?
    let startedAt: Date
    var endedAt: Date?
    let sourceApp: String
    let audioFileName: String
    var paused: [ClosedRange<Date>]
    var entries: [NoteEntry]
    var isEmpty: Bool { title == nil && entries.isEmpty }   // 为空则不生成 .md
}
```

### 设置

```swift
enum AudioFormat: String, Codable, Sendable { case monoMix, dualTrack }
enum MicSelection: Codable, Sendable, Equatable, Hashable { case smart; case device(uid: String) }
enum AppLanguage: String, Codable, Sendable { case zhHans = "zh-Hans", en = "en" }
```

`UserDefaults` 键（统一放 `Preferences` 里，用 `@AppStorage`/`Defaults`，键名字面量只出现一次）：

| 键 | 类型 | 默认 | 用途 |
|---|---|---|---|
| `launchAtLogin` | Bool | true | G2 |
| `showDockIcon` | Bool | false | G3 |
| `appLanguage` | AppLanguage | 跟随系统 | G4 |
| `saveDirectoryPath` | String | `~/Documents/知鱼录音` 或 `~/Documents/Knowing You`（首次启动按当前语言定，之后固定） | G9 |
| `showFloatingWidget` | Bool | true | R2 |
| `micSelection` | MicSelection | .smart | R4 |
| `captureSystemAudio` | Bool | true | R6 |
| `audioFormat` | AudioFormat | .monoMix | R14 |
| `knownApps` | [KnownApp] | 默认清单 | R9 |
| `autoRecord` | Bool | false | R11 |
| `hotkeysEnabled` | Bool | true | K2 |
| `notifyMeetingDetected` / `notifyMeetingEnded` / `notifyRecordingSaved` | Bool | true | N2–N4 |
| `hasCompletedOnboarding` | Bool | false | S05 |
| `floatingWidgetTopRight` | CGPoint? | nil | S15 (top-right corner of the widget, screen coordinates; was `floatingWidgetOrigin` until 2026-10-08) |
| `recentRecordingsExpanded` | Bool | false | P7 |

快捷键由 KeyboardShortcuts 包自行持久化，名字：`toggleRecording`、`quickMark`、`screenshotMark`。

### 通知

```swift
enum NotificationCategory: String { case meetingDetected = "MEETING_DETECTED", meetingEnded = "MEETING_ENDED", recordingSaved = "RECORDING_SAVED" }
enum NotificationAction: String { case startRecording = "START_RECORDING", ignore = "IGNORE", ignoreThisMeeting = "IGNORE_THIS_MEETING" }
```

### 错误与日志

```swift
enum KYError: Error, Sendable, Equatable {
    case permissionDenied(Permission)
    case audioDeviceUnavailable(String)
    case systemAudioTapFailed(OSStatus)
    case saveDirectoryUnwritable(URL)
    case diskFull
    case encodingFailed(String)
}
enum Permission: Sendable, Equatable { case microphone, systemAudio, notifications, screenRecording }
enum PermissionStatus: Sendable, Equatable { case notDetermined, granted, denied }
```

`Permission` is `Equatable` (not just `Sendable` as first drafted) so `KYError` can auto-synthesize `Equatable`. `PermissionStatus` (added during S01) is the three-value result `Permissions` (S05) and `SystemAudioTap.probePermission()` (S08) return.

OSLog：subsystem `com.jakobhe.knowingyou`，category 与目录同名（`Meeting`、`Recording`、`Storage`、`UI`、`System`）。

### 本地化 key 约定
`<页面>.<元素编号>.<字段>`，如 `settings.general.G2.title`、`popover.P5.start`。编号直接用 `02-ui-spec.md` 里的元素编号，方便对照。

## 验收标准
- [ ] `Contracts.swift` 编译通过，无实现逻辑，全部 `Sendable`。
- [ ] 后续 spec 若引入新的跨模块类型，本文件同步更新。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | `NoteEntry.offset` 不扣暂停时长 | 计划 §5.2 "偏移时间按真实时钟连续计"，与 m4a 时间轴对齐更简单 |
| 2026-09-23 | 新增 `PermissionStatus`（S01 落地时补） | `Permission` 只是"哪种权限"，S05/S08 还需要"当前状态"三态；顺手把 `Permission` 也补成 `Equatable`，否则 `KYError` 无法自动合成 `Equatable` |
| 2026-09-23 | `MicSelection` 补 `Hashable`（S04 落地时补） | R4 麦克风 Popup 用 `BorderlessPopup<MicSelection>`，S02 的 `BorderlessPopup<T: Hashable>` 要求 T 可哈希 |
| 2026-09-23 | `KeyboardShortcuts.Name` 三个常量（`toggleRecording`/`quickMark`/`screenshotMark`）声明挪到 `Contracts.swift`（S04 落地时补），不放 S17 的 `HotkeyManager.swift` | S04 的快捷键页要在 S17 之前显示"已存值 / 未设置"，必须引用到具体的 `Name`；两处都声明会冲突，所以提前声明在这里，S17 只负责在首次启动时用 `setShortcut(_:for:)` 写入默认组合键，不再重复声明 `Name`（已同步改 S17 spec） |
