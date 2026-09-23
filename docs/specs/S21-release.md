---
id: S21
title: 签名、公证、DMG、发布检查
milestone: M5
status: todo
depends_on: [S20, S19]
estimate_days: 2.5
plan_refs: [§1 分发, §3 分发, §5.7, §9 M5]
ui_refs: []
---

# S21 签名、公证、DMG、发布检查

## 目标
一条命令产出已签名、已公证、已 staple 的 DMG；在干净 Mac 上首次安装跑通全流程；用 Little Snitch 证明零网络连接；GitHub Release 草稿就位。

## 范围
### 做
- `scripts/sign-and-notarize.sh`：Release 构建（`xcodebuild archive` + `exportArchive`，Developer ID Application）→ `codesign --verify --deep --strict` → `notarytool submit --wait`（凭据用 keychain profile，脚本参数传 profile 名）→ `stapler staple` → `spctl -a -vv` 验证。
- `scripts/make-dmg.sh`：`hdiutil` 或 `create-dmg`，含 `Applications` 软链与背景；对 DMG 也签名 + 公证 + staple；输出 `KnowingYou-<version>-arm64.dmg` 与 `SHA256SUMS`。
- `make release VERSION=x.y.z`：校验 `project.yml` 版本一致、`KYFeedbackEmail` 已填（非占位值）、`DesignSystem/Brand.swift` 不再引用占位 `waveform.circle`（真实 logo 已接入）、`KYIsPrerelease` 与版本号 pre-release 标记一致、`check-no-network.sh` / `check-l10n.sh` 通过、`git tag`。这两项占位（反馈邮箱、Logo）是计划 §12 第 5、11 条明确要求发布前必须替换的，此处做成硬阻断而非提醒。
- 首次启动体验检查清单（写进 `docs/testing/release-checklist.md`）：Gatekeeper 无警告 → 引导窗口 → 授权 → 手动录一段 → 自动检测一段 → 文件与纪要正确 → 卸载（拖到废纸篓）后无残留服务（`SMAppService` 已注销）。
- 零网络验证：Little Snitch（或 `nettop -p <pid>` 观察 10 分钟含一次完整录音）无任何连接；结果截图放 `docs/testing/`。
- `README.md` 改成用户向：下载、安装、权限、文件位置、隐私声明、从源码构建；GitHub Release 草稿含 changelog 与 SHA256。
### 不做
- 自动更新（Sparkle）；Intel 构建；App Store。

## 交付物
- `scripts/{sign-and-notarize,make-dmg}.sh`、`Makefile` 新增 `release`
- `docs/testing/release-checklist.md`（含执行记录）、零网络验证截图
- `README.md` 重写

## 实现要点
- Hardened Runtime 下需要 entitlement `com.apple.security.device.audio-input`；不要加 `disable-library-validation`。
- 公证失败最常见原因：SPM 依赖的 bundle 未签名 → `--deep` 或 `xcodebuild` 自动签名设置检查。
- `SMAppService` 在 DMG 里直接运行会失败，清单里强调"先拖进 Applications"。
- Release 配置的 `CODE_SIGN_IDENTITY` 由脚本环境变量传入，仓库不写死身份。

## 验收标准
- [ ] 干净用户账户（或另一台 Mac）下载 DMG → 安装 → 首次启动无 Gatekeeper 拦截 → 按清单跑通全部步骤。
- [ ] `spctl -a -vv KnowingYou.app` 输出 `accepted … Notarized Developer ID`。
- [ ] 零网络验证结果记录在案。
- [ ] `make release` 在任一前置检查失败时中止且不打 tag。
- [ ] `CLAUDE.md` 增加发布命令与注意事项。

## 测试
见清单。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
