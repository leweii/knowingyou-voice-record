---
id: S02
title: DesignSystem 控件库
milestone: M0
status: todo
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
- [ ] 画廊里每个控件用 Xcode 视图调试器量尺寸，与 §1.3 规格误差 ≤1 pt。
- [ ] `grep -rn "toggleStyle\|\.buttonStyle(\.bordered" KnowingYou/UI` 无结果（画廊除外）。
- [ ] 所有控件 `#Preview` 可渲染。
- [ ] 换 `Brand.swift` 里一行即可全局换 logo 占位。

## 测试
`TokensTests`：`Color(hex:)` 对 §1.1 所有值解析正确；无效 hex 返回 nil。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
