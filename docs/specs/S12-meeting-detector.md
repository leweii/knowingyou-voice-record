---
id: S12
title: MeetingDetector + KnownApps
milestone: M2
status: todo
depends_on: [S06]
estimate_days: 2.5
plan_refs: [§5.1 第 1–4、6–7 点, §11]
ui_refs: [§4 R9]
---

# S12 MeetingDetector + KnownApps

## 目标
一个 actor 持续回答"此刻哪些白名单应用在用麦克风"，以事件流输出变化；不含状态机与业务决策。

## 范围
### 做
- `Meeting/KnownApps.swift`：默认清单（**bundle id 以 S06 报告为准**，下表为初值）与匹配函数：
  | 显示名 key | bundleIDPrefix | kind |
  |---|---|---|
  | 腾讯会议 | `com.tencent.meeting` | native |
  | 飞书 | `com.bytedance.lark` | native |
  | 钉钉 | `com.alibaba.DingTalkMac` | native |
  | 企业微信 | `com.tencent.WeWorkMac` | native |
  | Zoom | `us.zoom.xos` | native |
  | Microsoft Teams | `com.microsoft.teams` | native |
  | FaceTime | `com.apple.FaceTime` | native |
  | Slack | `com.tinyspeck.slackmacgap` | native |
  | Discord | `com.hnc.Discord` | native |
  | Webex | `Cisco-Systems.Spark` | native |
  | 微信 | `com.tencent.xinWeChat` | native |
  | 浏览器（仅提醒） | `com.google.Chrome`, `com.apple.Safari`, `org.mozilla.firefox`, `com.microsoft.edgemac`, `company.thebrowser.Browser` | browser |
  ```swift
  enum KnownApps {
      static let defaults: [KnownApp]
      static func match(bundleID: String, in apps: [KnownApp]) -> KnownApp?   // 最长前缀匹配；Helper 归并
  }
  ```
- `Meeting/MeetingDetector.swift`：
  ```swift
  actor MeetingDetector {
      struct ActiveMicUser: Sendable, Equatable { let app: KnownApp; let pids: [pid_t]; let bundleIDs: [String] }
      init(apps: @Sendable @escaping () -> [KnownApp])       // 读取当前白名单（含 isEnabled）
      nonisolated var updates: AsyncStream<[ActiveMicUser]> { get }   // 仅在集合变化时发
      func start() async; func stop() async
      func snapshot() async -> [ActiveMicUser]                 // S13 手动开录时取名用
  }
  ```
- 触发源：所有有输入流的设备的 `kAudioDevicePropertyDeviceIsRunningSomewhere` 监听；`kAudioHardwarePropertyDefaultInputDevice` 变化；`kAudioHardwarePropertyDevices` 变化（重新挂监听）；**2 s 定时兜底轮询**。
- 每次触发：枚举 `kAudioHardwarePropertyProcessObjectList`，读 `kAudioProcessPropertyIsRunningInput`、`kAudioProcessPropertyBundleID`、`kAudioProcessPropertyPID`；过滤 `isEnabled` 且匹配的；同一 `KnownApp` 多进程合并；与上次集合 diff 后发事件。
- 排除自身进程。
### 不做
- 3 s / 10 s 去抖与状态机（→ S13）；通知。

## 交付物
- `Meeting/{KnownApps,MeetingDetector,ProcessObjectReader}.swift`
- `KnowingYouTests/{KnownAppsTests,MeetingDetectorTests}.swift`（Detector 用可注入的 `ProcessObjectReading` 协议喂假数据）

## 实现要点
- 把 Core Audio 读取抽成 `protocol ProcessObjectReading { func activeInputProcesses() -> [(pid, bundleID)] }`，便于单测与 S06 spike 代码复用。
- 监听回调在 Core Audio 线程，只 `Task { await self.poll() }`，不要在回调里读属性。
- 轮询是 load-bearing（macOS 26 进程级监听不触发）；不要因为"监听能用"就去掉。
- 白名单变化（用户改 toggle）时 `apps()` 下次轮询即生效，无需重启。

## 验收标准
- [ ] `KnownAppsTests`：`com.bytedance.lark.helper` 匹配到飞书；`com.google.Chrome.helper` 匹配到浏览器；未知 id 返回 nil；最长前缀优先。
- [ ] `MeetingDetectorTests`：假 reader 从 [] → [Zoom] → [Zoom, Chrome] → [] 得到 3 次 update，且未变化时不重复发。
- [ ] 真机：打开 Zoom 入会 → `updates` 2 s 内收到 Zoom；退会 → 2 s 内收到空集合。
- [ ] 真机：Chrome 打开 Meet 并开麦 → 收到 kind == .browser 的项。
- [ ] 真机：在设置里关掉 Zoom 的 toggle → 下一次轮询后 Zoom 不再出现。
- [ ] 空闲时 CPU 占用不可见（<0.5%）。

## 测试
见交付物。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
