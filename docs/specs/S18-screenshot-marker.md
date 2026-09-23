---
id: S18
title: 截屏标记
milestone: M4
status: done
depends_on: [S16, S05]
estimate_days: 1
plan_refs: [§3 "截屏标记", §5.3, §6, §11]
ui_refs: [§10 E12, §5 K3]
---

# S18 截屏标记

## 目标
按钮或快捷键截取会议应用最前窗口为 PNG，存到录音同名子文件夹，并在纪要插入一条 `[截图]`。首次使用时才申请屏幕录制权限。

## 范围
### 做
- `System/ScreenshotMarker.swift`：
  ```swift
  actor ScreenshotMarker {
      func capture(for info: RecordingInfo, sourceBundleIDPrefix: String?, at wallClock: Date) async throws -> String   // 返回相对路径 "<baseName>/截图 HH-mm-ss.png"
  }
  ```
  流程：`Permissions.status(.screenRecording)` 非 granted → `request` → 仍拒绝抛 `.permissionDenied(.screenRecording)`；`SCShareableContent.current` → 找 `owningApplication.bundleIdentifier` 前缀匹配 `sourceBundleIDPrefix` 的、`onScreen` 且 `windowLayer == 0` 且面积最大的窗口；无匹配（手动录音）→ 前台 App 的最前窗口；`SCScreenshotManager.captureImage(contentFilter:configuration:)` 2x 缩放；写 PNG 到 `info.assetsDir`（不存在则建）；文件名 `截图 HH-mm-ss.png`（本地化 key）。
- `AppState.captureScreenshotMark()`：非录音态忽略；成功 → `NotesStore.addScreenshot(path:at:)`；失败 → `addEvent("截图失败：…")` + 浮窗短暂提示（E12 图标变红 1 s）。
- 首次触发权限：拒绝后 alert 带"打开系统设置"，并说明"截图为可选功能"。
### 不做
- 区域选择 / 全屏截图。

## 交付物
- `System/ScreenshotMarker.swift`；`AppState` 扩展

## 实现要点
- `SCShareableContent` 需要屏幕录制权限，未授权时返回空列表而非报错，所以先查 `CGPreflightScreenCaptureAccess`。
- 排除自身窗口（浮窗）：过滤 `owningApplication.processID == getpid()`。
- 截图 PNG 用 `CGImageDestination`，不要经过 `NSImage` 的 TIFF。

## 验收标准
- [ ] 首次点 E12 → 系统屏幕录制授权弹窗；授权后（可能需重启 app，系统限制）再点 → `<baseName>/截图 HH-mm-ss.png` 出现，内容是会议窗口，不含浮窗。**无法验证**：屏幕录制权限和麦克风一样，在这台机器上触发时大概率会把 TCC 身份归给宿主 "Air" 进程而不是 KnowingYou（S07 记录的同一类问题，虽然没有专门针对屏幕录制重新测一次，但没有理由认为它会不一样）；`ScreenCaptureKit` 的整条链路（`SCShareableContent.current` → 窗口筛选 → `SCScreenshotManager.captureImage`）因此完全无法在这台机器上跑一遍。`ScreenshotMarker.selectWindow(from:sourceBundleIDPrefix:)` 的筛选/排序逻辑本身经代码走查确认（过滤自身进程、`onScreen`、`windowLayer == 0`，用 `CGWindowListCopyWindowInfo` 的真实 z-order 而不是 `SCShareableContent.windows` 数组本身的顺序），但 `SCWindow` 没有公开构造器，没法像 `ProcessObjectReading` 那样注入假数据做单测——这是 ScreenCaptureKit 这套 API 本身的限制，不是设计选择。
- [ ] `.md` 出现 `## … · [截图]` 与 `![[<baseName>/截图 …png]]`，Obsidian / 任意 Markdown 查看器可显示。渲染格式本身（`[截图]` 后缀、`![[...]]` embed 语法）是 S14 `NotesMarkdown` 已经用 golden fixture 验证过的行为，S18 只是新增了调用 `NotesStore.addScreenshot(path:at:)` 的真实截图路径——这条路径本身依赖上一条已经说明无法验证的真实截图。
- [ ] 手动录音（无源应用）时截前台窗口。`selectWindow` 在 `sourceBundleIDPrefix == nil` 时直接落到"整体最前窗口"分支，代码走查确认；无法运行验证（同上）。
- [ ] 拒绝权限 → 纪要出现一条失败事件，录音不受影响。`AppState.captureScreenshotMark()` 用 `do/catch` 包住整个截图流程，失败只调用 `notesStore?.addEvent("截图失败：...")`，不touch `phase`/`session`——结构上录音确实不会受影响；`describeScreenshotFailure` 对 `KYError.permissionDenied`/`ScreenshotMarker.CaptureError.noMatchingWindow` 给出人话文案，其余错误退化为 `"\(error)"`。代码走查确认，运行时无法验证。
- [x] 未使用截图功能的录音，目录里不出现同名文件夹。`info.assetsDir` 只在 `ScreenshotMarker.capture(for:sourceBundleIDPrefix:at:)` 内部被 `FileManager.default.createDirectory` 创建，这个方法只有 `captureScreenshotMark()` 被调用时才会执行；没有任何其它代码路径会创建这个目录，结构上保证了这条标准，且这条不依赖真实截图权限——是唯一一条能给 `[x]` 的验收标准。

## 测试
手工为主（spec 本身就这么写的）；没有新增自动化测试——`ScreenshotMarker` 依赖的 `SCWindow`/`SCShareableContent` 都是 ScreenCaptureKit 系统直接创建的不透明类型，没有公开构造器，无法像 `MeetingDetector`/`ProcessObjectReading` 那样注入假数据。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 用 `SCStreamConfiguration`（而不是文档示例常见的 `SCScreenshotConfiguration`）配置 `SCScreenshotManager.captureImage(contentFilter:configuration:)` | 写代码时才发现 `SCScreenshotConfiguration` 是 macOS 26 才有的新类型，这个项目的部署目标是 14.4；`SCScreenshotManager.captureImage` 这个方法本身自 14.0 起就存在，只是早期版本的签名接受的是通用的 `SCStreamConfiguration`（本来是给连续流媒体用的配置类型，截图场景复用了它） |
| 2026-09-23 | 用 `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` 取真实的窗口 z-order，而不是直接假设 `SCShareableContent.windows` 数组的顺序就是前后顺序 | 查过 `SCWindow`/`SCShareableContent` 的文档和实际类型定义，没有找到任何"这个数组按 z-order 排序"的保证；`CGWindowListCopyWindowInfo` 用 `kCGWindowListOptionOnScreenOnly` 选项时官方文档明确说明返回顺序就是前后叠放顺序。两边都用 `CGWindowID` 标识同一个窗口，可以互相对照 |
| 2026-09-23 | 顺带修复了 S13 遗留的一个 bug：`AppState.resolveManualRecordingSourceApp` 这个闭包属性从 S11 就声明了，但 `MeetingCoordinator`（S13 引入）从来没有真的赋值给它——`MeetingRecordingControlling` 协议里压根没有声明这个属性，所以协调器拿到的窄接口类型根本不可能设置它。结果是"手动开始录音时，如果有白名单应用正在说话，用它的名字"这条 S13 就该有的行为，实际上从来没生效过，一直退化到"手动录音"这个默认值 | 这次要给 `RecordingInfo` 加 `sourceBundleIDPrefix` 字段，顺手需要给"手动开始录音时解析源应用"这条路径也把 bundle id 传过去，检查现有实现时才发现这个属性根本没人赋值。既然发现了，就在 S18 里一并修：把这个属性加进 `MeetingRecordingControlling` 协议，`MeetingCoordinator.start()` 里用 `detector.snapshot()` 真正实现它。这类"发现前一个 spec 遗留的真实 bug"的情况，比起假装没看见、留到 S20 边界测试阶段才发现，当场修掉更诚实也更省事——尤其是这次改动本来就要碰这几个文件 |
