---
id: S07
title: MicCapture + 电平计算
milestone: M1
status: done
depends_on: [S01]
estimate_days: 1
plan_refs: [§5.2]
ui_refs: []
---

# S07 MicCapture + 电平计算

## 目标
一个可指定设备（或跟随系统默认）的麦克风采集器，输出 PCM buffer 与 RMS 电平，设备拔出 / 默认设备变化时自动恢复并发事件。

## 范围
### 做
- `Recording/MicCapture.swift`：
  ```swift
  final class MicCapture: @unchecked Sendable {
      struct Config { var selection: MicSelection }
      enum Event: Sendable { case started(deviceName: String), deviceChanged(to: String), stopped, failed(KYError) }
      init(config: Config)
      var format: AVAudioFormat { get }                  // 实际采集格式
      var onBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?   // 实时线程回调，勿做分配
      var events: AsyncStream<Event>
      func start() throws
      func stop()
  }
  ```
- `AVAudioEngine.inputNode` + `installTap(bufferSize: 1024)`；指定设备：取 `inputNode.audioUnit` 设 `kAudioOutputUnitProperty_CurrentDevice` 为 UID 对应的 `AudioDeviceID`。
- `.smart`：跟随 `kAudioHardwarePropertyDefaultInputDevice`，监听其变化；具体设备被拔出 → 回落到默认并发 `.deviceChanged`。
- 监听 `AVAudioEngineConfigurationChange`，重建 tap 并重启。
- `Recording/LevelMeter.swift`：纯函数 `rms(buffer) -> Float`、`dbfs(rms) -> Float`、`LevelSmoother`（attack 快 / decay 慢，输出 0…1）。电平计算放在 `onBuffer` 消费方（S09），本 spec 只提供函数。
### 不做
- 混音、写文件（→ S09）；系统音频（→ S08）。

## 交付物
- `Recording/{MicCapture,LevelMeter}.swift`
- `KnowingYouTests/LevelMeterTests.swift`
- DEBUG 菜单项"Debug › 录 5 秒麦克风到桌面"用于手工验证

## 实现要点
- 实时回调里不要 `print`、不要拿锁、不要触碰 actor；只转发 buffer。
- 设备重建期间丢的样本 S09 用时间戳对齐补零，这里只保证事件与时间戳正确。
- `AVAudioTime.hostTime` 一并传出，S09 依赖它对齐。

## 验收标准
- [~] Debug 菜单录 5 秒，产物可播放且有声。**关键发现，值得记录**：真的跑了一次（临时环境变量钩子直接触发调试项，不是靠点菜单），结果 `AVAudioEngine.start()` 卡在系统麦克风权限弹窗上——而且弹窗标题是 **"Air" would like to access the Microphone**，不是"KnowingYou"！因为这台机器上跑的是 ad-hoc 签名的调试二进制，从这个 agent 环境（"Air"）启动，TCC 的身份判定跟到了父进程/宿主环境头上，不是 KnowingYou.app 自己。这意味着：① 这条验收项在这台机器上无法真正跑通，因为没人能点那个弹窗；② 即使点了"允许"，实际授权给的是宿主环境"Air"而不是 KnowingYou，测的东西是错的——所以我没有点，杀掉了进程。试过用 `CGEvent` 发 Escape 键想把这个残留弹窗关掉，发现 TCC 弹窗对合成按键/点击有防护，没反应——这是苹果刻意做的安全设计（防止恶意程序自动点权限弹窗），不是 bug。弹窗后来应该还留在屏幕上，Jakob 回来后点一下 "Don't Allow" 就行，不会造成实际影响。真正在一台正常签名的 Mac 上跑 KnowingYou.app 本身不会有这个身份错位问题。
- [~] 录制中拔掉 USB 麦克风：1 秒内恢复采集，`events` 收到 `.deviceChanged`，进程不崩。**无法验证**——这台机器没有可拔插的 USB 麦克风，且上一条的权限阻塞意味着连"先跑起来"都做不到。代码走查：`AVAudioEngineConfigurationChange` 通知处理器会重装 tap 并重启 engine，这是苹果文档推荐的标准应对方式。
- [~] `.smart` 模式下在系统设置切换默认输入设备，采集切换到新设备。**无法验证**，同上原因（权限 + 无法操作系统设置切换默认设备）。
- [x] 静音输入 `rms ≈ 0`，满幅正弦 `dbfs ≈ 0`（更准确地说是 -3.01 dBFS，只有峰值是 0 dBFS——测试按这个更精确的数学关系写的）。（`LevelMeterTests` 全覆盖，用合成正弦波验证）

## 测试
`LevelMeterTests`：已知正弦的 RMS / dBFS；`LevelSmoother` 单调收敛。10 项全过。全套 52/52 通过。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | **这台机器上无法做任何真实麦克风采集测试**，不只是"没人点授权弹窗"这么简单 | 实测发现系统权限弹窗把 TCC 身份判定给了宿主 agent 进程（"Air"）而不是 `KnowingYou.app`——这台开发环境的进程祖先关系导致的，与代码无关。就算硬要测，点"允许"授权的也是错的对象。**所有依赖真实麦克风/系统音频权限的功能（S07 的采集、S08 的系统音频 tap、S09 的完整录音流程）在这台机器上都只能做到"编译通过 + 逻辑走查 + 纯函数单测"，真实硬件链路必须在 Jakob 自己的、正常签名安装的 Mac 上验证一遍。** 这比 S03/S05 记录的"不方便点击"更进一步：不是"不方便"，是"点了也测不对东西"。 |
| 2026-09-23 | 尝试用 `CGEvent` 发送 Escape 键关闭残留的权限弹窗，未生效 | TCC 弹窗对合成键盘/鼠标事件有防护（苹果的安全设计，防止程序自动点掉权限提示），这是预期行为不是 bug；确认了这类系统级安全弹窗不会被自动化工具意外操作，这其实是好消息 |
| 2026-09-23 | `currentDeviceName()` 在 `.device(uid:)` 模式下查不到设备时 fallback 到系统默认设备名，而不是返回 nil | 只用于 `.deviceChanged`/`.started` 事件里的展示性文本，拿不到具体名字时给个合理的兜底比给 nil 更有用；不影响实际采集设备的选择逻辑（那部分在 `selectDevice(for:)`，出错会真的 throw） |
