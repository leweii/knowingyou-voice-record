---
id: S12
title: MeetingDetector + KnownApps
milestone: M2
status: done
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
- `Meeting/KnownApps.swift`：默认清单与匹配函数。bundle id 状态见 S06 spike 报告（`docs/spikes/2026-09-23-process-tap-spike.md`）——4 个已用 `mdls` 静态确认，其余 7 个仍是未经验证的猜测值，落地前用 `mdls -name kMDItemCFBundleIdentifier /Applications/<App>.app` 核实（不需要真的开会）：
  | 显示名 key | bundleIDPrefix | kind | 状态 |
  |---|---|---|---|
  | 腾讯会议 | `com.tencent.meeting` | native | 猜测，未验证（机器上没装） |
  | 飞书 | `com.bytedance.lark` | native | 猜测，未验证（机器上没装） |
  | 钉钉 | `com.alibaba.DingTalkMac` | native | 猜测，未验证（机器上没装） |
  | 企业微信 | `com.tencent.WeWorkMac` | native | 猜测，未验证（机器上没装） |
  | Zoom | `us.zoom.xos` | native | 猜测，未验证（机器上没装） |
  | Microsoft Teams | `com.microsoft.teams` | native | 猜测，未验证（机器上没装） |
  | FaceTime | `com.apple.FaceTime` | native | 猜测，未验证（系统自带但没测） |
  | Slack | `com.tinyspeck.slackmacgap` | native | **已用 `mdls` 确认** |
  | Discord | `com.hnc.Discord` | native | **已用 `mdls` 确认** |
  | Webex | `Cisco-Systems.Spark` | native | 猜测，未验证（机器上没装） |
  | 微信 | `com.tencent.xinWeChat` | native | **已用 `mdls` 确认** |
  | 浏览器（仅提醒） | `com.google.Chrome`（**已确认**）, `com.apple.Safari`, `org.mozilla.firefox`, `com.microsoft.edgemac`, `company.thebrowser.Browser` | browser | Chrome 已确认，其余未测 |
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
- [x] `KnownAppsTests`：`com.bytedance.lark.helper` 匹配到飞书；`com.google.Chrome.helper` 匹配到浏览器；未知 id 返回 nil；最长前缀优先。全部用真实 `KnownApps.defaults` 数据跑通，另加了 spec 没要求但顺手补的几个边界用例（"us.zoom.xosPro" 不该匹配 "us.zoom.xos"、`match` 本身不管 `isEnabled`）。
- [x] `MeetingDetectorTests`：假 reader 从 [] → [Zoom] → [Zoom, Chrome] → [] 得到 3 次 update，且未变化时不重复发。用可注入的 `ProcessObjectReading` 完整验证，另加了多 PID 合并、禁用应用被过滤、未匹配 bundle ID 被忽略三个用例。
- [ ] 真机：打开 Zoom 入会 → `updates` 2 s 内收到 Zoom；退会 → 2 s 内收到空集合。**无法验证**：这台机器没装 Zoom（或任何白名单里的真实会议软件），且不允许用合成输入去操作一个假想的会议流程。`CoreAudioProcessObjectReader` 是 S06 spike 里已经真实验证过、权限无关的 `who-uses-mic` 枚举逻辑的直接搬运（见 docs/spikes/2026-09-23-process-tap-spike.md），只加了"排除自身进程"这一行改动；`MeetingDetector` 之上的轮询/去重/分组逻辑已经用假数据完整测过，两者拼起来在真实会议软件下应该按预期工作，但没有条件在这台机器上把两者接在一起跑一次真实全链路。
- [ ] 真机：Chrome 打开 Meet 并开麦 → 收到 kind == .browser 的项。同上，无法在此环境验证（不允许用合成输入操作浏览器、也不会真的开一个会议链接触发麦克风）；`KnownApps.match` 对 Chrome 的匹配单测已覆盖，`kind == .browser` 字段在数据模型里已经正确标注。
- [ ] 真机：在设置里关掉 Zoom 的 toggle → 下一次轮询后 Zoom 不再出现。`MeetingDetectorTests.disabledAppsAreIgnored` 用假数据验证了"`isEnabled == false` 的应用不会出现在快照里"这条核心逻辑；"设置页面的 toggle 改动确实实时反映到下一次轮询"这条链路（`Preferences.knownApps` → `RecordingSettingsView` → 传给 `MeetingDetector.init` 的 `apps` 闭包）在 S13 真正把 `MeetingDetector` 接到 `MeetingCoordinator`、有真实调用点之前，无法端到端验证。
- [ ] 空闲时 CPU 占用不可见（<0.5%）。无法测量：`MeetingDetector` 还没有被任何调用方启动过（S13 才会真正 `start()` 它），没有真实运行中的实例可供 Activity Monitor 观察。

## 测试
见交付物；`KnownAppsTests` 7 个用例、`MeetingDetectorTests` 5 个用例，共 12 个，全部离线运行（不触真实 Core Audio），几毫秒内跑完。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-24 | 彻底删除 `KnownApp.isEnabled` 这个字段和 R9 设置页的每行开关，白名单里的应用永远全部生效，不再有"启用/禁用某个会议软件识别"这回事 | Jakob 在真机上看到 R9 列表（沿用 02-ui-spec.md §4 R9 的截图克隆，UI 上就是每行一个 Toggle）里只有腾讯会议开、其余全关，反馈"这个配置特别奇葩，应该全都支持，根本不需要配置就可以完全支持"。这其实推翻了两层东西：一是 spec 本身"第一项默认开、其余默认关"这条截图克隆的设定（S12 早前那条决策已经把默认值改成全开，但保留了开关本身），二是这次干脆连"开关"这个交互概念本身也一起去掉——产品所有者认为"识别这些常见会议软件"应该是自动生效的能力，不该是一个需要用户逐个勾选的配置项。`MeetingAppRow` 从"图标+名称+Toggle"简化成纯展示的"图标+名称"；`MeetingDetector.poll()` 不再 `.filter(\.isEnabled)`，`apps()` 返回的列表原样全部参与检测。副作用：Jakob 之前手动关掉的那些开关状态（残留在他本机已持久化的 `Preferences.knownApps` JSON 里）不需要任何迁移代码就自动失效了——`isEnabled` 字段从类型里整个删除后，`JSONDecoder` 对旧数据里多出来的这个 key 直接忽略，检测逻辑也根本不再读它，等于自动"修复"了他那台机器上看起来奇怪的持久化状态，不是巧合，是删除字段这个操作本身的自然结果。删掉了两个专门测试"禁用某个应用会被过滤掉"的单测（`KnownAppsTests.disabledAppsCanStillBeMatchedIfCallerPassesThemIn`、`MeetingDetectorTests.disabledAppsAreIgnored`）——它们测的能力已经不存在了，不是遗漏覆盖 |
| 2026-09-24 | R9 列表的 App 图标也去掉了，只剩纯文字名称 | 跟上一条同一次反馈的延伸——列表已经是纯展示、不可交互了，大部分未安装应用（这台机器上腾讯会议/飞书/钉钉/企业微信/Zoom/Teams 都没装）的图标本来就是 `AppIconView` 灰显出的空白方块，留着占地方又没有信息量，不如干脆去掉 |
| 2026-09-24 | 新增 `KnownApps.looksLikeMeetingApp(bundleID:)` 关键词兜底匹配（`meet`/`zoom`/`webex`/`teams`/`conference`/`会议`/`voov`，排除所有 `com.apple.*`），`MeetingDetector.poll()` 在精确匹配白名单失败后用它兜底，命中的进程标记为新增的 `KnownApp.Kind.inferred` | Jakob 问"识别要开始录音的条件是什么？应该跟 app 解耦"，我给出了几种本地可行的方案（摄像头+麦克风同时占用 / 窗口标题关键词 / App 名字关键词模糊匹配 / 维持现有名单）并分析了各自的误报/漏报代价，Jakob 选择"名单精确匹配 + 关键词兜底"这个折中方案（"可以"）。之所以只兜底匹配 bundle ID、不解析进程对应的运行中 App 显示名称：`ProcessObjectReading` 协议目前只暴露 `(pid, bundleID)`，要拿到真实显示名还需要额外注入一个名称解析依赖（比如 `NSRunningApplication(processIdentifier:)`），这台环境没法用真实会议软件验证这条路径值不值得加，加大 surface 但收益未知，先只做 bundle ID 关键词匹配这个成本最低的版本，效果不够再考虑加显示名。`com.apple.*` 整体排除在外是因为系统自己的一堆音频相关进程（Siri、听写、控制中心的各种音频 helper）不该被当成会议软件，况且苹果真正的会议 App（FaceTime）已经是精确匹配的白名单项，永远不会走到这条兜底逻辑。`.inferred` 被设计成一个独立于 `.native`/`.browser` 的新 `Kind`，而不是直接归到 `.native`——`MeetingCoordinator.activate` 判断"能不能自动录制"时只对 `.native` 放行，关键词猜出来的匹配天然比精确匹配的名单项更不确定，所以让它落进"总是弹通知问、绝不静默自动录制"这条分支（跟 `.browser` 一样），这是不用改动那行判断逻辑就自动获得的行为，不是巧合 |
| 2026-09-23 | `KnownApps.defaults` 里所有原生应用（`kind: .native`）默认 `isEnabled: true`，而不是延续 S04 占位列表里"只有腾讯会议默认开、其余默认关"的设定 | S12 才是这份清单的正式归属者，S04 当时的 `isEnabled` 值只是随手写的占位。产品的自动录制开关（`Preferences.autoRecord`）默认是关的（S13 状态机：`meetingActive` 时不自动录制则只发通知问用户），所以把"识别"这个更早、更低风险的环节默认开满并不会导致意外自动录音——用户依然要在通知里点"开始录音"才会真的录。默认开满对首次使用体验更好："装完就能测到常见会议软件"，而不是每个都要用户先去设置页手动打开 |
| 2026-09-23 | `MeetingDetector` 对 `kAudioHardwarePropertyDevices` 返回的**所有**设备（不筛选是否具备输入流）都挂 `kAudioDevicePropertyDeviceIsRunningSomewhere` 监听 | 和 S06 spike 工具的 `who-uses-mic --watch` 实现完全一致；精确判断"这个设备是否有输入流"需要额外读 `kAudioDevicePropertyStreamConfiguration`（scope input）并解析 `AudioBufferList`，这是这条监听路径本身只是"缩短轮询延迟"的锦上添花（2s 轮询才是 load-bearing 的兜底），投入额外复杂度换取的收益不成比例 |
| 2026-09-23 | `ProcessObjectReading` 协议方法是同步、非 `async` 的（`func activeInputProcesses() -> [(pid_t, String)]`），`MeetingDetector.poll()` 本身也是同步方法，只在 actor 外部调用点（`start()`里的轮询循环、监听回调里的 `Task { await self.poll() }`）需要 `await` | Core Audio 的这几个属性读取本身就是同步、非阻塞的系统调用（不像 `AudioDeviceStart`/Process Tap 创建那样可能触发 S08 记录的节流延迟），没有必要为一个本质同步的操作引入 `async` 接口；测试里的 `FakeProcessObjectReader` 因此也不需要处理异步 |
| 2026-09-23 | 没有真实会议软件、没有 Chrome 麦克风场景、没有真实白名单 toggle 联动这三条真机验收标准都标记为无法验证，而不是想办法在这台机器上硬凑一个"近似"验证 | 这台机器上没有安装任何白名单里的应用（S06 spike 报告里已经记录过这一点），装应用、开真实会议、用合成输入操作浏览器都超出了这个环境能负责任地做到的范围（尤其是"开真实会议"还涉及通知无关的人）。诚实标注比编一个假的"验证过"更有价值——S20 的手工测试矩阵会在真实 Mac 上补上这些 |
