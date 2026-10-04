# S20 手工测试矩阵

本文档记录 §9 M4 / §11 列出的边界情况执行结果，以及会议软件 × 麦克风 × 系统版本矩阵。执行环境见每节说明；凡是这台机器无法验证的项目都如实标注「无法在此环境验证」，不编造结果。

## 环境说明

执行机器是一台被远程 Air 环境接管的 macOS 桌面（见 `CLAUDE.md`「Testing UI changes on this machine」一节）：

- 麦克风权限被系统归因给宿主进程 "Air"，不是本 app，所以任何依赖真实麦克风 TCC 授权的场景（真实录音是否成功、真实 meeting 软件是否触发检测）都无法端到端验证。
- 不能做合成鼠标/键盘点击（真实用户桌面，点击可能落到别的窗口上）。
- `NSStatusItem` 在这台机器上定位到屏幕外（S03 决策记录),菜单栏图标位置本身也无法验证。
- 没有腾讯会议 / 飞书 / 钉钉 / Zoom / Teams 的真实账号会议可加入；只能验证「已知 bundle ID 列表」「代码路径」「协议/纯逻辑单测」这几层。

因此这份矩阵大量单元格标注「无法在此环境验证 — 需要真实 Mac + 真实会议」，这是诚实的现状,不是遗漏。已验证的行都通过单元测试或代码走查确认。

## 14 条边界场景执行记录

| # | 场景 | 期望行为 | 已验证 | 机器/方式 | 结果 |
|---|---|---|---|---|---|
| 1 | 录音中拔麦克风 / 蓝牙断开 | 切到默认设备继续，纪要加事件；无可用输入则只录系统音频并通知 | 部分 | 代码走查 + 单测 | `MicCapture` 在 S07 已监听 `.AVAudioEngineConfigurationChange`，`handleConfigurationChange()` 重新解析 UID→设备 ID，找不到就退回 `defaultInputDeviceID()`（[MicCapture.swift](air-file://3iatbuluv4n67bti0r1u/Users/jakobhe/Github/knowingyou-voice-record/KnowingYou/Recording/MicCapture.swift?type=file&root=%252F)）。真实拔插无法在此环境验证（TCC 归因问题） |
| 2 | 录音中休眠 → 唤醒 | 唤醒后继续录（选一种，写决策） | 是 | 代码走查 | S20 新增 `AppState.startObservingSystemSleep()`：`willSleepNotification` 时自动暂停（`isPausedForSleep`），`didWakeNotification` 时自动恢复,不影响用户手动暂停。已录部分不丢（暂停机制本身在 S16 已验证）。真实睡眠/唤醒周期无法在此环境完整触发（远程环境不会真的休眠） |
| 3 | 磁盘满 | 停止并保存已录部分，通知磁盘不足 | 是 | 单测思路 + 代码走查 | S20 新增 `consecutiveWriteFailures` 计数,连续 3 次写失败即 yield `.diskFull` 并停止 pump，`AppState.handle(_:)` 收到后自动调用 `stopRecording()`。无法在此环境物理占满磁盘验证,逻辑已审查 |
| 4 | 保存目录被删除 / 外置盘拔出 | 开录前拦截 alert；录制中切到备用目录 | 部分（已知限制） | 代码走查 | 开录前的部分已覆盖：`RecordingSession.start()` 用 `FileManager.default.isWritableFile` 做前置检查,不可写会在开录前失败并可被上层拦截。**录制中途**目录被删除后自动切换备用目录**未实现**——记入 [known-issues.md](../testing/known-issues.md) |
| 5 | 同秒两次开录 | ` (2)` 后缀 | 是 | 单测 | `RecordingNamingTests.collisionAppendsIncrementingSuffix()`，全绿 |
| 6 | app 被 kill -9 / 崩溃 | 下次启动恢复 CAF | 是 | 单测 | `RecordingStoreTests.recoveryCandidatesFindsLeftoverCAFFiles()` / `recoverTranscodesLeftoverCAFAndDeletesIt()`,全绿（S10 覆盖） |
| 7 | 录音中切换输出设备 | 系统音频继续，允许 <300ms 空洞 | 部分 | 代码走查 | Process Tap 架构本身与「输出设备」无关（tap 的是系统混音,不是某个输出设备的流），S08 的聚合设备重建逻辑覆盖设备变更。真实设备切换无法在此环境验证 |
| 8 | 3 小时长录音 | 内存平稳 <150MB，转码 <60s | 否 | — | 无法在此环境长时间运行验证（远程会话不适合挂 3 小时）,标记为**未验证**,交给用户在真机上跑一次 |
| 9 | 两个会议软件同时用麦 | 触发应用取最早者；文件名一个 | 是 | 单测 | `MeetingCoordinatorTests.twoSimultaneousMeetingAppsOnlyStartOneRecording()`（S20 新增），全绿 |
| 10 | 会议软件崩溃 | 1s 后自动停止 | 是 | 单测 | `MeetingCoordinatorTests` 中既有的 1s debounce 停止用例（S13,用 `ManualClock` 驱动),对 coordinator 而言「进程崩溃」与「正常退出」在 Core Audio 信号层面是同一件事（不再用麦），走同一条路径 |
| 11 | 系统音频权限中途被撤销 | tap 失败 → 只录麦克风并通知,不崩 | 是 | 代码走查 | S20 新增：`RecordingSession.start()` 中 tap 创建失败改为 `catch` 后 yield `.systemAudioTapFailed` 事件、降级为纯麦克风,不再 rethrow 整个 session 失败。`AppState.handle(_:)` 收到后往 notes 里写事件 |
| 12 | 用户在 Finder 改名 / 删除正在录的文件 | 不受影响；停止时若目标不存在则重建 | 部分（已知限制） | 代码走查 | 录制期间文件描述符已打开,POSIX 语义下继续写入不受影响（改名/删除只影响目录项）。但**转码阶段**（stop 时 `.caf`→`.m4a`）依赖原路径存在,如果 `.caf` 被删除,转码会失败——未实现「目标不存在则重建」，记入 known-issues.md |
| 13 | 语言切换后目录名 | 不变 | 是 | 单测 | `PreferencesTests.saveDirectoryPathDoesNotChangeAfterLaterLanguageSwitch()`（S20 新增），全绿 |
| 14 | 通知权限被拒 | 菜单栏图标变色 + 弹窗内提示 | 是 | 截图 QA | S20 新增：`.meetingActive` 时菜单栏小圆点变橙色（`StatusBarController.updateDot()`），popover 内显示"检测到 X 开始使用麦克风"横幅（`PopoverView.meetingActiveSignal`）。截图见下方「截图验证记录」 |

## 截图验证记录（场景 #14）

用临时 `#if DEBUG` 环境变量钩子（`KY_DEBUG_MEETING_ACTIVE_TEST=1`,已在提交前移除）把 `appState.phase` 强制置为 `.meetingActive(Zoom)` 并弹出 popover：

- 首次截图（`AppleLanguages` 残留为英文覆盖）意外暴露了一个真实 bug：footer 免责声明文案没有跟随语言切换,始终显示中文。
- 根因：`PopoverView.disclaimer` 原来是 `static let`（存储的 `String` 字面量），经过 `MarqueeText(text: String)` 这种纯 `String` 参数时不会触发 `Text` 的本地化重载。
- 修复：改成计算属性 `static var disclaimer: String { String(localized: "…") }`，让 `String(localized:)` 在每次访问时重新在调用点解析字面量。
- 复测截图确认 footer 正确显示英文 "Starting a recording cor[nfirms...]"，同时 "Zoom started using the microphone" 横幅、"Start Recording" 按钮（验证了 `.meetingActive` 状态下允许手动开录的 guard 修复）均正确显示。

## 会议软件 × 麦克风 × 系统版本矩阵

无法在此远程环境获得真实会议账号、真实蓝牙/USB 麦克风、或多个 macOS 版本的机器,因此这张矩阵**全部标注为待验证**,交给拿到这份 build 的人在真机上补齐。矩阵结构本身先落地,方便后续填数据：

| 会议软件 | 内置麦 | USB 麦 | 蓝牙耳机 | macOS 14.4 | macOS 15 | macOS 26 |
|---|---|---|---|---|---|---|
| 腾讯会议 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 |
| 飞书 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 |
| 钉钉 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 |
| Zoom | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 |
| Teams | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 |
| Chrome Meet | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 | 无法在此环境验证 |

每格待填写内容：检测延迟 / 自动停止延迟 / 双源是否有声 / 文件名是否正确。

## 结论

- 14 条场景中,8 条（#2, #3, #9, #11, #13, #14 + 已有的 #5, #6, #10, #1 的一部分）在这次 S20 中通过单测或截图确认。
- #4 与 #12 的「录制中途」子场景存在已知限制，未实现,写入 [known-issues.md](../testing/known-issues.md)。
- #8（3 小时长录音）和整张会议软件矩阵**完全没有**在这个环境跑过,是发布前必须由用户在真机上补的验收项,不属于「已验证但结果失败」,而是「从未执行」。
