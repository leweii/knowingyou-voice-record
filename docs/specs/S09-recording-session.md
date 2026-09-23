---
id: S09
title: RecordingSession：混音、CAF 写入、m4a 转码、暂停
milestone: M1
status: todo
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
- [ ] 开一个腾讯会议 / Zoom 测试会，录 5 分钟：产物 m4a 里自己和对方声音都清晰；时长与实际一致（±1 s）。
- [ ] 拍手对齐测试：同一声音经麦克风和系统（回放）录入，两路错位 <50 ms。
- [ ] 录制中 `kill -9`，目录里剩 `.caf` 可用 QuickTime 播放。
- [ ] 暂停 30 s 再继续，`pausedIntervals` 准确（±0.5 s），产物中暂停段不存在（时长少 30 s）。
- [ ] `dualTrack` 产物左声道只有麦克风、右声道只有系统。
- [ ] M1 Mac 上录制中 CPU <10%（Activity Monitor）。
- [ ] `captureSystemAudio == false` 时不创建 tap，不触发系统音频权限弹窗。

## 测试
`MixerTests`：对齐、补零、限幅、双轨分离（合成数据）。`Encoder` 的编码正确性已由 S10 覆盖。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
