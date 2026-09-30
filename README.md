# 知鱼录音 · Knowing You

macOS 菜单栏会议录音应用。检测到会议软件（腾讯会议、飞书、钉钉、Zoom、Teams 等）开始使用麦克风时，自动（或经你确认后）同时录下麦克风与系统音频；录音过程中可以在一个小浮窗里随手记纪要，每条自动带上挂钟时间和距开始的偏移。产物很简单：一个 `.m4a` 音频文件 + 一个同名的 `.md` 纪要文件，只保存在你自己选的本地文件夹里。

**零联网**：没有账号、没有云同步、没有遥测、没有自动更新、没有 AI 功能。源码里完全不链接任何联网 API（`scripts/check-no-network.sh` 把这条做成了构建期的强制检查，不是一句承诺）。你可以用 Little Snitch 之类的工具亲自验证。

## 下载与安装

1. 前往 [Releases](https://github.com/leweii/knowingyou-voice-record/releases) 下载最新的 `KnowingYou-x.y.z-arm64.dmg`。
2. 打开 DMG，把「知鱼录音」拖进 `应用程序`（`/Applications`）文件夹。
   - **必须先拖进「应用程序」再打开**——直接从 DMG 里双击运行，"开机启动"这个功能（用的是系统的 `SMAppService`）会注册失败，这是 macOS 本身的限制，不是 bug。
3. 从「应用程序」文件夹里双击打开。
   - **目前的 Beta 版未经 Apple 公证**（还没有 Developer ID 证书），首次打开会被 Gatekeeper 拦截，提示"无法验证开发者"或"已损坏"。任选一种方式放行：
     - 打开「系统设置 → 隐私与安全性」，在底部找到被拦截的「KnowingYou」，点「仍要打开」；或
     - 在终端执行 `xattr -dr com.apple.quarantine /Applications/KnowingYou.app` 后再双击打开。
   - 这一步只需要做一次。正式版会走完签名与公证，届时不再需要。
4. 按引导窗口走完首次设置（选择保存文件夹、决定是否自动录音等）。

**在拿到已公证的 DMG 之前，你现在就能用**：签名/公证只在"把 app 分发给别人下载"这条链路上是必需的——macOS 的 Gatekeeper 只拦截带有隔离标记（`com.apple.quarantine`，从浏览器/邮件下载的文件才会被打上）的 App，本机 `make run` 构建出来的 App 没有这个标记，直接双击打开不会被拦截。也就是说：`git clone` 这个仓库、`make run`，你自己电脑上今天就有一个功能完整、可以正常录音记纪要的 App，不需要等 S21 的签名/公证走完。已经用 Release 配置实测过一次：`xcodebuild build -scheme KnowingYou -configuration Release` 编译通过，`open` 启动后进程稳定运行、正常弹出首次引导窗口，没有触发任何"来自身份不明的开发者"的 Gatekeeper 拦截。签名/公证/DMG 那一整套，是为了以后你想把它发给别人下载用时才需要的东西。

当前只提供 **Apple Silicon（arm64）** 构建，没有 Intel 版本。

## 权限

首次使用相关功能时会按需申请，不会一次性弹一堆：

| 权限 | 什么时候申请 | 用途 |
|---|---|---|
| 麦克风 | 第一次开始录音时 | 录制你自己的声音 |
| 系统音频录制 | 第一次开始录音时（如果开启了"同时录制系统音频"） | 录制对方在会议里说的话/播放的内容 |
| 通知 | 首次启动引导时 | 检测到会议开始/结束时提醒你 |
| 屏幕录制 | 第一次使用"截图标记"功能时 | 把会议应用当前窗口截图，作为纪要里的一条标记 |

不需要辅助功能（Accessibility）权限——全局快捷键用的是系统原生的 Carbon 热键 API，不需要监听按键。

## 录音文件保存在哪里

默认保存目录：

- 中文界面：`~/Documents/知鱼录音`
- English：`~/Documents/Knowing You`

可以在设置里的「录音」页随时改成任意你自己选的文件夹。文件是一个平铺目录（不分子文件夹，除非某次录音里有截图标记），文件名格式是 `<开始时间到秒> <触发的应用名>.m4a`，配一个同名的 `.md` 纪要文件。手动开始、没有检测到具体会议软件的录音会命名为「手动录音」。

## 隐私声明

- 所有音频、纪要文件只写在你自己选的本地文件夹里，应用本身不会把任何数据发送到任何服务器——因为它压根不链接联网代码。
- 没有账号体系，不收集任何使用数据或崩溃日志（除非你自己主动在设置里点「导出诊断日志」，那也只是打包成一个 zip 文件让你自己查看/发给需要排查问题的人，不会自动上传）。
- 开始录音前，应用会提醒你确认所有参会者都已经知悉本次会议将被录音——这是产品层面的提醒，具体是否需要经过参会者同意，请遵守你所在地区的相关法律法规。

完整文本见应用内「设置 → 关于 → 用户协议 / 隐私政策」，或 [KnowingYou/Resources/Docs](KnowingYou/Resources/Docs)。

## 从源码构建

需要 Xcode（含 macOS 14.4+ SDK）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```sh
brew install xcodegen
git clone https://github.com/leweii/knowingyou-voice-record.git
cd knowingyou-voice-record
make run        # 生成工程、构建 Debug 版本、打开
```

其他常用命令：

```sh
make build      # 生成工程 + 构建（含零联网静态检查）
make test       # 生成工程 + 跑单元测试（含本地化完整性检查）
make clean      # 清理构建产物和生成的 .xcodeproj
```

Debug 构建用 ad-hoc 签名（`CODE_SIGN_IDENTITY: "-"`），可以直接本地跑，不需要 Apple Developer 账号。正式签名/公证/DMG 打包（`make release`）需要一个真实的 Developer ID Application 证书，见 [docs/specs/S21-release.md](docs/specs/S21-release.md) 和 [docs/testing/release-checklist.md](docs/testing/release-checklist.md)。

## 文档（面向想了解实现或参与开发的人）

| 文件 | 内容 |
|---|---|
| [CLAUDE.md](CLAUDE.md) | 给 AI 编码助手（以及任何想快速上手这个仓库的人）的架构总览、已踩过的坑、开发命令 |
| [docs/01-implementation-plan.md](docs/01-implementation-plan.md) | 技术选型、架构、关键方案、分阶段计划、风险、已确认决策 |
| [docs/02-ui-spec.md](docs/02-ui-spec.md) | 逐元素 UI 复刻规格：尺寸、颜色、字体、控件、每个屏幕的元素表 |
| [docs/specs/](docs/specs/README.md) | 开发 spec：22 个任务（S00–S21），含状态表、依赖图、每个 spec 的决策记录 |
| [docs/testing/](docs/testing) | 边界情况测试矩阵、已知问题、发布检查清单 |
| [docs/reference-screenshots/](docs/reference-screenshots/) | UI 复刻所参考的原型截图 |

## 状态

截至 2026-09-23，S00–S20（全部核心功能）已完成并测试。发布相关的 S21 已经把签名/公证/DMG 打包脚本和硬阻断检查做完，但实际的证书申请、公证凭证配置、真机安装测试、零网络流量抓包这几步需要 Jakob 本人的 Apple Developer 账号和一台非当前开发机的真实 Mac，详见 [docs/testing/release-checklist.md](docs/testing/release-checklist.md)。
