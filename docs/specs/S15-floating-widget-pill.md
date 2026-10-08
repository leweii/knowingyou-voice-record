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
| 2026-09-24 | W1 logo 从 11pt 调回 16pt（不是回到 spec 原来的 34pt） | 缩小整个药丸（见上一条）之后，Jakob 反馈 11pt 的图标在新的 44pt 宽药丸里显得太不显眼了；16pt 是这个 app 其它地方（弹窗头部的文件夹/齿轮图标等）统一在用的图标尺寸，比之前的 34pt 小得多，也比 11pt 更容易看清 |
| 2026-09-24 | `RecordingSession.pumpOnce()` 新增一条每秒一次的诊断日志，打印真实的原始线性 RMS 和归一化后的电平值 | Jakob 反馈"波形图收到声音之后没有动态动作"，但电平管线（RMS → dB 归一化 → 平滑 → `.level` 事件 → `FloatingWidgetPanel.updateLevel`）逐行代码走查没有发现问题，且用直接注入假数据的方式验证过 UI 那一半确实工作正常（见上一条决策记录）——问题很可能出在真实麦克风采集这一段，但这台环境的麦克风 TCC 被系统误归给宿主进程（S07 决策记录），完全无法用真实音频复现或验证。与其继续凭空猜测，加一条日志能在下一次真实测试时给出确切数字：如果 `rawMicRMS` 说话时仍然一直是 0，说明问题在更上游的真实采集（设备选错/静音/权限没真的生效等）；如果是一个不为零但很小的数、只是没能让柱子看起来动起来，说明问题还是在这个映射本身。这条日志本身不是修复，是为了下一轮反馈能给出诊断依据而不是继续盲改 |
| 2026-09-24 | `LevelMeterView` 从"5 段阈值梯子"（`thresholds`/`litSegmentCount`：所有段一起在同一个共享阈值下跳变，被点亮的几段固定是 `maxHeight`，其余固定是 `minHeight`）改成"5 格滚动历史"（每格独立展示最近若干次电平读数中的一个，用连续映射 `barHeight(for:minHeight:maxHeight:)` 决定高度，不再是二值跳变） | Jakob 反馈"波形图没有像真正的波形图一样显示，给人很不好的用户体验"。根因：原实现里 5 根柱子共享同一个 `level` 值，效果是所有柱子同步在同一个"阶梯"上跳变（更像电量/信号格），而不是真实波形该有的"每根柱子高度独立、随时间自然起伏"的样子。新实现用 `@State private var history: [Float]`，每次 `level` 变化（`RecordingSession` 每 50ms 推一次）就把最新值追加到历史、丢掉最旧的一个，5 根柱子各自展示历史里的一个读数，天然呈现出正常说话时高低不齐的波形观感。这也是这个视图第一次带内部状态（原来的文档注释强调"pure function of its input, no internal state/timers"）——但要在只有一个标量输入的前提下做出"看起来像波形"的效果，滚动历史几乎是唯一合理的办法；`litSegmentCount`/`thresholds` 被删除，`LevelMeterViewTests` 相应重写为测试新的连续映射函数。用临时 `#if DEBUG` 钩子（`KY_DEBUG_WAVEFORM_TEST=1`，验收后已移除）喂一串起伏的假数值截图确认：5 根柱子高度确实各不相同，不再是"整齐的台阶" |
| 2026-09-23 | `RoundedHostingView`（S11 引入的私有类型）提升为 `UI/DesignSystem/RoundedHostingView.swift` 里的共享 internal 类型，`PopoverPanel` 和 `FloatingWidgetPanel` 都用它 | 两个面板现在有完全相同的"给借来的 `NSHostingView` 加圆角"需求；S11 写的时候只有一个用例所以是 private，现在第二个用例出现，提取成共享类型比复制一份更合理 |
| 2026-09-24 | W1 logo 第三次调整：16pt → 22pt | Jakob 反馈 16pt 还是太小。这次没有再挑一个新的一次性数值，而是直接对齐 `NotesView` 头部（E1）已经在用的 22pt logo 尺寸——药丸态和纪要窗态展示的是同一个品牌标记，统一成同一个字号，比继续猜一个介于两者之间的独立数值更站得住脚，也减少了以后再被要求"调一下"的自由度 |
| 2026-09-24 | 电平表"不够实时"：去掉 `LevelMeterView` 的 `.animation(.easeOut(duration: 0.12), value: history)`，并把 `LevelSmoother` 的 `decayCoefficient` 从 0.15 提到 0.45（`attackCoefficient` 同时从 0.6 提到 0.75） | Jakob 反馈"波形图的波动不够实时，波形图应该跟当前接收到的声音一致"。这是三层延迟叠加的结果：① `LevelSmoother` 的衰减系数 0.15 意味着声音变小后电平要再过约 215ms 才降到一半，这本身就是一种"迟钝"；② `LevelMeterView` 每次电平更新（`RecordingSession` 每 50ms 推一次）都额外套了一个 0.12s 的 ease-out 缓动，等于下一次数据到达时上一次的动画还没播完，视觉上永远在"追"最新值而不是显示最新值；③ 两者叠加，观感就是"声音已经变了，波形图过一小段时间才反应"。去掉缓动让每次更新直接跳到新高度（不再有动画插值的滞后），衰减系数提到 0.45（约 65ms 降到一半）让数值本身也更快贴近真实声音；`attackCoefficient` 也同步提高，保持"起音比衰减快"这个既有关系不变（`smootherAttackIsFasterThanDecay` 测试只断言相对关系，两个系数一起调不会破坏它）。没有改动 `RecordingSession.pumpOnce()` 的 50ms 采样周期本身——那是音频混音管线的核心节奏，牵一发动全身，这次的延迟感全部来自 UI 层的平滑/动画，不需要动到音频那一层 |
| 2026-10-04 | 不再记住浮窗位置：每次开始录音，药丸都出现在**当前最前面那个窗口的右上角**（内缩 16 pt，并夹在该窗口所在屏幕的 `visibleFrame` 内）；最前面是本应用自己或没有可用窗口时，退回到鼠标所在屏幕的右上角。拖动只在本次录音内有效 | Jakob 反馈开始录音后看不到浮窗。原因：恢复的是上次拖到的位置（他机器上存的是 `[1778, 833]`），而越界检测只要求和任一屏幕有一点相交，所以在别的显示器上、或显示器布局变化后只露出一角的位置都会被照用。最前窗口用 `CGWindowListCopyWindowInfo` 取（layer 0、属于 `frontmostApplication`、≥100×100，按 z 序第一个）——窗口边界和 PID 不需要屏幕录制权限，只有窗口标题需要。`Preferences.floatingWidgetOrigin` 已不再读写，保留属性只是为了不动 S00 的契约 |
| 2026-10-08 | 浮窗位置改回"记住上次位置"：每次移动（`didMove`）、调整右/上边、关闭浮窗时保存浮窗**右上角**坐标到 `Preferences.floatingWidgetTopRight`（取代 `floatingWidgetOrigin`），下次出现时恢复；只有药丸能完整落在某块屏幕的 `visibleFrame` 内才用，否则（首次、那块显示器已不在）放到鼠标所在屏幕右上角，距菜单栏和右边缘各 20 pt。取代 2026-10-04 的"跟随最前窗口右上角" | Jakob 反馈浮窗贴着边缘，要求放右上角留一点间隔，并且关掉再开要出现在同一个地方。存右上角而不是 origin，因为浮窗在药丸/纪要窗之间以右上角为锚点变形，纪要窗态下拖动后存下的点对药丸也成立。2026-10-04 那次看不到浮窗的根因（越界检测只要求和屏幕"相交"）这次用"完整包含于 `visibleFrame`"修掉；`show()` 的滑入动画期间用 `isPlacing` 屏蔽保存，避免把动画中间位置当成用户位置 |
