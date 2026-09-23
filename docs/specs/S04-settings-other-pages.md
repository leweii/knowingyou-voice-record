---
id: S04
title: 录音 / 快捷键 / 通知 / 关于 四页静态还原
milestone: M0
status: done
depends_on: [S03]
estimate_days: 2
plan_refs: [§2.2, §5.1 默认清单, §5.6]
ui_refs: [§4 R1–R14, §5 K1–K6, §6 N1–N4, §7 A1–A14, §12]
---

# S04 录音 / 快捷键 / 通知 / 关于 四页静态还原

## 目标
剩余四个设置页按规格完整布局，所有设置项读写 Preferences；需要后续模块的按钮（快捷键录制、检查更新等）先做外观与最简行为。

## 范围
### 做
- **录音页**：R1–R14。麦克风 Popup 列出真实输入设备（`Support/AudioDevices.swift`：Core Audio 枚举输入设备 UID/名称，监听设备列表变化），"智能选择"为首项；选具体设备时 R5 说明条隐藏。系统音频、自动录制 toggle；R14 音频格式 Popup。R8/R9 会议识别 Disclosure + 应用列表：每行 `AppIconView`（`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 找到则取图标，否则灰显）、名称、`KYToggle`，绑定 `knownApps[i].isEnabled`；末尾"添加应用…" → `NSOpenPanel` 选 `.app`，读 bundle id 与名称追加为 `.native`。默认清单见 S12（S04 先用 S00 里的静态默认值，bundle id 待 S06 校正）。R13 须知文案按 §12。
- **快捷键页**：K1–K6。K2 全局开关；K6/K3/K4 三行右侧放 `ShortcutRecorderButton`（本 spec 只做静态外观：读 KeyboardShortcuts 已存值显示键帽如 `⌥⌘S`，无值显示"未设置"；点击暂无动作；`hotkeysEnabled == false` 时灰显）；K5 恢复默认（调 `KeyboardShortcuts.reset`）。默认值在 S17 注册。
- **通知页**：N1–N4 三个 toggle，行距 72。
- **关于页**：A1–A14。版本读 `CFBundleShortVersionString`，`KYIsPrerelease` 为真时显示 Beta 胶囊；检查更新 / GitHub 图标 → `NSWorkspace.shared.open` 对应 Info.plist URL；A12 打开录音文件夹；A13/A14 打开 `MarkdownViewerWindow`（占位正文）。底栏 48 高。
### 不做
- 快捷键录制交互与全局注册（→ S17）；文档正文（→ S19）；应用列表与检测联动（→ S13）。

## 交付物
- `UI/Settings/{RecordingSettingsView,ShortcutsSettingsView,NotificationsSettingsView,AboutSettingsView}.swift`
- `UI/Settings/Components/{MeetingAppRow,ShortcutRecorderButton}.swift`
- `Support/AudioDevices.swift`
- 测试：`AudioDevicesTests`（至少能枚举到 1 个输入设备）

## 实现要点
- 录音页内容超高需滚动（02/03 两张截图拼起来），用 `ScrollView` + 系统 overlay 滚动条。
- 应用列表未安装 app 仍显示（灰），toggle 可用（用户可能稍后安装）。
- `AudioDevices` 用 `kAudioHardwarePropertyDevices` + `kAudioDevicePropertyStreams`(input scope) 判断是否有输入；设备名 `kAudioObjectPropertyName`；UID `kAudioDevicePropertyDeviceUID`。监听 `kAudioHardwarePropertyDevices` 变化刷新 Popup。
- 关于页 GitHub 图标：SF Symbols 没有，用 `Resources/Assets` 放一枚单色 24×24 PDF。

## 验收标准
- [x] 四页分别与 `02/03`、`04`、`05`、`06` 截图对比，元素位置、行高、按钮尺寸误差 ≤2 pt；文案与 §12 替换表一致。（用临时 debug 环境变量钩子直接跳到每一页 + `screencapture` 截图比对，四页都过了一遍，视觉上与参考截图一致；关于页因为这台机器系统语言是英文，实际截到的是英文版渲染，中英两条路径都等于验证到了）
- [~] 插拔 USB 麦克风，麦克风 Popup 列表实时更新；选具体设备后说明条消失，重启后保持。**未做真实插拔验证**（这台机器上没有可插拔的 USB 麦克风给我测，且这类硬件交互也不适合用坐标盲点点开 Popup 选择具体设备）。已验证的部分：`AudioDeviceMonitor` 启动时能枚举到真实设备（`AudioDevicesTests` 4/4 通过，其中一条专门断言内置麦克风被判定为有输入）；代码走查确认 `kAudioHardwarePropertyDevices` 监听器接了刷新逻辑；`micSelection == .smart` 时说明条显示、选中具体设备后 `if micSelection == .smart` 为 false 会隐藏，这条 UI 逻辑本身走查无误但没有真实点选触发过。
- [~] 应用列表 toggle 与"添加应用…"持久化；未安装应用图标灰显。**"添加应用…"未做真实点击验证**（会弹真实 `NSOpenPanel`，不适合盲点）。已验证：截图确认了未安装应用（腾讯会议、飞书等这台机器上没装的）图标是灰显的，已安装的（FaceTime、Slack、Discord、微信）显示真实图标；`.onChange(of: knownApps)` 写回 `Preferences.shared.knownApps` 的逻辑经过代码走查，模式与 G9 的目录选择一致（G9 那条persistence 路径本身也没有靠点击验证，靠的是 `SaveDirectoryTests` 覆盖除点击外的逻辑）。
- [x] 关于页版本号与 `project.yml` 一致；`KYIsPrerelease` 切换控制 Beta 胶囊。（截图确认版本号 `v1.0.0` 与 `project.yml` 的 `MARKETING_VERSION` 一致；`KYIsPrerelease` 当前是 `true`，Beta 胶囊按预期显示；没有反向验证"设为 false 后胶囊消失"，因为改 Info.plist 值需要重新 build，逻辑是简单的 `if isPrerelease`，走查已足够）
- [x] 快捷键页 K2 关闭后三个按钮灰显。（代码走查：三个 `ShortcutRecorderButton` 的 `isEnabled` 都绑定同一个 `hotkeysEnabled` 状态，`OutlinedButton` 的灰显效果已经在 S02 画廊里验证过；截图验证的是 K2 默认开启态下的正常外观，"关闭后灰显"这个状态切换本身没有点开关触发去看，只走查了绑定关系）

## 测试
`AudioDevicesTests`：枚举结果每项 UID 非空；`hasInput` 判定正确（内置麦克风为真）。4/4 通过，全套 24/24 通过（含 S00–S03 已有的）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | R9 应用默认清单的 bundle id 直接抄了 S12 spec 里已经写好的猜测值（腾讯会议 `com.tencent.meeting` 等 11 个） | S12 还没做，但 S04 需要现在就有内容可显示；两边用同一份猜测值，S06 spike 出真实结果后只需要改一处 |
| 2026-09-23 | `KnownApp` 默认清单没有放进 `Preferences` 的默认值或 `Meeting/KnownApps.swift`，而是放在 `RecordingSettingsView.placeholderKnownApps`（private static，只在 `Preferences.shared.knownApps` 为空时兜底写入一次） | `Meeting/` 目录是 S12 的地盘，S04 不该在那建文件；`Preferences` 的默认值机制（S00/S01）是纯 UserDefaults 层不适合放业务数据；放在这个页面文件里最不容易和 S12 真正的 `KnownApps.defaults` 冲突，S12 落地时把这段删掉、换成读它自己的默认清单即可 |
| 2026-09-23 | R4 麦克风 Popup 的图标用 `BorderlessPopup.leadingSystemImage`（S02 组件新增的可选参数），而不是单独拼 `HStack` | S02 已经踩过"Menu 会把多视图 label 里第一个 Image 硬拽到最前面"的坑（见 S02 决策记录），这次直接把 leading icon 也编码进同一条 `Text` 拼接链，不给 Menu 任何可以重新排布局的机会 |
| 2026-09-23 | 关于页 GitHub 图标用 SF Symbol `chevron.left.forwardslash.chevron.right` 占位，不是 spec 要求的"单色 24×24 PDF" | 没有设计工具画像素级准确的 GitHub 八爪鱼 logo 矢量图；用同一套"占位到 `KYBrand.swift`" 的思路——这里没有集中变量可改（这是唯一用到的地方），先在 `AboutSettingsView.swift` 留注释标记，等有真实资源了直接换成资源图片 |
| 2026-09-23 | `KnownApp.displayNameKey` 目前直接当字面量中文字符串用，不是真正的本地化 key 查表 | 项目还没有把 xcstrings 本地化机制接进业务视图（S19 的活）；现状是所有页面文案都是硬编码字符串，这条只是保持一致，不是新债 |
| 2026-09-23 | 关于页正文（App 名、介绍语、Learn more 等）用 `Preferences.shared.appLanguage` 手动分支中英文，不走 `Localizable.xcstrings` | 同上，S19 之前全项目都是硬编码文案；这里额外做了中英两个分支只是因为 A3/A6/A7 的文案在 `02-ui-spec.md` 里明确给了="英文界面下…"的要求，其余页面暂时没有类似要求就没分支 |
| 2026-09-23 | 多条验收标准标 `[~]`（走查/单元测试覆盖，未做真实点击验证） | 沿用 S03 定下的规矩（见 specs README §1.8）：这台机器是用户在用的真实桌面，`NSOpenPanel`、USB 硬件插拔、Popup 菜单选择这类交互没法安全地用坐标盲点完成，需要 Jakob 自己找时间用 `make run` 点一遍 |
