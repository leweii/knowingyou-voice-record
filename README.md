# 知鱼录音 · Knowing You

macOS 菜单栏会议录音应用。检测到会议软件开始使用麦克风时自动（或经确认后）录音，同时录下麦克风与系统音频；录音中可在浮窗里记纪要，每条带挂钟时间与距开始偏移；产物是 `时间戳 应用名.m4a` + 同名 `.md`，只保存在本地文件夹。

**零联网**：无账号、无云、无遥测、无自动更新、无 AI。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/01-implementation-plan.md](docs/01-implementation-plan.md) | 技术选型、架构、关键方案、分阶段计划、风险、已确认决策（§12） |
| [docs/02-ui-spec.md](docs/02-ui-spec.md) | 逐元素 UI 复刻规格：尺寸、颜色、字体、控件、每个屏幕的元素表、文案替换表 |
| [docs/specs/](docs/specs/README.md) | 开发 spec：22 个可独立领取、独立验收的任务（S00–S21），含工作流、已确认决策、依赖图、状态表 |
| [docs/reference-screenshots/](docs/reference-screenshots/) | 原型（Plaud 桌面端 v1.3.7 Beta）9 张截图 |

## 状态

2026-09-23：计划、UI 规格与开发 spec 已由 Jakob 确认（`01-implementation-plan.md` §12 全部按建议值拍板），尚未开始编码。下一步：按 `docs/specs/README.md` 从 S00 → S01 开工。反馈邮箱与 Logo 仍是占位，发布前（S19/S21）需替换为真实值。
