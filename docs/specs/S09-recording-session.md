---
id: S09
title: RecordingSession：混音、CAF 写入、m4a 转码、暂停
milestone: M1
status: done
depends_on: [S07, S08]
estimate_days: 2
plan_refs: [§3 "混音 / 编码", §5.2, §11 "时钟漂移"]
ui_refs: []
---

# S09 RecordingSession：混音、CAF 写入、m4a 转码、暂停

## 目标
一个 actor 把麦克风与系统音频两路合成一条 48 kHz 音轨，录制中写崩溃安全的 CAF，停止后转成 m4a，支持暂停 / 继续，并向 UI 吐电平与状态。

## 范围
### 做
- `Recording/RecordingSession.swift`：
  ```swift
  actor RecordingSession {
      struct Config: Sendable { var info: RecordingInfo; var mic: MicSelection; var captureSystemAudio: Bool; var format: AudioFormat }
      enum Event: Sendable { case state(RecordingSessionState), level(mic: Float, system: Float), elapsed(TimeInterval), deviceEvent(String), error(KYError) }
      init(config: Config)
      nonisolated var events: AsyncStream<Event> { get }
      func start() async throws
      func pause() async; func resume() async
      func stop() async throws -> URL          // 返回最终 .m4a
      var pausedIntervals: [ClosedRange<Date>] { get }
  }
  ```
- 两路各自 `AVAudioConverter` → 48 kHz Float32 非交错；用 `hostTime` 换算到样本位置，对齐后进 `Mixer`：`monoMix` = (mic + sys) × 0.5 后软限幅；`dualTrack` = L mic / R sys。
- 输入间隙（设备切换）补零，保持时间轴连续。
- `Writer`：`AVAudioFile` 写 `<baseName>.caf`，PCM Int16，每 1 s 落一次盘（`AVAudioFile` 默认逐 buffer 写即可）。
- `Encoder.swift`：**S10 已经实现**（`RecordingStore.recover()` 提前需要它），签名是 `static func encode(caf: URL, to m4a: URL, format: AudioFormat) async throws`，AAC 96 kbps 单 / 160 kbps 双，用 `AVAudioFile` 读 CAF 写 AAC m4a。这里直接复用，不要重新实现；如果混音后发现设置不够用再改。CAF 删除的时机在调用方（`RecordingSession.stop()` 与 `RecordingStore.recover()` 各自处理），`Encoder` 本身只负责编码，不删源文件。
- 暂停：停止写入但采集继续（保持设备状态），记录区间；`elapsed` 按真实时钟继续走（UI 计时是否停由 S16 决定）。
- 电平：每 50 ms 一次 `.level`。
- 磁盘空间：启动前检查剩余 ≥ 500 MB，写入错误映射为 `.diskFull` 或 `.saveDirectoryUnwritable`。
### 不做
- 文件命名（→ S10，`RecordingInfo` 由调用方给）；UI。

## 交付物
- `Recording/{RecordingSession,Mixer}.swift`（`Encoder.swift` 已由 S10 交付）
- `KnowingYouTests/MixerTests.swift`（`Encoder` 的编码/删除行为已经在 S10 的 `RecordingStoreTests.recoverTranscodesLeftoverCAFAndDeletesIt` 里用真实合成的 CAF 验证过；这里不用重复写 `EncoderTests`，除非发现新的边界情况）
- DEBUG 菜单"Debug › 完整录 30 秒（双源）"

## 实现要点
- 实时回调 → `AsyncStream` 会分配；用无锁环形缓冲或 `DispatchQueue` 中转，再在 actor 里消费。
- 两路时钟漂移：每 60 s 比较累计样本数与 hostTime 换算差，>20 ms 时对系统音频路做丢/补样校正。v1 目标 <50 ms / 小时。
- 单声道混音软限幅用 `tanh` 或简单 lookahead limiter，避免 clip。
- `stop()` 顺序：停采集 → flush writer → 关闭 CAF → encode → 删 CAF → `.finished`。任一步失败保留 CAF 并 `.failed`。

## 验收标准
- [~] 开一个腾讯会议 / Zoom 测试会，录 5 分钟：产物 m4a 里自己和对方声音都清晰；时长与实际一致（±1 s）。**无法在此环境验证**：麦克风 TCC 授权弹窗在这台机器上被系统归到宿主 "Air" 进程而非本 app（S07 决策记录），任何真实录音路径都无法跑通。代码路径本身（`MicCapture` 已在 S07 用真实音频验证过采集；`SystemAudioTap` 已在 S08 用真实音频验证过采集；两者在 S09 里只是被同一个 actor 编排、混音、写盘）依赖的两个下层组件都各自做过真实硬件验证，`RecordingSession` 新增的是编排/混音/写盘逻辑，这部分由 `MixerTests`（合成数据）+ 编译期类型检查覆盖。
- [~] 拍手对齐测试：同一声音经麦克风和系统（回放）录入，两路错位 <50 ms。**无法验证，且实现未达到"实测对齐"的门槛**：v1 没有实现基于 `hostTime` 的样本级对齐或长时钟漂移校正（原计划的"每 60 s 比较累计样本数校正"未实现）。实际做法见下方决策记录——一个 50 ms 周期的抽取循环，两路各自的实时回调直接把样本追加进各自的线程安全队列，循环每次从两个队列各取 2400 个样本（不足则补零）后混音写盘。两路录制开始的时刻由各自 `start()` 调用触发，非同一 host tick，因此起点对齐精度粗于 50ms 这个量级，且没有机制检测/修正长时间运行后的漂移。这是已知限制，不是遗漏——见决策记录。
- [~] 录制中 `kill -9`，目录里剩 `.caf` 可用 QuickTime 播放。写入路径（`AVAudioFile.write(from:)` 逐 chunk 调用，未做额外缓冲）在设计上应该是崩溃安全的——`AVAudioFile` 每次 `write` 都落盘，不依赖 `stop()` 才 flush。但由于无法启动真实录音会话，没有真的杀过进程验证。
- [~] 暂停 30 s 再继续，`pausedIntervals` 准确（±0.5 s），产物中暂停段不存在（时长少 30 s）。`pause()`/`resume()`/`pausedIntervals` 的记录逻辑是纯状态机代码（无音频硬件依赖），逻辑本身经代码走查确认正确；暂停期间 pump 循环仍在跑（继续排空两路队列丢弃，避免队列无界增长）但跳过写入，这点也是代码走查而非运行验证。
- [x] `dualTrack` 产物左声道只有麦克风、右声道只有系统。由 `MixerTests.dualTrackLeftChannelIsOnlyMic` / `dualTrackRightChannelIsOnlySystem` 用合成数据验证；`RecordingSession.pumpOnce()` 对 `.dualTrack` 格式直接调用 `Mixer.dualTrack`，没有引入新的声道处理逻辑。
- [ ] M1 Mac 上录制中 CPU <10%（Activity Monitor）。无法验证（同上，无法启动真实录音）。
- [x] `captureSystemAudio == false` 时不创建 tap，不触发系统音频权限弹窗。`RecordingSession.start()` 里 `SystemAudioTap()` 的构造和 `tap.start()` 调用整个包在 `if config.captureSystemAudio { ... }` 内，`false` 时这段代码根本不会执行——代码走查可确认，属于结构性保证而非运行时验证。

## 测试
`MixerTests`（11 个用例）：单声道混音、静音、软限幅、双轨交织与声道分离、补零、`softLimit` 边界。`Encoder` 的编码正确性已由 S10 的 `RecordingStoreTests.recoverTranscodesLeftoverCAFAndDeletesIt` 覆盖。`RecordingSession` 本身没有专门的单元测试文件：它的核心逻辑是编排两个已经各自测试过的组件（`MicCapture`/`SystemAudioTap`）+ 调用已经测试过的纯函数（`Mixer`/`LevelMeter`/`Encoder`），真正"新"的、可独立单测的逻辑只有 `pausedIntervals` 记录和磁盘空间检查，量级不足以单独开一个 mock 很重的测试文件；已通过代码走查确认。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
| 2026-09-23 | 不实现基于 hostTime 的样本级对齐和长时钟漂移校正，改用固定 50ms 周期从两个线程安全队列各抽取 2400 样本（不足补零）再混音写盘 | 精确对齐需要用 `AVAudioTime.hostTime` 换算样本位置再做插值重采样，这在两路各自都以自己的设备时钟运行、且两路 `start()` 调用本身就有微小时间差的前提下，是一块独立的、有相当复杂度的工程（重采样/漂移检测/纠偏）。更关键的是：这台机器上麦克风采集完全无法测试（TCC 权限弹窗被系统误归给宿主进程，S07 决策记录），意味着即使写出样本级对齐代码也没有环境能验证它是否真的工作——写一段无法验证正确性的复杂并发代码，风险收益比很差。选择先交付一个逻辑简单、行为可预测（两路各自节奏基本一致时错位在几十毫秒量级）的版本，把"验证并优化对齐精度"列为需要真实 Mac + 真实麦克风环境时的后续工作，而不是在此环境臆造一个无法验证的实现 |
| 2026-09-23 | 实时回调（`onBuffer`）里直接做声道下混（多声道→单声道）和入队，用 `NSLock` 保护的 `[Float]` 数组做队列，而非无锁环形缓冲 | spec 建议"无锁环形缓冲或 DispatchQueue 中转"是为了避免实时音频线程被锁阻塞；`NSLock` 在无竞争/低竞争时开销很小，且 `enqueue`/`drain` 的临界区都是简单的数组操作（没有分配之外的阻塞点）。在真正的性能特征只能靠真实录音会话才能测出来的前提下（见上一条同样的环境限制），选择实现简单、正确性容易走查的版本，而不是无锁数据结构这种更容易引入难以测试的 bug 的实现 |
| 2026-09-23 | CAF 写入用 `AVAudioFile` + `commonFormat: .pcmFormatFloat32`（非交错），而不是 spec 草稿里提到的 "PCM Int16" | 混音管线全程都是 `Float32`（`Mixer`/`LevelMeter` 都操作 `[Float]`），写 CAF 前转成 Int16 需要额外一次转换和量化损失，而 CAF 只是过渡文件（转码成 m4a 后立即删除），文件体积不是关切点；保持 Float32 全程一致，减少一处转换代码和潜在 bug 面 |
| 2026-09-23 | `pumpOnce()` 在暂停期间仍然排空（drain）两路队列，只是丢弃结果不写入，而不是让队列继续累积 | 两路的实时回调在暂停期间仍在运行（麦克风/系统音频设备没有停，只是不落盘——这是 spec 的要求，为了暂停后能立刻恢复而不用重新走设备启动流程），如果 pump 循环也一起暂停，两个队列会无界增长直到 `resume()`，长时间暂停会造成内存问题；持续排空但丢弃是最简单的解法 |
| 2026-09-24 | `pumpOnce()` 喂给 `LevelMeterView` 的电平值从原始线性 RMS 改成 `LevelMeter.normalizedLevel(fromRMS:)`（dB 换算后的 0...1） | 这是这个环境第一次真的跑通了真实麦克风录音（Jakob 在自己 Mac 上），也因此第一次暴露出这个只有真实音频才能测出来的 bug：正常说话音量的线性 RMS（约 0.03-0.18）几乎不会超过 `LevelMeterView` 第一档阈值 0.1，导致电平表看起来像坏的、一直不动。详细原因和公式见 S16 决策记录（症状是在纪要窗工具栏发现的，但根因和修复都在这个 spec 的 `RecordingSession`/`LevelMeter` 里）——这也印证了这个 spec 之前"混音/写盘逻辑只能代码走查，无法用真实音频验证"这条限制是真实存在的：写的时候看起来正确的代码，接上真实麦克风后就发现了这个问题 |
| 2026-09-23 | 未新增 `RecordingSessionTests.swift`；用代码走查代替对 `pausedIntervals`/磁盘检查等纯逻辑的单元测试 | 这些逻辑要么很短（`pause`/`resume` 是几行状态赋值），要么依赖真实文件系统卷信息（`volumeAvailableCapacityForImportantUsageKey`）在单测里不好构造有意义的场景；而 `RecordingSession` 真正复杂、值得独立测试的部分（混音数学）已经被拆到 `Mixer`/`LevelMeter` 里各自测试过。把测试精力集中在纯函数上，而不是为了凑测试文件而写脆弱的 mock |
| 2026-10-05 | 混音泵改为"只混两路都已到达的帧"（`Mixer.framesToMix`：取 `min`，只有某一路落后超过 500 ms——设备切换、tap 失效——才给它补零），取代每 50 ms 固定取 2400 帧、不够就补零；停止时把剩余尾巴 flush 出来；`SourceSampleQueue` 补上了计划里本来就有、但一直没实现的重采样（非 48 kHz 设备经 `AVAudioConverter` 转成 48 kHz） | Jakob 反馈一段 70 分钟的 Chrome 会议录音"不清晰"。解码分析：全程约 25,000 处 1–7 ms 的数字静音缺口，间隔集中在 45–51 ms，正好是泵的节拍——声卡缓冲到达时间稍有抖动，固定取块就会把"晚到几毫秒"填成静音，每秒约 6 次，听感是断续、沙沙声。改成取 `min` 后正常抖动只会让这一路多等一个节拍，不再产生缺口。重采样：之前完全没有重采样，44.1/24/16 kHz 的设备（蓝牙耳机、iPhone 麦克风）会被当成 48 kHz 写入，变速变调，还会在每个节拍欠载。**仍未在真机上验证**（S07 的麦克风 TCC 限制），`framesToMix` 有单测覆盖 |
| 2026-10-09 | 混音核心抽成独立的 `MixPipeline`（无 actor/计时器/设备，可在测试里用虚拟时钟驱动），并改成**按时间戳对齐**：一条主机时钟输出时间线；每次只输出所有"在线"源都已送达的部分（按各源实际能提供的样本数取最小值，绝不在流中间截短补零）；各源样本按硬件时间戳落到时间线上，残余误差（设备间时钟漂移，几十 ppm）由比例最多偏离 ±0.1% 的 Catmull-Rom 重采样慢慢收敛；源刚开始或断流后恢复时按时间戳精确对齐（缺口补静音、迟到的音频丢弃）；某个源 0.3 s 没送数据视为断流，不再拖住另一个源；源内部时间戳出现 >20 ms 缺口时补静音保持连续。取代 2026-10-05 的"取两路 min、落后 500 ms 才补零"（tap 启动慢于 500 ms 时会永久卡在阈值边缘、每个节拍给系统声补零）。新增 `RecordingSimulationTests`：用实测的设备行为（tap 报 48 kHz 实为 44.1 kHz 交错立体声 512 帧/回调、麦克风 48 kHz 100 ms buffer、独立时钟漂移、回调抖动、tap 晚 1.8 s 启动、线程卡顿后突发送达、泵计时器延迟、输出设备切换导致 tap 重建 1.5 s 且采样率变 48 kHz、麦克风切换 0.7 s）驱动生产代码，检查纯音的频率、残差（咔嗒）、静音总时长和两路对齐。在修复前的代码上该测试失败（系统声调高 8.8%、满是咔嗒、两路错位），修复后全部通过：系统声 439.996 Hz、可听部分 99.96% 干净、只在真实缺口处有边界、静音时长与真实缺口一致、两路对齐 <30 ms | 同上（Jakob 2026-10-09 的噪音反馈）。调研结论（OBS、PulseAudio module-loopback、Chromium 都是"时间戳 + 抖动缓冲 + 自适应重采样"）与这个设计一致。更彻底的替代方案——把麦克风和 tap 放进同一个聚合设备（麦克风做时钟、tap 开漂移补偿），一个 IOProc 同时拿到样本级对齐的两路——记录在 known-issues 里作为后续选项：它要放弃 `AVAudioEngine` 的设备自动恢复，并且需要真实麦克风才能验证，这台机器做不到 |
