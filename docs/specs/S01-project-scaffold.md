---
id: S01
title: Xcode 工程脚手架与构建命令
milestone: M0
status: done
depends_on: [S00]
estimate_days: 1.5
plan_refs: [§1, §3, §6, §8]
ui_refs: []
---

# S01 Xcode 工程脚手架与构建命令

## 目标
一个能从命令行 `make build` / `make test` / `make run` 的 Swift 6 菜单栏 App 骨架，启动后只在菜单栏出现一个占位图标和"退出"菜单。之后所有 spec 都在这个骨架上加东西。

## 范围
### 做
- 用 **XcodeGen**（`project.yml`）描述工程，`KnowingYou.xcodeproj` 进 `.gitignore`；`make gen` 生成。
- 两个 target：`KnowingYou`（app）、`KnowingYouTests`（Swift Testing）。
- 构建设置：`SWIFT_VERSION = 6.0`，`SWIFT_STRICT_CONCURRENCY = complete`，`MACOSX_DEPLOYMENT_TARGET = 14.4`，`ARCHS = arm64`，`ENABLE_HARDENED_RUNTIME = YES`，**不启用** App Sandbox，`PRODUCT_BUNDLE_IDENTIFIER = com.jakobhe.knowingyou`，`MARKETING_VERSION = 1.0.0`。
- Info.plist：`LSUIElement = YES`、`NSMicrophoneUsageDescription`、`NSAudioCaptureUsageDescription`（手填）、`NSScreenCaptureUsageDescription`、`KYIsPrerelease`（Bool，控制关于页 Beta 胶囊）、`KYGitHubURL`、`KYReleasesURL`、`KYFeedbackEmail`（占位）。
- Entitlements：`com.apple.security.device.audio-input`。
- SPM 依赖：`sindresorhus/KeyboardShortcuts`。
- 目录骨架按 `CLAUDE.md` 的模块布局建好（空文件夹放 `.gitkeep` 或首个文件）。
- `Support/Contracts.swift`（S00）、`Support/Preferences.swift`（键表 + 默认值）、`Support/Logger.swift`（`Logger` 工厂）。
- `App/KnowingYouApp.swift`（`@main`，AppKit `NSApplicationDelegateAdaptor`）、`App/AppDelegate.swift`（建 `NSStatusItem` 占位 + 菜单：偏好设置（暂无操作）、退出）、`App/AppState.swift`（`@MainActor @Observable`，先只有 `phase: AppPhase = .idle`）。
- `Resources/Localizable.xcstrings`，源语言 zh-Hans，加 en。
- `Makefile`：`gen`、`build`（`xcodebuild -quiet -scheme KnowingYou -configuration Debug build`）、`test`（`xcodebuild test -scheme KnowingYou -destination 'platform=macOS'`）、`run`（build 后 `open` 产物）、`clean`。
- `scripts/check-no-network.sh`：对 `KnowingYou/` grep `URLSession|NWConnection|Network\.framework|import Network|CFNetwork|NSURLConnection|WKWebView`，命中即退出 1；`make build` 前置调用。
- `.gitignore`（xcuserdata、DerivedData、`*.xcodeproj`、`.build`）。
- 更新 `CLAUDE.md`："项目状态"改写，新增"常用命令"一节。
### 不做
- 任何真实 UI（→ S02+）、任何音频代码（→ S07/S08）。

## 交付物
- `project.yml`、`Makefile`、`scripts/check-no-network.sh`、`.gitignore`
- `KnowingYou/App/*.swift`、`KnowingYou/Support/{Contracts,Preferences,Logger}.swift`
- `KnowingYou/Resources/{Info.plist,KnowingYou.entitlements,Localizable.xcstrings}`
- `KnowingYouTests/PreferencesTests.swift`（一个测默认值的测试，证明测试链路通）
- `CLAUDE.md` 更新

## 实现要点
- `LSUIElement = YES` 与 `showDockIcon` 开关配合：启动时若偏好为 true，`NSApp.setActivationPolicy(.regular)`。
- Preferences 不要把 `UserDefaults` 键名散落各处；用一个 `enum Key: String` 集中。
- strict concurrency 下 `AppDelegate` 标 `@MainActor`；`NSStatusItem` 只在主线程碰。
- `make test` 在没有已签名开发者身份的机器上也要能跑：`CODE_SIGN_IDENTITY=-`（ad-hoc）用于 Debug。

## 验收标准
- [x] 干净 clone 后 `brew install xcodegen && make gen && make build` 成功，零 warning。（验证：本机 Xcode 27 / Swift 6.4，`xcodebuild build` 无 warning/error，仅有无关的 `appintentsmetadataprocessor` 工具提示）
- [x] `make test` 通过。（`PreferencesTests` 6/6 通过）
- [x] `make run` 后菜单栏出现图标，Dock 无图标，菜单"退出"可退出。（验证：`open` 产物后 `System Events` 报告该进程 `background only = true`；`pkill -x KnowingYou` 后进程干净退出，未验证部分：未用辅助功能 API 逐像素确认菜单项文字，因终端未开辅助功能权限——下次有 UI 交互需求时应一并开启）
- [x] `scripts/check-no-network.sh` 对当前代码返回 0；在临时文件里写一行 `URLSession.shared` 会让它返回 1。（两种情况均已实测）
- [x] `plutil -p` 产物 Info.plist 能看到三条 Usage Description 与 `LSUIElement`。（已用 `plutil -p` 核对，另外确认了 KYIsPrerelease/KYGitHubURL/KYReleasesURL/KYFeedbackEmail 也都在）
- [x] `CLAUDE.md` 有"常用命令"，且"项目状态"不再说"没有代码"。

## 测试
`PreferencesTests`：所有键的默认值与 S00 表一致。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 用 XcodeGen 而不是手改 pbxproj | Claude Code 编辑 YAML 可靠，pbxproj 合并冲突多 |
| 2026-09-23 | 不引入 SwiftLint / SwiftFormat | 先靠编译器 strict concurrency 与 review；需要时另开 spec |
| 2026-09-23 | `KnowingYouTests` target单独设 `GENERATE_INFOPLIST_FILE: YES` | 项目级默认 `NO`（app target 用手写 Info.plist）；测试 bundle 没有自己的 plist 会导致 codesign 报错，测试目标用自动生成即可，不需要手写 |
| 2026-09-23 | `KYFeedbackEmail` 占位值用 `feedback@example.invalid` | `.invalid` 是 RFC 2606 保留 TLD，占位值不可能被误当成真实地址发出邮件；S19/S21 检查"非占位值"时按域名 `.invalid` 判断 |
