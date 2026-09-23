---
id: S17
title: HotkeyManager + 快捷键页交互
milestone: M4
status: todo
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
- [ ] 全新安装：Zoom 前台时按 ⌥⌘R → 录音开始（红点亮），再按 → 停止。
- [ ] 录音中按 ⌥⌘M → `.md` 出现 `[标记]`，即便浮窗隐藏。
- [ ] 快捷键页点"未设置"→ 录制态 → 按 ⌃⌥K → 显示 `⌃⌥K`，重启 app 后仍是；Esc 取消不改值；Delete 清空显示"未设置"。
- [ ] K2 关闭 → 三个快捷键全部失效，按钮灰显；开启后恢复。
- [ ] 恢复默认 → 三个按钮回到 `⌥⌘R` / `⌥⌘M` / `⌥⌘S`。

## 测试
`ShortcutFormattingTests`：修饰符顺序与符号。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
