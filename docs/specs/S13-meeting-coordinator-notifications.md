---
id: S13
title: MeetingCoordinator 状态机 + 通知 + 自动录制
milestone: M2
status: todo
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
- [ ] 单测场景全部通过：① 白名单进程 2 s 消失 → 不进 meetingActive；② 3 s → meetingActive + 通知（autoRecord 关）；③ autoRecord 开 → 3 s 直接 recording，无通知；④ 浏览器 + autoRecord 开 → 只通知；⑤ recording 中进程消失 8 s 又出现 → 不停止；⑥ 消失 10 s → finalizing → idle + meetingEnded；⑦ 用户在 meetingActive 点通知"开始录音" → recording；⑧ "本次会议不再提示" → 同一进程存续期间不再发通知；⑨ 手动停止后该进程仍在 → 不再自动开录。
- [ ] 真机：Zoom 入会且 autoRecord 关 → 3 s 内收到"检测到 Zoom 开始使用麦克风 / 要开始录音吗？"通知，按钮可用，20 s 自动消失。
- [ ] 真机：autoRecord 开 → 入会 3 s 内菜单栏红点亮；退会 10 s 后自动停，收到"录音已保存"，文件名 `… Zoom.m4a`，点通知 Finder 定位文件。
- [ ] 真机：Chrome Meet 开麦 → 只收到询问通知，即便 autoRecord 开。
- [ ] 通知页三个开关分别关闭后对应通知不再出现。

## 测试
见交付物。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
