---
id: S10
title: RecordingStore + 文件命名 + 崩溃恢复
milestone: M1
status: todo
depends_on: [S01]
estimate_days: 1
plan_refs: [§5.3, §11 "应用名做文件名"]
ui_refs: [§8 P7, §11 "最近录音为空"]
---

# S10 RecordingStore + 文件命名 + 崩溃恢复

## 目标
纯逻辑、可单测的文件命名规则，以及扫描保存目录得到"最近录音"列表、发现残留 CAF 做恢复的存储层。

## 范围
### 做
- `Storage/RecordingNaming.swift`：
  ```swift
  enum RecordingNaming {
      static func baseName(startedAt: Date, sourceApp: String, existing: Set<String>) -> String   // "2026-09-23 14-30-12 腾讯会议" / 撞名 " (2)"
      static func sanitize(_ appName: String) -> String        // / : \ ? * " < > | 与控制字符 → "-"；trim；截到 60 字符；空 → "录音"
      static func parse(_ baseName: String) -> (startedAt: Date, sourceApp: String)?
      static let manualSourceAppKey = "recording.source.manual"   // 本地化 → "手动录音" / "Manual Recording"
  }
  ```
  时间戳用固定 `yyyy-MM-dd HH-mm-ss`、当前时区、`en_US_POSIX` 日历。
- `Storage/RecordingStore.swift`（`@MainActor @Observable`）：
  - `rootDirectory: URL`（跟随 Preferences，变化时重扫）；`ensureWritable() throws`。
  - `recordings: [Recording]` 按 `startedAt` 降序；`refresh()` 扫描 `*.m4a`，配对同名 `.md`；`duration` 用 `AVURLAsset` 懒加载。
  - `recoveryCandidates: [URL]` = 目录里的 `*.caf`；`recover(_:) async throws -> URL` 调 `Encoder`。
  - `reveal(_ recording:)`, `revealRootInFinder()`, `diskUsage() async -> Int64`（与 S03 的 `SaveDirectory` 合并到这里，S03 已实现的搬过来）。
  - 用 `DispatchSource` 监听目录变化触发 `refresh()`（用户在 Finder 删文件时列表同步）。
- 启动时若 `recoveryCandidates` 非空 → alert"发现上次未完成的录音，恢复？"（恢复 / 删除 / 稍后）。
### 不做
- 纪要写入（→ S14）；列表 UI（→ S11）。

## 交付物
- `Storage/{RecordingNaming,RecordingStore}.swift`
- `KnowingYouTests/{RecordingNamingTests,RecordingStoreTests}.swift`（fixture 目录用 `FileManager.temporaryDirectory`）

## 实现要点
- 撞名检查针对 `baseName` 前缀：`.m4a` / `.caf` / `.md` / 同名文件夹任一存在都算撞。
- 应用显示名取 `Bundle(url:).localizedInfoDictionary?["CFBundleDisplayName"]` 回落 `CFBundleName`，再 `sanitize`。取名逻辑放这里，S13 调用。
- `parse` 失败的文件（用户改名过）仍列出，`sourceApp` 取文件名剩余部分，`startedAt` 取文件修改时间。

## 验收标准
- [ ] 单测覆盖：正常命名、同秒两次撞名 → ` (2)`/` (3)`、非法字符、超长名、空名、`parse` 往返。
- [ ] 目录里放 3 个 m4a（其中 1 个有同名 md、1 个改过名）→ `recordings` 3 项，排序正确，`notesURL` 配对正确。
- [ ] 目录放一个 `.caf` 启动 app → 恢复 alert 出现；选恢复 → 得到 m4a 且 caf 删除。
- [ ] Finder 里删除一个 m4a → 1 s 内 `recordings` 更新。
- [ ] 目录设为只读 → `ensureWritable()` 抛 `.saveDirectoryUnwritable`。

## 测试
见交付物。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
