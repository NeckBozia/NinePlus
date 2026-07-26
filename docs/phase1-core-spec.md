# Phase 1 · 能用 详细规格

2.2 周，累计到第 5.2 周。做完这三项，App 就能看车况、能控车、通知栏能直接控车 —— 日常可用。

目录约定延续 Phase 0：

```
android/
  core/domain/          车况派生逻辑（1.1）
  feature/dashboard/    主卡片 + 车控面板（1.1 / 1.2）
  feature/tile/         5 个 TileService（1.3）
  core/work/            磁贴用的 Worker（1.3）
```

依赖顺序：1.1 → 1.2 → 1.3。1.3 复用 1.2 的 `VehicleCommandRepository`，不要在磁贴里另写一份网络调用。

> **一处对 iOS 现状的重要修正**（读之前先看）
>
> **`isDangerous` / `confirmationTitle` / `confirmationMessage` 在 iOS 侧是死代码**。全仓只有定义（`NinebotViewModel.swift:68/77/99`），没有任何调用点。`performVehicleAction`（`NinebotDashboardView.swift:192-197`）裸执行，**App 内既无确认弹窗也无生物识别**，安全性完全依赖系统对 App Intents 的 `authenticationPolicy` 拦截。Android 的「滑动确认 + BiometricPrompt」是**新增安全层**，这三个属性正好提供现成文案。
>
> **已定决策**
> - 电量显示照抄 iOS 的线性细长条，不做环形图
> - 寻车铃与磁贴控车均不做生物识别
> - **下拉刷新完整复刻 iOS 手势**（不用 Material3 组件，工期 +2 天）
> - **电量条变化加平滑动画**（iOS 是跳变，这是有意升级）

---

## 1.1 车辆状态主卡片（4 天）

### 一 · iOS 现状

主卡片不是一个 View，而是首屏 `ScrollView` 的前两块 + 若干附属组件。

| 组件 | 行号 | 作用 |
| --- | --- | --- |
| `NinebotDashboardView` | 7-282 | 首屏容器、下拉刷新手势、紧凑头切换 |
| `PullRefreshTimestampCircle` | 346-388 | 下拉时浮出的「更新 HH:mm」圆片 |
| `CompactVehicleHeader` | 1613-1633 | 滚动后吸顶的单行摘要 |
| **`VehicleControlHero`** | **1635-1790** | **主卡片本体** |
| `AlgorithmEstimateTitle` | 1792-1824 | 「算法预估」+ 兜底说明弹窗 |
| `TeslaHeroMetric` | 1826-1848 | 底部三联指标单元 |
| `BatteryProgressBar` | 1850-1867 | 电量条（线性，非环形） |
| `StatusChip` | 1869-1887 | 胶囊状态标签 |
| `VehicleHeroStatusStack` | 1889-1904 | 右上角锁车 chip |
| `PowerOffWarningBanner` | 1906-1935 | 未上电红橙渐变警告条 |
| `ChargingStatusView` | 1937-2018 | 充电中面板（两个循环动画） |
| `ChargingMetricChip` | 2030-2056 | 功率/电压/温度 chip |
| `VehicleHealthPanel` | 2504-2564 | 电池健康卡 |
| `BatteryGauge` | 5407-5427 | 环形电量表（旧版卡片用） |
| `EmptyDashboardView` | 5313-5336 | 无车/未配置空态 |
| `VehicleImage` | 5338-5385 | 车辆图，明暗两套 URL |

数据侧 `Shared/NinebotModels.swift`：`NinebotVehicleState`（1007-1707，27 个可选字段 + 约 60 个 `...Text` 计算属性）、`NinebotVehicleHealth`（152-158、219-224）、`NinebotVehicleSnapshot`（1796-1801）、`NinebotDashboard.primaryVehicle`（1808-1813，`selectedSN` 命中则用它否则取首个）。

**`VehicleControlHero` 实际层次**（1646-1782，间距为源码原值）

```
VStack(spacing: 16)                                   padding(h:22, top:10, bottom:4)
├─ HStack(alignment:.top, spacing:12)
│  ├─ VStack(alignment:.leading, spacing:5)
│  │  ├─ Button → VStack(spacing:5)                    点击切车
│  │  │  ├─ HStack(spacing:6){ 车名 title2/semibold lineLimit2
│  │  │  │                     chevron.down caption/bold（多车才有）}
│  │  │  └─ 车型 footnote/medium secondaryText lineLimit1
│  │  └─ 地址 caption2/medium secondaryText lineLimit1 truncationMode(.tail)
│  │     · 有坐标 → NavigationLink 进地图；无坐标 → 纯文本
│  │     · 地址为空且 showsUpdateTime → "更新 yyyy-MM-dd HH:mm"
│  └─ VehicleHeroStatusStack                           右上角锁车 chip
├─ PowerOffWarningBanner                               仅 isPoweredOn == false
├─ VStack(spacing:6)
│  ├─ localEstimatedMileageText  system(size:44, weight:.semibold, design:.rounded)
│  │                             monospacedDigit lineLimit1 minimumScaleFactor 0.72
│  └─ AlgorithmEstimateTitle     "算法预估" footnote/medium
├─ ZStack(alignment:.bottom) frame(height:196)
│  ├─ RoundedRectangle(18) 黑3.5% height24 blur16 offsetY60     车下投影
│  └─ VehicleImage(size:246) shadow(黑12%, r24, y18)
├─ VStack(spacing:12)
│  ├─ BatteryProgressBar(batteryFraction)   height 5
│  └─ HStack(spacing:10)
│     ├─ TeslaHeroMetric("电量", batteryText, battery.100)
│     ├─ Divider height34
│     ├─ TeslaHeroMetric("官方预估", officialEstimatedMileageText, road.lanes)
│     ├─ Divider height34
│     └─ TeslaHeroMetric("均速", averageSpeedText, speedometer)
└─ ChargingStatusView          仅 isCharging == true && !isFullyCharged，padding(h:-6)
```

主卡片**没有 `.ninePlusCard()`**：直接铺在 `teslaPageBackground` 上，无卡片底、无描边、无阴影。卡片样式从它下面的 `VehicleActionPanel` 才开始。

### 二 · 要移植的逻辑

#### 2.1 每个字段的取值与兜底文案（原文照抄）

| 界面位置 | 属性 | 有值输出 | 兜底文案 |
| --- | --- | --- | --- |
| 三联「电量」 | `batteryText`(1037) | `"{n}%"` | `"--%"` |
| 电量条/环比例 | `batteryFraction`(1042) | `clamp(n/100, 0, 1)` | `0` |
| 巨型主数字 | `localEstimatedMileageText`(1316) | `"{x.x} km"` | `"-- km"` |
| 三联「官方预估」 | `officialEstimatedMileageText`(1079) | `"{x.x} km"` | **`"接口未返回"`** |
| health 消息里的续航 | `enduranceText`(1067) | `"{x} km"` | `"-- km"` |
| 三联「均速」 | `averageSpeedText`(1426) | `"{x.x} km/h"` | `"-- km/h"` |
| 右上 chip | `lockTitle`(1900) | `"已上锁"` / `"已解锁"` | **`"锁车未知"`** |
| 详情行「锁车」 | `lockText`(1089) | `"已锁"` / `"未锁"` | **`"未知"`** |
| 详情行「电源」 | `powerText`(1094) | 见 2.2 | **`"离线"`** |
| 充电 chip | `chargingStateText`(1182) | `"已充满"`/`"充电中"`/`"未充电"` | **`"未知"`** |
| 电池卡副标题 | `chargeSummaryText`(1176) | `"已充满"`/`"充电中 · 约 {X} 充满"`/`"未充电"` | **`"充电未知"`** |
| 充电面板 | `estimatedFullChargeTimeText`(1160) | `durationText` | 非充电`"未充电"`；nil`"计算中"`；0`"已充满"` |
| health 时刻 | `estimatedFullChargeClockText`(1167) | `"HH:mm"` | `"--"`；0 时`"已充满"` |
| 充电 chip 功率 | `chargingPowerText`(1062) | `"{n} W"` | `"接口未返回"` |
| 充电 chip 电压 | `batteryVoltageText`(1047) | `"{x.x} V"` | `"接口未返回"` |
| 充电 chip 温度 | `batteryTemperatureText`(1052) | `"{x.x} °C"` | `"接口未返回"` |
| 循环次数 | `batteryCycleCountText`(1057) | `"{n} 次"` | `"接口未返回"` |
| 地址行 | `locationText`(1226) | 描述原文 | `"未知位置"` |
| 吸顶摘要 | `compactVehicleStatusText`(5160) | 见 2.3 | 落到 `health.title` |

`ChargingStatusView` 的三个 chip 走 `formatNumber`（`:5109`）而不是 state 的 `...Text`，兜底是 `"-- W"`/`"-- V"`/`"--°C"`，而且**值为 nil 时整个 chip 不出现**（`metrics` 用 `compactMap`，`:2005-2017`）。两套兜底并存，不要统一。

空态（`:5313-5336`）：

| `hasConfiguration` | 标题 | 副标题 |
| --- | --- | --- |
| `true` | `"暂无车辆数据"` | `"刷新后会显示九号车辆状态"` |
| `false` | `"未配置服务器"` | `"到“我的”填写服务器地址并绑定账号后即可读取车辆"` |

未上电横幅（`:1912-1914`）：`"车辆未上电"` / `"当前处于未上电状态，请确认车辆状态后再操作"`。

算法兜底弹窗（`:1818-1822`）：`"算法预估"` / `"由于样本量不足，为确保预估准确性已切换为默认算法"` / 按钮 `"知道了"`。触发条件 `isUsingDefaultAlgorithmFallback` = `serverPrediction?.range.isReady == false`（`:1329`）——**三态判断**，`serverPrediction == nil` 时不弹（社区服务端就是这种情况，那个 info 图标默认不出现）。

#### 2.2 `powerText` 优先级（1094-1099）

```
isFullyCharged            → "已充满"     ← battery >= 100，与是否在充电无关
isCharging == true        → "充电中"
isPoweredOn == nil        → "离线"
isPoweredOn == true       → "已上电"
isPoweredOn == false      → "已熄火"
```

两个坑：

1. **`"离线"` 不代表网络离线**，只代表 `isPoweredOn` 字段缺失。别接到网络状态上，否则会出现「有网、有数据、显示离线」。
2. **`已充满` 抢在 `已上电` 前面**。一台电量 100% 且正在骑行的车，「电源」显示 `"已充满"`。iOS 既有行为，照抄。

#### 2.3 `compactVehicleStatusText`（5160-5174）

```
isFullyCharged      → "已充满"
isCharging == true  → "充电中"
isLocked == true    → "已上锁"
isLocked == false   → "未上锁"
其他                → health.title
```

吸顶整行：`"{车名}·{batteryText}·{上面结果}"`，用 `·`（U+00B7）无空格连接，`lineLimit(1) minimumScaleFactor(0.78)`。触发 `scrollOffset > 24`，动画 `easeInOut(0.18)`。

注意锁车文案**三套并存**：chip（已上锁/已解锁）、详情行（已锁/未锁）、吸顶（已上锁/未上锁）。别合并。

#### 2.4 电量配色 —— iOS 有三套阈值，必须显式选

| 出处 | 行号 | 规则 |
| --- | --- | --- |
| `batteryTextColor`（数字用） | 5176-5183 | 已充满→green；充电中→green；nil→primary；**<15 red**；**<50 orange**；else primary |
| `BatteryGauge.gaugeColor`（环形用） | 5421-5426 | nil→**gray**；**<20 red**；**<50 orange**；else green |
| Widget 侧 | 605-608 / 757-763 | 充电中→green；nil→green；**<20 red**；else green（**无 orange 档**） |

Android 规定：**环形用 20/50 那套，数字用 15/50 那套**，Widget（5.3）沿用第三套。写成三个独立函数，不要偷偷统一。

#### 2.5 数字格式化

- `decimalFormatter`（1518-1523）：`max 1 位, min 0 位`。用于 `enduranceText`、`monthMileageText`、`totalMileageText`、`durationText`
- `numberText(_:maximumFractionDigits:)`（1697-1706）：用于 `localEstimatedMileageText`(1)、`officialEstimatedMileageText`(1)、`batteryVoltageText`(1)、`batteryTemperatureText`(1)、`chargingPowerText`(0)、`averageSpeedText`(1)、`rangePerBatteryPercentText`(2)

`durationText`（1689-1695）：`minutes >= 60 → "{分/60 保留1位} 小时"`，否则 `"{分 保留1位} 分钟"`。例：260 → `"4.3 小时"`；90 → `"1.5 小时"`。

Kotlin 对齐（两个必须显式设的项）：

```kotlin
private fun numberText(value: Double, maxFrac: Int, minFrac: Int = 0): String =
    DecimalFormat().apply {
        maximumFractionDigits = maxFrac
        minimumFractionDigits = minFrac
        isGroupingUsed = false                     // DecimalFormat 默认开，会出现 12,345.6
        roundingMode = RoundingMode.HALF_EVEN      // NumberFormatter 的默认；"%.1f" 是 HALF_UP
    }.format(value)
```

`"%.1f".format(x)` 在 x.x5 边界会和 iOS 差 0.1；千位分隔符在总里程上一眼可见。

#### 2.6 下拉刷新手势参数（217-249、346-388）

```
DragGesture(minimumDistance: 12, coordinateSpace: .global)
起手：scrollOffset <= 1 且 translation.height > 0，只在起手那刻记住
拖动：pullDistance = min(translation.height, 110)；> 16 显示时间圆片
松手：translation.height > 86 → 触发刷新；否则 220ms 收起
圆片：62×62，scale = 0.86 + min(1, pullDistance/84) × 0.14
      opacity = min(1, max(0.35, pullDistance/44))
收起延迟：正常 900ms / 刷新完成 450ms / 手势非法 200ms
```

**已定：完整复刻这套手势，不用 Material3 `PullToRefreshBox`。** 工期 +2 天。

实现路径：自定义 `nestedScroll` 连接器接管顶部过冲，把上面的阈值和曲线逐条搬过来。需要额外处理的边界：

- 嵌套滚动的消费顺序（内层 LazyColumn 到顶后才把剩余位移交给刷新手势）
- 快速甩动时不误触发（对应 iOS 的「起手那一刻记住是否在顶部」）
- 圆片的缩放与透明度用同样的两条线性映射，不要换成 spring
- 三档收起延迟（900 / 450 / 200ms）照抄

### 三 · Android 实现要点

#### 3.1 状态分层

```kotlin
// core/domain/VehicleDisplay.kt —— 纯 Kotlin，无 Android 依赖，可单测
data class VehicleCardModel(
    val name: String,
    val model: String,
    val imageUrl: String?,
    val batteryPercent: Int?,          // null = 接口未返回
    val batteryFraction: Float,        // 0f..1f，null → 0f
    val rangeText: TextValue,          // sealed: Value(str) / Missing(reason)
    val powerStatus: PowerStatus,      // FullyCharged/Charging/Offline/PoweredOn/PoweredOff
    val lockStatus: LockStatus,        // Locked/Unlocked/Unknown
    val isCharging: Boolean,
    val isFullyCharged: Boolean,
    val showsPowerOffBanner: Boolean,
    val warnings: List<WarningKind>,
    val health: HealthLevel,
    val updatedAt: Instant,
)
```

枚举出界面、文案查 `strings.xml`。优先级判定放领域层，`when (powerStatus)` 到界面层再映射成字符串。

#### 3.2 电量条（照抄 iOS，不做环形图）

iOS 的 `BatteryProgressBar` 完整实现只有 15 行（`NinebotDashboardView.swift:1850-1867`）：

```swift
GeometryReader { proxy in
    ZStack(alignment: .leading) {
        Capsule().fill(Color.teslaControlBackground)             // 轨道
        Capsule().fill(Color.teslaGreen)                          // 进度
            .frame(width: max(proxy.size.width * value, 8))       // ← 最小 8pt
    }
}
.frame(height: 5)
.accessibilityLabel("电量进度 \(Int(value * 100))%")
```

| 参数 | 值 |
| --- | --- |
| 高度 | 5 |
| 形状 | Capsule（全圆角） |
| 轨道色 | `teslaControlBackground` |
| 进度色 | **恒为 `teslaGreen`** |
| 最小进度宽 | **8**（0% 时也显示一个 8pt 的绿点，不是完全空） |
| 无障碍 | `"电量进度 {n}%"` |
| 动画 | **无** |

**注意进度色不随电量分档**。这一条修正了本文 2.4 节的说法：细长条恒绿，2.4 里那三套配色阈值只用于**电量数字文本**（`batteryTextColor`，15/50 两档）；`gaugeColor`（20/50 三档）属于旧版 `BatteryGauge` 环形表，既然不做环形图，这一套**不需要移植**。Widget 侧那套（5.3）仍然独立。

```kotlin
@Composable
fun BatteryProgressBar(fraction: Float, modifier: Modifier = Modifier) {
    val pct = (fraction * 100).roundToInt()
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(5.dp)
            .clip(CircleShape)
            .background(NinePlusTheme.colors.controlBackground)
            .semantics { contentDescription = "电量进度 $pct%" },
    ) {
        val minWidth = 8.dp
        val target = maxWidth * fraction.coerceIn(0f, 1f)
        Box(
            Modifier
                .width(if (target < minWidth) minWidth else target)
                .fillMaxHeight()
                .clip(CircleShape)
                .background(NinePlusTheme.colors.green),
        )
    }
}
```

**动画对照**：

| 效果 | iOS | Compose |
| --- | --- | --- |
| 电量变化 | **无动画**，width 直接跳变 | **已定：加平滑动画** `tween(600, FastOutSlowInEasing)`。有意升级，主要为了解决冷启动时从缓存旧值跳到新值那一下的突兀 |
| 充电闪电浮动 | `offset(y: ±1)`，`easeInOut(0.8).repeatForever(autoreverses:true)`（`:1951`） | `rememberInfiniteTransition` + `tween(800)`, `RepeatMode.Reverse` |
| 充电流光 | 宽 42%、高 2pt，`LinearGradient(clear→green90%→clear)`，offset `-0.42w → +w`，`linear(1.35).repeatForever(autoreverses:false)`（`:1984-1997`） | `tween(1350, LinearEasing)`, `RepeatMode.Restart`, `graphicsLayer{translationX}`，父容器 `clipToBounds()` |

`clipToBounds()` 必须加在**流光的父容器**上，加在流光自己身上无效。

后两个循环动画是装饰性的，两端参数照抄即可，没有争议。有争议的只有电量变化和下拉刷新，见下节。

#### 3.3 主卡片骨架

```kotlin
Column(
    verticalArrangement = Arrangement.spacedBy(16.dp),
    modifier = Modifier.padding(start = 22.dp, end = 22.dp, top = 10.dp, bottom = 4.dp),
    // 不套 ninePlusCard()，直接铺在 pageBackground 上
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { /* 车名/车型/地址 + 锁车 chip */ }
    if (model.showsPowerOffBanner) PowerOffWarningBanner()
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { /* 44sp 巨型续航 + 算法预估 */ }
    Box(Modifier.fillMaxWidth().height(196.dp), contentAlignment = Alignment.BottomCenter) { /* 车图 246dp */ }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        BatteryRing(...)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { /* 三联 + 两条 34dp 分隔 */ }
    }
    if (model.isCharging && !model.isFullyCharged) ChargingStatusPanel(...)
}
```

`minimumScaleFactor` 无直接对应。巨型续航（0.72）、三联指标值（0.72）、吸顶行（0.78）都需处理：用 `BasicText` + `autoSize = TextAutoSize.StepBased(minFontSize = 32.sp, maxFontSize = 44.sp)`（Compose 1.8+），或退化成 `maxLines = 1, overflow = Ellipsis`。`"12345.6 km"` 是真会出现的，别假设短。

车图：Coil `AsyncImage`，明暗两套 URL 由 `imageURLString(prefersDarkImage:)`（`NinebotModels.swift:95`）决定，读 `isSystemInDarkTheme()`。失败兜底图标尺寸 `size × 0.38`。

### 四 · 陷阱

1. **`updatedAt` 在空 dashboard 上是 `Date.distantPast`**（`:1815`），格式化出来是 `"0001-01-01 00:00"`。iOS 靠空态视图规避。Android 的更新时间必须走 `if (vehicles.isNotEmpty())`。

2. **`isLocked`/`isPoweredOn`/`isCharging` 是三态 `Boolean?`**，全仓有 4 处语义不同：
   - `powerText`：nil → `"离线"`
   - `VehicleHeroStatusStack`：nil → `"锁车未知"`
   - `VehicleActionPanel.isLocked`（`:3546`）：`isLocked != false` → **nil 视为已锁**
   - `health` 第 4 条：只在 `== false` 时报未锁车，nil 不报

   Kotlin 用 `Boolean?` 原样保留，**禁止在映射层写 `?: false`**。一个 `?: false` 会让「锁车未知」的车显示成「已解锁」并触发未锁车告警。

3. **`officialEstimatedMileageText` 兜底是 `"接口未返回"` 不是 `"-- km"`**。三联指标第二格可能显示 5 个中文字，把单元挤变形。iOS 靠 `minimumScaleFactor(0.72)` 顶住。必须实测 360dp 宽屏 + 最大字号。

4. `battery` 可能 > 100（接口偶发）。`batteryFraction` 有 clamp，`batteryText` 没有，`"105%"` 原样显示。照抄，别自作主张。

5. **`localEstimatedMileage` 不是「本地算的」**（`:1308-1314`）：优先 `serverPrediction?.range.estimatedRange`，缺失才回退官方预估。社区服务端不返回预测，所以那个 44sp 巨型数字实际显示**官方预估值**，而标签写着「算法预估」。iOS 既有文案缺陷，照抄行为但可修文案 —— 修的话在 plan 里记一笔。

6. `estimatedMileageSourceTitle` 恒返回 `"官方预估"`（`:1321`，硬编码），`predictionModelTitle`（`:1325`）才随状态变。三联第二格用前者。

7. `warningTexts` 前两条是 `if/else if`（`:1504-1508`），电量 <15 时**只出**「电量低于 15%」。后两条独立 `if` 可叠加，最多 3 条。

8. `ChargingStatusView` 挂了 `.padding(.horizontal, -6)`（`:1776`），`VehicleActionPanel` 充电时有 `.padding(.top, -8)`（`:52`）。Compose 无负 padding，用 `Modifier.layout {}` 或把父 padding 降到 16 再给其他子项补 6。

9. 时区**恒定 `Asia/Shanghai`**、locale `zh_CN`（`:5024-5025`、`:1525-1531`），不是设备时区。设备设成美国时区时两端必须仍显示同一时刻。

### 五 · 验收标准

- [ ] 造 12 组输入（battery = null/0/8/20/49/86/100/105；isPoweredOn/isLocked/isCharging 各 null/true/false 组合），每个字段输出字符串与 iOS 同输入**逐字符相同**。用共享 JSON 夹具跑单测，不靠肉眼
- [ ] `powerText` 五分支各命中一次，含「100% 且 isPoweredOn == true 显示已充满」
- [ ] `--%` / `-- km` / `-- km/h` / `接口未返回` / `未知` / `离线` / `未知位置` / `锁车未知` 八种兜底各出现一次并截图归档
- [ ] 环形：0% 显示 4% 最小弧不空白；100% 首尾无缝无重叠；19/20、49/50 边界配色正确；充电中恒绿
- [ ] 20%→80% 有 600ms 补间不跳变；连续刷新不抖动
- [ ] 充电中闪电 800ms 往复、流光 1350ms 单向，流光不溢出圆角
- [ ] 空 dashboard 不显示 `0001-01-01`，两种 `hasConfiguration` 分支文案正确
- [ ] 设备时区改 UTC-8，更新时间仍显示北京时间
- [ ] 系统最大字号 + 360dp 宽：三联不换行不重叠，巨型数字不被裁
- [ ] 下拉刷新圆片显示上次 `updatedAt` 的 HH:mm，刷新中变「更新中」

---

## 1.2 四个控制指令 + 滑动确认 + 生物识别（4 天）

### 一 · iOS 现状

| 组件 | 位置 |
| --- | --- |
| `NinebotVehicleAction` | `NinebotViewModel.swift:24-107` |
| `perform(_:sn:)` | `NinebotViewModel.swift:374-404` |
| `runLoadingOperation` | `NinebotViewModel.swift:648-680` |
| `performVehicleAction` | `NinebotDashboardView.swift:192-197` |
| `VehicleActionPanel` | `NinebotDashboardView.swift:3488-3553` |
| `VehicleControlLoadingStrip` | `NinebotDashboardView.swift:3555-3584` |
| `CommandPadButton` | `NinebotDashboardView.swift:3586-3627` |
| **`SlideActionControl`** | **`NinebotDashboardView.swift:3629-3751`** |

**`VehicleActionPanel` 层次**（3494-3544）：

```
VStack(spacing:12)                              padding(12)
├─ VehicleControlLoadingStrip                   仅 activeAction != nil
└─ HStack(spacing:12)
   ├─ CommandPadButton("寻车", bell.fill)                       70×64
   ├─ SlideActionControl  .id(isLocked ? "unlock":"lock")       撑满，height 64
   └─ CommandPadButton("座桶", shippingbox.fill)                70×64
teslaCardBackground，圆角 24，1pt hairline，阴影 黑5% r14 y8，外层 padding(h:16)
```

**上电/熄火不是两个按钮，是同一控件的两个状态**（3512-3522、3546-3552）：

```
isLocked = (state.isLocked != false)          ← nil 视为已锁
isLocked  → title "滑动开锁"  completedTitle "正在开锁"  icon lock.fill
!isLocked → title "滑动关锁"  completedTitle "正在关锁"  icon lock.open.fill
color 恒为 teslaGreen
.id(isLocked ? "unlock" : "lock")             ← 锁态翻转时重建 View，清空全部 @State
```

图标看似反了（已锁时显示 `lock.fill`）—— 它表达**当前状态**而非动作结果。照抄。

### 二 · 要移植的逻辑

#### 2.1 全部文案（原文照抄）

| case | `title` | `resultTitle` | `loadingTitle` | `confirmationTitle` | `confirmationMessage` | `isDangerous` |
| --- | --- | --- | --- | --- | --- | --- |
| `bell` | 寻车铃 | 寻车铃已发送 | 正在寻车鸣笛 | 发送寻车铃？ | 车辆会发出提示音。 | **false** |
| `openBucket` | 开座桶 | 开座桶指令已发送 | 正在打开座桶 | 打开座桶？ | 座桶会被打开，请确认车辆在你身边。 | **true** |
| `engineStart` | 上电 | 上电指令已发送 | 正在开锁 | 车辆上电？ | 车辆会进入上电/解锁状态，请确认车辆在你身边。 | **true** |
| `engineStop` | 熄火 | 熄火指令已发送 | 正在关锁 | 车辆熄火？ | 车辆会进入熄火/锁车状态，请确认不会影响当前骑行。 | **true** |

`subtitle`：让车辆发出提示音 / 打开座桶 / 车辆进入可骑行状态 / 关闭电源并锁车。

注意 `title` 与 `loadingTitle` 用词不一致：`engineStart` 的 title 是「上电」但 loading 是「正在开锁」。`title` 写进诊断中心的 `operation`（`:347`），`loadingTitle` 是加载条文案。两个都要。

Widget 侧还有第三套（`NinebotWidgetControlIntents.swift:11-19`）：寻车/开座桶/**开锁**/**关锁**。

#### 2.2 鉴权矩阵

| 指令 | `isDangerous` | App Intent | Control Widget | **Android 应用内** | **Android 磁贴** |
| --- | --- | --- | --- | --- | --- |
| 寻车铃 | false | `.requiresAuthentication`(56) | **无**(32-41) | 直接点，**不鉴权** | 不鉴权 |
| 开座桶 | **true** | ✓(68) | ✓(47) | 点击 → BiometricPrompt | `unlockAndRun` |
| 上电 | **true** | ✓(80) | ✓(59) | 滑动 → BiometricPrompt | `unlockAndRun` |
| 熄火 | **true** | ✓(92) | ✓(71) | 滑动 → BiometricPrompt | `unlockAndRun` |

**寻车铃在两处策略不一致**：Shortcuts 要鉴权，Control Widget 不要，且 `isDangerous == false`。三票对一票，**Android 以 `isDangerous` 为准，寻车铃不鉴权**（找车是最高频场景，加鉴权会难用）。

`openBucket` 是「点按 + 生物识别」，不走滑动，与 iOS 控件形态一致。

#### 2.3 `SlideActionControl` 完整状态机

**几何**（3705-3706、3712、3690）：

```
height = 64，thumbSize = 52，thumb padding = 5
maxOffset = max(width - thumbSize - 10, 0) = width - 62
commit 阈值 = maxOffset × 0.72
```

实测：外层 padding 16 + 面板 padding 12 + 两个 70pt 按钮 + 两个 12pt 间距 → 滑轨宽 = 屏宽 − 220。393dp 屏 → 173dp，maxOffset = 111dp，**阈值 ≈ 80dp**。

**状态机**：

```
[Idle] dragOffset=0, isDragging=false, isCommitted=false
       显示 title、双 chevron、渐变填充 opacity 0

├─ onChanged（守卫 !isDisabled && !isCommitted）
│    isDragging = true
│    dragOffset = clamp(translation.width, 0, maxOffset)
│    → [Dragging] 渐变填充 opacity 1（瞬变无动画），宽度 max(52+offset, 52)
│
└─ onEnded（同守卫）
     ├─ dragOffset >= maxOffset × 0.72
     │    isCommitted = true                    ← 立即，无动画。文案瞬变 completedTitle，chevron 消失
     │    animate spring(response:0.28, damping:0.86) → dragOffset = maxOffset
     │    onCommit()                            ← 同步触发，不等动画
     │    asyncAfter(+0.45s) {
     │        animate spring(response:0.32, damping:0.86) → 全部归零复位
     │    }                                     ← 与网络请求完全无关的硬编码定时器
     └─ 否则
          animate spring(response:0.32, damping:0.86) → dragOffset = 0
```

`[Loading]` 态（`isLoading && !isCommitted`）：滑块内换白色 small ProgressView，标签是 `completedTitle`，无 chevron。因父级传 `isDisabled = isLoading`，`isDisabled && !isLoading` 为 false，所以**不降透明度**。只有「别的操作在跑」时才 `opacity 0.55`（3749）。

**视觉**：

| 层 | 规格 | 行号 |
| --- | --- | --- |
| 轨道 | Capsule fill `controlBackground` + stroke `hairline` 1pt | 3714-3720 |
| 渐变填充 | `LinearGradient([color×0.42, color×0.16], .leading→.trailing)` | 3722-3732 |
| 标签行 | `Spacer(minLength:60)` → `HStack(spacing:8)`.offset(x:10) → `Spacer(minLength:12)` | 3734-3757 |
| 文字 | `subheadline/semibold` `lineLimit(1)` `minimumScaleFactor(0.76)` | 3739-3741 |
| 双箭头 | `HStack(spacing:-2){chevron.right ×2}` `caption/bold` | 3747-3752 |
| 滑块 | Circle fill `teslaActionThumb`，`shadow(黑14%, r8, y4)`，图标 `title3/semibold` 白 | 3763-3775 |

**弹簧参数换算（关键）**

SwiftUI 的 `.spring(response:dampingFraction:)` 在单位质量下：

```
stiffness k = (2π / response)²
damping   c = 4π × dampingFraction / response
```

Compose 的 `spring(dampingRatio, stiffness)` 同样按质量 1 建模。所以：

> **`dampingRatio` = `dampingFraction`（同一个量，直接抄）**
> **`stiffness` = `(2π / response)²`**

| iOS | response | dampingFraction | Compose stiffness | dampingRatio | 沉降(1%) |
| --- | --- | --- | --- | --- | --- |
| commit 前推 | 0.28 | 0.86 | **503.6f** | **0.86f** | ≈240ms |
| 回弹/复位 | 0.32 | 0.86 | **385.5f** | **0.86f** | ≈275ms |

校验：`c = 4π×0.86/0.28 = 38.60`；Compose `c = 2ζ√k = 2×0.86×22.44 = 38.60`。一致。

不要用 `StiffnessMediumLow`(400f) 或 `StiffnessMedium`(1500f) 近似，前者慢 12%、后者快到不像同一控件。

```kotlin
private val CommitSpring  = spring<Float>(dampingRatio = 0.86f, stiffness = 503.6f, visibilityThreshold = 0.5f)
private val ReleaseSpring = spring<Float>(dampingRatio = 0.86f, stiffness = 385.5f, visibilityThreshold = 0.5f)
```

`visibilityThreshold` 必须给。默认 `0.01f` 对像素位移意味着尾巴多跑十几毫秒；`0.5f`（半像素）感知等价且提前收敛。

#### 2.4 执行链路（374-404）

```
1. activeVehicleAction = action; activeVehicleActionSN = sn    （defer 清空）
2. runLoadingOperation(message: loadingTitle) {
     POST 端点（返回值丢弃）
     statusMessage = resultTitle                              ← 在刷新之前就置成功
     dashboard = fetchDashboard(selectedSN: sn)                ← 1 + N 个请求
     saveDashboard → cacheVehicleImages → refreshAddresses
     WidgetCenter.reloadAllTimelines()
   }
3. 兜底：成功 → 记 RefreshEvent(operation: loadingTitle, success:true)
         失败 → errorMessage = ...; statusMessage = nil        ← 抹掉第 2 步的成功
```

界面侧只在 `activeVehicleActionSN == sn` 时才认（`:187-190`），多车不串台。

**端点**（`NinebotServerClient.swift:46-60`，均为无 body POST）：

| 指令 | 路径 |
| --- | --- |
| `bell` | `POST /vehicles/{sn}/bell` |
| `openBucket` | `POST /vehicles/{sn}/`**`buck`** |
| `engineStart` | `POST /vehicles/{sn}/engine/start` |
| `engineStop` | `POST /vehicles/{sn}/engine/stop` |

是 **`buck`** 不是 `bucket`。写错服务端返回 404，界面显示 `"HTTP 404"`。

### 三 · Android 实现要点

#### 3.1 滑动控件

```kotlin
@Composable
fun SlideActionControl(
    title: String, completedTitle: String, icon: ImageVector, color: Color,
    isLoading: Boolean, isDisabled: Boolean, onCommit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val offset = remember { Animatable(0f) }        // px
    var isDragging by remember { mutableStateOf(false) }
    var isCommitted by remember { mutableStateOf(false) }
    var maxOffset by remember { mutableFloatStateOf(0f) }
    val isBusy = isLoading || isCommitted

    BoxWithConstraints(
        modifier.height(64.dp)
            .alpha(if (isDisabled && !isLoading) 0.55f else 1f)
            .semantics {                                   // iOS 侧无障碍缺失，这里补
                role = Role.Button
                contentDescription = title
                onClick(label = "确认执行") { onCommit(); true }
            },
    ) {
        maxOffset = (constraints.maxWidth - thumbPx - tenDp).coerceAtLeast(0f)
        // 轨道 / 渐变填充（瞬变，不加 animateFloatAsState）/ 标签行
        Box(
            Modifier.offset { IntOffset(offset.value.roundToInt(), 0) }
                .padding(5.dp).size(52.dp)
                .draggable(
                    orientation = Orientation.Horizontal,
                    enabled = !isDisabled && !isCommitted,
                    state = rememberDraggableState { delta ->
                        isDragging = true
                        scope.launch { offset.snapTo((offset.value + delta).coerceIn(0f, maxOffset)) }
                    },
                    onDragStopped = {
                        if (offset.value >= maxOffset * 0.72f) {
                            isCommitted = true                          // 立即，不等动画
                            haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                            scope.launch { offset.animateTo(maxOffset, CommitSpring) }
                            onCommit()                                  // 同步触发
                            scope.launch {
                                delay(450)                              // 与网络无关
                                offset.animateTo(0f, ReleaseSpring)
                                isCommitted = false; isDragging = false
                            }
                        } else {
                            scope.launch { offset.animateTo(0f, ReleaseSpring) }
                            isDragging = false
                        }
                    },
                ),
        ) { /* ProgressView 或图标，白色 */ }
    }
}
```

调用侧对齐 `.id()`：

```kotlin
key(isLocked) {                     // 锁态翻转时重建，清空 offset/isCommitted/isDragging
    SlideActionControl(
        title = if (isLocked) "滑动开锁" else "滑动关锁",
        completedTitle = if (isLocked) "正在开锁" else "正在关锁",
        ...
    )
}
```

`key()` 不能省。缺了它，指令成功后锁态翻转、文案变了，但滑块可能还停在右端或残留 `isCommitted`。

`Animatable` 的 `animateTo` 会被下一个 `animateTo`/`snapTo` 抢占（互斥），正好对上 SwiftUI 的行为 —— 用户在回弹途中重新抓住滑块时 `snapTo` 打断回弹。别自己写 `Job.cancel()`。

#### 3.2 BiometricPrompt

```kotlin
// MainActivity 必须是 FragmentActivity。androidx.biometric 的构造要 FragmentActivity，
// 纯 ComponentActivity 不够。
val info = BiometricPrompt.PromptInfo.Builder()
    .setTitle(action.confirmationTitle)        // "车辆上电？"
    .setSubtitle(action.confirmationMessage)   // "车辆会进入上电/解锁状态，请确认车辆在你身边。"
    .setAllowedAuthenticators(BIOMETRIC_STRONG or BIOMETRIC_WEAK or DEVICE_CREDENTIAL)
    .setConfirmationRequired(true)             // 人脸这类被动模态要再点一下确认
    // 允许 DEVICE_CREDENTIAL 时禁止 setNegativeButtonText()，会抛 IllegalArgumentException
    .build()
```

`onAuthenticationError` 里的取消（`ERROR_USER_CANCELED` / `ERROR_NEGATIVE_BUTTON`）静默返回。`onAuthenticationFailed` **不要**当取消，系统会让用户重试。

无生物识别硬件或未录入时降级成普通 `AlertDialog`，用**同一对**文案。**不能因为没录指纹就不让人控车** —— 这是电动车 App，不是银行。

**待执行动作放 ViewModel，不放 Composable**。BiometricPrompt 走系统 UI，期间可能配置变更（旋转、折叠屏展开），Composable 里的 `mutableStateOf` 会丢。

```kotlin
sealed interface CommandStage {
    data object Idle : CommandStage
    data class AwaitingAuth(val action: VehicleAction, val sn: String) : CommandStage
    data class InFlight(val action: VehicleAction, val sn: String) : CommandStage
}
```

时序：滑块 commit 时立刻进 `AwaitingAuth` 并弹 prompt；滑块**照旧 450ms 自动复位**（不等鉴权）；成功进 `InFlight`，加载条才出现；取消回 `Idle` 并弹 Snackbar「已取消」。不要让滑块卡在右端等鉴权。

#### 3.3 指令仓库

```kotlin
class VehicleCommandRepository(private val api: NinebotApi, private val dashboardRepo: DashboardRepository) {
    private val mutex = Mutex()      // 每次只允许一条指令在飞，对应 iOS 的全局 isLoading

    suspend fun perform(action: VehicleAction, sn: String): Result<Unit> = mutex.withLock {
        runCatching {
            when (action) {
                VehicleAction.Bell        -> api.ringBell(sn)
                VehicleAction.OpenBucket  -> api.openBucket(sn)     // POST .../buck
                VehicleAction.EngineStart -> api.engineStart(sn)
                VehicleAction.EngineStop  -> api.engineStop(sn)
            }
        }.onSuccess { dashboardRepo.refresh(selectedSn = sn) }
    }
}
```

加载条只在 `LoadingKind.VehicleAction` 时出现，不会被下拉刷新误触发（iOS 靠字符串匹配区分，`:202`，那是要修掉的东西）。

### 四 · 陷阱

1. **成功语义被刷新失败污染**（`:395` vs `:663-667`）。指令 POST 成功 → `statusMessage = resultTitle`；随后 `fetchDashboard` 失败 → `errorMessage = ...; statusMessage = nil`。结果：**车已经开锁了，界面报错**。Android 必须分开上报：指令成功就弹「上电指令已发送」，刷新失败另给「车况刷新失败，下拉重试」。主动修的行为差异。

2. **450ms 复位定时器和网络无关**（`:3800` 硬编码）。请求要 3 秒，滑块 0.45 秒就弹回，之后靠 `isLoading` 维持转圈。别写成 `delay` 等请求返回，否则慢网下滑块长时间停在右端像卡死。

3. **`guard !model.isLoading else { return }`（`:193`）静默丢弃点击**。任何操作在飞时点按钮毫无反应也无提示。Android 要么真的 `enabled = false`（视觉可见），要么给 Snackbar。别照抄静默无响应。

4. **`isDisabled` 和 `isLoading` 同源**（`:3518` 传 `isDisabled: isLoading`），所以 `isDisabled && !isLoading` 只在「别的操作在跑」时为真。看着像死代码，其实不是。保留两个入参。

5. **`buck` 不是 `bucket`。**

6. **滑动控件的无障碍在 iOS 侧是坏的**：只有 `.accessibilityLabel`（`:3750`），无 `accessibilityAction`，VoiceOver 用户**无法触发上电/熄火**。Android 必须补 `semantics { onClick }`，让 TalkBack 用户能双击执行（照旧走 BiometricPrompt）。这是 Android 必须比 iOS 好的地方。

7. **Compose touch slop 比 iOS 的 10pt 小**（多数设备 6-8dp），滑块会显得更容易误触发。手感偏轻就套一层 `pointerInput` 自己实现 10dp 门槛。

8. **`AnchoredDraggable` 不能直接替代**。它松手会吸到最近锚点，而 iOS 是「未达 72% 一律回 0」。用它必须设 `positionalThreshold = { it * 0.72f }` 且 `velocityThreshold = { Float.MAX_VALUE }`（禁用甩动直达），否则**一个快速小幅甩动就能开锁**。这是安全相关的默认值，必须显式关掉。

9. **`teslaActionThumb` 明暗反转**（`:4931-4934`）：亮色是近黑 `#0E1014`，暗色是绿 `#21D147`。不是同色深浅两版，别在 ColorScheme 里写成 `onSurface`。

10. **重复触发无客户端去重**。iOS 只靠 `isLoading`，置真前有几毫秒窗口。Android 用 `Mutex` + `CommandStage != Idle` 双重拦。

11. `BiometricPrompt` 允许 `DEVICE_CREDENTIAL` 时**不能**调 `setNegativeButtonText`，直接抛异常。最常见的接入崩溃。

### 五 · 验收标准

- [ ] 四个指令各发一次，路径分别是 `/bell`、`/buck`、`/engine/start`、`/engine/stop`，POST 无 body
- [ ] 滑到 71% 松手回弹不触发；73% 松手触发。用 UiAutomator 按 dp 精确投递，不靠手指
- [ ] 快速甩动（>2000 dp/s）但位移 < 72% 时**不触发**
- [ ] commit 动画 240ms 内到位、复位 275ms 内归零，与 iOS 并排录屏逐帧比对，起落时间差 < 30ms
- [ ] commit 瞬间文案立刻变「正在开锁」、双箭头立刻消失（非渐变消失）
- [ ] 450ms 后滑块归零；请求仍在飞时滑块内转圈、文案仍是「正在开锁」、**不降透明度**
- [ ] 指令成功后锁态翻转，文案变「滑动关锁」、图标变 LockOpen，滑块位置为 0 无残留（验证 `key()` 生效）
- [ ] 上电/熄火/开座桶各触发一次 BiometricPrompt，标题正文与表格**逐字相同**
- [ ] 寻车铃**不**触发 BiometricPrompt
- [ ] 未录指纹的设备上三个危险指令降级为 AlertDialog 且仍可执行
- [ ] 鉴权取消 → 不发请求、Snackbar 提示、控件回到可用态
- [ ] BiometricPrompt 弹出时旋转屏幕，鉴权成功后指令仍正确执行（待执行动作没丢）
- [ ] TalkBack 打开时滑动控件可聚焦并双击执行（走完整鉴权链路）
- [ ] 指令成功但刷新失败：提示明确说明「指令已发送」，不是笼统报错
- [ ] 1 秒内连点 10 次寻车铃，服务端只收到 1 个请求

---

## 1.3 快捷设置磁贴 ×5（3 天）

### 一 · iOS 现状

**5 个 Control Widget**（`NinebotWidgets.swift:57-124`，注册在 `:10-27`，`if #available(iOS 18.0, *)` 包裹）

| # | 类型 | displayName | 按钮 Label | `.tint` |
| --- | --- | --- | --- | --- |
| 1 | `NinebotRefreshControlWidget` | 刷新车况 | 刷新车况 / `arrow.clockwise` | green |
| 2 | `NinebotUnlockControlWidget` | 九号开锁 | 开锁 / `lock.open.fill` | green |
| 3 | `NinebotLockControlWidget` | 九号关锁 | 关锁 / `lock.fill` | primaryText |
| 4 | `NinebotBucketControlWidget` | 打开座桶 | 开座桶 / `shippingbox.fill` | primaryText |
| 5 | `NinebotBellControlWidget` | 寻车鸣笛 | 寻车 / `bell.fill` | primaryText |

**5 个对应 AppIntent**（`NinebotWidgetControlIntents.swift:21-77`），全部 `openAppWhenRun = false`：

| Intent | title | authenticationPolicy | 成功 dialog |
| --- | --- | --- | --- |
| Refresh | 刷新车况 | — | `"{name} 车况已刷新"` |
| RingBell | 寻车鸣笛 | **无** | `"{name} 寻车指令已发送"` |
| OpenBucket | 打开座桶 | ✓(47) | `"{name} 开座桶指令已发送"` |
| EngineStart | 滑动开锁 | ✓(59) | `"{name} 开锁指令已发送"` |
| EngineStop | 滑动关锁 | ✓(71) | `"{name} 关锁指令已发送"` |

刷新的名字兜底是 `"九号"`（`:98`），指令类没有兜底（拿不到车辆就抛错）。

**执行器 `NinebotWidgetIntentRunner`（`:79-177`）**

网络会话（`:80-86`）—— 这是 Widget 扩展与主 App 最大的区别：

```swift
let configuration = URLSessionConfiguration.ephemeral   // 不落盘
configuration.timeoutIntervalForRequest = 8             // 相邻数据包最大间隔
configuration.timeoutIntervalForResource = 12           // 整个任务最长寿命
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
```

主 App 是 `URLSession.shared` + 20 秒（`NinebotServerClient.swift:285`）。Widget 扩展有严格的执行时间与内存预算，压到 8/12 是为了在被系统掐掉之前失败得干净。

编排（`:105-135`）：

```
1. client(from: store)  配置不可用 → "请先在 App 里配置数据源"
2. dashboardForOperation（:145-159）
     缓存里有 primaryVehicle → 直接用，零网络请求
     否则 fetchDashboard(selectedSN: nil) → save
     仍无 → "没有找到可操作的车辆"
3. POST 对应端点
4. fetchDashboard(selectedSN: vehicle.sn) → saveDashboard
5. recordWidgetEvent(source:"Widget", operation: action.title, success:true, message: vehicle.name)
6. WidgetCenter.reloadAllTimelines()
```

`action.title` 用的是 Widget 私有枚举（`:5-19`）：寻车 / 开座桶 / **开锁** / **关锁**，与 App 侧的 寻车铃/开座桶/上电/熄火 **不同**。诊断中心（5.1）里两套字符串会混在同一列表里。

### 二 · 要移植的逻辑

#### 2.1 磁贴清单

| # | Service 类 | 标签 | 指令 | 需要解锁 |
| --- | --- | --- | --- | --- |
| 1 | `RefreshTileService` | 刷新车况 | 仅刷新 | 否 |
| 2 | `UnlockTileService` | 九号开锁 | `engineStart` | **是** |
| 3 | `LockTileService` | 九号关锁 | `engineStop` | **是** |
| 4 | `BucketTileService` | 打开座桶 | `openBucket` | **是** |
| 5 | `BellTileService` | 寻车鸣笛 | `bell` | 否 |

用 iOS 的 `displayName`（九号开锁/九号关锁/…），因为快捷设置面板没有 App 名做前缀，「开锁」两字太容易和系统磁贴混。

#### 2.2 超时对齐

| iOS | Android（磁贴专用 OkHttpClient） |
| --- | --- |
| `timeoutIntervalForRequest = 8` | `connectTimeout/readTimeout/writeTimeout = 8s` |
| `timeoutIntervalForResource = 12` | `callTimeout(12s)` |
| `.ephemeral` | `.cache(null)` |
| `reloadIgnoringLocalCacheData` | `CacheControl.FORCE_NETWORK` |

主 App 保留 20s，两个 client 各自注入（Hilt `@Named("tile")` / `@Named("app")`）。别共用。

#### 2.3 编排

```
1. 读配置 → 不可用则 STATE_UNAVAILABLE + 通知「请先在 App 里配置数据源」
2. 取 SN：缓存 primaryVehicle 优先（零网络）；缓存空 → GET /vehicles + dashboard；仍空 → 通知
3. POST 指令
4. 刷新：只拉 GET /vehicles/{sn}/dashboard，不走完整 fetchDashboard
5. 写 DataStore；记 RefreshEvent(source = "Tile")
6. 通知栏反馈 + 磁贴 subtitle 更新
```

第 4 步是**有意偏离**：iOS 的 `fetchDashboard` 是 `GET /vehicles` 加每辆车一次 dashboard（`NinebotServerClient.swift:80-163`），两辆车就是 3 个串行请求，在 12 秒预算里很紧。磁贴只需选中那辆，省下 N−1 个请求。

### 三 · Android 实现要点

#### 3.1 `TileService` 生命周期约束（本项核心难点）

五条必须知道：

1. **一个 `TileService` 类只能对应一个磁贴**。5 个磁贴 = 5 个类。可共享抽象基类，子类只提供 `action` 和 `requiresUnlock`。
2. **服务只在监听窗口内绑定**：`onStartListening()` → `onStopListening()`。窗口在面板可见时打开，收起即关闭。窗口外 `qsTile` 可能为 null，`updateTile()` 是 no-op。
3. **`onClick()` 跑在主线程，且点击后面板通常立刻收起** → 解绑 → 进程可能被降为 cached 并随时回收。**在 `onClick` 里 `launch { 网络请求 }` 是错的**，请求会被中途干掉。
4. `startActivityAndCollapse(Intent)` 在 API 34 废弃、35+ 抛异常；34+ 必须传 `PendingIntent`。minSdk 33 → 两条分支都要写。
5. **`BiometricPrompt` 不能在 `TileService` 里弹**（没有 `FragmentActivity`）。只能用 `unlockAndRun {}` 或拉起透明 Activity。

#### 3.2 骨架

```kotlin
abstract class BaseVehicleTileService : TileService() {
    abstract val action: VehicleAction?            // null = 仅刷新
    abstract val requiresUnlock: Boolean
    private var listeningScope: CoroutineScope? = null

    override fun onStartListening() {
        // 监听窗口内订阅 DataStore，面板打开期间能实时更新 subtitle
        listeningScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope ->
            scope.launch { tileStateRepository.tileState.collect { render(it) } }
        }
    }
    override fun onStopListening() { listeningScope?.cancel(); listeningScope = null }

    override fun onClick() {
        if (requiresUnlock) unlockAndRun { enqueue() } else enqueue()
    }

    private fun enqueue() {
        qsTile?.apply { subtitle = getString(R.string.tile_sending); updateTile() }
        val work = OneTimeWorkRequestBuilder<VehicleCommandWorker>()
            .setInputData(workDataOf(KEY_ACTION to action?.name))
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork("tile-${action?.name ?: "refresh"}", ExistingWorkPolicy.KEEP, work)
        //                                                          ↑ 连点去重
    }
}
```

**不要**加 `ACTIVE_TILE` meta-data。声明为 active tile 后系统就不再在面板打开时调 `onStartListening`，得自己调 `requestListeningState` —— 反而让「打开面板看到最新电量」变复杂。用默认 push 模式，`onStartListening` 里订阅 Flow，面板开着期间指令完成能实时反映到 subtitle。

#### 3.3 Worker

```kotlin
override suspend fun doWork(): Result {
    val sn = dashboard.cachedPrimarySn() ?: dashboard.fetchPrimarySn()
        ?: return fail(R.string.tile_error_no_vehicle)
    return try {
        withTimeout(12_000) {                      // 对齐 timeoutIntervalForResource
            action?.let { commands.sendOnly(it, sn) }
            dashboard.refreshSingle(sn)            // 只刷选中那辆
        }
        diagnostics.record(source = "Tile", operation = action.tileOperationName(), success = true)
        notifier.success(action, dashboard.cachedName(sn))
        requestTileRefresh()
        Result.success()
    } catch (t: Throwable) {
        diagnostics.record(source = "Tile", operation = action.tileOperationName(), success = false)
        notifier.failure(t.localizedMessage)
        Result.failure()                           // 不 retry
    }
}
```

`Result.failure()` **不重试** —— 控车指令重放可能造成「用户以为没开锁，五分钟后车自己开了」。与普通网络 Worker 区别对待。

#### 3.4 反馈通道（没有 `ProvidesDialog` 等价物）

| 手段 | 可靠性 | 说明 |
| --- | --- | --- |
| **通知**（`IMPORTANCE_LOW`，`setTimeoutAfter(6000)`，`setAutoCancel(true)`） | 高 | 唯一可靠的反馈。文案用 iOS dialog 原文 |
| Tile `subtitle` | 中 | 只在面板还开着时可见 |
| Toast | 低 | Android 12+ 后台受限，不要依赖 |

渠道 id `tile_feedback`，名称「快捷设置反馈」。需要 `POST_NOTIFICATIONS`（0.6 已声明，但**运行时授权**要在设置页为磁贴单独引导一次，用户可能拒过）。

#### 3.5 引导添加磁贴

iOS 的 Control Widget 只能手动添加，无 API。**Android 有**（API 33+，正好是 minSdk）：

```kotlin
context.getSystemService(StatusBarManager::class.java)
    .requestAddTileService(
        ComponentName(context, UnlockTileService::class.java),
        getString(R.string.tile_unlock_label),
        Icon.createWithResource(context, R.drawable.ic_tile_lock_open),
        ContextCompat.getMainExecutor(context),
    ) { result -> /* TILE_ADDED / NOT_ADDED / ALREADY_ADDED */ }
```

设置页放 5 个「添加到快捷设置」按钮，比 iOS 体验好一截。注意同一磁贴请求有频率限制，用户多次拒绝后系统会静默不弹，要处理 `result` 回调并给文字兜底指引。

### 四 · 陷阱

1. **`onClick` 里做网络 = 请求被杀**。面板收起就解绑，进程随时进 cached。必须 WorkManager。这是本项最容易踩且最难复现的坑（网好的时候看起来一直正常）。

2. **`setExpedited` 有配额**。用完后降级成普通任务，可能延迟几分钟 —— 用户点了开锁，五分钟后车才响。在诊断中心记录 `enqueue → doWork 开始` 的时延，超过 3 秒就在通知里说明「指令已排队，等待系统调度」。频繁触碰配额说明磁贴被当成主要交互，那时应改用前台服务（`foregroundServiceType="shortService"`，API 34+）。

3. **`unlockAndRun` 在设备已解锁时立即执行，不做任何验证**。iOS 的 `.requiresAuthentication` 在控制中心里**即使手机已解锁也会要求 Face ID**。语义不等价。要严格对齐就得拉透明 Activity 弹 `BiometricPrompt`：
   ```kotlin
   if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(pendingIntent)
   else @Suppress("DEPRECATION") startActivityAndCollapse(intent)
   ```
   建议做成设置项「磁贴控车需要验证身份」，默认开。**需要产品决策**。

4. **磁贴图标只能单色，系统强制着色**。iOS 的 `.tint` 区分（开锁绿、关锁灰）在 Android 完全丢失。状态只能靠 `Tile.state` 和 `subtitle` 表达。别提交带渐变的 VectorDrawable。

5. **瞬时动作磁贴的状态语义别乱用**。寻车/座桶/刷新是「按一下做一件事」，应恒为 `STATE_INACTIVE`；只有开锁/关锁可映射 `STATE_ACTIVE`（开锁磁贴在 `isLocked == false` 时 active）。给瞬时磁贴设 `STATE_ACTIVE`，用户会以为「寻车模式已开启」。

6. **`isLocked == null` 时全部置 `STATE_INACTIVE`，不要猜**。别复用 1.2 里「nil 视为已锁」的规则 —— 那是为了决定滑动控件显示哪个动作，磁贴显示状态是另一套语义。

7. **`qsTile` 可能为 null**。`onClick` 里通常非 null，Worker 回调里通常是 null（服务已解绑）—— 所以 Worker 不能直接改磁贴，只能写 DataStore 让下次 `onStartListening` 读到。

8. **`operation` 文案用 Widget 那套**（寻车/开座桶/开锁/关锁），不是 App 那套。诊断中心要能按 `source` 区分「App」「Tile」，两套字符串共存是 iOS 既有状态，照抄以便对账。

9. **国产 ROM 的快捷设置面板差异大**。MIUI/ColorOS/HarmonyOS 对第三方磁贴数量、`subtitle` 渲染、`requestAddTileService` 支持都不一致，部分 ROM 干脆不显示 subtitle。至少在一台小米或 OPPO 上实测 5 个磁贴都能添加、能点、有反馈。与 0.6 的保活引导同类风险。

10. **磁贴的 DataStore 读取不能阻塞主线程**。`onStartListening` 在主线程，`runBlocking` 会卡面板动画。做法：`Application` 里维护一个 `@Volatile` 最近快照供首帧同步渲染，再由 Flow 补准确值。

### 五 · 验收标准

- [ ] 5 个磁贴都能从系统编辑面板添加，标签图标正确
- [ ] 设置页「添加到快捷设置」能拉起系统对话框，三种 `result` 都有提示
- [ ] 未配置服务器时 5 个磁贴均 `STATE_UNAVAILABLE`
- [ ] 有缓存时点寻车 → 只收到 `POST /bell` + 1 次 `GET dashboard`，**没有** `GET /vehicles`（验证缓存优先）
- [ ] 缓存为空时点寻车 → 先 `GET /vehicles` 补齐再执行
- [ ] **点击后立刻息屏，10 秒后亮屏**：指令仍已送达、通知已出现（验证 WorkManager 而非 service scope）
- [ ] 点击后立刻 `adb shell am kill <pkg>`：指令仍完成
- [ ] 1 秒内连点开锁 5 次：服务端只收到 1 个请求（`ExistingWorkPolicy.KEEP`）
- [ ] 锁屏下点开锁/关锁/座桶先要求解锁；点寻车/刷新直接执行
- [ ] 断网时 12 秒内失败，通知显示可读中文错误，磁贴不卡在「正在发送」
- [ ] 磁贴 client 超时是 8/12 秒（MockWebServer 延迟验证），主 App 仍 20 秒
- [ ] 面板保持打开时执行指令，subtitle 完成后自动更新（验证 Flow 订阅）
- [ ] 开锁磁贴在已解锁时 `STATE_ACTIVE`、已上锁时 `INACTIVE`、`isLocked` 缺失时 `INACTIVE`
- [ ] 诊断中心能看到 `source = "Tile"` 事件，`operation` 为开锁/关锁/开座桶/寻车/刷新车况，含耗时与成败
- [ ] 在一台国产 ROM 上重跑添加、点击、反馈三项

---

## 依赖与并行

1.1 的领域层（`VehicleCardModel` 映射 + 三套配色函数 + 格式化器）必须先做，1.2 的加载条和 1.3 的磁贴 subtitle 都要用。

1.2 的 `VehicleCommandRepository` 是 1.3 的前置 —— 磁贴**不允许**另写一份指令调用，否则端点、超时、去重三处会各自漂移。

图标资产在关键路径上：1.1 需 12 个（电量/续航/均速/锁/开锁/电源/闪电/温度/电压/警告/时钟/信息），1.2 需 4 个，1.3 需 5 个**单色磁贴图标**（要单独出一套，不能复用界面图标 —— 尺寸与描边粗细规范不同）。这 21 个应在 Phase 1 开工前交付。
