---
id: S21
title: 签名、公证、DMG、发布检查
milestone: M5
status: done
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
- [ ] 干净用户账户（或另一台 Mac）下载 DMG → 安装 → 首次启动无 Gatekeeper 拦截 → 按清单跑通全部步骤。**未执行**——这台开发机没有 Developer ID 签名证书，无法产出一个真实签过名/公证过的 DMG，也没有另一台干净的 Mac 可用。清单本身已经写好（`docs/testing/release-checklist.md`），留给 Jakob 配好凭证后执行。
- [ ] `spctl -a -vv KnowingYou.app` 输出 `accepted … Notarized Developer ID`。**未执行**——同上，没有真实证书/notarytool 凭证。
- [x] 零网络验证结果记录在案（部分）。没有 Little Snitch，改用系统自带的 `nettop -p <pid>` + `lsof -p <pid> -i`，对 Release 构建、空闲状态下的进程做了一次真实运行时验证：90 秒观察窗口内零 TCP/UDP 连接，进程不持有任何网络类文件描述符，与 `scripts/check-no-network.sh` 的源码静态扫描结论互相印证。方法与结果见 `docs/testing/network-verification.md`。**范围限制**：只覆盖空闲态，不包含真实录音全流程（麦克风 tap 实际工作时）——这台环境的麦克风 TCC 权限归因问题导致无法在这里触发一次真正的端到端录音，这部分留给 Jakob 在自己机器上补充。
- [x] `make release` 在任一前置检查失败时中止且不打 tag。**已验证**：`make release VERSION=1.0.0` 在 `check-release-readiness.sh` 阶段正确报出三条真实存在的问题（反馈邮箱占位、logo 占位、`KYIsPrerelease` 与版本号不一致）并以非零退出码中止，`git tag` 确认没有产生任何 tag。
- [x] `CLAUDE.md` 增加发布命令与注意事项。

## 测试
见清单（`docs/testing/release-checklist.md`）。三个新脚本（`check-release-readiness.sh`/`sign-and-notarize.sh`/`make-dmg.sh`）均用 `sh -n` 做过语法检查；`check-release-readiness.sh` 的三条检查分支各用不同版本号（`1.0.0`/`1.0.0-beta.1`/`2.0.0`）手动触发过一次，确认版本匹配、占位符检测、pre-release 标记一致性三条逻辑都按预期工作。`sign-and-notarize.sh`/`make-dmg.sh` 的实际执行路径（真实签名与公证）无法在此环境验证——见下方决策记录。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | S21 的产出定位为"把发布流水线的脚本和硬阻断检查做完、跑通到卡在需要真实凭证为止"，而不是尝试用占位/伪造凭证走完整流程 | 签名身份、notarytool 凭证、真实反馈邮箱、logo 设计资源都是需要 Jakob 本人提供的账号凭证或产品资产，编造假值（比如随便填一个签名身份或邮箱）只会制造一个看起来"通过"但实际上毫无意义甚至误导的结果；如实标注"脚本已就绪，等凭证"比假装完成更有价值 |
| 2026-09-23 | `make-dmg.sh` 用系统自带的 `hdiutil` 而不是 `create-dmg`（spec 里两者都提到） | `hdiutil` 不需要额外的 Homebrew 依赖，`make release` 这条关键路径少一个外部工具意味着少一个"用户机器上没装"的失败点；背景图/自定义窗口布局这类视觉打磨可以后续再加，不阻塞发布流水线本身能不能跑通 |
| 2026-09-23 | 签名身份/团队 ID/notarytool profile 名一律通过环境变量传入脚本，不写进 `project.yml` 或任何仓库文件 | spec"实现要点"明确要求身份不写死；这也符合"仓库是公开的，账号凭证不该出现在任何提交历史里"的一般原则 |
| 2026-09-23 | `git tag` 只在本地打，`make release` 不自动 `git push` | 打 tag 是本地、可撤销的操作；push 一个 tag（尤其是触发 CI/Release 流程的 tag）是对外可见、影响共享状态的动作，应该由 Jakob 自己在确认一切就绪后手动执行，而不是被自动化流水线代劳 |
| 2026-09-23 | 补充实测并记录：signing/notarization 只在"分发给别人下载"这条链路上是硬需求，Jakob 自己用 `make run`/本机 `open` 跑，今天就是一个完整可用的 App，不受影响 | Gatekeeper 的公证检查只作用于带 `com.apple.quarantine` 隔离标记的文件（从浏览器/邮件/AirDrop 下载才会打标记），本机构建、`open` 直接启动的 App 没有这个标记。实测：`xcodebuild build -scheme KnowingYou -configuration Release` 编译通过，ad-hoc 签名的 `.app` 用 `open` 启动后进程稳定运行、引导窗口正常弹出，没有触发任何 Gatekeeper 拦截对话框（`spctl -a -vv` 对它判定 `rejected` 是预期内的静态判定，不代表 `open` 会被拦）。这条记录下来是为了避免"S21 没完全 done"被误读成"App 现在还不能用"——两者是完全不同的两件事，前者只影响未来想公开分发给别人下载这一步 |
| 2026-09-23 | 补充实测并记录：零网络验证不要求 Little Snitch，改用系统自带工具在空闲态完成一次真实的运行时验证 | spec 原文本就允许 `nettop` 作为 Little Snitch 的替代方案；实际跑了 `nettop -p <pid> -L 45 -s 2`（90 秒零连接）加 `lsof -p <pid> -i`（零网络文件描述符，且用同一份 `lsof` 快照对比出这台机器上其它正常应用都有真实连接，排除"lsof 本身没抓到"的可能）。这比单纯的源码静态扫描更有说服力，也比"完全没做、全部留给 Jakob"更接近验收标准的字面要求；真实录音路径仍受 TCC 归因问题限制，如实标注为范围限制而非略过不提 |
