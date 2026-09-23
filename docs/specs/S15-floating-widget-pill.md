---
id: S15
title: 浮窗药丸态
milestone: M3
status: todo
depends_on: [S02, S09]
estimate_days: 1.5
plan_refs: [§3 "浮窗", §5.4]
ui_refs: [§9 W1–W5, §4 R2]
---

# S15 浮窗药丸态

## 目标
录音开始时出现 70×270 的非激活浮窗：logo、5 段电平、停止、笔；可拖动、记住位置、盖在全屏会议软件上；停止时淡出。

## 范围
### 做
- `UI/FloatingWidget/FloatingWidgetPanel.swift`：`NSPanel(styleMask: [.borderless, .nonactivatingPanel])`，`level = .floating`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`，`isMovableByWindowBackground = true`，`hasShadow = true`，圆角 12 白底（`NSVisualEffectView` 不用，纯白）；`hidesOnDeactivate = false`。位置：读 `floatingWidgetOrigin`，无则主屏右缘内 16 pt、垂直居中；拖动结束写回；越界（显示器变化）时回到默认。
- `UI/FloatingWidget/PillView.swift`：W1 logo（点击 → `expand()`，本 spec 先无操作）、W2 `LevelMeterView`（5 段，4 pt 宽、间距 5，静音 4 pt 方点，随电平各段升到 16 pt；输入 0…1，段阈值 0.1/0.3/0.5/0.7/0.85，衰减用 `LevelSmoother`）、W3 分割线、W4 停止方块、W5 笔（→ `expand()`）。
- `UI/DesignSystem/LevelMeterView.swift`（放 DesignSystem，S16 小尺寸复用，参数化段高与间距）。
- `AppState` 扩展：`phase == .recording` 且 `showFloatingWidget` → `FloatingWidgetPanel.shared.show()`；停止 → `fadeOut(0.25s)` 后 `orderOut`。订阅 `.level(mic:)` 驱动电平。
### 不做
- 纪要窗态与尺寸动画（→ S16）。

## 交付物
- `UI/FloatingWidget/{FloatingWidgetPanel,PillView}.swift`、`UI/DesignSystem/LevelMeterView.swift`

## 实现要点
- 电平更新 20 Hz，UI 用 `withAnimation(.linear(0.05))`，避免 SwiftUI 每帧重排整个面板。
- `NSHostingView` 在 `.nonactivatingPanel` 里按钮可点但不会成为 key；药丸态不需要键盘。
- 全屏 Space 测试：Zoom 全屏共享时浮窗仍可见。
- `canJoinAllSpaces` 与 `isMovableByWindowBackground` 同时开，拖动时不会切 Space。

## 验收标准
- [ ] 与 `08-floating-widget-collapsed.png` 对比：70×270、五元素中心位置误差 ≤2 pt。
- [ ] 开始录音（弹窗或将来的自动）→ 浮窗出现在上次位置；拖到别处停止再开 → 出现在新位置。
- [ ] 对着麦克风说话，电平 5 段跟随；静音时 5 个方点。
- [ ] 点停止方块 → 录音停止、浮窗淡出；R2 关闭时不出现浮窗。
- [ ] Zoom 进入全屏，浮窗仍在最上层；点浮窗不会把 KnowingYou 变成前台 App。

## 测试
`LevelMeterViewTests`：0…1 → 段数映射。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
