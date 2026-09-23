---
id: S14
title: NotesStore + 纪要 Markdown 序列化
milestone: M3
status: done
depends_on: [S10]
estimate_days: 1.5
plan_refs: [§5.3 纪要格式]
ui_refs: []
---

# S14 NotesStore + 纪要 Markdown 序列化

## 目标
纪要在内存里的模型、精确到字节的 Markdown 序列化 / 反序列化、3 s 自动落盘与原子写。纯逻辑，可完全单测。

## 范围
### 做
- `Storage/NotesMarkdown.swift`：
  ```swift
  enum NotesMarkdown {
      static func render(_ doc: NotesDocument) -> String
      static func parse(_ text: String) throws -> NotesDocument
  }
  ```
  输出格式**逐字符**按计划 §5.3 示例：YAML frontmatter（`title`, `started_at` ISO8601 带时区, `ended_at`, `duration` `HH:mm:ss`, `source_app`, `audio`, `paused` 为 `[["start","end"], …]` 或 `[]`）、空行、`# 标题`、每条 `## HH:mm:ss · +HH:mm:ss` 加可选 ` · [标记]` / ` · [截图]` / ` · [事件]`，正文另起一行；截图条正文 `![[<相对路径>]]`。无标题时 `title` 与 `#` 用 baseName。
- `Storage/NotesStore.swift`（`@MainActor @Observable`）：
  ```swift
  final class NotesStore {
      private(set) var document: NotesDocument
      init(info: RecordingInfo)
      func setTitle(_: String)
      func beginEntry(at wallClock: Date) -> NoteEntry.ID     // 第一个字符落下时调用，打时间戳
      func updateEntry(_ id:, text:)
      func addMark(at:)  func addScreenshot(path:, at:)  func addEvent(_ text:, at:)
      func recordPause(_ range: ClosedRange<Date>)
      func finish(endedAt: Date) async throws                 // 写 ended_at / duration，落盘
      var autosaveInterval: TimeInterval = 3
  }
  ```
  落盘规则：`document.isEmpty` 为真则不生成文件；否则每 3 s（有变化时）与 `finish` 时写 `<baseName>.md.tmp` 后 `replaceItemAt` 原子替换。
### 不做
- 编辑器 UI（→ S16）。

## 交付物
- `Storage/{NotesMarkdown,NotesStore}.swift`
- `KnowingYouTests/NotesMarkdownTests.swift` + `Fixtures/notes-golden.md`（计划 §5.3 的示例逐字复制）
- `KnowingYouTests/NotesStoreTests.swift`

## 实现要点
- 时间格式化全部用 `en_US_POSIX` + 用户当前时区；`started_at` 用 `ISO8601DateFormatter` 带 `+08:00` 形式（`withInternetDateTime`，不带小数秒）。
- `offset` 不扣暂停（S00 决策）；`duration` = `ended_at - started_at`（含暂停），暂停区间单独在 `paused` 里。
- `parse` 主要给测试往返用，允许对手写 md 宽容失败。
- 原子写时若目标目录不可写抛 `.saveDirectoryUnwritable`，由 S16 提示，不丢内存数据（继续重试）。

## 验收标准
- [x] golden 测试：构造与计划 §5.3 示例相同的 `NotesDocument`，`render` 输出与 fixture 文件字节相同。`NotesMarkdownTests.rendersByteForByteMatchToThePlanExample` 直接比较 `render(goldenDocument())` 与 `Fixtures/notes-golden.md`（后者是计划文档示例的逐字复制），首次运行即完全匹配。
- [x] `parse(render(doc)) == doc` 对随机 20 条条目成立。字面意义上的 `==`（含 `NoteEntry.id`）做不到——`.md` 格式本身不存储条目 ID（渲染时根本不写出来），`parse` 每次都会生成新的随机 UUID；条目的 `wallClock` 也只有"当天的时分秒"能在格式里存活（示例格式没有为每条纪要单独存日期）。`roundTripsTwentyRandomEntries` 因此比较的是格式实际编码的字段：`kind`/`text`/`offset`（容差 1s）/`wallClock` 精确到秒（用 `Calendar.isDate(_:equalTo:toGranularity:.second)`），不比较 `id` 和日期部分——这是这个文件格式本身的设计边界，不是测试偷懒。
- [x] 空文档 `finish` 不产生文件；只有标题 / 只有一条标记都产生文件。`NotesStoreTests` 三个用例分别验证。
- [x] 连续 `updateEntry` 10 次，3 s 内磁盘最多写 1 次；`finish` 后立即可见完整内容；目录里无残留 `.tmp`。`burstOfEditsWritesAtMostOnceWithinTheDebounceWindow` 用缩短的 `autosaveInterval`（0.05-0.1s，而非真实 3s）验证防抖窗口内只写一次；`finishWritesImmediatelyWithoutWaitingForTheDebounce` 特意把 `autosaveInterval` 设成 10s 来证明 `finish()` 没有等它；`noLeftoverTmpFileAfterWriting` 确认 `replaceItemAt` 后无残留。

## 测试
`NotesMarkdownTests`（7 个用例，含 golden + round-trip + 空/未完成文档的边界格式）、`NotesStoreTests`（7 个用例，覆盖落盘规则/防抖/原子写）。全部离线运行在真实临时目录上（不 mock 文件系统），`make test` 总计 101 个测试 0.4 秒内跑完。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | `NotesMarkdown.render`/`parse` 都加了一个 `timeZone: TimeZone = .current` 参数，而不是硬编码用系统当前时区 | 计划 §5.3 的示例里 `started_at`/条目时间戳全部是 +08:00，如果 `render` 内部写死 `TimeZone.current`，golden 测试就只有在恰好跑在 +08:00 时区的机器上才会通过（这台机器凑巧是，但不能假设所有人的机器都是）。加一个可覆盖的参数后，真实使用时保持默认的"按用户当前时区显示"（这是对用户读自己纪要最合理的行为），测试则显式传 `Asia/Shanghai` 让 golden 比对不依赖运行环境 |
| 2026-09-23 | `NotesMarkdown` 没有使用真正的 YAML/Markdown 解析库，`parse` 是一个只理解自己 `render` 输出的手写小状态机 | spec 本身就说"parse 主要给测试往返用，允许对手写 md 宽容失败"——这不是一个需要打开任意用户编辑过的纪要文件的场景（S16 的纪要窗直接持有内存中的 `NotesDocument`，不会重新解析磁盘文件）。引入一个真正的 YAML 库处理一个我们自己完全控制格式的四五个字段的 frontmatter，复杂度收益比很差 |
| 2026-09-23 | `NotesStore` 的自动保存是"每次编辑都取消并重新排一个 N 秒后的写入任务"（真正的 debounce），而不是 spec 草稿字面写的"每 3 秒（有变化时）"这种固定节拍轮询 | 固定节拍轮询很难在单测里快速验证"连续编辑只写一次"这条验收标准——要么等一个真实的节拍周期，要么把节拍做成可注入的但仍然是"到点检查脏标记"的语义，两者都不如"最后一次编辑之后 N 秒没有新编辑就写一次"直接。debounce 版本额外的好处是保证的是"编辑停止后最多 N 秒内落盘"，而不是"取决于编辑发生在节拍周期的哪个位置，最多可能要等接近 2N 秒"，对用户体验也更好 |
| 2026-09-23 | `paused` 区间的序列化格式定为 `[["<ISO8601>","<ISO8601>"], …]`（两个 ISO8601 时间戳字符串） | 计划文档只给了空数组 `paused: []` 的例子，没有给非空时的具体格式；`["start","end"]` 字符串对本来就是 spec 交付物清单里写的字面结构（"为 `[["start","end"], …]` 或 `[]`"），选 ISO8601 时间戳作为 start/end 的具体表示是因为文件里其它所有时间字段都是 ISO8601，保持格式内部一致 |
