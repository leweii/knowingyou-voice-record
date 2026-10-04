---
id: S13
title: MeetingCoordinator 状态机 + 通知 + 自动录制
milestone: M2
status: done
depends_on: [S12, S09, S11, S04]
estimate_days: 3.5
plan_refs: [§5.1 第 5 点, §5.3, §5.5]
ui_refs: [§6 N2–N4, §11 "会议开始系统通知" "会议结束 / 录音已保存通知"]
---

# S13 MeetingCoordinator 状态机 + 通知 + 自动录制

## 目标
把检测事件变成用户可感知的行为：自动录 / 询问 / 忽略，自动停止，发三类系统通知，文件名带上触发应用。M2 里程碑在此闭环。

## 范围
### 做
- `Meeting/MeetingCoordinator.swift`（`@MainActor`）：
  ```swift
  final class MeetingCoordinator {
      struct Timing: Sendable { var activateAfter: TimeInterval = 3; var endAfter: TimeInterval = 10; var notificationTTL: TimeInterval = 20 }
      init(detector: MeetingDetector, appState: AppState, notifier: Notifier, prefs: Preferences, clock: any Clock<Duration> = ContinuousClock(), timing: Timing = .init())
      func start()
      func userDidRespond(_ action: NotificationAction, for signal: MeetingSignal)
  }
  ```
  状态机严格按计划 §5.1：`idle → meetingActive`（白名单进程持续 3 s）；`meetingActive` 且 `autoRecord && app.kind == .native` → 立即 `recording`；否则发 `MEETING_DETECTED` 通知；`recording` 且触发进程消失持续 10 s → `stop` → `finalizing` → `idle` + `MEETING_ENDED`；用户手动开始 / 停止覆盖自动逻辑（手动停止后同一会议不再自动开录；手动开始时若有白名单进程则用其名）；"本次会议不再提示"记住 `MeetingSignal.app + since`，直到该进程消失。多个应用同时用麦克风：取最早的一个作为触发应用。浏览器永远不自动录。
- `System/Notifier.swift`：注册三个 category（含 action）；`send(meetingDetected:)` / `send(meetingEnded:)` / `send(recordingSaved:)` 各自检查偏好开关；`MEETING_DETECTED` 20 s 后 `removeDeliveredNotifications`；`UNUserNotificationCenterDelegate` 处理 action → `coordinator.userDidRespond`；点击 `RECORDING_SAVED` → `RecordingStore.reveal`；`willPresent` 返回 `.banner` 让前台时也显示。
- `AppState` 扩展：`startRecording(sourceApp:)`；录音停止且 m4a 写完 → `send(recordingSaved:)`。
- 录音页 R9 列表 toggle 已在 S04 持久化，本 spec 确认 `MeetingDetector.apps` 闭包读同一份 Preferences。
### 不做
- 浮窗（→ S15）；纪要（→ S14/S16）。

## 交付物
- `Meeting/MeetingCoordinator.swift`、`System/Notifier.swift`
- `KnowingYouTests/MeetingCoordinatorTests.swift`（注入假 detector 流与 `TestClock`，覆盖下列场景）

## 实现要点
- 状态机用 `Clock` 注入，测试用 swift-clocks 风格的手动时钟（可自己写 20 行 `ManualClock`），不要 `Task.sleep` 真等。
- 通知 action 回调在后台线程，跳回 `@MainActor`。
- LSUIElement app 的通知默认样式可能是"横幅 + 不进通知中心"，接受。
- 自动停止后如果同一应用 5 s 内又开麦（网络重连），视为新会议 → 新文件；不做合并。

## 验收标准
- [x] 单测场景全部通过：① 白名单进程 2 s 消失 → 不进 meetingActive；② 3 s → meetingActive + 通知（autoRecord 关）；③ autoRecord 开 → 3 s 直接 recording，无通知；④ 浏览器 + autoRecord 开 → 只通知；⑤ recording 中进程消失 8 s 又出现 → 不停止；⑥ 消失 10 s → finalizing → idle + meetingEnded；⑦ 用户在 meetingActive 点通知"开始录音" → recording；⑧ "本次会议不再提示" → 同一进程存续期间不再发通知；⑨ 手动停止后该进程仍在 → 不再自动开录。全部 9 个场景用 `ManualClock`（自制 20 行 `Clock` 实现）+ 假 `ProcessObjectReading` + 假 `MeetingNotifying`/`MeetingRecordingControlling` 跑通，`make test` 里 0.03 秒内完成，没有一次真实的 3s/10s 等待。
- [ ] 真机：Zoom 入会且 autoRecord 关 → 3 s 内收到"检测到 Zoom 开始使用麦克风 / 要开始录音吗？"通知，按钮可用，20 s 自动消失。**无法验证**：这台机器没装 Zoom（S12 决策记录已经记过），也无法验证真实 `UNUserNotificationCenter` 弹窗行为——这是一个 LSUIElement app，通知在无 GUI/远程环境里的实际弹出与消失行为本身就需要真实桌面会话。`Notifier.send(meetingDetected:)` 的调用时机、`removeDeliveredNotifications` 的 20s 定时器逻辑经代码走查确认；`MeetingCoordinator` 何时调用它由上面 9 个单测场景验证过。
- [ ] 真机：autoRecord 开 → 入会 3 s 内菜单栏红点亮；退会 10 s 后自动停，收到"录音已保存"，文件名 `… Zoom.m4a`，点通知 Finder 定位文件。**无法验证**：这一条同时依赖真实 Zoom、真实麦克风采集（S07 的 TCC 环境限制）、真实菜单栏图标可见性（S03/S11 已记录的环境限制）——三重环境限制叠加。状态机本身"3s 后调用 `startRecording`"这一步已经被单测 `threeSecondsWithAutoRecordOnStartsRecordingDirectly` 覆盖；`startRecording` 之后是否真的产生双源有声的 m4a、菜单栏红点是否真的亮起，分别是 S09 和 S11 各自遗留、且仍然成立的验证缺口。
- [ ] 真机：Chrome Meet 开麦 → 只收到询问通知，即便 autoRecord 开。逻辑本身由单测 `browserWithAutoRecordOnOnlyNotifiesNeverAutoRecords` 覆盖（`user.app.kind == .native` 的判断是硬编码在 `activate()` 里的，不依赖真实 Chrome）；"真的开一个 Google Meet 链接并打开麦克风"这个动作本身需要通话另一方在场或至少产生真实网络活动，不在这个环境能负责任做到的范围内。
- [ ] 通知页三个开关分别关闭后对应通知不再出现。`Notifier.send(meetingDetected:)`/`send(meetingEnded:)`（`AppState.stopRecording` 触发的 `send(recordingSaved:)`）三处都在方法开头 `guard Preferences.shared.notify*` 直接返回——代码走查可确认，S04 已经验证过这三个开关本身的持久化（`NotificationsSettingsView`），这里只是新增了读取端。

## 测试
9 个场景见上；另有 `KnownAppsTests`/`MeetingDetectorTests`（S12）为下游依赖打底。没有新增 `NotifierTests`——`Notifier`本身是对 `UNUserNotificationCenter` 的一层薄封装，其"调用了正确的 API"这件事本身很难在不真正弹通知的情况下验证，而"在正确的时机调用了 Notifier"这件事已经被 `MeetingCoordinatorTests` 用 `FakeNotifier`（`MeetingNotifying` 协议）完整覆盖。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | `MeetingCoordinator` 的 `appState`/`notifier` 参数类型是新引入的两个窄协议 `MeetingRecordingControlling`/`MeetingNotifying`，而不是 spec 草稿里写的具体类型 `AppState`/`Notifier` | 和 S12 把 Core Audio 读取抽成 `ProcessObjectReading` 是同一个理由：真实 `AppState.startRecording` 需要麦克风权限（S07 环境限制），真实 `Notifier` 需要真实 `UNUserNotificationCenter` 弹窗，两者在这台机器上都无法在单测里安全触发。`AppState`/`Notifier` 各自 `extension ... {}` 遵循对应协议，生产环境的调用方（`AppDelegate`）用回真实类型，两边接口完全一致，唯一区别是测试用假实现替换 |
| 2026-09-23 | `MeetingDetector.init` 的 `apps` 闭包从 S12 定的 `@Sendable () -> [KnownApp]`（同步）改成了 `@Sendable () async -> [KnownApp]`（异步） | 接上真实 `Preferences.shared.knownApps` 时才发现的问题：`Preferences` 是 `@MainActor` 类，它的属性不能从 `MeetingDetector`（一个独立 actor）的同步、非隔离闭包里直接读取。改成 `async` 后闭包实现里可以 `await MainActor.run { Preferences.shared.knownApps }`；`{ KnownApps.defaults }` 这种同步闭包字面量依然能满足 `async` 参数类型（Swift 允许同步函数隐式当作 async 使用），所以 S12 写的所有测试都不需要改一行 |
| 2026-09-23 | `MeetingCoordinator.Timing` 去掉了 spec 草稿里的 `notificationTTL`，20 秒的通知自动消失定时器直接写死在 `Notifier.send(meetingDetected:)` 内部 | 通知的生命周期（何时撤下）本质上是 `Notifier` 自己的职责，和状态机的 3s/10s 债务定时器不是一类东西；让 `Notifier` 自己管理这个定时器，`MeetingCoordinator.Timing` 只保留它自己真正用得上的两个参数，接口更清楚 |
| 2026-09-23 | "忽略"（`.ignore`）和"本次会议不再提示"（`.ignoreThisMeeting`）对内部 `currentSignal` 的处理不对称：后者清空 `currentSignal`（释放"当前会议"这个槽位，让检测能继续响应其它应用，同时把该 app 计入 `silencedBundleIDs` 防止同一进程存续期间重复通知），前者完全不改动状态 | 如果"忽略"也清空 `currentSignal`，同一个仍在说话的应用会在 3 秒后被重新判定为"新的 meetingActive"，导致通知每 3 秒重新弹出一次——比不清空更糟。"忽略"被理解为"这次不处理，但这个会议我还知道它在开"，状态不变，等它自然通过 10 秒无响应超时结束；"本次会议不再提示"则是明确要求"这个会议我不想再被打扰"，所以要让检测重新走一遍激活流程（这样才能命中 `silencedBundleIDs` 的过滤），而不是让旧信号一直占着位置 |
| 2026-09-23 | 新增 `MeetingRecordingControlling.setMeetingActive(_:)` 方法，而不是让协议直接暴露一个可写的 `phase` | `AppState.phase` 的 `.recording`/`.finalizing` 转换必须只能通过 `startRecording`/`stopRecording` 内部逻辑发生（否则会绕过真实的 session 生命周期管理）；`setMeetingActive` 是一个限定行为的入口——内部用 `switch phase { case .idle, .meetingActive: ...; case .recording, .finalizing: break }` 保证协调器永远不可能在录音进行中把 phase 意外改回 `.meetingActive`/`.idle` |
| 2026-10-01 | 会议结束判定从 10 s 缩短到 1 s（`Timing.endAfter = 1`），同时 `MeetingDetector` 默认轮询间隔从 2 s 缩短到 0.5 s | Jakob 要求退会后一秒就停止录音，不要再等十秒。录音期间本应用自己也在用麦克风，设备级 `DeviceIsRunningSomewhere` 监听不会因会议软件放开麦克风而触发，结束信号实际只能靠轮询；轮询 2 s 时 1 s 防抖的真实延迟会是 1–3 s，所以同步缩到 0.5 s（枚举进程对象只是几次 Core Audio 属性读取，开销可忽略），真实延迟约 1–1.5 s。代价：会议中麦克风短暂中断超过 1 s（例如某些应用静音时释放麦克风、浏览器重抢麦克风）会被当成会议结束而停录；同一 `endAfter` 也用于"同一会议不再重复提示"的清除窗口，因此超过 1 s 的中断后可能再次提示 |
