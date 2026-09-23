---
id: S16
title: 浮窗纪要窗态 + 尺寸动画
milestone: M3
status: todo
depends_on: [S15, S14]
estimate_days: 3
plan_refs: [§2.3 最后一条, §5.2 暂停, §5.4]
ui_refs: [§10 E1–E12, §11 快捷键录制态除外]
---

# S16 浮窗纪要窗态 + 尺寸动画

## 目标
同一面板动画展开为 418×380 的纪要窗：标题、逐条带时间戳的正文、暂停 / 停止 / 标记 / 截图、电平与计时、更多菜单、收起。M3 里程碑在此闭环。

## 范围
### 做
- `FloatingWidgetPanel` 扩展：`expand()` / `collapse()`，`setFrame(_:display:animate:)` 0.25 s，右上角锚定不动；展开态 `becomesKeyOnlyIfNeeded = true`（点进文本区才成 key，不激活 App）；收起时 `resignKey`。
- `UI/FloatingWidget/NotesView.swift`：E1 logo；E2 更多菜单（在 Finder 中显示 / 隐藏浮窗（本次录音）/ 偏好设置）；E3 收起；E4 "纪要仅保存在本机"；E5 标题 `TextField`（17 pt，无边框，`onChange` → `NotesStore.setTitle`）；E6 正文编辑器；E7 工具栏：E8 暂停（`pause`⇄`play.fill`，调 `RecordingSession.pause/resume`，`NotesStore.recordPause`，加 `[暂停]`/`[继续]` event 条目）、E9 停止、E10 小电平 + 计时（`mm:ss` / `h:mm:ss`，**暂停时计时停**，即显示 `elapsed - 已暂停总时长`）、E11 标记（`addMark`）、E12 截图（调 `AppState.captureScreenshotMark()`，S18 前为记录一条 event"截图功能未就绪"并 log）。
- `UI/FloatingWidget/NotesEditor.swift`：`NSViewRepresentable` 包 `NSTextView`。规则：内容按条目分段，每段一行以上；Enter 结束当前条目并开新条目；新条目的时间戳在**第一个字符落下**时 `beginEntry(at: .now)`；退格删空的条目移除；条目与 `NotesStore.document.entries` 双向同步（编辑器为主，store 为镜像）；占位态：`pencil.line` 14 pt 灰 + "随手记下你的灵感和重点"；条目之间不显示时间戳（截图里没有），时间戳只进 `.md`。
- 设备变化事件（S07 `.deviceChanged`）→ `addEvent("麦克风切换到 X")`。
- 停止：`RecordingSession.stop()` 与 `NotesStore.finish()` 并发；面板淡出；`recordingSaved` 通知（S13）。
### 不做
- 截图实现（→ S18）；全局快捷键触发标记（→ S17）。

## 交付物
- `UI/FloatingWidget/{NotesView,NotesEditor,NotesToolbar}.swift`
- `FloatingWidgetPanel` 扩展
- `KnowingYouTests/NotesEditorModelTests.swift`（条目分段逻辑抽成纯模型 `NotesEditorModel` 测）

## 实现要点
- 编辑器分段逻辑与 `NSTextView` 解耦：`NotesEditorModel` 接收 `(range, replacement)` 产出条目变化，可单测。
- `NSTextView` 在 `.nonactivatingPanel` 里要能输入：面板 `becomesKeyOnlyIfNeeded = true` 且 `canBecomeKey` 返回 true；点击文本区后 `makeFirstResponder`。
- 展开动画期间隐藏内容视图，动画结束再显示，避免布局抖动。
- "隐藏浮窗（本次录音）"：`orderOut` 但录音继续，弹窗 P5 仍可停止。

## 验收标准
- [ ] 与 `09-floating-widget-notes.png` 对比：418×380，E1–E12 位置误差 ≤2 pt。
- [ ] 点笔 / logo 展开、点收起收回，动画右上角不动；连续快速点击不错位。
- [ ] 展开后 Zoom 仍是前台 App；点进正文区可以打字，此时 Zoom 仍不显示为失焦的 Dock 切换（仅其窗口标题变灰可接受）。
- [ ] 输入"第一条" Enter "第二条"，停止后 `.md` 有两条 `##`，时间戳分别是各自第一个字符输入时刻（±1 s）。
- [ ] 暂停 20 s：计时停在原值，继续后接着走；`.md` frontmatter `paused` 有一个区间，正文有 `[暂停]`/`[继续]` 事件。
- [ ] 点标记 → `.md` 出现 `· [标记]` 条目；标题输入 → frontmatter `title` 与 `#` 一致，文件名不变。
- [ ] 什么都不写直接停止 → 不生成 `.md`。

## 测试
`NotesEditorModelTests`：Enter 分段、首字符时间戳、退格合并、粘贴多行。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 纪要窗计时暂停时停表，`NoteEntry.offset` 仍按真实时钟 | UI 直觉 vs 与音轨对齐；两者分别满足 |
