# S21 发布检查清单

## 这台机器能做到哪一步（诚实边界）

这是一台被远程 Air 环境接管的开发机,没有：

- Apple Developer Program 账号 / Developer ID Application 签名证书
- `xcrun notarytool` 的 keychain profile（需要 App Store Connect API key 或 Apple ID + app-specific 密码,都是账号凭证,不该也不能由我代为生成)
- 一台"干净"的、非当前开发机的 Mac 用于首次安装体验测试
- Little Snitch（或任何需要额外安装/购买的网络监控工具)
- 一个真实可用的反馈邮箱地址,或者品牌 logo 设计资源

这些全部是**需要 Jakob 本人提供凭证/资产**的东西,不是代码问题,因此本轮 S21 的产出是：**把整条发布流水线的脚本和硬阻断检查做完、跑通到"卡在需要真实凭证"那一步为止**,而不是假装已经发布过。以下逐项记录。

## 已完成

- [x] `scripts/check-release-readiness.sh <version>`：硬阻断 `make release`,校验（已用 `1.0.0` / `1.0.0-beta.1` / `2.0.0` 三种输入实测确认三条检查分别能触发/通过)：
  - `project.yml` 的 `MARKETING_VERSION` 与传入版本号一致
  - `Info.plist` 的 `KYFeedbackEmail` 不再是占位值 `feedback@example.invalid`
  - App 图标资源 `AppIcon.appiconset` 存在，且 `Brand.swift` 不再引用占位 SF Symbol `waveform.circle`（2026-09-30 S22 改：Logo 已落地，检查改为防回退）
  - `Info.plist` 的 `KYIsPrerelease` 与版本号是否带有 `-` 后缀（semver pre-release 标记)一致
- [x] `scripts/sign-and-notarize.sh <version>`：`xcodebuild archive` → `exportArchive`（Developer ID Application, manual signing) → `codesign --verify --deep --strict` → `ditto` 打包 → `notarytool submit --wait` → `stapler staple` → `spctl -a -vv` 验证。签名身份/团队 ID/notarytool profile 名全部通过环境变量传入（`KY_SIGN_IDENTITY`/`KY_TEAM_ID`/`KY_NOTARY_PROFILE`),仓库里不出现任何真实身份信息。
- [x] `scripts/make-dmg.sh <version>`：`hdiutil` 打包（选用它而不是 `create-dmg`,避免为了背景图多引入一个 Homebrew 依赖)、`Applications` 软链、DMG 本身也签名+公证+staple、输出 `SHA256SUMS`。
- [x] `make release VERSION=x.y.z`：串起 `check-no-network` → `check-l10n` → `check-release-readiness` → `sign-and-notarize` → `make-dmg` → `git tag`（本地打 tag,不自动 push,推送是有对外可见影响的动作,留给 Jakob 自己决定时机)。**已实测**：在当前仓库状态下运行 `make release VERSION=1.0.0`,在 `check-release-readiness` 这步正确失败并中止,没有创建任何 tag（`git tag` 命令确认为空)——这正是验收标准里"在任一前置检查失败时中止且不打 tag"要验证的行为。
- [x] 三个脚本用 `sh -n` 做过语法检查,`check-release-readiness.sh` 的三条检查分支各自用不同版本号手动触发过一次,确认逻辑正确。
- [x] **补充验证**：Release 配置（不只是 Debug）也编译通过——`xcodebuild build -scheme KnowingYou -configuration Release` 成功产出 ad-hoc 签名（`Sign to Run Locally`, hardened runtime on）的 `KnowingYou.app`。`open` 启动后用 `ps aux` 确认进程稳定运行（未崩溃），首次引导窗口正常弹出，麦克风权限对话框正常触发（虽然像 S07 记录的那样归因到宿主 "Air" 进程，而非应用本身——这是这台远程开发沙盒进程祖先链的固有特性，见 CLAUDE.md）。`spctl -a -vv` 对这个 ad-hoc 签名的 App 判定 `rejected`（预期内，因为没有 Developer ID），但 `open` 命令本身没有被 Gatekeeper 拦截、没有弹出"来自身份不明的开发者"的对话框——这印证了下面这条结论：**本机构建的 App（未被标记隔离属性）不受 Gatekeeper 未公证检查的限制，只有从网络下载的、带 `com.apple.quarantine` 标记的文件才会被拦**。也就是说，Jakob 完全可以在拿到已公证 DMG 之前，直接用 `make run`/`open` 跑一个功能完整的本机版本，S21 剩下没做完的部分只影响"分发给别人下载安装"这条链路，不影响他自己现在就能用。

## 无法在这台机器上完成、需要 Jakob 补齐的部分

### 1. 占位符必须换成真实值（`check-release-readiness.sh` 会硬阻断,不能跳过)

- ~~`KYFeedbackEmail` 占位~~：2026-09-30 已设为 `lewei.me@gmail.com`。
- ~~Logo 占位~~：2026-09-30 已完成（S22）——Dock / App 图标、菜单栏图标、应用内标志统一为"鱼形声波"标志。

### 2. 首次发布前，`KYIsPrerelease` 需要从 `true` 改成 `false`

`Info.plist` 里目前写死 `true`——`check-release-readiness.sh` 已经能在版本号和这个标记不一致时拦下来,但选择改成 `false` 本身（也就是"这就是要正式发布的版本，不是内测")是个产品决定,由 Jakob 在真正要发布时改。

### 3. 需要 Jakob 本人一次性设置的发布凭证（Apple 账号相关,不能代做)

```sh
# 在 Keychain Access 里已经有 Developer ID Application 证书的前提下:
xcrun notarytool store-credentials <profile-name> \
  --apple-id <your-apple-id> \
  --team-id <TEAMID> \
  --password <app-specific-password>

# 然后设置环境变量再跑 make release：
export KY_SIGN_IDENTITY="Developer ID Application: Jakob He (TEAMID)"
export KY_TEAM_ID="TEAMID"
export KY_NOTARY_PROFILE="<profile-name>"
make release VERSION=1.0.0
```

### 4. 首次启动体验清单（需要真实签名的 build,在真机上人工过一遍)

- [ ] 从 DMG 拖到 `/Applications`（不能直接从 DMG 内运行——`SMAppService` 在 DMG 里注册会失败,这是 Apple 的限制,不是本项目的 bug,已经在 `README.md`/用户文档里提醒)
- [ ] 双击启动,Gatekeeper 无警告（前提是公证+staple 成功)
- [ ] 引导窗口正常展示
- [ ] 麦克风/系统音频/通知权限弹窗正常，同意后正常工作
- [ ] 手动录一段：菜单栏图标点击 → 开始录音 → 停止 → 生成的 `.m4a`/`.md` 文件名和内容正确
- [ ] 打开一个白名单会议软件,自动检测 → 通知 → 自动录音（或按设置询问)全流程正确
- [ ] 把 app 拖到废纸篓卸载,确认 `SMAppService` 已注销（登录项列表里不再出现)、没有残留后台进程

### 5. 零网络验证（Little Snitch 或 `nettop`)

- [x] **空闲态已用系统自带工具验证**：这台机器没有 Little Snitch,改用 `nettop -p <pid> -L 45 -s 2` 采样 90 秒 + `lsof -p <pid> -i` 交叉核对,确认 Release 构建的 `KnowingYou` 进程在启动后完全空闲的状态下，没有建立过任何 TCP/UDP 连接，也不持有任何网络类文件描述符——不是"没抓到"，是真的一个都没有。详细方法、结果、范围限制见 [network-verification.md](network-verification.md)。
- [ ] **仍未覆盖**：包含一次真实录音全流程（麦克风 tap + 系统音频 tap 实际工作时）的联网观察——这台环境的麦克风 TCC 权限被错误归因给宿主 "Air" 进程，无法在这里真正触发一次端到端录音，这部分留给 Jakob 在自己的 Mac 上补一次，用 Little Snitch 或 `nettop` 都可以。

`scripts/check-no-network.sh` 已经在源码层面做了静态扫描（构建时的强制门禁,见 `CLAUDE.md`),`network-verification.md` 补上了运行时层面（虽然只覆盖空闲态)的验证,两者结合比单独任何一个都更有说服力,但真实录音路径这一段仍然只有 Jakob 能在真机上补完。

### 6. GitHub Release 草稿

README.md 已经按 S21 范围重写成面向用户的版本（下载/安装/权限/文件位置/隐私声明/从源码构建),changelog 文案可以直接从这次 commit 历史整理,但**实际创建 GitHub Release 草稿**（`gh release create`)需要：(a) 一个已经通过公证的真实 DMG 文件可供上传,(b) 对这个仓库的 push 权限。两者现在都不具备,所以这一步同样留给 Jakob 在完成第 1-5 项之后自己执行,或届时再叫我用 `gh release create --draft` 帮忙创建。

## 验收标准对照

| 验收标准 | 状态 |
|---|---|
| 干净用户账户下载 DMG → 安装 → 首次启动无 Gatekeeper 拦截 → 按清单跑通全部步骤 | 未执行——无真实签名 DMG，见上方第 4 项 |
| `spctl -a -vv KnowingYou.app` 输出 `accepted … Notarized Developer ID` | 未执行——无 Developer ID 证书和 notarytool 凭证 |
| 零网络验证结果记录在案 | **部分完成**——空闲态用 `nettop`/`lsof` 验证过（见 [network-verification.md](network-verification.md)），真实录音全流程的那部分见上方第 5 项，留给 Jakob |
| `make release` 在任一前置检查失败时中止且不打 tag | **已验证**：`make release VERSION=1.0.0` 在 `check-release-readiness` 阶段正确失败并退出,未创建 tag |
| `CLAUDE.md` 增加发布命令与注意事项 | 已完成 |
