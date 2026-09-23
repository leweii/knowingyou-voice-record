---
id: S06
title: Spike：Process Tap + 麦克风占用检测验证
milestone: M1
status: todo
depends_on: [S01]
estimate_days: 2
plan_refs: [§3, §5.1, §5.2, §9 "spike", §11]
ui_refs: []
---

# S06 Spike：Process Tap + 麦克风占用检测验证

## 目标
在正式写 S08 / S12 之前，用一个独立的命令行工具在真机上验证两件没有官方文档的事：（a）全局 Process Tap 排除自身能录到系统声音；（b）Core Audio 进程对象能读出"哪个 bundle id 正在用麦克风"。产出一份结论报告，直接决定 S08 / S12 / S13 的实现细节。**时间盒 2 天，到点就写报告。**

## 范围
### 做
- `Spikes/ProcessTapSpike/`：独立 SwiftPM executable（不进 app target），子命令：
  - `tap --seconds N --out file.caf`：`CATapDescription(stereoGlobalTapButExcludeProcesses: [自身])` → 私有聚合设备 → IOProc 写 CAF。
  - `who-uses-mic --watch`：每 500 ms 枚举 `kAudioHardwarePropertyProcessObjectList`，打印 `pid / bundleID / IsRunningInput`；同时注册 `kAudioDevicePropertyDeviceIsRunningSomewhere` 与进程级 `IsRunningInput` 监听，打印哪种监听真的触发。
- 在可用的机器 / 系统版本上（至少当前开发机；能拿到 14.4 / 15 / 26 各一台更好）跑下列矩阵并记录：
  - 会议软件：腾讯会议、飞书、钉钉、企业微信、Zoom、Teams、FaceTime、Chrome(Meet)、微信通话（尽量多）；
  - 每个软件：入会前后 `who-uses-mic` 输出的 bundle id（尤其 Electron Helper 的 id 形态）、进程级监听是否触发、设备级监听是否触发、退会后 `IsRunningInput` 归零延迟；
  - 麦克风：内置 / USB / 蓝牙（AirPods）各测一次设备级监听是否触发；
  - tap：播放音乐 + 会议 → CAF 有声、自己的通知音是否被排除；切换输出设备（耳机↔扬声器）tap 是否继续。
- 报告 `docs/spikes/2026-MM-DD-process-tap-spike.md`：矩阵表、每个应用的 bundle id 前缀结论、每个系统版本"哪种监听可用"、tap 遇到的错误码、**go / no-go** 与对 S08 / S12 / S13 的具体修改建议。
### 不做
- 任何可复用的 app 代码（允许 S08 复制粘贴，但 spike 代码本身不追求质量）。

## 交付物
- `Spikes/ProcessTapSpike/Package.swift` + 源码
- `docs/spikes/2026-MM-DD-process-tap-spike.md`
- 把确认的 bundle id 前缀写回 S12 的默认清单表

## 实现要点
- 参考 insidegui/AudioCap 的 `ProcessTap.swift` / `AudioProcessController.swift`，保留 license 头。
- 首次跑 `tap` 会弹"系统音频录制"授权；记录授权前的错误码，S08 用它做权限探针。
- 记录 macOS 26 上进程级监听是否触发（计划 §5.1 第 7 点已知不触发，需实证）。

## 验收标准
- [ ] 报告存在，矩阵至少覆盖 4 个会议软件 × 开发机系统版本。
- [ ] 报告对每个测过的应用给出 bundle id 前缀与"是否需要 Helper 归并"。
- [ ] 报告写明设备级监听、进程级监听、轮询三种方式在每个测过系统版本上的可用性。
- [ ] 报告写明 tap 的权限错误码与切换输出设备时的行为。
- [ ] 明确 go / no-go；若 no-go，写出备选（ScreenCaptureKit 音频）的影响评估。

## 测试
无自动化。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
