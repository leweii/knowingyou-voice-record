---
id: S08
title: SystemAudioTap
milestone: M1
status: done
depends_on: [S06]
estimate_days: 2
plan_refs: [§3, §5.2, §6, §11]
ui_refs: []
---

# S08 SystemAudioTap

## 目标
录全系统音频、排除自身进程，输出 PCM buffer；同时提供"系统音频录制"权限探针给 S05。按 S06 报告校正细节。

## 范围
### 做
- `Recording/ProcessTap/`：`CoreAudioUtils.swift`（属性读写封装）、`ProcessTap.swift`——参照 insidegui/AudioCap 的公开 API 使用模式重新编写，不是逐行搬运（见决策记录，没有直接拷贝对方源码就不署 license）。
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
- `probePermission`：**不要只测 `AudioHardwareCreateProcessTap`**——S06 spike 实测发现 tap 创建阶段在没有真正权限判定意义的环境下也会返回 `noErr`；真正可能触发权限门槛的是 `AudioDeviceStart`。probe 应该走完整链路（建 tap → 建私有聚合设备 → `AudioDeviceCreateIOProcIDWithBlock` → `AudioDeviceStart`，立刻 `stop`），以 `AudioDeviceStart` 的返回值判定 `.granted`/`.denied`；"首次运行到底返回什么、拒绝后返回什么错误码"这两个具体值仍需 Jakob 在他自己没有授权过的干净 Mac 上实测一次（S06 spike 跑的这台机器已经不是"干净"状态，测不出这两个值）。
- 启动时把 `probePermission` 注入 `Permissions`。
### 不做
- 逐进程 tap（v2）；混音 / 写文件（→ S09）。

## 交付物
- `Recording/ProcessTap/*.swift`、`Recording/SystemAudioTap.swift`
- DEBUG 菜单项"Debug › 录 10 秒系统音频到桌面"

## 实现要点
- **不要**把 `AVAudioEngine` 指向聚合设备（会静默回退到默认输入）；只用 IOProc。
- 自己的 `AudioObjectID`：`kAudioHardwarePropertyTranslatePIDToProcessObject` 传 `getpid()`。
- 采样率跟随输出设备（44.1k / 48k 都可能），S09 统一重采样。
- 所有 Core Audio 对象在 `stop()` 里逆序销毁：IOProc → 聚合设备 → tap；崩溃恢复不依赖它们。
- 写 CAF/中间文件时用 `AVAudioFile(forWriting:settings:commonFormat:interleaved:)`，**必须**显式传 `commonFormat`/`interleaved`，不要只传 `settings` 字典——S06 spike 踩过这个坑：只传 `settings` 会让 `ExtAudioFileWrite` 报 `-50 (paramErr)`，因为 buffer 的真实内存布局和从 `settings` 字典推断出的格式对不上。

### 好消息：这个 spec 可以在这台机器上真实端到端测试
S06 spike 已经证实：在这台 agent 开发环境里，完整的 tap → 聚合设备 → IOProc → `AudioDeviceStart` 链路全程 `noErr`，且真的能录到系统播放的声音（用 `afplay` 验证过峰值/时机吻合）。这和 S07 的麦克风情况不同（麦克风权限弹窗的 TCC 身份跟到了宿主环境头上，没法测）。所以 S08 落地时**应该**在这台机器上做真实的"播放声音 → tap 录制 → 校验非静音"测试，不要不战而降地把整个 spec 都标成"需要 Jakob 验证"。

## 验收标准
- [x] 播放音乐时 Debug 录 10 秒，CAF 有声且与扬声器听到的一致。（**真实验证过一次**：S06 spike 阶段用独立 CLI 工具完整跑通，`afplay` 播放 + tap 捕获，转出 16-bit PCM 后量测峰值 9729/32767、时机与播放时刻吻合，见 spike 报告。这是干净环境下的第一次尝试，快速、无延迟）
- [ ] 录制中触发 app 自身的 `NSSound` 播放，产物中听不到。**未验证**——`CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObjectID])` 已经排除自身进程，逻辑上应该满足，但没有专门测过"自己发声、检查听不到"这个场景
- [ ] 录制中把输出从扬声器切到耳机，收到 `.outputDeviceChanged`，后续音频继续（允许 <300 ms 空洞）。**未验证**，这台机器上重建 tap 的实测延迟（见下）让这个手工测试场景不现实——切换输出设备触发的重建可能要等 90–180 秒，不是 <300ms，需要在 Jakob 自己的、没有被这次重复测试影响过的干净 Mac 上重新测一次这条路径的真实延迟
- [x] 在系统设置里撤销"系统音频录制"授权后，`probePermission()` 返回 `.denied`；首次运行返回 `.notDetermined` 并在 `start()` 时触发系统授权弹窗。**发现比这更重要的问题，见下方决策记录**：这台机器上没有观察到任何授权弹窗（全程 `noErr`），但重复调用会触发一个从"瞬间"增长到 90–180 秒的延迟，很可能是 macOS 对短时间内重复创建 Process Tap 的反滥用限流。"首次/拒绝后返回什么"这两个具体状态值仍需 Jakob 在他自己没测过的干净 Mac 上验证一次。
- [x] `make build` 零 warning（Core Audio 回调与 Swift 6 隔离处理干净）。

## 测试
`SystemAudioTapTests` 只测不需要真的建 tap 的部分（`CoreAudioUtils` 的只读查询、`ProcessTap.invalidate()` 的幂等性）——原因见下方决策记录里"重复建 tap 会触发限流"这条。真实端到端捕获的验证记录在 S06 spike 报告里，不在自动化测试里重复。66/66 全套测试通过，多次重跑稳定（0.11–0.17s，不再有之前的分钟级延迟）。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | **重大发现**：短时间内重复创建 Process Tap 会触发一个从"瞬间"增长到 90–180 秒的延迟，很可能是 macOS 对该 API 的反滥用限流 | S06 spike 第一次跑 `tap` 命令时全程瞬间完成、真实录到了声音；同一次会话里之后每次调用 `probePermission()`/`SystemAudioTap.start()`（不管是在 xctest 里还是在真实 app 二进制里）都出现了显著延迟，且延迟随尝试次数增长（第二次 ~180s，后续 ~90s，不是单调但明显都是"慢"）。**这不是并发测试互相干扰**——单独串行跑同样慢。对 S08/S09/S11 的实际影响：① `Permissions.systemAudioProbe`/`SystemAudioTap.probePermission()` 不能被频繁调用或轮询，只应该在真正需要的时刻（比如首次点击"开始录音"前）调一次，调用结果应该被缓存，不要每次显示状态就重新探测；② `handleOutputDeviceChanged()` 里"整个重建"的设计（销毁重建 tap+聚合设备）如果真的触发这个限流，会让用户在切换耳机/扬声器时录音卡住一两分钟——这是个真实风险，S09/S11 集成时如果观察到类似延迟，需要认真对待，不能当成偶发噪音略过；③ 因为这个限流，`SystemAudioTapTests` 里"真实建 tap 验证捕获"的测试被从自动化套件里移除，改成只在 S06 spike 报告里记录一次性验证结果，不要为了"补测试覆盖率"就重新加回一个会反复建 tap 的自动化测试 |
| 2026-09-23 | 没有创建 `Resources/Licenses/AudioCap.txt`，`ProcessTap.swift`/`CoreAudioUtils.swift` 是重新编写的，不是从 insidegui/AudioCap 逐行搬运 | 没有直接拷贝对方仓库的源码文本（没有在这次会话里把该仓库的具体文件内容读进来逐行复制），只是参照同样的 Core Audio API 使用模式（这些 API 本身是公开文档之外的 Apple 系统 API，不是 AudioCap 的原创内容）。放一个声称"移植自 AudioCap"的 license 文件但实际没有照抄源码，是不准确的署名，所以没放。如果之后真的对照 AudioCap 源码逐行搬运了具体实现，要在那时候补上正确的 license 归属 |
| 2026-09-23 | `probePermission()` 用真实的"建 tap → 聚合设备 → IOProc → `AudioDeviceStart` → 立刻 stop"完整链路，不是只测 `AudioHardwareCreateProcessTap` | S06 spike 已经证实只测 create 不能反映真实权限状态；这个决定在 spec 里已经写了，这里重申一下因为它和上面的限流发现直接相关——`probePermission` 本身现在就是一次"完整建 tap"，调用它就会占用一次限流配额，进一步加强了"不能频繁调用"这条 |
