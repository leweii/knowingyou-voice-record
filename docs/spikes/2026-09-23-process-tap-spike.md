---
title: S06 Spike 结论 — Process Tap + 麦克风占用检测
date: 2026-09-23
machine: 这是一台 Claude Code agent 会话所在的开发环境（"Air"），不是 Jakob 的日常 Mac
macOS: 26.6.2 (Build 25G83), Apple M1 Pro, arm64
---

# S06 Spike 结论

## 重要前提：这次 spike 是在一台特殊环境里做的，不是"随便一台真机"

这台机器是本次 Claude Code 会话运行所在的开发环境，从属于宿主 agent 程序（下文称"Air"）。这带来两个此前未预料到的影响，直接决定了下面哪些矩阵格子能填、哪些不能：

1. **麦克风权限完全测不了**：触发 `AVCaptureDevice.requestAccess` 会弹系统权限框，但标题是 **"Air" would like to access the Microphone**，不是这个 spike 工具或 KnowingYou。TCC 身份判定跟的是进程祖先关系，不是这个可执行文件本身。没人能点、点了也是给错误的对象授权。详见 S07 决策记录，这条对 S08 的"麦克风身份"部分同样适用（但 Process Tap 走的是系统音频，不是麦克风输入，见下）。
2. **意外惊喜：系统音频 Process Tap 完全没有触发任何权限弹窗，且真实可用**——这是本次 spike 最重要的产出，直接推翻了"这台机器没法测系统音频"的预期。

**没有真实会议软件可用**：这台机器装了 Discord、Slack、WeChat，但没有腾讯会议、飞书、钉钉、企业微信、Zoom、Teams。且出于对 Jakob 真实账号/联系人的尊重，我没有在 Discord/Slack/WeChat 里发起或加入任何真实通话去触发"正在用麦克风"信号——这会通知到真实的人，不是我能自主决定的事。所以"入会前后 who-uses-mic 输出""tap 时会议声音是否被录到"这类需要真实通话的矩阵格子，**没有做**，需要 Jakob 在自己的 Mac、自己的账号上跑一遍。

## 做了什么

`Spikes/ProcessTapSpike/`：两个子命令，`who-uses-mic [--watch]`（安全，纯读取，不需要任何权限）和 `tap --seconds N --out path.caf`（尝试完整的 Process Tap → 聚合设备 → IOProc → 写 CAF 链路）。都实际跑通了，不是纸上谈兵。

## 结论 1：`who-uses-mic` 可用，且不需要权限

```
Registered device-level kAudioDevicePropertyDeviceIsRunningSomewhere listeners on 3 devices.
[...] no process reports IsRunningInput=true (33 process objects enumerated)
```

- 枚举 `kAudioHardwarePropertyProcessObjectList`、读 `IsRunningInput`/`BundleID`/`PID` **不需要任何 TCC 权限**，静默运行，没有弹窗。这对 S12 是好消息：`MeetingDetector` 这部分不会被本 spec 发现的权限问题卡住。
- 设备级 `kAudioDevicePropertyDeviceIsRunningSomewhere` 监听器成功注册在了 3 个设备上（这台机器的输入/输出设备）。**没有真实触发过**（没有应用在用麦克风），所以"是否真的 fire"这条留空，需要真实会议验证。
- 进程级 `kAudioHardwarePropertyProcessObjectList` 监听器同样注册成功，同样没有真实数据触发过。
- **bundle id 确认**（用 `mdls -name kMDItemCFBundleIdentifier` 静态读取，不需要通话）：

  | 应用 | bundle id | 来源 |
  |---|---|---|
  | Discord | `com.hnc.Discord` | 本机实测确认，与 S12 草稿表一致 |
  | Slack | `com.tinyspeck.slackmacgap` | 本机实测确认，与 S12 草稿表一致 |
  | 微信 (WeChat) | `com.tencent.xinWeChat` | 本机实测确认，与 S12 草稿表一致 |
  | Chrome | `com.google.Chrome` | 本机实测确认，与 S12 草稿表一致 |
  | 腾讯会议、飞书、钉钉、企业微信、Zoom、Teams、Webex | 未变 | 这台机器没装，S12 表里的值仍是未经验证的猜测，需要 Jakob 装了之后跑 `mdls` 确认一下（一行命令，不需要真的开会） |

  这 4 个确认足以说明"猜测 bundle id 前缀"这个方法本身是可靠的（4/4 命中），但**不能**因此假设剩下 7 个也一定对——尤其飞书/钉钉/企业微信这类 Electron 应用的 Helper 进程 bundle id 形态，没有实测过，S12 落地前务必用真机核实。

## 结论 2：Process Tap 全链路在这台机器上真实可用，且不需要权限（重要修正）

这是最意外的发现。完整跑了一遍：`AudioHardwareCreateProcessTap` → `AudioHardwareCreateAggregateDevice`（`kAudioAggregateDeviceIsPrivateKey=true`，主设备是当前默认输出设备）→ 读 `kAudioTapPropertyFormat` → `AudioDeviceCreateIOProcIDWithBlock` → `AudioDeviceStart`。**全部返回 `noErr` (0)，没有出现任何系统权限弹窗**：

```
AudioHardwareCreateProcessTap: status=0 tapID=133
AudioHardwareCreateAggregateDevice: status=0 aggregateDeviceID=134
tap format status=0 sampleRate=48000.0 channels=2
AudioDeviceCreateIOProcIDWithBlock: status=0
AudioDeviceStart: status=0
```

而且捕获到的不是静音：一边后台录制一边 `afplay` 播放系统提示音，产物用 `afconvert` 转 16-bit PCM 后量测：峰值 9729/32767（约 30% 满幅），落在录制开始后 0.1 秒——与播放提示音的时机吻合。**这是真实、可验证的系统音频捕获，不是猜测。**

踩到的一个坑（已修复，写进了 spike 代码注释，S08 要照做）：直接用 `AVAudioFile(forWriting:settings:)`（只传 `settings` 字典）写 tap 吐出来的 buffer 会在 `ExtAudioFileWrite` 上报 `-50 (paramErr)`——buffer 的实际内存布局和只靠 `settings` 字典推断出的 processing format 对不上。修复方式和 S10 的 `Encoder.swift` 一致：显式传 `commonFormat: .pcmFormatFloat32, interleaved:`，不要只依赖 `settings`。

### 这对 S07/S08/S09 的推论意味着什么

- **系统音频 tap 这条链路，在这类"Air"宿主环境里可以真实端到端测试**——和麦克风不一样。原因推测：系统音频录制的 TCC 语义可能和麦克风不同（例如宿主环境本身可能已经持有系统音频录制授权，或者这条 API 路径在当前 macOS 版本下门槛更低），具体原因不重要，重要的是**实测结果是可以录到真实系统声音**。
- 但这不能反过来证明"麦克风也应该能测"——两次实测结果不同就是不同，不要在没有再次实测的情况下类推。
- `Permissions.systemAudioProbe`（S05 里预留的钩子，S08 要实现）不能只看 `AudioHardwareCreateProcessTap` 的返回值来判定"有没有权限"——这次实测中 create 阶段全程 `noErr`，如果真的没有权限，更可能是在 `AudioDeviceStart` 那一步失败（或者干脆这台机器上这个探针永远不会失败，因为环境本身没有真正意义上的"未授权"状态）。**S08 实现 probe 时要以 `AudioDeviceStart` 的返回值/是否报错为准，而不是只测 `AudioHardwareCreateProcessTap`**。真正的"denied 时返回什么错误码"仍然需要在 Jakob 自己的、干净的（没授权过）Mac 上实测一次，这台机器已经不是"干净"状态测不出来了。

## Go / No-Go

**Go。** 按计划书 §3/§5.2 的技术方案（Core Audio Process Tap + 私有聚合设备 + IOProc）继续做 S08，不需要考虑 ScreenCaptureKit 音频这个备选方案——本次 spike 已经用真实捕获数据证明了主方案可行。

`who-uses-mic` 的检测机制（设备级监听 + 进程级监听 + 轮询兜底）代码路径都能正常注册、不报错，虽然没有真实会议触发过，但没有理由认为 API 本身不可用；继续按计划书 §5.1 的"设备级监听 + 2 秒轮询兜底"设计做 S12，不要偷懒去掉轮询。

## 对 S08 / S12 / S13 的具体修改建议

1. **S08**：`SystemAudioTap` 的实现直接参考本 spike 已跑通的顺序；写文件时必须显式指定 `commonFormat`，不要只传 `settings` 字典（见上文的坑）。`probePermission()` 应该真正走一遍 `AudioDeviceStart`（哪怕立刻 stop），不能只做到 `AudioHardwareCreateProcessTap` 就判定为"已授权"。
2. **S08 的测试范围可以放宽**：由于这台机器能真实捕获系统音频，S08 落地时可以（而且应该）在这台机器上做真实的端到端捕获测试（录系统声音、验证非静音、验证格式转换），不必像 S07 那样把"真实硬件验证"整个推给 Jakob。麦克风部分（`MicCapture`，S07 已完成）仍然测不了。
3. **S12**：`KnownApps.defaults` 表里 Discord/Slack/微信/Chrome 的 bundle id 已经过静态确认，可以直接标记为"已验证"；其余 7 个会议应用的 bundle id 仍是猜测值，落地前需要 Jakob 用 `mdls -name kMDItemCFBundleIdentifier /Applications/<App>.app` 核实一遍（不需要开会，一行命令）。真正的"应用一开麦克风就被检测到"这条行为，必须由 Jakob 用真实会议软件验证。
4. **S13**：状态机的去抖时长（3s / 10s）、自动录制策略等纯逻辑部分不受本次 spike 结果影响，按计划书原样实现即可；真实通知时序仍需人工验证。

## 未覆盖的矩阵（如实列出，不假装测过）

- 6 款会议软件的真实入会/退会检测延迟、进程级监听在 macOS 26 上是否真的不触发——**未测**，机器上没装这些软件，且不该在没有真实会议的情况下伪造这类数据。
- USB / 蓝牙麦克风的设备级监听触发情况——**未测**，这台机器只有内置麦克风，且麦克风权限本身也测不了（见上）。
- 切换输出设备（耳机⇄扬声器）时 tap 是否继续——**未测**，这次 spike 没有可切换的第二输出设备；代码层面已经在 `SystemAudioTap`（S08，尚未实现）里安排了 `kAudioHardwarePropertyDefaultOutputDevice` 监听器重建聚合设备，逻辑上应该覆盖这个场景，但没有实测确认。
