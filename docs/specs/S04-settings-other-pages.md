---
id: S04
title: 录音 / 快捷键 / 通知 / 关于 四页静态还原
milestone: M0
status: todo
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
- [ ] 四页分别与 `02/03`、`04`、`05`、`06` 截图对比，元素位置、行高、按钮尺寸误差 ≤2 pt；文案与 §12 替换表一致。
- [ ] 插拔 USB 麦克风，麦克风 Popup 列表实时更新；选具体设备后说明条消失，重启后保持。
- [ ] 应用列表 toggle 与"添加应用…"持久化；未安装应用图标灰显。
- [ ] 关于页版本号与 `project.yml` 一致；`KYIsPrerelease` 切换控制 Beta 胶囊。
- [ ] 快捷键页 K2 关闭后三个按钮灰显。

## 测试
`AudioDevicesTests`：枚举结果每项 UID 非空；`hasInput` 判定正确（内置麦克风为真）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
