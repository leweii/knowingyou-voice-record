---
id: S07
title: MicCapture + 电平计算
milestone: M1
status: todo
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
- [ ] Debug 菜单录 5 秒，产物可播放且有声。
- [ ] 录制中拔掉 USB 麦克风：1 秒内恢复采集，`events` 收到 `.deviceChanged`，进程不崩。
- [ ] `.smart` 模式下在系统设置切换默认输入设备，采集切换到新设备。
- [ ] 静音输入 `rms ≈ 0`，满幅正弦 `dbfs ≈ 0`。

## 测试
`LevelMeterTests`：已知正弦的 RMS / dBFS；`LevelSmoother` 单调收敛。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
