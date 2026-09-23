---
id: S18
title: 截屏标记
milestone: M4
status: todo
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
- [ ] 首次点 E12 → 系统屏幕录制授权弹窗；授权后（可能需重启 app，系统限制）再点 → `<baseName>/截图 HH-mm-ss.png` 出现，内容是会议窗口，不含浮窗。
- [ ] `.md` 出现 `## … · [截图]` 与 `![[<baseName>/截图 …png]]`，Obsidian / 任意 Markdown 查看器可显示。
- [ ] 手动录音（无源应用）时截前台窗口。
- [ ] 拒绝权限 → 纪要出现一条失败事件，录音不受影响。
- [ ] 未使用截图功能的录音，目录里不出现同名文件夹。

## 测试
手工为主。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
