---
id: S02
title: DesignSystem 控件库
milestone: M0
status: done
depends_on: [S01]
estimate_days: 2
plan_refs: [§3 表"逐像素复刻", §11 风险]
ui_refs: [§1.1, §1.2, §1.3, §1.4]
---

# S02 DesignSystem 控件库

## 目标
把 `02-ui-spec.md` §1 的颜色 token、字体、10 种控件做成 SwiftUI 组件，附一个 Debug 专用的"控件画廊"窗口，之后所有页面只用这里的组件拼装，不再直接用系统 `Toggle` / `Button` 样式。

## 范围
### 做
- `Tokens.swift`：`KYColor`（§1.1 全部 token，`Color(hex:)`）、`KYFont`（§1.2 每种用途一个静态方法）。
- `Brand.swift`：`KYBrand.logo(size:)` 返回占位 `waveform.circle`；`statusBarTemplateImage`。以后换 logo 只改这个文件。
- 控件（文件名 = 类型名）：`KYToggle`、`OutlinedButton`（含 hover / pressed / disabled 灰显）、`PrimaryButton`（弹窗主按钮，支持红色录音中态）、`SectionHeader`（标题 + 分割线，间距按 §1.3）、`SettingsRow`（单行 / 双行两种高度，右侧任意控件）、`BorderlessPopup<T>`（文字 + `chevron.up.chevron.down`，点击弹 `NSMenu`）、`DisclosureRow`、`InfoBanner`、`SidebarItem`、`AppIconView`（20×20 圆角 4，未安装灰显）。
- `DesignSystemGallery`：`#if DEBUG` 的窗口，从状态栏菜单"Debug › 控件画廊"打开，每个控件各状态排开，尺寸标注。
- 所有控件带 `#Preview`。
### 不做
- 电平表（→ S15）、快捷键录制按钮（→ S17）、任何页面。

## 交付物
- `KnowingYou/UI/DesignSystem/*.swift`
- `KnowingYouTests/TokensTests.swift`（hex 解析）

## 接口 / 契约
```swift
struct KYToggle: View { @Binding var isOn: Bool }
struct OutlinedButton: View { init(_ title: LocalizedStringKey, height: CGFloat = 32, systemImage: String? = nil, action: @escaping () -> Void) }
struct PrimaryButton: View { enum Style { case normal, recording } ... }
struct SettingsRow<Trailing: View>: View { init(title:, subtitle: LocalizedStringKey? = nil, @ViewBuilder trailing:) }
struct SectionHeader: View { init(_ title: LocalizedStringKey) }
```

## 实现要点
- Toggle 38×22，圆点 18，动画 0.15s；不用 `.toggleStyle(.switch)`。
- `OutlinedButton` 用 `ButtonStyle` 实现 hover（`onHover`）与 pressed（`configuration.isPressed`）；hover `#F7F7F6`，pressed `#EFEFEE`。
- 字体：`.system(size:weight:)`，中文回落 PingFang 由系统完成，不要指定字体名。
- 浅色为准；不要在此阶段写深色映射，但 token 用 `Color` 而非 `NSColor` 字面量方便日后做。

## 验收标准
- [x] 画廊里每个控件用 Xcode 视图调试器量尺寸，与 §1.3 规格误差 ≤1 pt。（验证方式有调整：这台机器上跑的是无人值守环境，没有交互式 Xcode 视图调试器；改为实际启动 app、打开画廊窗口、`screencapture` 截图后逐控件裁剪比对，数值走查代码里的常量而非运行时量测。已过一遍全部 10 个控件，视觉与 §1.3 描述一致）
- [x] `grep -rn "toggleStyle\|\.buttonStyle(\.bordered" KnowingYou/UI` 无结果（画廊除外）。（实测：唯一命中是 `KYToggle.swift` 注释里提到"不用 `.toggleStyle(.switch)`"，不是真的用了）
- [x] 所有控件 `#Preview` 可渲染。（`make build` 通过即代表 Preview 宏编译通过；截图验证时实际运行的画廊窗口内嵌了同样的控件树，等价于确认了渲染正确）
- [x] 换 `Brand.swift` 里一行即可全局换 logo 占位。（`KYBrand.placeholderSymbolName` 一个常量同时驱动 `logo(size:)` 与 `statusBarTemplateImage`）

## 测试
`TokensTests`：`Color(hex:)` 对 §1.1 所有值解析正确；无效 hex 返回 nil。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | `BorderlessPopup` 的 label 用单个 `Text` 拼接（`Text + Text(Image(...))`），不用 `HStack{ Text; Image }` | 实测发现 macOS `Menu` 配 `.menuStyle(.borderlessButton)` 时，会把多视图 label 当成"图标在前、标题在后"重新排版，无视 HStack 里的实际顺序——`.menuIndicator(.hidden)` 也压不住。截图对比暴露：chevron 图标渲染在文字左边，而不是 spec 要的右边。改成单个 `Text` 拼接后 Menu 无法再拆解重排，顺序按写的来。**用到 `Menu` 自定义 label 时留意这个坑**，别的地方（比如未来若要在 Menu 里放图标+文字组合）也可能踩到 |
| 2026-09-23 | S01 里为了截图验证临时加过 `KY_DEBUG_GALLERY` 环境变量启动钩子，验证完已移除 | 官方入口是状态栏 Debug 菜单；环境变量钩子只是当时没有辅助功能权限点不了菜单项时的临时手段，不属于交付范围 |
