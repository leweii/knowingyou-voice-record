---
id: S05
title: 权限模块 + 首次启动引导
milestone: M0
status: done
depends_on: [S02]
estimate_days: 1
plan_refs: [§6]
ui_refs: [§11 "首次启动权限引导"]
---

# S05 权限模块 + 首次启动引导

## 目标
一个统一的 `Permissions` 门面，能查询 / 请求四类 TCC 权限；首次启动弹 480×360 三步 checklist 窗口。

## 范围
### 做
- `System/Permissions.swift`：
  ```swift
  @MainActor final class Permissions: Observable {
      func status(_ p: Permission) async -> PermissionStatus   // .notDetermined / .granted / .denied
      func request(_ p: Permission) async -> PermissionStatus
      func openSystemSettings(for p: Permission)              // x-apple.systempreferences: 深链
      var systemAudioProbe: (@Sendable () async -> PermissionStatus)?   // 由 S08 注入
  }
  ```
  - 麦克风：`AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess`。
  - 系统音频录制：无公开查询 API；通过 `systemAudioProbe`（S08 实现：尝试建 tap）判定；S05 阶段未注入时返回 `.notDetermined`。
  - 通知：`UNUserNotificationCenter` 授权状态 / 请求（`.alert, .sound`）。
  - 屏幕录制：`CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`。
- `UI/Onboarding/OnboardingWindow.swift`：三步（麦克风 / 系统音频录制 / 通知），每行右侧 `OutlinedButton("去授权")`，完成变 `checkmark` 绿；底部"完成"按钮；关闭写 `hasCompletedOnboarding = true`。
- 首次启动（`hasCompletedOnboarding == false`）自动弹；从状态栏菜单"Debug › 重新引导"可重开（DEBUG）。
### 不做
- 屏幕录制引导（→ S18 首次点截图时按需请求）。

## 交付物
- `System/Permissions.swift`、`UI/Onboarding/OnboardingWindow.swift`、`UI/Onboarding/OnboardingView.swift`

## 实现要点
- 权限状态在窗口 `becomeKey` 与 `NSApplication.didBecomeActiveNotification` 时刷新（用户从系统设置切回来）。
- 引导窗口用 `NSWindow`（非 panel），居中，`activate(ignoringOtherApps:)`，否则 LSUIElement app 的窗口不会前置。
- 系统音频那一步在 S08 前显示"稍后在首次录音时申请"灰字，不阻塞完成。

## 验收标准
- [x] 删掉 `hasCompletedOnboarding` 后启动，引导窗口出现并前置。（`defaults delete com.jakobhe.knowingyou hasCompletedOnboarding` 后 `open` app，截图确认窗口出现并前置，标题"首次启动"）
- [~] 点"去授权"出现系统麦克风 / 通知授权弹窗；授权后行内变对勾（无需重开窗口）。**未做真实点击验证**（会触发真实系统授权弹窗，不适合在这台共享机器上盲点）。代码走查：`request(_:)` 调用系统 API 后返回值直接写回 `@State`，SwiftUI 会自动重渲染成对勾，不需要重开窗口。
- [~] 用户拒绝后按钮变"打开系统设置"，点击跳到对应隐私面板。**未做真实点击验证**。`systemSettingsURL(for:)` 的 URL 格式经过单元测试（4/4 通过）；"跳到对应隐私面板"这一步的锚点名称（尤其是系统音频录制用的 `Privacy_ScreenCapture`）是猜测值，没有在真机 System Settings 里点开确认过锚点真的存在/命中正确分区，标进决策记录了。
- [x] 窗口尺寸 480×360，视觉与设置页同一套控件。（截图确认尺寸与布局；行内用的是 `SettingsRow`/`OutlinedButton`，与设置页共享同一套 DesignSystem 组件）

## 测试
手工为主；`PermissionsTests` 只测 `openSystemSettings` 生成的 URL 字符串。4/4 通过，全套 28/28 通过。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | "系统音频录制"和"屏幕录制"共用 `Privacy_ScreenCapture` 这个系统设置锚点 | 现代 macOS 把这两者放进同一个"屏幕与系统音频录制"面板；没有公开文档确认锚点字符串，是猜测值，真机验证前不要假设它一定跳得对 |
| 2026-09-23 | `openSystemSettings` 拆成 `systemSettingsURL(for:)`（纯函数，`nonisolated static`）+ 一个调 `NSWorkspace` 的薄包装 | 让 URL 生成逻辑不依赖 MainActor、可以直接单测，不用起 UI |
