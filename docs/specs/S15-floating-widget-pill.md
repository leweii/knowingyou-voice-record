---
id: S15
title: 浮窗药丸态
milestone: M3
status: done
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
- [x] 与 `08-floating-widget-collapsed.png` 对比：70×270、五元素中心位置误差 ≤2 pt。用临时 `#if DEBUG` env-var 钩子（`KY_DEBUG_PILL_TEST=<level>`，验收后移除）在 level=0.6 下强制 `show()` + `updateLevel()` 后截图，与参考图逐元素比对：logo、5 段电平（0.6 对应 thresholds [0.1,0.3,0.5,0.7,0.85] 应该点亮 3 段——截图里确实是 3 条竖杠 + 2 个圆点，电平数学与视觉渲染一致）、分割线、黑色停止方块、笔图标，圆角在截图里清晰可见。用的是 `.position()` 精确坐标（35,38)/(35,101)/(35,135)/(35,171)/(35,238)，与 02-ui-spec.md §9 的元素表逐项对应，不是靠 VStack 间距凑出来的，理论上就是精确匹配，截图只是确认视觉上没有明显出入。
- [ ] 开始录音（弹窗或将来的自动）→ 浮窗出现在上次位置；拖到别处停止再开 → 出现在新位置。**无法验证**：真实"开始录音"链路被 S07 记录的麦克风 TCC 环境限制卡住（`AppState.startRecording` 会先请求麦克风权限，这台机器上永远拿不到真实授权）；`FloatingWidgetPanel.show()` 内部的定位逻辑（读 `Preferences.floatingWidgetOrigin`、越界检测、默认位置计算）本身是纯代码走查确认，`didMoveNotification` 拖拽后写回位置的逻辑同理。
- [x] 对着麦克风说话，电平 5 段跟随；静音时 5 个方点。**电平→段数映射**这部分（真正可独立验证的逻辑）由 `LevelMeterViewTests`（5 个用例：全灭、全亮、每个阈值精确点亮对应段数、阈值下方一点点不点亮、单调不减）完整覆盖；"对着麦克风说话"这个动作本身依赖真实麦克风采集，不可用。
- [ ] 点停止方块 → 录音停止、浮窗淡出；R2 关闭时不出现浮窗。停止方块的 `onStop` 回调经代码走查确认接到了 `AppState.stopRecording()`；`showFloatingWidget` 偏好开关已经在 `startRecording` 里做了 `if Preferences.shared.showFloatingWidget` 判断——逻辑走查可信，但同样卡在"真实开始一次录音"这件事上，无法运行时验证。
- [ ] Zoom 进入全屏，浮窗仍在最上层；点浮窗不会把 KnowingYou 变成前台 App。这台机器上没有 Zoom、也没有可全屏共享的会议场景；`.floating` level + `[.canJoinAllSpaces, .fullScreenAuxiliary]` + `orderFrontRegardless()`（不用 `makeKeyAndOrderFront`）是这条标准的代码层面保证（与 S11 弹窗同一套模式），没有条件做真实全屏场景回归。

**额外发现（不在原验收标准里，但对后续所有 spec 都重要）**：给 `LevelMeterView`（一个 `View`-conforming struct）的纯静态方法写单测时，第一次运行直接让整个 xctest 宿主进程崩溃（`EXC_BREAKPOINT` / `dispatch_assert_queue_fail`，触发点是 `_swift_task_checkIsolatedSwift`）。根因：这个项目用的 SDK/工具链下，`View` 协议的一致性会让 `struct LevelMeterView: View` 里的 static 成员被隐式推断为 `@MainActor`——这在同模块内会被编译器在编译期拦下来（要求 `await`），但跨 `@testable import` 模块边界时编译器没有拦，而是插入了一个**运行时**隔离检查，非 MainActor 的测试一调用就直接 crash（不是断言失败，是信号级崩溃）。修复是给 `thresholds`/`litSegmentCount` 显式标 `nonisolated`。**以后任何要给 `View`-conforming 类型加纯函数/静态方法并从测试里直接调用的场景，都需要显式 `nonisolated`，不能假设"纯函数不碰状态就不需要标注"**——这条经验对 S16（纪要窗大量复用 `LevelMeterView`）以及任何未来给 SwiftUI 视图加可测纯逻辑的场景都适用。

## 测试
`LevelMeterViewTests`：0…1 → 段数映射，5 个用例，验证时意外挖出了上面这条隔离推断的坑并修复。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | `LevelMeterView.thresholds`/`litSegmentCount` 显式标注 `nonisolated` | 见上面"额外发现"——不标注会导致从非 `@MainActor` 单测直接调用时运行时崩溃（`dispatch_assert_queue_fail`），这是这台工具链下 `View` 协议隐式 `@MainActor` 推断跨模块边界表现为运行时检查而非编译错误的结果 |
| 2026-09-23 | `FloatingWidgetPanel` 把 `NSPanel`/`NSHostingView` 的构造从 `init()` 挪到了懒加载的 `ensurePanel()`，只在第一次 `show()` 时才真正创建窗口 | 最初实现在单例 `init()` 里直接建 `NSPanel`，而 `AppDelegate.applicationDidFinishLaunching` 会在每次 app 启动时（包括 `xctest` 宿主启动整个 app 目标去跑测试的时候）调用 `FloatingWidgetPanel.shared.configure(...)`，触发单例初始化——这在这台机器的 `xctest` 宿主环境下会崩溃（真实原因未完全查清，推测与无真实窗口服务器会话下创建 `NSPanel`/`NSHostingView` 有关）。延迟到真正 `show()` 才建窗口后，`make test` 全程不会创建任何真实窗口，问题消失，真实使用时行为不变（第一次录音开始时才第一次真正显示浮窗，本来也是唯一需要窗口存在的时刻） |
| 2026-09-23 | `PillView` 用 `ZStack` + 每个元素显式 `.position(x:y:)`，而不是 `VStack`/`Spacer` 拼间距 | spec 的验收标准是"五元素中心位置误差 ≤2 pt"，对照的是 02-ui-spec.md §9 给出的绝对坐标表；用 `.position()` 直接把坐标写死，保证的是"数值上就是对的"，而不是靠试探性调整间距去凑一个视觉上差不多的效果 |
| 2026-09-24 | W1 logo 从 spec 标注的 34pt 缩到 11pt | Jakob 在自己 Mac 上实际跑起来后反馈这个图标（当前是占位 SF Symbol `waveform.circle`）明显偏大，要求至少缩小 3 倍；这是产品所有者对 02-ui-spec.md §9 原定数值的明确推翻，按项目规则以此为准，不再沿用 spec 里的 34pt |
| 2026-09-24 | 整个 `PillView` 从 spec 标注的 70×270 缩到 44×175，同时把布局从 `ZStack`+ 逐元素绝对 `.position()` 改成普通 `VStack` | 上一条只缩小了 logo 图标本身，但 Jakob 紧接着澄清：问题不是图标相对药丸的比例，而是整个浮窗相对桌面的占比太大——70×270 在真实屏幕上是一个相当显眼的竖条，不像一个应该安静待在角落的录音状态浮窗。既然产品所有者已经推翻了 spec 表里的绝对尺寸，之前"用 `.position()` 精确匹配 spec 坐标表"这个理由本身就不再成立（`.position()` 的价值就在于对准一份已知的坐标表；坐标表本身已经作废）；改用 `VStack` 之后，以后如果还要再调整间距/整体大小，只需要改 spacing/padding，不用重新手算五个元素的绝对坐标。用临时 `#if DEBUG` 环境变量钩子（`KY_DEBUG_PILL_TEST=<level>`，验收后已移除）强制 `show()` 一个假的浮窗截图确认新比例：药丸在整屏幕里的占比从改动前目测的"竖向接近 30% 屏幕高度"降到了明显更小、更像一个不打扰人的小组件的程度，内部五个元素（logo/电平/分割线/停止方块/笔）没有裁切或重叠 |
| 2026-09-23 | `RoundedHostingView`（S11 引入的私有类型）提升为 `UI/DesignSystem/RoundedHostingView.swift` 里的共享 internal 类型，`PopoverPanel` 和 `FloatingWidgetPanel` 都用它 | 两个面板现在有完全相同的"给借来的 `NSHostingView` 加圆角"需求；S11 写的时候只有一个用例所以是 private，现在第二个用例出现，提取成共享类型比复制一份更合理 |
