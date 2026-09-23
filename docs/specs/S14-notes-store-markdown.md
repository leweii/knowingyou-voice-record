---
id: S14
title: NotesStore + 纪要 Markdown 序列化
milestone: M3
status: todo
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
- [ ] golden 测试：构造与计划 §5.3 示例相同的 `NotesDocument`，`render` 输出与 fixture 文件字节相同。
- [ ] `parse(render(doc)) == doc` 对随机 20 条条目成立。
- [ ] 空文档 `finish` 不产生文件；只有标题 / 只有一条标记都产生文件。
- [ ] 连续 `updateEntry` 10 次，3 s 内磁盘最多写 1 次；`finish` 后立即可见完整内容；目录里无残留 `.tmp`。

## 测试
见交付物。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
