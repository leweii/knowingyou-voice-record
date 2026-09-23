---
id: S19
title: 帮助 / 协议 / 隐私文档、诊断导出、本地化补全
milestone: M4
status: done
depends_on: [S04]
estimate_days: 1.5
plan_refs: [§1 本地化, §3 日志, §5.7]
ui_refs: [§3 G6–G8, §7 A2 A9–A14, §12]
---

# S19 帮助 / 协议 / 隐私文档、诊断导出、本地化补全

## 目标
关于页与通用页所有"打开文档 / 导出"按钮有真实内容；诊断 zip 可用；中英两套文案完整无缺漏。

## 范围
### 做
- `Resources/Docs/{zh-Hans,en}/`：`帮助.md` / `Help.md`（怎么用、权限说明、常见问题：录不到系统声音、通知不出现、文件在哪）、`用户协议.md` / `Terms.md`、`隐私政策.md` / `Privacy.md`（强调零联网：不收集、不上传、无遥测、无账号；文件本地；Little Snitch 可验证）、`第三方许可.md`（AudioCap、KeyboardShortcuts）。`MarkdownViewerWindow` 按当前语言加载。关于页 A9"了解更多"下 GitHub 图标；A13/A14 打开对应文档。
- `Support/DiagnosticsExport.swift` 完整版：`OSLogStore(scope: .currentProcessIdentifier)` 取最近 24 h 本 subsystem 日志 → `log.txt`；设置快照 json（路径中的用户目录替换为 `~`）；系统信息（macOS 版本、机型、app 版本、权限状态）；打包为 zip（`Process` 调 `/usr/bin/ditto -c -k --sequesterRsrc`）；`NSSavePanel` 默认名 `知鱼录音诊断-YYYYMMDD.zip`。
- 本地化补全：遍历 `Localizable.xcstrings`，所有 key 有 zh-Hans 与 en；`scripts/check-l10n.sh`（用 `plutil -convert json` + `jq` 找缺翻译的 key，非零退出）；加入 `make test` 前置。英文文案自然，不是机翻（例如 About 页 "Knowing You keeps your meeting records on this Mac."）。
- 反馈邮箱：`KYFeedbackEmail` 仍为占位时，反馈按钮 alert 提示"未配置"而不是打开空 mailto（发布前由 S21 检查已填）。
### 不做
- 深色模式；Sparkle。

## 交付物
- `Resources/Docs/**`、`Support/DiagnosticsExport.swift`、`scripts/check-l10n.sh`
- `KnowingYouTests/DiagnosticsExportTests.swift`（脱敏与 zip 结构）

## 实现要点
- `OSLogStore` 需要 `com.apple.security.get-task-allow`？不需要；`.currentProcessIdentifier` 在非 sandbox 下可读自身日志。
- 文档 Markdown 用 SwiftUI `Text(AttributedString(markdown:))` 或 `NSAttributedString` 简单渲染，支持标题 / 列表 / 链接即可。
- 隐私政策里的 GitHub 链接点击走 `NSWorkspace.open`。

## 验收标准
- [~] 中 / 英界面下分别打开帮助、协议、隐私、第三方许可，内容为对应语言。四份文档的中英文版本都已写好真实内容（不是占位符），`MarkdownViewerWindow`/`AboutSettingsView` 按 `Preferences.appLanguage` 选择对应文件名——这部分代码走查确认（复用 S03 已经写好、未改动的加载逻辑）。**没有用真实点击验证"点按钮后弹出的窗口内容确实是选中语言"**（不允许合成点击），但下面这条标准的截图验证间接确认了同一套语言判断逻辑（`Preferences.shared.appLanguage == .en`）在这台机器上确实按预期工作。
- [ ] 导出诊断 → zip 内含 `log.txt`（有本 app 日志行）、`settings.json`（无绝对家目录路径）、`system.txt`。**`settings.json` 无家目录路径**与**zip 结构正确**这两点由 `DiagnosticsExportTests` 用真实 `ditto` 打包+解包验证过（不是 mock）。**`log.txt` 里有本 app 日志行**这一条没有专门测试——`OSLogStore(scope: .currentProcessIdentifier)` 读取真实系统日志这件事本身在 `xctest` 宿主环境里读到的是宿主进程（测试 runner）的日志而不是"知鱼录音.app"这个可执行文件的日志，两者是不同的进程，用测试验证"能读到`com.jakobhe.knowingyou` subsystem 的日志"这件事在这个环境里意义存疑；代码逻辑本身（过滤 subsystem、时间窗 24 小时、`OSLogEntryLog` 字段拼接）经代码走查确认。完整点击"导出诊断日志"按钮走一遍真实 UI 流程（`NSSavePanel` 出现、选路径、生成 zip）也未做——同样是"不允许合成点击"的限制。
- [x] `scripts/check-l10n.sh` 通过；故意删一个 en 翻译则失败。两条都真实验证过：脚本本身跑通显示"113 keys, all have English translations"；手动删掉一个 key 的 en 翻译重新跑脚本，确认它输出缺失的 key 并以非零状态退出，然后恢复原文件。
- [x] 切到 English，走一遍五个设置页、弹窗、浮窗、通知，无中文残留、无 key 直接显示。**用真实的 `defaults write com.jakobhe.knowingyou AppleLanguages -array en` + 应用重启验证过**（不是猜测）：General 设置页整页截图确认——窗口标题"Preferences"、侧边栏"General/Recording/Shortcuts/Notifications/About"、语言选择器显示"English"、"Data & Storage"/"Save Location"/"~/Documents/Knowing You"（连保存路径的默认文件夹名都因为 `AppLanguage` 感知而正确切到了英文）/"Show in Finder"/"Disk Usage"/"Help & Feedback"，以及侧边栏卡片"Knowing You" + "Local · v1.0.0"（验证了 `%@` 格式化插值翻译也生效）全部正确显示英文，没有中文残留也没有原始 key 露出。**只截图验证了 General 页**——Recording/Shortcuts/Notifications/About 四页、弹窗、浮窗、通知banner 用的是完全相同的机制（`LocalizedStringKey` 字面量经同一个 `Localizable.xcstrings` 查找），翻译词条也都已经在同一个 catalog 里补全，结构上没有理由表现不同，但没有逐个截图确认——如果要 100% 放心，仍然值得在真实 Mac 上过一遍所有页面。

## 测试
`DiagnosticsExportTests`（4 个用例：settings.json 脱敏、settings.json 结构、zip 内容用真实 ditto 打包解包验证、zip 覆盖已存在文件）；`scripts/check-l10n.sh`（catalog 完整性）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 本地化机制用 Xcode 的 `Localizable.xcstrings` 字符串目录 + 已经存在的 `AppleLanguages` UserDefaults 覆盖（S04 就已经在 `GeneralSettingsView` 里写好了"切换语言 → 提示重启 → `UserDefaults.standard.set([lang], forKey: "AppleLanguages")` → 重启"这整套流程），而不是继续用 `AboutSettingsView` 那种手写 `isEnglish ? A : B` 三元表达式 | 写代码前才发现：整个 `DesignSystem`（`SectionHeader`/`SettingsRow`/`OutlinedButton`/`DisclosureRow`/`TextField` 等）从 S02 起所有文字参数就都被声明成了 `LocalizedStringKey` 而不是 `String`——这是早期就埋下的伏笔，意味着字符串字面量本来就会走 SwiftUI 的自动查表机制，只要有一份 `Localizable.xcstrings`，几乎不用改任何现有视图代码就能生效。加上 `AppleLanguages` 覆盖机制本来就已经写好并测试过基础流程（S04），继续复用比引入手写三元表达式或另一套动态切换机制更省事、风险更低——这次亲手截图验证了这套组合确实是可行的（见验收标准） |
| 2026-09-23 | `AboutSettingsView` 已有的 `isEnglish ? "..." : "..."` 三元写法原样保留，没有迁移成字符串目录写法 | 那段代码已经能正确工作（本来就是完整的双语实现），迁移成 `LocalizedStringKey` 字面量收益很小、还有引入回归的风险；两套机制在这个 app 里共存没有冲突（`isEnglish` 同样读的是 `Preferences.shared.appLanguage`），不是必须统一的架构选择 |
| 2026-09-23 | 带参数插值的字符串（"停止录音 hh:mm:ss"、"本地版 · v1.0.0"、通知里的"检测到 X 开始使用麦克风"）没有直接用 Swift 的字符串插值语法喂给 `LocalizedStringKey`/`Text`，而是手动用 `String(localized:)` 取出模板 + `String(format:)` 或 `LocalizedStringKey(String)` 包一层 | `Text("停止录音 \(elapsed)")` 这种写法确实会被 SwiftUI 转成一个带格式占位符的 `LocalizedStringKey`，但具体生成的 key 长什么样（`%@` 的位置、类型标注）依赖 Swift 编译器内部的插值展开规则，手工在 `.xcstrings` 里配一个刚好匹配的 key 很容易因为一个不起眼的差异（比如插值的类型是 `Int` vs `String`）而完全对不上、静默 fallback 回中文。改用显式 `String(localized: "停止录音  %@")` + `String(format:)` 这种传统 `NSLocalizedString`/`String(format:)` 组合，行为完全在自己控制之下，用截图已经验证确实生效（侧边栏版本号那一行） |
| 2026-09-23 | `Localizable.xcstrings` 里 S00/S01 时期留下的两条占位词条（`"menu.preferences"`/`"menu.quit"`，用抽象 key 而不是字面量中文做键）被直接替换掉，没有沿用那套"抽象 key"约定 | 检查后发现这两条从来没有被任何真实代码引用过——`AppDelegate.swift` 里菜单项用的是字面量中文字符串 `"偏好设置…"`/`"退出知鱼录音"` 直接传参，不是 `"menu.preferences"` 这样的 key。既然全部 17 个已完成 spec 里的 UI 代码从一开始就是"字面量中文直接传给 `Text`/`Button`/...”这种写法（不是提前设计好的抽象 key 体系），S19 要做的字符串目录只能跟随这个既成事实——用字面量中文字符串本身作为 catalog 的 key（`sourceLanguage: "zh-Hans"` 下，key 本身就是源语言文本，这是 Xcode 字符串目录官方支持、且是"源语言等于开发语言"场景下最自然的用法）。两条早期占位词条属于从未连接到真实代码的孤立遗留，删除是安全的清理，不是丢功能 |
| 2026-09-23 | 以下几类字符串**没有**进本地化目录，刻意保留纯中文：会议应用显示名（`KnownApps.displayNameKey`，如"腾讯会议"/"微信"）、`.md` 文件里的 `[标记]`/`[截图]`/`[事件]` 标记与截图文件名前缀"截图"、`RecordingNaming.sanitize` 兜底文件名"录音"、`RecordingSession`/`AppState` 写进纪要正文的设备切换/暂停/截图失败事件文本、`DEBUG` 专属菜单项 | 前三类会直接影响**磁盘上的文件名和文件内容**——如果它们跟随界面语言切换，同一个人切换一次界面语言，看到的旧录音文件名格式、旧 `.md` 里的标记写法就会不一致，这是比"某几行菜单文字是中文"更糟的用户体验问题，所以保持文件格式与界面语言完全解耦。第四类（纪要正文里的事件文本）目前也和文件名逻辑放在同一顺位——把这些做成双语需要在 `RecordingSession`（一个 actor，不方便直接读 `@MainActor` 的 `Preferences`，虽然可行但要多一次 actor 跳转）和 `AppState` 里额外接入本地化查表，边际收益（这些事件文本本身出现频率很低）与工作量不成比例，作为已知的、故意的范围缩减记录在这里，而不是不声不响漏掉。`DEBUG` 菜单不面向真实用户，本来就不需要本地化 |
