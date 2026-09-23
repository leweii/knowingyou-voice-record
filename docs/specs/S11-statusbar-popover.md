---
id: S11
title: 菜单栏图标 + 弹窗
milestone: M1
status: todo
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
- [ ] 与 `07-menubar-popover.png` 对比：尺寸 280×188、圆角、头部 / 分割线 / 底栏位置一致。
- [ ] 弹窗内点"开始录音"→ 3 s 内菜单栏红点出现、按钮变红计时；点"停止录音"→ 目录里出现 `YYYY-MM-DD HH-mm-ss 手动录音.m4a`，可播放，双源有声。
- [ ] 点击弹窗外部 / Esc 关闭；在第二显示器的菜单栏点击，弹窗出现在该显示器。
- [ ] 最近录音展开显示 ≤5 条，hover 图标可用；无录音时显示"还没有录音"。
- [ ] 声明文字跑马灯滚动；复制后剪贴板内容正确、图标短暂变对勾。
- [ ] 弹窗打开期间会议软件（如 Zoom）仍是前台 App（Dock 不切、标题栏不变灰）。

## 测试
手工为主；`MarqueeTextTests` 可选。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
