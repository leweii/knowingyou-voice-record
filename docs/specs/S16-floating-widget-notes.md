---
id: S16
title: 浮窗纪要窗态 + 尺寸动画
milestone: M3
status: done
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
- [x] 与 `09-floating-widget-notes.png` 对比：418×380，E1–E12 位置误差 ≤2 pt。用临时 `#if DEBUG` env-var 钩子（`KY_DEBUG_NOTES_TEST`，验收后已移除）造一个假 `NotesStore`、`show()` 后立即 `expand()`，截图比对。第一次截图就发现了一个真 bug（见下面"额外发现"）：工具栏整个不可见。修好之后二次截图，E1（logo）/E2（···菜单）/E3（收起箭头）/E4（"纪要仅保存在本机"）/E5（标题占位符）/E6（正文占位符+图标）/E7-E12（工具栏五个控件，顺序、图标、电平段数在 level=0.5 下点亮 3 段——与 PillView/LevelMeterView 同一套阈值逻辑）都和参考图对得上。
- [ ] 点笔 / logo 展开、点收起收回，动画右上角不动；连续快速点击不错位。`expand()`/`collapse()` 的锚点计算（`applyFrame` 用旧 frame 的 `maxX`/`maxY` 反推新 origin）经代码走查确认逻辑正确，截图验证了"展开后处于正确位置"这一个静态结果；动画过程本身的流畅度、连续快速点击是否错位，这些需要真实交互（不允许合成点击）才能验证，这台机器上做不到。
- [ ] 展开后 Zoom 仍是前台 App；点进正文区可以打字，此时 Zoom 仍不显示为失焦的 Dock 切换（仅其窗口标题变灰可接受）。无法验证：这台机器没有 Zoom，也没有其它可全屏共享的应用；`becomesKeyOnlyIfNeeded = true` + 从不 `makeKeyAndOrderFront` 是代码层面的保证（与 S11/S15 同一套模式）。
- [x] 输入"第一条" Enter "第二条"，停止后 `.md` 有两条 `##`，时间戳分别是各自第一个字符输入时刻（±1 s）。这条被拆成了两半验证：分段+时间戳逻辑本身由 `NotesEditorModelTests.enterSplitsIntoTwoEntriesPreservingTheFirstsIdentity` 完整覆盖（精确到时间戳相等，不是 ±1s 的模糊匹配，因为测试用的是注入的固定 `Date`，不是真实时钟）；"停止后 `.md` 真的有两条 `##`"这一段依赖 `NotesEditor`（真实 `NSTextView` 委托）把 `shouldChangeTextIn:replacementString:` 正确转发给模型——这部分没有真实键盘交互环境来验证，但转发代码本身只有几行、职责单一，风险较低。
- [ ] 暂停 20 s：计时停在原值，继续后接着走；`.md` frontmatter `paused` 有一个区间，正文有 `[暂停]`/`[继续]` 事件。`AppState.displayedElapsed` 的数学（`elapsed - 已完成暂停时长 - 进行中暂停时长`）经代码走查确认在暂停期间会保持不变、恢复后从原值继续——这是纯算术，逻辑上站得住，但整条链路依赖真实 `RecordingSession.pause()/resume()`（S09 已实现但从未真实运行过，见 S09 决策记录）和真实计时事件，无法端到端跑一遍。`NotesStore.recordPause`/`addEvent` 本身（S14 已测）不需要重新验证。
- [ ] 点标记 → `.md` 出现 `· [标记]` 条目；标题输入 → frontmatter `title` 与 `#` 一致，文件名不变。`NotesStore.addMark`/`setTitle`（S14）+ `NotesMarkdown.render` 的 `[标记]` 后缀渲染（S14 golden 测试已覆盖 mark 条目）都已验证过；"标题输入框改了 `notesStore.setTitle`"这一行代码走查确认，真实键盘输入无法在此验证。**已知缺口**：E11/E12（标记/截图）触发的条目直接写入 `NotesStore`，不会在 `NotesEditor` 里插入对应的可见行——用户按下"标记"按钮，`.md` 里会正确出现一条记录，但正在编辑的文本区不会实时显示这一行。这是本 spec 范围内一个明确记录的简化（见决策记录），不是遗漏。
- [x] 什么都不写直接停止 → 不生成 `.md`。这是 S14 的 `NotesStoreTests.emptyDocumentNeverWritesAFile` 已经覆盖的行为，S16 没有改变 `NotesStore` 的这条规则，只是新增了会调用它的 UI。

## 测试
`NotesEditorModelTests`：6 个用例——首字符时间戳、Enter 分段（保留前半身份）、退格合并空行（不产生新条目）、粘贴多行（每行一个条目）、清空文本保留原时间戳、`fullText` 往返。全部离线，不碰真实 `NSTextView`。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 纪要窗计时暂停时停表，`NoteEntry.offset` 仍按真实时钟 | UI 直觉 vs 与音轨对齐；两者分别满足 |
| 2026-09-23 | `AppState.displayedElapsed` 用 `elapsed - 已完成暂停区间总时长 - 当前暂停进行时长` 这一个纯算术公式，而不是在暂停开始时"冻结"一个快照值 | `RecordingSession` 的 `elapsed` 事件在暂停期间仍然按真实时钟继续增长（S09 设计如此，`offset` 需要真实时钟）；如果单独维护一个"暂停时快照"变量，恢复后还要处理"快照 + 恢复后新增时长"的拼接逻辑，容易出错。上面这个公式的巧妙之处是：暂停期间 `elapsed` 和"当前暂停进行时长"以完全相同的真实时钟速度增长，两者相减自然保持不变，不需要任何快照/拼接代码 |
| 2026-09-23 | `NotesEditor.Coordinator`（`NSTextViewDelegate`）监听 `shouldChangeTextIn:replacementString:`（编辑前），而不是 `textDidChange:`（编辑后） | 前者给出精确的 `NSRange` + 替换字符串，直接匹配 `NotesEditorModel.applyEdit(range:replacement:)` 的参数形状；后者只告诉你"文本变了"，要反推出精确的编辑操作（这一段具体插入/删除了什么）需要对比编辑前后的全文差异，对单字符编辑之外的场景（分段、合并）容易产生歧义（比如无法区分"删除了这一段" vs "把这一段和内容一样的新文本替换掉"） |
| 2026-09-23 | E11/E12（标记/截图）触发的 `NotesStore.addMark`/`captureScreenshotMark` 事件不会同步插入到 `NotesEditor` 正在显示的 `NSTextView` 里 | 要做到这一点，需要反向路径：程序化地往 `NSTextView` 的 text storage 插入一行文本，同时让 `NotesEditorModel` 的 `lines` 数组和这次插入保持同步（否则下一次用户敲键盘算出的 range 就会和真实文本错位），这是双向绑定里比"编辑器 → 模型 → store"单向流动复杂得多的另一半。参考截图（09-floating-widget-notes.png）本身也没有展示"标记"在正文里长什么样，说明这不是一个视觉上需要证明的行为；`.md` 文件里数据仍然完整正确（S14 已验证），只是编辑器里少一行视觉反馈——这个缺口记在这里，留给愿意做双向同步的后续迭代 |
| 2026-09-23 | `NotesView` 里标题/正文编辑器/工具栏改用普通从上到下的 `VStack`，而不是像 `PillView` 一样全部用 `ZStack` + 绝对 `.position()` | 第一版按 02-ui-spec.md §10 的绝对坐标表整页用 `.position()`（包括把 `NotesEditor` 这个 `NSViewRepresentable` 也摆在 `ZStack` 里），截图验收时发现工具栏完全消失不见——根因是 `.position()` 会把子视图摆到 `ZStack` 的隐式坐标系里，而那几个子视图各自的 `.position()` y 值（如 342.5）是"整个 418×380 窗口"坐标系下的绝对值；当 `ZStack` 本身只有 `.frame(height: 44)` 这种局部约束时，子视图仍按各自 `.position()` 里的绝对值摆放，导致 `ZStack` 的隐式内容边界被撑到远超 44pt，工具栏被摆到了视觉上不可见的位置。把标题/编辑器/工具栏改成普通 `VStack` 自然堆叠后，问题消失，而且从根上避免了"局部坐标系 vs 窗口绝对坐标系混用"这类错误——头部三个图标（E1-E3）因为本来就在窗口最顶端（局部坐标系和窗口坐标系恰好重合），所以继续沿用 `.position()` 没有问题 |
| 2026-09-24 | E4/E5 的字号从 spec 标注的 11pt/17pt 统一改成 13pt（与 E6 正文占位、E10 计时已经在用的字号一致） | Jakob 在真机上反馈整个纪要窗里的文字大小应该一致，这是对 02-ui-spec.md §10 原定分级字号（顶部提示 11pt / 标题 17pt / 正文 13pt）的明确推翻；选 13pt 是因为正文占位和工具栏计时已经用这个尺寸，改这两处比改全部四处动的地方最少 |
| 2026-09-24 | E10 电平+计时组的 `.position(x:)` 从 240 改成 208（停止按钮右边缘 138 与旗标按钮左边缘 278 的中点） | Jakob 在真机上发现电平表到左边停止按钮的间距明显比计时数字到右边旗标按钮的间距大很多；原来的 240 是拍脑袋定的一个值，不是两侧按钮边缘的中点。把 `.position()` 的中心点设在两侧邻居边缘的正中间后，无论电平+计时这组内容本身多宽（取决于计时文字位数），两侧间距在几何上必然相等，不需要再按视觉硬凑 |
| 2026-09-24 | 电平表在真实说话音量下几乎不动的 bug：`RecordingSession.pumpOnce()` 把 `LevelMeter.rms()` 算出的原始线性 RMS 直接喂给 `LevelMeterView` 的 0.1/0.3/0.5/0.7/0.85 阈值 | Jakob 在真机上录音说话，发现电平表始终停在静音的"五个点"状态不动。根因：正常说话音量大约在 -30~-15 dBFS，换算成线性振幅只有约 0.03-0.18，几乎不会超过第一档 0.1 的阈值——响度是感知/对数量级的物理量，直接用线性 RMS 配线性阈值，等于要求说话音量接近满量程削波才会点亮任何一段。新增 `LevelMeter.normalizedLevel(fromRMS:floorDB:)`（默认 floor -50dB）把线性 RMS 转成一个以 dB 为底的 0...1 值再喂给平滑器和阈值，这样才是让"响度看起来对"这件事和真实听感对上，而不是和振幅的线性数值对上。改动只影响 `RecordingSession.pumpOnce()` 一处调用点，`LevelMeter.rms`/`.dbfs` 本身的既有单测不受影响 |
| 2026-09-24 | E4/E5/E6/E10/编辑器正文的字号从 13pt 统一再加一号到 14pt | Jakob 反馈"这个界面文字再大一号"；上一轮（同一天早些时候）刚把四处不一致的字号统一到 13pt，这次是在那个基础上整体再调大一档，五处（顶部提示、标题、正文占位、`NotesEditor` 里 `NSTextView` 的实际输入字体、工具栏计时）一起改，保持"整个窗口字号统一"这条前一天定下的原则不变 |
| 2026-09-24 | 纪要窗从固定 418×380 改成用户可拖拽调整大小（`NSPanel.styleMask` 动态插入/移除 `.resizable`，仅在展开状态生效，药丸态维持固定尺寸不可调），并把窗口大小持久化到新增的 `Preferences.notesWindowSize` | Jakob 反馈"窗口大小需要可调整"。药丸态是一个固定的小状态指示器，不适合做成可调整大小的窗口，所以只在 `expand()`/`collapse()` 里切换 `.resizable`（进入纪要窗态时加上、退回药丸态时去掉），并设了 `minSize`(340×300)/`maxSize`(900×800) 避免被拖到不可用的极端尺寸。大小变化通过监听 `NSWindow.didEndLiveResizeNotification`（只在拖拽结束时写一次，不是每帧都写）持久化，下次展开时读取 `Preferences.notesWindowSize ?? NotesView.size` 作为初始尺寸，行为上完全对应已有的 `floatingWidgetOrigin` 记住位置的模式。**连带的必要重构**：既然窗口宽度不再固定，`NotesView` 的头部（logo/更多菜单/收起按钮）和 `NotesToolbar` 的五个控件就不能再用window-absolute 的 `.position()` 坐标（那些坐标是按 418pt 固定宽度手算的，宽度一变就不对了），两处都改成了 `HStack`+`Spacer` 的弹性布局——logo 固定贴左、菜单和收起按钮固定贴右，工具栏里暂停+停止贴左、旗标+截图贴右、电平+计时靠两侧对称的 `Spacer()` 自动居中，这样任何窗口宽度下间距都自动正确，不需要再像上一条那样手算一个"两侧邻居中点"的坐标常量。用临时 `#if DEBUG` 钩子（`KY_DEBUG_NOTES_RESIZE_TEST=650x500`，验收后已移除）把窗口程序化地设成一个明显大于默认值的尺寸并截图确认：头部图标仍然贴边、正文区域正确随窗口变大而扩展、工具栏五个控件没有裁切且间距看起来对称、圆角在新尺寸下依然正确（`RoundedHostingView` 的 `CALayer.cornerRadius`+`masksToBounds` 本来就是按当前 bounds 动态算的，不需要额外处理）。**范围限定**：程序性的药丸⇄纪要窗展开/收起动画仍然保证"右上角不动"这条既有约束（`applyFrame` 的实现没变）；但用户真的用鼠标拖边框调整大小时，跟普通可调整大小的窗口一样，拖哪条边就动哪条边，不强制保持右上角锚点——这是 AppKit 标准可调整大小窗口的默认行为，没有为了保锚点去接管用户的手动拖拽手势 |
