---
id: S03
title: 设置窗口框架 + 通用页
milestone: M0
status: todo
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
- [ ] 与 `01-settings-general.png` 并排对比：左栏、分组标题、行高、按钮位置目测无偏差（±2 pt）。
- [ ] 五个左栏项可切换，选中态底色正确；底部卡片点击跳到关于（空页）。
- [ ] G2/G3/G4 切换后重启 app 状态保持；G3 切换后 Dock 图标立即出现 / 消失。
- [ ] "更改…"选一个新目录后副标题立即更新，磁盘占用重新计算；选只读目录出现红字。
- [ ] "在 Finder 中显示"打开正确目录；反馈打开邮件客户端并预填主题。
- [ ] 语言切换出现重启提示，重启后界面语言变化。

## 测试
`SaveDirectoryTests`：默认路径按语言；可写性校验（用 `chmod 555` 临时目录）；目录大小计算。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
