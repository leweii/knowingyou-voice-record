---
id: S10
title: RecordingStore + 文件命名 + 崩溃恢复
milestone: M1
status: done
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
- [x] 单测覆盖：正常命名、同秒两次撞名 → ` (2)`/` (3)`、非法字符、超长名、空名、`parse` 往返。（`RecordingNamingTests` 全覆盖，9 个测试）
- [x] 目录里放 3 个 m4a（其中 1 个有同名 md、1 个改过名）→ `recordings` 3 项，排序正确，`notesURL` 配对正确。（`RecordingStoreTests.scansAndPairsNotesFiles`）
- [x] 目录放一个 `.caf` 启动 app → 得到 m4a 且 caf 删除。（自动化验证了核心链路：`recoverTranscodesLeftoverCAFAndDeletesIt` 用真实合成的 CAF 走完整个 `recover()`，产出可用 m4a）。**"恢复 alert 出现"这一步未做真实点击验证**——`AppDelegate.checkForRecoverableRecordings()` 里的 `NSAlert.runModal()` 三个按钮走查无误，但没有实际启动 app 点过"恢复/删除/稍后"（会阻塞式弹窗，不适合在这台共享机器上盲测）。
- [~] Finder 里删除一个 m4a → 1 s 内 `recordings` 更新。**未做真实验证**——`DispatchSource` 监听目录变化的写法是标准模式，但没有实际去 Finder 删文件观察时延；单元测试里 `watchFileSystem: false` 特意跳过了这条（避免测试依赖真实文件系统事件时序）。
- [x] 目录设为只读 → `ensureWritable()` 抛 `.saveDirectoryUnwritable`。（`ensureWritableThrowsForReadOnlyDirectory`，用 `chmod 555` 真实验证）

## 测试
`RecordingNamingTests`（9 项）+ `RecordingStoreTests`（4 项，含一次真实 CAF→m4a 转码往返）。全套 42/42 通过，重复跑 3 次无 flaky。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 把 `Recording/Encoder.swift` 从 S09 提前搬到这里实现 | `RecordingStore.recover()` 必须能把残留的 `.caf` 转成 `.m4a`，而 S09 的 `RecordingSession`/`Mixer` 还没做；`Encoder` 是纯粹的"读 CAF 写 AAC m4a"逻辑，跟混音/录制会话无关，先做出来不影响 S09 后续只需要复用它 |
| 2026-09-23 | `SaveDirectory.swift`（S03）保留不动，`RecordingStore` 只是调用它，不是"搬过去删掉原文件" | spec 原话"与 S03 的 SaveDirectory 合并到这里"如果字面理解成删除重建，会连带影响已经上线的 `GeneralSettingsView`（S03）。保留 `SaveDirectory` 作为底层工具、`RecordingStore` 作为录音域的调用方，功能上等价于"合并"（新代码都通过 `RecordingStore` 走），但不用碰已验证过的 S03 代码 |
| 2026-09-23 | `RecordingStore` 用 `UserDefaults.didChangeNotification` 观察 `Preferences.shared.saveDirectoryPath` 变化，而不是让 G9 的"更改…"按钮显式通知它 | 这样"跟随 Preferences"是真正自动的，不用往 S03 已经写好的 `GeneralSettingsView.chooseDirectory()` 里加一行调用；代价是回调会在任何 UserDefaults 变化时触发，用路径比对做了去重，足够便宜 |
| 2026-09-23 | 测试里踩到 `/var` → `/private/var` 符号链接坑：`FileManager.default.temporaryDirectory` 返回 `/var/...`，但 `contentsOfDirectory` 会解析成 `/private/var/...`，导致同一个文件的两个 `URL` 用 `==`/`.path` 比较会判不相等 | `resolvingSymlinksInPath()` 在这台机器上对该路径不生效（原因不明，可能是这个沙盒环境的怪癖），试了"建目录前解析"和"建目录后解析"都没用；最终对策是测试断言改成比 `baseName`／`lastPathComponent`，不比较完整路径字符串——这类"两个 URL 指向同一文件但字符串不相等"的情况以后写测试要留意，别默认 `URL ==` 就等价于"同一个文件" |
