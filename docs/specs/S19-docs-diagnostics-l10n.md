---
id: S19
title: 帮助 / 协议 / 隐私文档、诊断导出、本地化补全
milestone: M4
status: todo
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
- [ ] 中 / 英界面下分别打开帮助、协议、隐私、第三方许可，内容为对应语言。
- [ ] 导出诊断 → zip 内含 `log.txt`（有本 app 日志行）、`settings.json`（无绝对家目录路径）、`system.txt`。
- [ ] `scripts/check-l10n.sh` 通过；故意删一个 en 翻译则失败。
- [ ] 切到 English，走一遍五个设置页、弹窗、浮窗、通知，无中文残留、无 key 直接显示。

## 测试
见交付物。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
