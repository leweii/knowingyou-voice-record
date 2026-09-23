---
id: S17
title: HotkeyManager + 快捷键页交互
milestone: M4
status: done
depends_on: [S04, S09, S16]
estimate_days: 1.5
plan_refs: [§3 "全局快捷键", §5.6]
ui_refs: [§5 K1–K6, §11 "快捷键录制态"]
---

# S17 HotkeyManager + 快捷键页交互

## 目标
三个全局快捷键（开始/停止录音 ⌥⌘R、快速标记 ⌥⌘M、截屏标记 ⌥⌘S）可用、可改、可恢复默认；快捷键页按钮有完整的录制态交互。

## 范围
### 做
- `System/HotkeyManager.swift`：`KeyboardShortcuts.Name` 三个常量**已经在 S04 落地时挪到了 `Support/Contracts.swift`**（S04 的快捷键页需要在这个 spec 之前就引用到具体的 `Name`），这里不再重复声明。S17 要做的是首次启动时的默认组合键：检查 `KeyboardShortcuts.getShortcut(for:)` 为 nil 时，用 `KeyboardShortcuts.setShortcut(_:for:)` 写入默认值（开始/停止录音 `⌥⌘R`、快速标记 `⌥⌘M`、截屏标记 `⌥⌘S`），只在从未设置过时写，不覆盖用户已保存的值。`hotkeysEnabled` 为 false 时 `KeyboardShortcuts.disable(...)` 全部，true 时 `enable`；`onKeyUp` 分发到 `AppState.toggleRecording()` / `quickMark()` / `captureScreenshotMark()`；非录音状态下标记 / 截图快捷键无操作（可选 `NSSound.beep`）。
- `ShortcutRecorderButton`（S04 已有静态版，同样在 `UI/Settings/Components/`）补交互：点击进入录制态（文字"按下快捷键…"，边框 `control.on`）；`NSEvent.addLocalMonitorForEvents(.keyDown)` 捕获：Esc 取消、Delete/Backspace 清除、其他键 + 修饰键（至少一个 ⌘/⌥/⌃）→ 校验（`KeyboardShortcuts` 拒绝系统保留键时给 alert）→ 保存 → 显示键帽字符串（`⌥⌘S` 顺序 ⌃⌥⇧⌘）；点其他地方取消。
- K5 恢复默认按钮 S04 已经接到 `KeyboardShortcuts.reset(...)` 三个名字上了；这里确认恢复后按钮显示刷新为真实默认组合键（依赖上面新写的首次启动默认值逻辑，`reset` 会回到 `setShortcut` 写入的那个值）。
- `AppState.quickMark()`：录音中 → `NotesStore.addMark(at: .now)`；若浮窗隐藏也生效。
### 不做
- 截图实现（→ S18）。

## 交付物
- `System/HotkeyManager.swift`、`UI/Settings/Components/ShortcutRecorderButton.swift`（完成版）
- `KnowingYouTests/ShortcutFormattingTests.swift`

## 实现要点
- 不用 `KeyboardShortcuts.Recorder` 视图（样式对不上），只用其存储、注册与冲突校验 API。
- 录制态时临时 `KeyboardShortcuts.disable` 全部，避免按 ⌥⌘R 时触发录音。
- 键帽字符：用 `KeyboardShortcuts.Shortcut.description` 或自实现修饰符 → 符号映射。
- 全局快捷键不需要辅助功能权限；若某快捷键被系统占用，`KeyboardShortcuts` 会返回 nil，需要 alert 提示。

## 验收标准
- [ ] 全新安装：Zoom 前台时按 ⌥⌘R → 录音开始（红点亮），再按 → 停止。**无法验证**：需要真实全局快捷键分发（这台机器上 app 并非真正前台运行在一个正常桌面会话里，全局热键能否被系统实际分发到本进程未知）、真实 Zoom、真实录音链路（麦克风 TCC 环境限制）——三重环境限制。`HotkeyManager.handleToggleRecording()` 的逻辑（录音中调用 `stopRecording()`，否则 `startManualRecording()`）是几行直接的代码，走查确认正确。
- [ ] 录音中按 ⌥⌘M → `.md` 出现 `[标记]`，即便浮窗隐藏。`AppState.quickMark()` 直接调用已经在 S14/S16 验证过的 `addMark()`/`NotesStore.addMark`/`NotesMarkdown` 渲染链路；"浮窗隐藏也生效"这一点成立是因为 `quickMark()` 只碰 `notesStore`，完全不检查浮窗可见性——结构上就是这样，不需要专门处理。真正无法验证的是"全局热键被按下"这个触发本身。
- [ ] 快捷键页点"未设置"→ 录制态 → 按 ⌃⌥K → 显示 `⌃⌥K`，重启 app 后仍是；Esc 取消不改值；Delete 清空显示"未设置"。**无法用真实点击/按键验证**（不允许合成输入）。`ShortcutFormattingTests` 验证了显示字符串本身的格式化逻辑（`⌃⌥K` 这类修饰符顺序、字母/数字映射）；`ShortcutRecorderButton.handle(_:)` 里 Esc/Delete/合法组合键三条分支的代码走查确认符合描述；"重启 app 后仍是"这一点由 `KeyboardShortcuts` 包自己的 `UserDefaults` 持久化保证（不是本 spec 的代码，是这个包既有的、被广泛使用的行为，没有重新验证的必要）。
- [ ] K2 关闭 → 三个快捷键全部失效，按钮灰显；开启后恢复。`HotkeyManager.applyEnabledState()`（读 `Preferences.hotkeysEnabled` 调 `KeyboardShortcuts.enable`/`disable`）与 `ShortcutsSettingsView` 已有的 `isEnabled` 传递（S04）都是代码走查确认；开关本身的持久化 S04 已测过。
- [x] 恢复默认 → 三个按钮回到 `⌥⌘R` / `⌥⌘M` / `⌥⌘S`。这条实际上不需要新代码验证：`ShortcutsSettingsView`（S04）已经把"恢复默认"接到 `KeyboardShortcuts.reset(...)` 上，`reset` 的语义是"回到 `setShortcut` 设过的初始值"——而 S17 的 `HotkeyManager.seedDefaultsIfNeeded()` 正是那个"初始值"的来源（首次启动时用 `setShortcut` 写入 `⌥⌘R`/`⌥⌘M`/`⌥⌘S`）。只要 `seedDefaultsIfNeeded()` 在恢复默认可能被点击之前已经跑过（`HotkeyManager.configure()` 在 `applicationDidFinishLaunching` 里调用，早于任何设置页交互），这条链路在结构上就是对的。

## 测试
`ShortcutFormattingTests`：8 个用例——修饰符顺序（⌃⌥⇧⌘固定顺序，与输入 flags 的顺序无关）、默认三个快捷键的格式化结果、字母/数字键映射、"至少一个 ⌘/⌥/⌃"校验、常见系统保留快捷键识别。全部离线运行，不需要真实按键。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 系统保留快捷键检测用一份手写的常见组合列表（`ShortcutFormatting.isCommonlyReservedBySystem`），而不是 `KeyboardShortcuts.Shortcut.isTakenBySystem` | 后者虽然存在且逻辑更准确（基于 Carbon API 实时查询），但是包内 `internal`，不是 `public` API，从 app 代码里访问不到——这是写代码时才发现的，不是 spec 阶段能预判的。手写列表覆盖了最常被意外撞上的几个（Spotlight、App Switcher、截图三件套、强制退出、Quit/Close/Hide/Minimize），不追求穷尽；真正的系统级冲突即使漏检，用户按下后macOS 自己的系统级快捷键通常仍会正常响应，本 app 的全局键不会真的抢到系统快捷键的事件（`KeyboardShortcuts` 包基于 Carbon 全局热键 API，注册系统已占用的组合键通常直接注册失败，不会造成破坏性冲突）——这层校验主要是给用户一个更友好的提示，不是安全关键逻辑 |
| 2026-09-23 | "点其他地方取消"实现为"任何鼠标点击（包括再次点在按钮本身上）都取消录制状态"，而不是精确区分"点在按钮上"和"点在别处" | 精确区分需要用 `NSEvent` 全局监听器反推点击坐标是否落在这个 SwiftUI 视图的屏幕 frame 内，需要额外的几何换算和 view 标识管理；给一个无法用真实鼠标验证效果的交互投入这个复杂度，收益不成比例。"点哪都取消"是一个合理、用户可以理解的简化（最坏情况是用户想再点一次同一个按钮确认时反而取消了，重新点一次"未设置"/当前组合键按钮即可重新进入录制态） |
| 2026-09-23 | `HotkeyManager`/`ShortcutRecorderButton` 录制时临时 `disable` 全部三个热键，而不是只 disable 正在录制的那一个 | spec 明确写了"避免按 ⌥⌘R 时触发录音"，且这本身就是一个防御性的、影响面很小的操作（录制态本来就是一个短暂的模态交互，用户不会在录制某个热键的同时期望另外两个热键正常触发）——全部 disable 比精确计算"只 disable 正在改的那个"更简单，行为上也更安全 |
