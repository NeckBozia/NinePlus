# Phase 2 · 车控完整详细规格

3.8 周，累计到第 9 周。做完这一阶段车控 Tab 与 iOS 功能对等。

---

## 2.3 / 2.4 预测逻辑（先讲，因为 2.2 和界面都依赖它）

这是整个 Phase 2 里最需要精确对齐的部分。核心原则：**服务端预测优先，缺失时走本地兜底**，而社区服务端**不返回预测**，所以本地兜底就是默认路径。

### 判定入口

```
usesServerAlgorithmEstimate  ← 是否采用服务端算法结果
serverPrediction == nil      → 全部走本地兜底
```

### 本地兜底常量（`NinebotModels.swift:1531-1537`）

```
fastChargeUpperBound        = 80.0   快充区上限（百分比）
fastMinutesPerPercent       = 4.0    快充区每 1% 耗时（分钟）
taperMinutesPerPercent      = 7.0    涓流区每 1% 耗时（分钟）
electricityPricePerKWh      = 0.6    电价，用于费用估算
minimumObservedKmPerPercent = 0.2    实测样本下限，低于此视为异常剔除
maximumObservedKmPerPercent = 3.0    实测样本上限，高于此视为异常剔除
rangeRecencyHalfLifeDays    = 14.0   样本时间衰减半衰期
```

### 充电到 80%（`estimatedChargeTo80Minutes`）

```
isCharging != true          → nil
battery == nil              → nil
level = clamp(battery, 0, 100)
level >= 80                 → 0
minutes = (80 - level) × (服务端 fastMinutesPerPercent ?? 4.0)
返回 ceil(minutes / 5) × 5          ← 向上取整到 5 的倍数
```

取整到 5 分钟是为了避免界面上出现「还需 67 分钟」这种伪精度。Android 侧必须保留，否则两端显示会不一致。

### 充满（`estimatedFullChargeMinutes`）

```
isCharging != true                        → nil
服务端 remainingMinutes 存在              → max(值, 0)     ← 优先
battery == nil                            → remainingChargeTime（接口原始值）
level = clamp(battery, 0, 100)
level >= 100                              → 0

fastPercentRemaining  = max(min(80, 100) - min(level, 80), 0)
taperPercentRemaining = max(100 - max(level, 80), 0)
minutes = fastPercentRemaining × 4.0 + taperPercentRemaining × 7.0
```

举例：battery = 50 → 快充区剩 30%、涓流区剩 20% → 30×4 + 20×7 = 260 分钟。

### 充电速度（`estimatedChargingSpeedKmh`，1191-1218 行）

服务端 `estimatedSpeedKmh > 0` 时直接用。否则：

```
前置条件：isCharging == true && battery < 100 && estimatedFullChargeMinutes > 0

kmPerPercent 按优先级取第一个 > 0 的：
  1. observedKmPerBatteryPercent      服务端实测
  2. rangePerBatteryPercent           endurance / battery
  3. localEstimatedMileage / battery

remainingRange = kmPerPercent × (100 - battery)
返回 remainingRange / (minutes / 60)
```

### 每百分比续航（`rangePerBatteryPercent`）

```
采用服务端算法 && 服务端 kmPerPercent > 0  → 服务端值
否则 battery > 0 && endurance 存在        → max(endurance, 0) / battery
否则                                       → nil
```

### 精度与样本（重要：社区服务端下全部退化）

| 属性 | 服务端有预测 | 服务端无预测（当前情况） |
| --- | --- | --- |
| `observedKmPerBatteryPercent` | 服务端 kmPerPercent | **nil** |
| `observedRangeSampleCount` | 服务端 sampleCount | **0** |
| `rangeEstimateAccuracy` | `clamp(accuracyPercent/100, 0, 1)` | **nil** |
| `rangeEstimateAccuracyText` | 百分比 | **"样本不足"** |
| `rangeModelSummaryText` | `x.xx km/% · nn%` | **"等待行程样本"** |
| `rangeEstimateAccuracyDetailText` | 见下 | **"服务端未返回算法指标"** |
| `predictionModelTitle` | "算法预估" | **"官方预估"** |
| `rangeModelInsightText` | 见下 | **"服务端未返回算法预测，当前显示官方预估。"** |

`rangeEstimateAccuracyDetailText` 的完整分支：
- 服务端 sampleCount > 0 且 `accuracySource == "measured"` → `实测预测误差 · {measuredSampleCount ?? sampleCount} 次已验证行程`
- 服务端 sampleCount > 0 其他情况 → `算法服务端 · {sampleCount} 次有效行程`
- 无预测 → `服务端未返回算法指标`
- 有预测但样本为 0 → `服务端样本不足`

`rangeModelInsightText` 的完整分支：
- 采用服务端算法 且 `source == "default"` → `服务端样本不足，当前使用默认算法估算。`
- 采用服务端算法 且 accuracy ≥ **0.82** → `服务端近期样本稳定，估算可信。`
- 采用服务端算法 其他 → `服务端已根据近期行程持续校准。`
- 有 prediction 但不采用 → `服务端未给出可用算法续航，当前显示官方预估。`
- 无 prediction → `服务端未返回算法预测，当前显示官方预估。`

### Android 实现要点

这些计算全部属于领域层，**不要写进 Composable**。放 `core/domain/` 下的纯 Kotlin 函数，输入 `VehicleState`，输出结构化结果：

```kotlin
data class RangeEstimate(
    val kilometers: Double?,
    val kmPerPercent: Double?,
    val source: EstimateSource,      // Server / Official / Unavailable
    val accuracy: Double?,           // 0..1
    val sampleCount: Int,
    val isReady: Boolean,
)
```

**文案不要塞进领域层**。iOS 侧把 `...Text` 属性和算法混在一起（模型层有 91 处中文），这是领域层抽取要解决的问题之一。Android 侧领域层只返回 `source` 枚举和数值，界面层查 `strings.xml`。

### 界面必须体现的状态

因为社区服务端不返回预测，用户看到的默认是「官方预估 + 样本不足」。界面**不能显示成故障或空白**，要明确表达「这是车辆自报的预估值，算法预测未启用」。iOS 侧靠上面那些文案表达，Android 侧要有等价设计。

### 验收

对同一组 `VehicleState` 输入，Android 领域层输出与 iOS 计算结果逐项一致。这正是共享 JSON 测试夹具要覆盖的第一批用例。

---

## 2.2 电池详情（2 天）

### 数据来源

`NinebotVehicleState` 的四个字段，经过归一化：

| 字段 | 归一化规则（`NinebotServerClient.swift:840-857`） |
| --- | --- |
| `batteryVoltage` | >1000 除 1000；>120 除 10；否则原值 |
| `batteryTemperature` | 绝对值 >120 除 10；否则原值 |
| `batteryCycleCount` | 无归一化，取 `bms_cycle`/`bmsCycle`/`cycle`/`cycles` |
| `chargingPower` | 取 `charging_power`/`chargingPower`/`charge_power`/`chargePower` |

取值时会在多个来源里依次查找：`statusObject` → `statusRoot` → `statusBatteryObject` → `batteryPayloadObject` → `batteryRoot` → `batteryListObject` → `batteryMainObject`（见 `vehicleState(status:travel:battery:...)` 的 `batterySources`）。移植时这个查找顺序要保留。

### 健康评分（`health`，1439-1499 行）

**按顺序判定，首个命中即返回**，五个等级：

| 顺序 | 条件 | level | 标题 | 消息 |
| --- | --- | --- | --- | --- |
| 1 | `isFullyCharged`（battery ≥ 100） | good | 已充满 | 电量已满，可以拔掉充电器 |
| 2 | `isCharging == true` | charging | 充电中 | 约 {充满时长} 充满，{时刻} 左右 |
| 3 | `battery < 15` | critical | 低电量 | 当前 {n}%，建议尽快充电 |
| 4 | `isLocked == false` | attention | 未锁车 | 车辆未锁定，请确认停放环境 |
| 5 | `battery < 25` | attention | 电量偏低 | 当前 {n}%，续航约 {enduranceText} |
| 6 | `isLocked == true \|\| isPoweredOn == false` | good | 状态正常 | 车辆已停放，续航约 {enduranceText} |
| 7 | 其他 | unknown | 状态未知 | 部分车况字段暂未返回 |

注意顺序的含义：**充电中优先于低电量**（正在充就不必催），**未锁车优先于电量偏低**（安全优先）。Android 侧照抄这个顺序，别按自己的直觉重排。

### 警告列表（`warningTexts`）

与 health 独立，可同时出现多条：
- `battery < 15` → `电量低于 15%，建议尽快充电`
- 否则 `battery < 25` → `电量偏低，出门前建议确认续航`
- `isPoweredOn == false` → `上电状态为 0，请确认车辆电源`
- `isLocked == false` → `车辆当前未锁车`

### 验收

七个 health 分支各造一组输入验证；电压 60500 / 605 / 60.5 三种输入都得到 60.5。

---

## 2.1 车辆位置地图（5 天，风险中）

### iOS 现状

四处地图，Phase 2 涉及两处：
- 主卡片里的车辆位置（`NinebotDashboardView.swift:1028-1193`）：`Map(position:)` + 车辆 Marker + 我的位置 Marker，含手工算包围盒
- 位置预览小图（`:2247-2320`）

用 iOS 17 的声明式 `Map`，不是 `MKMapView`。跳系统地图用 `MKMapItem(location:address:).openInMaps()`（`:1136`）。

### 坐标系（关键，容易搞错）

`Shared/NinebotCoordinateTransform.swift` 做 WGS-84 → GCJ-02 转换，只在中国大陆经纬范围内生效（`longitude 72.004~137.8347`、`latitude 0.8293~55.8271`）。

**高德底图是 GCJ-02，所以这段代码原样保留**，不要删也不要反向改写。

**但有一处必须实测**：`NinebotDashboardView.swift:1243` 对 `CLLocationManager` 返回的坐标又做了一次转换。iOS 在中国大陆返回的定位可能已经是偏移后的坐标，若是，这里存在双重偏移（约 500 m）。

Android 的 `FusedLocationProviderClient` 返回 **WGS-84**，所以：

| 数据 | Android 处理 |
| --- | --- |
| 服务端返回的车辆坐标 | 转一次 GCJ-02（与 iOS 一致） |
| 本机定位（我的位置） | 转一次 GCJ-02（因为高德底图是 GCJ-02，而 Fused 给的是 WGS-84） |

**两端行为不同，不要照抄 iOS 的那一行**。实现后在地图上同时打车辆点和自己的位置，走到车旁边看两点是否重合来验证。

### 地址反解

iOS 用 MapKit 的 `MKReverseGeocodingRequest`，`preferredLocale = zh_CN`，取地址的优先级是 `fullAddress(includingRegion:singleLine:)` → `address.fullAddress` → `address.shortAddress` → `name`。

Android 用高德的逆地理编码（`GeocodeSearch`）。**注意高德的逆地理输入必须是 GCJ-02**，所以转换后再传（iOS 侧也是这么做的，见 `NinebotViewModel.swift:587`）。

**缓存策略**（`isFreshAddress`，`NinebotViewModel.swift:619-627`）：
```
坐标差 < 0.00001（经纬各自）且 更新时间在 15 分钟内 → 用缓存，不重新请求
```
强制刷新时忽略缓存；若一辆车都没解析成功且没有坐标，抛「车辆暂未返回可解析的坐标」。

### Android 实现要点

- 用 `AndroidView` 包 `MapView`，或高德官方的 Compose 封装（若可用）
- 生命周期要手动转发：`onCreate`/`onResume`/`onPause`/`onDestroy`/`onSaveInstanceState`，漏了会内存泄漏
- 包围盒用 `LatLngBounds.Builder` + `newLatLngBounds(bounds, padding)`，比 iOS 手算 span 简单
- 跳导航用 `amapuri://route/plan?...` scheme，或 `Intent.ACTION_VIEW` 配合 `geo:` URI 让用户选 App

### 陷阱

- 高德 SDK 需要在 `Application` 里设隐私合规同意（`MapsInitializer.updatePrivacyShow/updatePrivacyAgree`），不设直接崩
- Key 要绑定包名 + SHA1，debug 和 release 签名不同，需要注册两个
- 地图 SDK 会拉起独立进程，注意 `Application.onCreate` 里的初始化要判断进程名

### 验收

车辆位置与官方九号 App 显示的位置一致（误差在 GPS 精度内）；地址反解结果与 iOS 版对同一坐标的输出一致。

---

## 2.5 电池历史折线图（3 天）

### iOS 现状

`BatteryHistoryLineChart`（`NinebotDashboardView.swift:820-952`），手写 `Canvas`，**不依赖 Apple Charts**，所以可以近乎逐行直译到 Compose Canvas。

两个函数：
- `drawGrid`（:883）：虚线网格，`dash: [3, 4]`
- `drawLine`（:894）：双系列折线，空值处断线（不插值）

### 数据来源

`NinebotVehicleHistoryPoint`（`NinebotModels.swift:1708` 起），由 `saveDashboard` 时自动追加。

**去重规则**（`shouldAppend`，`NinebotSharedStore.swift` 约 520-545）：
```
与上一点的 battery / endurance / totalMileage / isCharging / isLocked / isPoweredOn 全部相同时：
  间隔 < 60 秒   → 跳过
  间隔 < 300 秒  → 跳过
任一数值不同     → 立即追加
```
上限 **240** 点，超出从头部删除。

### Android 实现

```kotlin
Canvas(modifier = Modifier.fillMaxWidth().height(chartHeight)) {
    // 网格
    val dash = PathEffect.dashPathEffect(floatArrayOf(3f, 4f), 0f)
    // 折线：空值断线 —— 遇到 null 就结束当前 Path，另起一段
}
```

关键是**空值断线**：不要用插值把缺口连起来，那会让图表说谎。iOS 侧是遇到 nil 就 `move(to:)` 另起一段，Compose 侧同理。

### 验收

同一份历史数据在两端渲染出的折线形状一致，缺口位置相同。

---

## 2.6 多车切换（1 天）

`selectVehicle(sn:)`（`NinebotViewModel.swift:367`）：写入 `dashboard.selectedSN` → 存储 → 重载 Widget。

`resolvedSelectedSN` 的兜底（`NinebotServerClient.swift:151-156`）：传入的 SN 在车辆列表里存在则用它，否则取第一辆。

单车用户看不到切换入口，但**代码路径要通**，否则以后加第二辆车会踩坑。

---

## 2.7 原始字段调试面板（2 天）

### iOS 现状

`RawFieldSection` 展示 `rawStatus`/`rawTravel`/`rawBattery` 的键值对，`RawJSONSection` 展示格式化后的完整 JSON，都支持长按复制（`UIPasteboard`）。

`JSONValue.displayText`（`NinebotModels.swift` 约 2039 起）决定每种类型怎么渲染成一行文本。

### 用途

这是排查「为什么这个字段不显示」最快的工具。社区服务端与官方服务端返回的字段可能有差异，这个面板能直接看出来。

**做不做待定，见 [pending-decisions.md](./pending-decisions.md) 的 D4。** 砍掉省 2 天。

### Android 实现

`LazyColumn` 展示键值对 + `ClipboardManager` 复制。JSON 格式化用 `Json { prettyPrint = true }`。

---

## 依赖与顺序

2.3 / 2.4 的领域层要先做，因为 2.2 的健康评分消息里嵌了充电时长文案，主卡片也要显示预测结果。地图（2.1）最独立，可以并行给另一个人。
