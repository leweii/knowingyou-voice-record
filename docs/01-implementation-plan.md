---
title: 知鱼录音 (Knowing You) macOS 录音 App 实现计划与技术选型
date: 2026-09-23
status: confirmed
---

# 知鱼录音 (Knowing You) macOS 录音 App 实现计划与技术选型

一句话总结：用 **Swift 6 + SwiftUI/AppKit 原生菜单栏应用** 实现，系统音频走 macOS 14.4+ 的 **Core Audio Process Tap**，会议识别靠 Core Audio **进程级麦克风占用检测**，录音与纪要以"时间戳 + 触发会议的应用"命名直接落在用户指定的本地文件夹里；整个 app **没有任何网络出口**，数据不出本机是核心卖点。UI 逐元素复刻 Plaud 桌面端（见 `02-ui-spec.md`），只去掉联网 / 账号 / AI 三类内容。

> 第 12 节的决策已由 Jakob 于 2026-09-23 确认（全部按建议值），可以开工。反馈邮箱与 Logo 仍是占位，发布前必须替换，见该节第 5、11 条。

## 1. 基本信息

| 项 | 内容 |
|---|---|
| 产品名 | Knowing You / 知鱼录音 |
| 平台 | macOS，菜单栏常驻应用（默认不显示 Dock 图标） |
| 最低系统 | macOS 14.4（Process Tap + 独立的"系统音频录制"TCC 权限的实际可用下限；主测 15 / 26） |
| 架构 | Apple Silicon 优先；Intel 可选 |
| 主语言 | Swift 6（strict concurrency，音频管线用 actor 隔离） |
| UI | SwiftUI 为主，AppKit 负责 NSStatusItem / NSPanel 浮窗 / NSOpenPanel |
| 联网 | **无**。无账号、无更新检查请求、无遥测、无云同步、无 AI 调用。仅有的"外链"是关于页里用系统浏览器打开网页，app 进程本身不发请求 |
| 分发 | Developer ID 签名 + 公证的 DMG，不上 App Store（不启用 App Sandbox） |
| 本地化 | 简体中文 + 英文（String Catalog），设置里可切换 |
| 参考原型 | Plaud 桌面端 v1.3.7 Beta，9 张截图在 `reference-screenshots/` |
| UI 规格 | `02-ui-spec.md`（逐元素、带尺寸与文案替换表） |

## 2. 产品范围

**原则：截图里的每个元素都复刻，只做三类改动**——去联网 / 账号，去 AI，换品牌文案。完整的逐元素对照在 `02-ui-spec.md`，这里只列改动摘要。

### 2.1 去掉（仅这些）

- 左栏"私有云同步"整页
- 左栏底部账号 / 会员卡片的账号语义（卡片布局保留，改显示 App 名与版本）
- 通用页"联系客服"（行位保留，改为"使用帮助"）
- 关于页 5 个社交媒体图标（改为 1 个 GitHub 图标）与"Plaud Web"按钮（改为"打开录音文件夹"）
- 纪要窗"内容由 AI 生成，仅供参考"文案（位置保留，改为"纪要仅保存在本机"）
- 录音须知中的"和转写"
- 通知页"上传完成 / 笔记就绪"的原语义（行位保留，改为"会议结束提醒 / 录音已保存提醒"）

### 2.2 新增（截图没有、但闭环必需）

- 通用页新增分组"数据与存储"：录音保存路径（核心需求）、在 Finder 中显示、磁盘占用
- 录音页新增行"音频格式"（单轨混音 / 双轨）
- 快捷键页新增行"开始 / 停止录音"
- 弹窗的录音中态、最近录音展开列表、系统通知、首次启动权限引导

### 2.3 保留原样的关键交互

- 麦克风"智能选择"Popup 与说明条、会议识别应用列表（含每个应用的 toggle）、自动录制开关、录音须知
- 快捷键录制按钮"未设置"→ 录制态 → 键帽显示，"恢复默认"
- 弹窗：文件夹 / 齿轮 / 大黑按钮 / 最近列表 disclosure / 底部跑马灯声明 + 复制按钮
- 浮窗：药丸态（logo / 电平 / 停止 / 笔）⇄ 纪要窗态（标题、正文、暂停、停止、电平计时、标记、截图、更多、收起）
- 纪要窗标题输入框保留：写入纪要 `.md` 的标题，**不影响文件名**

## 3. 技术选型

| 领域 | 选择 | 备选 | 选择理由 |
|---|---|---|---|
| App 框架 | Swift 6 + SwiftUI，AppKit 补位 | Electron / Tauri | 系统音频、TCC 权限、非激活浮窗、全局快捷键全是原生 API，Electron 在 macOS 上没有系统音频 loopback，要额外写原生模块，得不偿失 |
| 菜单栏 | `NSStatusItem` + 自定义无箭头 `NSPanel` 弹窗 | SwiftUI `MenuBarExtra(.window)`；`NSPopover` | 截图弹窗没有三角箭头、圆角 14、底部有跑马灯与分割线，需要完全自绘；`MenuBarExtra` 定制空间不够 |
| 系统音频捕获 | **Core Audio Process Tap**（`CATapDescription` + `AudioHardwareCreateProcessTap` + 私有聚合设备 + `AudioDeviceCreateIOProcIDWithBlock`） | ScreenCaptureKit 音频流；虚拟声卡（BlackHole） | Process Tap 只需"系统音频录制"权限，不需要屏幕录制权限，也不需要装驱动；可以排除自己的进程。参考实现 insidegui/AudioCap |
| 麦克风捕获 | `AVAudioEngine` inputNode tap（可指定设备） | `AVCaptureSession` | 简单、可选设备、能拿到 PCM buffer 做电平表 |
| 混音 / 编码 | 自建 `RecordingSession` actor：两路 PCM → 重采样到 48 kHz → 混合 → `AVAudioFile` 写 **CAF（录制中）**，停止后用 `AVAudioConverter` 转 **AAC m4a** | 直接写 m4a | m4a 的 moov 原子在文件尾，进程中途崩溃则文件不可播；CAF 可追加、崩溃安全，转码只需几秒 |
| 会议识别 | Core Audio 进程对象：`kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput` + `kAudioProcessPropertyBundleID`，由设备级 `kAudioDevicePropertyDeviceIsRunningSomewhere` 监听触发轮询 | 仅检查应用是否在运行；EventKit 日历 | "哪个应用正在用麦克风"是会议开始最可靠的信号，不依赖日历、不依赖联网；纯"应用在运行"会误报 |
| 浮窗 | `NSPanel`（`.nonactivatingPanel`, level `.floating`, `canJoinAllSpaces + fullScreenAuxiliary`）+ `NSHostingView`，尺寸动画在 70×270 与 418×380 间切换 | SwiftUI Window scene | 需要不抢焦点、盖在全屏会议软件之上、可拖动记忆位置、同一面板两种形态 |
| 通知 | `UNUserNotificationCenter`，带 action 按钮的 category | 自绘 HUD | 系统通知可点击"开始录音"，且在其他 app 全屏时也能弹出 |
| 全局快捷键 | sindresorhus/KeyboardShortcuts（SPM，MIT） | 自己封装 Carbon `RegisterEventHotKey` | 自带"录制快捷键"控件，重绘成截图里"未设置"的描边按钮 |
| 截屏标记 | `ScreenCaptureKit` `SCScreenshotManager` 截会议应用最前窗口 | `CGWindowListCreateImage`（已废弃） | 官方现行 API；需要屏幕录制权限，启用该功能时才申请 |
| 开机自启 | `SMAppService.mainApp`（macOS 13+） | LaunchAgent plist | 官方 API，系统设置里可见可撤销 |
| Dock 图标切换 | `LSUIElement = YES` + 运行时 `NSApp.setActivationPolicy(.regular/.accessory)` | — | 与"在 Dock 中显示图标"开关一一对应 |
| 设置存储 | `UserDefaults`（`@AppStorage` / Defaults 包） | SQLite | 设置量小；"最近录音"直接扫描保存目录，不引入数据库、不留额外元数据文件 |
| 本地化 | Xcode String Catalog（`.xcstrings`），运行时改 `AppleLanguages` 后提示重启 | — | 官方方案；设置页里"显示语言"直接可用 |
| 日志 | `OSLog` + 本地"导出诊断日志"zip | — | 无遥测的前提下给用户一个自助排障出口 |
| 测试 | Swift Testing 单元测试（纪要序列化、状态机、文件命名）+ 手工测试矩阵（各会议软件 × 麦克风类型） | XCUITest | 音频与 TCC 无法在 CI 自动化，重点保证纯逻辑部分可测 |
| 分发 | Developer ID + Hardened Runtime + notarization，DMG | App Store | Process Tap 需要非公开 Info.plist key，且沙盒会让快捷键 / 任意路径写入变复杂 |

## 4. 系统架构

```
┌──────────────────────────────────────────────────────────────────┐
│ KnowingYou.app (Swift)                                           │
│                                                                  │
│  UI 层                                                           │
│   ├─ StatusBarController      菜单栏图标 + 自定义弹窗面板          │
│   ├─ SettingsWindow           偏好设置（5 个页面）                 │
│   ├─ FloatingWidgetPanel      药丸态 ⇄ 纪要窗态                    │
│   └─ Onboarding / 权限引导                                        │
│                                                                  │
│  应用层（@MainActor / @Observable）                              │
│   ├─ AppState                 录音状态、当前录音、最近列表          │
│   ├─ MeetingCoordinator       会议识别事件 → 自动录 / 询问 / 忽略   │
│   └─ NotesStore               纪要条目（时间戳 + 偏移 + 文本）      │
│                                                                  │
│  领域层                                                          │
│   ├─ MeetingDetector (actor)  Core Audio 进程对象 → 谁在用麦克风    │
│   ├─ RecordingSession (actor) 麦克风 + 系统音频 → 混音 → CAF        │
│   │    ├─ MicCapture (AVAudioEngine)                              │
│   │    ├─ SystemAudioTap (Process Tap + 聚合设备)                   │
│   │    └─ Encoder (CAF → m4a)                                     │
│   ├─ RecordingStore           文件命名、目录扫描、崩溃恢复          │
│   ├─ ScreenshotMarker         SCScreenshotManager                 │
│   ├─ HotkeyManager            KeyboardShortcuts                   │
│   └─ Notifier                 UNUserNotificationCenter            │
│                                                                  │
│  基础设施                                                        │
│   └─ Preferences (UserDefaults) · Logger (OSLog)                 │
└──────────────────────────────────────────────────────────────────┘
        （没有网络层。App 不 link 任何网络相关代码，可用 Little Snitch 验证零连接）
```

## 5. 关键技术方案

### 5.1 会议识别

信号来源：**某个"会议类应用"开始占用麦克风**。

1. 注册设备级监听：对所有有输入流的音频设备监听 `kAudioDevicePropertyDeviceIsRunningSomewhere`；同时监听默认输入设备变化。
2. 事件触发后（以及每 2 秒的低频兜底轮询），枚举 `kAudioHardwarePropertyProcessObjectList`，对每个进程读 `kAudioProcessPropertyIsRunningInput` + `kAudioProcessPropertyBundleID`。
3. 与用户在"录音 → 会议识别"里勾选的应用列表（bundle id 集合）匹配。Electron 类应用（飞书 / Teams / 钉钉）的麦克风由 Helper 进程持有，匹配时用 bundle id **前缀**并合并到父应用。
4. 匹配到的应用名就是本次录音文件名的"会议类型"部分（见 §5.3）。
5. 状态机：

```
idle ──(白名单进程 IsRunningInput=true，持续 3s)──▶ meetingActive
meetingActive ──自动录制开──▶ recording
meetingActive ──自动录制关──▶ 发通知「检测到 XX 开始使用麦克风，要录音吗？」[开始录音][忽略]
recording ──(该进程 IsRunningInput=false 持续 1s)──▶ finalizing ──▶ idle（发"会议结束"通知）
任意状态 ──用户手动开始/停止──▶ 覆盖自动逻辑
```

6. 浏览器会议（Google Meet 等）：只能识别到"Chrome 在用麦克风"，置信度低，**永远走询问通知**不自动录；文件名里的类型记为浏览器名（如"Chrome"）。
7. 已知坑（写进测试矩阵）：macOS 26 上 `IsRunningInput` 的**属性监听不会触发**，只能读，所以设计成"设备级监听 + 轮询进程"；蓝牙麦克风的 `IsRunningSomewhere` 有系统 bug，兜底轮询可以覆盖。

默认会议应用清单：腾讯会议、飞书、钉钉、企业微信、Zoom、Microsoft Teams、FaceTime、Slack、Discord、Webex、微信（通话），以及"浏览器（仅提醒）"。允许用户从 `/Applications` 选任意 app 加入。

### 5.2 录音管线

- **麦克风**：`AVAudioEngine`，按设置选设备或跟随系统默认（"智能选择"= 系统默认 + 设备拔出时自动切换并在纪要里记一条事件）。
- **系统音频**：`CATapDescription(stereoGlobalTapButExcludeProcesses: [自身进程])`，即"录全系统、排除自己"。比逐进程 tap 稳（Electron 多进程、进程重启都不受影响）。tap → 私有聚合设备（`kAudioAggregateDeviceIsPrivateKey = true`）→ `AudioDeviceCreateIOProcIDWithBlock` 拿 buffer。注意：**不能**把 AVAudioEngine 指到 tap 聚合设备上（会静默回退到默认输入），必须直接用 IOProc。
- **混音**：两路各自 `AVAudioConverter` 到 48 kHz float，按 buffer 时间戳对齐后相加（默认单声道混音；可选"双轨"= 立体声 L 麦克风 / R 系统）。
- **写文件**：录制中写 `<文件名>.caf`（PCM 16-bit）；停止后转码为 `<文件名>.m4a`（AAC 96 kbps 单声道 / 160 kbps 双轨），成功后删 CAF。如果 app 崩溃重启，发现残留 CAF 就提示"恢复上次录音"。
- **电平表**：麦克风 tap 里算 RMS，5 段柱状图给浮窗用。
- **暂停**：停止写入但会话不结束，纪要里记 `[暂停]/[继续]` 事件，偏移时间按真实时钟连续计，暂停区间写进纪要 frontmatter。

### 5.3 文件命名与纪要格式

保存根目录：设置项，默认 `~/Documents/知鱼录音/`（英文系统为 `~/Documents/Knowing You/`）。**文件平铺，不建子文件夹**；文件名 = `开始时间戳 + 空格 + 触发会议的应用名`，纯自动生成，app 内不提供改名：

```
~/Documents/知鱼录音/
├── 2026-09-23 14-30-12 腾讯会议.m4a
├── 2026-09-23 14-30-12 腾讯会议.md          ← 仅当用户写了纪要 / 标题或打了标记时生成
├── 2026-09-23 16-05-40 Zoom.m4a
├── 2026-09-23 18-20-03 手动录音.m4a          ← 用户主动点"开始录音"、无会议应用触发时
└── 2026-09-23 14-30-12 腾讯会议/            ← 仅当用了截屏标记，存放截图
    └── 截图 14-45-30.png
```

- 时间戳到秒，避免同一分钟内两次录音撞名；再撞名追加 ` (2)`。
- 应用名取 `CFBundleDisplayName` 的本地化值（"腾讯会议" / "Zoom" / "Microsoft Teams"），去掉文件名非法字符。
- 手动开始录音时若此刻恰好有白名单应用在用麦克风，也用该应用名；否则用"手动录音"。
- 纪要窗的"会议标题"输入框只写进 `.md`，不改文件名。

`2026-09-23 14-30-12 腾讯会议.md`：

```markdown
---
title: 供应商重叠问题讨论
started_at: 2026-09-23T14:30:12+08:00
ended_at: 2026-09-23T15:17:24+08:00
duration: 00:47:12
source_app: 腾讯会议
audio: 2026-09-23 14-30-12 腾讯会议.m4a
paused: []
---

# 供应商重叠问题讨论

## 14:32:05 · +00:01:53
供应商重叠的 379 组 SKU 需要在下周前确认归属……

## 14:40:11 · +00:09:59 · [标记]

## 14:45:30 · +00:15:18 · [截图]
![[2026-09-23 14-30-12 腾讯会议/截图 14-45-30.png]]

## 15:02:47 · +00:32:35
Action：Jay 下周三前给出 42* 与 5* 合并方案
```

- 未填标题时 `title` 与 `#` 标题用文件名。
- 每条纪要 = `{wallClock, offsetFromStart, kind: note|mark|screenshot|event, text}`。用户在纪要窗里每按一次 Enter 开新条目，时间戳取**该条目第一个字符落下的时刻**。
- 内存中每 3 秒 + 停止时落盘（先写 `.tmp` 再原子替换）。
- 录音元数据只放在 `.md` frontmatter 与 m4a 自身的时长里，不再有 json 元数据文件；"最近录音"列表扫描目录、按文件名时间戳排序。

### 5.4 浮窗与纪要窗

规格见 `02-ui-spec.md` §9–§10。实现要点：

- 同一个 `NSPanel`，`setFrame(_:display:animate:)` 在 70×270 与 418×380 间做尺寸动画，锚点保持右上角不动。
- `nonactivatingPanel`：药丸态不接收键盘；纪要窗态 `becomesKeyOnlyIfNeeded = true`，点进文本区才成为 key window，不激活 App。
- `.floating` + `canJoinAllSpaces` + `fullScreenAuxiliary`，可盖在全屏会议软件上；`isMovableByWindowBackground`，位置持久化到 UserDefaults。
- 停止录音 → 面板淡出，发"录音已保存"通知。

### 5.5 通知与自动录制策略

- 会议开始提醒（可关）：`MEETING_DETECTED` category，动作：**开始录音** / 忽略 / 本次会议不再提示。通知 20 秒后自动消失，会议持续时不再重复打扰。
- 会议结束提醒（可关）：自动停止录音时发，正文为文件名。
- 录音已保存提醒（可关）：文件写入完成后发，点击在 Finder 中显示文件。
- 自动录制开启时不发询问通知。

### 5.6 快捷键、开机自启、Dock

- 全局快捷键总开关（关闭时注销全部热键，下方按钮灰显）。
- 默认键位：开始/停止录音 `⌥⌘R`；快速标记 `⌥⌘M`；截屏标记 `⌥⌘S`（用户可改，"恢复默认"一键还原）。
- 开机自启 `SMAppService`；Dock 图标开关即时生效。

### 5.7 隐私与"本地"卖点

- App 没有网络层：不 link 任何网络库；可以在关于页 / 隐私政策里写"用 Little Snitch 验证：零连接"。
- 关于页"检查更新"与 GitHub 图标只是 `NSWorkspace.open(url)` 交给系统浏览器，进程自身不发请求（是否保留见 §12）。
- 文件是通用格式（m4a + Markdown + PNG），用户随时可以用任何工具处理，不锁定。

## 6. 权限清单（TCC）

| 权限 | 触发时机 | Info.plist |
|---|---|---|
| 麦克风 | 第一次开始录音 | `NSMicrophoneUsageDescription` |
| 系统音频录制（"屏幕与系统音频录制"里的仅音频项） | 第一次开始录音且"系统音频"开启 | `NSAudioCaptureUsageDescription`（Xcode 下拉里没有，手填） |
| 通知 | 首次启动引导 | — |
| 辅助功能 | **不需要**（KeyboardShortcuts 用 Carbon 热键，不需要 AX 权限） | — |
| 屏幕录制 | 仅当用户第一次使用"截屏标记" | `NSScreenCaptureUsageDescription` |
| 登录项 | 开启开机自启时系统弹提示 | — |

## 7. 界面清单

全部见 `02-ui-spec.md`：§2 框架、§3–§7 五个设置页、§8 菜单栏弹窗、§9–§10 浮窗两态、§11 截图外必需状态、§12 文案替换表、§13 去掉项清单。

## 8. 项目结构

```
knowingyou-voice-record/
├── README.md
├── docs/
│   ├── 01-implementation-plan.md      ← 本文
│   ├── 02-ui-spec.md                  ← 逐元素 UI 规格
│   └── reference-screenshots/         ← Plaud 原型 9 张截图
├── KnowingYou.xcodeproj
├── KnowingYou/
│   ├── App/            KnowingYouApp.swift, AppDelegate.swift, AppState.swift
│   ├── UI/             StatusBar/, Settings/, FloatingWidget/, Onboarding/, DesignSystem/ (颜色 token、Toggle、描边按钮、分组标题)
│   ├── Meeting/        MeetingDetector.swift, MeetingCoordinator.swift, KnownApps.swift
│   ├── Recording/      RecordingSession.swift, MicCapture.swift, SystemAudioTap.swift,
│   │                   ProcessTap/ (移植自 AudioCap), Encoder.swift, LevelMeter.swift
│   ├── Storage/        RecordingStore.swift, RecordingNaming.swift, NotesStore.swift
│   ├── System/         HotkeyManager.swift, LaunchAtLogin.swift, Notifier.swift,
│   │                   Permissions.swift, DockIcon.swift, ScreenshotMarker.swift
│   ├── Support/        Preferences.swift, Logger.swift, DiagnosticsExport.swift
│   └── Resources/      Localizable.xcstrings, Assets, 帮助.md, 用户协议.md, 隐私政策.md
├── KnowingYouTests/    纪要序列化 / 状态机 / 文件命名（撞名、非法字符、本地化应用名）
└── scripts/            sign-and-notarize.sh, make-dmg.sh
```

## 9. 分阶段实现计划

按单人 + AI 辅助开发估算，共约 7.5 周。每个阶段末都有可运行、可自测的产物。

| 阶段 | 内容 | 产物 / 验收 | 估时 |
|---|---|---|---|
| **M0 脚手架 + 设计系统** | Xcode 工程、DesignSystem（token、Toggle、描边按钮、分组标题、设置行）、设置窗口五页按 `02-ui-spec.md` 静态还原、左栏底部卡片、String Catalog 双语、开机自启、Dock 开关、保存路径选择、权限引导页 | 五个设置页与截图逐像素对比无明显偏差；所有开关可改并持久化 | 1.5 周 |
| **M1 手动录音 + 弹窗** | 菜单栏图标与自定义弹窗（含跑马灯、复制、最近录音）、麦克风 + Process Tap 系统音频、混音、CAF → m4a、文件命名规则、崩溃恢复 | 从弹窗开录一段腾讯会议，双方声音都在，文件名为 `时间戳 腾讯会议.m4a`；kill -9 后重启能恢复 | 1.5 周 |
| **M2 会议识别** | MeetingDetector、状态机、白名单应用列表（含图标与 toggle）、询问通知、会议结束通知、自动录制、自动停止 | 打开 Zoom 入会 → 3 秒内收到通知 / 自动开录；退会约 1 秒后自动停并通知 | 1.5 周 |
| **M3 浮窗与纪要** | 药丸浮窗、电平表、尺寸动画展开纪要窗、标题与正文、时间戳条目、暂停、快速标记、`.md` 落盘 | 录音中边记边看，停止后 `.md` 时间戳与偏移正确、与 m4a 同名 | 1.5 周 |
| **M4 打磨** | 全局快捷键页（录制态、键帽显示、恢复默认）、截屏标记、关于页、帮助 / 协议 / 隐私文档、导出诊断、边界情况（设备拔插、休眠唤醒、磁盘满、路径不可写、撞名） | 手工测试矩阵：6 个会议软件 × 内置/USB/蓝牙麦 × 14.4/15/26 | 1 周 |
| **M5 发布** | 签名 + 公证脚本、DMG、首次启动体验、README | 在一台干净 Mac 上从 DMG 安装并跑通全流程；Little Snitch 确认零网络连接 | 0.5 周 |

M1 与 M2 是技术风险最高的两段，建议先做一个 2 天的 **spike**：用 AudioCap 代码在目标机器上验证 Process Tap 全局录制 + 进程级 `IsRunningInput` 读取都正常，再正式开工。

## 10. v2 候选（不在本计划内）

- **本地转写**：WhisperKit（Apple Silicon，模型下载一次即离线）或 macOS 26 的 `SpeechAnalyzer`（系统自带，零依赖）。产物是同名 `.transcript.md`，仍然全本地。
- 日历关联（EventKit 只读本地日历）：文件名里追加日程标题。
- 逐进程 tap（只录会议软件，不录系统提示音 / 音乐）。
- 深色模式。

## 11. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| Process Tap API 无正式文档，行为随系统版本变 | 系统音频录不到 / 权限弹窗不出 | 直接移植 AudioCap 已验证代码；M1 前先 spike；测试矩阵覆盖 14.4 / 15 / 26 |
| macOS 26 上进程级属性监听不触发；蓝牙麦 `IsRunningSomewhere` 不准 | 会议漏检 | 设计即为"设备级监听 + 2 秒轮询"，不依赖进程级监听 |
| 浏览器会议只能识别到浏览器 | 误报 | 浏览器永远只提醒不自动录 |
| 两路音频时钟漂移 | 长会议后期声音错位 | 按 host time 对齐，每分钟校正一次；v1 接受 <50 ms 偏差 |
| 应用名做文件名：本地化名随系统语言变、含非法字符 | 同一应用在不同语言下文件名不一致 | 用 `CFBundleDisplayName` 当前本地化值，非法字符替换为 `-`；单元测试覆盖 |
| 逐像素复刻 SwiftUI 默认控件做不到 | Toggle / 按钮样式与截图不一致 | M0 就自绘 DesignSystem 控件，不用系统 `Toggle` 默认样式 |
| 截屏标记需要屏幕录制权限 | 削弱"权限最小化"叙事 | 仅首次点击截图按钮或设置该快捷键时申请；隐私政策里说明 |
| 无自动更新 | 用户停在旧版 | 关于页"检查更新"跳 GitHub Releases；或 v1.1 加默认关闭的 Sparkle |
| 录音合规 | 法律 | 保留 Plaud 式同意声明与跑马灯；`.md` frontmatter 记录来源 app 与时间以便追溯 |

## 12. 决策记录（2026-09-23 已确认，Jakob 拍板：全部按建议值执行）

1. **最低系统版本**：14.4。
2. **音频格式默认值**：单轨混音 m4a 为默认，双轨为可选项。
3. **文件命名**：`YYYY-MM-DD HH-mm-ss 应用名.m4a` 平铺在保存目录、纪要同名 `.md`、无会议应用触发时用"手动录音"，纪要窗标题只写进 `.md` 不改文件名。
4. **关于页外链**：保留"检查更新"（跳 GitHub Releases）和一个 GitHub 图标，均由系统浏览器打开，app 进程本身不发请求。
5. **通用页"帮助与反馈"三行**：使用帮助（本地文档）/ 反馈（mailto）/ 导出诊断日志。**反馈邮箱尚未提供**——先用 Info.plist 里的占位常量 `KYFeedbackEmail`，S19 做本地化时若仍是占位则反馈按钮提示"未配置"而非打开空白邮件；S21 发布检查会拦截该占位值，必须在发布前由 Jakob 填入真实邮箱。
6. **左栏底部卡片**：改成"App 图标 + 知鱼录音 + 本地版 · 版本号"，点击跳关于。
7. **通知页第二、三行**：改成"会议结束提醒 / 录音已保存提醒"。
8. **本地转写**：不进 v1，列入 v2 候选（见 §10）。
9. **CPU 架构**：v1 只出 Apple Silicon（arm64）；Intel 视后续需求再开 spec。
10. **bundle id**：`com.jakobhe.knowingyou`。
11. **Logo**：设计稿尚未提供——先用 SF Symbol `waveform.circle` 占位，集中在 `DesignSystem/Brand.swift` 一处（菜单栏模板图标、App 图标、浮窗大字形三处引用同一函数），设计稿就位后只改这一个文件。这也是 S21 发布前必须替换的项目之一，不能带占位 logo 发布。

## References

- [insidegui/AudioCap — Sample code for recording system audio on macOS 14.4+](https://github.com/insidegui/AudioCap)
- [Recall.ai — Core Audio Taps: A deep-dive](https://www.recall.ai/blog/core-audio-taps)
- [DGR Labs — Capturing System Audio on macOS in 2026](https://dgrlabs.co/blog/2026-04-25-capturing-system-audio-on-macos-in-2026.html)
- [home-assistant/iOS #5635 — macOS 26 上 kAudioProcessPropertyIsRunningInput 监听不触发的分析](https://github.com/home-assistant/iOS/issues/5635)
- [Apple Developer Forums — Detect when microphone is being used](https://developer.apple.com/forums/thread/741026)
- [Apple Developer Forums — Issue with kAudioProcessPropertyDevices](https://developer.apple.com/forums/thread/748257)
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
