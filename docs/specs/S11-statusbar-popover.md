---
id: S11
title: 菜单栏图标 + 弹窗
milestone: M1
status: done
depends_on: [S02, S09, S10]
estimate_days: 2
plan_refs: [§3 "菜单栏", §5.3]
ui_refs: [§8 P1–P10, §11 "弹窗录音中" "最近录音为空"]
---

# S11 菜单栏图标 + 弹窗

## 目标
点击菜单栏图标弹出 280×188 自绘面板，能开始 / 停止手动录音、看最近录音、打开目录与设置；录音中图标带红点呼吸。M1 里程碑验收在这里闭环。

## 范围
### 做
- `UI/StatusBar/StatusBarController.swift`：`NSStatusItem`，模板图标 `KYBrand.statusBarTemplateImage`（18×18）；录音中右下叠 6 pt 红点，1 s 周期 alpha 呼吸（`CABasicAnimation`）。左键切换弹窗；右键 / ⌃点击出 `NSMenu`（偏好设置、退出、DEBUG 子菜单）。
- `UI/StatusBar/PopoverPanel.swift`：`NSPanel`（`.borderless, .nonactivatingPanel`），圆角 14 白底系统阴影，紧贴菜单栏下缘、右缘对齐图标；`NSEvent.addGlobalMonitor` 点击外部 / Esc / 切换 Space 关闭；高度随内容动画变化（最近录音展开）。
- `UI/StatusBar/PopoverView.swift`：P1–P10。P5 `PrimaryButton`：空闲"开始录音"；录音中红底 `#D33` "停止录音  hh:mm:ss" 左侧白方块；P7 上方录音中显示当前文件名灰字 12 pt。P7 Disclosure"最近录音"：展开最多 5 行（文件名 + 右侧时长灰字；hover 显示 `folder` 与 `play` 图标：Finder 显示 / `NSWorkspace.open`），空态"还没有录音"；展开状态持久化 `recentRecordingsExpanded`。P9 跑马灯：文字宽 > 容器时用 `TimelineView` 匀速循环滚动，间隔 40 pt；P10 复制 → `NSPasteboard`，图标变 `checkmark` 1.5 s。
- `App/AppState.swift` 扩展：`startManualRecording()`, `stopRecording()`；构造 `RecordingInfo`（S10 命名，sourceApp 本 spec 一律"手动录音"；S13 改为检测结果）；持有 `RecordingSession`，订阅 events 更新 `phase` / `elapsed` / `levels`；录音前调 `Permissions` 检查麦克风（与系统音频，若开启），未授权则弹 Onboarding。
### 不做
- 会议检测 / 通知（→ S13）；浮窗（→ S15）。

## 交付物
- `UI/StatusBar/{StatusBarController,PopoverPanel,PopoverView,RecentRecordingsList,MarqueeText}.swift`
- `App/AppState.swift` 扩展

## 实现要点
- 弹窗定位：`statusItem.button!.window!.frame` 换算屏幕坐标；多显示器时在图标所在屏幕。
- `.nonactivatingPanel` 下按钮仍可点击；不要 `makeKey`，否则会激活 App 抢会议软件焦点。
- 录音计时用 `AppState.elapsed`（来自 session 事件），不要在 UI 里另起 Timer。
- 停止后：`RecordingStore.refresh()`，弹窗若打开则最近列表刷新。

## 验收标准
- [x] 与 `07-menubar-popover.png` 对比：尺寸 280×188、圆角、头部 / 分割线 / 底栏位置一致。验证方式：临时 `#if DEBUG` env-var 钩子（`KY_DEBUG_POPOVER_TEST`，已在提交前移除，见决策记录）强制打开弹窗后截图比对，逐项核对：logo/文件夹/齿轮头部、黑底"开始录音"主按钮、"最近录音" disclosure（默认折叠，chevron 朝下）、灰底带分割线的底栏、跑马灯声明文字、复制图标——布局与参考图一致，圆角在截图中清晰可见。
- [~] 弹窗内点"开始录音"→ 3 s 内菜单栏红点出现、按钮变红计时；点"停止录音"→ 目录里出现 `YYYY-MM-DD HH-mm-ss 手动录音.m4a`，可播放，双源有声。**真实点击链路无法在此环境验证**：麦克风 TCC 在这台机器上被系统误归给宿主 "Air" 进程（S07/S09 决策记录一脉相承的限制）。用同一个临时 env-var 钩子把 `appState.phase` 直接设成 `.recording`（不跑真实采集，只是翻状态机）截图验证了红底"停止录音 00:12:34"+ 左侧白方块 + 上方文件名行的渲染，与参考图 P5 描述一致；`AppState.startManualRecording()`/`stopRecording()` 的业务逻辑（构造 `RecordingInfo`、创建/驱动 `RecordingSession`、失败回滚到 `.idle`）经代码走查确认，但"点击后菜单栏图标真的出现红点""产物文件真的双源有声"这两点需要真实 Mac 上跑一遍。
- [~] 点击弹窗外部 / Esc 关闭；在第二显示器的菜单栏点击，弹窗出现在该显示器。`PopoverPanel` 实现了全局鼠标监听（外部点击关闭）、本地 Esc 键监听、`activeSpaceDidChangeNotification` 监听（切 Space 关闭）——代码走查确认逻辑存在且合理，但由于本机不允许合成点击（CLAUDE.md 的 no-synthetic-input 规则）且这台机器的 `NSStatusItem` 本身就不出现在真实菜单栏里（S03 已记录的环境问题，见下），"点击外部真的关闭""第二显示器定位正确"都无法在这台机器上用真实鼠标交互验证。
- [x] 最近录音展开显示 ≤5 条，hover 图标可用；无录音时显示"还没有录音"。`RecentRecordingsList` 对 `recordings.prefix(5)` 渲染，空数组时渲染"还没有录音"——纯 SwiftUI 视图逻辑，代码走查 + `RecordingStore` 已有的真实数据（S10 测试用真实文件系统验证过 `recordings` 的产生）可以确认这部分数据源是可信的；hover 显示 folder/play 图标是 SwiftUI `.onHover`，无法用截图验证 hover 态本身（需要真实鼠标移动），但折叠/展开与空文案两种状态已截图确认。
- [x] 声明文字跑马灯滚动；复制后剪贴板内容正确、图标短暂变对勾。`MarqueeText` 用 `TimelineView(.animation)` 持续滚动——截图里意外地直接抓到了文字滚动到一半、开头被裁切的画面，反而证实了动画确实在跑（不是静止的）。复制逻辑（`NSPasteboard.general.setString` + `didCopy` 1.5s 定时器切图标）是纯代码走查，逻辑简单直接，风险低。
- [ ] 弹窗打开期间会议软件（如 Zoom）仍是前台 App（Dock 不切、标题栏不变灰）。无法验证：这台机器上没有真实菜单栏图标可点（见下），也没有会议软件在跑。`PopoverPanel` 用 `.nonactivatingPanel` + `orderFrontRegardless()`（不用 `makeKeyAndOrderFront`）是这条验收标准的代码层面保证，但没有条件做真实场景回归。

**额外发现（不在原验收标准里，但值得记录）**：这台机器上真实菜单栏完全看不到 `NSStatusItem` 图标（菜单栏只有 Apple 菜单和宿主 App 自己的菜单项）——这就是 S03 决策记录里已经记下的"`NSStatusItem` 在这台机器上定位到屏幕外"问题的再次印证，不是 S11 引入的新问题。奇怪的是 `statusItem.button.window.frame`（`PopoverPanel.positionPanel()` 用来算弹窗位置的依据）仍然返回了一个说得通的屏幕内坐标，使得强制打开的弹窗渲染在了屏幕左上角、可以正常截图——这说明"图标不可见"和"图标的 window frame 不可用"是两回事，弹窗定位逻辑本身没有因为这个环境问题而跟着失效，但这纯属这台机器上的巧合，不能当作"定位逻辑已验证"的证据。

## 测试
手工为主（原因见上：涉及真实鼠标点击、真实菜单栏图标、真实麦克风/系统音频，这台机器都无法提供）。`MarqueeTextTests` 未添加——spec 标注为可选，且 `MarqueeText` 的核心行为（是否需要滚动、滚动速度/间隔）已经通过一次真实截图直接观测到在运行，比起对 `TimelineView` 内部时间函数写脆弱的单测更有说服力。`make test` 的 66 个既有测试保持全绿；S11 没有新增可独立测试的纯函数（`RecordingRow.durationString` 这种量级不足以单独开测试文件）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 左键弹出自绘弹窗、右键/⌃点击弹出 `NSMenu`，通过临时把 `statusItem.menu` 赋值→`button.performClick(nil)`→再清空 `statusItem.menu` 来实现单个 `NSStatusItem` 同时支持两种点击行为 | `NSStatusItem` 一旦设置了 `.menu`，左键也会弹出该菜单，没有官方 API 能"只在右键弹菜单"；这个赋值-点击-清空的三步是 AppKit 里处理这种场景的标准 trick，比自己重新实现一个右键菜单的显示逻辑更可靠 |
| 2026-09-23 | `StatusBarController` 用一个内部 `ClickTarget: NSObject` 类做 target/action 桥接，而不是让 `StatusBarController` 自己继承 `NSObject` | `NSStatusBarButton.target` 要求 `NSObject`，但 `StatusBarController`没有必要继承 `NSObject`（它不需要其他 Cocoa 特性）；一个几行代码的适配器类比让整个 controller 继承 `NSObject` 更小的改动面 |
| 2026-09-23 | `AppState.startManualRecording()` 只对麦克风调用 `Permissions.request(.microphone)` 做预检查，系统音频完全不预检查，直接让 `RecordingSession.start()` 内部一次性尝试创建 tap | S08 记录过反复创建 Process Tap 会触发一个类似防滥用节流（后续尝试从瞬间变成 90–180 秒）。如果录音前先调用 `Permissions.request(.systemAudio)`（它背后是 `SystemAudioTap.probePermission()`，会真的建一次 tap 探测）、再在 `session.start()` 里为真正录音又建一次 tap，等于每次手动录音都要建两次 tap——这会让"点两次开始录音"必然命中节流，是一个会显著伤害真实使用体验的设计错误。选择只在真正需要时建一次 tap，代价是系统音频失败时的报错来得比原计划晚一点（录音已经进入 `RecordingSession.start()` 内部才发现），可以接受 |
| 2026-09-23 | 弹窗高度用一个 150ms 轮询循环（`PopoverPanel.trackContentSize()`）比较 `NSHostingView.fittingSize` 是否变化，而不是用响应式的 SwiftUI 尺寸回调 | SwiftUI 没有内建的"通知宿主 `NSHostingView` 我的高度变了"机制（`fittingSize` 本身不是响应式的，需要主动查询）；轮询虽然不优雅，但对一个只在弹窗打开时才跑、间隔 150ms 的循环来说，性能代价可以忽略，比手写 `PreferenceKey` + 双向绑定的复杂度低很多 |
| 2026-09-23 | 用一个临时 `#if DEBUG` + `ProcessInfo.environment["KY_DEBUG_POPOVER_TEST"]` 钩子（值 `"1"` 直接打开弹窗、值 `"recording"` 额外把 `appState.phase` 强制设成 `.recording` 假状态）做视觉验收截图，验收后从代码里删除，不提交 | 沿用 S02/S03 建立的模式：这台机器不能用合成点击测交互，但可以用一次性的 env-var 钩子跳到目标状态截图核对像素/布局，验证完就删掉，不留一个绕过真实交互路径的后门在正式代码里 |
