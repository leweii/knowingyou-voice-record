---
id: S08
title: SystemAudioTap（移植 AudioCap）
milestone: M1
status: todo
depends_on: [S06]
estimate_days: 2
plan_refs: [§3, §5.2, §6, §11]
ui_refs: []
---

# S08 SystemAudioTap（移植 AudioCap）

## 目标
录全系统音频、排除自身进程，输出 PCM buffer；同时提供"系统音频录制"权限探针给 S05。按 S06 报告校正细节。

## 范围
### 做
- `Recording/ProcessTap/`：从 insidegui/AudioCap 移植 `CoreAudioUtils.swift`（属性读写封装）、`ProcessTap.swift`；保留原 license 头；`Resources/Licenses/AudioCap.txt`。
- `Recording/SystemAudioTap.swift`：
  ```swift
  final class SystemAudioTap: @unchecked Sendable {
      enum Event: Sendable { case started(format: AVAudioFormat), outputDeviceChanged, stopped, failed(KYError) }
      var onBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
      var events: AsyncStream<Event>
      func start() throws          // 建 tap → 建私有聚合设备 → IOProc
      func stop()
      static func probePermission() async -> PermissionStatus   // 注入 Permissions.systemAudioProbe
  }
  ```
- `CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObjectID])`，`muteBehavior = .unmuted`，`isPrivate = true`。聚合设备 `kAudioAggregateDeviceIsPrivateKey = true`，主设备为当前默认输出设备 UID，tap 列表含此 tap 的 UUID。
- `AudioDeviceCreateIOProcIDWithBlock` 中把 `AudioBufferList` 包成 `AVAudioPCMBuffer`（格式来自 `kAudioTapPropertyFormat`），附 `AudioTimeStamp.mHostTime`。
- 监听 `kAudioHardwarePropertyDefaultOutputDevice` 变化 → 销毁并重建聚合设备（tap 可复用），发 `.outputDeviceChanged`。
- `probePermission`：尝试创建 tap，成功即 `.granted` 并立刻销毁；按 S06 记录的错误码区分 `.denied` / `.notDetermined`。
- 启动时把 `probePermission` 注入 `Permissions`。
### 不做
- 逐进程 tap（v2）；混音 / 写文件（→ S09）。

## 交付物
- `Recording/ProcessTap/*.swift`、`Recording/SystemAudioTap.swift`、`Resources/Licenses/AudioCap.txt`
- DEBUG 菜单项"Debug › 录 10 秒系统音频到桌面"

## 实现要点
- **不要**把 `AVAudioEngine` 指向聚合设备（会静默回退到默认输入）；只用 IOProc。
- 自己的 `AudioObjectID`：`kAudioHardwarePropertyTranslatePIDToProcessObject` 传 `getpid()`。
- 采样率跟随输出设备（44.1k / 48k 都可能），S09 统一重采样。
- 所有 Core Audio 对象在 `stop()` 里逆序销毁：IOProc → 聚合设备 → tap；崩溃恢复不依赖它们。

## 验收标准
- [ ] 播放音乐时 Debug 录 10 秒，CAF 有声且与扬声器听到的一致。
- [ ] 录制中触发 app 自身的 `NSSound` 播放，产物中听不到。
- [ ] 录制中把输出从扬声器切到耳机，收到 `.outputDeviceChanged`，后续音频继续（允许 <300 ms 空洞）。
- [ ] 在系统设置里撤销"系统音频录制"授权后，`probePermission()` 返回 `.denied`；首次运行返回 `.notDetermined` 并在 `start()` 时触发系统授权弹窗。
- [ ] `make build` 零 warning（Core Audio 回调与 Swift 6 隔离处理干净）。

## 测试
手工为主；`ProcessTapTests` 测 `AudioBufferList → AVAudioPCMBuffer` 转换（构造假 buffer）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
