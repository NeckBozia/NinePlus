# Phase 4 · 4.2 GPS + IMU 本地采集与滤波 详细规格

10 天，风险「高」。Phase 4 全长 4 周，这一项占掉一半以上工时。

> **这份规格的价值全在数值精确度上。**
>
> 采集链上的每个阈值都直接决定「记录出来的骑行数据是不是能用」。抄错一个数字，真机上不会报错、不会崩、界面照样转，只是记录出来的距离、最高速、最大 G 值全是废数据 —— 而且要骑一趟、导出来和里程表对一遍才能发现。所以：**写代码时逐个数字对着源码行号核，不要凭记忆。**
>
> 另一半风险来自 Android 传感器生态：iOS 侧全部阈值是照 iPhone 的 CoreLocation / CoreMotion 特性调出来的，Android 上必须重调。第「六」节专门讲这件事，**不要跳过**。

---

## 这一项和 Phase 4 其他项的关系

| | 内容 | 谁写 | 与 4.2 的关系 |
| --- | --- | --- | --- |
| 4.1 | 接口轨迹回放 | 另一份规格 [phase4-track-spec.md](./phase4-track-spec.md) | **无耦合**。数据来自九号云，不经过本地采集链。两者在 4.4 的展示层汇合（本地记录优先，没有才回退接口轨迹） |
| **4.2** | **GPS + IMU 本地采集与滤波** | **本文** | 只负责「传感器 → 内存状态 → Room」这一段 |
| 4.3 | 实时速度环形表 + G 值 | phase4-track-spec.md | **消费 4.2 的输出**。4.2 必须先定好 `currentSpeedKmh` / `currentAccelerationG` / `gpsQuality` / `distanceMeters` 四个字段的更新频率与语义，4.3 才能画。本文第 2.7 节给出 `gpsQuality` 五个状态的文案与配色映射，渲染归 4.3 |
| 4.4 | 本地记录列表、详情、轨迹回放 | phase4-track-spec.md | **消费 4.2 落库的数据**。本文第 2.9 节的「两套距离口径」直接决定列表里显示的距离数字，必须先看完再写 4.4 |
| 4.5 | GPX 导出 | phase4-track-spec.md | 消费同一张轨迹点表。注意本文第 2.11 节关于存库坐标系的说明 |

**依赖 Phase 0 的东西**（都已有规格，本文只引用不重写）：

| Phase 0 项 | 4.2 用到什么 |
| --- | --- |
| 0.3 存储 | `rides` + `ride_points` 两张 Room 表的表结构（[phase0-foundation-spec.md](./phase0-foundation-spec.md) 第 171-181 行）。列表只查 `rides`，`distance_meters` 存**重算后**的值 |
| 0.6 定位与前台服务 | 六个权限声明、`RideRecordingService` 的 `foregroundServiceType="location"`、通知渠道 `IMPORTANCE_LOW`、国产 ROM 电池优化白名单引导页、厂商自启动管理 Intent 的 try-catch 兜底。**这些一律不在本文重复**，见 0.6「权限」「前台服务」「国产 ROM 保活」三节 |
| 0.4 状态骨架 | `LoadingKind` 密封类；本文的 recorder 状态走同一套 `StateFlow` 约定 |
| 0.2 数据模型 | `pointCount` 可空的向后兼容语义 |

已定的产品决策（[pending-decisions.md](./pending-decisions.md) 的「已定的决策」表）：**本地 GPS/IMU 记录 —— 做**；**本地记录跨端同步 —— 不做**；**定位 SDK —— 高德定位优先，回退 Google 融合定位（D8）**；**地图 —— 高德**。

---

> **两处对既有文档的修正**（写之前先看）
>
> **1. Phase 0 的 0.6 把定位配置的出处写错了。** 它写的是「iOS 侧的 `CLLocationManager` 配置（`NinebotRecordingView.swift:178-181`）」。那四行实际是 `RecordingHeader.statusText` 的分支。真正的配置在 **`NinebotRideRecorder.swift:66-71`**（`init()` 里）。0.6 那张对照表的内容本身是对的，只是行号指错了地方。
>
> **2. iOS 侧没有暂停/恢复。** `NinebotRideRecorder` 只有 `start(vehicleSN:)`（`:146`）和 `stop()`（`:204`），没有 `pause()`。看起来像暂停的行为其实是「稳定化冷却」（第 2.7、2.10 节）。任何「暂停时累计值怎么处理」的问题在 iOS 侧没有答案，见文末 `## 待定` 的 P4。
>
> **3. 记录期间 App 被杀 = 数据全丢。** iOS 侧 `points` 是内存里的 `@Published` 数组（`:27`），只在 `stop()` 时才交给 `NinebotViewModel.saveRecordedRide`（`NinebotRecordingView.swift:46-48`）落盘。骑了两小时被系统回收，一个点都不剩。Android 侧用 Room 增量写入能顺手解决，见第 3.4 节 —— 这是**主动做得比 iOS 好**的地方，但「恢复未完成的记录」要不要给界面入口是产品决策，见 `## 待定` 的 P5。

---

## 一 · iOS 现状

### 1.1 文件与职责

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| **`Domain/NinebotRideRecorder.swift`** | **556** | **采集链全部逻辑。本文主体** |
| `App/NinebotRecordingView.swift` | 1089 | 界面侧。驱动 recorder 的生命周期、`RecordingGPSQuality` 的文案/图标/配色映射（`:91-120`）、格式化函数（`:1036-1077`） |
| `Shared/NinebotModels.swift` | 2051 | `NinebotRideTrackPoint`（`:831-857`）、`NinebotRecordedRide`（`:859-1005`）、距离重算（`:969-1004`） |
| `Shared/NinebotSharedStore.swift` | ~590 | 摘要与轨迹点分离持久化（`:216-335`） |
| `Shared/NinebotCoordinateTransform.swift` | 57 | WGS-84 → GCJ-02（`gcj02Coordinate` `:10-28`、`mapKitCoordinate` `:30-33`、中国境内判定 `:35-37`） |

`NinebotRideRecorder` 是 `@MainActor final class`，同时是 `NSObject` 与 `CLLocationManagerDelegate`（`:17-18`）。所有 delegate 回调都是 `nonisolated` 加 `Task { @MainActor in ... }` 跳回主 actor（`:235`、`:246`、`:252`）。CoreMotion 的回调直接投递到 `.main` 队列（`:267`）后再跳一次（`:269`）。

### 1.2 对外状态（13 个 `@Published`，`:19-31`）

| 属性 | 行号 | 类型 | 语义 |
| --- | --- | --- | --- |
| `authorizationStatus` | 19 | `CLAuthorizationStatus` | 定位授权 |
| `isRecording` | 20 | `Bool` | 是否在记录（区别于「预览」） |
| `currentSpeedKmh` | 21 | `Double` | 平滑后的当前速度 |
| `currentAccelerationG` | 22 | `Double` | 平滑后的当前 G 值 |
| `maxSpeedKmh` | 23 | `Double` | 本次记录内最高速 |
| `maxAccelerationG` | 24 | `Double` | 本次记录内最大 G |
| `gpsQuality` | 25 | `RecordingGPSQuality` | 五态枚举，初值 `.waiting` |
| `distanceMeters` | 26 | `Double` | 实时累计距离（**不是最终落库的那个值**，见 2.9） |
| `points` | 27 | `[NinebotRideTrackPoint]` | 内存里的轨迹点 |
| `currentLocationPoint` | 28 | `NinebotRideTrackPoint?` | 最新一个位置（含被拒绝为轨迹点的位置） |
| `startedAt` / `endedAt` | 29-30 | `Date?` | |
| `lastErrorText` | 31 | `String?` | 界面直接显示原文 |

派生量：`elapsedSeconds`（`:95-99`，记录中用 `Date()`，停止后用 `endedAt ?? startedAt`）、`distanceKilometers`（`:101-103`）、`isAuthorized`（`:105-107`，`authorizedAlways || authorizedWhenInUse`）。

### 1.3 内部可变状态（`:35-46`）

`vehicleSN`、`lastLocation`、`lastSpeedMPS`、`lastAcceptedLocationAt`、`smoothedSpeedMPS`、`speedSamples`、`lastMotionTimestamp`、`smoothedMotionG`、`ignoreLocationUntil`、`ignoreMotionUntil`、`appActiveObserver`、`isBackgroundLocationEnabled`。

**`lastLocation` 和 `lastAcceptedLocationAt` 不是一回事**，这是理解整条链的关键：`lastLocation` 在几乎每条路径上都会更新（包括「太密不算距离」那条），`lastAcceptedLocationAt` 只在三处更新（`:412`、`:425`、`:462`）。第 2.4 节的陷阱 A 就出在这个差别上。

---

## 二 · 要移植的逻辑

### 2.1 阈值常量全表（15 个声明常量）

全部在 `NinebotRideRecorder.swift:48-62`，一个连续的 `private let` 块。**判定方向一栏是「什么情况下算不合格」**，抄的时候连比较符一起抄，`<=` 写成 `<` 在边界上就是另一套行为。

| # | 名字 | 值 | 单位 | 用途 | 判定方向 | 行号 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `maximumReasonableSpeedKmh` | **132.0** | km/h | 速度上限。四处使用：候选速度的两条分支（`:484`、`:499`）、原始速度终检（`:369`）、可靠段判定（`:532`） | `> 132` 拒 | 48 |
| 2 | `maximumReasonableGPSAccelerationG` | **0.75** | G | **仅**用于 GPS 反推的 G 值（`:383`），不管 IMU 那一路 | `> 0.75` 归零 | 49 |
| 3 | `maximumReasonableMotionG` | **1.35** | G | IMU G 值上限。两处：原始值检查（`:308`）、平滑后钳位（`:318`） | `> 1.35` 归零 | 50 |
| 4 | `maximumReasonableSegmentDistance` | **160.0** | m | 单段位移上限（瞬移检测）。两处：候选速度（`:491`）、可靠段（`:530`） | `> 160` 拒 | 51 |
| 5 | `maximumLocationAge` | **6** | s | 定位点年龄上限，用 `abs(timestampSinceNow)`，**未来时间同样受限**（`:549-552`） | `> 6` 整点丢弃 | 52 |
| 6 | `minimumLocationDeltaTime` | **0.45** | s | 两个定位点最小间隔。四处：太密分支（`:352`）、候选速度（`:488`）、可靠段（`:527`）、除零保护（`:381`、`:511`） | `< 0.45` 不算距离 | 53 |
| 7 | `maximumLocationDeltaTimeForSpeed` | **6** | s | 用位移反推速度时的最大间隔。两处：`:489`、`:528` | `> 6` 拒 | 54 |
| 8 | `maximumLocationGapBeforeCooldown` | **8** | s | 超过这个空档判定为「刚恢复」，进冷却。两处：`:433`、`:438` | `> 8` 进冷却 | 55 |
| 9 | `recoveryCooldownDuration` | **2.2** | s | 定位冷却时长。三处：`:182`、`:427`、`:442` | 时间窗 | 56 |
| 10 | `goodHorizontalAccuracy` | **35.0** | m | `.good` / `.weak` 的分界。两处：`:340`、`:471` | `<= 35` 判 good | 57 |
| 11 | `maximumHorizontalAccuracy` | **60.0** | m | 水平精度硬上限。五处：整点可用性（`:551`）、基线入库（`:465`）、候选速度两端（`:492-493`）、可靠段两端（`:533-534`） | `> 60` 整点丢弃 | 58 |
| 12 | `maximumDisplayedAccelerationMPS2` | **4.5** | m/s² | 速度**上升**时的变化率限幅（`:512`） | 超出则钳位 | 59 |
| 13 | `maximumDisplayedDecelerationMPS2` | **7.0** | m/s² | 速度**下降**时的变化率限幅（`:512`）。刹车比加速给得宽 | 超出则钳位 | 60 |
| 14 | `maximumMotionSampleGap` | **0.75** | s | IMU 采样最大间隔，超出则重置滤波器并进 IMU 冷却（`:287`） | `> 0.75` 重置 | 61 |
| 15 | `motionCooldownDuration` | **1.1** | s | IMU 冷却时长。四处：`:183`、`:291`、`:443`、`:280` 判定 | 时间窗 | 62 |

### 2.2 内联魔数全表（17 个）

上表之外，还有 17 个直接写在表达式里的数字。**它们和上表 15 个同等重要**，滤波系数全在这里。

| # | 数值 | 单位 | 用途 | 出处 |
| --- | --- | --- | --- | --- |
| 16 | **1** | m | `manager.distanceFilter`，位移不足 1 m 不回调 | `NinebotRideRecorder.swift:70` |
| 17 | **1.0 / 20.0** | s | `deviceMotionUpdateInterval` = **20 Hz** | `:266` |
| 18 | **0.025** | G | G 值死区，`g < 0.025` 直接当 0 | `:313` |
| 19 | **0.18** | — | G 值一阶低通系数 α（20 Hz 下） | `:315` |
| 20 | **0.08** | G | G 值单步变化上限（20 Hz 下 = **1.6 G/s**） | `:317`（`maxStep`） |
| 21 | **0.34** | — | 速度 EMA 系数 α，**上升**方向（1 Hz 下） | `:514` |
| 22 | **0.48** | — | 速度 EMA 系数 α，**下降**方向（1 Hz 下） | `:514` |
| 23 | **6** | m/s | `location.speedAccuracy` 上限，超出就不信系统速度 | `:482` |
| 24 | **9.80665** | m/s² | GPS 反推 G 值时的重力常数 | `:381` |
| 25 | **120** | m | 轨迹点水平精度上限（**注意比采集时的 60 宽一倍**） | `NinebotModels.swift:945`、`:977` |
| 26 | **30** | s | 距离重算时的段间隔上限（采集时是 6） | `NinebotModels.swift:993` |
| 27 | **300** | m | 距离重算时的段长上限（采集时是 160） | `NinebotModels.swift:995` |
| 28 | **20 / 1** | m | 重算时缺失精度的兜底值 20，下限钳到 1 | `NinebotModels.swift:984` |
| 29 | **120** | 条 | 本地记录保留上限，超出连轨迹文件一起删 | `NinebotSharedStore.swift:255-259` |
| 30 | **0.35** | G | 界面 G 值胶囊变橙的阈值 | `NinebotRecordingView.swift:255` |
| 31 | **132.0** | km/h | 速度表满量程，**与 #1 是两个独立字面量** | `NinebotRecordingView.swift:196` |
| 32 | **120** | 点 | 地图绘制的轨迹点降采样上限 | `NinebotRecordingView.swift:1083`、`NinebotModels.swift:952` |

`#31` 必须和 `#1` 保持一致，否则速度表在满量程处会和「超速拒绝」错位。Android 侧写成同一个常量引用（`#31` 归 4.3 的渲染层，但取值来自 4.2 的常量对象）。

`#25 / #26 / #27` 是三组**故意比采集阶段宽松**的阈值，只在最终重算距离时用。这不是笔误 —— 采集时要拒掉可疑点，重算时要把已经存下来的点尽量都串上。后果见 2.9。

### 2.3 定位与传感器的配置

**`CLLocationManager`（`init()`，`:66-71`）**

| 设置 | 值 | 行号 |
| --- | --- | --- |
| `desiredAccuracy` | `kCLLocationAccuracyBestForNavigation` | 68 |
| `activityType` | `.automotiveNavigation` | 69 |
| `distanceFilter` | `1`（米） | 70 |
| `pausesLocationUpdatesAutomatically` | `false` | 71 |

`CoreLocation` 在 `BestForNavigation` + `distanceFilter = 1` 下，骑行速度大致给到 **1 Hz**。iOS 侧没有显式设定回调频率 —— **这正是整条链最脆的假设**，见第 2.4 节陷阱 A 和第 3.2 节。

**`CMMotionManager`（`startMotionUpdates`，`:264-273`）**

```swift
guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
motionManager.deviceMotionUpdateInterval = 1.0 / 20.0          // 20 Hz
motionManager.startDeviceMotionUpdates(to: .main) { ... }
```

用的是 **Device Motion**（融合了加速度计 + 陀螺仪 + 磁力计）而不是裸加速度计，取的是 `motion.userAcceleration`（`:302`），**重力已由系统扣掉**，单位就是 G。`isDeviceMotionAvailable == false` 时整个 IMU 路径不启动，G 值走 GPS 反推那条（2.6）。

**后台定位（`setBackgroundLocationUpdates`，`:195-202`）**

只在记录期间开（`start()` 里 `:186` 开，`stop()` 里 `:209` 关）。同时设 `allowsBackgroundLocationUpdates` 和 `showsBackgroundLocationIndicator`。注释说明了为什么不常开：预览时开着会让状态栏蓝条常驻并耗电（`:191-194`）。

**生命周期驱动（`NinebotRecordingView.swift`）**

| 时机 | 调用 | 行号 |
| --- | --- | --- |
| 页面出现 | `recorder.startPreview()` | 82-84 |
| 页面消失 | `recorder.stopPreviewIfIdle()` —— 记录中则什么都不做（`recorder:141`） | 85-87 |
| 点「开始记录」 | `recorder.start(vehicleSN: snapshot?.vehicle.sn)` | 42-44 |
| 点「结束记录」 | `recorder.stop()`，返回 nil 就什么都不做；否则 `saveRecordedRide` + 弹关联 sheet | 45-49 |

注意 `stop()` **不停止定位和 IMU**，只是关掉后台定位并结算。停止后页面仍在预览态。

**`startPreview()`（`:113-138`）的四条分支**

```
!locationServicesEnabled()      → lastErrorText = "系统定位服务未开启"；gpsQuality = .unavailable；return
authorizationStatus == .notDetermined → requestWhenInUseAuthorization()；return（不动 gpsQuality）
!isAuthorized                   → lastErrorText = "需要定位权限才能显示实时位置"；gpsQuality = .unavailable；return
否则                             → lastErrorText = nil
                                  currentLocationPoint == nil 时 gpsQuality = .waiting
                                  startMotionUpdates() + startUpdatingLocation() + requestLocation()
```

最后那个 `requestLocation()`（`:137`）是额外的一次性单次定位请求，用来尽快点亮界面。

**`start(vehicleSN:)`（`:146-189`）的四条分支**

前三条同上，但文案不同：`"系统定位服务未开启"`、`"请允许定位后再开始记录"`（**这一条不改 `gpsQuality`**）、`"需要定位权限才能记录轨迹"`。第四条是完整重置（`:166-188`）：

```
vehicleSN = 传入值；isRecording = true
currentSpeedKmh / currentAccelerationG / maxSpeedKmh / maxAccelerationG / distanceMeters = 0
points = []；speedSamples = []
lastLocation / lastSpeedMPS / smoothedSpeedMPS / lastAcceptedLocationAt
  / lastMotionTimestamp / smoothedMotionG = nil
gpsQuality = .stabilizing
ignoreLocationUntil = now + 2.2      ← recoveryCooldownDuration
ignoreMotionUntil   = now + 1.1      ← motionCooldownDuration
startedAt = now；endedAt = nil
setBackgroundLocationUpdates(true)；startMotionUpdates()；startUpdatingLocation()
```

**开始记录后的前 2.2 秒不会累计任何距离**，全部走基线路径（2.4）。这是有意的：刚点下按钮时手机大概还在手上晃。

### 2.4 单个定位点要过的五道闸门

```
didUpdateLocations(locations)                                       :252
  └─ handleLocations: for location in locations where isUsable(...)  :258-262
       ┌─ 闸门 1 · isUsable                                          :548-555
       │    horizontalAccuracy >= 0                    ← 负值 = 无效定位
       │    horizontalAccuracy <= 60                   ← maximumHorizontalAccuracy
       │    abs(timestamp.timeIntervalSinceNow) <= 6   ← maximumLocationAge，双向
       │    latitude ∈ [-90, 90]，longitude ∈ [-180, 180]
       │  不过 → 整点丢弃，连 gpsQuality 都不更新
       └─ consume(location)                                          :326
            ┌─ 闸门 2 · 时间单调                                      :327-329
            │    timestamp <= lastLocation.timestamp → return（乱序点直接丢）
            ├─ updateGPSQuality(location)                             :331 → :470-472
            │    hAcc <= 35 → .good；否则 .weak
            ├─ 闸门 3 · 冷却窗口                                      :333-336
            │    now < ignoreLocationUntil
            │      → acceptBaselineLocation(location, .stabilizing)
            ├─ 首个点（previousLocation == nil）                       :339-342
            │    → acceptBaselineLocation(location, hAcc <= 35 ? .good : .weak)
            ├─ 闸门 4 · 恢复检测 shouldTreatAsRecoveredLocation        :345-349 → :430-439
            │    lastAcceptedLocationAt 存在且 (timestamp − 它) > 8   ← 注意用的是「已接受」时刻
            │    或 deltaTime > 8
            │      → enterStabilizationCooldown() + 基线点(.stabilizing)
            ├─ 闸门 5 · 采样太密                                      :352-356
            │    deltaTime < 0.45
            │      → lastLocation = location；currentLocationPoint 更新；return
            │      ⚠ 不更新 lastAcceptedLocationAt，不更新 lastSpeedMPS，不累计距离
            └─ 进入速度与距离处理（2.5、2.8）
```

**四条「接受但不算距离」的旁路**，一定要分清（它们都会把 `currentLocationPoint` 点亮，所以界面上小箭头照样动，但 `distanceMeters` 不涨）：

| 旁路 | 触发 | 副作用 | 行号 |
| --- | --- | --- | --- |
| `acceptBaselineLocation` | 冷却中 / 首个点 / 恢复检测命中 / 候选速度算不出来 | 速度归零、`lastSpeedMPS`/`smoothedSpeedMPS` 清空、更新 `lastAcceptedLocationAt`；**`isRecording && points.isEmpty && hAcc <= 60` 时把这个点入库** | 452-468 |
| `rejectSpeedSample` | 原始速度 > 132 km/h | 同上 + `gpsQuality = .stabilizing` + 重置 2.2 s 冷却；**这个点不入库** | 415-428 |
| 闸门 5 太密 | `deltaTime < 0.45` | 只动 `lastLocation` 和 `currentLocationPoint` | 352-356 |
| 可靠段不通过 | `isReliableRecordingSegment == false` | `points.isEmpty` 时仍然 append，但**距离不加**（`:405-407`） | 396-407 |

> **陷阱 A（严重）：定位回调快于 2.2 Hz 会让距离永远归零。**
>
> 闸门 5 更新 `lastLocation` 但不更新 `lastAcceptedLocationAt`。假设 SDK 以 0.2 s 间隔投递：每次 `deltaTime = 0.2 < 0.45` → 走闸门 5 → 永远算不出距离；同时 `lastAcceptedLocationAt` 一直停在最初那一刻，8 秒后闸门 4 判定「刚恢复」→ 进 2.2 s 冷却 → 冷却期内每个点都是基线点（会刷新 `lastAcceptedLocationAt`）→ 冷却结束后又回到闸门 5 饿死。**结果是记录器在「校准中」和「什么都不做」之间循环，距离恒为 0，界面无任何异常提示。**
>
> iOS 侧碰不到，因为 CoreLocation 在这套配置下大约 1 Hz。**Android 侧必须把定位间隔钉在 1000 ms，任何情况下不得低于 450 ms**（第 3.2 节）。想让速度表更顺滑就在渲染层插值（4.3），不要提高定位频率。

> **陷阱 B：红灯停车超过 8 秒，起步后头 2.2 秒的距离会丢。**
>
> `distanceFilter = 1` 意味着静止时不回调 → `lastAcceptedLocationAt` 变旧 → 起步第一个点触发闸门 4 → 冷却 2.2 s。所以每次长时间停车之后都会少算 2 秒多的距离。这是 iOS 的既有行为，不是 bug 修复对象；但它是「记录距离系统性偏小」的主要来源之一，第六节要量它。

### 2.5 速度：取值优先级 + 两级滤波

**第一步 · 候选速度 `speedCandidate`（`:474-503`）—— 系统速度优先**

```
若同时满足：
    location.speed         >= 0
    location.speedAccuracy >= 0
    location.speedAccuracy <= 6            ← m/s
    location.horizontalAccuracy <= 60
    location.speed * 3.6   <= 132
  → 返回 max(location.speed, 0)            ← 用系统给的多普勒速度

否则退到位移反推，要求全部满足：
    deltaTime >= 0.45
    deltaTime <= 6
    segmentDistance >= 0
    segmentDistance <= 160
    location.horizontalAccuracy         <= 60
    previousLocation.horizontalAccuracy <= 60
  → impliedSpeedMPS = segmentDistance / deltaTime
    再检查 impliedSpeedMPS * 3.6 <= 132
  → 返回 max(impliedSpeedMPS, 0)

两条都不成立 → 返回 nil → 调用方走 acceptBaselineLocation(.stabilizing)
```

所以**速度既不是纯粹「取系统给的」也不是纯粹「自己算的」**：优先系统多普勒速度，不可信时用两点位移反推，都不行就当 0 并进校准态。

**第二步 · 终检（`:368-372`）**

`rawSpeedKmh = rawSpeedMPS * 3.6`；`!isFinite || > 132` → `rejectSpeedSample`（进冷却，点不入库）。注意这一步和候选速度里的 132 检查重复，是刻意的双保险。

**第三步 · 变化率限幅 + EMA（`smoothedSpeed`，`:505-518`）**

```swift
guard let previous = smoothedSpeedMPS else {
    smoothedSpeedMPS = rawSpeedMPS          // 首个样本原值直通，无滤波
    return rawSpeedMPS
}
let safeDeltaTime = max(deltaTime, 0.45)                                    // minimumLocationDeltaTime
let maxDelta = (rawSpeedMPS >= previous ? 4.5 : 7.0) * safeDeltaTime        // m/s² × s
let limitedSpeed = min(max(rawSpeedMPS, previous - maxDelta), previous + maxDelta)
let alpha = limitedSpeed >= previous ? 0.34 : 0.48
let smoothed = previous + (limitedSpeed - previous) * alpha
smoothedSpeedMPS = max(smoothed, 0)
```

写成公式：

```
初值      s₀ = raw₀                                （首个样本不滤波，直接取原值）
限幅      Δmax = (raw ≥ s_{n-1} ? 4.5 : 7.0) × max(dt, 0.45)
          raw' = clamp(raw, s_{n-1} − Δmax, s_{n-1} + Δmax)
EMA       α = (raw' ≥ s_{n-1} ? 0.34 : 0.48)
          s_n = s_{n-1} + (raw' − s_{n-1}) × α = α·raw' + (1−α)·s_{n-1}
钳位      s_n = max(s_n, 0)
输出       currentSpeedKmh = s_n × 3.6
```

三点必须照抄：

1. **限幅方向判断用 `raw`，EMA 方向判断用 `raw'`**（限幅后的值）。因为限幅只往 `previous` 方向收，符号不变，两个判断结论总是一致，但代码里是两个不同的比较对象，直译不要合并。
2. `>=` 相等时都走「上升」分支（α = 0.34、Δmax 用 4.5）。
3. `safeDeltaTime` 用 `max(dt, 0.45)`，不是 `dt` 本身 —— 这里同时充当除零保护。

**α 与采样率的关系（Android 必须懂这一步）**：α = 0.18/0.34/0.48 这种定值只在**固定采样间隔**下才代表固定的时间常数。换算关系 `α = 1 − e^(−dt/τ)`，即 `τ = −dt / ln(1−α)`：

| 系数 | 假定 dt | 等效时间常数 τ |
| --- | --- | --- |
| 速度上升 α = 0.34 | 1.0 s | **2.41 s** |
| 速度下降 α = 0.48 | 1.0 s | **1.53 s** |
| G 值 α = 0.18 | 0.05 s（20 Hz） | **0.252 s** |

**Android 侧定位间隔固定 1000 ms，所以速度那两个 α 直接抄字面量 0.34 / 0.48**，不要换算 —— 换算引入浮点差异，反而对不上 iOS。**IMU 那个 α 必须换算**，因为 Android 拿不到稳定的 20 Hz（第 3.3 节）。

### 2.6 G 值：两条数据源、三级处理

**主路径 · IMU（`consumeMotion`，`:279-324`）**

```
① 冷却检查                                                      :280-283
   now < ignoreMotionUntil → currentAccelerationG = 0；return
   （不更新 lastMotionTimestamp，不动 smoothedMotionG）

② 采样间隔检查                                                  :285-294
   deltaTime = motion.timestamp − lastMotionTimestamp
   deltaTime <= 0 或 deltaTime > 0.75
     → lastMotionTimestamp = 本次；smoothedMotionG = nil
       currentAccelerationG = 0；ignoreMotionUntil = now + 1.1；return

③ （:296-299 的时间倒退检查是不可达代码，②已经用 deltaTime <= 0 拦掉了。直译时可以省，省了要在注释里写明原因）
   lastMotionTimestamp = motion.timestamp

④ 三轴合成                                                      :302-307
   g = √(ax² + ay² + az²)     ← userAcceleration，单位已经是 G，重力已扣除

⑤ 合理性检查                                                    :308-311
   !g.isFinite 或 g > 1.35 → currentAccelerationG = 0；return
   ⚠ 这一步不动 smoothedMotionG —— 滤波器状态被保留，下一帧从旧值继续

⑥ 死区                                                          :313
   normalizedG = (g < 0.025) ? 0 : g

⑦ 一阶低通                                                      :314-315
   previousG = smoothedMotionG ?? 0                ← 初值 0，不是首样本直通
   filteredG = previousG + (normalizedG − previousG) × 0.18

⑧ 单步限幅                                                      :316-317
   maxStep = 0.08
   rateLimitedG = clamp(filteredG, previousG − 0.08, previousG + 0.08)

⑨ 钳位并输出                                                    :318-323
   smoothedMotionG = clamp(rateLimitedG, 0, 1.35)
   currentAccelerationG = smoothedMotionG
   if isRecording { maxAccelerationG = max(maxAccelerationG, currentAccelerationG) }
```

公式形式：

```
g_raw = ‖userAcceleration‖₂                       (单位 G)
g_dz  = g_raw < 0.025 ? 0 : g_raw
p     = smoothedMotionG ?? 0                       (初值 0)
g_lp  = p + (g_dz − p) × 0.18                      = 0.18·g_dz + 0.82·p
g_rl  = clamp(g_lp, p − 0.08, p + 0.08)
g_out = clamp(g_rl, 0, 1.35)
```

**滤波级数是两级：一阶低通（⑦）串上单步限幅（⑧）。** 在 20 Hz 下 ⑦ 的 α = 0.18 已经使单步变化最大只有 `0.18 × 1.35 = 0.243`，远大于 ⑧ 的 0.08，所以**实际起作用的是 ⑧ 那个 0.08**（等价 1.6 G/s 的爬升上限）。抄的时候两级都要有，不能只留一级。

**⑦ 的初值是 0 而不是首样本**（`smoothedMotionG ?? 0`），这一点和速度滤波（首样本直通）**不同**。刚开始记录时 G 值从 0 慢慢爬上来，最快 1.6 G/s。

**备用路径 · GPS 反推（`:379-384`，只在 `!motionManager.isDeviceMotionActive` 时生效）**

```swift
let previousSmoothedSpeed = smoothedSpeedMPS ?? lastSpeedMPS       // :374，在 smoothedSpeed() 之前捕获
...
let gpsAccelerationG = previousSmoothedSpeed.map {
    max((displaySpeedMPS - $0) / max(deltaTime, 0.45) / 9.80665, 0)
} ?? 0
currentAccelerationG = (gpsAccelerationG.isFinite && gpsAccelerationG <= 0.75) ? gpsAccelerationG : 0
```

四个要点：

- `previousSmoothedSpeed` 在 `:374` 捕获，**必须在调用 `smoothedSpeed()` 之前**，否则拿到的是已更新的值，加速度恒为 0 附近。
- `max(..., 0)` 意味着**减速不产生 G 值**，只有加速才有。IMU 路径没有这个限制（三轴合成本来就是标量）。
- 上限用 `maximumReasonableGPSAccelerationG = 0.75`，不是 IMU 的 1.35。
- 除以 `9.80665`（`SensorManager.GRAVITY_EARTH` 是同一个数）。

**两条路径的分派点共 5 处**，全部用 `motionManager.isDeviceMotionActive` 判断：`:379`（算 G）、`:391`（更新最大 G）、`:419`（拒绝速度样本时归零）、`:453`（基线点带不带 G）、`:456`（基线点归零）。Android 侧要有一个统一的 `hasImu: Boolean`，不要在五处各判一次。

**`maxAccelerationG` 只在 `isRecording` 时更新**（IMU 路径 `:321`，GPS 路径 `:391`）。预览态下界面显示 `currentAccelerationG` 但最大值不涨。

### 2.7 GPS 质量状态机（`RecordingGPSQuality`，五态）

枚举定义在 `NinebotRideRecorder.swift:9-15`，界面映射在 `NinebotRecordingView.swift:91-120`。

| 状态 | 界面文案（`:92-100`） | SF Symbol（`:102-110`） | 配色（`:112-119`） |
| --- | --- | --- | --- |
| `.waiting` | `"等待 GPS"` | `location` | `teslaSecondaryText` |
| `.stabilizing` | `"校准中"` | `scope` | `teslaSecondaryText` |
| `.good` | `"GPS 稳定"` | `location.fill` | `teslaGreen` |
| `.weak` | `"GPS 弱"` | `location.slash` | `.orange`（系统橙） |
| `.unavailable` | `"定位不可用"` | `exclamationmark.triangle.fill` | `.red`（系统红） |

**进入条件**

| 状态 | 何时进入 | 行号 |
| --- | --- | --- |
| `.waiting` | 属性初值；`startPreview()` 里 `currentLocationPoint == nil` 时 | 25、132-134 |
| `.stabilizing` | `start()` 时无条件置；`enterStabilizationCooldown()`；冷却窗口内的每个点；候选速度算不出来；`rejectSpeedSample`；恢复检测命中 | 181、449、334、364、426、347 |
| `.good` | 有点通过闸门 1、2 且 `horizontalAccuracy <= 35`（`updateGPSQuality`）；首个点同判 | 471、340 |
| `.weak` | 同上但 `35 < horizontalAccuracy <= 60` | 471、340 |
| `.unavailable` | 系统定位服务关闭；`startPreview` / `start` 检测到无授权；授权变更回调里 `!isAuthorized` | 117、127、151、163、242 |

**转移图**

```
                    ┌──────────────┐
                    │  .waiting    │  初值 / 预览且还没有任何点
                    └──────┬───────┘
                           │ 第一个通过闸门的点
       ┌───────────────────┼────────────────────┐
       │ hAcc <= 35        │                    │ 35 < hAcc <= 60
       ▼                   │                    ▼
  ┌─────────┐              │              ┌─────────┐
  │  .good  │◄─────────────┼─────────────►│  .weak  │   每个点按 hAcc 重判，可来回跳
  └────┬────┘              │              └────┬────┘
       │                   │                   │
       │  点「开始记录」 / 空档 > 8 s / 速度 > 132 / 候选速度算不出 / 前后台切换*
       ▼                   ▼                   ▼
                  ┌─────────────────┐
                  │  .stabilizing   │  冷却 2.2 s
                  └────────┬────────┘
                           │ 冷却结束后的第一个点，按 hAcc 重判
                           ▼
                    回到 .good / .weak

任意状态 ──（定位服务关闭 / 授权被撤销）──► .unavailable
.unavailable ──（授权恢复，:238-239 重新 startPreview）──► .waiting / .good / .weak
```

\* 前后台切换那条只在**非记录**状态生效：`didBecomeActive` 观察者（`:72-86`）有 `guard !self.isBackgroundLocationEnabled else { return }`，记录期间后台定位是开着的，所以不进冷却。注释写明了理由：后台定位在跑时轨迹从未中断，没有需要稳定的东西；真断了的话闸门 4 的空档检测会在下一个点抓到（`:79-82`）。

**执行顺序上的一个坑**：`updateGPSQuality`（`:331`）在冷却检查（`:333`）**之前**执行。所以每个点先被判成 `.good`/`.weak`，冷却中再被 `acceptBaselineLocation` 改回 `.stabilizing`。净效果是冷却期内显示 `.stabilizing`，但**中间存在一次 `@Published` 抖动** —— SwiftUI 在同一次 runloop 内合并了，Compose 里如果用两次 `emit` 会真的闪一下。Android 侧在同一个函数内先算出终值再发一次。

**哪些状态下的点不入库**

| 情形 | `gpsQuality` | 入 `points` 吗 | 计入距离吗 |
| --- | --- | --- | --- |
| 闸门 1 不过（hAcc > 60 / 年龄 > 6 s / 坐标越界 / hAcc < 0） | 不变 | **否** | 否 |
| 闸门 2 不过（时间戳乱序） | 不变 | **否** | 否 |
| 冷却窗口内 | `.stabilizing` | 仅当 `isRecording && points.isEmpty && hAcc <= 60`（`:465`） | 否 |
| 首个点 | `.good`/`.weak` | 同上（走同一个 `acceptBaselineLocation`） | 否 |
| 恢复检测命中 | `.stabilizing` | 同上 | 否 |
| 候选速度算不出来 | `.stabilizing` | 同上 | 否 |
| 原始速度 > 132 km/h | `.stabilizing` | **否**（`rejectSpeedSample` 不 append） | 否 |
| `deltaTime < 0.45` | 保持 `.good`/`.weak` | **否** | 否 |
| 可靠段判定不通过 | 保持 | 仅当 `points.isEmpty`（`:405-407`） | **否** |
| 全部通过 | `.good`/`.weak` | **是** | **是** |

`.unavailable` 状态下根本没有定位回调，所以不存在「入库」问题。

### 2.8 累计量怎么维护

| 量 | 维护方式 | 条件 | 行号 |
| --- | --- | --- | --- |
| `distanceMeters` | `+= segmentDistance`，`segmentDistance = location.distance(from: previousLocation)` | `isRecording` 且 `isReliableRecordingSegment` | 403 |
| `maxSpeedKmh` | `max(maxSpeedKmh, displaySpeedKmh)` —— 用**平滑后**的速度，不是原始速度 | `isRecording` | 390 |
| `maxAccelerationG` | `max(...)`，IMU 路径每帧更新，GPS 路径随定位点更新 | `isRecording` | 322、392 |
| `speedSamples` | `append(displaySpeedKmh)`，**无上限、无降采样** | `isRecording` | 394 |
| `points` | `append(point)` | 见 2.7 表 | 404、406、466 |

**距离用的是逐点椭球面测地线距离，不是 Haversine。** `CLLocation.distance(from:)` 按 WGS-84 椭球算。Haversine（球面，R = 6371 km）在同一对坐标上会差 **0.1%–0.5%**（随纬度变化），5 km 骑行折合 5–25 m。Android 侧用 `Location.distanceBetween()`（内部是 Vincenty 反解，与 WGS-84 一致），**不要手写 Haversine**。

**`isReliableRecordingSegment`（`:520-535`）—— 八个条件全部 AND**

```
deltaTime >= 0.45                              minimumLocationDeltaTime
deltaTime <= 6                                 maximumLocationDeltaTimeForSpeed
segmentDistance >= 0
segmentDistance <= 160                         maximumReasonableSegmentDistance
speedMPS >= 0
speedMPS * 3.6 <= 132                          maximumReasonableSpeedKmh
location.horizontalAccuracy <= 60              maximumHorizontalAccuracy
previousLocation.horizontalAccuracy <= 60      ← 两端都要查
```

传进去的 `speedMPS` 是 `displaySpeedMPS`（**平滑后**的值，`:401`），不是原始速度。

**平均速度不实时维护**，只在 `stop()` 里算一次（2.9）。

### 2.9 停止与落库：**两套距离口径**

`stop()`（`:204-233`）：

```swift
guard isRecording, let startedAt else { return nil }           // 非记录态返回 nil
let endedAt = Date()
isRecording = false; self.endedAt = endedAt
setBackgroundLocationUpdates(enabled: false)                    // 不停定位、不停 IMU

let correctedDistanceMeters = NinebotRecordedRide.recalculatedDistanceMeters(from: points)
let finalDistanceMeters = correctedDistanceMeters > 0 ? correctedDistanceMeters : distanceMeters

let durationHours = max(endedAt.timeIntervalSince(startedAt) / 3600, 0)
let averageSpeed: Double
if durationHours > 0        { averageSpeed = (finalDistanceMeters / 1000) / durationHours }
else if !speedSamples.isEmpty { averageSpeed = speedSamples.reduce(0, +) / Double(speedSamples.count) }
else                        { averageSpeed = 0 }

return NinebotRecordedRide(vehicleSN:, startedAt:, endedAt:,
                           distanceMeters: finalDistanceMeters, maxSpeedKmh:,
                           averageSpeedKmh: averageSpeed, maxAccelerationG:, points:)
```

**平均速度含停车时间**：分母是墙钟时长，不是运动时长。`durationHours > 0` 几乎恒真，所以 `speedSamples` 那条均值分支实际只在「开始和结束在同一时刻」这种退化情况下走到。`speedSamples` 那个无上限数组（1 Hz × 2 小时 ≈ 7200 个 `Double`，回调更密时翻倍）就为了这条几乎不触发的分支存在。

**距离重算（`NinebotModels.swift:969-1004`）用的是另一套阈值**：

```
遍历 points（按 date 升序），逐点过滤：
  latitude ∈ [-90, 90]、longitude ∈ [-180, 180]
  (horizontalAccuracy ?? 0) <= 120            ← 采集时是 60
构造 CLLocation，horizontalAccuracy = max(hAcc ?? 20, 1)
相邻两点累加，条件：
  deltaTime >= 0                              ← 采集时是 >= 0.45
  deltaTime <= 30                             ← 采集时是 <= 6
  distance  >= 0
  distance  <= 300                            ← 采集时是 <= 160
```

**后果：结算时的距离和骑行过程中界面上显示的距离不是同一个数。** 重算会把「入了库但当时没计入距离」的段补上（基线点、`points.isEmpty` 时强行 append 的点、以及冷却前后跨越较长空档的两点），所以 `finalDistanceMeters` 通常**大于**实时的 `distanceMeters`。停下的一瞬间距离数字会跳一下。iOS 既有行为，照抄；但 4.4 的列表和详情必须都用重算值（`displayDistanceMeters`，`NinebotModels.swift:961-967`），不能一处用重算一处用实时。

`trackSummary()`（`NinebotModels.swift:918-926`）在存摘要时把 `distanceMeters` **冻结成重算值**，注释写明了理由：摘要要和完整记录报同一个距离。Phase 0 的 0.3 已经把这一条写进 Room 表约定（`distance_meters` 存重算后的值）。

**持久化路径（iOS）**：`NinebotViewModel.saveRecordedRide`（`:461-465`）→ `store.upsertRecordedRide`（`NinebotSharedStore.swift:272-280`）→ `saveRecordedRides`（`:253-270`）：按 `startedAt` 降序、保留前 120 条、超出的删轨迹文件、摘要写 `UserDefaults`、轨迹点逐条写 `RideTracks/{id}.json`（`:306-320`，`.atomic` 写入）。`statusMessage = "骑行记录已保存"`。

`saveRecordedRides` 里有一条必须移植的守卫（`:262-265`）：

```swift
// An unloaded summary must not overwrite the track already on disk.
if !ride.points.isEmpty || ride.trackPointCount == 0 {
    writeTrackPoints(ride.points, id: ride.id)
}
```

从列表里拿到的是不带轨迹点的摘要，直接回写会把磁盘上的轨迹清空。Room 侧同样的坑：更新 `rides` 行时**不要**顺手 `deleteAll` + `insertAll` `ride_points`。

### 2.10 暂停与恢复

**iOS 侧没有暂停功能。** 只有 `start()`（完整重置）和 `stop()`（结算）。三种看起来像暂停/恢复的场景，实际行为是：

| 场景 | 实际行为 | 累计值 | 行号 |
| --- | --- | --- | --- |
| 记录中切后台 / 锁屏 | 后台定位在跑，轨迹不中断；`didBecomeActive` 的冷却被 `isBackgroundLocationEnabled` 守卫跳过 | 全部保持 | 83、195-202 |
| 记录中被系统压制、定位空档 > 8 s | 闸门 4 抓到 → 冷却 2.2 s → 空档那一段**不计入距离**，但空档两端的点都在库里，`stop()` 时重算会把它补上（只要空档 ≤ 30 s 且段长 ≤ 300 m） | `distanceMeters` 少算，落库值补回 | 430-439、992-997 |
| 记录中再点 `start()` | **全部累计值归零，之前的轨迹丢失且不落盘** | 全丢 | 166-188 |

第三条在界面上进不去（同一个按钮在记录中显示「结束记录」并走 `onStop`，`NinebotRecordingView.swift:296-302`），但 Android 侧如果做了通知栏按钮或磁贴入口，就有可能同时到达。`RideRecorder` 必须自己守卫 `if (isRecording) return`。

**iOS 侧「预览」与「记录」的区别**（Android 要保留这个二态）：

| | 预览（`startPreview`） | 记录（`start`） |
| --- | --- | --- |
| 定位 | 开 | 开 |
| IMU | 开 | 开 |
| 后台定位 | **关** | **开** |
| `currentSpeedKmh` / `currentAccelerationG` | 更新 | 更新 |
| `maxSpeedKmh` / `maxAccelerationG` / `distanceMeters` / `points` | **不更新** | 更新 |
| 前后台切换 | 进 2.2 s 冷却 | 不进 |

### 2.11 坐标系与存库口径

**iOS 侧库里存的是 WGS-84 原值。** `trackPoint(for:speedKmh:accelerationG:)`（`:537-546`）直接取 `location.coordinate.latitude/longitude`，没有任何转换。GCJ-02 转换只在**绘制时**发生：

| 消费点 | 转换 | 出处 |
| --- | --- | --- |
| 实时轨迹预览 | `recordingMapCoordinate` → `NinebotCoordinateTransform.mapKitCoordinate` | `NinebotRecordingView.swift:440-454`、`:1079-1081` |
| 记录详情地图 | `NinebotRecordedRide.trackCoordinates` | `NinebotModels.swift:939-950` |
| **GPX 导出** | **也转了**（`:897`） | `NinebotRecordingView.swift:893-915` |

`gcj02Coordinate`（`NinebotCoordinateTransform.swift:10-28`）只在中国境内偏移（`isInsideMainlandChina`：`lon ∈ (72.004, 137.8347)` 且 `lat ∈ (0.8293, 55.8271)`，`:35-37`），境外原样返回。常数 `earthRadius = 6378245.0`、`earthEccentricity = 0.00669342162296594323`（`:39-40`）。

`trackCoordinates`（`:939-950`）在转换前还过一道滤：按 `date` 升序、坐标范围合法、`(horizontalAccuracy ?? 0) <= 120`。

**GPX 导出那处转换在语义上是错的**（GPX 规范要求 WGS-84），Android 侧的取舍见 `## 待定` 的 P1。

**Android 的坐标问题比 iOS 复杂**，因为两条 SDK 路径给的坐标系不同：

| 路径 | SDK 返回 | 存库前要做什么 |
| --- | --- | --- |
| 高德定位（首选） | **GCJ-02** | **反向转换成 WGS-84** |
| Google 融合定位（回退） | WGS-84 | 无 |

**规定：坐标在数据源适配器（`LocationSource` 实现）内部统一成 WGS-84，往上层只暴露 WGS-84。** 三个理由：

1. 和 iOS 的存库口径一致，两端的轨迹文件可以互相拿来做回归夹具（跨端同步不做，但夹具对齐是已定方案）。
2. `Location.distanceBetween()` 是按 WGS-84 椭球定义的。喂 GCJ-02 坐标进去，虽然偏移量随经纬度缓变、同一小段两端的偏移近似相等因而段长差异很小，但「很小」不等于零，而且没人量过。统一转成 WGS-84 之后两条 SDK 路径共用同一套数值，可对比性最好。
3. 地图（高德）和轨迹绘制在 4.4，那一层再转回 GCJ-02，与 iOS 的「存原值、画时转」结构一致。

**GCJ-02 → WGS-84 没有闭式解**，标准做法是迭代逼近：拿当前估计值正向转一次，用误差修正估计值，重复 2–4 次即可收敛到厘米级。实现放在 `NinebotCoordinateTransform` 的 Kotlin 版里，加一个 `wgs84Coordinate(latitude, longitude)`，并用「正转再反转应回到原点，误差 < 0.5 m」当单测。境外判定沿用同一个 `isInsideMainlandChina` 边界，境外直接返回原值 —— 两边都不转，闭环成立。

### 2.12 格式化（4.3 / 4.4 会用，值来自 4.2）

`NinebotRecordingView.swift:1036-1077`，全部走 `NumberFormatter`：

| 函数 | 小数位 | 单位 | 行号 |
| --- | --- | --- | --- |
| `formatRecordingSpeed` | max 1 | `" km/h"`（`showsUnit: false` 时无单位） | 1036-1038 |
| `formatRecordingDistance` | max 2 | `" km"` | 1040-1042 |
| `formatRecordingG` | max 2、**min 2** | `" G"` | 1044-1046 |
| `formatRecordingDuration` | — | `H:MM:SS`（有小时）/ `MM:SS` | 1048-1057 |
| `formatRecordingDate` | — | `"MM-dd HH:mm"`，locale `zh_CN` | 1059-1064 |

`formatRecordingG` 是唯一固定两位小数的（`0.00 G` 而不是 `0 G`）。Kotlin 侧按 Phase 1 的 2.5 节口径写：`isGroupingUsed = false` + `RoundingMode.HALF_EVEN`。

---

## 三 · Android 实现要点

### 3.1 分层与类名

```
android/
  core/location/
    LocationSource.kt              interface：一个 Flow<RawFix>，两个实现
    AmapLocationSource.kt          高德，GCJ-02 → WGS-84
    FusedLocationSource.kt         Google，WGS-84 直通
    LocationSourceFactory.kt       GMS 探测与回退
    MotionSource.kt                interface：Flow<RawMotion>
    LinearAccelerationSource.kt    TYPE_LINEAR_ACCELERATION
    DerivedLinearAccelSource.kt    降级：TYPE_ACCELEROMETER (+ TYPE_GRAVITY)
    RideRecordingService.kt        前台服务（骨架见 Phase 0 的 0.6）
  core/domain/recording/
    RideRecorder.kt                ★ 采集链本体，纯 Kotlin，无 Android 依赖，可单测
    RecordingThresholds.kt         ★ 32 个常量，唯一定义处
    SpeedFilter.kt                 2.5 的两级滤波
    MotionGFilter.kt               2.6 的两级滤波
    GpsQualityMachine.kt           2.7 的五态机
    RecordedRideAssembler.kt       2.9 的结算与重算
  core/storage/
    RideDao.kt / RidePointDao.kt   Room（表结构见 Phase 0 的 0.3）
    RideWriteBuffer.kt             3.4 的批量写
```

**`RideRecorder` 必须是纯 Kotlin**（输入 `RawFix` / `RawMotion` 数据类，输出状态），这是唯一能把 32 个数值钉住的办法。全链路单测用录制好的 fix 序列跑，不碰真机：

```kotlin
data class RawFix(
    val timestampMillis: Long,        // 墙钟，用于 date 字段
    val elapsedRealtimeNanos: Long,   // 单调时钟，用于算 deltaTime 和年龄 ← 必须有
    val latitude: Double,             // WGS-84
    val longitude: Double,
    val horizontalAccuracyMeters: Float,   // < 0 表示无效
    val speedMetersPerSecond: Float?,      // null = SDK 没给
    val speedAccuracyMetersPerSecond: Float?,
)

data class RawMotion(
    val elapsedRealtimeNanos: Long,   // SensorEvent.timestamp
    val x: Float, val y: Float, val z: Float,   // m/s²，需除 GRAVITY_EARTH
)
```

> **时钟：所有 `deltaTime` 一律用单调时钟。**
>
> iOS 侧 `location.timestamp` 是 `Date`（墙钟），`motion.timestamp` 是开机以来的秒数（单调）。Android 侧 `Location.getTime()` 是墙钟，**NTP 校时或用户改时间会让它跳几秒甚至几小时** —— 这会直接触发闸门 2（乱序丢点）或闸门 4（8 秒空档 → 冷却），而且是随机偶发的。`Location.getElapsedRealtimeNanos()`（API 17+）和 `SensorEvent.timestamp` 都是单调的。**`deltaTime`、年龄检查、8 秒空档判定全部用单调时钟；`timestampMillis` 只用来填轨迹点的 `date` 字段。** 这是 iOS 代码里不存在但 Android 必须处理的差异。

### 3.2 定位：两条路径统一

**间隔固定 1000 ms**（陷阱 A），两条路径都一样。

**高德（首选）**

```kotlin
// SDK 初始化前必须先过隐私合规，否则拿不到定位且不报明确错误
AMapLocationClient.updatePrivacyShow(context, true, true)
AMapLocationClient.updatePrivacyAgree(context, true)

val option = AMapLocationClientOption().apply {
    locationMode = AMapLocationClientOption.AMapLocationMode.Hight_Accuracy   // 对应 BestForNavigation
    interval = 1_000L                                                        // ≥ 450 ms，见陷阱 A
    isNeedAddress = false                                                    // 采集不需要逆地理，省流量与耗时
    isOnceLocation = false
    isLocationCacheEnable = false                                            // 不要缓存点，会破坏时间单调性
}
```

（隐私合规两个静态方法的签名以接入时的 SDK 版本文档为准，这两个调用漏了是最常见的「集成完全无定位」原因。）

`AMapLocation` 继承 `android.location.Location`。要用的字段：`accuracy`（水平精度，米）、`speed`（m/s）、`elapsedRealtimeNanos`、`errorCode`（非 0 表示这次定位失败，**必须先查再用坐标**，失败时坐标是 0,0）、`locationType`（GPS / WiFi / 基站，可以记进诊断日志）。

**高德不提供 `speedAccuracy`。** 这直接决定 `speedCandidate`（2.5）走哪条分支：iOS 侧第一条分支要求 `speedAccuracy >= 0 && <= 6`，拿不到的话第一条分支永远不成立，**速度会全程走位移反推**。位移反推在低速（< 5 km/h）时噪声明显大于多普勒速度。

规定：`RawFix.speedAccuracyMetersPerSecond == null` 时，`speedCandidate` 的第一条分支改为「其余条件成立即采信 SDK 速度」（即跳过 `speedAccuracy` 那两个判定），并在诊断日志里标记这一路。这样两条 SDK 路径的行为差异集中在一处，第六节要专门量它。**这是本文里唯一一处偏离 iOS 逐条判定的地方，理由是判定所依赖的输入在这条路径上不存在。**

**Google 融合定位（回退）**

```kotlin
val available = GoogleApiAvailability.getInstance()
    .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
    .setMinUpdateIntervalMillis(1_000L)      // 不许比 450 ms 更快
    .setMinUpdateDistanceMeters(1f)          // 对应 iOS distanceFilter = 1
    .setWaitForAccurateLocation(true)
    .build()
```

`Location` 上要用的：`accuracy`、`speed`、`hasSpeedAccuracy()` / `speedAccuracyMetersPerSecond`（API 26+，minSdk 33 无需判版本，但**要查 `hasSpeedAccuracy()`**，很多设备不填）、`elapsedRealtimeNanos`。

**回退判定与切换**：`LocationSourceFactory` 在**记录开始前**决定用哪条，记录期间不切换（中途换数据源会让坐标系、精度语义、速度可信度全变，滤波器状态无法延续）。判定顺序：高德客户端初始化成功 → 用高德；否则 GMS 可用 → 用 Google；两者都不行 → `gpsQuality = .unavailable` + 错误文案，并按 D8 的遗留问题决定是否再垫一层原生 `LocationManager`（见 `## 待定` 的 P2）。

**`distanceFilter = 1` 的对齐**：Google 侧有 `setMinUpdateDistanceMeters`，高德侧的 `AMapLocationClientOption` 没有等价项，会按 `interval` 一直投递。**规定在适配器里自己补**：与上一个**已投递**的 fix 相比位移 < 1 m 就丢掉。这样两条路径都保持 iOS 的「静止不回调」特性，闸门 4 的 8 秒空档规则在两条路径上同样会在红灯时触发（陷阱 B），行为一致才好比对。

**不要**擅自去掉这个 1 m 过滤来「修掉」陷阱 B —— 去掉之后静止时的 GPS 抖动会被当成真实位移累计进距离，那是更大的误差来源。要不要改见 `## 待定` 的 P3，先按 iOS 口径实现，量完再说。

### 3.3 IMU：`SensorManager` + 三个 Android 特有的坑

```kotlin
val sensorManager = context.getSystemService(SensorManager::class.java)
val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)   // 可能是 null，见坑 (c)
val thread = HandlerThread("imu").apply { start() }
sensorManager.registerListener(listener, sensor, 50_000, Handler(thread.looper))
//                                              ↑ 50000 µs = 20 Hz，对应 deviceMotionUpdateInterval = 1/20
```

传感器回调**不要跑在主线程**：20 Hz 的回调加上滤波运算放主线程会和 Compose 的重组抢帧。用专门的 `HandlerThread`，滤波在那条线程上做，只把结果发到 `StateFlow`。

单位换算：`SensorEvent.values[0..2]` 是 **m/s²**，除以 `SensorManager.GRAVITY_EARTH`（= 9.80665f，和 iOS 用的 `9.80665` 是同一个数）得到 G。**除法要在三轴合成之前还是之后不影响结果**（线性），但要在**死区判定之前**做，否则 0.025 这个阈值的单位就错了 —— 0.025 m/s² 和 0.025 G 差 40 倍。

#### 坑 (a) · `registerListener` 的采样率参数只是建议

`samplingPeriodUs` 是 hint。实际频率由 HAL 决定，常见偏差：请求 20 Hz 拿到 15 Hz 或 50 Hz；同一台机器充电时和省电模式下不一样；有的 ROM 在后台把速率降到 5 Hz。

**后果：α = 0.18 和 maxStep = 0.08 都是「每样本」量，采样率一变，滤波的时间特性就变了。**

- 实际 100 Hz：α = 0.18 的等效 τ 从 0.252 s 掉到 0.050 s，滤波器快了 5 倍 → G 值噪声大幅上升，`maxAccelerationG` 被单次尖峰顶高。
- 实际 5 Hz：τ 涨到 1.008 s，慢 4 倍 → G 值反应迟钝，急加速的峰值被削平，`maxAccelerationG` 系统性偏低。
- `maxStep = 0.08/样本` 同理：100 Hz 下等于 8 G/s（形同虚设），5 Hz 下等于 0.4 G/s（把真实加速度削掉）。

**规定的做法：把两个「每样本」量换算成「每秒」量，用实测 dt 逐样本重算。**

```kotlin
// RecordingThresholds.kt —— 从 iOS 的 20 Hz 字面量反推出的率无关形式
const val G_FILTER_TAU_SECONDS = 0.252        // = -0.05 / ln(1 - 0.18)
const val G_MAX_RATE_G_PER_SECOND = 1.6       // = 0.08 / 0.05

// 每个样本：
val dt = (event.timestamp - lastTimestampNanos) / 1e9
val alpha = 1.0 - exp(-dt / G_FILTER_TAU_SECONDS)     // dt = 0.05 时 alpha = 0.18，与 iOS 一致
val maxStep = G_MAX_RATE_G_PER_SECOND * dt            // dt = 0.05 时 maxStep = 0.08，与 iOS 一致
```

单测必须钉住：**喂 dt = 0.05 的序列进去，输出与 iOS 的定值 α = 0.18 / maxStep = 0.08 逐样本一致（误差 < 1e-9）**。这条测试是「换算没写错」的唯一凭证。

`maximumMotionSampleGap = 0.75 s`（#14）在 20 Hz 下是 15 个采样间隔。如果实测采样率低到 5 Hz，0.75 s 只有 3.75 个间隔，正常抖动就会频繁触发「重置滤波器 + 1.1 s 冷却」，G 值会一直是 0。规定用 `max(0.75, 4 × 实测采样间隔)`，实测间隔在启动后头 2 秒用中位数估出来。**这一条是从 iOS 数值推导出的适配，不是抄的，要在代码注释里写明。**

启动时还要采一次实际速率并记进诊断日志（5.1）：前 40 个事件的 `timestamp` 差值中位数。真机调参时这是第一个要看的数字。

#### 坑 (b) · `TYPE_LINEAR_ACCELERATION` 是复合传感器，各家实现质量差一个量级

它不是硬件直出，是 HAL 用「加速度计 − 重力估计」合成的。重力估计的做法各家不同：有陀螺仪的用九轴融合（等价 iOS 的 Device Motion，质量接近）；没有的用加速度计低通估重力，**残留噪声可以比 iPhone 大一个数量级**，静止时读数在 ±0.05 G 甚至 ±0.15 G 上跳。

三条直接后果：

1. **死区 0.025 G 在噪声大的机型上完全挡不住。** 静止放桌上 `currentAccelerationG` 会一直显示 `0.05 G` 上下。
2. **`maxAccelerationG` 会被噪声顶满。** 一次骑行的最大 G 值取的是全程最大值，采到一个 1.2 G 的噪声尖峰就永久污染这条记录，而且不可逆（没有存原始序列）。
3. **上限 1.35 G 可能被误触发**，导致 `currentAccelerationG` 频繁被强制归零（2.6 的 ⑤），G 值断续闪烁。

**规定：启动记录前做一次 1.5 秒的静止噪声本底测量**（`RideRecorder` 之外，放 `MotionSource` 的初始化路径），算出静止时 G 值的标准差 σ，写进诊断日志和这条记录的元数据。死区在实现上写成 `max(0.025, 3σ)`，σ 的实测值和最终生效的死区都要落日志。**不要把死区硬编码成某个更大的值** —— 那等于对所有机型放弃低 G 段的分辨率。

`maxAccelerationG` 的抗尖峰做法（第六节要验证效果）：候选最大值必须**连续 3 个样本都超过当前最大值**才采纳。这是 Android 侧新增的，iOS 没有；理由是 iOS 的 Device Motion 噪声本底足够低，单样本尖峰不成问题。加不加、阈值取几，见 `## 待定` 的 P6。

#### 坑 (c) · 没有陀螺仪的低端机上这个传感器可能根本不存在

`getDefaultSensor(TYPE_LINEAR_ACCELERATION)` 返回 `null`。**必须检测并降级，不能 NPE，也不能静默什么都不做。** 三级降级：

| 级别 | 条件 | 做法 | G 值质量 |
| --- | --- | --- | --- |
| 1 | `TYPE_LINEAR_ACCELERATION != null` | 直接用 | 对齐 iOS |
| 2 | 它为 null，但 `TYPE_ACCELEROMETER` + `TYPE_GRAVITY` 都有 | 逐轴相减去重力 | 略差，可用 |
| 3 | 只有 `TYPE_ACCELEROMETER` | 自己低通估重力（τ 取 1.0 s 左右）再相减 | 差，噪声明显 |
| 4 | 连加速度计都没有 | **走 GPS 反推那条路径**（2.6 备用路径，上限 0.75 G，只有加速有值） | 只能看趋势 |

第 4 级正好对应 iOS 的 `isDeviceMotionAvailable == false` 分支，所以 `RideRecorder` 里那个统一的 `hasImu: Boolean` 在第 4 级置 false，其余置 true。

**界面必须说明降级**：第 3、4 级下 G 值的绝对数值不具可比性。文案与呈现归 4.3，但**判定与标记归 4.2**：`RideRecorder` 的状态里加 `imuQuality: ImuQuality`（`Fused` / `GravitySubtracted` / `LowPassEstimated` / `None`），落库时写进 `rides` 表（Phase 0 的 0.3 表结构里要加这一列）。没有这一列的话,三个月后回看一条记录根本不知道那个 `0.82 G` 是什么档次的传感器测的。

**锁屏时传感器会停。** `TYPE_LINEAR_ACCELERATION` 默认是非唤醒传感器（`Sensor.isWakeUpSensor() == false`），CPU 进入 suspend 后事件停止投递或被缓存到 FIFO 里延迟批量吐出。定位那一路有前台服务保着，G 值这一路没有。iOS 侧 `allowsBackgroundLocationUpdates` 顺带把 CoreMotion 也保住了，Android 不会。

规定：`RideRecordingService` 在记录期间持有 `PARTIAL_WAKE_LOCK`（`PowerManager.newWakeLock(PARTIAL_WAKE_LOCK, "NinePlus:ride")`），`stopSelf()` 前释放。这会增加耗电，是必须付的代价 —— 否则「锁屏继续采集」只对轨迹成立、对 G 值不成立，而且 `maxAccelerationG` 会莫名偏低。真机上要量锁屏 10 分钟期间 IMU 事件的连续性（第六节）。

批量延迟（`registerListener` 的 `maxReportLatencyUs`）**必须传 0**。给了非零值，HAL 会把事件攒在 FIFO 里一次吐出，`SensorEvent.timestamp` 虽然还是对的，但一次投递十几个事件会让「实时 G 值」变成阶梯状，而且 `maximumMotionSampleGap` 的判定被打乱。

### 3.4 落库：Room 批量写

轨迹点是 1 Hz 写入，两小时骑行 7200 条。逐条 `insert` 意味着 7200 个事务，每个事务都有 fsync，实测会造成可感知的耗电和偶发卡顿。

**规定的批量策略**

| 参数 | 值 | 理由 |
| --- | --- | --- |
| 攒够多少条 flush | **20 条** | 1 Hz 下 20 秒一次事务 |
| 最长多少秒 flush | **10 s** | 低速/静止时点少，不能无限期攒 |
| 事务边界 | 一次 `@Transaction` 内 `insertAll(points)` + `updateRideSummary(...)` | 摘要与点必须同一个事务，否则崩溃后 `point_count` 与实际行数不符 |
| 强制 flush 时机 | 记录停止、服务 `onDestroy`、`onTrimMemory(TRIM_MEMORY_COMPLETE)`、进程即将被杀的任何信号 | |
| 序号 | `ride_points.seq` 由 `RideWriteBuffer` 单调分配，不依赖时间戳排序 | 时间戳可能相等（同一秒两个点） |

```kotlin
class RideWriteBuffer(private val dao: RidePointDao, private val rideDao: RideDao, private val scope: CoroutineScope) {
    private val pending = ArrayDeque<RidePointEntity>()
    private var lastFlushElapsed = 0L

    suspend fun add(point: RidePointEntity) {
        pending += point
        if (pending.size >= 20 || SystemClock.elapsedRealtime() - lastFlushElapsed >= 10_000) flush()
    }

    suspend fun flush() { /* @Transaction: insertAll + 更新 rides 的累计字段 */ }
}
```

**App 被杀怎么不丢数据**

iOS 侧是全丢（本文开头的修正 3）。Android 侧靠三件事：

1. **记录一开始就往 `rides` 插一行**，`ended_at = null` 标记「进行中」。不要等 `stop()` 才建行。
2. 每次 flush 顺手把当前累计值（`distance_meters`、`max_speed_kmh`、`max_accel_g`、`point_count`）写进这一行。最坏情况丢最后 20 条点 / 10 秒。
3. **启动时扫 `ended_at IS NULL` 的行**，用已落库的点跑一遍 `recalculatedDistanceMeters`（2.9 的重算，阈值用 #25/#26/#27）补完摘要。要不要在界面上问用户「发现一条未完成的记录，恢复还是丢弃」是产品决策，见 `## 待定` 的 P5。

**Room 配置**：WAL 默认开着，不要关。`ride_points` 建 `(ride_id, seq)` 复合索引。外键 `ON DELETE CASCADE`（Phase 0 的 0.3 已定）—— 注意 Room 需要显式 `db.setForeignKeyConstraintsEnabled(true)` 或在 `@Database` 上依赖迁移里的 `PRAGMA foreign_keys=ON`，否则 CASCADE 不生效、删记录会留下孤儿点。

**`StateFlow` 更新频率**：G 值 20 Hz，直接推给 Compose 会造成每秒 20 次重组。`RideRecorder` 内部保持全速率（`maxAccelerationG` 必须看到每个样本），对外分两个 Flow：`instantState`（20 Hz，只给 4.3 的仪表用，收集侧自行 `conflate()`）和 `summaryState`（1 Hz，距离/时长/最大值等，给指标格子用）。iOS 侧靠 SwiftUI 的 runloop 合并加 `TimelineView(.periodic(by: 1))`（`NinebotRecordingView.swift:322`）达到同样效果。

### 3.5 前台服务

骨架、权限、通知渠道、国产 ROM 引导**全部见 Phase 0 的 0.6**，本文只补 4.2 专有的四点：

1. **`foregroundServiceType="location"`**（0.6 已声明）。Android 14+ 起，声明了这个类型就必须持有 `FOREGROUND_SERVICE_LOCATION` 权限，否则 `startForeground` 抛异常。
2. **`ACCESS_BACKGROUND_LOCATION` 的申请时机**：0.6 定的是「开始记录时申请」。这里补一条需要真机验证的细节 —— 一个从前台启动的 location 类型前台服务，在其运行期间本身就被系统当作「前台在用定位」，锁屏后定位不会被掐；这种场景下 `ACCESS_BACKGROUND_LOCATION` 并非必需。它真正必需的场景是 5.4 的后台定时刷新（没有可见 Activity 也没有前台服务）。**按 0.6 的口径实现（开始记录时申请），但把「拒绝了后台定位权限时锁屏 10 分钟轨迹是否连续」列为验收项**（第七节），实测结果反过来修正 0.6。
3. **服务与 recorder 的生命周期**：`RideRecorder` 的实例归服务持有，不归 ViewModel 或 Composable。页面销毁（旋转、切 Tab、退到桌面）不能中断记录。预览态（2.10）不启服务，只在 ViewModel 里持有一个轻量实例；点「开始记录」时启服务并把状态交接过去。**交接时不要重建滤波器状态** —— 重建会让速度和 G 值从 0 重新爬升，用户看到的是「一按开始，速度掉到 0」。
4. **通知内容**：0.6 定了「显示已记录时长和距离」。更新频率压到 **1 Hz**，且用 `NotificationCompat.Builder` 复用同一个 builder 只改文本 —— 每秒重建通知在部分 ROM 上会造成通知栏闪动。

---

## 四 · 界面侧要保留的行为

只列 4.2 负责产出的部分，渲染归 4.3 / 4.4。

**`RecordingHeader.statusText` 的五级优先级**（`NinebotRecordingView.swift:166-182`）：

```
lastErrorText != nil                        → 直接显示错误原文（颜色 .orange，:184-186）
isRecording                                 → "正在记录 · 可以锁屏，后台继续"
authorizationStatus == .notDetermined       → "允许定位后会显示实时位置"
!isAuthorized                               → "需要在系统设置里允许定位"
其他                                        → "当前位置实时显示，点击开始记录"
```

`lastErrorText` 显示的是 `error.localizedDescription` 原文（`:246-250`），中文由系统提供。**Android 侧的 SDK 错误信息不是中文**（高德给 `errorCode` + 英文 `errorInfo`，Google 给 `ApiException`），必须自己映射成中文文案，否则界面上会出现英文。映射表放 `strings.xml`，至少覆盖：定位服务关闭、权限被拒、无网络（高德的辅助定位失败）、GPS 搜星超时、高德 Key 鉴权失败（`errorCode = 7`，接入期最常见）。

**四个由 4.2 直接产出的错误文案**（原文照抄）：`"系统定位服务未开启"`（`:116`、`:150`）、`"需要定位权限才能显示实时位置"`（`:126`）、`"请允许定位后再开始记录"`（`:156`）、`"需要定位权限才能记录轨迹"`（`:161`）。注意后两条分别属于 `start()` 的不同分支，且 `"请允许定位后再开始记录"` 那条**不改 `gpsQuality`**。

---

## 五 · 陷阱清单

1. **定位间隔低于 450 ms → 距离恒为 0，无任何报错。** 第 2.4 节陷阱 A。间隔钉在 1000 ms，并加一条运行时断言：连续 10 个 fix 的中位间隔 < 0.45 s 就往诊断日志写警告。

2. **`deltaTime` 用墙钟 → NTP 校时随机毁掉一段记录。** 第 3.1 节。全部用单调时钟。

3. **G 值单位。** `SensorEvent.values` 是 m/s²，CoreMotion 的 `userAcceleration` 是 G。死区 0.025、上限 1.35、maxStep 0.08 全部是 **G**。除以 `GRAVITY_EARTH` 要在这些判定之前。

4. **α = 0.18 直接抄字面量 → 在非 20 Hz 设备上滤波特性完全不同。** 第 3.3 节坑 (a)。速度那两个 α（0.34/0.48）可以抄字面量（定位间隔固定 1 s），G 那个不行。

5. **采集用 60 m 精度门限，重算用 120 m；采集段长上限 160 m，重算 300 m；采集间隔上限 6 s，重算 30 s。** 三组阈值必须分开定义（#11/#25、#4/#27、#7/#26）。合并成一套的话，要么实时距离虚高、要么结算距离偏低。

6. **停止记录时距离会跳一下。** 第 2.9 节。实时值和结算值本来就是两个数。4.4 的列表/详情一律用结算值。

7. **别用不带轨迹点的摘要回写数据库。** 第 2.9 节末。iOS 侧有一句显式守卫，Room 侧对应「更新 `rides` 时不要动 `ride_points`」。

8. **`maxAccelerationG` 不可逆。** 只存最大值，不存原始序列。一个噪声尖峰永久污染一条记录。坑 (b)。

9. **锁屏后 IMU 会停，除非持 `PARTIAL_WAKE_LOCK`。** 坑 (c) 末。只测轨迹连续性测不出来这个问题，要单独看 G 值的样本连续性。

10. **`maxReportLatencyUs` 必须为 0。** 非零会让事件批量吐出，打乱 `maximumMotionSampleGap` 判定。

11. **高德 SDK 的隐私合规两个静态调用漏掉 → 完全拿不到定位，且不报明确错误。** 第 3.2 节。

12. **高德没有 `speedAccuracy` → `speedCandidate` 第一条分支永远不成立。** 第 3.2 节给了明确处置，不要让它默默退化成全程位移反推。

13. **`AMapLocation.errorCode != 0` 时坐标是 0,0。** 不查这个字段的话，`isUsable` 的经纬度范围检查会放它过去（0,0 在合法范围内），轨迹上会出现一条飞到几内亚湾的线。iOS 侧不存在这个字段所以没有对应检查 —— **这是必须新增的一道闸门**。

14. **`gpsQuality` 在一次 `consume` 内可能被赋值两次**（先 good/weak 再 stabilizing）。第 2.7 节末。Compose 侧算出终值再发一次。

15. **`speedSamples` 无上限增长。** 1 Hz 下两小时 ≈ 7200 个 `Double`，而它服务的那条分支几乎不触发。Android 侧改成只维护 `sum` 和 `count` 两个数（数值等价，第 2.9 节的均值公式不变），别照抄数组。

16. **记录中重复调 `start()` 会清空一切。** 第 2.10 节。`RideRecorder.start` 开头加 `if (isRecording) return`。

17. **`NinebotRideRecorder.swift:296-299` 是不可达代码。** 直译时省掉并注明原因，不要当成一条真实规则去实现（照抄也无害，但会让人以为存在第二道时间检查）。

18. **`stop()` 不停止定位与 IMU。** 停止记录后页面仍在预览态。Android 侧前台服务要停（`stopSelf`）但轻量预览要接上，交接见第 3.5 节第 3 点。

---

## 六 · 真机调参（**不可跳过**）

> **所有 32 个数值都是照 iPhone 的 CoreLocation / CoreMotion 特性调出来的。照抄到 Android 上只是「有一个能跑的起点」，不是「做完了」。**
>
> 这一节存在的唯一目的：让实施的人不要以为把数字抄对就结束了。10 天工期里**至少留 3 天**给这一节。

### 6.1 最可能需要改的阈值，按优先级

| 优先级 | 阈值 | 为什么 Android 上会不一样 | 预期方向 |
| --- | --- | --- | --- |
| **1** | `#18` G 值死区 **0.025 G** | `TYPE_LINEAR_ACCELERATION` 噪声本底差一个量级（坑 b） | 需要按机型的 3σ 抬高 |
| **2** | `#19/#20` G 滤波 τ = 0.252 s / 1.6 G/s | 实际采样率不是 20 Hz（坑 a） | 换算后应基本对齐，但要验证 |
| **3** | `#3` IMU G 上限 **1.35 G** | 噪声尖峰会顶到上限触发归零，G 值断续闪 | 可能要抬到 1.6–2.0，或改为「超限保持上一值」而非归零 |
| **4** | `#11` 水平精度上限 **60 m** | 高德融合了基站/WiFi，`accuracy` 的含义和 CoreLocation 不同；城市峡谷里可能大量点在 60–100 m | 可能要放宽，或对 `locationType` 分档 |
| **5** | `#10` good/weak 分界 **35 m** | 同上 | 同上 |
| **6** | `#23` `speedAccuracy` 上限 **6 m/s** | 高德不给，Google 侧很多设备不填 | 需要统计填充率再定 |
| **7** | `#8/#9` 8 s 空档 / 2.2 s 冷却 | 国产 ROM 的后台调度会造成 iOS 上不出现的空档 | 可能要放宽 8 s，否则频繁进冷却、距离持续少算 |
| **8** | `#14` IMU 采样间隔上限 **0.75 s** | 低采样率机型会频繁误触发（坑 a 末） | 已规定用 `max(0.75, 4 × 实测间隔)`，要验证 |
| **9** | `#12/#13` 速度限幅 4.5 / 7.0 m/s² | 定位间隔固定 1 s，理论上一致；但融合定位的速度跳变模式与 CoreLocation 不同 | 大概不用改，要确认 |
| **10** | `#1` 速度上限 132 km/h | 电动自行车用不到这么高，两端一致即可 | 不动 |

### 6.2 怎么测

**测试 A · 静止噪声本底（10 分钟，每台机器必做，最先做）**

手机放桌上不动，跑记录 10 分钟。看：

- IMU 实际采样率（前 40 个事件时间差的中位数）—— 期望 20 Hz 附近
- 静止 G 值的均值与标准差 σ、最大值 —— **σ 是死区阈值的依据**
- `maxAccelerationG` 最终值 —— **理想是 0.00，超过 0.10 说明必须加抗尖峰（坑 b）**
- `distanceMeters` 最终值 —— **理想是 0，超过 20 m 说明静止漂移会污染距离，`distanceFilter` 的 1 m 过滤要重新审视**
- `gpsQuality` 的状态分布 —— 室内应该主要是 `.weak`

**测试 B · 定长直线（500 m，每台机器必做）**

找一段能用地图量准的直路（操场跑道一圈、或两个明确地标之间），推着车或匀速骑一遍。判定标准：**记录距离与实测距离误差 < 3%**（500 m 允许 ±15 m）。

同时看：定位实际间隔的中位数（必须 ≥ 0.45 s，见陷阱 A）、`points` 数量（500 m 骑行约 2 分钟 ≈ 120 点）。

**测试 C · 里程表对照（5 km 以上，每台机器必做）**

对照物是**车辆里程表读数**（`totalMileage` 前后差值，从车况接口读，不靠肉眼看仪表）。骑一段包含直路、路口、红灯的真实路线。判定标准见第七节。

同时记：红灯停车次数、每次停车时长。**用停车次数去解释距离偏差** —— 陷阱 B 说每次长停会丢 2.2 s 的距离，5 个红灯每次起步 15 km/h 折合约 5 × 9 m = 45 m。如果实测偏差和这个估算量级吻合，说明偏差来源已经定位清楚，不要再瞎调阈值。

**测试 D · 急加速 / 急刹（同一段路来回 3 次）**

从静止全油门加速到 25 km/h，然后急刹到停。看 `maxAccelerationG`。

- 参照值：电动自行车 0–25 km/h 大约 3–4 秒，折合 **0.18–0.24 G**。加上路面颠簸和车身晃动，合理读数在 **0.3–0.6 G**。
- **读数 > 1.0 G 说明滤波没起作用或噪声失控**，回头查坑 (a)/(b)。
- **读数 < 0.15 G 说明滤波过度**（采样率过低导致 τ 太大，或 maxStep 太小）。
- 同一段路来回 3 次的 `maxAccelerationG` **离散度应当 < 20%**。离散度大说明是噪声在决定这个数，不是加速度。

**测试 E · 锁屏连续性（10 分钟）**

开始记录后立刻锁屏，装兜里骑 10 分钟。停下后看：

- 轨迹点的时间间隔序列有没有 > 8 s 的空档（对应 Phase 0 的 0.6 验收项）
- **IMU 样本的连续性** —— 这一项 0.6 没有，必须在这里测。做法：诊断日志里记 IMU 事件计数，10 分钟 × 20 Hz 应该是 12000 上下；掉到几百说明 `PARTIAL_WAKE_LOCK` 没生效或被 ROM 掐了
- 前台服务通知有没有被 ROM 杀掉

**测试 F · 双 SDK 路径对照（同一台有 GMS 的机器，同一段路）**

同一台设备、同一条路线，分别强制走高德和 Google 两条路径各骑一次。对比距离、最高速、点数、速度曲线形状。**两条路径的距离差异应当 < 2%**。差异更大说明高德那边缺 `speedAccuracy` 导致的分支差异（第 3.2 节）在实质上改变了结果，要回头处理。

### 6.3 至少覆盖几个品牌

**硬性要求：至少 3 个品牌、4 台设备。** 必须包含：

| 类别 | 为什么必须有 | 具体要求 |
| --- | --- | --- |
| **无 GMS 的国产旗舰**（华为 / 荣耀） | 唯一能验证高德路径是主路径的场景；华为的 HMS 定位与高德的交互是独有风险 | 至少 1 台 |
| **有 GMS 的国产机**（小米 / OPPO / vivo） | 验证两条路径都能跑、`LocationSourceFactory` 的判定正确；这三家的后台管控最凶 | 至少 2 台，不同厂家 |
| **低端机 / 老机型** | 验证坑 (c) 的降级链。目标是找到一台 `TYPE_LINEAR_ACCELERATION` 为 null 或噪声极大的设备 | 至少 1 台，价位 1000 元以下或 5 年以上机龄 |

Phase 4 的计划表写的是「至少覆盖两个品牌」。这里要求 3 个品牌是因为「无 GMS」和「后台管控最凶」是两个不重叠的风险，各需要一台，再加一台低端机验降级。**如果只能拿到两台，优先保「无 GMS 国产旗舰」+「低端机」** —— 有 GMS 的路径是回退路径，风险最低。

### 6.4 调参数据记在哪

**规定：`docs/phase4-sensor-tuning-log.md`**，由实施的人在调参过程中建立并维护，一台设备一节。每节固定这些字段：

```
## {品牌} {型号} / Android {版本} / {ROM 版本}

- GMS：有 / 无
- 采用路径：高德 / Google
- TYPE_LINEAR_ACCELERATION：有 / 无（降级到第 __ 级）
- IMU 实测采样率（中位）：__ Hz
- 静止 G 值 σ：__ G，最大值 __ G，10 分钟 maxAccelerationG：__ G
- 静止 10 分钟累计距离：__ m
- 定位实测间隔（中位）：__ s
- speedAccuracy 填充率：__ %
- 测试 B（500 m 直线）：记录 __ m，误差 __ %
- 测试 C（里程表对照）：里程表 __ km，记录 __ km，误差 __ %，红灯停车 __ 次
- 测试 D（急加速）：三次 maxAccelerationG = __ / __ / __ G，离散度 __ %
- 测试 E（锁屏 10 分钟）：最大轨迹空档 __ s，IMU 事件数 __ / 期望 12000
- 测试 F（双路径对照）：高德 __ km vs Google __ km，差异 __ %
- **本机偏离默认值的阈值**：#__ 从 __ 改成 __，理由：__
```

最后一行是这份日志的核心。**任何阈值偏离默认值都必须记在这里，写清是哪一号常量、改成了多少、依据是哪次测试的哪个数字。** 没有依据的调整不许进代码。

如果多台设备都需要同一个方向的调整，就把默认值改掉并在 `RecordingThresholds.kt` 的注释里写明「原 iOS 值 __，因 __ 改为 __，依据 tuning-log 的 __ 节」。**保留原 iOS 值在注释里，不要覆盖掉。** 两端夹具对齐时要用。

如果出现「某机型必须用一套明显不同的值」，那说明需要按机型分档而不是改全局默认值 —— 那是个产品决策，见 `## 待定` 的 P7。

---

## 七 · 验收标准

### 7.1 纯逻辑（不需要真机，用录制序列跑单测）

- [ ] `RecordingThresholds.kt` 里的 32 个数值与本文 2.1 / 2.2 两张表**逐个相同**，每个都带源码 `文件:行号` 注释
- [ ] 阈值表用一个反射单测锁死：常量个数 == 32，任何增删改都让测试失败
- [ ] 喂 dt = 0.05 s 的等间隔 IMU 序列，`MotionGFilter` 的输出与 iOS 定值 α = 0.18 / maxStep = 0.08 的实现**逐样本误差 < 1e-9**（证明第 3.3 节的率无关换算没写错）
- [ ] 喂 dt = 1.0 s 的定位序列，`SpeedFilter` 输出与 iOS 逐样本误差 < 1e-9
- [ ] 五态机的 12 条转移（2.7 的转移图）各命中一次
- [ ] 2.7 那张「哪些点不入库」表的 10 行各构造一个用例，`points.size` 与 `distanceMeters` 的增量与表一致
- [ ] 构造 0.2 s 间隔的定位序列，断言**触发陷阱 A 的运行时警告**（证明防护生效）
- [ ] 同一份 100 点序列，实时累计距离与 `recalculatedDistanceMeters` 的差值被明确断言（证明 2.9 的双口径是有意的，不是 bug）
- [ ] `deltaTime` 计算全部走单调时钟：构造一个「墙钟中途倒退 3600 s」的序列，输出与不倒退时**完全相同**
- [ ] 坐标转换往返：中国境内随机 1000 个点，WGS-84 → GCJ-02 → WGS-84 误差 < 0.5 m；境外点两次转换都返回原值
- [ ] `errorCode != 0` 的高德定位（坐标 0,0）被拒绝，不进 `points`
- [ ] 记录中重复调 `start()` 不清空数据
- [ ] 用不带轨迹点的摘要调一次保存，`ride_points` 的行数不变

### 7.2 真机（每台设备都要过）

- [ ] **测试 C：骑 5 km 以上，记录距离与车辆里程表读数（`totalMileage` 前后差）误差 < 5%**。同时在调参日志里写清红灯停车次数，并说明偏差与陷阱 B 的估算是否量级吻合
- [ ] **测试 B：500 m 定长直线，误差 < 3%**
- [ ] **静止 10 分钟：`distanceMeters` < 20 m，`maxAccelerationG` < 0.10 G**
- [ ] **测试 D：同一段急加速来回 3 次，`maxAccelerationG` 落在 0.3–0.6 G，三次离散度 < 20%**
- [ ] **测试 E：锁屏 10 分钟，轨迹点最大间隔 < 8 s，IMU 事件数 ≥ 期望值的 90%**（12000 × 0.9 = 10800）
- [ ] 定位实测间隔中位数 ≥ 0.45 s，且诊断日志里**没有**陷阱 A 的警告
- [ ] **测试 F：同机双路径同路线，距离差异 < 2%**（仅有 GMS 的设备）
- [ ] 记录中旋转屏幕 5 次、切到其他 App 再回来 5 次：`points` 连续，累计值不重置，速度不掉到 0
- [ ] 记录中杀掉 App（`adb shell am force-stop`），重启后 `ended_at IS NULL` 的记录能被扫出来，已落库的点数 ≥ 被杀前的点数 − 20
- [ ] 拒绝 `ACCESS_BACKGROUND_LOCATION` 后仍锁屏骑 10 分钟：轨迹是否连续 —— **结果写回 Phase 0 的 0.6**（第 3.5 节第 2 点）
- [ ] 在无 `TYPE_LINEAR_ACCELERATION` 的设备上（或用 `Sensor` 打桩模拟）四级降级链各走一次，界面不崩且 `imuQuality` 落库正确
- [ ] 关掉系统定位服务、撤销定位权限、高德 Key 填错三种情况各显示一条**中文**错误，不出现英文原文
- [ ] `docs/phase4-sensor-tuning-log.md` 已建立，覆盖 ≥ 3 品牌 / ≥ 4 台设备，6.4 的字段全部填满

### 7.3 与 iOS 的对齐

- [ ] 同一份录制的 fix + motion 序列（存成 JSON 夹具，与 iOS 共享），两端 `RideRecorder` 输出的 `distanceMeters`、`maxSpeedKmh`、`maxAccelerationG`、`points.size`、每个点的 `speedKmh` / `accelerationG` **逐字段误差 < 1e-6**
- [ ] 上一条在「阈值全部取 iOS 默认值」的配置下必须通过。任何按机型改过的阈值都不参与这条对齐测试，改动记在调参日志里

---

## 待定

需要人拍板的项。每条写清现状 / iOS 怎么做的 / 分歧点 / 建议决定时机。

### P1 · GPX 导出用哪个坐标系

**现状**：本文规定库里存 WGS-84（2.11）。导出时转不转成 GCJ-02 没有定。

**iOS 怎么做的**：转了。`NinebotRecordingView.swift:897` 在生成 `<trkpt>` 之前调 `recordingMapCoordinate`，导出的是 GCJ-02 坐标。

**分歧点**：GPX 规范明确要求 WGS-84，所以 iOS 导出的文件导进任何标准工具（Garmin、Strava、佳明、大部分 GIS）都会整体偏移 100–700 m。但如果用户的用途是导进国内地图 App 看，转过的反而"看着对"。

**建议决定时机**：Phase 4 的 4.5（GPX 导出，另一份规格）。**4.2 侧不受影响** —— 无论怎么定，库里存 WGS-84 都是对的，转换发生在导出那一层。

### P2 · 高德和 Google 都拿不到定位时垫不垫原生 `LocationManager`

**现状**：D8 已经把这条列为遗留问题，留到 Phase 0 的 0.6 实测再定。到 4.2 还没定的话，本文的 `LocationSourceFactory` 在两条路径都不可用时只能报 `.unavailable`。

**iOS 怎么做的**：不存在这个问题，CoreLocation 是系统唯一入口。

**分歧点**：原生 `LocationManager` 任何设备都有、不依赖任何 SDK，但不做多源融合，室内和城市峡谷精度明显差；而且返回 WGS-84，需要走和 Google 相同的适配路径（这部分代码是复用的，增量成本低）。真正的问题是：如果一台设备连高德都拿不到定位，垫一层裸 GPS 之后记出来的数据可用性存疑，可能不如直接告诉用户"这台设备不支持"。

**建议决定时机**：Phase 0 的 0.6 实测时定。如果拖到 4.2，就在第六节的品牌覆盖测试里顺便验证 —— 4 台设备里有没有一台真的两条路径都不可用。

### P3 · 静止时的 1 m 位移过滤要不要保留

**现状**：本文规定两条 SDK 路径都保留 1 m 过滤，与 iOS 的 `distanceFilter = 1` 对齐（3.2 节）。

**iOS 怎么做的**：`distanceFilter = 1`（`NinebotRideRecorder.swift:70`）。副作用是红灯停车超 8 秒后起步会丢 2.2 秒的距离（陷阱 B）。

**分歧点**：三个选项，各有代价 ——

| 方案 | 代价 |
| --- | --- |
| 保留 1 m 过滤（本文默认） | 每次长停丢约 2.2 s 距离，5 个红灯约 45 m，5 km 骑行约 0.9% 偏小 |
| 去掉过滤，静止时也持续投递 | 8 秒空档规则不再触发，但静止 GPS 抖动会被当真实位移累计，静止 10 分钟可能虚增几十米 |
| 保留过滤，但把 `maximumLocationGapBeforeCooldown` 从 8 s 放宽到比如 60 s | 长停后不进冷却，距离不丢；但真正的信号中断（进隧道、被 ROM 掐掉）也不会进冷却，中断前后两点会被当成一段真实位移（受 160 m 段长上限保护，但隧道口到隧道口不到 160 m 的情况下会算错） |

**建议决定时机**：第六节的测试 A（静止漂移量）和测试 C（里程表对照，含红灯计数）做完之后。这两组数据能量化前两个方案的实际代价，那时候再定不用猜。

### P4 · 要不要加暂停 / 恢复

**现状**：本文完全照 iOS，只有开始和结束（2.10）。

**iOS 怎么做的**：没有暂停。看起来像暂停的是 2.2 秒稳定化冷却。

**分歧点**：骑行中途停下来买东西、进商场，这段时间的墙钟计入时长，所以**平均速度会被拉低**（2.9 的分母是墙钟时长）。加暂停能解决，但要定：暂停期间还采不采点、恢复时要不要走稳定化冷却、暂停时长算不算进 `durationSeconds`、暂停状态要不要落库（App 被杀后恢复时怎么办）。这四个子问题每一个都会影响 `rides` 表结构和 4.4 的详情展示。

**建议决定时机**：Phase 4 收尾，实际用过几次之后。**不要在 4.2 里预留半成品的暂停状态** —— 落库了一个永远不会被置位的 `paused_at` 列，比没有更糟。

### P5 · 恢复未完成的记录，要不要给界面入口

**现状**：本文规定 App 被杀后启动时扫 `ended_at IS NULL` 的行并补完摘要（3.4）。**补完之后怎么处理没定** —— 直接当成一条正常记录存下来，还是问用户。

**iOS 怎么做的**：数据全丢，没有任何恢复（开头的修正 3）。所以 iOS 侧没有可参照的行为。

**分歧点**：三个选项 ——

| 方案 | 效果 |
| --- | --- |
| 静默补完并存为正常记录 | 用户下次打开会看到一条自己没点"结束"的记录，`ended_at` 是最后一个点的时间。不需要交互 |
| 启动时弹一次询问「发现一条未完成的记录（__ km / __ 分钟），保存还是丢弃？」 | 语义清楚，但多一个打断 |
| 静默丢弃（与 iOS 一致） | 白写第 3.4 节的增量落库 —— 那部分仍然值得写（它同时解决了 7200 次事务的性能问题），但恢复能力浪费了 |

**建议决定时机**：Phase 4 的 4.4（记录列表）。那时候能看到这条记录在列表里长什么样再定。**4.2 侧无论如何都要按 3.4 增量落库**，这一条只影响启动时那段处理逻辑，改动很小。

### P6 · `maxAccelerationG` 要不要加抗尖峰，阈值取几

**现状**：本文提了一个「连续 3 个样本都超过当前最大值才采纳」的做法（3.3 坑 b），但标注为待验证。

**iOS 怎么做的**：没有抗尖峰，`max(maxAccelerationG, currentAccelerationG)` 单样本就采纳（`:322`）。iOS 的 Device Motion 噪声本底足够低，不需要。

**分歧点**：加了之后 Android 和 iOS 的 `maxAccelerationG` 在同一份夹具上会**不一致**（7.3 的对齐测试要为它开例外）。不加的话，噪声大的机型上这个数字基本没有意义。「连续 3 个」这个数字本身也是拍的，可能是 2 也可能是 5。

**建议决定时机**：第六节的测试 A（静止 10 分钟的 `maxAccelerationG`）做完。如果所有设备静止 10 分钟都 < 0.05 G，这条就不用加；只要有一台超过 0.10 G，就必须加，并用那台设备的数据定「连续几个」。

### P7 · 阈值要不要按机型分档

**现状**：本文规定一套全局默认值，偏离必须记进调参日志（6.4）。

**iOS 怎么做的**：一套值，全机型通用。iPhone 的传感器一致性足够好。

**分歧点**：如果调参时发现某个机型必须用明显不同的值（最可能是 G 值死区，坑 b），有三条路 ——

| 方案 | 代价 |
| --- | --- |
| 全局取最保守的值 | 好设备上白白损失分辨率 |
| 按 `Build.MANUFACTURER` / `Build.MODEL` 分档 | 维护成本高，没测过的机型落到哪一档是猜的，新机型上市就要更新 |
| 运行时自适应（用启动时的静止噪声测量结果动态定死区） | 本文的死区 `max(0.025, 3σ)` 已经是这个思路的一半。彻底做的话 G 上限、`maximumMotionSampleGap` 都能自适应，但两端夹具对齐会变得很难验证 |

**建议决定时机**：第六节调参跑完，看实测的机型间差异有多大。差异在 2 倍以内建议取保守全局值；超过 5 倍就得走自适应。
