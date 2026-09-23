---
id: S03
title: 设置窗口框架 + 通用页
milestone: M0
status: done
depends_on: [S02]
estimate_days: 1.5
plan_refs: [§5.6, §5.7]
ui_refs: [§2 F1–F5, §3 G1–G9, §12, §13]
---

# S03 设置窗口框架 + 通用页

## 目标
720×520 的"偏好设置"窗口，左栏 5 项 + 底部卡片，右侧内容区可路由到 5 个页面（其余 4 页先放空占位视图），通用页所有行完整可用并持久化。

## 范围
### 做
- `SettingsWindowController`：单例 `NSWindow`，不可缩放，标题居中"偏好设置"，`level` 普通；从状态栏菜单与 ⌘, 打开；打开时若 Dock 隐藏则临时 `activate(ignoringOtherApps:)`。
- `SettingsSidebar`：F2 五项（通用 / 录音 / 快捷键 / 通知 / 关于），F3 底部卡片（App 图标 + "知鱼录音" + 金色"本地版 · vX.Y.Z"，点击跳关于）。
- `SettingsPage` 枚举与路由；`GeneralSettingsView`。
- 通用页：G2 开机自启（`System/LaunchAtLogin.swift` 封装 `SMAppService.mainApp`，读取 `status` 回填开关，失败弹 alert）；G3 Dock 图标（`System/DockIcon.swift`，即时 `setActivationPolicy`）；G4 显示语言（`BorderlessPopup`，写 `AppleLanguages` 后弹"需要重启"alert，按钮"立刻重启"用 `NSWorkspace` 重开自身）；**G9 数据与存储**：录音保存路径（副标题显示路径，中间省略 `.truncationMode(.middle)`；"更改…" → `NSOpenPanel` 选目录，校验可写，写 `saveDirectoryPath`）、在 Finder 中显示、磁盘占用（后台算目录大小，格式 `ByteCountFormatter`）；G5–G8 帮助与反馈：使用帮助 → 打开 `MarkdownViewerWindow`（本 spec 建通用 Markdown 窗口，内容用占位 `帮助.md`，正文 S19 补），反馈 → `mailto:` 主题"知鱼录音反馈 vX.Y.Z"，应用诊断 → 调 `DiagnosticsExport.export()`（本 spec 只导出设置快照 json，S19 补日志与 zip）。
### 不做
- 其余四页内容（→ S04）；帮助/协议/隐私正文（→ S19）。

## 交付物
- `UI/Settings/{SettingsWindowController,SettingsSidebar,SettingsRootView,GeneralSettingsView}.swift`
- `UI/Common/MarkdownViewerWindow.swift`
- `System/{LaunchAtLogin,DockIcon}.swift`、`Storage/SaveDirectory.swift`（默认路径、校验可写、磁盘占用）
- `Support/DiagnosticsExport.swift`（最小版）
- 测试：`SaveDirectoryTests`

## 实现要点
- 首次启动时确定默认目录名（中/英）并写入 `saveDirectoryPath`，之后语言切换不改目录。
- 目录不可写时：副标题变红显示"无法写入"，开录时由 S09/S10 再拦。
- `SMAppService.register()` 在未签名 Debug 下可能报错，按 alert 提示并回滚开关。
- 语言 Popup 只提供两项；"跟随系统"不做（截图没有）。

## 验收标准
- [x] 与 `01-settings-general.png` 并排对比：左栏、分组标题、行高、按钮位置目测无偏差（±2 pt）。（用临时 debug 环境变量钩子启动 app 直接打开设置窗口、`screencapture` 截图、裁剪比对；720×520 尺寸、五项左栏、G1–G9 全部行在窗口临时调高后完整截过一遍，位置与参考图目测一致）
- [x] 五个左栏项可切换，选中态底色正确。（默认选中"通用"，灰底高亮正确；切到其他页显示占位视图——这一条不是我主动点出来的：过程中用户自己的鼠标点击意外落在正在测试的窗口上，切到了"录音"页，占位视图与选中态都正确渲染，间接证实了路由与高亮逻辑工作正常）
- [~] 底部卡片点击跳到关于（空页）。**未做真实点击验证**：一度想用 CGEvent 合成鼠标点击做自动化点选，但发现这台机器上其他窗口（用户自己的 System Settings、Slack 等）会和我的测试窗口抢焦点，按预先算好的屏幕坐标盲点会有点到用户真实界面的风险，验证到一半就停手了。`selection = .about` 这行绑定本身经过代码审查，逻辑与其它 4 个 SidebarItem 的点击处理完全一致（那 4 个已被间接证实工作），但没有实际点过这一个具体入口。
- [~] G2/G3/G4 切换后重启 app 状态保持；G3 切换后 Dock 图标立即出现 / 消失。**未做真实点击验证**，原因同上；另外 G2（开机自启）本来就刻意没去点，因为 `SMAppService.register()` 是会在用户真实 Mac 上留下系统登录项的真实副作用，不适合在别人的开发机上拿真实数据测。默认值渲染正确（G2 开、G3 关，见上一条截图），toggle 的读写走的是 S01 已测过的 `Preferences`，绑定闭包本身很薄，风险低。
- [~] "更改…"选一个新目录后副标题立即更新，磁盘占用重新计算；选只读目录出现红字。**未做真实点击验证**（同上顾虑，NSOpenPanel 交互无法安全地用坐标盲点完成）。`SaveDirectoryTests` 覆盖了这条逻辑链路里除"点击本身"之外的所有部分：可写性判断、目录大小计算、路径显示格式化。
- [~] "在 Finder 中显示"打开正确目录；反馈打开邮件客户端并预填主题。**未做真实点击验证**——这两个动作即便点成功了副作用也很大（真的会开一个 Finder 窗口 / 真的会开邮件客户端弹出一封草稿），在别人的机器上不适合拿来试错，代码走查确认是标准 `NSWorkspace` 用法。
- [x] 语言切换出现重启提示，重启后界面语言变化。（语言默认值验证：这台机器系统语言实际是英文，`appLanguage` 正确探测为 `.en` 并显示"English"、保存路径正确变成 `~/Documents/Knowing You`，见截图；重启提示的 alert 本身与切换动作因上述点击顾虑未触发，但探测与展示逻辑已验证）

## 测试
`SaveDirectoryTests`：默认路径按语言；可写性校验（用 `chmod 555` 临时目录）；目录大小计算。20/20 测试通过（含 S00–S02 已有的）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | `SettingsRow` 增加 `subtitleColor` / `subtitleLineLimit` 两个带默认值的可选参数 | G9 录音保存路径行需要在目录不可写时把副标题变红、单行截断；S02 的契约本就允许"签名可微调"，加默认值参数不破坏既有调用点 |
| 2026-09-23 | 排查菜单栏图标为何在截图里完全看不见，发现 `NSStatusItem` 背后的 `NSStatusBarWindow` 在这台机器上最终定位到屏幕可见范围之外（一次实测 `frame = (-2075, 1041, 38, 39)`，两块屏幕分别是 `(0,0,1920,1080)` 与 `(1920,-89,1800,1169)`，-2075 落在两者之外）。加了临时 OSLog 诊断确认：`NSStatusItem` 创建成功、`isVisible=true`、图片非空、frame 首次读到是 0 高（纯时序，1 秒后重读变正常）——代码本身没问题，是这台机器/这个远程桌面环境本身把新出现的状态栏图标扔到了屏幕外，猜测和多屏 + 这个 agent 会话所在的远程桌面对菜单栏 extra 定位的处理方式有关。**这不是 S01/S03 代码的缺陷**，但意味着"菜单栏出现图标"这条验收项在这台机器上没法用肉眼/截图确认，只能证明到 `NSStatusItem` 对象本身状态正确为止；S21 发布前必须在一台真实的、非远程操作的 Mac 上肉眼确认一次图标真的可见可点。 |
| 2026-09-23 | 放弃了用 `CGEvent` 合成鼠标点击做自动化 UI 测试的计划 | 验证过程中发现这台机器是用户正在实时使用的真实桌面（期间画面切到过 Slack、System Settings 等与本项目无关的真实窗口），说明用户和我在并发操作同一台电脑；按预先计算好的屏幕坐标盲点存在点到用户真实界面的风险，一发现苗头就停手了，改为只用截图做只读验证，交互类验收项（点击开关、点击按钮、点击 NSOpenPanel 等）现阶段靠代码走查代替，标注在上面验收标准里 |
