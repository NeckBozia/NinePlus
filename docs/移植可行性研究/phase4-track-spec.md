# Phase 4 · 轨迹 详细规格（4.1 / 4.3 / 4.4 / 4.5）

覆盖 Phase 4 的四项：接口轨迹回放（4.1，2 天）、实时速度环形表 + G 值（4.3，3 天）、本地记录列表与详情与回放（4.4，4 天）、GPX 导出（4.5，1 天）。

**4.2（GPS + IMU 采集与滤波，10 天，高风险）不在本文范围**，写在 `docs/phase4-sensors-spec.md`。本文在需要「轨迹点的字段」「G 值来源」时引用它，不重复写滤波系数与阈值。

---

## 本阶段依赖什么、能并行做什么

### 硬依赖（必须先有）

| 依赖 | 出处 | 4.1 | 4.3 | 4.4 | 4.5 |
| --- | --- | --- | --- | --- | --- |
| 高德地图 `MapView` 封装 + 生命周期转发 + 隐私合规初始化 | Phase 2 的 2.1 | ✓ | ✓ | ✓ | |
| WGS-84 → GCJ-02 转换（`NinebotCoordinateTransform` 的 Kotlin 版） | Phase 0 的 0.2 / Phase 2 的 2.1 | ✓ | ✓ | ✓ | ✓ |
| 宽松 JSON 取值层（`JsonValue` 密封类 + `firstDouble` 这类多键名取值） | Phase 0 的 0.1 / 0.2 | ✓ | | | |
| Room 两张表 `rides` / `ride_points` | Phase 0 的 0.3 | | | ✓ | ✓ |
| 行程列表与行程详情页（接口行程） | Phase 3 的 3.1 / 3.2 | ✓ | | ✓ | |
| 采集器（轨迹点字段、`currentSpeedKmh` / `currentAccelerationG` / `gpsQuality` 的产出） | **4.2** | | ✓ | ✓ | ✓ |
| 前台服务 + 定位权限 + 国产 ROM 电池优化引导 | Phase 0 的 0.6 | | ✓ | | |

### 能并行做的

- **4.1 与 4.3 / 4.4 / 4.5 完全独立**。4.1 只碰接口 JSON 与行程详情页，不碰采集器、不碰 Room。可以在 4.2 还在真机调参时同步做完。
- **4.1 的 JSON 兼容层可以在 Phase 0 就写**（它只依赖 0.1 / 0.2 的取值层），并且可以纯单测驱动，完全不需要地图。建议提前，因为它是 Phase 4 里唯一「工期取决于服务端实测结果」的一项。
- **4.5 依赖 4.4 的 Room 读取，但不依赖地图**。4.4 的详情页骨架一出来就能并行。
- **速度分段着色（`SpeedTrackSegment`）是 4.1 与 4.4 共用的**，写在 `core/domain/` 一份，两处调用。不要各写一份，否则区间边界会漂。
- **4.3 与 4.4 共享 Room 的写入路径**（4.3 结束记录 → 写 `rides` + `ride_points` → 4.4 列表读出来），必须同一个人或同一次评审对齐，别分给两个人。

### 建议顺序

```
4.1（可提前，独立）
4.2（另一份规格，最长）
  └→ 4.3（依赖 4.2 的产出流）
        └→ 4.4（依赖 4.3 写出的记录 + 2.1 的地图）
              └→ 4.5（依赖 4.4 的详情页）
```

---

## 前置一 · 两种轨迹的区别（读 4.1 / 4.4 之前必须先看）

App 里有两套完全不同的轨迹数据，共用一部分渲染代码，但来源、字段、精度、能否离线全都不同。

| | **接口轨迹** | **本地记录** |
| --- | --- | --- |
| 数据源 | 九号云（车机自己上报），`GET /vehicles/{sn}/travel/{travelID}`（`NinebotServerClient.swift:165-178`） | 手机 GPS + 加速度计（`NinebotRideRecorder.swift`） |
| 手机要开着吗 | **不要**。骑行时手机可以关机，事后拉取即可 | **要**。App 必须在跑；锁屏与后台可继续（`allowsBackgroundLocationUpdates`，`NinebotRideRecorder.swift:195-202`） |
| 模型 | `NinebotInterfaceTrackPoint`（`NinebotModels.swift:304-314`） | `NinebotRideTrackPoint`（`NinebotModels.swift:831-857`） |
| 字段 | `id` / `latitude` / `longitude` / `speedKmh: Double?` / `auxiliaryValue: Double?`（航向、方位等，见 4.1 的键名表） | `id` / `date: Date` / `latitude` / `longitude` / `speedKmh: Double`（非可选） / `accelerationG: Double` / `horizontalAccuracy: Double?` |
| 有时间戳吗 | **没有**。点只有顺序，没有时刻 → **接口轨迹无法做时间轴回放** | 有，每点一个 `date` |
| 有 G 值吗 | 没有 | **有**，`accelerationG`（来源见 4.2） |
| 采样密度 | 由九号决定，通常稀疏 | GPS 定位回调驱动，`distanceFilter = 1` m、相邻点最小间隔 `0.45` s（`NinebotRideRecorder.swift:70`、`:53`）→ 实际每秒 1~2 点 |
| 落地位置 | 不落地，`NinebotViewModel.rideDetails` 内存字典（`NinebotViewModel.swift:433-435`） | UserDefaults 摘要 + 每条一个 JSON 文件（见 4.4） |
| 能导出 GPX 吗 | 不能（无导出入口，且坐标已被转成 GCJ-02，见前置二） | 能（4.5） |

### 界面上怎么区分（iOS 现状）

**接口行程详情页（行程 Tab → 某条行程）**，`NinebotRideDetailView`（`NinebotDashboardView.swift:4084-4160`）：

```
if 有关联的本地记录        → RideTrackMapPanel（标题「本地轨迹」）
else if 接口轨迹点非空     → InterfaceRideTrackMapPanel（标题「接口轨迹」）
else                       → 不显示任何地图
```

这是 `if / else if`（`:4101-4106`），**两者互斥，永不同屏**。而且 `interfaceTrackPoints` 有一道额外闸门（`:4151-4154`）：

```swift
private var interfaceTrackPoints: [NinebotInterfaceTrackPoint] {
    guard localRecord == nil else { return [] }      // ← 有本地记录时连解析都不做
    return remoteDetail?.interfaceTrackPoints ?? []
}
```

关联关系由 `associatedRecord(for:)`（`NinebotDashboardView.swift:3997-4001`）建立：

```
本地记录.associatedRideID == 接口行程.id
  && (vehicleSN == nil || 本地记录.vehicleSN == nil || 本地记录.vehicleSN == vehicleSN)
```

关联是**用户在结束记录时手动选的**（4.4 的 `RideAssociationSheet`），没有任何自动按时间匹配的逻辑。

**记录 Tab（`NinebotRecordingView`，`ContentView.swift:47-50` 注册，标签「记录」）** 只显示本地记录，从不显示接口轨迹。

三处轨迹面板的差异（iOS 现状，**互不一致，不是笔误**）：

| 面板 | 位置 | 高度 | 折线 | 额外元素 |
| --- | --- | --- | --- | --- |
| `RideTrackMapPanel`（本地轨迹，行程详情内） | `NinebotDashboardView.swift:4248-4335` | 240 | **速度分段着色**，5pt round cap/join | 最快徽章、速度图例、4 个指标（开始/结束/最快/最大 G） |
| `InterfaceRideTrackMapPanel`（接口轨迹） | `NinebotDashboardView.swift:4337-4415` | 240 | **速度分段着色**，5pt | 最快徽章、速度图例 |
| `RecordedRideTrackMap`（记录 Tab 详情） | `NinebotRecordingView.swift:687-819` | 300 | **单色 `teslaGreen`，4pt** | 开始/结束 Marker、回放滑块 |

也就是说：**同一条本地记录，从行程 Tab 进去是速度分段彩色折线、从记录 Tab 进去是纯绿折线，而且只有记录 Tab 那条有回放滑块。** 这是 iOS 的既有不一致，Android 是否统一见 `## 待定` R7。

### Android 侧的区分要求

1. 两种轨迹在 UI 上必须能一眼分清，不能只靠标题文字。建议：接口轨迹折线加 `setDottedLine(true)` 或降低透明度到 0.75，并在面板右上角挂一个来源 chip（「车机上报」/「本机记录」）。**接口轨迹没有时间戳这件事必须在 UI 上体现**——不要给它画回放滑块，否则用户会以为拖不动是 bug。
2. 领域层用一个统一的渲染入口，两种来源都先归一成
   ```kotlin
   data class TrackPoint(
       val lat: Double,          // WGS-84 原值，不转换
       val lon: Double,
       val speedKmh: Double?,    // 接口轨迹可能为 null
       val timestamp: Instant?,  // 接口轨迹恒为 null
       val accelG: Double?,      // 接口轨迹恒为 null
       val horizontalAccuracyM: Double?,
   )
   ```
   `timestamp == null` 就是「不能回放」的判据，`accelG == null` 就是「不显示 G 相关指标」的判据。不要用两个平行的 UI 树。
3. 能不能叠加显示两条轨迹 → **产品决策，见 `## 待定` R6。本规格照 iOS 写成互斥。**

---

## 前置二 · 坐标系（4.1 / 4.3 / 4.4 / 4.5 都要看）

坐标转换本身已在 **Phase 2 的 2.1**（`docs/phase2-vehicle-control-spec.md` 的「坐标系」一节）讲过：`Shared/NinebotCoordinateTransform.swift` 做 WGS-84 → GCJ-02，只在 `longitude ∈ (72.004, 137.8347)` 且 `latitude ∈ (0.8293, 55.8271)` 内生效（`NinebotCoordinateTransform.swift:35-37`），高德底图是 GCJ-02 所以这段代码原样保留。**算法与边界条件不在此重复。**

本节只补 Phase 4 特有的三件事。

### 一 · 每条轨迹现在是什么坐标系

| 数据 | iOS 转换发生的位置 | 转换后 | 原值还留着吗 |
| --- | --- | --- | --- |
| 接口轨迹点 | `NinebotModels.swift:688-697` 的 `coordinate(latitude:longitude:)`，**在 JSON 解析里** | GCJ-02 | **不留**。`NinebotInterfaceTrackPoint.latitude/longitude` 已经是 GCJ-02，原始 WGS-84 只在 `raw` JSON 里 |
| 本地记录点（存储） | 不转换 | 存的是 `CLLocation` 原值 | 留 |
| 本地记录点（画地图） | `NinebotRecordedRide.trackCoordinates`（`NinebotModels.swift:939-950`）、`speedTrackPoints`（`NinebotDashboardView.swift:4492`）、`recordingMapCoordinate`（`NinebotRecordingView.swift:1079-1081`） | GCJ-02 | 留 |
| 本地记录点（GPX 导出） | `NinebotRecordingView.swift:897` 也走 `recordingMapCoordinate` | **GCJ-02** | 留 |

**接口轨迹是不是真的 WGS-84，iOS 侧从来没有验证过。** 解析代码无条件调用转换（`:696`），这等于假设九号返回 WGS-84。如果九号返回的本来就是 GCJ-02（国内车联网服务端很常见），那 iOS 现在的接口轨迹**已经是双重偏移**的。这条**必须实测**，见下面第三点。

本地记录点在 Android 上情况不同：已定用**高德定位 SDK**（`pending-decisions.md` D8），它**直接返回 GCJ-02**。所以：

| 数据 | Android 处理 |
| --- | --- |
| 接口轨迹坐标 | 实测决定：若九号返回 WGS-84 → 转一次；若已是 GCJ-02 → **不转** |
| 高德定位 SDK 采集的本地记录点 | **不转**（已经是 GCJ-02） |
| 回退到 `FusedLocationProviderClient` / `LocationManager` 采集的点 | 转一次（它们是 WGS-84） |

**因此本地记录点必须随点存一个坐标系标记**，否则同一条记录里混着两种坐标系而无从分辨（用户中途换了定位源、或高德定位在某台设备上不可用而回退）：

```kotlin
enum class CoordinateSystem { WGS84, GCJ02 }
// ride_points 表加一列 coord_sys TEXT NOT NULL DEFAULT 'WGS84'
```

### 二 · 转换在哪一层做

**iOS 的做法（接口轨迹在解析层就转）是错的，Android 不要照抄。**

理由有三条，都能落到具体后果上：
1. GPX 必须是 WGS-84（见 4.5）。转换发生在解析层意味着导出时拿不到原值，只能导出偏移坐标。iOS 现在就是这个 bug。
2. 一旦确认某类数据本来就是 GCJ-02，解析层要改就得改模型，波及范围大。
3. 单测里写期望值时，转换后的数值不可读（这也是 `RideDetailParsingTests.swift:11-13` 特意把全部夹具放在东京、绕开中国大陆包围盒的原因）。

Android 规定：

```
存储层 / 解析层  →  原样保存 (lat, lon, coordSys)，不转换
领域层           →  归一成 TrackPoint（仍是原值）
地图渲染层       →  toGcj02() 后再交给高德（若 coordSys 已是 GCJ02 则直通）
GPX 导出层       →  toWgs84() 后再写文件（若 coordSys 已是 WGS84 则直通）
```

即：**转换只出现在两个出口（地图、GPX），且各自幂等**。写成两个纯函数并单测：

```kotlin
fun TrackPoint.forAmap(): LatLng =
    when (coordSys) { GCJ02 -> LatLng(lat, lon); WGS84 -> gcj02(lat, lon) }

fun TrackPoint.forGpx(): Pair<Double, Double> =
    when (coordSys) { WGS84 -> lat to lon; GCJ02 -> gcj02ToWgs84(lat, lon) }
```

`gcj02ToWgs84` 是新代码，iOS 侧没有。用迭代反解（正向转换 + 二分/牛顿迭代 3~4 轮即可收敛到 1e-7 度以内），别去找封闭解，没有。

### 三 · 双重偏移长什么样、怎么一眼看出来

对已经是 GCJ-02 的坐标再转一次，会产生**第二次同方向的偏移**。量级：

| 地点 | 一次偏移 | 双重偏移（约两倍，方向基本相同） |
| --- | --- | --- |
| 北京（39.91, 116.40） | 约 500~600 m | 约 1.0~1.2 km |
| 上海（31.23, 121.47） | 约 350~450 m | 约 0.7~0.9 km |

特征（这三条合起来就能确诊，不需要精确测距）：

1. **整条轨迹平行位移，形状完全不变**。不是漂移、不是抖动、不是缩放——是整体刚性平移。如果轨迹形状对但整条压在马路旁边的建筑里、或压在河里，就是偏移问题。
2. **偏移方向恒定**：中国大陆范围内 GCJ-02 相对 WGS-84 大体是「往东北偏」（经度增大、纬度增大），双重偏移就是同方向再来一次。轨迹整体偏向左下（西南）说明反了向。
3. **出中国大陆立刻消失**。转换函数在包围盒外直接返回原值（`NinebotCoordinateTransform.swift:11-13`），所以拿一条东京/香港边界外的夹具轨迹，双重偏移和正常渲染完全一样。**这是最好的判别手段**：同一份代码，境内偏、境外不偏 → 一定是坐标转换问题；境内境外都偏 → 是别的 bug。

**实测方法（必做，一次覆盖三项）**

在同一张高德地图上同时画三样东西，站在车旁边看：

| # | 内容 | 期望 |
| --- | --- | --- |
| 1 | 高德定位 SDK 返回的「我的位置」（不转换） | 落在你脚下 |
| 2 | 服务端返回的车辆坐标（Phase 2 的 2.1 已定转一次） | 落在车上 |
| 3 | 同一条行程的**接口轨迹首点**（分别试「转」与「不转」两版） | 落在你出发的位置 |

第 3 项两版中只有一版对得上，那一版就是结论。若两版都差 500 m 上下但方向相反，说明九号给的是 GCJ-02（不转的那版才对）。**这条实测结论直接决定 4.1 的解析层要不要调用转换，务必在写 4.1 之前做完。**

补一条自动化闸门：在 CI 里放一条「北京五环内 20 点」的夹具轨迹，断言渲染坐标与预期 GCJ-02 值的差 < 1e-6 度。双重偏移会让这条测试差出 5e-3 度量级，一眼就红。

---

## 4.1 接口轨迹回放（2 天，风险中）

### 一 · iOS 现状

数据入口是 `GET /vehicles/{sn}/travel/{travelID}`（`NinebotServerClient.swift:165-178`），返回值整块塞进 `NinebotRideDetail.raw: JSONValue`（`NinebotModels.swift:288-302`），不做任何 schema 校验。

解析全部在 `extension NinebotRideDetail`，`NinebotModels.swift:316-765`，**450 行**，全是 `private static`，只有两个公开入口：

| 入口 | 行号 | 产出 |
| --- | --- | --- |
| `interfaceTrackPoints` | `:317-330` | `[NinebotInterfaceTrackPoint]`（带速度与辅助值） |
| `interfaceTrackCoordinates` | `:332-338` | `[CLLocationCoordinate2D]`（只有坐标） |

内部结构（两条平行通路，**不是一条通路的两种视图**）：

```
interfaceTrackPoints
├─ bestTrackPoints(from:)                  :340-347   带速度的通路
│  ├─ trackCandidateValues(from:)          :358-401   全树 DFS 找候选
│  ├─ trackPoints(from:)                   :403-429
│  │  ├─ trackPoints(fromArray:)           :431-454
│  │  ├─ trackPoint(fromObject:index:)     :456-464
│  │  ├─ trackPoint(fromPair:index:)       :466-469
│  │  ├─ trackPoints(fromString:startIndex:) :471-491
│  │  ├─ trackPointsFromJSONString(_:)     :493-500
│  │  └─ trackPoint(fromNumbers:index:)    :502-513
│  └─ interfaceTrackPoint(...)             :515-528   生成 id
└─ 回退：interfaceTrackCoordinates.enumerated().map { 无速度的点 }   :322-329

interfaceTrackCoordinates
├─ bestTrackPoints(from:) 非空 → 直接取坐标   :333-336
└─ bestTrackCoordinates(from:)             :349-356   只有坐标的通路
   └─ trackCoordinates(from:)              :530-556
      ├─ coordinates(fromArray:)           :558-578
      ├─ coordinate(fromObject:)           :580-598
      ├─ coordinate(fromPair:)             :600-612
      ├─ coordinates(fromString:)          :614-638
      ├─ coordinatesFromJSONString(_:)     :640-647
      └─ coordinates(fromAny:)             :649-680   走 JSONSerialization，递归所有对象值
```

界面侧 `InterfaceRideTrackMapPanel`（`NinebotDashboardView.swift:4337-4415`）。

**测试**：`Tests/NineBotCoreTests/RideDetailParsingTests.swift`（728 行，两个类共 **52 个用例**：`RideDetailParsingTests` 33 个覆盖轨迹解析，`RideRecordIdentityTests` 19 个覆盖 `stableIdentityKey`，后者属于 Phase 3 的 3.1）。**读这 33 个用例是看清规则最快的路子**，本节的规则表就是从它们和源码逐条对出来的。所有夹具坐标都在东京（`longitude > 137.8347`），故意落在中国大陆包围盒外，让期望值不受坐标转换影响（`RideDetailParsingTests.swift:11-13`）。

### 二 · 要移植的逻辑

#### 2.1 认哪些键名（原文照抄，顺序有意义）

**顶层轨迹容器键（20 个，`Set<String>`，`NinebotModels.swift:359-380`）**——用于全树查找，无序（是 `Set`）：

```
trial  trail  trace  track  tracks  track_list  trackList
trajectory  trajectory_list  trajectoryList
points  point_list  pointList
gps  gps_list  gpsList
location_list  locationList
coordinate_list  coordinateList
```

**嵌套下钻键（11 个，`Array`，有序，`:413` 与 `:540` 两处内容完全相同）**——对象里找不到坐标时，按此顺序试：

```
trial  trail  trace  track  tracks  points  list  data  gps  locations  coordinates
```

**纬度键（7 个，有序，`:581` / `:683`）**：`lat` `latitude` `y` `gcj_lat` `gcjLat` `wgs_lat` `wgsLat`

**经度键（12 个，有序，`:582` / `:684`）**：`lon` `lng` `longitude` `x` `gcj_lng` `gcjLng` `gcj_lon` `gcjLon` `wgs_lng` `wgsLng` `wgs_lon` `wgsLon`

**坐标容器键（6 个，有序，`:588`）**：`location` `loc` `coordinate` `coordinates` `point` `gps`

**速度键（6 个，有序，`:460`）**：`speed` `spd` `speed_kmh` `speedKmh` `velocity` `v`

**辅助值键（7 个，有序，`:461`）**：`direction` `bearing` `heading` `course` `angle` `aux` `auxiliary`

三点注意：
- `gcj_lat` / `wgs_lat` 这些键名**被认出来之后照样过一遍坐标转换**（`:696`）。名字里写着 `gcj_` 的坐标也会被再转一次 → 必然双重偏移。这是现成的坑，见前置二。
- 取值一律走 `firstDouble`（`:699-706`），底层 `JSONValue.doubleValue`（`:2010-2021`）**接受数字、数字字符串、以及布尔（true→1、false→0）**。所以 `"lat": "35.5"` 能解（测试 `testNumericStringsAreAcceptedAsCoordinates`），`[true, true]` 会被当成坐标 (1, 1)。
- 辅助值**不做任何范围校验**（速度有，见下）。`auxiliaryValue` 现在界面上完全没用到，只被解析出来存着。

#### 2.2 遇到什么形状怎么退化 —— 可实现的规则表

**入口算法**

```
interfaceTrackPoints:
  P = bestTrackPoints(raw)
  if P 非空 → return P
  C = interfaceTrackCoordinates                      // 坐标通路
  return C.mapIndexed { i, c -> Point(id="{i}-...", c, speed=null, aux=null) }

interfaceTrackCoordinates:
  P = bestTrackPoints(raw)
  if P 非空 → return P.map(coordinate)
  return bestTrackCoordinates(raw)

bestTrackPoints(v) / bestTrackCoordinates(v):
  candidates = trackCandidateValues(v)
  parsed = candidates.map { parse(it) }.filter { it.count > 1 }      // ← 硬门槛：> 1
  return parsed.maxBy { count } ?: []                                 // 并列时取第一个
```

**候选收集 `trackCandidateValues`（`:358-401`）**：从根开始 DFS。对象：每个键若命中 20 键集合，把它的**值**加入候选；无论是否命中，都继续递归进这个值。数组：递归每个元素。所以

- 轨迹键可以在**任意嵌套深度**被找到（测试 `testTrackKeyIsFoundAtAnyNestingDepth`：`data.detail.extra[0].gps_list`）。
- 同一份返回值里可以有多个候选，最长的赢（测试 `testTheLongestCandidateWins`：`track` 2 点 vs `points` 4 点 → 取 4 点）。
- **不带这 20 个键名的坐标数组一律看不见**（测试 `testPayloadWithoutTrackKeysHasNoCoordinates`：`items: [{lat, lon}]` 被忽略）。

**单个候选的解析 `trackPoints(from:)`（`:403-429`）**

| 候选形状 | 处理 |
| --- | --- |
| 数组 | → `trackPoints(fromArray:)`，见下 |
| 对象，且自身能解出坐标 | 返回 **1 个点**（随后被 `> 1` 门槛滤掉） |
| 对象，自身解不出坐标 | 按 11 个嵌套键的**顺序**逐个下钻，返回**第一个结果 > 1 个点**的（测试 `testTrackWrappedInAnObjectWithAListKey`：`track.list`） |
| 字符串 | → `trackPoints(fromString:)`，见下 |
| 数字 / 布尔 / null | `[]` |

**数组的解析 `trackPoints(fromArray:)`（`:431-454`）**——顺序很关键：

```
第 0 步：先把「整个数组」当成一个 [lat, lon, speed?, aux?] 元组试一次
         成功 → 直接 return 这 1 个点（随后被 > 1 门槛滤掉）
第 1 步：否则逐元素：
         元素是对象 → trackPoint(fromObject:)，成功则收下
         元素是数组 → trackPoint(fromPair:)，成功则收下
         元素是字符串 → trackPoints(fromString:, startIndex: 已收点数) 全部收下
第 2 步：deduplicated(结果)
```

第 0 步是三个反直觉行为的根源：
- `"track": [35.5, 139.5]` → **无轨迹**（1 个点被门槛滤掉，测试 `testSinglePointTracksAreIgnored` 的 `flatPair`）。
- `"track": ["35.5", "139.5"]` → 同样被当成 1 个点（`doubleValue` 认数字字符串）→ 无轨迹。
- `"track": ["35.5,139.5", "35.6,139.6"]` → **无轨迹**。第 0 步的 `compactMap(\.doubleValue)` 对 `"35.5,139.5"` 返回 nil，落到第 1 步；每个字符串各自只解出 1 个坐标，被 `trackPoints(fromString:)` 内部的 `> 1` 门槛滤成空 → 整个数组丢失。但同样的坐标写在**一个**字符串里就能解（测试 `testArrayOfOneCoordinatePerStringIsNotRecognised`）。这是**已记录的解析缺口**，不是 bug 修复对象——照抄，Android 侧用同一条测试钉住。

**数字元组的解析 `trackPoint(fromNumbers:)`（`:502-513`）+ `coordinate(fromPair:)`（`:600-612`）**

```
numbers = 元素里所有能转成 Double 的值（按原顺序）
numbers.count < 2                        → nil
经纬顺序判定：
  |numbers[0]| > 90 且 |numbers[1]| <= 90 → 视为 [lon, lat]，交换
  否则                                    → 视为 [lat, lon]
范围校验：lat ∈ [-90, 90] 且 lon ∈ [-180, 180]，否则 nil（整点丢弃）
speed = numbers[2]（count >= 3），过 normalizedSpeed
aux   = numbers[3]（count >= 4），不校验
坐标转换：mapKitCoordinate(lat, lon)
```

**速度归一化 `normalizedSpeed`（`:733-736`）**：

```
value == nil            → nil
value < 0 或 value > 160 → nil        ← 点保留，只是速度变 nil
否则                     → value      单位按 km/h 原样采纳，不做 m/s 判定
```

测试 `testImplausibleSpeedsAreDroppedButThePointIsKept`：`999` 与 `-3` 都变 nil，两个点都还在。**注意上界是 160，与本地记录侧的 132（`NinebotRideRecorder.swift:48` 的 `maximumReasonableSpeedKmh`）和环形表量程 132（`NinebotRecordingView.swift:196`）都不一样。三个数字互不相同，别统一。**

**字符串的解析 `trackPoints(fromString:)`（`:471-491`）**

```
1. trim 首尾空白与换行；空 → []
2. 首字符是 '{' 或 '[' → 尝试 JSON 解码 → trackPoints(from:) → 结果 > 1 就返回
3. 否则按 分隔符集合 {';', '|', '\n'} 切成段
4. 每段按 {',', ' ', '\t'} 切成数字，逐段 trackPoint(fromNumbers:)（index = startIndex + 段序号）
5. 结果 > 1 → deduplicated；否则 → []
```

覆盖的四种真实形状（各有测试）：`"35.5,139.5;35.6,139.6;35.7,139.7"`、`"35.5 139.5|35.6 139.6"`、`"35.5,139.5\n35.6,139.6"`、`"[[35.5,139.5],[35.6,139.6]]"`、`"[{\"lat\":35.5,\"lon\":139.5},...]"`。

**坐标通路与点通路的三处不同**（这是 `interfaceTrackPoints` 需要回退到坐标通路的原因）：

| | 点通路 | 坐标通路 |
| --- | --- | --- |
| 数组：先试「整个数组当一个元组」 | **会**（`:432`） | 不会（`:558-578` 无此步） |
| JSON 字符串的解码器 | `JSONDecoder` → `JSONValue` → 只下钻 11 个键（`:493-500`） | `JSONSerialization` → `coordinates(fromAny:)`，**递归所有对象值**（`:649-680`） |
| 能不能拿到速度 | 能 | 不能，全 nil |

后果：`"gps": "{\"a\":{\"lat\":35.5,...},\"b\":{...}}"` 这种「坐标挂在任意键名下」的 JSON 字符串，点通路解不出（`a`/`b` 不在 11 键里），只有坐标通路能解，于是 `interfaceTrackPoints` 回退过去，得到**两个没有速度的点**（测试 `testPointsFallBackToCoordinateOnlyParsing`）。

**去重 `deduplicated`（`:738-750` 点版 / `:752-764` 坐标版）**

```
key(p) = "{round(lat * 1e6)}|{round(lon * 1e6)}"
只折叠「与上一个保留点 key 相同」的连续重复
```

- 连续重复折叠（测试 `testConsecutiveDuplicatesAreCollapsed`）。
- **非连续重复保留**——绕回同一地点是骑行的真实部分（测试 `testNonConsecutiveDuplicatesAreKept`：3 个点里第 1、3 相同，结果仍是 3 点）。
- 比较精度 6 位小数（约 0.11 m）。相差 1e-7 会被折叠（测试 `testDeduplicationComparesToSixDecimalPlaces`）。

**点 id 格式（`:521-527`）**

```
"{index}-{round(lat*1e6)}-{round(lon*1e6)}"        lat/lon 是转换之后的值
```

`index` 是**去重之前**的下标，所以 id 序列可能跳号：3 点里前两点重复 → id 为 `["0-35500000-139500000", "2-35600000-139600000"]`（测试 `testIdentifiersKeepTheIndexFromBeforeDeduplication`）。界面侧用 id 做 `ForEach` 的 identity，不要重排。

#### 2.3 什么情况判定为「无轨迹」

**判据只有一条：点通路与坐标通路的全部候选，没有任何一个产出 > 1 个点。** 展开成清单：

| 情形 | 结果 | 测试 |
| --- | --- | --- |
| `raw` 是 null / 数字 / 字符串 / 空数组 | 无轨迹 | `testNonContainerPayloadsHaveNoCoordinates` |
| 有坐标但键名不在 20 键集合里 | 无轨迹 | `testPayloadWithoutTrackKeysHasNoCoordinates` |
| 只有 1 个点（`[[lat,lon]]` / `[{lat,lon}]` / `[lat,lon]`） | 无轨迹 | `testSinglePointTracksAreIgnored` |
| 单坐标字符串 `"35.5,139.5"` | 无轨迹 | `testAStringHoldingASingleCoordinateYieldsNothing` |
| 数组里每个元素各含一个坐标字符串 | 无轨迹（已记录的缺口） | `testArrayOfOneCoordinatePerStringIsNotRecognised` |
| 全部点都超出经纬范围 | 无轨迹 | 由 `testOutOfRangeCoordinatesAreSkipped` 的逐点丢弃推得 |
| 恰好 2 个点、其中 1 个越界 | **无轨迹**（剩 1 点被门槛滤掉） | 组合推得，Android 侧要补这条 |

界面表现：`interfaceTrackPoints.isEmpty` → 行程详情页**不显示任何地图面板**，也没有任何「本次行程无轨迹」的提示（`NinebotDashboardView.swift:4101-4106`）。Android 侧建议补一个明确空态（见 4.1 的验收），避免用户以为地图加载失败。

#### 2.4 渲染

见 4.4 的「速度分段着色」一节——`InterfaceRideTrackMapPanel` 与 `RideTrackMapPanel` 共用 `makeSpeedTrackSegments` / `bestSpeedTrackPoint` / `speedTrackColor`，规格写在那里，不重复。

接口轨迹特有的一点：`speedKmh` 大量为 nil 时，`speedTrackColor(nil)` 返回 `teslaGreen`（`NinebotDashboardView.swift:4533`），与 8~25 km/h 档**同色**，用户无法区分「巡航」和「没有速度数据」。见 `## 待定` R8。

相机初始定位 `region(for:)`（`:4393-4414`）：

```
坐标为空 → center = (31.2304, 121.4737)  上海人民广场，span = 0.03 × 0.03
否则     → center = 包围盒中心
           span   = max(包围盒跨度 × 1.5, 0.006)   经纬各自算
```

### 三 · Android 实现要点

#### 3.1 前置风险：社区服务端是否原样透传（必须先做，决定本项工期）

**这 450 行兼容代码存在的唯一理由是「九号返回的 JSON 形状不固定」。而 Android 端连的是社区适配器 [`wuchiawuchi/nineplus-ha-server`](https://github.com/wuchiawuchi/nineplus-ha-server)（`android-implementation-plan.md` 的已定方案），不是九号官方服务端。**

如果这个适配器对 travel detail 做了字段裁剪或形状归一，那么：
- 20 个键名里实际只会出现 1 个；
- 20 键集合、11 个下钻键、两条平行通路、JSON-in-string 解码这些分支**全部用不上**；
- 本项工期从 2 天降到 0.5 天，兼容层缩成十几行。

反过来，如果适配器**根本不透出 travel detail 端点**，那 4.1 整项做不了，只能靠 4.4 的本地记录，本阶段规模直接砍掉一项。

**实测清单（在写任何 4.1 代码之前完成）**

| # | 要确认的 | 怎么做 | 影响 |
| --- | --- | --- | --- |
| 1 | 适配器有没有 `GET /vehicles/{sn}/travel/{travelID}` 这条路由 | 直接 curl 一次 | 没有 → 4.1 整项取消 |
| 2 | 返回体是九号原文还是重新组装的 | 把原始 JSON 存下来，和字段名对照 20 键集合 | 重组过 → 兼容层可大幅精简 |
| 3 | 轨迹在哪个键下、什么形状（对象数组 / 数字元组 / 字符串） | 看原始 JSON | 直接决定要实现哪几个分支 |
| 4 | 有没有 `speed` / 航向字段 | 看原始 JSON | 没速度 → 分段着色对接口轨迹无意义，只画单色 |
| 5 | 坐标是 WGS-84 还是 GCJ-02 | 前置二第三点的实测 | 决定解析层是否转换 |
| 6 | 一次骑行返回多少个点 | 数一下 | 决定要不要抽稀（见 3.3） |

**把 1~6 的原始 JSON 直接存成测试夹具**（`androidTest/assets/travel-detail-*.json`），这是本项最有价值的产出——它决定后面所有分支要不要写。

**在实测结论出来之前，按「全量移植 450 行」排 2 天工期**，因为：适配器换掉、或用户改用官方直连时，这些分支会立刻用上；而这 450 行是纯函数、纯单测覆盖，移植成本可预测（约 1 天写 + 0.5 天对测试），风险远低于「先精简、以后重写」。

#### 3.2 解析层结构

放 `core/domain/track/InterfaceTrackParser.kt`，**纯 Kotlin，不依赖 Android、不依赖高德**，输入 `JsonElement`，输出 `List<TrackPoint>`（原始坐标，不转换，见前置二）。

```kotlin
object InterfaceTrackParser {
    private val TRACK_KEYS = setOf(/* 20 个，照抄 */)
    private val NESTED_KEYS = listOf(/* 11 个，顺序照抄 */)
    private val LAT_KEYS = listOf("lat", "latitude", "y", "gcj_lat", "gcjLat", "wgs_lat", "wgsLat")
    private val LON_KEYS = listOf(/* 12 个 */)
    private val CONTAINER_KEYS = listOf("location", "loc", "coordinate", "coordinates", "point", "gps")
    private val SPEED_KEYS = listOf("speed", "spd", "speed_kmh", "speedKmh", "velocity", "v")
    private val AUX_KEYS = listOf("direction", "bearing", "heading", "course", "angle", "aux", "auxiliary")

    private const val MIN_POINTS = 2            // iOS 的 `count > 1`
    private const val MAX_SPEED_KMH = 160.0     // normalizedSpeed 上界，与本地记录的 132 不同
    private const val DEDUP_SCALE = 1_000_000.0 // 6 位小数

    fun parse(raw: JsonElement): List<TrackPoint> { /* bestTrackPoints，失败回退坐标通路 */ }
}
```

四条与 iOS 不同、必须显式处理的：

1. **候选并列时的胜者**。iOS 用 `max { $0.count < $1.count }`，并列保留**先遇到的**；但 Swift `Dictionary` 的迭代顺序**未定义**，所以 iOS 在「两个不同键各给出同样多的点」时结果不确定（`RideDetailParsingTests.swift:421` 那句 "Dictionary iteration order is unspecified" 就是被这个逼出来的）。kotlinx.serialization 的 `JsonObject` 是 `LinkedHashMap`，**保留 JSON 文档顺序**，所以 Android 天然确定。**这是有意的行为改进**：明确规定「并列时取 JSON 文档中先出现的候选」，并补一条测试钉住。
2. **`Double` 解析要跟 `JSONValue.doubleValue` 完全一致**（`NinebotModels.swift:2010-2021`）：数字直接取；字符串走 Swift `Double(String)` 语义；**布尔 true→1.0、false→0.0**。Kotlin 侧 `JsonPrimitive.doubleOrNull` 对布尔返回 null，会和 iOS 分叉。要自己写：
   ```kotlin
   val JsonPrimitive.numberOrNull: Double? get() = when {
       !isString && content == "true"  -> 1.0
       !isString && content == "false" -> 0.0
       else -> content.toDoubleOrNull()
   }
   ```
   Swift `Double("1e3")` = 1000、`Double(" 35.5")` = nil（不 trim）、`Double("0x1p3")` = 8.0（十六进制浮点！）。Kotlin `toDoubleOrNull` 对 `"0x1p3"` 返回 null，对 `" 35.5"` 也返回 null（同 Swift）。十六进制这条现实中不会出现，记录一下不必对齐。
3. **递归深度**。`trackCandidateValues` 是无限深度 DFS，恶意/畸形返回值能栈溢出。加一个 `maxDepth = 32` 的守卫并计入测试（iOS 侧没有，属新增防护）。
4. **同一份 JSON 会被遍历多次**（点通路一遍、坐标通路一遍，且候选之间有嵌套重叠）。对 5000 点的返回值这是几十毫秒级别，**不要在主线程做**。放 `Dispatchers.Default`，结果缓存在 ViewModel 里（对应 iOS 的 `rideDetails` 字典，`NinebotViewModel.swift:433-435`）。

#### 3.3 渲染

- 折线用高德 `PolylineOptions`，分段着色见 4.4 的 3.2。
- 相机：`LatLngBounds.Builder().include(...)` + `CameraUpdateFactory.newLatLngBounds(bounds, padding)`。**不要照抄 iOS 的 `span × 1.5`**——`newLatLngBounds` 自己带 padding 语义，`× 1.5` 会让轨迹缩成中间一小团。padding 取 48dp 折算的 px。
- 单点或空轨迹：`newLatLngZoom(LatLng(31.2304, 121.4737), 14f)` 对齐 iOS 的上海兜底（span 0.03 ≈ zoom 13~14，实测取整）。
- **点数上限**。iOS 对接口轨迹**不抽稀**（`sampledTrackCoordinates` 只有本地记录用，且实际只被测试引用，见 4.4）。高德 `Polyline` 单条超过约 1 万点会明显掉帧。加一道保护：> 2000 点时按 4.4 的抽稀算法降到 2000，并在诊断中心记一条日志。

### 四 · 陷阱

1. **`gcj_lat` / `gcj_lng` 键名照样被转一次**（`NinebotModels.swift:696`）。名字明确写着 GCJ-02 的坐标被当成 WGS-84 再转 → 必然双重偏移。Android 侧遇到 `gcj_*` 键名应该标记 `coordSys = GCJ02` 并跳过转换。**这是修 iOS 的 bug，行为差异，记进 `## 待定` R2。**

2. **`> 1` 是硬门槛，不是「>= 1」**。一次只走了几米的骑行、或九号只上报了一个点，界面上什么都不显示。别顺手改成 `>= 1`，那会让「一个孤立坐标」被当成轨迹画出来（很多返回体的元数据里就带一个终点坐标）。

3. **速度上界三个值互不相同**：接口轨迹 160（`:734`）、本地记录 132（`NinebotRideRecorder.swift:48`）、环形表量程 132（`NinebotRecordingView.swift:196`）。写成三个常量，不要抽成一个。

4. **经纬顺序判定只在「|first| > 90 且 |second| <= 90」时才交换**（`:607-609`）。所以 `[45.0, 30.0]`（都 ≤ 90）恒被当成 [lat, lon]——如果九号某天给的是 [lon, lat] 且两个值都 ≤ 90（中国境内经度 72~137 都 > 90，所以境内安全；**境外轨迹会错**）。照抄，但在测试里明确记录这个边界。

5. **辅助值不校验**。`auxiliaryValue` 可能是航向（0~360）、可能是海拔、可能是时间戳。iOS 从来没显示它。**不要凭字段名推断它是航向就画箭头**——`aux` / `auxiliary` 这两个键名下的东西完全不知道是什么。

6. **`interfaceTrackPoints` 与 `interfaceTrackCoordinates` 都是计算属性，每次访问全量重算**。`InterfaceRideTrackMapPanel` 的 `speedPoints` / `speedSegments` / `maxSpeedPoint` 三个计算属性各自再调一遍（`:4375-4391`），一次渲染里解析 3~4 遍。Compose 侧用 `remember(rawJson) { parse(...) }`，**别写成 `@Composable get()`**。

7. **`raw` 是 `JSONValue` 不是强类型**，所以服务端换字段名不会报错，只会静默变成「无轨迹」。Android 必须在解析返回空时把「找到了哪些候选键、各自解出几个点」写进诊断中心（Phase 5 的 5.1），否则线上排查只能靠猜。

8. **布尔会变成坐标**。`"track": [[true, true], [true, false]]` 解出两个点 (1,1) 和 (1,0)，`count > 1` 通过 → 画出一条横跨几内亚湾的线。现实中不会有，但畸形返回值下会看到「轨迹在非洲」，别以为是坐标转换错了。

### 五 · 验收标准

- [ ] **先做**：实测社区服务端 travel detail 的 6 项（3.1 的表），原始 JSON 存成夹具入库，结论写进本文档
- [ ] 移植 `RideDetailParsingTests.swift` 的 **33 个轨迹解析用例**，逐个通过（`RideRecordIdentityTests` 的 19 个属 Phase 3）
- [ ] 20 个顶层键名各造一条夹具，都能解出轨迹
- [ ] 7 个纬度键 × 12 个经度键的组合至少覆盖 `lat/lon`、`latitude/longitude`、`y/x`、`gcj_lat/gcj_lng`、`wgs_lat/wgs_lng` 五组
- [ ] 4 种字符串形状（`;` / `|` / `\n` 分隔、JSON-in-string）各一条夹具
- [ ] 数字元组 2 / 3 / 4 元素各一条，速度与辅助值取值正确
- [ ] 速度 `999` / `-3` / `160` / `160.1` 四个输入：前两个和 `160.1` 变 null，`160` 保留，**四种情况下点都不丢**
- [ ] `> 1` 门槛的 5 种无轨迹情形（4.1 的 2.3 表）各一条，界面显示明确空态而不是空白
- [ ] 连续重复折叠、非连续重复保留、1e-7 折叠三条各一个用例
- [ ] 点 id 在去重后仍保留去重前下标（`["0-...","2-..."]`）
- [ ] 两个候选点数并列时，取 JSON 文档中先出现的那个（Android 新增的确定性保证）
- [ ] 递归深度 32 层守卫生效，畸形深嵌套 JSON 不崩
- [ ] 北京五环内 20 点夹具：渲染坐标与预期 GCJ-02 值差 < 1e-6 度（双重偏移检测闸门）
- [ ] 东京夹具（`longitude > 137.8347`）渲染坐标与输入完全相同（包围盒外不转换）
- [ ] 5000 点返回值解析不在主线程，界面无卡顿；> 2000 点抽稀生效
- [ ] 同一条行程连续进出详情页 5 次，只解析 1 次（`remember` 生效，用日志计数验证）

---

## 4.3 实时速度环形表 + G 值（3 天，风险低）

### 一 · iOS 现状

`NinebotRecordingView.swift`，记录 Tab 的第二块卡片。

| 组件 | 行号 | 作用 |
| --- | --- | --- |
| `NinebotRecordingView` | 8-89 | Tab 容器，`ScrollView` + 6 块，`VStack(spacing: 18)`，`padding(16)` + `padding(.bottom, 20)` |
| `RecordingGPSQuality` 的界面扩展 | 91-120 | 5 档 GPS 质量的文案/图标/颜色（枚举本身在 `NinebotRideRecorder.swift:9-15`） |
| `RecordingHeader` | 128-187 | 车名 + 状态文案 + REC/READY 胶囊 |
| **`RecordingSpeedGauge`** | **189-265** | **环形表本体** |
| `RecordingGaugePill` | 267-287 | 表盘内的两个小胶囊（GPS 质量、G 值） |
| `RecordingControlPanel` | 289-316 | 开始/结束记录大按钮 |
| `RecordingMetricsGrid` | 318-337 | 2×2 指标（当前 G / 最大 G / 距离 / 时长） |
| `RecordingMetricTile` | 339-367 | 指标格 |
| `RecordingTrackPreview` | 369-476 | 实时轨迹小地图 |
| 格式化函数 | 1036-1077 | `formatRecordingSpeed` / `Distance` / `G` / `Duration` / `Date` / `Number` |

外层布局（`:28-37`）：`RecordingSpeedGauge` 外面套 `padding(.horizontal, 12)` + `padding(.vertical, 14)` + `ninePlusCard(cornerRadius: 30)`。

### 二 · 要移植的逻辑

#### 2.1 量程与刻度

```swift
private let maxGaugeSpeed = 132.0        // NinebotRecordingView.swift:196
```

**量程 0~132 km/h**，与采集器的 `maximumReasonableSpeedKmh = 132.0`（`NinebotRideRecorder.swift:48`）一致——即「表针永远走不出满量程」是设计好的，因为超过 132 的速度样本在采集侧就被丢掉了。

刻度（`:200-206`）：

```swift
ForEach(0..<33, id: \.self) { index in
    Capsule()
        .fill(index % 4 == 0 ? Color.teslaSecondaryText.opacity(0.74)
                             : Color.teslaSecondaryText.opacity(0.28))
        .frame(width: index % 4 == 0 ? 3 : 2,
               height: index % 4 == 0 ? 18 : 10)
        .offset(y: -128)
        .rotationEffect(.degrees(Double(index) / 32 * 270 - 135))
}
```

| 项 | 值 |
| --- | --- |
| 刻度总数 | **33**（index 0…32） |
| 主刻度 | `index % 4 == 0` → index 0, 4, 8, 12, 16, 20, 24, 28, 32 共 **9 个** |
| 次刻度 | 其余 **24 个** |
| 主刻度尺寸 / 不透明度 | 宽 3、高 18、`teslaSecondaryText` × **0.74** |
| 次刻度尺寸 / 不透明度 | 宽 2、高 10、`teslaSecondaryText` × **0.28** |
| 刻度半径 | **128**（`offset(y: -128)` 后绕视图中心旋转） |
| 刻度角度 | `index / 32 × 270 − 135` 度（**相对 12 点方向，顺时针为正**） |
| 每格代表 | 132 / 32 = **4.125 km/h** |
| 每主格代表 | 4 × 4.125 = **16.5 km/h** |

**主刻度落在 0 / 16.5 / 33 / 49.5 / 66 / 82.5 / 99 / 115.5 / 132 km/h** —— 全是非整数。iOS 没画数字标签所以看不出来。**Android 如果加数字标签，这套刻度会显示成「16.5」「49.5」这种，很难看。** 见 `## 待定` R9。

`.offset(y:) + .rotationEffect()` 这个组合在 SwiftUI 里之所以成立：`offset` 不改变布局 frame，而 `rotationEffect` 默认锚点是**布局 frame 的中心**（即 ZStack 中心），于是被 offset 出去的刻度绕中心公转。Compose 里对应 `DrawScope.rotate(degrees, pivot = center)`，或者直接算三角函数（推荐，见 3.1）。

#### 2.2 弧线与角度映射公式

```swift
// 底环（:208-211）
Circle()
    .trim(from: 0.125, to: 0.875)
    .stroke(Color.teslaControlBackground, style: StrokeStyle(lineWidth: 18, lineCap: .round))
    .rotationEffect(.degrees(90))

// 进度弧（:213-224）
Circle()
    .trim(from: 0.125, to: 0.125 + min(max(speedKmh / maxGaugeSpeed, 0), 1) * 0.75)
    .stroke(LinearGradient(colors: [Color.teslaGreen, .yellow, .red],
                           startPoint: .leading, endPoint: .trailing),
            style: StrokeStyle(lineWidth: 18, lineCap: .round))
    .rotationEffect(.degrees(90))
    .shadow(color: Color.teslaGreen.opacity(isRecording ? 0.55 : 0.18),
            radius: isRecording ? 18 : 6)
```

**换算到「起始角 + 扫过角」（这是 Compose `drawArc` 直接要的两个参数）**

SwiftUI `Circle().trim(from:to:)` 的分数 `f` 对应角度 `360f` 度，从 **3 点方向**起算、**顺时针**为正。再叠加 `.rotationEffect(.degrees(90))`：

```
底环：起 = 0.125 × 360 + 90 = 135°      终 = 0.875 × 360 + 90 = 405° ≡ 45°
      扫过 = (0.875 − 0.125) × 360 = 270°
进度：起 = 135°（同上）
      扫过 = 0.75 × 360 × fraction = 270° × fraction
      其中 fraction = clamp(speedKmh / 132, 0, 1)
```

Compose `drawArc` 的 `startAngle` 同样以 3 点方向为 0、顺时针为正，所以**数值可以直接照搬**：

```kotlin
private const val MAX_GAUGE_SPEED = 132f
private const val START_ANGLE = 135f      // 左下
private const val TOTAL_SWEEP = 270f      // 缺口 90° 在正下方

val fraction = (speedKmh / MAX_GAUGE_SPEED).coerceIn(0f, 1f)
drawArc(color = controlBackground, startAngle = START_ANGLE, sweepAngle = TOTAL_SWEEP,
        useCenter = false, style = Stroke(width = 18.dp.toPx(), cap = StrokeCap.Round))
drawArc(brush = gaugeBrush, startAngle = START_ANGLE, sweepAngle = TOTAL_SWEEP * fraction,
        useCenter = false, style = Stroke(width = 18.dp.toPx(), cap = StrokeCap.Round))
```

**几何自检**：`START_ANGLE = 135°` 在屏幕坐标（y 向下）里指向左下 `(cos135°, sin135°) = (−0.71, +0.71)`；终点 `135 + 270 = 405° ≡ 45°` 指向右下。缺口是从右下顺时针到左下的 90°，即**正下方开口**。与刻度公式一致：刻度 index 0 的角度是 `−135°`（相对 12 点顺时针），也就是左下；index 32 是 `+135°`，右下。两套公式的换算关系是 `刻度角(相对12点) = 弧角(相对3点) − 90°`。

**没有指针。** iOS 只有进度弧，中间是数字，**不画针**。别自己加一根针（要加也是 `## 待定`）。

**渐变方向有坑**：`LinearGradient(startPoint: .leading, endPoint: .trailing)` 定义在**旋转之前**的局部坐标系里，而 `.rotationEffect(90°)` 把整个渲染结果（含渐变）一起转了 90°。推导结果是屏幕上渐变轴变成**从上到下**（顶部绿、底部红），而弧的两端都在底部 → **两端都偏红、弧顶（约 66 km/h 处）最绿**。这与「越快越红」的直觉相反。

**这条必须用截图实测确认**，不要照着推导实现。做法：iOS 真机跑一遍，速度停在 30 / 66 / 120 三档各截一张图，取弧上像素颜色。确认后：

| 若实测是「顶绿底红」（推导结果） | 若实测是「左绿右红」 |
| --- | --- |
| Compose 用 `Brush.verticalGradient(listOf(green, yellow, red))` | Compose 用 `Brush.horizontalGradient(listOf(green, yellow, red))` |

两者都不要用 `Brush.sweepGradient`——那是「沿弧长渐变」，和 iOS 的线性渐变不是一回事，会让同一速度在两端显示不同颜色。

阴影（`:224`）：`teslaGreen` × `0.55`（记录中）/ `0.18`（未记录），radius `18` / `6`。Compose 没有对应的 outer glow，用 `Modifier.drawBehind` 画一圈 `BlurMaskFilter` 的弧，或退化成不做（`## 待定` D7 已覆盖阴影精细度的总体口径）。

#### 2.3 表盘中央的四行内容（`:226-259`）

`VStack(spacing: 6)`：

| 行 | 内容 | 字体 | 备注 |
| --- | --- | --- | --- |
| 1 | `formatRecordingSpeed(speedKmh, showsUnit: false)` | `system(size: 72, weight: .bold, design: .rounded)`，`monospacedDigit`，`lineLimit(1)`，`minimumScaleFactor(0.58)` | 最多 1 位小数、最少 0 位 → `0` / `23.4` / `132` |
| 2 | `"km/h"` | `.headline.monospacedDigit().weight(.semibold)`，`teslaSecondaryText` | |
| 3 | `"MAX " + formatRecordingSpeed(maxSpeedKmh)` + `arrow.up.forward` 图标 | `.caption.monospacedDigit().weight(.bold)`，`teslaGreen`，`padding(.top, 8)` | 带单位 → `MAX 42.7 km/h` |
| 4 | 两个 `RecordingGaugePill`，`HStack(spacing: 8)`，`padding(.top, 4)` | | 见下 |

外框：`.frame(height: 300)` + `.frame(maxWidth: .infinity)` + `.padding(.vertical, 8)`（`:261-263`）。所以**表盘直径 = min(可用宽度, 300)**，在 393dp 宽屏上（外层 16 + 卡片 12 = 28×2 内缩）可用宽约 337 → 直径 300。刻度半径 128 < 150，在圆内。18pt 的描边以路径为中心，会向外溢出 9pt 超出 300 的 frame（SwiftUI 默认不裁剪）—— **Compose 的 Canvas 会裁剪**，所以画弧时半径要取 `(size.minDimension - strokeWidth) / 2`，否则弧的外沿被切掉。

两个胶囊（`RecordingGaugePill`，`:267-287`）：

| # | 内容 | 图标 | 颜色 |
| --- | --- | --- | --- |
| 1 | `gpsQuality.title` | `gpsQuality.systemImage` | `gpsQuality.tint` |
| 2 | `formatRecordingG(accelerationG)` | `bolt.circle.fill` | `accelerationG > 0.35 ? .orange : teslaSecondaryText` |

样式：`HStack(spacing: 5)`，图标 `.caption2.weight(.bold)`，文字 `.caption.monospacedDigit().weight(.semibold)` `lineLimit(1)` `minimumScaleFactor(0.72)`，`padding(.horizontal, 9)` `padding(.vertical, 6)`，背景 `teslaControlBackground`，`Capsule()`。

**GPS 质量 5 档（`:91-120`，枚举定义在 `NinebotRideRecorder.swift:9-15`）**

| case | 文案 | SF Symbol | 颜色 |
| --- | --- | --- | --- |
| `waiting` | `等待 GPS` | `location` | `teslaSecondaryText` |
| `stabilizing` | `校准中` | `scope` | `teslaSecondaryText` |
| `good` | `GPS 稳定` | `location.fill` | `teslaGreen` |
| `weak` | `GPS 弱` | `location.slash` | `.orange` |
| `unavailable` | `定位不可用` | `exclamationmark.triangle.fill` | `.red` |

**各档的触发条件属于 4.2**（`updateGPSQuality` 用 `goodHorizontalAccuracy = 35.0` 分 good/weak，冷却期强制 `stabilizing`），本节只负责显示。

#### 2.4 G 值的显示范围与刷新频率

**来源见 4.2。** 本节只固定显示契约：

| 项 | 值 | 出处 |
| --- | --- | --- |
| 显示格式 | `formatRecordingG` = 最多 2 位、**最少 2 位**小数 + `" G"` → `0.00 G` / `0.12 G` / `1.35 G` | `NinebotRecordingView.swift:1044-1046` |
| 取值范围 | `0.00` ~ **`1.35`**（采集侧 clamp 到 `maximumReasonableMotionG = 1.35`） | `NinebotRideRecorder.swift:50`、`:318` |
| 变橙阈值 | **> 0.35**（严格大于） | `NinebotRecordingView.swift:255` |
| 更新频率 | **20 Hz**（`deviceMotionUpdateInterval = 1.0 / 20.0`） | `NinebotRideRecorder.swift:266` |
| 无 IMU 时 | 退化成 GPS 微分求 G，上界 `maximumReasonableGPSAccelerationG = 0.75`，随 GPS 定位频率更新 | `NinebotRideRecorder.swift:49`、`:379-384` |
| 最大 G | `maxAccelerationG`，仅 `isRecording` 时累计 | `NinebotRideRecorder.swift:321-323` |

**速度的更新频率**：由 GPS 定位回调驱动，`distanceFilter = 1` m + 相邻点最小间隔 `minimumLocationDeltaTime = 0.45` s → **实测约 1~2 Hz**（`NinebotRideRecorder.swift:70`、`:53`、`:352-356`）。所以表盘上「速度每秒跳一两次、G 值连续流动」是正常现象，不是 bug。

**四个 2×2 指标格（`RecordingMetricsGrid`，`:318-337`）**外面套了 `TimelineView(.periodic(from: .now, by: 1))` → **1 Hz 强制重绘**。原因：`elapsedSeconds` 是计算属性（`NinebotRideRecorder.swift:95-99`）不是 `@Published`，不刷新就不会走时间。四格内容：

| 格 | 值 | 图标 | 色 |
| --- | --- | --- | --- |
| 当前 G | `formatRecordingG(currentAccelerationG)` | `bolt.circle.fill` | `.yellow` |
| 最大 G | `formatRecordingG(maxAccelerationG)` | `bolt.fill` | `.red` |
| 距离 | `formatRecordingDistance(distanceKilometers)`（2 位小数 + `" km"`） | `point.3.connected.trianglepath.dotted` | `teslaGreen` |
| 时长 | `formatRecordingDuration(elapsedSeconds)` | `timer` | `teslaSecondaryText` |

`formatRecordingDuration`（`:1048-1057`）：`hours > 0 → "H:MM:SS"`（小时不补零），否则 `"MM:SS"`（分钟补零）。例：3725 s → `1:02:05`；65 s → `01:05`。

**动画：iOS 一处都没有。** 速度弧、数字、G 值全是随 `@Published` 直接跳变。别加 `animateFloatAsState`——在 1~2 Hz 的速度更新上加 300ms 补间会让表盘持续滞后于真实速度，骑行时看着像坏了。

#### 2.5 屏幕常亮与横竖屏（iOS 现状：都没做）

- **屏幕常亮：iOS 没有。** 全仓搜不到 `isIdleTimerDisabled`。骑行中屏幕会按系统设置自动锁屏；锁屏后记录靠后台定位继续（`NinebotRideRecorder.swift:195-202`），数据不丢，但**看不到仪表了**。
- **横竖屏：iOS 允许竖屏 + 左右横屏**（`mini-ninebot/Config/mini-ninebot-Info.plist:61-66`，iPhone 三向；iPad 四向 `:67-73`）。记录页是一条竖直 `ScrollView`，横屏下 300pt 的表盘 + 大按钮会把内容挤到要滚动，**没有专门的横屏布局**。
- `RecordingHeader` 的状态文案里写着「正在记录 · 可以锁屏，后台继续」（`:173`），源码注释明确说「记录现在能扛住进后台和锁屏，但界面上没别的地方说这件事」。

Android 侧这两条都是新增行为 → `## 待定` R4（屏幕常亮）、R5（横屏布局）。

### 三 · Android 实现要点

#### 3.1 Canvas 手绘

```kotlin
@Composable
fun RecordingSpeedGauge(
    speedKmh: State<Float>,          // ← 传 State，不是值
    maxSpeedKmh: State<Float>,
    accelerationG: State<Float>,
    gpsQuality: RecordingGpsQuality,
    isRecording: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = NinePlusTheme.colors
    val tickMajor = colors.secondaryText.copy(alpha = 0.74f)
    val tickMinor = colors.secondaryText.copy(alpha = 0.28f)

    Box(modifier.height(300.dp).fillMaxWidth().padding(vertical = 8.dp)) {
        Canvas(Modifier.fillMaxSize()) {                 // 只读 State → 跳过重组，只走 draw
            val stroke = 18.dp.toPx()
            val diameter = size.minDimension
            val center = Offset(size.width / 2f, size.height / 2f)
            val radius = (diameter - stroke) / 2f        // ← 必须减去描边宽，Canvas 会裁剪
            val arcRect = Rect(center = center, radius = radius)

            // 33 个刻度：角度以 12 点为 0、顺时针为正
            repeat(33) { i ->
                val isMajor = i % 4 == 0
                val theta = Math.toRadians(i / 32.0 * 270.0 - 135.0)
                val tickR = 128.dp.toPx()
                val cx = center.x + tickR * sin(theta).toFloat()
                val cy = center.y - tickR * cos(theta).toFloat()
                rotate(degrees = (i / 32f * 270f - 135f), pivot = Offset(cx, cy)) {
                    drawRoundRect(
                        color = if (isMajor) tickMajor else tickMinor,
                        topLeft = Offset(cx - (if (isMajor) 3f else 2f).dp.toPx() / 2f,
                                         cy - (if (isMajor) 18f else 10f).dp.toPx() / 2f),
                        size = Size((if (isMajor) 3f else 2f).dp.toPx(),
                                    (if (isMajor) 18f else 10f).dp.toPx()),
                        cornerRadius = CornerRadius((if (isMajor) 3f else 2f).dp.toPx() / 2f),
                    )
                }
            }

            drawArc(color = colors.controlBackground, startAngle = 135f, sweepAngle = 270f,
                    useCenter = false, topLeft = arcRect.topLeft, size = arcRect.size,
                    style = Stroke(width = stroke, cap = StrokeCap.Round))

            val fraction = (speedKmh.value / 132f).coerceIn(0f, 1f)
            if (fraction > 0f) {
                drawArc(brush = gaugeBrush,                     // 方向由截图实测决定，见 2.2
                        startAngle = 135f, sweepAngle = 270f * fraction,
                        useCenter = false, topLeft = arcRect.topLeft, size = arcRect.size,
                        style = Stroke(width = stroke, cap = StrokeCap.Round))
            }
        }
        // 中央四行用普通 Composable 叠在上面
    }
}
```

四个要点：

1. **传 `State<Float>` 而不是 `Float`**。G 值 20 Hz 更新，如果作为普通参数传进来，每次都触发**重组**；把读取放进 `Canvas` 的 draw lambda 里，只触发**重绘**（跳过组合和布局两个阶段）。这是本项唯一的性能要点。
2. **`radius = (minDimension − strokeWidth) / 2`**。Compose 的 `Canvas` 裁剪到自身边界，iOS 不裁剪。照抄 iOS 的「直径 300、描边 18 向外溢出 9」会导致弧外沿被切平。
3. **`StrokeCap.Round` 会让 0 速度时也出现一个圆点**（半径 9pt 的半圆）。iOS 同样如此（`lineCap: .round` 且 `trim(from:0.125, to:0.125)` 时 SwiftUI 不画）。差异：Compose `sweepAngle = 0f` 时 `drawArc` 仍可能画出圆帽。**加 `if (fraction > 0f)` 守卫**，并在 0 km/h 时截图比对。
4. **刻度不要用整体 `rotate` 包住循环**（那会让每个刻度的坐标基准都变），要么按上面的写法逐个算圆心再局部旋转，要么用 `withTransform { rotate(...) }` 每次只包一个刻度。

字号：72sp（`fontFamily` 用圆体近似 `design: .rounded`，Material 侧没有等价物，用系统默认 + `FontWeight.Bold`），`minimumScaleFactor(0.58)` 用 `BasicText` + `TextAutoSize.StepBased(minFontSize = 42.sp, maxFontSize = 72.sp)`（72 × 0.58 ≈ 41.8）。

#### 3.2 屏幕常亮（若 R4 定为「做」）

```kotlin
val view = LocalView.current
DisposableEffect(isRecording) {
    view.keepScreenOn = isRecording
    onDispose { view.keepScreenOn = false }
}
```

**不要用 `WakeLock`。** `keepScreenOn` 跟随 View 生命周期自动释放，`WakeLock` 忘了 `release()` 就会一直亮着直到电池耗尽，而且需要 `WAKE_LOCK` 权限。`onDispose` 里必须置 `false`——否则离开记录页屏幕仍然常亮。

#### 3.3 横竖屏

- **不要在 Manifest 里 `screenOrientation="portrait"`**。Android 15+ 对大屏设备强制忽略方向限制，写了也不生效，还会在折叠屏上出现黑边。
- 用 `WindowSizeClass`（`androidx.window`）分支：`heightSizeClass == Compact`（横屏手机）时把「表盘 + 中央数字」和「2×2 指标格」改成左右并排，表盘尺寸从 300dp 降到 `min(可用高度 - 32dp, 300dp)`。
- 配置变更时 `NinebotRideRecorder` 对应的 Repository/Service **必须活过旋转**。放前台服务 + `ViewModel`，绝不放 Composable 的 `remember`。旋转丢掉正在进行的记录是最严重的可能故障。

#### 3.4 前台服务与记录状态

4.2 负责采集，但**「记录中」这个状态的持有者要在这里定清**：

```
前台服务（0.6 的骨架）持有 RideRecordingSession（单例，进程级）
  ├─ StateFlow<Float> speedKmh / accelG / maxSpeed / maxAccelG / distanceMeters
  ├─ StateFlow<RecordingGpsQuality> gpsQuality
  ├─ StateFlow<Boolean> isRecording
  └─ fun start(vehicleSn: String?) / fun stop(): RecordedRide?
ViewModel 只订阅，不持有
```

对齐 iOS 的两个副作用（`NinebotRecordingView.swift:82-87`）：

```
onAppear  → recorder.startPreview()        进页面就开始定位（未记录也要，为了显示当前位置）
onDisappear → recorder.stopPreviewIfIdle() 离开页面且未在记录 → 停止定位
```

Compose 侧用 `LifecycleEventEffect(ON_START / ON_STOP)`，**不要用 `DisposableEffect(Unit)`**——后者在配置变更时会走一遍 dispose，导致旋转屏幕时预览定位被停掉再开。

预览态也要开定位这件事有耗电代价：iOS 侧特意只在真正记录时才打开 `allowsBackgroundLocationUpdates`（`NinebotRideRecorder.swift:191-202` 的注释），预览态是前台定位。Android 对齐：预览态用普通定位请求，记录态才启动前台服务。

### 四 · 陷阱

1. **量程 132 不是 120 也不是 140**。`maxGaugeSpeed`（`NinebotRecordingView.swift:196`）和 `maximumReasonableSpeedKmh`（`NinebotRideRecorder.swift:48`）必须同源，写成一个共享常量。如果 4.2 真机调参时把 132 改了，表盘量程要跟着改，否则表针会顶死在满量程。

2. **`startAngle` 的参考方向：Compose 是 3 点，SwiftUI trim 也是 3 点，但 iOS 额外叠了 `rotationEffect(90°)`**。少加这 90° 会得到一个「缺口在右侧」的表，看起来像坏了。刻度公式的参考方向是 **12 点**，两套差 90°，别混用。

3. **20 Hz 的 G 值不能走普通参数传递**。实测一次：把 G 值当 `Float` 参数传进 `RecordingSpeedGauge`，用 Layout Inspector 看重组次数——会看到每秒 20 次全卡片重组，中低端机上明显掉帧。

4. **不要给速度弧加动画**。见 2.4。

5. **`accelerationG > 0.35` 是严格大于**（`:255`）。恰好 0.35 不变橙。

6. **`formatRecordingG` 最少 2 位小数**，所以 0 显示成 `0.00 G` 不是 `0 G`。Kotlin 侧 `DecimalFormat` 要显式设 `minimumFractionDigits = 2`，并且按 Phase 1 的 2.5 节把 `isGroupingUsed = false`、`roundingMode = HALF_EVEN` 一起设上。

7. **`formatRecordingDate` 没有设时区**（`NinebotRecordingView.swift:1059-1064`：只设了 `locale = zh_CN` 和 `dateFormat = "MM-dd HH:mm"`），走**设备时区**；而 `NinebotFormatting.swift:38-52` 的 `formatDate` / `formatTime` 固定 `Asia/Shanghai`。**同一条记录在记录 Tab 和行程 Tab 会显示不同时间**（设备时区非 +8 时）。见 `## 待定` R10。

8. **`RecordingMetricsGrid` 的 1 Hz `TimelineView` 不能省**。Android 侧计时器要独立于传感器：用 `LaunchedEffect { while (true) { delay(1000); tick++ } }` 或 `flow { while(true){ emit(now); delay(1000) } }`，别指望 `distanceMeters` 变化顺带刷新时长——停车等红灯时距离不变，时长必须继续走。

9. **`ScrollView` 里放 300dp 的 Canvas + 地图**：Compose 的 `Column(verticalScroll)` 里嵌 `AndroidView(MapView)` 会争抢手势。地图外面套 `Modifier.pointerInteropFilter`，或对齐 iOS 的做法——`RecordingTrackPreview` 的地图设了 `interactionModes: []`（`NinebotRecordingView.swift:387`），**完全禁用交互**。照抄：高德侧 `uiSettings.setAllGesturesEnabled(false)`。

10. **记录中被系统杀掉**。iOS 靠后台定位模式保命，Android 靠前台服务 + 国产 ROM 白名单引导（0.6）。这一项在 4.3 的验收里必须实测，因为「表盘好看但骑到一半记录断了」是最难挽回的失败。

### 五 · 验收标准

- [ ] 量程 132：输入 0 / 33 / 66 / 99 / 132 / 200 km/h，弧扫过角分别为 0° / 67.5° / 135° / 202.5° / 270° / 270°（截图量角或用 `captureToImage` 断言像素）
- [ ] 33 个刻度：9 个主刻度（宽 3 高 18 alpha 0.74）+ 24 个次刻度（宽 2 高 10 alpha 0.28），首尾分别在左下与右下，缺口 90° 在正下方
- [ ] 刻度半径 128dp，与弧的位置关系和 iOS 截图叠图误差 < 2dp
- [ ] 弧起点 135°、总扫过 270°，与 iOS 并排截图叠图无角度偏差
- [ ] **渐变方向先实测 iOS**（30 / 66 / 120 km/h 三档截图取色），再实现，两端同速度下弧上取色一致
- [ ] 0 km/h 时不出现残留圆帽（`fraction > 0f` 守卫生效）
- [ ] 弧外沿不被 Canvas 裁平（`radius` 减去了描边宽）
- [ ] 中央数字 72sp、`0` / `23.4` / `132` 三种输出格式正确；`minimumScaleFactor` 等价物在最大系统字号下不裁字
- [ ] `MAX` 行显示带单位（`MAX 42.7 km/h`），未记录时为 `MAX 0 km/h`
- [ ] G 胶囊：`0.00 G` / `0.35 G`（不橙） / `0.36 G`（橙） / `1.35 G` 四档正确
- [ ] GPS 质量 5 档文案、图标、颜色逐项对齐 2.3 的表
- [ ] G 值 20 Hz 更新时，Layout Inspector 显示卡片**重组次数为 0**（只有重绘）
- [ ] 速度、弧、G 值均无补间动画（逐帧录屏比对，跳变时刻两端一致）
- [ ] 停车不动 60 秒：距离不变、时长每秒 +1（1 Hz 计时器独立生效）
- [ ] 时长格式：65 s → `01:05`，3725 s → `1:02:05`
- [ ] 旋转屏幕：正在进行的记录不中断、已采集点数不变、表盘数值连续
- [ ] 横屏下表盘不被裁、内容不重叠（`heightSizeClass == Compact` 分支）
- [ ] 屏幕常亮（若 R4 定为做）：记录中不自动锁屏；离开记录页后恢复系统超时
- [ ] 记录中息屏 10 分钟再亮屏：轨迹连续，无 10 分钟空档
- [ ] 记录中 `adb shell am kill <pkg>` 之后的行为符合 R4 之外的既定预期（前台服务应存活；若被杀，重进 App 要能给出明确提示而不是静默丢数据）
- [ ] 在一台国产 ROM（小米或 OPPO）上重跑「息屏 10 分钟」与「后台 30 分钟」两项

---

## 4.4 本地记录列表、详情、轨迹回放（4 天，风险中）

### 一 · iOS 现状

分散在两个文件、两条入口路径。

**记录 Tab 路径**（`NinebotRecordingView.swift`）

| 组件 | 行号 | 作用 |
| --- | --- | --- |
| `RecordingHistorySection` | 478-509 | 「最近记录」列表，**只显示 5 条** |
| `RecordedRideRowContent` | 511-548 | 列表行 |
| `RecordedRideDetailView` | 550-639 | 记录详情页 |
| `RecordedRideDetailHero` | 641-685 | 详情页头卡 |
| `RecordedRideTrackMap` | 687-819 | 轨迹地图 + **回放滑块** |
| `RecordedRideDetailMetrics` | 821-842 | 8 格指标 |
| `RecordedRideExportCard` | 844-916 | GPX 导出（见 4.5） |
| `RideAssociationSheet` | 951-1028 | 结束记录后的「关联到哪段行程」表单 |

**行程 Tab 路径**（`NinebotDashboardView.swift`）

| 组件 | 行号 | 作用 |
| --- | --- | --- |
| `associatedRecord(for:)` | 3997-4001 | 按 `associatedRideID` 找本地记录 |
| `NinebotRideDetailView` | 4084-4160 | 接口行程详情，内嵌本地/接口轨迹面板 |
| `RideDetailHero` | 4162-4246 | 有本地记录时追加 3 格指标 + 「已关联本地轨迹」 |
| `RideTrackMapPanel` | 4248-4335 | 本地轨迹（速度分段着色，**无回放滑块**） |
| `TrackSpeedPoint` / `TrackSpeedSegment` | 4417-4431 | 分段模型 |
| `TrackMaxSpeedBadge` | 4433-4450 | 最快点徽章 |
| `TrackSpeedLegend` | 4452-4473 | 速度图例 |
| `speedTrackPoints` / `speedTrackSegments` / `maxSpeedTrackPoint` | 4475-4509 | `NinebotRecordedRide` 的私有扩展 |
| **`makeSpeedTrackSegments`** | **4511-4524** | **分段算法（top-level）** |
| **`bestSpeedTrackPoint`** | **4526-4530** | **最快点（top-level）** |
| **`speedTrackColor`** | **4532-4544** | **颜色映射（按约定留在界面层）** |

**数据层**：`NinebotRecordedRide`（`NinebotModels.swift:859-1005`）、`NinebotRideTrackPoint`（`:831-857`）、`NinebotSharedStore` 的记录读写（`NinebotSharedStore.swift:216-335`）、`NinebotViewModel` 的 6 个方法（`:414-431`、`:461-471`）。

**测试**：`Tests/NineBotCoreTests/RecordedRideTests.swift`（**13 个用例**，距离重算 6 个 + 摘要/轨迹拆分 7 个）、`Tests/NineBotCoreTests/SharedStoreTrackStorageTests.swift`（**10 个用例**，存储拆分与旧数据迁移）、`Tests/NineBotCoreTests/ModelCodingTests.swift:513-681` 的 `RecordedRideTrackSamplingTests`（**16 个用例**，坐标过滤 6 个 + 抽稀 9 个 + 坐标转换 1 个）。合计 **39 个**。

### 二 · 要移植的逻辑

#### 2.1 `NinebotRecordedRide` 的字段（`NinebotModels.swift:859-899`）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `String` | 默认 `UUID().uuidString` |
| `vehicleSN` | `String?` | 可为 nil（无车时也能记录） |
| `associatedRideID` | `String?` | 关联的接口行程 id，nil = 未关联 |
| `startedAt` | `Date` | **非可选** |
| `endedAt` | `Date` | **非可选** |
| `distanceMeters` | `Double` | 存的是**重算后**的值，见 2.3 |
| `maxSpeedKmh` | `Double` | |
| `averageSpeedKmh` | `Double` | |
| `maxAccelerationG` | `Double` | |
| `points` | `[NinebotRideTrackPoint]` | 摘要形态下为**空数组** |
| `pointCount` | `Int?` | **可选**，为兼容轨迹拆分之前写入的记录；`init` 里 `pointCount ?? points.count` |

派生（`:901-967`）：

| 派生 | 定义 |
| --- | --- |
| `durationSeconds` | `max(endedAt − startedAt, 0)` |
| `trackPointCount` | `pointCount ?? points.count` |
| `isTrackLoaded` | `!points.isEmpty || trackPointCount == 0`（**空轨迹的记录视为已加载**） |
| `distanceKilometers` | `displayDistanceMeters / 1000` |
| `displayDistanceMeters` | `recalculated > 0 ? recalculated : distanceMeters` |
| `trackCoordinates` | 排序 + 过滤 + 坐标转换，见 2.2 |
| `sampledTrackCoordinates(maxCount:)` | 抽稀，见 2.4 |

`NinebotRideTrackPoint`（`:831-857`）：`id`（默认 UUID）、`date`、`latitude`、`longitude`、`speedKmh: Double`、`accelerationG: Double`、`horizontalAccuracy: Double?`。字段语义与采集见 4.2。

#### 2.2 轨迹点的过滤（`trackCoordinates`，`:939-950`）

```
points
  .sorted { $0.date < $1.date }                        ← 必须先按时间排序
  .filter {
      lat ∈ [-90, 90]
      && lon ∈ [-180, 180]
      && (horizontalAccuracy ?? 0) <= 120              ← nil 视为 0，即保留
  }
  .map { 坐标转换 }
```

三条测试钉住的行为（`ModelCodingTests.swift:552-595`）：
- 乱序输入按 `date` 排序后输出（`testTrackCoordinatesAreSortedByDate`）。
- 精度 500 m 的点被丢，**前后点直接连起来**，不插值（`testTrackCoordinatesDropInaccuratePoints`）。
- `horizontalAccuracy == nil` 的点**保留**（`?? 0 <= 120`，`testTrackCoordinatesKeepPointsWithoutAnAccuracyReading`）。这条最容易在 Kotlin 侧写成 `?: Double.MAX_VALUE` 而把点全丢掉。

`speedTrackPoints`（`NinebotDashboardView.swift:4480-4496`）用的是**同一套过滤条件**，外加 `.enumerated()` 生成兜底 id（`"local-{index}"`，当 `point.id` 为空时）。两处必须共用一个函数，否则地图折线和分段着色会用不同的点集。

#### 2.3 距离重算（`recalculatedDistanceMeters`，`:969-1004`）

**列表里显示的距离不是采集时累加的那个值，而是从轨迹点重新算出来的。**

```
points.count <= 1 → 0
按 date 排序
逐点：
  跳过 lat/lon 越界 或 (horizontalAccuracy ?? 0) > 120 的点        ← 与 trackCoordinates 同一套
  与上一个「保留下来的点」算大圆距离（CLLocation.distance，即 WGS-84 椭球距离）
  只有同时满足才累加：
      deltaTime >= 0
      deltaTime <= 30           秒
      distance  >= 0
      distance  <= 300          米
  无论是否累加，都把当前点设为「上一个点」
```

四条测试（`RecordedRideTests.swift:39-98`）：3 点各 100 m → 200 m；中间点精度 500 被丢 → 仍是 200 m（跨过被丢的点直接连）；间隔 120 s → 0 m（超 30 s 上限）；5 s 内 5.5 km → 0 m（超 300 m 上限）。

**注意三组上限互不相同，不要统一**：

| 用途 | 时间上限 | 距离上限 | 出处 |
| --- | --- | --- | --- |
| 事后距离重算 | 30 s | 300 m | `NinebotModels.swift:993-995` |
| 采集时段内累加 | 6 s（`maximumLocationDeltaTimeForSpeed`） | 160 m（`maximumReasonableSegmentDistance`） | `NinebotRideRecorder.swift:54`、`:51`（属 4.2） |
| 坐标过滤精度阈值 | — | 120 m 水平精度 | `NinebotModels.swift:945`、`:977` |

**为什么必须重算**：`distanceMeters` 是采集时用 6 s / 160 m 的严格窗口累加的，事后用 30 s / 300 m 的宽松窗口重算，能把「隧道里断了几秒」这类缺口补回来。`displayDistanceMeters` 优先取重算值，重算为 0（没轨迹点）才回退到存储值。

**摘要必须冻结重算结果**（`trackSummary()`，`:918-926`）：

```swift
func trackSummary() -> NinebotRecordedRide {
    var summary = self
    summary.distanceMeters = displayDistanceMeters      // ← 冻结
    summary.pointCount = points.isEmpty ? trackPointCount : points.count
    summary.points = []
    return summary
}
```

不冻结的话，列表行为了显示距离就得把全部轨迹点读出来，懒加载白做（`phase0-foundation-spec.md:181` 已记录这个坑）。而且 `trackSummary()` **必须幂等**——对摘要再摘要一次不能把点数清零（测试 `testSummaryIsIdempotent`，注释里写明「弄错这个会让每次重存都把点数清零，于是详情页再也不去加载轨迹，尽管文件还在磁盘上」）。

对应的 `withTrack(_:)`（`:928-933`）：传空数组时**保留已知点数**（`points.isEmpty ? trackPointCount : points.count`），所以一次失败的磁盘读取不会把 4 点的记录变成 0 点（测试 `testWithEmptyTrackKeepsTheKnownCount`）。

#### 2.4 抽稀（`sampledTrackCoordinates`，`:952-959`）

```
coordinates = trackCoordinates                     ← 已过滤、已转换
coordinates.count <= maxCount 或 maxCount <= 1 → 返回全部
step = (count − 1) / (maxCount − 1)
返回 (0 until maxCount).map { coordinates[min(round(i × step), count − 1)] }
```

`maxCount` 默认 **120**。首尾必被保留，顺序不变（测试 `testSamplingThinsToTheDefaultCap`、`testSamplingKeepsTheTrackOrder`）。`maxCount = 0 / 1` 返回全部（测试 `testSamplingWithACapBelowTwoReturnsTheWholeTrack`）。

**这个方法在 App 里其实没被调用**——只有测试引用它（全仓 grep 确认）。实际在用的是 `NinebotRecordingView.swift:1083-1089` 的同名 top-level 函数 `sampledMapCoordinates`，算法逐字相同，被 `RecordingTrackPreview` 用来给实时轨迹打圆点标注（`:446-448`）。**Android 侧只写一份**，放领域层。

#### 2.5 摘要与轨迹点分开存（`NinebotSharedStore.swift:216-335`）

**这是本项最重要的存储事实。** 一条记录的数据被劈成两半：

| 部分 | 位置 | 键 / 路径 |
| --- | --- | --- |
| 摘要数组（全部记录，无轨迹点） | `UserDefaults(App Group)` | 键 `"ninebot.recorded.rides"`（`:16`），整个数组一个 JSON |
| 轨迹点 | **文件系统，每条记录一个文件** | `{AppGroup容器}/RideTracks/{sanitize(id)}.json`（`:327-335`） |

`sanitizedFileName`（`:589-594`）：非 `[A-Za-z0-9\-_]` 的字符逐个替换成 `_`，结果为空则用 `"vehicle"`。

关键行为，逐条：

| 行为 | 实现 | 行号 |
| --- | --- | --- |
| 列表读取只拿摘要 | `loadRecordedRides()` 只解 UserDefaults，`points` 恒为空 | `:219-236` |
| **旧数据迁移** | 读到任何一条 `!points.isEmpty` → 把**全部**记录的点写进各自文件、转成摘要、回写 UserDefaults | `:226-233` |
| 详情读取 | `loadRecordedRide(id:)` = 摘要 + `loadTrackPoints(id:)` | `:239-242` |
| 单条轨迹读取 | 文件不存在 / 解码失败 → **返回空数组**，不报错 | `:244-251` |
| 保留上限 | 按 `startedAt` 降序取前 **120** 条；被裁掉的**同时删轨迹文件** | `:253-259` |
| **摘要不覆盖磁盘轨迹** | 只在 `!ride.points.isEmpty || ride.trackPointCount == 0` 时才写文件 | `:262-265` |
| 排序 | 恒按 `startedAt` **降序**（新的在前） | `:232`、`:235`、`:254` |
| upsert | 按 `id` 找到则替换，否则 `insert(at: 0)`，然后走 `saveRecordedRides` 重排 | `:272-280` |
| 删除 | 过滤掉摘要 + 删轨迹文件 + 重存 | `:282-286` |
| 占用统计 | `recordedTrackByteCount()` 遍历 `RideTracks/` 累加文件大小（诊断中心用） | `:288-299` |

`SharedStoreTrackStorageTests.swift` 的 10 个用例把这些全钉住了，其中三个必须原样搬到 Android：

- `testDefaultsPayloadStaysSmallForALongRide`（`:86-96`）：4000 点（约两小时、2 s 采样）的记录，摘要 < 4 KB，轨迹 > 50 KB，且摘要 < 轨迹/10。
- `testResavingSummariesPreservesTracks`（`:117-128`）：改一条摘要的 `associatedRideID` 后重存全部摘要，**磁盘上的 200 个点必须还在**。这是「摘要不覆盖磁盘轨迹」那条守卫的回归测试。
- `testLegacyInlineRecordsAreMigratedOnFirstRead`（`:192-209`）：直接往 UserDefaults 塞一条 500 点的内联旧记录，第一次读取后摘要体积降到原来的 1/10 以下，且轨迹能完整读回。

#### 2.6 列表（`RecordingHistorySection`，`NinebotRecordingView.swift:478-509`）

```
records = model.recordedRides(for: snapshot?.vehicle.sn)
过滤（NinebotViewModel.swift:414-419）：
   sn == nil                → 全部
   ride.vehicleSN == nil    → 保留（无车时录的记录在任何车下都可见）
   ride.vehicleSN == sn     → 保留
排序：沿用 store 的 startedAt 降序
显示：records.prefix(5)        ← 只有 5 条，没有「查看全部」入口
空态：「结束一次记录后会出现在这里」
```

**上限 120 条但界面只露 5 条**，第 6 条起在 App 里**完全看不到**（只能通过行程 Tab 的关联关系间接进入）。见 `## 待定` R11。

列表行（`RecordedRideRowContent`，`:511-548`）：

| 位置 | 内容 |
| --- | --- |
| 左图标 | `associatedRideID == nil ? "record.circle"(secondaryText) : "checkmark.circle.fill"(teslaGreen)` |
| 主标题 | `formatRecordingDate(startedAt)` → `MM-dd HH:mm`（**设备时区**，见 4.3 陷阱 7） |
| 副标题 | `associatedRideID == nil ? "未关联行程" : "已关联行程"` |
| 右上 | `formatRecordingDistance(distanceKilometers)` → 2 位小数 + `" km"` |
| 右下 | `formatRecordingSpeed(maxSpeedKmh)` → 1 位小数 + `" km/h"`，`teslaGreen` |
| 尾 | `chevron.right` |

样式：`padding(12)`、`minHeight 72`、`ninePlusCard(cornerRadius: 22)`，行间距 8。

#### 2.7 详情（`RecordedRideDetailView`，`:550-639`）

块序：头卡 → 轨迹地图 → 8 格指标 → 导出卡 → （有关联时）关联卡 → 删除按钮。`padding(16)` + `padding(.bottom, 20)`，间距 16。

**轨迹的懒加载**（`:611-614`）：

```swift
.task(id: record.id) {
    guard !record.isTrackLoaded else { return }
    loadedRecord = NinebotSharedStore().loadRecordedRide(id: record.id)
}
```

`detailRecord = loadedRecord ?? record`（`:559-561`）。地图挂 `.id(detailRecord.points.count)`（`:568`）强制在轨迹到位后重建 View，让 `@State cameraPosition` 用新坐标重新初始化。

**这段是同步磁盘 IO 跑在主线程上**（`loadRecordedRide` 内部会解 UserDefaults 里的整个摘要数组 + 读文件 + 解码）。Android 必须走 Room `suspend` + `Dispatchers.IO`。

**8 格指标**（`RecordedRideDetailMetrics`，`:821-842`），2 列 `LazyVGrid`，间距 10：

| 格 | 值 | 图标 | 色 |
| --- | --- | --- | --- |
| 开始 | `formatRecordingDate(startedAt)` | `play.fill` | `teslaGreen` |
| 结束 | `formatRecordingDate(endedAt)` | `stop.fill` | `.red` |
| 时长 | `formatRecordingDuration(durationSeconds)` | `timer` | `teslaSecondaryText` |
| 均速 | `formatRecordingSpeed(averageSpeedKmh)` | `speedometer` | `teslaGreen` |
| 最快 | `formatRecordingSpeed(maxSpeedKmh)` | `gauge.with.dots.needle.67percent` | `.yellow` |
| 最大 G | `formatRecordingG(maxAccelerationG)` | `bolt.circle.fill` | `.red` |
| 轨迹点 | `"{trackPointCount} 个"` | `point.3.connected.trianglepath.dotted` | `teslaGreen` |
| 关联 | `associatedRideID == nil ? "未关联" : "已关联"` | `link` | nil→`secondaryText` / 有→`teslaGreen` |

头卡（`RecordedRideDetailHero`，`:641-685`）：`formatRecordingDate(startedAt)` 作标题，副标题是 `"{开始} - {结束}"`（**两个都用 `formatRecordingDate`，所以是 `MM-dd HH:mm - MM-dd HH:mm`**），巨型距离 `system(size: 44, weight: .bold, design: .rounded)` `minimumScaleFactor(0.62)` + 标签「本地记录」。

删除（`:592-603`、`:629-637`）：红底按钮「删除这条记录」（`trash.fill`，高 54，圆角 18）→ `confirmationDialog`：

```
标题   "删除这条记录？"（titleVisibility: .visible）
消息   "{MM-dd HH:mm} · {x.xx km}"
按钮   "删除记录"（destructive）/ "取消"（cancel）
```

删除后 `dismiss()` 返回列表。

关联卡（`:572-590`）：`Label("已关联接口行程", systemImage: "link")` + 等宽字体显示 `associatedRideID`，`textSelection(.enabled)`。

复制提示浮层（`:615-628`）：顶部胶囊 + `.regularMaterial` 背景，`animation(.easeInOut(duration: 0.18))`，文案与时长见 4.5。

#### 2.8 回放（`RecordedRideTrackMap`，`:687-819`）—— **iOS 没有自动播放，只有一个拖拽滑块**

完整实现就这些：

```swift
@State private var playbackProgress: Double = 1        // ← 初始 1，即停在终点

// 地图内（:726-741）
if let playbackCoordinate {
    Annotation("回放", coordinate: playbackCoordinate) {
        ZStack {
            Circle().fill(Color.teslaGreen.opacity(0.18)).frame(width: 26, height: 26)
            Circle().fill(Color.teslaGreen).frame(width: 12, height: 12)
                .overlay { Circle().stroke(Color(.systemBackground), lineWidth: 2) }
        }
    }
}

// 滑块（:760-772），仅当坐标数 > 1 才出现
HStack(spacing: 10) {
    Image(systemName: "play.circle.fill")          // ← 只是图标，不可点
    Slider(value: $playbackProgress, in: 0...1).tint(Color.teslaGreen)
    Text(playbackTimeText)                          // .frame(width: 46, alignment: .trailing)
}

// 索引映射（:783-788）
index = clamp(Int(round(Double(count − 1) × playbackProgress)), 0, count − 1)

// 时间文案（:790-793）
playbackTimeText = formatRecordingDuration(durationSeconds × playbackProgress)
```

**明确记录：**

| 项 | iOS 现状 |
| --- | --- |
| 自动播放 | **没有**。`play.circle.fill` 只是装饰图标，不是按钮，点了没反应 |
| 倍速 | **没有** |
| 时间轴 | 有，但是**线性插值出来的假时间轴**：`durationSeconds × progress`，与轨迹点的真实 `date` 无关。采样不均匀时（隧道断档）滑块位置和显示时间会对不上 |
| 初始位置 | `progress = 1`，即打开就停在终点 |
| 播放点样式 | 26pt 半透明外圈（绿 18%）+ 12pt 实心绿点 + 2pt 系统背景色描边 |
| 起终点 | `Marker("开始", "play.fill", teslaGreen)` / `Marker("结束", "stop.fill", .red)`（`:716-724`） |
| 折线 | **单色 `teslaGreen`，4pt**，无速度分段（`:711-714`） |
| 空轨迹 | 覆盖层：`map` 图标 + 「这条记录没有轨迹点」（`:744-755`） |
| 地图高度 | 300 |
| 标题行 | 「轨迹」+ 右侧 `"{trackPointCount} 点"` |

真正的自动播放 + 倍速是**新功能** → `## 待定` R3。

#### 2.9 速度分段着色（4.1 与 4.4 共用）

**`makeSpeedTrackSegments`（`NinebotDashboardView.swift:4511-4524`）**

```swift
guard points.count > 1 else { return [] }
return (0..<(points.count - 1)).map { index in
    let start = points[index]
    let end   = points[index + 1]
    let speed = end.speedKmh ?? start.speedKmh        // ← 优先用「终点」速度
    return TrackSpeedSegment(
        id: "\(start.id)-\(end.id)-\(index)",
        coordinates: [start.coordinate, end.coordinate],
        speedKmh: speed
    )
}
```

要点：
- 输出 **n − 1 段**，每段恰好 2 个坐标。
- 段速取 **`end.speedKmh`，为 nil 才回退 `start.speedKmh`**，两个都 nil 则段速为 nil。
- 段 id = `"{起点id}-{终点id}-{下标}"`。

**`speedTrackColor`（`:4532-4544`）—— 区间边界原文**

```swift
guard let speed else { return Color.teslaGreen }      // ← nil 也是绿
switch speed {
case ..<8:   return .cyan
case ..<25:  return Color.teslaGreen
case ..<40:  return .orange
default:     return .red
}
```

| 速度区间（km/h） | 颜色 | 图例文案（`TrackSpeedLegend`，`:4452-4473`） |
| --- | --- | --- |
| `speed == nil` | `teslaGreen` | （图例里没有这一档） |
| `[0, 8)` | `.cyan`（SwiftUI 系统青） | 低速 |
| `[8, 25)` | `teslaGreen` | 巡航 |
| `[25, 40)` | `.orange`（SwiftUI 系统橙） | 较快 |
| `[40, +∞)` | `.red`（SwiftUI 系统红） | 最快 |

**边界是左闭右开**：恰好 8.0 是绿，恰好 25.0 是橙，恰好 40.0 是红。负速度落进 `..<8` → 青（本地记录的 `speedKmh` 非负，接口轨迹的负速度已被 `normalizedSpeed` 变 nil，所以实际到不了）。

图例项样式：`Capsule` 16×4 + 文案，`HStack(spacing: 4)`，整行 `HStack(spacing: 10)` + 尾部 `Spacer(minLength: 0)`，字体 `.caption2.weight(.medium)`，色 `teslaSecondaryText`。

`.cyan` / `.orange` / `.red` 是 SwiftUI 系统色，**明暗两套值不同**，Android 侧要取具体 RGB。iOS 实测取色（在两种外观下各截一次）后写进设计 token，**不要用 Material 的 `Color.Cyan`** —— 差得很明显。

**`bestSpeedTrackPoint`（`:4526-4530`）**

```swift
points
  .filter { ($0.speedKmh ?? 0) > 0.5 }         // ← 严格大于 0.5，nil 视为 0 被滤掉
  .max { ($0.speedKmh ?? 0) < ($1.speedKmh ?? 0) }
```

Swift 的 `max(by:)` 在**并列时保留先遇到的**（只有严格小于才替换）。所以多个点同为最高速时取**最早**那个。Kotlin 的 `maxByOrNull` 同样保留第一个 → 行为一致，但要写测试钉住。

全部速度为 nil 或 ≤ 0.5 → 返回 nil → **不显示最快徽章**。

徽章（`TrackMaxSpeedBadge`，`:4433-4450`）：`speedometer` 图标 + `formatSpeed(speed)`（1 位小数 + `" km/h"`），白字，`.caption2.bold`，`padding(h: 9, v: 6)`，红底 `Capsule`，阴影黑 24% r8 y4。锚点标题 `"最快"`。

#### 2.10 记录保存与关联（`NinebotRecordingView.swift:39-81`、`951-1028`）

结束记录的完整时序：

```
1. 点「结束记录」→ recorder.stop() → 得到 NinebotRecordedRide（含 vehicleSN，:224）
   stop() 返回 nil（未在记录）→ 什么都不做（:46）
2. model.saveRecordedRide(record)          ← 先无条件存一次
3. pendingRecord = record                  ← 弹出 RideAssociationSheet
4. sheet 里选一条行程 → onSave(ride.id)
     savedRecord.vehicleSN = snapshot?.vehicle.sn      ← 冗余，stop() 已经设过
     savedRecord.associatedRideID = rideID
     model.saveRecordedRide(savedRecord)   ← 再存一次（upsert 覆盖）
5. 或点「暂不关联，直接保存」→ onSave(nil)
6. 或点「取消」→ 只 dismiss（函数名叫 pendingDiscard 但什么都不丢，:1025-1027）
```

**「取消」不会丢弃记录** —— 第 2 步已经存了。函数名 `pendingDiscard` 有误导性。Android 侧照抄行为（记录一定保住），但按钮文案改成「稍后再说」更准确（属文案改进，不是行为变更）。

`RideAssociationSheet`（`:951-1028`）：

| 区 | 内容 |
| --- | --- |
| 摘要区 | 距离 `system(size: 34, weight: .bold, design: .rounded)` + 最快速度 + 最大 G |
| 「关联到哪段行程」 | `snapshot?.state.rides` 的**前 20 条**；每行 `startedAt` 或兜底 `"行程 {index+1}"`，副标题 `"{里程} · {时长}"` |
| 空态 | 「当前车辆暂无可关联的接口行程」 |
| 底部 | 「暂不关联，直接保存」（`tray.and.arrow.down.fill`） |
| 导航栏 | 标题「保存记录」，左侧「取消」 |

ViewModel 的两条状态消息（`NinebotViewModel.swift:464`、`:470`）：`"骑行记录已保存"` / `"骑行记录已删除"`。

### 三 · Android 实现要点

#### 3.1 Room 两张表

表结构在 `phase0-foundation-spec.md:176-179` 已定，这里补 Phase 4 需要的约束、索引和 DAO。

```kotlin
@Entity(tableName = "rides")
data class RideEntity(
    @PrimaryKey val id: String,
    val vehicleSn: String?,                 // nullable，对齐 iOS
    val associatedRideId: String?,
    val startedAtEpochMs: Long,             // 非空
    val endedAtEpochMs: Long,               // 非空
    val distanceMeters: Double,             // ← 存重算冻结值
    val maxSpeedKmh: Double,
    val avgSpeedKmh: Double,
    val maxAccelG: Double,
    val pointCount: Int?,                   // ← 必须 nullable，对齐 iOS 的兜底语义
)

@Entity(
    tableName = "ride_points",
    primaryKeys = ["rideId", "seq"],
    foreignKeys = [ForeignKey(
        entity = RideEntity::class, parentColumns = ["id"], childColumns = ["rideId"],
        onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index("rideId")],
)
data class RidePointEntity(
    val rideId: String,
    val seq: Int,                           // 采集顺序，等于 iOS 数组下标
    val timestampEpochMs: Long,
    val lat: Double,
    val lon: Double,
    val coordSys: String,                   // 'WGS84' / 'GCJ02'，见前置二
    val speedKmh: Double,
    val accelG: Double,
    val horizontalAccuracyM: Double?,       // ← nullable，nil 语义是「保留该点」
)
```

四条不能省的：

1. **`ON DELETE CASCADE` 必须配合 `db.setForeignKeyConstraintsEnabled(true)`**（Room 默认开，但如果自定义 `RoomDatabase.Builder` 里动过就要确认）。这一条替代 iOS 的手动 `removeTrackPoints(id:)`（`NinebotSharedStore.swift:284`、`:258`）。
2. **`pointCount` 必须 nullable**（`phase0-foundation-spec.md:144` 已记录）。`trackPointCount = pointCount ?: pointsInMemory.size`，`isTrackLoaded = points.isNotEmpty() || trackPointCount == 0`。
3. **保留上限 120 条要在事务里做**：
   ```kotlin
   @Query("DELETE FROM rides WHERE id NOT IN (SELECT id FROM rides ORDER BY startedAtEpochMs DESC LIMIT 120)")
   suspend fun trimToRetentionLimit()
   ```
   CASCADE 会把对应的点一起删掉。别写成「先查 id 再删」——两次查询之间可能插入新记录。
4. **列表查询绝不 join `ride_points`**：
   ```kotlin
   @Query("SELECT * FROM rides WHERE :sn IS NULL OR vehicleSn IS NULL OR vehicleSn = :sn ORDER BY startedAtEpochMs DESC")
   fun observeSummaries(sn: String?): Flow<List<RideEntity>>
   ```
   注意 `:sn IS NULL OR vehicleSn IS NULL OR vehicleSn = :sn` 逐字对应 `NinebotViewModel.swift:414-419` 的三分支。写成 `vehicleSn = :sn` 会让「无车时录的记录」消失。

**Room 的天然优势要用上**：iOS 的「摘要 / 轨迹拆分 + 旧数据迁移 + 摘要不覆盖磁盘轨迹」这一整套（`NinebotSharedStore.swift:216-335`，约 120 行 + 10 个测试）在 Room 里**自动成立**——两张表本来就是分开的，更新 `rides` 不可能碰到 `ride_points`。所以：

| iOS 的机制 | Android |
| --- | --- |
| `trackSummary()` / `withTrack()` / `isTrackLoaded` | **仍然需要**（是领域层的「摘要 vs 完整」区分，UI 要用） |
| 「摘要不覆盖磁盘轨迹」守卫（`:262-265`） | **不需要**，Room 天然分表 |
| 旧数据内联迁移（`:226-233`） | **不需要**，Android 没有旧数据。但**要在 `MIGRATION` 里留位**，别把这条测试也一起省了：换成「`pointCount IS NULL` 的记录读出来点数正确」 |
| `distanceMeters` 冻结重算值 | **仍然需要**，写入时算好再存 |
| `recordedTrackByteCount()` | 换成 `SELECT COUNT(*) FROM ride_points` 或 `page_count * page_size` 估算，诊断中心用 |

#### 3.2 高德分段折线

iOS 是 n−1 条独立 `MapPolyline`。高德有更好的做法，但**要先实测**：

**方案 A（推荐，先实测）**：单条 `Polyline` + `colorValues`

```kotlin
val options = PolylineOptions()
    .addAll(latLngs)                              // n 个点
    .colorValues(colors)                          // 分段颜色
    .useGradient(false)                           // ← 关掉插值，否则相邻段之间会渐变过渡
    .width(5f.dpToPx())
    .lineCapType(PolylineOptions.LineCapType.LineCapRound)
    .lineJoinType(PolylineOptions.LineJoinType.LineJoinRound)
```

`colorValues` 的长度与 `latLngs` 的对应关系（是 n 还是 n−1、最后一个颜色是否生效）**必须用一条 3 点、颜色 [红, 绿] 的夹具实测一次**再定，高德各版本文档说法不一致。实测方法：3 个点画一条 L 形，看两段颜色是否分别为红和绿。

**方案 B（兜底，直译 iOS）**：n−1 条独立 `Polyline`，每条 2 个点。

方案 B 在 4000 点的轨迹上会创建 3999 个 `Polyline` 对象，高德侧会明显掉帧且内存暴涨。**如果方案 A 实测不通，必须先抽稀再用方案 B**：按 2.4 的算法降到 400 点以内（对应 399 条折线，实测可接受）。

**方案 A 的额外好处**：`useGradient(false)` + `colorValues` 里塞 nil 段的颜色时，可以给「无速度数据」段一个专门的颜色（见 `## 待定` R8），而方案 B 需要额外一层。

`StrokeCap.Round` 对应 `LineCapType.LineCapRound`；iOS 的 `lineJoin: .round` 对应 `LineJoinType.LineJoinRound`。**两条都要设**，默认值不是 round，接缝处会出现尖角。

#### 3.3 回放

即便 R3 定为「只做 iOS 那样的拖拽滑块」，Android 侧也有两个必须处理的差异：

1. **`Slider` 的 `onValueChange` 频率远高于 iOS 的 `Slider`**。每帧都会触发 → 每帧重算 `playbackCoordinate` 并移动 Marker。用 `Marker.setPosition()`（复用同一个 Marker 对象），**不要**每次 `addMarker` / `remove`。
2. **索引映射照抄**：`index = ((count - 1) * progress).roundToInt().coerceIn(0, count - 1)`。注意 Kotlin `roundToInt()` 是 HALF_UP（`.5` 向上），Swift `rounded()` 是 `.toNearestOrAwayFromZero`（也是 `.5` 远离零）→ 正数区间两者一致，不用特殊处理。
3. **时间文案照抄假时间轴**：`formatDuration(durationSeconds * progress)`。如果 R3 定为「做真回放」，就要改成按 `timestamp` 二分查找，那时这条作废。

#### 3.4 详情页的懒加载

```kotlin
// ViewModel
private val trackCache = MutableStateFlow<Map<String, List<TrackPoint>>>(emptyMap())

fun loadTrack(rideId: String) = viewModelScope.launch(Dispatchers.IO) {
    if (trackCache.value.containsKey(rideId)) return@launch
    val points = dao.pointsFor(rideId)          // suspend
    trackCache.update { it + (rideId to points) }
}
```

Composable 侧 `LaunchedEffect(rideId) { vm.loadTrack(rideId) }`。**不要**照抄 iOS 的 `NinebotSharedStore()` 现场构造 + 同步读盘（`NinebotRecordingView.swift:613`、`NinebotDashboardView.swift:4135`），那在 Android 上会直接触发 StrictMode 的磁盘读违规。

iOS 用 `.id(points.count)` 强制重建地图。Compose 对应 `key(points.size) { TrackMapPanel(...) }`——但**更好的做法是不重建**，而是在 `points` 变化时调 `aMap.animateCamera(newLatLngBounds(...))`，避免整个 `MapView` 重新创建（那会闪一下白屏并重新加载瓦片）。这是有意的改进，写进验收。

### 四 · 陷阱

1. **`horizontalAccuracy == nil` 要保留该点**（`(horizontalAccuracy ?? 0) <= 120`，`NinebotModels.swift:945`、`:977`）。Kotlin 侧 `horizontalAccuracyM ?: 0.0 <= 120.0`。写成 `?: Double.MAX_VALUE` 会把所有无精度读数的点丢掉——而这类点在某些设备的定位回调里占比不小。测试 `testTrackCoordinatesKeepPointsWithoutAnAccuracyReading` 专门盯这个。

2. **距离必须重算而不是用存储值**，而且三组窗口（30s/300m 重算、6s/160m 采集、120m 精度）互不相同。用错窗口会让距离偏差 10% 以上。

3. **`trackSummary()` 必须幂等**。不幂等的后果不是「显示错」而是「详情页永久不加载轨迹」：`pointCount` 被清零 → `trackPointCount == 0` → `isTrackLoaded == true` → 跳过加载 → 空地图，而文件还在磁盘上。Room 侧对应的坑是「更新 `rides` 行时把 `pointCount` 写成 `pointsInMemory.size`（摘要形态下是 0）」。**更新摘要字段（如 `associatedRideId`）时必须用 `@Query UPDATE` 只改那一列，不要 `@Update` 整行。**

4. **列表过滤的三分支不能简化**。`vehicleSn IS NULL` 那一支意味着「没绑车时录的记录在任何车下都可见」。省掉它，用户换车后旧记录全部消失。

5. **`records.prefix(5)`**。iOS 只显示 5 条。照抄的话第 6~120 条在记录 Tab 完全不可达。见 R11。

6. **两处渲染不一致**（记录 Tab 单色绿 4pt / 行程 Tab 速度分段 5pt，还有 300 vs 240 的高度）。这是 iOS 的既有状态，不是笔误。见 R7。

7. **速度分段的段速取「终点」速度**（`end.speedKmh ?? start.speedKmh`，`:4517`）。取起点会让整条折线的颜色相对真实速度**滞后一段**，加速时看着尤其明显。

8. **`speedTrackColor(nil)` 与 8~25 km/h 同色**。本地记录的 `speedKmh` 非可选所以不受影响，但**接口轨迹**大量为 nil，会显示成一条「全程都在巡航」的绿线。见 R8。

9. **`bestSpeedTrackPoint` 的阈值是 `> 0.5` 严格大于**，且 nil 视为 0 被滤掉。全程静止或全程无速度 → 没有徽章。

10. **`.cyan` / `.orange` / `.red` / `.yellow` 是 SwiftUI 系统色，明暗两套值不同**。必须在 iOS 真机的浅色和深色下各截图取色，写进 `NinePlusTheme` 的明暗两套 token。Material 的同名色差异明显（尤其 cyan 和 orange）。

11. **`formatRecordingDate` 用设备时区**（见 4.3 陷阱 7）。列表行、详情头卡、删除确认消息、GPX 的 `<name>` 四处都用它。

12. **`Marker` 复用**。回放点、起点、终点三个 Marker 在 `points` 变化时会重建。高德 `Marker` 是重对象，每帧 add/remove 会 GC 抖动。

13. **`RideAssociationSheet` 的「取消」不丢记录**（记录在第 2 步已存）。别把「取消」实现成删除。

14. **`snapshot?.state.rides` 的前 20 条**是关联候选的来源。这是车况快照里携带的行程列表，不是 Phase 3 的行程 Tab 那份分页数据。两者可能不同步，照抄 iOS 用快照那份。

### 五 · 验收标准

**领域层（可纯单测，不需要设备）**

- [ ] 移植 `RecordedRideTests.swift` 的 13 个用例
- [ ] 移植 `ModelCodingTests.swift:513-681`（`RecordedRideTrackSamplingTests`）的 16 个用例
- [ ] 移植 `SharedStoreTrackStorageTests.swift` 的 10 个用例（迁移那条改成「`pointCount IS NULL` 的记录读出点数正确」）
- [ ] `horizontalAccuracy` = `null` / `0` / `120` / `120.1` 四个输入：前三个保留，最后一个丢弃
- [ ] 距离重算：3 点各 100 m → 200 m ± 20；中间点精度 500 → 仍 200 m；间隔 120 s → 0；5 s 内 5.5 km → 0
- [ ] `trackSummary()` 连续调用两次，`pointCount` 与 `distanceMeters` 不变（幂等）
- [ ] `withTrack(emptyList())` 保留原有 `pointCount`
- [ ] 抽稀：5 点 / 120 点 / 300 点 / `maxCount = 0,1,2` 六种输入的结果数与首尾点正确
- [ ] `makeSpeedTrackSegments`：n 点 → n−1 段；段速取终点、终点 nil 时取起点、两者皆 nil 时为 null
- [ ] `speedTrackColor` 边界：7.99 青 / **8.0 绿** / 24.99 绿 / **25.0 橙** / 39.99 橙 / **40.0 红** / null 绿
- [ ] `bestSpeedTrackPoint`：0.5 被滤 / 0.51 保留 / 并列最高速取最早那个 / 全 null 返回 null

**存储**

- [ ] 4000 点的记录：`observeSummaries` 查询**不产生任何 `ride_points` 读取**（用 `Room` 的 query log 或 `SQLiteStatement` 计数验证）
- [ ] 更新一条记录的 `associatedRideId` 后，`ride_points` 行数不变
- [ ] 删除一条记录后 `ride_points` 里对应行归零（CASCADE 生效）
- [ ] 写入第 121 条记录后，`rides` 恰好 120 行，被裁掉那条的 `ride_points` 一并消失
- [ ] 列表过滤：`sn = "A"` 时能同时看到 `vehicleSn = "A"` 与 `vehicleSn = null` 的记录，看不到 `vehicleSn = "B"` 的
- [ ] 排序恒为 `startedAt` 降序

**界面**

- [ ] 列表行 5 个元素（图标、日期、关联态、距离、最快）与 iOS 逐字对齐；关联/未关联两种图标与颜色正确
- [ ] 详情页 8 格指标逐格对齐 2.7 的表，含 `"{n} 个"` 和「未关联」
- [ ] 巨型距离 44sp，`12345.67 km` 不被裁
- [ ] 空轨迹记录：地图显示「这条记录没有轨迹点」覆盖层，不显示回放滑块
- [ ] 单点记录（`count == 1`）：不显示折线、不显示回放滑块
- [ ] 详情页首帧不读 `ride_points`（StrictMode 无磁盘违规告警），轨迹到位后地图**不闪白**（验证没有重建 `MapView`）
- [ ] 速度分段折线：造一条覆盖 4 个速度档的轨迹，4 种颜色都出现，接缝无尖角（`LineJoinRound` 生效）
- [ ] 最快徽章位置与 iOS 同一条轨迹一致（同一个点）
- [ ] 图例 4 项文案与颜色正确，明暗两套下取色与 iOS 截图一致
- [ ] 回放滑块：拖到 0 / 0.5 / 1 三处，播放点索引分别为 0 / round((n−1)/2) / n−1；时间文案为 `0` / 半程 / 全程
- [ ] 回放拖动时 Marker 用 `setPosition` 移动（Profiler 上无对象分配尖峰）
- [ ] 删除确认对话框三段文案逐字对齐；确认后返回列表且该行消失
- [ ] 结束记录 → 关联表单 → 点「取消」→ **记录仍在列表里**（未关联态）
- [ ] 关联表单：无行程时显示「当前车辆暂无可关联的接口行程」；有行程时最多 20 条
- [ ] 关联成功后，从行程 Tab 进入该行程详情，显示「已关联本地轨迹」+ 3 格追加指标 + 速度分段轨迹面板，**且不显示接口轨迹面板**
- [ ] 4000 点轨迹在地图上渲染，滑动缩放帧率 > 50fps（分段方案 A/B 实测结论写进文档）

---

## 4.5 GPX 导出（1 天，风险低）

### 一 · iOS 现状

`RecordedRideExportCard`（`NinebotRecordingView.swift:844-916`），记录详情页的第四块卡片。**导出方式是写系统剪贴板**，没有分享、没有存文件。

界面（`:848-891`）：

| 元素 | 内容 |
| --- | --- |
| 标题 | `轨迹导出` |
| 副标题 | `复制 GPX 后可以导入地图或轨迹工具` |
| 右上计数 | `"{record.trackCoordinates.count} 点"` ← **过滤后**的点数 |
| 按钮 | `Label("复制 GPX", systemImage: "doc.on.doc.fill")`，`.borderedProminent`，`tint = teslaGreen`，高 46，撑满 |
| 禁用条件 | `record.trackCoordinates.isEmpty` |

点击行为（`:867-873`）：

```swift
UIPasteboard.general.string = gpxText
copiedMessage = "已复制 GPX"
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 1_300_000_000)   // 1.3 秒
    copiedMessage = nil
}
```

提示浮层在 `RecordedRideDetailView` 顶部（`:615-628`）：胶囊 + `.regularMaterial` 背景，`.footnote.weight(.semibold)`，`transition(.move(edge: .top).combined(with: .opacity))`，`animation(.easeInOut(duration: 0.18))`。

### 二 · 要移植的逻辑

#### 2.1 GPX 的确切格式（`gpxText`，`:893-915`）

**模板（原文，注意缩进与换行位置）**

```
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="NineBot+" xmlns="http://www.topografix.com/GPX/1/1">
<trk>
<name>{formatRecordingDate(record.startedAt)}</name>
<trkseg>
{trkpt 逐行，用 \n 连接}
</trkseg>
</trk>
</gpx>
```

**单个 trkpt（一行，无缩进，无换行）**

```
<trkpt lat="{%.7f}" lon="{%.7f}"><time>{ISO8601}</time><speed>{%.2f}</speed></trkpt>
```

**逐字段规格**

| 字段 | 值 | 格式 | 来源行 |
| --- | --- | --- | --- |
| 根元素 | `gpx` | `version="1.1"`、`creator="NineBot+"`、`xmlns="http://www.topografix.com/GPX/1/1"` | `:906` |
| `<trk><name>` | `formatRecordingDate(startedAt)` | `MM-dd HH:mm`，**设备时区**，locale `zh_CN` | `:908`、`:1059-1064` |
| 点集 | `record.points.sorted { $0.date < $1.date }` | **不过滤精度、不过滤越界** | `:894` |
| `lat` / `lon` | `recordingMapCoordinate(...)` 的结果 | `String(format: "%.7f", ...)` → 7 位小数 | `:897`、`:899` |
| `<time>` | `ISO8601DateFormatter().string(from: point.date)` | 默认 `withInternetDateTime` + GMT → `2023-11-14T22:13:20Z`（**秒级，无小数，UTC**） | `:895`、`:899` |
| `<speed>` | `point.speedKmh / 3.6` | `String(format: "%.2f", ...)` → **米/秒**，2 位小数 | `:899` |
| `<ele>` | **没有** | | |
| `<extensions>` | **没有** | | |
| **G 值** | **完全不导出** | | |
| `<metadata>` | **没有** | | |
| 转义 | **没有做任何 XML 转义** | | |

**具体示例**（一条两点的记录，起始 2023-11-14 22:13:20 UTC，设备时区 +8）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="NineBot+" xmlns="http://www.topografix.com/GPX/1/1">
<trk>
<name>11-15 06:13</name>
<trkseg>
<trkpt lat="35.5000000" lon="139.5000000"><time>2023-11-14T22:13:20Z</time><speed>6.11</speed></trkpt>
<trkpt lat="35.5004500" lon="139.5000000"><time>2023-11-14T22:13:22Z</time><speed>6.11</speed></trkpt>
</trkseg>
</trk>
</gpx>
```

#### 2.2 三处必须记录的问题

**(a) 坐标是 GCJ-02，不是 WGS-84 —— GPX 规范要求 WGS-84**

`:897` 走 `recordingMapCoordinate` = `NinebotCoordinateTransform.mapKitCoordinate`。所以导出的 GPX 在任何标准工具（Garmin、Strava、GPXSee、QGIS、Google Earth）里打开都会**在中国大陆偏移 350~600 m**。境外记录不受影响（转换在包围盒外是恒等）。

修法很简单（改用 `point.latitude/longitude` 原值，Android 侧还要处理高德定位给的 GCJ-02 → 反解回 WGS-84，见前置二）。但这是**行为差异** → `## 待定` R2。

**(b) 点集与界面显示的点集不一致**

| 位置 | 用的集合 | 过滤 |
| --- | --- | --- |
| 卡片右上「N 点」 | `record.trackCoordinates` | 排序 + 精度 ≤120 + 经纬范围 |
| 按钮禁用判断 | `record.trackCoordinates.isEmpty` | 同上 |
| **实际导出的点** | `record.points` | **只排序，不过滤** |

于是：按钮显示「50 点」，导出的文件里可能有 200 个 `<trkpt>`，其中 150 个是被地图丢掉的低精度/越界点。**极端情况**：所有点精度都 > 120 m → 按钮禁用（`trackCoordinates` 空）→ 用户根本导不出来，尽管 `points` 非空。

**(c) `<speed>` 不是合法的 GPX 1.1 元素**

`<speed>` 是 GPX **1.0** 里 `<trkpt>` 的子元素。GPX 1.1 把它移除了，速度要放进 `<extensions>`（通常是 `gpxtpx:TrackPointExtension`）。所以这份文件声明 `version="1.1"` 却带 1.0 的元素，**严格校验的工具会拒绝**（宽松的会忽略 `<speed>`）。

正确的 1.1 写法（若 R12 定为修）：

```xml
<trkpt lat="35.5000000" lon="139.5000000">
  <time>2023-11-14T22:13:20Z</time>
  <extensions>
    <gpxtpx:TrackPointExtension>
      <gpxtpx:speed>6.11</gpxtpx:speed>
    </gpxtpx:TrackPointExtension>
  </extensions>
</trkpt>
```

需要在根元素加 `xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`。

**G 值放哪** —— GPX 没有加速度的标准字段。三个选项：
1. 自定义命名空间：`xmlns:np="https://github.com/.../nineplus/gpx/v1"` + `<np:accelG>0.12</np:accelG>`，放在 `<extensions>` 里。标准工具会忽略，本 App 可以往回读。
2. 借用 `gpxtpx:TrackPointExtension` 里的 `<gpxtpx:cad>`（踏频）之类语义不符的字段 —— **不要**，会在别的工具里显示成错误的数据。
3. 不导出（iOS 现状）。

见 `## 待定` R13。

### 三 · Android 实现要点

#### 3.1 剪贴板 vs 系统分享（这一项的核心决策）

**Android 上系统分享明显更好**，但这是行为差异 → `## 待定` R1。以下把两条路各自的实现和技术论据都写清，供拍板。

**技术论据（不是审美偏好，是硬约束）**

| # | 约束 | 后果 |
| --- | --- | --- |
| 1 | **剪贴板走 Binder，单次事务上限约 1 MB** | 4000 点 × 约 120 字节 ≈ **480 KB**，加上 Binder 开销已经接近上限。两小时以上的骑行有真实概率抛 `TransactionTooLargeException` 或被静默截断 |
| 2 | **Android 13（= minSdk 33）起，系统对每次复制自动弹一个确认 UI** | iOS 那个「已复制 GPX」浮层会变成**双重提示**，必须去掉 |
| 3 | **GPX 是文件格式，不是文本** | 用户拿到剪贴板里的 XML 之后无处可用——大多数地图/轨迹 App 只接受文件，不接受粘贴 |
| 4 | Android 有现成的 `ACTION_SEND` + `FileProvider` + `ACTION_CREATE_DOCUMENT` | 一次分享可以直接落到「文件」App、微信、邮件、Strava，零额外成本 |

**方案 A：系统分享（推荐）**

```kotlin
// res/xml/file_paths.xml
// <paths><cache-path name="gpx" path="gpx/" /></paths>

suspend fun exportGpx(ride: RecordedRide): Intent = withContext(Dispatchers.IO) {
    val dir = File(context.cacheDir, "gpx").apply { mkdirs() }
    val file = File(dir, "${gpxFileName(ride)}.gpx")
    file.writeText(buildGpx(ride))                        // 纯函数，可单测
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    Intent(Intent.ACTION_SEND).apply {
        type = "application/gpx+xml"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_TITLE, file.name)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }.let { Intent.createChooser(it, context.getString(R.string.track_export_share)) }
}
```

要点：
- `type` 用 `application/gpx+xml`；部分接收方只认 `application/octet-stream` 或 `text/xml`，实测后可能要退到前者。**不要用 `text/plain`**，那会让接收方当纯文本处理。
- 文件名要能看懂：`NineBotPlus-{yyyyMMdd-HHmm}.gpx`（用 `Asia/Shanghai`，见 R10）。iOS 侧没有文件名概念。
- 写 `cacheDir` 而不是 `filesDir`：系统可以自己清理，不需要额外的清理逻辑。但**同一条记录重复导出要覆盖同名文件**，别累积。
- **再提供一个「保存到文件」入口**（`ACTION_CREATE_DOCUMENT`，`rememberLauncherForActivityResult(CreateDocument("application/gpx+xml"))`），这是用户想长期留存时的正路。

**方案 B：照抄剪贴板（若 R1 定为「与 iOS 一致」）**

```kotlin
val clipboard = context.getSystemService(ClipboardManager::class.java)
clipboard.setPrimaryClip(ClipData.newPlainText("GPX", gpxText))
// Android 13+ 不要再弹自己的 "已复制 GPX" —— 系统已经弹了
```

必须加的保护：`gpxText.length > 400_000` 时**不走剪贴板**，退化成分享（否则会崩）。也就是说，方案 B 实际上仍然要实现方案 A 的一半。这是「照抄」比「改好」更贵的少见情况，拍板时请连这条一起看。

#### 3.2 GPX 生成

放 `core/domain/export/GpxWriter.kt`，**纯函数**，输入 `RecordedRide` + `List<TrackPoint>`，输出 `String`。这样能对同一份夹具做两端字节级比对。

```kotlin
fun buildGpx(ride: RecordedRide, points: List<TrackPoint>): String
```

五个必须显式处理的：

1. **时间格式**：`ISO8601DateFormatter()` 的默认输出是 `yyyy-MM-dd'T'HH:mm:ss'Z'`（**UTC、秒级、无小数**）。Kotlin：
   ```kotlin
   private val gpxTime = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)
   ```
   **不要**用 `Instant.toString()`（会输出 `2023-11-14T22:13:20.123Z`，带毫秒）也不要用 `DateTimeFormatter.ISO_INSTANT`（同样带小数秒）。
2. **`%.7f` / `%.2f` 的 locale**。`String.format("%.7f", x)` 在土耳其语等 locale 下会输出 `35,5000000`（逗号小数点）→ **XML 属性值直接废掉**。必须写 `String.format(Locale.ROOT, "%.7f", x)`。这是本项最容易漏、后果最严重的一条。
3. **舍入模式**。`String(format:)` 与 `String.format` 都走 C 的 `printf`（HALF_EVEN 附近的行为由底层实现决定，两端在 `.5` 边界可能差 1 个末位）。7 位小数下差 1e-7 度 ≈ 1 cm，可忽略；`%.2f` 的速度差 0.01 m/s，也可忽略。**不必对齐，但要在两端比对测试里给 1 个末位的容差**，别写成字节完全相同。
4. **XML 转义**。`<name>` 里塞的是 `MM-dd HH:mm`，不含特殊字符，所以 iOS 侧不转义也没出事。Android 侧仍然要转义（用 `TextUtils.htmlEncode` 或手写 5 个实体），因为 R10 一旦把 `<name>` 改成带车名的格式，车名里的 `&` 就会炸掉整个文件。
5. **换行**。iOS 用 `"""` 多行字符串，产出的是 `\n`（LF）。Kotlin 的 `trimIndent()` 同样是 LF。别在 Windows 上生成时被 IDE 换成 CRLF。

#### 3.3 空轨迹与大轨迹

- 空轨迹（按 iOS 是 `trackCoordinates.isEmpty`，见 2.2(b) 的不一致）→ 按钮 `enabled = false`。**Android 侧建议改用「导出用的点集」判空**，即 `points.isEmpty()`，这样修掉 2.2(b) 那个「按钮禁用但有点可导」的洞。属修 bug，记进 R2 一起拍。
- 生成必须在 `Dispatchers.IO`。4000 点的字符串拼接 + 文件写入在主线程会掉帧。用 `StringBuilder`（预估容量 `points.size * 128`），别用 `+=`。

### 四 · 陷阱

1. **`String.format` 不带 `Locale.ROOT` = 在部分 locale 下产出无效 XML**。这一条独占本项一半的风险。写死 `Locale.ROOT`，并在测试里 `Locale.setDefault(Locale("tr", "TR"))` 跑一遍。

2. **`ISO_INSTANT` / `Instant.toString()` 会带毫秒**，与 iOS 输出不同。用显式 pattern。

3. **导出的坐标是 GCJ-02（iOS 现状）**，在标准工具里偏 500 m。别在没定 R2 之前就"顺手修好"——两端不一致会让共享夹具比对全红。

4. **`<speed>` 在 GPX 1.1 里非法**。照抄会得到一个「声明 1.1 但内容是 1.0」的文件。修与不修都要显式决定（R12）。

5. **剪贴板有 1 MB Binder 上限**，长骑行会崩。方案 B 也必须带大小兜底。

6. **Android 13+ 自带复制提示**，别再加自己的浮层。

7. **`FileProvider` 的 authority 必须与 Manifest 里一致**，且 `file_paths.xml` 要覆盖 `cacheDir/gpx/`。漏了就是 `IllegalArgumentException: Failed to find configured root`——接入 FileProvider 最常见的崩溃。

8. **`FLAG_GRANT_READ_URI_PERMISSION` 不能省**，否则接收方拿到 Uri 读不了，表现是"分享成功但文件是空的"。

9. **导出的点集不过滤**（`record.points` 而非 `trackCoordinates`）。所以 GPX 里会有精度 500 m 的野点，导入地图后可能出现"飞到隔壁市再飞回来"的尖刺。iOS 既有行为，是否过滤见 R2。

10. **文件名里不能有 `/` `:` 等字符**。`MM-dd HH:mm` 直接当文件名会在部分文件管理器里出问题。用 `yyyyMMdd-HHmm`。

### 五 · 验收标准

- [ ] `buildGpx` 是纯函数，同一份夹具（20 点，含 1 个越界点、1 个精度 500 的点）两端输出逐行比对，数值差 ≤ 1 个末位
- [ ] 根元素三个属性、`<trk>` / `<name>` / `<trkseg>` 层级与 iOS 逐字相同
- [ ] `lat` / `lon` 恒 7 位小数，`<speed>` 恒 2 位小数且单位是 **m/s**（22 km/h → `6.11`）
- [ ] `<time>` 格式为 `yyyy-MM-ddTHH:mm:ssZ`，UTC，**无毫秒**
- [ ] `Locale.setDefault(Locale("tr","TR"))` 下重跑上面全部断言，输出不变（小数点仍是 `.`）
- [ ] 生成的文件能被 GPXSee 或 Google Earth 打开且不报 schema 错误（若 R12 定为修 `<speed>`，改用 `gpxtpx` 后重验）
- [ ] 空 `points` → 按钮禁用；1 点 → 能导出（1 个 `<trkpt>`，合法 GPX）
- [ ] 4000 点导出：生成 + 写盘在 IO 线程完成，主线程无掉帧；文件大小约 480 KB
- [ ] **分享路径**（若 R1 选方案 A）：`ACTION_SEND` 能被「文件」App、微信、邮件三个接收方接住，落地文件内容与生成内容一致（不是空文件 → 验证 `FLAG_GRANT_READ_URI_PERMISSION`）
- [ ] 同一条记录连续导出 3 次，`cacheDir/gpx/` 里只有 1 个文件（覆盖而非累积）
- [ ] **剪贴板路径**（若 R1 选方案 B）：4000 点不崩（大小兜底生效）；Android 13 上只出现系统那一个提示，没有自己的浮层
- [ ] 坐标系（按 R2 的结论）：境内记录导出后在标准工具里的位置正确（若定为修）或与 iOS 完全一致（若定为不修）—— 两者都要在地图上实测一次，不能只看数值
- [ ] 「保存到文件」（`ACTION_CREATE_DOCUMENT`）能落到用户选定的目录，文件名为 `NineBotPlus-yyyyMMdd-HHmm.gpx`

---

## 待定

以下条目需要人拍板。本文的条目用 **R** 前缀独立编号（R = 轨迹），跨阶段的通用决策在 [pending-decisions.md](./pending-decisions.md) 里用 D 前缀，两套不冲突。定下来之后请合并进去。

---

### R1 · GPX 导出用剪贴板还是系统分享

**现状（本规格的写法）**：两条路都写了实现，默认推荐系统分享（`ACTION_SEND` + `FileProvider`），并额外给一个「保存到文件」（`ACTION_CREATE_DOCUMENT`）。

**iOS 怎么做的**：写系统剪贴板 —— `UIPasteboard.general.string = gpxText`，然后弹一个 1.3 秒的「已复制 GPX」浮层（`NinebotRecordingView.swift:867-873`）。没有分享、没有存文件。

**分歧点**：
- 剪贴板在 Android 上有硬约束：Binder 单次事务约 1 MB，4000 点的 GPX 约 480 KB，两小时以上的骑行有真实崩溃风险；Android 13（= minSdk）起系统自带复制提示，iOS 那个浮层会变成双重提示；而且 GPX 是文件格式，粘贴到大多数地图 App 里没用。
- 但改成分享后两端行为不一致。另外「照抄剪贴板」实际上也**必须**实现一半的分享逻辑（大文件兜底），所以照抄并不更省。

**建议决定时机**：Phase 4 的 4.5 开工前。这条决定完，4.5 的 1 天工期怎么花就定了。

**要问的**：你导出 GPX 之后是拿去做什么？如果是发给自己/存档，分享明显更顺；如果只是偶尔看一眼内容，剪贴板够用。

---

### R2 · GPX 与接口轨迹的坐标系（iOS 现在是错的）

**现状（本规格的写法）**：Android 侧把转换收到「地图」和「GPX」两个出口，各自幂等；GPX 出口转成 WGS-84。即**修掉 iOS 的问题**，但标记为行为差异待确认。

**iOS 怎么做的**：三处都把 WGS-84 → GCJ-02 的转换做在了不该做的地方：
1. **GPX 导出用 GCJ-02 坐标**（`NinebotRecordingView.swift:897` 走 `recordingMapCoordinate`）。GPX 规范要求 WGS-84，所以导出文件在 Garmin / Strava / GPXSee / Google Earth 里打开，在中国大陆偏 350~600 m。
2. **接口轨迹在 JSON 解析层就转**（`NinebotModels.swift:696`），原始坐标丢失，且**无条件转**——连键名明写 `gcj_lat` / `gcj_lng` 的坐标也再转一次，那必然是双重偏移。
3. **导出的点集不过滤**（`record.points`，`:894`），而按钮的启用判断用的是过滤后的 `trackCoordinates`（`:862`、`:882`）。极端情况下按钮禁用但有点可导；正常情况下 GPX 里带着地图已经丢掉的低精度野点。

**分歧点**：这三条都是明确的缺陷，不是设计。但修完之后：同一条记录两端导出的 GPX 内容不同，共享测试夹具的字节比对会全红（需要改成「各端与各自期望值比对」）。第 2 条还依赖前置二的实测结论（九号到底给的是哪个坐标系）。

**建议决定时机**：前置二的实测做完之后、4.1 开工之前。第 1、3 条可以拖到 4.5。

**要问的**：iOS 侧要不要一起修？一起修就没有不一致问题，成本大约半天（GPX 那处改一行，接口轨迹那处要把转换从解析层挪到渲染层）。

---

### R3 · 轨迹回放要不要加自动播放和倍速

**现状（本规格的写法）**：照 iOS 写成「只有一个拖拽滑块」，并把自动播放列为新功能。

**iOS 怎么做的**：`RecordedRideTrackMap`（`NinebotRecordingView.swift:687-819`）只有一个 `Slider(value: $playbackProgress, in: 0...1)`，初值 1（打开就停在终点）。旁边那个 `play.circle.fill` **只是装饰图标，不是按钮，点了没反应**（`:762-764`）。没有播放、没有暂停、没有倍速。时间文案是 `durationSeconds × progress` 线性插值出来的**假时间轴**，与轨迹点的真实 `date` 无关，采样不均匀时（隧道断档）滑块位置和显示时间对不上。

**分歧点**：
- 加自动播放（`LaunchedEffect` + 按真实 `timestamp` 推进 + 1×/2×/4×/8× 倍速 + 相机跟随）大约 +1 天，是本项唯一能明显超过 iOS 的地方，而「回放」这个词本身就暗示会动。
- 但那需要把假时间轴换成按 `timestamp` 二分查找，滑块与时间的对应关系会变（同一个进度值落到不同的点上），两端表现不一致。
- 也可以走中间路线：只把假时间轴换成真时间轴（半天），不加播放。

**建议决定时机**：Phase 4 的 4.4 开工前。

**要问的**：你会真的看回放，还是只是想拖着看某一段的位置？只要后者，现在这个滑块就够了。

---

### R4 · 骑行中要不要屏幕常亮

**现状（本规格的写法）**：4.3 里写了 `view.keepScreenOn = isRecording` 的实现和 `onDispose` 释放，但标记为「若 R4 定为做」。

**iOS 怎么做的**：**没做。** 全仓搜不到 `isIdleTimerDisabled`。骑行中屏幕按系统设置自动锁屏；锁屏后记录靠后台定位继续（`NinebotRideRecorder.swift:195-202`），数据不丢，但看不到仪表了。`RecordingHeader` 的状态文案「正在记录 · 可以锁屏，后台继续」（`:173`）就是在解释这件事。

**分歧点**：把手机架在车上当仪表盘看，屏幕自动黑掉基本等于这个功能不可用；但常亮会明显加快耗电，而且骑行本来就在阳光下、亮度拉满，叠起来掉电很快。第三条路是做成设置项（默认关），成本几乎为零。

**建议决定时机**：Phase 4 的 4.3。实现只有 5 行，主要是要不要默认开。

**要问的**：你骑车时手机是架在车上一直看，还是放兜里？前者需要常亮，后者完全不需要。

---

### R5 · 记录页要不要做横屏专用布局

**现状（本规格的写法）**：不锁方向，用 `WindowSizeClass` 在 `heightSizeClass == Compact`（横屏手机）时把表盘和 2×2 指标格改成左右并排，表盘尺寸按可用高度收缩。

**iOS 怎么做的**：Info.plist 允许竖屏 + 左右横屏（`mini-ninebot/Config/mini-ninebot-Info.plist:61-66`；iPad 四向 `:67-73`），但**没有横屏专用布局**。记录页是一条竖直 `ScrollView`，横屏下 300pt 的表盘加 58pt 的大按钮会把内容挤到必须滚动。

**分歧点**：把手机横着架在车把上是常见做法，横屏布局能让表盘和指标同屏可见；但这是 +0.5 天的额外布局工作，而且要在真机上调。锁竖屏最省事，但 Android 15+ 对大屏设备强制忽略方向限制，锁了也可能不生效，还会在折叠屏上出黑边。

**建议决定时机**：Phase 4 的 4.3，实测一次横屏效果之后。

---

### R6 · 本地记录与接口轨迹能不能叠加显示

**现状（本规格的写法）**：照 iOS 写成互斥（本地记录优先，没有才回退接口轨迹）。

**iOS 怎么做的**：`if / else if` 二选一（`NinebotDashboardView.swift:4101-4106`），而且有一道额外闸门：有本地记录时连接口轨迹的解析都不做（`:4151-4154` 的 `guard localRecord == nil else { return [] }`）。两条轨迹永不同屏。

**分歧点**：叠加显示能直接看出「车机上报的轨迹」和「手机记录的轨迹」差多少，这对判断坐标系问题、采样质量、以及九号的上报可靠性都很有用（对 Phase 4 本身的调试价值尤其大）。但对日常使用是噪音——两条几乎重合的线，用户分不清哪条是哪条。中间路线：默认互斥，在诊断中心（Phase 5 的 5.1）里给一个「叠加显示两种轨迹」的开关。

**建议决定时机**：Phase 4 的 4.4。如果前置二的坐标系实测出了问题，这个功能会立刻变成刚需，那时再定也来得及。

---

### R7 · 同一条本地记录在两个入口的渲染不一致，要不要统一

**现状（本规格的写法）**：照抄 iOS 的两套渲染，并在「前置一」里明确列出差异表。

**iOS 怎么做的**：同一条本地记录，两条路径进去看到的东西不一样：

| | 记录 Tab → 记录详情（`RecordedRideTrackMap`，`NinebotRecordingView.swift:687-819`） | 行程 Tab → 行程详情（`RideTrackMapPanel`，`NinebotDashboardView.swift:4248-4335`） |
| --- | --- | --- |
| 折线 | 单色 `teslaGreen`，4pt | **速度分段着色**，5pt |
| 地图高度 | 300 | 240 |
| 回放滑块 | **有** | 无 |
| 起终点 Marker | 有 | 无 |
| 最快徽章 | 无 | **有** |
| 速度图例 | 无 | **有** |
| 指标 | 详情页另有 8 格 | 面板内 4 格（开始/结束/最快/最大 G） |
| 标题 | 「轨迹」+ 点数 | 「本地轨迹」+ 日期区间 + 距离 |

**分歧点**：这明显是两次独立开发留下的分叉，不是有意设计。统一成一套（速度分段 + 回放滑块 + 起终点 + 徽章 + 图例）体验更好、代码更少，大约 +0.5 天；但两端会不一致，而且「记录 Tab 看简版、行程 Tab 看详版」也可以解释成有意的信息分层。

**建议决定时机**：Phase 4 的 4.4 开工前。这条直接影响要写几个 Composable。

---

### R8 · 没有速度数据的轨迹段用什么颜色

**现状（本规格的写法）**：照 iOS 写成 `teslaGreen`（与 8~25 km/h 的「巡航」档同色）。

**iOS 怎么做的**：`speedTrackColor(nil)` 返回 `Color.teslaGreen`（`NinebotDashboardView.swift:4533`），与 `[8, 25)` 区间完全同色。速度图例（`:4452-4473`）里也没有「无数据」这一档。

**分歧点**：本地记录的 `speedKmh` 是非可选的，所以这条在本地轨迹上无影响。但**接口轨迹的 `speedKmh` 大量为 nil**（九号不一定上报速度，`normalizedSpeed` 还会把超出 0~160 的值变 nil），于是接口轨迹会显示成一条「全程都在 8~25 km/h 巡航」的绿线，与真实速度毫无关系，而用户完全看不出来这是「没数据」。给它一个专门的灰色（或直接虚线）成本几乎为零，但两端不一致。

**建议决定时机**：Phase 4 的 4.1 —— 而且要在 4.1 的服务端实测（3.1 的第 4 项）确认「接口轨迹到底有没有速度字段」之后。如果社区服务端根本不给速度，这条从「小改进」变成「必须改」。

---

### R9 · 环形表要不要加数字刻度标签

**现状（本规格的写法）**：照 iOS 不加标签，只画 33 根刻度线。

**iOS 怎么做的**：量程 132 km/h，33 根刻度（9 主 + 24 次），**没有任何数字标签**（`NinebotRecordingView.swift:200-206`）。

**分歧点**：9 个主刻度落在 **0 / 16.5 / 33 / 49.5 / 66 / 82.5 / 99 / 115.5 / 132 km/h** —— 全是非整数（132 / 8 = 16.5）。不画标签所以看不出来。一旦想加标签，就必须先改量程或刻度数：
- 量程改 120、主刻度 8 段 → 0/15/30/…/120，整数，但**量程会小于采集上限 132**，超过 120 时表针顶死；
- 量程保持 132、主刻度改 6 段 → 0/22/44/66/88/110/132，仍不整；
- 量程改 140、主刻度 7 段 → 0/20/40/…/140，整数且覆盖 132。

这三条都会让表盘与 iOS 视觉不同。

**建议决定时机**：Phase 4 的 4.3。如果不加标签，这条无需决定，直接照抄。

---

### R10 · `formatRecordingDate` 用设备时区还是 `Asia/Shanghai`

**现状（本规格的写法）**：照抄 iOS 用设备时区，并在 4.3 的陷阱 7、4.4 的陷阱 11 里两次标注。

**iOS 怎么做的**：**两套并存，而且不一致**：
- `NinebotFormatting.swift:38-52` 的 `formatDate` / `formatTime` 固定 `Asia/Shanghai` + `zh_CN`（Phase 1 的陷阱 9 已记录这是有意的）。
- `NinebotRecordingView.swift:1059-1064` 的 `formatRecordingDate` 只设了 `locale = zh_CN` 和 `dateFormat = "MM-dd HH:mm"`，**没设 timeZone**，走设备时区。

用到 `formatRecordingDate` 的四处：记录列表行（`:521`）、记录详情头卡（`:648`、`:651`）、删除确认消息（`:636`）、**GPX 的 `<trk><name>`**（`:908`）。而同一条记录在行程 Tab 那边走 `formatDate`（`NinebotDashboardView.swift:4263`），固定北京时间。

**分歧点**：设备时区非 +8 时，同一条记录在记录 Tab 和行程 Tab 显示不同时间。统一到 `Asia/Shanghai` 更自洽（且与 Phase 1 定下的口径一致），但会改变 iOS 现有输出，共享夹具要跟着改。也有一种说法是本地记录本来就该用本地时间（毕竟是「我在哪骑的」），那反而应该把 `formatDate` 改成设备时区 —— 但那会波及全 App。

**建议决定时机**：Phase 4 的 4.4。顺带把 GPX 文件名的时区一起定（R1 的方案 A 需要文件名）。

---

### R11 · 记录列表只显示 5 条，要不要加「全部记录」入口

**现状（本规格的写法）**：照抄 `prefix(5)`，并在 4.4 的陷阱 5 里标注。

**iOS 怎么做的**：存储保留 **120 条**（`NinebotSharedStore.swift:255`），但记录 Tab 的「最近记录」只显示 `records.prefix(5)`（`NinebotRecordingView.swift:497`），**没有「查看全部」入口**。第 6~120 条在记录 Tab 完全不可达，只能通过行程 Tab 的关联关系间接进入（前提是当初关联过）。

**分歧点**：这看起来是「首页只放摘要」的设计，但既然没有别的入口，实际效果是 115 条记录被永久藏起来。加一个「全部记录」页（`LazyColumn` + 按月分组）大约 +0.5 天，Room 的分页查询是现成的。不加就要接受「记录攒到第 6 条以后就看不见了」。

**建议决定时机**：Phase 4 的 4.4。

**要问的**：你会回头翻很久以前的记录吗？如果只关心最近几次，5 条够用。

---

### R12 · `<speed>` 要不要改成合法的 GPX 1.1 写法

**现状（本规格的写法）**：照抄 iOS 的 `<trkpt>...<speed>6.11</speed></trkpt>`，同时给出了 `gpxtpx:TrackPointExtension` 的正确写法供选择。

**iOS 怎么做的**：根元素声明 `version="1.1"`（`NinebotRecordingView.swift:906`），但 `<trkpt>` 里直接放 `<speed>`（`:899`）—— `<speed>` 是 **GPX 1.0** 的元素，1.1 已移除，速度要放进 `<extensions>` 里的 `gpxtpx:TrackPointExtension`。

**分歧点**：宽松的工具会忽略这个 `<speed>`（等于速度数据白导），严格校验 schema 的工具会**直接拒绝整个文件**。改成 `gpxtpx` 写法成本很小（加一个 xmlns + 三层嵌套），但两端输出不同。也可以把 `version` 改成 `1.0` —— 那样文件就合法了，但 1.0 是 2002 年的老规范，`<extensions>` 都没有，以后想加 G 值就没地方放。

**建议决定时机**：Phase 4 的 4.5，和 R1、R13 一起定。

---

### R13 · G 值要不要导出、放哪个字段

**现状（本规格的写法）**：照抄 iOS 不导出，并列出了三个选项。

**iOS 怎么做的**：**完全不导出。** GPX 里只有 `lat` / `lon` / `<time>` / `<speed>`，`accelerationG` 一个字都没写（`NinebotRecordingView.swift:893-915`）。G 值只存在 App 内的记录里。

**分歧点**：G 值是本地记录相对接口轨迹的**唯一独有数据**，不导出等于它永远出不了这个 App。但 GPX 没有加速度的标准字段，只能：
1. **自定义命名空间**：`xmlns:np="…/nineplus/gpx/v1"` + `<extensions><np:accelG>0.12</np:accelG></extensions>`。标准工具忽略，本 App 以后可以往回读（导入功能的伏笔）。推荐这条。
2. **借用现有字段**（如 `gpxtpx:cad` 踏频）—— 不要，会在别的工具里显示成错误数据。
3. 不导出（iOS 现状）。

注意选项 1 依赖 R12 —— 如果 `version` 保持 1.1 就有 `<extensions>` 可用；如果为了让 `<speed>` 合法而退回 1.0，就没有 `<extensions>`，G 值只能不导出。**这两条要一起定。**

**建议决定时机**：Phase 4 的 4.5，与 R12 同时。

---

### R14 · 4.1 的兼容层做到什么程度（取决于服务端实测）

**现状（本规格的写法）**：按「全量移植 450 行、20 个键名、两条平行解析通路」排 2 天工期，并把 6 项服务端实测列为 4.1 的第一个验收项。

**iOS 怎么做的**：`NinebotModels.swift:316-765`，450 行、20 个顶层键名、11 个下钻键、7+12 个经纬键名、两条平行解析通路（带速度的点通路 + 只有坐标的坐标通路）、JSON-in-string 二次解码、4 种字符串分隔格式。33 个测试用例覆盖。这些全是为了兜住**九号官方服务端**返回形状不固定。

**分歧点**：Android 端连的是社区适配器 [`wuchiawuchi/nineplus-ha-server`](https://github.com/wuchiawuchi/nineplus-ha-server)，不是九号官方。三种可能：

| 实测结果 | 兼容层 | 4.1 工期 |
| --- | --- | --- |
| 适配器原样透传九号返回 | 全量移植 450 行 | 2 天（按本规格） |
| 适配器做了字段裁剪/形状归一 | 缩到十几行 + 一条夹具测试 | 0.5 天 |
| 适配器不透出 travel detail 端点 | 整项取消，只剩本地记录 | 0 天，Phase 4 少一项 |

**分歧点的另一半**：即使实测发现适配器已经归一，是否仍然全量移植？理由是「以后换服务端或改直连官方时会立刻用上，而且这 450 行是纯函数、纯单测覆盖，移植成本可预测」；反理由是「为一个可能永远不出现的场景花 1.5 天」。

**建议决定时机**：实测做完立刻定，在 4.1 写代码之前。实测本身约 1 小时（curl 一次 + 存下原始 JSON）。

**要问的**：先把那条 travel detail 的原始返回值贴出来，看一眼就能定。

---

### 附：本阶段涉及的既有待定项

- **D7（卡片阴影精细度）** 覆盖 4.3 环形表的外发光（`teslaGreen` × 0.55 / 0.18，radius 18 / 6）。Compose 没有 outer glow，按 D7 的口径先近似、Phase 5 收尾再调。
- **D8（定位 SDK，已定）** 决定本地记录点的坐标系是 GCJ-02（高德定位）还是 WGS-84（回退到 Google 融合定位）。这直接影响前置二的转换分支，也是 `ride_points` 表必须带 `coord_sys` 列的原因。
- **D4（原始字段调试面板）** 若砍掉，4.1 排查「为什么这条行程没有轨迹」会失去最直接的工具。本规格在 4.1 的陷阱 7 里给了替代方案（把候选键与解析结果写进诊断中心），成本约 2 小时，与 D4 独立。
