# Phase 5 · 桌面 Widget 与充电实时活动 详细规格

本文只覆盖 Phase 5 的 5.3（桌面 Widget）和 5.5（充电实时活动）两项，各 7 天，累计 2.8 周。5.1 诊断中心 / 5.2 防截屏 / 5.4 后台刷新 / 5.6 应用快捷方式见 `phase5-system-spec.md`。

格式与章节结构沿用 [phase1-core-spec.md](./phase1-core-spec.md)。阶段划分见 [android-implementation-plan.md](./android-implementation-plan.md)，厂商灵动岛调研结论见 [android-porting-plan.md](./android-porting-plan.md) 的 §2.1–2.4，已定产品决策见 [pending-decisions.md](./pending-decisions.md)。

目录约定：

```
android/
  feature/widget/          GlanceAppWidget、三档布局、ActionCallback（5.3）
  feature/charging/        前台服务、通知构建、三条路径的装饰器（5.5）
  core/work/               刷新 Worker（与 1.3、5.4 共用）
  core/domain/             充电状态与预测（Phase 2 的 2.3/2.4 产出）
```

## 本阶段依赖什么

| 依赖项 | 来自 | 5.3 要它做什么 | 5.5 要它做什么 |
| --- | --- | --- | --- |
| DataStore 快照 + Room | Phase 0 的 0.3 | Widget 唯一的数据来源 | 通知内容的数据来源 |
| 主题 token（8 组明暗色） | Phase 0 的 0.4 | `WidgetTheme` 那 8 个颜色 | 通知配色与岛配色 |
| 前台服务骨架 + 电池优化引导 | Phase 0 的 0.6 | — | **整项都跑在它上面** |
| 领域层格式化器与状态映射 | Phase 1 的 1.1 | 全部 `...Text` 兜底文案 | 同 |
| `VehicleCommandRepository` | Phase 1 的 1.2 | 交互按钮的唯一指令出口 | — |
| `@Named("tile")` OkHttp client（8/12 秒）、`VehicleCommandWorker`、`tile_feedback` 通知渠道 | Phase 1 的 1.3 | 按钮走同一套 | 轮询用同一个 client |
| 充电预测四个枚举 | Phase 2 的 2.3/2.4 | 无 | 启停判定与剩余时间 |
| WorkManager 刷新链与自适应间隔 | Phase 5 的 5.4 | **Widget 自己不发网络请求，全靠它驱动** | 服务运行期间要让位 |

## 能并行做什么

- **5.3 与 5.5 之间只共享「读同一份快照」这一件事**，没有代码依赖，两个人可以完全并行。
- 5.3 依赖 5.4 的刷新链，但只依赖它的**触发点**（一个 `updateAll(context)` 调用）。可以先写死一个手动刷新按钮开发，等 5.4 好了接上。
- **图标资产在关键路径上**：5.3 需要 11 个（`bolt.fill`、`lock.fill`、`lock.open.fill`、`shippingbox.fill`、`speaker.wave.2.fill`、`bell.fill`、`calendar`、`speedometer`、骑行轨迹图标、`bicycle` 兜底、`link.badge.plus` 空态），5.5 需要 1 个新增（`bolt.batteryblock.fill`）。Widget 图标与界面图标**不能复用**：Glance 里图标会被按 dp 硬缩放，描边粗细规范不同，且要单色可 tint。
- **小米资质申请与本地通知实测必须在 5.5 开工前 2 周启动**（见 `android-porting-plan.md:265`、`:298-303` 与本文 `## 待定` 的 C1）。

## 没有小米资质就无法验收的项

5.5 验收清单里标了 **〔小米〕** 的全部条目。如果 C1 的实测结论是「本地通知不生效」，路径 B 整体不可交付 —— 它需要 MiPush 服务端下发，而 Phase 1 已定「不做推送」（`pending-decisions.md:158`）。那种情况下 5.5 的交付物只有路径 A（标准 `ProgressStyle`）和路径 C（普通进度通知），工时可从 7 天压到 4 天，OPPO 与原生 Android 16 的效果不受影响。

---

## 5.3 桌面 Widget（Glance）（7 天，风险中）

### 一 · iOS 现状

#### 组件清单

| 组件 | 行号（`NinebotWidgets.swift`） | 作用 |
| --- | --- | --- |
| `NinebotWidgetBundle` | 11-28 | 8 个 widget 的注册入口 |
| `NinebotStatusWidget` | 30-42 | 桌面 widget 配置，`supportedFamilies` 三档，挂了 `.contentMarginsDisabled()` |
| `NinebotLockScreenWidget` | 44-55 | 锁屏 widget 配置，三个 accessory family，**没有** `contentMarginsDisabled` |
| `NinebotHomeWidgetView` | 481-508 | 按 `widgetFamily` 分派，容器背景 `WidgetTheme.pageBackground` |
| **`SmallStatusWidget`** | **510-575** | systemSmall 本体 |
| `SmallWidgetBatteryRing` | 577-610 | 30×30 电量环 |
| **`MediumStatusWidget`** | **660-741** | systemMedium 本体 |
| `MediumBatteryProgressBar` | 743-765 | 线性电量条，height 6 |
| `MediumWidgetStatusPill` | 779-813 | 圆点 + 状态文案胶囊 |
| `MediumWidgetControlStrip` | 815-832 | 三按钮横条，height 40 |
| `MediumWidgetControlButton` | 834-849 | 纯图标按钮 |
| **`LargeStatusWidget`** | **851-923** | systemLarge 本体 |
| `WidgetBatteryBar` | 1167-1184 | 线性电量条，height 由调用方给（Large 传 7） |
| `WidgetInfoTile` | 1213-1238 | 三联信息格 |
| `WidgetLargeControlStrip` | 1037-1061 | 三按钮横条，height 44 |
| `WidgetLargeControlItem` | 1063-1090 | 图标 + 文字按钮 |
| `WidgetVehicleImage` | 1143-1165 | 车图，无数据兜底 `bicycle` 42pt |
| `EmptyWidgetView` | 1020-1035 | 空态 |
| `NinebotAccessoryWidgetView` | 925-948 | 锁屏三档分派 |
| `AccessoryRectangularStatus` | 950-986 | 锁屏矩形 |
| `AccessoryCircularStatus` | 988-1018 | 锁屏圆形 |
| `WidgetTheme` | 1356-1395 | 8 个明暗双色 token |

时间线与数据：`NinebotWidgetProvider.swift`（150 行）。交互按钮：`NinebotWidgetControlIntents.swift`（191 行）。数据共享：`Shared/NinebotSharedStore.swift`，App Group id `group.com.example.NineBotPlus`（`NinebotModels.swift:5`）。

**死代码，不要移植**（全仓只有定义没有调用点，已用 grep 逐个确认）：`MediumWidgetInlineStatus`(767-777)、`WidgetControlGrid`(1092-1115)、`WidgetControlGlyph`(1117-1127，只被 `WidgetControlGrid` 用)、`WidgetRoundControlIcon`(1129-1141)、`WidgetStatusLine`(1186-1196)、`WidgetStatusPill`(1198-1211)、`primaryWidgetStatus`(1308-1310)、`formatWidgetDate`(1292-1298)。`batteryAccent`(1267-1269) 活着但两个分支都返回 green，是个退化的三元。

#### `SmallStatusWidget` 层次（516-573，间距为源码原值）

```
ZStack
├─ RoundedRectangle(cornerRadius:26, style:.continuous) fill smallWidgetBackground
├─ Circle().stroke(smallWidgetHaloColor, lineWidth:20) frame 128×128 offset(x:54, y:40)   光晕
├─ WidgetVehicleImage frame 154×94 offset(x:48, y:42)                                      车图，溢出裁切
└─ VStack(alignment:.leading, spacing:12) padding(16) 左上对齐
   ├─ 车名                       caption/semibold  smallWidgetSecondaryText  lineLimit1 minScale 0.72
   ├─ HStack(alignment:.center, spacing:8)
   │  ├─ SmallWidgetBatteryRing frame 30×30
   │  └─ HStack(alignment:.firstTextBaseline, spacing:2)
   │     ├─ estimatedRangeDigits  system(size:35, weight:.bold, design:.rounded) monospacedDigit minScale 0.58
   │     └─ "km"                  system(size:16, weight:.semibold, design:.rounded)
   ├─ Spacer(minLength:34)
   └─ 更新时间胶囊  formatWidgetTime → "HH:mm"  caption2/monospacedDigit/semibold
      padding(h:8, v:5)  background smallWidgetTimeBackground  clipShape Capsule
```

`SmallWidgetBatteryRing`（583-610）：轨道 `Circle().stroke(smallWidgetRingTrack, lineWidth:5)`；进度 `Circle().trim(from:0, to: clamp(value,0,1)).stroke(activeColor, lineWidth:5, lineCap:.round).rotationEffect(-90°)`；中心充电时是 `bolt.fill` 9pt bold green，非充电时是一个直径 12 的背景色实心圆（用来在环中间挖个洞）。

**systemSmall 没有交互按钮**，只展示。

#### `MediumStatusWidget` 层次（666-736）

```
ZStack
├─ RoundedRectangle(26) fill smallWidgetBackground
├─ Circle().stroke(smallWidgetHaloColor, lineWidth:26) frame 176×176 offset(x:126, y:58)
└─ VStack(alignment:.leading, spacing:8) padding(h:14, v:11)
   ├─ HStack(alignment:.top, spacing:10)
   │  ├─ VStack(alignment:.leading, spacing:5)                        撑满
   │  │  ├─ 车名  caption/semibold  secondaryText  minScale 0.68
   │  │  └─ HStack(alignment:.firstTextBaseline, spacing:7)
   │  │     ├─ estimatedRangeDigits  size:34 bold rounded monospacedDigit  minScale 0.58
   │  │     ├─ "km"                  size:17 semibold rounded  primaryText
   │  │     └─ "预估"                caption2/semibold  secondaryText
   │  └─ VStack(alignment:.trailing, spacing:3) frame(width:108)
   │     ├─ "{HH:mm} 更新"  caption2/medium  secondaryText  minScale 0.72
   │     ├─ batteryText     size:22 bold rounded monospacedDigit  batteryColor(...)
   │     └─ MediumWidgetStatusPill
   ├─ MediumBatteryProgressBar frame(height:6)
   ├─ Spacer(minLength:0)
   └─ MediumWidgetControlStrip frame(height:40)
```

`MediumWidgetStatusPill`（783-798）：`HStack(spacing:7)` = 直径 7 的圆点 + `caption2/medium secondaryText minScale 0.78`，`padding(h:8, v:4)`，背景 `controlBackground.opacity(0.86)`，Capsule。

`MediumWidgetControlStrip`（819-831）：`HStack(spacing:0)` 三个等宽按钮，背景 `controlBackground.opacity(0.92)`，`RoundedRectangle(18)`。按钮图标 `size:18 semibold primaryText minScale 0.78`，**无文字**。

#### `LargeStatusWidget` 层次（858-918）

```
ZStack
├─ RoundedRectangle(26) fill smallWidgetBackground
├─ Circle().stroke(smallWidgetHaloColor, lineWidth:38) frame 288×288 offset(x:164, y:130)
└─ VStack(alignment:.leading, spacing:10) padding(14)
   ├─ HStack(alignment:.top, spacing:10)
   │  ├─ VStack(alignment:.leading, spacing:3)
   │  │  ├─ 车名          headline/semibold  primaryText  minScale 0.76
   │  │  └─ "{HH:mm} 更新" caption/medium  secondaryText
   │  └─ WidgetVehicleImage frame 142×72
   ├─ HStack(alignment:.lastTextBaseline, spacing:10)
   │  ├─ estimatedRangeText  size:39 bold rounded monospacedDigit  minScale 0.52
   │  ├─ Spacer(minLength:8)
   │  └─ batteryText         size:34 bold rounded monospacedDigit  batteryColor(...)  minScale 0.58
   ├─ WidgetBatteryBar(height:7)
   ├─ HStack(spacing:8) frame(height:60)  三个 WidgetInfoTile
   ├─ Spacer(minLength:0)
   └─ WidgetLargeControlStrip frame(height:44)
```

`WidgetInfoTile`（1219-1237）：`VStack(alignment:.leading, spacing:5)` = 图标 caption/semibold → 值 caption/semibold primaryText minScale 0.7 → 标题 caption2/medium secondaryText。`padding(10)`，背景 `cardBackground`，`RoundedRectangle(8)`。

三个格子（905-909）：`("本月日均", dailyAverageMileageText, "calendar")`、`("行程均速", averageSpeedText, "speedometer")`、`("最近骑行", lastRideSummaryText, "point.topleft.down.curvedto.point.bottomright.up")`。

`WidgetLargeControlItem`（1069-1089）：`HStack(spacing:5)` = 图标 `size:15 semibold` frame 18×18 + 标题 `caption2/semibold minScale 0.72`。背景 `controlBackground`，`RoundedRectangle(16)`。

#### 锁屏三档（Android 无对应物）

`NinebotLockScreenWidget`（44-55）支持 `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline`。**Android 手机没有锁屏 widget**，`android-porting-plan.md:123` 已定「降级为常驻通知」，排在 Phase 3。**5.3 不做这三档**，但 `AccessoryCircularStatus` 的一条参数在 Phase 3 会用到，记在这里：环的最小可见比例是 `max(0.04, min(fraction, 1))`（`:993`），0% 也画 4% 的弧。

#### 时间线与网络（`NinebotWidgetProvider.swift`）

**iOS 的 widget 扩展自己发网络请求**，这是与 Android 最大的结构差异。

```
placeholder(:20-22)  → .preview 假数据，不读缓存
getSnapshot(:24-33)  → 只读缓存（loadDashboard() ?? .preview），零网络
getTimeline(:35-43)  → loadEntry() 真发请求 → Timeline([entry], policy:.after(now + N 分钟))
```

`loadEntry()`（:53-112）：

```
1. 配置不可用 → 记事件 source="Widget" operation="刷新小组件" success=false message="未配置服务器"
                 返回 cached ?? .empty
2. fetchDashboard(selectedSN: cached?.selectedSN) → saveDashboard → 记成功事件
3. 失败 → saveLastError + 记失败事件，返回 cached ?? .empty，errorMessage = 错误文案
```

网络会话（:12-18）与 Control Widget 的那份**逐字相同**：

```swift
URLSessionConfiguration.ephemeral
timeoutIntervalForRequest = 8
timeoutIntervalForResource = 12
requestCachePolicy = .reloadIgnoringLocalCacheData
```

`refreshIntervalMinutes(for:)`（:45-51），**五档**：

| 条件 | 间隔 |
| --- | --- |
| `state == nil` | 30 分钟 |
| `isCharging == true && !isFullyCharged` | **3 分钟** |
| `isLocked == false \|\| isPoweredOn == true` | 8 分钟 |
| `battery < 20` | 10 分钟 |
| 其他 | 20 分钟 |

注意这套间隔与 5.4 后台刷新那套（充电 15 / 使用中 20 / 空闲 30，`NinebotBackgroundTaskManager.swift:94-103`）**不是同一套**，两边独立。

车图下载（:114-140）：每辆车一次 `URLSession.shared.data(from:)`，只接受 HTTP 2xx、非空、`data.count <= 2_500_000`，落 `saveVehicleImageData`。缓存读取走 `cachedVehicleImages`（:142-149）。

#### 交互按钮（`NinebotWidgetControlIntents.swift`）

Widget 侧有自己的动作枚举（:5-19），文案是**第三套**：

| case | `title` | App 侧对应文案 |
| --- | --- | --- |
| `bell` | 寻车 | 寻车铃 |
| `openBucket` | 开座桶 | 开座桶 |
| `engineStart` | **开锁** | 上电 |
| `engineStop` | **关锁** | 熄火 |

四个 Intent 的鉴权与成功文案：

| Intent | 行号 | `authenticationPolicy` | 成功 dialog |
| --- | --- | --- | --- |
| `NinebotWidgetRefreshIntent` | 21-30 | — | `"{name} 车况已刷新"` |
| `NinebotWidgetRingBellIntent` | 32-41 | **无** | `"{name} 寻车指令已发送"` |
| `NinebotWidgetOpenBucketIntent` | 43-53 | `.requiresAuthentication`(:47) | `"{name} 开座桶指令已发送"` |
| `NinebotWidgetEngineStartIntent` | 55-65 | `.requiresAuthentication`(:59) | `"{name} 开锁指令已发送"` |
| `NinebotWidgetEngineStopIntent` | 67-77 | `.requiresAuthentication`(:71) | `"{name} 关锁指令已发送"` |

四个都是 `openAppWhenRun = false`。`NinebotWidgetEngineStartIntent.title` 是 `"滑动开锁"`（:56）、`EngineStop` 是 `"滑动关锁"`（:68）—— 这两个 title 只出现在 Shortcuts 列表里，桌面 widget 按钮上不显示，「滑动」二字在 widget 语境下没有意义。

执行器 `NinebotWidgetIntentRunner`（:79-177），超时预算在 **:80-86**（8 秒 request / 12 秒 resource，与 provider 那份相同）。编排（:105-135）：

```
1. client(from: store)          配置不可用 → "请先在 App 里配置数据源"
2. dashboardForOperation(:145-159)
     缓存里有 primaryVehicle → 直接用，零网络请求
     否则 fetchDashboard(selectedSN: nil) → save；仍无 → "没有找到可操作的车辆"
3. POST 对应端点
4. fetchDashboard(selectedSN: vehicle.sn) → saveDashboard
5. recordWidgetEvent(source:"Widget", operation: action.title, success:true, message: vehicle.name)
6. WidgetCenter.shared.reloadAllTimelines()
```

`WidgetCenter.reloadAllTimelines()` 的全部调用点：`NinebotViewModel.swift:251/274/298/368/375/406`、`NinebotBackgroundTaskManager.swift:78`、`NinebotAppIntents.swift:271/289/316/348`、`NinebotWidgetControlIntents.swift:97/129`。

### 二 · 要移植的逻辑

#### 2.1 Family 与尺寸映射

| iOS family | 是否在 5.3 范围 | Android |
| --- | --- | --- |
| `.systemSmall` | ✅ | `SizeMode.Responsive` 的 SMALL 档 |
| `.systemMedium` | ✅ | MEDIUM 档 |
| `.systemLarge` | ✅ | LARGE 档 |
| `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` | ❌ Phase 3 | 常驻通知 |

**一个 `GlanceAppWidgetReceiver` 就够**，不需要三个。iOS 是一个 `StaticConfiguration` 声明三个 family，Android 对应一个 `GlanceAppWidget` + `SizeMode.Responsive(setOf(三个 DpSize))`。

#### 2.2 每个尺寸显示哪些字段

| 字段 | Small | Medium | Large |
| --- | --- | --- | --- |
| 车名 | ✅ caption | ✅ caption | ✅ headline |
| 续航数字 | ✅ 35pt（`estimatedRangeDigits`） | ✅ 34pt（`estimatedRangeDigits`） | ✅ 39pt（`estimatedRangeText`，**含 `(预估)` 后缀**） |
| `km` 单位 | ✅ 16pt 独立文本 | ✅ 17pt 独立文本 | ❌ 已在 `estimatedRangeText` 里 |
| `预估` 标签 | ❌ | ✅ caption2 独立文本 | ❌ 同上 |
| 电量百分比文本 | ❌（只有环） | ✅ 22pt | ✅ 34pt |
| 电量环 | ✅ 30×30 | ❌ | ❌ |
| 线性电量条 | ❌ | ✅ height 6 | ✅ height 7 |
| 更新时间 | ✅ `"HH:mm"` 胶囊 | ✅ `"{HH:mm} 更新"` | ✅ `"{HH:mm} 更新"` |
| 状态胶囊 | ❌ | ✅ | ❌ |
| 车图 | ✅ 154×94，右下溢出裁切 | ❌ | ✅ 142×72，右上 |
| 光晕圆环 | ✅ lineWidth 20 | ✅ lineWidth 26 | ✅ lineWidth 38 |
| 三联信息格 | ❌ | ❌ | ✅ 本月日均 / 行程均速 / 最近骑行 |
| 交互按钮 | ❌ | ✅ 3 个纯图标，height 40 | ✅ 3 个图标+文字，height 44 |

#### 2.3 文案与兜底（原文照抄）

| 位置 | 函数 | 行号 | 有值 | 兜底 |
| --- | --- | --- | --- | --- |
| Small/Medium 续航数字 | `estimatedRangeDigits` | 1280-1283 | `formatWidgetNumber(mileage, 0)` | **`"--"`** |
| Large 续航 | `estimatedRangeText` | 1271-1273 | `"{X}km(预估)"` | **`"--km(预估)"`** |
| Large 续航内层 | `estimatedRangeShortText` | 1275-1278 | `"{X}km"` | `"--km"` |
| 电量文本 | `batteryText` | `NinebotModels.swift:1037` | `"{n}%"` | `"--%"` |
| 更新时间 | `formatWidgetTime` | 1300-1306 | `"HH:mm"` | 无兜底 |
| Large 本月日均 | `dailyAverageMileageText` | `NinebotModels.swift:1387-1392` | `"{x.x} km/日"` | **`"-- km/日"`** |
| Large 行程均速 | `averageSpeedText` | `NinebotModels.swift:1437-1440` | `"{x.x} km/h"` | `"-- km/h"` |
| Large 最近骑行 | `lastRideSummaryText` | `NinebotModels.swift:1416-1420` | `"{x.x} km · {n} Wh"` | `"-- km · -- Wh"`（两段各自兜底） |
| 空态 | `NinebotHomeWidgetView` | 503 | — | `entry.errorMessage ?? "暂无车辆"` |
| 配置缺失事件 | `loadEntry` | 66 | — | `"未配置服务器"` |
| Intent 配置缺失 | `NinebotWidgetIntentError` | 186 | — | `"请先在 App 里配置数据源"` |
| Intent 无车 | 同上 | 188 | — | `"没有找到可操作的车辆"` |

**`lastRideSummaryText` 是最容易挤爆的一格**：`"12.3 km · 456 Wh"` 共 16 个字符，要塞进 Large 里三分之一宽的 `WidgetInfoTile`，iOS 靠 `minimumScaleFactor(0.7)` 顶住。

`MediumWidgetStatusPill.statusText`（800-806）——**注意这一套文案 Widget 独有，与 App 侧完全不同**：

```
isFullyCharged     → "电量已充满"
isCharging == true → "正在充电"
isLocked == true   → "守卫模式已开启"
isLocked == false  → "车辆未上锁"
其他               → widgetStatusText(state)
```

`widgetStatusText`（1333-1340），第五套锁车/电源文案：

```
isFullyCharged      → "已充满"
isCharging == true  → "充电中"
isPoweredOn == true → "已上电"
isLocked == true    → "已上锁"
isLocked == false   → "未上锁"
其他                → health.title
```

`health.title` 七种取值（`NinebotModels.swift:1450-1511`）：已充满 / 充电中 / 低电量 / 未锁车 / 电量偏低 / 状态正常 / 状态未知。

`statusDotColor`（808-812）：

```
isLocked == false                    → .orange
isCharging == true || isFullyCharged → WidgetTheme.green
其他                                 → WidgetTheme.primaryText
```

注意 `isLocked == false` 抢在充电前面：一台**正在充电但没锁**的车，圆点是橙的、文案是「正在充电」。照抄。

#### 2.4 Widget 侧有三套电量配色，必须分开写

`phase1-core-spec.md` 的 §2.4 只提到了其中一套。完整是三套：

| 出处 | 行号 | 规则 | 用在哪 |
| --- | --- | --- | --- |
| `SmallWidgetBatteryRing.activeColor` | 605-609 | 充电中→green；`nil`→**green**；`<20`→red；else green | Small 电量环 |
| `MediumBatteryProgressBar.activeColor` | 760-764 | 同上，逐字相同 | Medium 电量条 |
| `batteryColor(_:isCharging:)` | 1240-1246 | 充电中→green；`nil`→**gray**；`<15`→red；`<50`→**orange**；else green | Medium/Large 的电量**文本** |
| `batteryAccent(isCharging:)` | 1267-1269 | 两个分支都 green | Large 电量条（退化的三元） |

三条要点：

1. **环和条是 20 一档，文本是 15/50 两档**。同一屏上 18% 的电量：Medium 的条是红的，数字也是红的；30% 的电量：条是绿的，数字是**橙的**。iOS 既有行为，照抄。
2. **`battery == nil` 时环/条是绿的，文本是灰的**。别统一。
3. Large 的条恒绿（`batteryAccent`），与 Medium 的条规则不同。

Android 写成三个独立函数：`widgetRingColor(battery, isCharging)`、`widgetTextColor(battery, isCharging)`、`widgetLargeBarColor()`。加上 1.1 的 `batteryTextColor`（15/50）和已弃用的 `gaugeColor`（20/50），全仓一共五套阈值 —— 每一套都用自己的函数，禁止合并。

#### 2.5 交互按钮映射

| 位置 | 行号 | 锁态分支 | 三个按钮 |
| --- | --- | --- | --- |
| Medium | 819-827 | `isLocked == false` → `EngineStopIntent` + `lock.open.fill`<br>否则 → `EngineStartIntent` + `lock.fill` | 锁 / `shippingbox.fill` / **`speaker.wave.2.fill`** |
| Large | 1041-1059 | `isLocked == false` → `EngineStopIntent` + 标题 `"关锁"` + `lock.open.fill`<br>否则 → `EngineStartIntent` + 标题 `"开锁"` + `lock.fill` | 锁 / `"座桶"` `shippingbox.fill` / `"寻车"` **`bell.fill`** |

三个要照抄的细节：

1. **图标表达当前状态，标题表达要执行的动作**。已锁时图标是 `lock.fill`（闭锁），标题是「开锁」。与 1.2 的 `SlideActionControl` 同一套逻辑。
2. **`isLocked == nil` 走 else 分支**，即当成已锁，显示「开锁」。与 1.2 的 `isLocked != false` 一致，但**与 1.3 磁贴的「nil 一律 INACTIVE」不一致**，两处语义不同，别互相抄。
3. **寻车图标两处不一样**：Medium 是 `speaker.wave.2.fill`（喇叭），Large 是 `bell.fill`（铃）。这是 iOS 侧的不一致，Android 统一用 `bell.fill` 即可（少一个图标资产），在 plan 里记一笔。

#### 2.6 数字与时间格式化

`formatWidgetNumber`（1285-1290）与 `NinebotVehicleState.numberText`（`NinebotModels.swift:1705-1714`）**配置逐字相同**：`NumberFormatter()`、`maximumFractionDigits` 由调用方给、`minimumFractionDigits = 0`。所以 Android 侧**直接复用 1.1 §2.5 已经对齐好的那个 `numberText`**，不要另写一份。

Widget 里全部调用点的 `maximumFractionDigits` 都是 **0**（1277、1282、459、465、471、477），也就是 widget 上的所有数字都是整数。`NumberFormatter` 默认 `RoundingMode.HALF_EVEN`：`47.5 → "48"`，`46.5 → "46"`。用 `"%.0f"` 会得到 47.5 → "48"、46.5 → "47"，与 iOS 差 1。

`formatWidgetTime`（1300-1306）：locale `zh_CN`、时区**恒定 `Asia/Shanghai`**、格式 `"HH:mm"`。设备时区改成 UTC-8 时 widget 上仍必须是北京时间。

### 三 · Android 实现要点

#### 3.1 类结构

```kotlin
// feature/widget/StatusWidget.kt
class StatusWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val entryPoint = EntryPointAccessors.fromApplication<WidgetDeps>(context)
        val first = entryPoint.widgetRepo().snapshotOnce()      // 首帧同步值，不发网络
        provideContent {
            val model by entryPoint.widgetRepo().snapshotFlow.collectAsState(first)
            GlanceTheme { WidgetRoot(model, LocalSize.current) }
        }
    }
}

class StatusWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = StatusWidget()
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray) {
        super.onUpdate(c, m, ids)
        enqueueRefreshWork(c)                                   // 见 3.6
    }
}
```

Hilt 在 `GlanceAppWidget` 里不能用字段注入（它不是 Android 组件），用 `EntryPointAccessors`。

#### 3.2 `SizeMode` 与断点

```kotlin
private val SMALL  = DpSize(140.dp, 140.dp)
private val MEDIUM = DpSize(300.dp, 140.dp)
private val LARGE  = DpSize(300.dp, 280.dp)
```

`appwidget-provider` 里：

```xml
<appwidget-provider
    android:minWidth="140dp" android:minHeight="140dp"
    android:targetCellWidth="2" android:targetCellHeight="2"
    android:maxResizeWidth="320dp" android:maxResizeHeight="300dp"
    android:resizeMode="horizontal|vertical"
    android:updatePeriodMillis="1800000"
    android:description="@string/widget_description"
    android:previewLayout="@layout/widget_preview" />
```

三点必须知道：

1. **实际 dp 由启动器网格决定**，不由我们决定。`SizeMode.Responsive` 会在集合里挑最接近的一档，用 `LocalSize.current` 读回来。必须在 Pixel Launcher、MIUI 桌面、ColorOS 桌面各测一遍三档都能落到预期布局上。
2. **`updatePeriodMillis` 的最小有效值是 30 分钟（1800000）**，系统不会更频繁地送。所以它不能承担 iOS 那套 3/8/10/20 分钟的自适应节奏，只能当兜底心跳，见 3.6。
3. **Android 12+ 会给 widget 加系统默认外边距**。iOS 的 `.contentMarginsDisabled()`（`:40`）意思是四边贴满自己画背景。Android 侧要做到同样效果，根节点自己 `fillMaxSize().background(...).cornerRadius(26.dp)`，内容 padding 自己给（Small 16dp / Medium h14 v11 / Large 14dp），并实测三个启动器的实际留白。`cornerRadius(Dp)` 需要 API 31+，minSdk 33 无需分支。

#### 3.3 Glance 能力缺口（本项主要风险）

Glance 只支持 Compose 的一个很小子集，编译成 `RemoteViews`。下面每一条都是必须处理的缺口，不是可选优化。

| iOS 用了什么 | Glance 有没有 | 变通方案与代价 |
| --- | --- | --- |
| `Circle().trim().stroke(lineCap:.round)` 电量环 | **没有 `Canvas`**，没有 `drawArc` | 见下方「环形图三条路」 |
| `LinearGradient`（充电卡渐变、5.5 用） | `background()` 只吃颜色或 `ImageProvider` | 渐变做成 `<shape><gradient>` 的 `drawable`，用 `background(ImageProvider(resId))`；动态角度做不到 |
| `Circle().stroke(lineWidth:20).offset(...)` 光晕 | 无描边 API | 三档各出一张 9-patch 或 PNG 背景 drawable，光晕烘进图里；或直接砍掉（在小尺寸上几乎看不见） |
| `Capsule()` 电量条 | 有 `Box` + `cornerRadius` | `Box(GlanceModifier.height(6.dp).cornerRadius(3.dp).background(track))` 里套一个定宽 `Box`。**Glance 没有 `BoxWithConstraints`**，宽度得用 `LocalSize.current.width` 减掉自己的 padding 算，或用 `defaultWeight()` 分两段。**三条进度条的最小可见宽度不一样**：`MediumBatteryProgressBar` 是 **5**（`:755`），`WidgetBatteryBar`（Large）是 **8**（`:1179`），5.5 的 `ChargingLiveProgressBar` 是 **8**（`:414`）。别统一 |
| `.shadow(color:radius:y:)` | 无 | 砍掉。widget 有系统背景，阴影本来不明显 |
| `minimumScaleFactor` ×12 处 | **没有**，`Text` 只有 `maxLines` | 见下方「字号分档」 |
| `monospacedDigit()` | 无 API | `TextStyle(fontFamily = FontFamily.Monospace)` 会换掉整个字族，观感差异大。建议放弃等宽，接受数字跳动时的轻微位移 |
| `design: .rounded` | 无系统圆体 | 打包一份圆体字重（如 MiSans Rounded / 思源黑体圆角变体），或放弃改用系统默认。**要设计确认** |
| `offset(x:y:)` 让车图溢出裁切 | 有 `Box` 对齐，无负偏移 | 车图切成「已经带留白与裁切效果」的位图，或改成不溢出的常规布局 |
| `Spacer(minLength: 34)` | `Spacer(GlanceModifier.height(34.dp))` 或 `defaultWeight()` | 直译，无损 |
| `AsyncImage` 车图 | 无异步加载 | Worker 里用 Coil 下到本地文件，`provideGlance` 只读已下好的位图。见 3.4 |
| `Button(enabled:)` 禁用态 | 不保证有 | 用 `Box(modifier.clickable(...))` 并在 pending 时**不挂 `clickable`**，视觉上降透明度靠换颜色实现（Glance 无 `alpha`） |

**环形图三条路（`## 待定` W1，选哪条是产品决策）**

| 路 | 做法 | 代价 |
| --- | --- | --- |
| A · 预渲染 Bitmap | Worker 或 `provideGlance` 的 suspend 段里用 `android.graphics.Canvas` + `Paint(strokeCap = ROUND)` 画 `drawArc`，`Image(ImageProvider(bitmap))` | 每次电量变化都要重画；明暗两套 × 每个 widget 实例；位图要按 `LocalSize` × density 生成（不能画一张 1024² 再缩）；`RemoteViews` 走 Binder，事务有上限（超出抛 `TransactionTooLargeException`），`AppWidgetHostView` 另有一个位图内存上限（超出抛 `IllegalArgumentException`，消息形如 `RemoteViews for widget update exceeds maximum bitmap memory usage`）；无障碍要单独给 `contentDescription` |
| B · 降级成线性条 | 用 Medium 那套 `Box` + `cornerRadius` 拼的条替掉 Small 的环 | 零风险、零额外资产、与已定决策「电量显示照抄 iOS 的线性细长条」（`pending-decisions.md:168`）一致；代价是 Small 的视觉与 iOS 不同 |
| C · 多个 `Box` 拼 | 用 12 个小方块围成一圈，按比例点亮 | 拼不出 `lineCap: .round`，60dp 直径下锯齿明显；12 个 `Box` 让 `RemoteViews` 树变深；不值得 |

**注意 Glance 的 `CircularProgressIndicator` 顶不上这个位置**：它是不确定进度的转圈动画，不接受 `progress` 参数。`LinearProgressIndicator` 有接受 `progress: Float` 的重载，但它是 Material 样式的方角条，与 iOS 的 Capsule 观感不同，且颜色只能整条一个色。

> **上面这张缺口表里关于 Glance 的每一条断言，都要在开工第一天用实际依赖版本核对一遍**（`androidx.glance:glance-appwidget` 的 `package-summary` 与真机渲染），核对完把结论补回本节。iOS 侧的行号与数值是从源码逐行读出来的，可以直接信；Glance 那一列是按当前认知写的，**不要照本文的描述直接写代码**。本项目此前出过凭印象编 API 的事故，这张表是最容易复现同一个错误的地方。



**字号分档（替代 `minimumScaleFactor`）**

把 iOS 的 `基准 pt × minimumScaleFactor` 换算成最小可接受字号，在 Kotlin 侧按字符数选一档：

| 位置 | 基准 | minScale | 下限 |
| --- | --- | --- | --- |
| Small 续航数字 | 35 | 0.58 | 20.3 |
| Small 车名 | caption 12 | 0.72 | 8.6 |
| Medium 续航数字 | 34 | 0.58 | 19.7 |
| Medium 车名 | caption 12 | 0.68 | 8.2 |
| Medium 更新时间 | caption2 11 | 0.72 | 7.9 |
| Medium 状态胶囊 | caption2 11 | 0.78 | 8.6 |
| Medium 按钮图标 | 18 | 0.78 | 14.0 |
| Large 车名 | headline 17 | 0.76 | 12.9 |
| Large 续航 | 39 | 0.52 | 20.3 |
| Large 电量 | 34 | 0.58 | 19.7 |
| Large 三联值 | caption 12 | 0.70 | 8.4 |
| Large 按钮标题 | caption2 11 | 0.72 | 7.9 |

（SwiftUI 默认动态字体档位：caption 12、caption2 11、headline 17。）

```kotlin
private fun rangeFontSize(text: String): TextUnit = when {
    text.length <= 3 -> 34.sp     // "88"、"120"
    text.length <= 5 -> 27.sp     // "1234"
    else             -> 20.sp     // 下限，对应 34 × 0.58
}
```

8sp 以下的档位没有意义，那几行（更新时间、状态胶囊、按钮标题、三联值）直接用基准字号 + `maxLines = 1` 即可，`lastRideSummaryText` 那一格例外，要按字符数降到 10sp。

#### 3.4 数据读取与 `provideGlance` 生命周期

**Android 不需要 App Group**（`phase0-foundation-spec.md:169`）：Glance widget 与主 App 同进程，直接读同一份 DataStore / Room。App Group 那 23 个 key（`NinebotSharedStore.swift:4-23`）在 Android 侧就是 0.3 已经建好的存储。

四条约束：

1. **`provideGlance` 是 `suspend` 的，并且在调用 `provideContent` 之后不返回**。Glance 会持续观察 Composition 里的 state，所以 `collectAsState` 是有效的订阅。但进程被回收后订阅就没了，之后要靠外部 `update()` 重新走一遍 `provideGlance`。**不能把 Flow 订阅当成唯一的刷新途径。**
2. **首帧要有同步值**。`collectAsState(initial)` 的 initial 必须是真实数据，否则 widget 会闪一下空态。做法：`provideGlance` 进入后先 `suspend fun snapshotOnce(): WidgetModel`（一次 `first()`），拿到再 `provideContent`。这段是 suspend 的，可以安全读 DataStore/Room，不会阻塞主线程。
3. **`provideGlance` 里不发网络请求**。这是对 iOS 的**有意偏离**：iOS 的 `getTimeline`（`NinebotWidgetProvider.swift:35-43`）真的在扩展进程里 `fetchDashboard`。Android 侧改成「只读缓存 + 由 5.4 的 Worker 负责刷新后调 `update`」，理由是 widget 更新是被系统调起的短生命周期，长请求会被掐；且 Glance 的更新本身没有 iOS 那种「返回一条 timeline 就完事」的模型。
4. **`updateAppWidgetState` 只放 UI 瞬态**（pendingAction、上次失败文案），车况数据一律走仓库。两份状态混着放会出现「widget 里的电量和 App 里的不一样」。

```kotlin
data class WidgetModel(
    val hasVehicle: Boolean,
    val vehicleName: String,
    val rangeDigits: String,          // "--" 或整数字符串
    val batteryText: String,          // "--%"
    val batteryPercent: Int?,         // null = 接口未返回
    val batteryFraction: Float,
    val isCharging: Boolean,
    val isFullyCharged: Boolean,
    val isLocked: Boolean?,           // 三态，禁止 ?: false
    val isPoweredOn: Boolean?,
    val statusPillText: String,
    val statusDotColor: WidgetDotColor,
    val updatedAtText: String,        // "HH:mm"，Asia/Shanghai
    val dailyAverage: String, val averageSpeed: String, val lastRide: String,
    val vehicleImagePath: String?,    // 已下好的本地文件
    val emptyMessage: String?,        // errorMessage ?: "暂无车辆"
    val pendingAction: VehicleAction?,
    val lastFailure: String?,
)
```

车图：Coil 在**刷新 Worker 里**下载到 `filesDir/widget_vehicle/{sn}.png`，尺寸按最大档（154×94dp × 最大 density）生成，落盘前校验 `size <= 2_500_000`（对齐 `NinebotWidgetProvider.swift:128` 与 `NinebotSharedStore.swift:396`）。`provideGlance` 只 `BitmapFactory.decodeFile` 已存在的文件。**不要在 `provideGlance` 里下载**。

#### 3.5 交互按钮

Glance 侧是 `ActionCallback` + `actionRunCallback`：

```kotlin
class VehicleActionCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val action = parameters[ActionKey] ?: return
        // 1. 立刻写 pending 态并刷新 widget，让用户看到按下去了
        updateAppWidgetState(context, glanceId) { it[PendingKey] = action.name }
        StatusWidget().update(context, glanceId)
        // 2. 真正的请求交给 WorkManager，不在这里做
        WorkManager.getInstance(context).enqueueUniqueWork(
            "widget-${action.name}",
            ExistingWorkPolicy.KEEP,                       // 防连点
            OneTimeWorkRequestBuilder<VehicleCommandWorker>()
                .setInputData(workDataOf(KEY_ACTION to action.name, KEY_SOURCE to "Widget"))
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build(),
        )
    }
}
```

**谁去发请求：WorkManager，不是 `onAction`。** `actionRunCallback` 是通过广播派发的，`onAction` 跑在广播的时间预算里（`BroadcastReceiver` 的 10 秒 ANR 门槛）。一个 12 秒预算的网络请求放进去必然被掐。这与 1.3 磁贴的 `onClick` 是同一个坑，`phase1-core-spec.md` §1.3 三 3.1 第 3 条已经写过，**理由和解法一模一样，复用同一个 `VehicleCommandWorker`**。

按钮布局（Glance 无 `Button(enabled:)` 保证，用 `Box`）：

```kotlin
@Composable
private fun ControlButton(action: VehicleAction, iconRes: Int, title: String?, pending: Boolean) {
    val mod = GlanceModifier.fillMaxHeight().defaultWeight()
        .let { if (pending) it else it.clickable(actionRunCallback<VehicleActionCallback>(
            actionParametersOf(ActionKey to action.name))) }
    Box(mod, contentAlignment = Alignment.Center) { /* Image + 可选 Text */ }
}
```

| 项 | 值 |
| --- | --- |
| 超时 | 复用 1.3 的 `@Named("tile")` client（connect/read/write 8 秒、`callTimeout` 12 秒、`cache(null)`、`FORCE_NETWORK`）。iOS 侧 provider 与 control intent 用的是**同一份配置**（`NinebotWidgetProvider.swift:12-18` 与 `NinebotWidgetControlIntents.swift:80-86` 逐字相同），所以 Android 也用同一个，建议把 Hilt 限定符从 `@Named("tile")` 改名为 `@Named("system")` |
| 编排 | 与 1.3 的 §2.3 相同：缓存 primaryVehicle 优先（零网络）→ POST 指令 → 只拉 `GET /vehicles/{sn}/dashboard` → 写仓库 → 记 `RefreshEvent(source = "Widget", operation = 2.5 那套文案)` → `StatusWidget().updateAll(context)` |
| 防连点 | `ExistingWorkPolicy.KEEP` + `PendingKey` 双重拦。`KEEP` 是硬保证，`PendingKey` 是给用户看的 |
| 失败反馈 | 通知（复用 1.3 的 `tile_feedback` 渠道，`IMPORTANCE_LOW`、`setTimeoutAfter(6000)`、`setAutoCancel(true)`）+ 把错误文案写进 `LastFailureKey`，widget 上显示一行小字，下次成功刷新时清掉 |
| 鉴权 | 见 `## 待定` W2 |

**Widget 上没有 `ProvidesDialog` 的等价物。** iOS 那四条成功 dialog（`"{name} 寻车指令已发送"` 等，`NinebotWidgetControlIntents.swift:39/51/63/75`）在桌面 widget 按钮里是否真的会显示未核实（`Button(intent:)` 没有对话框宿主），但无论如何 Android 必须自己给反馈。文案直接用 iOS 那四条原文。

#### 3.6 刷新触发链

| 触发者 | 时机 | 对应 iOS |
| --- | --- | --- |
| 主 App 刷新成功 | `DashboardRepository` 写完快照 | `NinebotViewModel.swift:251/274/298/368/375/406` |
| 5.4 的周期 Worker | 每次刷新成功 | `NinebotBackgroundTaskManager.swift:78` |
| Widget 按钮的 Worker | 成功或失败都要更新（失败要显示错误行） | `NinebotWidgetControlIntents.swift:97/129` |
| 磁贴 Worker（1.3） | 成功后 | 同上 |
| 应用快捷方式（5.6） | 执行后 | `NinebotAppIntents.swift:271/289/316/348` |
| `StatusWidgetReceiver.onUpdate` | 系统按 `updatePeriodMillis` 调起（≥30 分钟一次） | iOS 的 timeline `.after()` |

统一出口一个函数，别散着调：

```kotlin
suspend fun refreshWidgets(context: Context) = StatusWidget().updateAll(context)
```

**与 5.4 的关系**：iOS 的 widget 有自己一套 3/8/10/20/30 分钟的自适应间隔（`NinebotWidgetProvider.swift:45-51`），和后台刷新那套 15/20/30（`NinebotBackgroundTaskManager.swift:94-103`）是两套独立节奏。Android 侧**只保留一套** —— 5.4 的 15/20/30，widget 跟着它走。理由：Android 没有「widget 自己排下一次唤醒」的机制，`updatePeriodMillis` 下限就是 30 分钟，硬做两套只会得到两条互相打服务端的链路。

代价是充电中 widget 的刷新从 iOS 的 3 分钟变成 15 分钟。**缓解**：5.5 的前台服务在充电期间本来就在按分钟级轮询并写同一份快照，服务每次写完顺手调一次 `refreshWidgets` —— 充电中 widget 反而比 iOS 更新得更勤。这条是 5.3 与 5.5 之间唯一的耦合点，两边都要知道。

`updatePeriodMillis` 设 1800000 而不是 0，是因为 `provideGlance` 不发网络，光靠系统周期调起只会用旧数据重画一遍。所以在 `StatusWidgetReceiver.onUpdate` 里额外 `enqueueUniqueWork("widget-heartbeat", KEEP, RefreshWorker)`，把它变成 5.4 之外的第二条心跳 —— 国产 ROM 把 WorkManager 的周期任务掐掉时，桌面 widget 至少还能每 30 分钟自救一次。

### 四 · 陷阱

1. **`provideGlance` 里发网络请求会被掐。** iOS 就是这么做的（`NinebotWidgetProvider.swift:53-112`），照抄必错。Android 侧只读缓存。

2. **Android 的 widget 不会产生 `source = "Widget"` 的刷新事件。** iOS 的 widget 自己刷新时记 `operation = "刷新小组件"`（`NinebotWidgetProvider.swift:62/82/99`），Android 侧这条链路搬到了 5.4 的 Worker，所以诊断中心（5.1）里 `source = "Widget"` 只会有**指令**事件（寻车/开座桶/开锁/关锁），没有刷新事件。5.1 的负责人必须知道这条，否则会按 iOS 的事件表去做界面然后发现少一类。

3. **`isLocked` 是三态，`?: false` 会让「锁车未知」的车显示成「车辆未上锁」并把状态圆点变橙。** Widget 里有三处用到它：`MediumWidgetStatusPill.statusText`(803-804)、`statusDotColor`(809)、两个 `ControlStrip` 的分支(820/1042)。三处语义都不同，逐个照抄。

4. **`estimatedRangeText` 把 `(预估)` 拼进了同一个 39pt 文本里**（1271-1273）。Large 那个大数字实际是 `"48km(预估)"` 这种形状，不是纯数字。别按 Medium 的三段式去拆，会得到不同的排版。

5. **`localEstimatedMileage` 不是「本地算的」**（`NinebotModels.swift:1323-1329`）：优先服务端预测，缺失才回退官方预估。社区服务端不返回预测，所以 widget 上那个「预估」数字实际显示的是官方预估。与 1.1 §陷阱 5 同一个问题，见 `pending-decisions.md` 的 D5。

6. **Widget 上的所有数字都是整数（`maximumFractionDigits: 0`）且按 HALF_EVEN 舍入。** 用 `"%.0f"` 在 x.5 边界会与 iOS 差 1。用 1.1 §2.5 那个已经对齐好的 `numberText`。

7. **时区恒定 `Asia/Shanghai`**（1300-1306）。别用 `LocalDateTime.now()`。

8. **Medium/Large 内部各有一个不可达的 `EmptyWidgetView`**（738、920）：`NinebotHomeWidgetView`（487）已经先判过 `primaryVehicle`，走到 Medium/Large 时它必然非空。这两个分支的文案是硬编码 `"暂无车辆"`，**不带 `errorMessage`** —— 如果照抄成 Android 的真实分支，网络错误时会显示「暂无车辆」而不是错误原因。空态只在根节点判一次。

9. **`RemoteViews` 树有节点数与事务大小限制**，Large 那一档（3 个 tile × 3 个 Text + 3 个按钮 + 条 + 车图）已经不算小。如果 W1 选了预渲染 Bitmap 的路，同一次更新里可能同时带三档的位图 —— 位图内存上限和 Binder 事务上限都要实测，别等上线才发现某个启动器上 widget 变成空白。

10. **Glance 没有动画。** 1.1 已定的「电量条 600ms 补间」（`pending-decisions.md:172`）在 widget 上做不到，也不该做 —— widget 是跳变的。别为了一致性去尝试用多帧位图模拟。

11. **`speaker.wave.2.fill` 与 `bell.fill` 的不一致要主动收敛。** 照抄会白做一个图标资产。

12. **`requestPinAppWidget` 有频率限制。** 与 1.3 的 `requestAddTileService` 同类：设置页可以放「添加到桌面」按钮（`AppWidgetManager.requestPinAppWidget`，API 26+），但用户多次拒绝后系统会静默不弹，要处理回调并给文字兜底指引。

### 五 · 验收标准

- [ ] 三档尺寸在 Pixel Launcher / MIUI 桌面 / ColorOS 桌面各添加一次，`LocalSize.current` 落到预期档位（打日志验证，不靠肉眼）
- [ ] 每档的字段清单与 §2.2 表格逐项对照，缺一项算不通过
- [ ] `"--"` / `"--%"` / `"--km(预估)"` / `"-- km/日"` / `"-- km/h"` / `"-- km · -- Wh"` / `"暂无车辆"` / `"未配置服务器"` 八种兜底各截图归档
- [ ] 三套电量配色分别打点：`battery = null` 时环/条绿、文本灰；`battery = 18` 时 Medium 条红、文本红；`battery = 30` 时条绿、文本**橙**；充电中三处全绿；Large 条恒绿
- [ ] `battery = 19/20` 与 `14/15` / `49/50` 四个边界各验一次
- [ ] `battery = 0`：Medium 的条留 5dp 可见残段、Large 的条留 8dp 可见残段（两档最小宽度不同，不是完全空条）
- [ ] 状态胶囊五分支各命中一次，含「守卫模式已开启」与「正在充电 + 橙点」（充电且未锁）
- [ ] `isLocked = null` 时：胶囊落到 `widgetStatusText`、圆点为 primaryText、按钮显示「开锁」+ `lock.fill`
- [ ] Medium 与 Large 的锁态按钮在 `isLocked` 三态下各截图，图标/标题组合与 §2.5 表格一致
- [ ] 点按钮后 1 秒内 widget 上出现 pending 态；请求成功后 pending 清除、数据已更新
- [ ] **点按钮后立刻息屏，10 秒后亮屏**：指令已送达、widget 已更新（验证走的是 WorkManager 而不是广播预算）
- [ ] 点按钮后立刻 `adb shell am kill <pkg>`：指令仍完成
- [ ] 1 秒内连点开锁 10 次：服务端只收到 1 个请求
- [ ] 断网点按钮：12 秒内失败，通知里有可读中文错误，widget 上出现错误行且不卡在 pending
- [ ] Widget client 超时是 8/12 秒（MockWebServer 延迟验证），主 App 仍 20 秒
- [ ] 设备时区改 UTC-8，更新时间仍显示北京时间
- [ ] 系统最大字号 + 最小档 widget：Large 三联不换行不重叠，续航数字不被裁；`"12.3 km · 456 Wh"` 完整可读
- [ ] 未配置服务器时三档都显示 `"未配置服务器"`，按钮不可点
- [ ] 冷启动（清数据后首次添加 widget）不闪空态：首帧就是缓存值或明确的空态，不是先空后有
- [ ] 车图：无缓存时显示 `bicycle` 兜底；有缓存时显示车图；下载失败不影响其他字段
- [ ] 关掉 5.4 的 Worker，等 30 分钟：`updatePeriodMillis` 心跳把数据刷新了（验证第二条心跳生效）
- [ ] 充电中：5.5 的前台服务每轮询一次，widget 的更新时间跟着走
- [ ] TalkBack：电量环/条有 `contentDescription`（`"电量进度 {n}%"`，对齐 1.1），三个按钮各有可读标签

---

## 5.5 充电实时活动（7 天，风险中）

### 一 · iOS 现状

iOS 侧是 ActivityKit 的 Live Activity，注册在 `NinebotWidgets.swift:15-19`（`if #available(iOS 16.1, *)`），呈现在 `NinebotWidgets.swift:127-479`，生命周期在 `NinebotChargingLiveActivityManager.swift`（209 行），数据契约在 `Shared/NinebotChargingActivityAttributes.swift`（97 行）。

#### `ContentState` 八个字段（`NinebotChargingActivityAttributes.swift:12-20`）

| 字段 | 类型 | 取值来源（`NinebotChargingLiveActivityManager.swift:49-58`） |
| --- | --- | --- |
| `battery` | `Int`（**非可选**） | `snapshot.state.battery`，为 nil 时整个活动不启动 |
| `estimatedRange` | `Double?` | `localEstimatedMileage ?? endurance ?? aiEstimatedMileage`（:51，三级兜底） |
| `estimatedFullAt` | `Date?` | `estimatedFullChargeMinutes > 0` 时 `Date() + minutes*60`，否则 nil（:105-108） |
| `chargingPower` | `Double?` | `state.chargingPower` |
| `batteryTemperature` | `Double?` | `state.batteryTemperature` |
| `batteryVoltage` | `Double?` | `state.batteryVoltage` |
| `chargingSpeed` | `Double?` | `state.estimatedChargingSpeedKmh` |
| `updatedAt` | `Date` | `state.updatedAt` |

`Attributes` 本体三个静态字段：`vehicleSN`、`vehicleName`、`vehicleModel`（:8-10）。

**`batteryVoltage` 和 `vehicleModel` 在界面上一处都没用到**。前者在 `ContentState` 里占着位、走了编解码，后者同理。移植时可以省，但要在 plan 里记一笔，否则以后对账会以为漏了。

`ContentState` 的自定义编解码（:53-94）值得注意：`estimatedFullAt` / `updatedAt` 编码成 `timeIntervalSince1970`（Double），解码时 `> 1_000_000_000` 认作 1970 纪元、否则认作 2001 纪元，还兼容字符串与 ISO8601（:77-94）。这是为了容纳服务端 APNs payload 的时间格式漂移。**Android 不做推送，这套兼容逻辑不需要移植**。

#### 三种呈现分别显示什么

**锁屏 / 通知中心卡片**（`NinebotChargingLiveActivityCard`，178-251）

```
ZStack  clipShape RoundedRectangle(cornerRadius:28, style:.continuous)
├─ chargingCardGradient(colorScheme)                     暗:3 色 / 亮:3 色，topLeading→bottomTrailing
└─ VStack(alignment:.leading, spacing:12)  padding(h:20, top:15, bottom:14)
   ├─ HStack(alignment:.center)
   │  ├─ Label("充电中", "bolt.fill")     subheadline/bold  chargingCardPrimaryText
   │  ├─ Spacer(minLength:8)
   │  └─ Image("bolt.batteryblock.fill")  headline/bold  primaryText.opacity(0.90)
   ├─ HStack(alignment:.bottom, spacing:10)
   │  ├─ HStack(alignment:.firstTextBaseline, spacing:7)          撑满，左对齐
   │  │  ├─ "{battery}%"        size:38 bold rounded monospacedDigit green  minScale 0.68
   │  │  └─ chargingRangeText   size:31 bold rounded monospacedDigit green  minScale 0.58
   │  └─ VStack(alignment:.trailing, spacing:1)  frame(width:112)
   │     ├─ "剩余时间"           caption/semibold  chargingCardSecondaryText
   │     └─ ChargingRemainingText size:29 heavy rounded **italic** monospacedDigit
   │                              secondaryText.opacity(0.92)  minScale 0.52
   ├─ ChargingLiveProgressBar(battery/100)  frame(height:6) padding(top:1)
   └─ HStack(spacing:8)  三个 ChargingLiveMetric
      ├─ (chargingPowerText,       "充电功率")
      ├─ (chargingTemperatureText, "电池温度")
      └─ (chargingSpeedText,       "充电速度")
```

`ChargingLiveMetric`（360-381）：值 `size:23 heavy rounded italic monospacedDigit secondaryText.opacity(0.96) minScale 0.55`；标题 `caption2/semibold minScale 0.75`。

卡片外层还有 `.activityBackgroundTint(WidgetTheme.chargingActivityBackground)` 与 `.activitySystemActionForegroundColor(WidgetTheme.green)`（136-137）。

**灵动岛展开态**（139-154）三个 region：

| region | 组件 | padding |
| --- | --- | --- |
| `.leading` | `ChargingIslandTitle`（254-275） | leading 4, top 2 |
| `.trailing` | `ChargingIslandRemaining`（278-303） | top 2, trailing 12 |
| `.bottom` | `ChargingIslandBottom`（306-321） | horizontal 4, top 4 |

```
ChargingIslandTitle    VStack(alignment:.leading, spacing:4) frame(maxWidth:124)
├─ Label("充电中","bolt.fill")  caption/bold  green
├─ attributes.vehicleName       caption2/semibold  白 0.74  minScale 0.7
└─ "{battery}%"                 size:24 bold rounded monospacedDigit  green

ChargingIslandRemaining  VStack(alignment:.trailing, spacing:4) frame(width:88)
├─ "剩余"                caption2/semibold  白 0.58
├─ ChargingRemainingText size:22 heavy rounded italic monospacedDigit  白 0.82  minScale 0.72
└─ chargingRangeText     caption/semibold  green

ChargingIslandBottom    VStack(spacing:8)
├─ ChargingLiveProgressBar  frame(height:5)
└─ HStack(spacing:8)  三个 ChargingIslandMetric
   ├─ (chargingPowerText,       "功率")
   ├─ (chargingTemperatureText, "温度")
   └─ (chargingSpeedText,       "速度")
```

`ChargingIslandMetric`（383-401）：值 `caption/monospacedDigit/bold 白 0.86 minScale 0.62`；标题 `caption2/medium 白 0.52`。

**注意展开岛的三个指标标签是「功率/温度/速度」，锁屏卡片是「充电功率/电池温度/充电速度」。两套并存，别合并。**

**灵动岛紧凑态与最小态**（155-169）：

| 位置 | 内容 |
| --- | --- |
| `compactLeading` | `Image("bolt.fill")` `caption/bold` green，frame 16×16 |
| `compactTrailing` | `"{battery}%"` `caption2/monospacedDigit/bold` green `lineLimit(1) minScale 0.7` |
| `minimal` | `Image("bolt.fill")` green，无字号修饰 |
| `keylineTint` | green（:170） |

紧凑态**只有闪电 + 百分比**，没有剩余时间。`ChargingCompactRemainingText`（324-333）定义了一个带剩余时间的紧凑组件但**从未被使用**，是死代码。

**共用组件**

`ChargingLiveProgressBar`（403-418）：`Capsule` 轨道 `chargingProgressTrackColor`（暗 白16% / 亮 黑12%）+ `Capsule` 进度恒 green，宽度 `max(width * clamp(value,0,1), 8)` —— **0% 时也有 8pt 的绿点**，与 1.1 的 `BatteryProgressBar` 同一个规则。

`ChargingRemainingText`（335-358）：

```swift
TimelineView(.periodic(from: Date(), by: 30)) { context in Text(remainingText(now: context.date)) }

remainingText(now:):
  estimatedFullAt == nil        → "--"
  remainingSeconds <= 0         → "0分"
  totalMinutes = max(ceil(remainingSeconds/60), 1)
  hours > 0                     → "{hours}:{minutes 补零两位}"      例 "2:05"
  否则                          → "{minutes}分"                    例 "45分"
```

**这是本地插值，不消耗网络也不需要推送**：`estimatedFullAt` 是个绝对时刻，界面每 30 秒重算一次剩余。

格式化兜底（456-478），注意**单位前没有空格**，与 App 侧的 `"-- W"` / `"-- V"` / `"-- °C"` 不同：

| 函数 | 行号 | 有值 | 兜底 |
| --- | --- | --- | --- |
| `chargingRangeText` | 457-460 | `"{整数}km"` | `"--km"` |
| `chargingPowerText` | 463-466 | `"{整数}W"` | `"--W"` |
| `chargingTemperatureText` | 469-472 | `"{整数}°C"` | `"--°C"` |
| `chargingSpeedText` | 475-478 | `"{整数}km/h"` | `"--km/h"` |

四个都走 `formatWidgetNumber(..., maximumFractionDigits: 0)`。

#### 生命周期（`NinebotChargingLiveActivityManager.swift`）

`sync(with:)`（:30-96）的启动条件：

```
1. ActivityAuthorizationInfo().areActivitiesEnabled == false → endAll()
2. guard primaryVehicle != nil
        && state.isCharging == true
        && !state.isFullyCharged
        && state.battery != nil                              → 否则 endAll()
3. 构造 attributes + ContentState + ActivityContent(state:staleDate:)
4. 单车约束：activities 里找 attributes.vehicleSN 匹配的那个
   其余全部 activity.end(content, dismissalPolicy: .immediate)
5. 有匹配 → matchingActivity.update(content)
   没有   → Activity.request(attributes:content:pushType:.token)
```

`staleDate(for:)`（:110-115）：`estimatedFullAt` 在未来 → `estimatedFullAt + 5 分钟`；否则 → `now + 60 分钟`。

`endAll()`（:98-103）：全部 `end(nil, dismissalPolicy: .immediate)`，**立即消失，不留残影**。

三个调用点：`NinebotViewModel.swift:548`（每次 `saveDashboard`）、`NinebotBackgroundTaskManager.swift:69`（后台刷新成功后）、`NinebotAppIntents.swift:394`。

`pushType: .token`（:85）+ `NinebotChargingLiveActivityTokenObserver`（:119-202）：注册 per-activity push token 与 push-to-start token 到服务端，由 APNs 推送更新活动内容。**Android 侧整块不移植**（已定不做推送）。

#### 状态判定已经抽好了，不要重新推导

`Shared/NinebotChargingStatus.swift`（112 行）四个枚举 + 六个派生属性：

| 枚举 | 行号 | 说明 |
| --- | --- | --- |
| `NinebotPowerStatus` | 9-17 | `fullyCharged` / `charging` / `offline` / `poweredOn` / `poweredOff`，**顺序是承重的** |
| `NinebotChargingState` | 20-26 | `fullyCharged` / `charging` / `notCharging` / `unknown` |
| `NinebotChargeEstimate` | 29-42 | `notCharging` / `calculating` / `reached` / `minutes(Double)` |
| `NinebotChargeClock` | 45-51 | `unavailable` / `reached` / `at(Date)` |

`fullChargeEstimate`（:68-70）→ `chargeEstimate(isCharging:minutes:)`（:106-111）：`isCharging != true` → `.notCharging`；`minutes == nil` → `.calculating`；`minutes <= 0` → `.reached`；否则 `.minutes(m)`。

边界行为由 `Tests/NineBotCoreTests/ChargingStatusTests.swift`（183 行）钉住。三条与 5.5 直接相关：

- `testEstimateIsCalculatingWithoutAMinuteFigure`（:100-104）：充电中但 `battery == nil` → `.calculating`。这种状态下 iOS 的活动**根本不会启动**（`sync` 的第 2 步要求 `battery != nil`），所以 `.calculating` 在实时活动里不可达。
- `testEstimateIsReachedAtTheTarget`（:106-111）：`battery == 100` 且充电中 → `.reached`。同样不可达（`!isFullyCharged` 已挡）。
- `testStaleServerTimestampReadsAsFullyCharged`（:168-175）：**服务端给的充满时刻是和「现在」比的，不是和 `updatedAt` 比的**。一份放久了的缓存快照会在 50% 电量时报「已充满」。见 `pending-decisions.md` 的 D9。社区服务端不返回预测，现在触发不到，但换服务端后 5.5 会第一个撞上 —— **前台服务每分钟读一次快照，快照本身却是几分钟前的，这正是 D9 最容易发作的场景**。

### 二 · 要移植的逻辑

#### 2.1 启停条件（照抄，不重新推导）

```
启动/更新：primaryVehicle != null
        && isCharging == true
        && !isFullyCharged
        && battery != null
结束：以上任一不成立
```

Android 侧直接用 Phase 2 产出的 `ChargingState` / `ChargeEstimate`，判定写成：

```kotlin
fun shouldRunChargingActivity(m: VehicleSnapshot?): Boolean =
    m != null && m.state.chargingState == ChargingState.Charging && m.state.battery != null
```

`ChargingState.Charging` 已经排除了 `fullyCharged`（`NinebotChargingStatus.swift:62-66`：`isFullyCharged` 先返回 `.fullyCharged`），所以不需要再写 `&& !isFullyCharged`。**但要在测试里钉住这一点**，否则以后有人改了枚举顺序，充满的车会一直挂着通知。

#### 2.2 每个字段的取值链与兜底

| 通知上的位置 | 数据 | 兜底 |
| --- | --- | --- |
| 主标题的电量 | `battery`（非空保证） | 无 |
| 续航 | `localEstimatedMileage ?? endurance ?? aiEstimatedMileage` | `"--km"` |
| 剩余时间 | 从 `estimatedFullAt` 现算，见 2.3 | `"--"` |
| 功率 | `chargingPower` | `"--W"` |
| 温度 | `batteryTemperature` | `"--°C"` |
| 充电速度 | `estimatedChargingSpeedKmh` | `"--km/h"` |
| 进度条 | `battery / 100`，最小可见宽 8dp | — |
| 车名 | `attributes.vehicleName` | 无（`NinebotVehicleInfo.name` 本身非可选） |
| 更新时刻 | `updatedAt` → `"HH:mm"` Asia/Shanghai | — |

`estimatedFullAt` 的算法（`NinebotChargingLiveActivityManager.swift:105-108`）：`estimatedFullChargeMinutes > 0` 时取 **`Date() + minutes*60`**，注意基准是**调用时刻**而不是 `updatedAt`。Android 侧照抄这个基准（即前台服务每轮算一次 `now + minutes*60`），否则剩余时间会随快照变旧而不动。

#### 2.3 剩余时间文案（照抄）

```kotlin
fun remainingText(estimatedFullAt: Instant?, now: Instant): String {
    if (estimatedFullAt == null) return "--"
    val seconds = Duration.between(now, estimatedFullAt).seconds
    if (seconds <= 0) return "0分"
    val total = maxOf(ceil(seconds / 60.0).toInt(), 1)
    val h = total / 60
    val m = total % 60
    return if (h > 0) "$h:${m.toString().padStart(2, '0')}" else "${m}分"
}
```

三个边界：`0 秒` → `"0分"`（不是 `"0:00"`）；`1 秒` → `"1分"`（`ceil` + `max(...,1)`）；`60 分整` → `"1:00"`。

#### 2.4 三种呈现的字段对照

| 字段 | 紧凑态左 | 紧凑态右 | 最小态 | 展开态 | 锁屏卡片 |
| --- | --- | --- | --- | --- | --- |
| 闪电图标 | ✅ | — | ✅ | ✅（在"充电中"Label 里） | ✅ |
| 电量百分比 | — | ✅ | — | ✅ 24pt | ✅ 38pt |
| 车名 | — | — | — | ✅ | ❌ |
| 续航 | — | — | — | ✅ caption | ✅ 31pt |
| 剩余时间 | — | — | — | ✅ 22pt | ✅ 29pt |
| 进度条 | — | — | — | ✅ height 5 | ✅ height 6 |
| 功率/温度/速度 | — | — | — | ✅ 短标签 | ✅ 长标签 |
| 电池图标 | — | — | — | ❌ | ✅ 右上角 |
| 更新时刻 | — | — | — | ❌ | ❌ |

**`updatedAt` 进了 `ContentState` 但界面一处都没显示。** Android 侧建议**显示**它（通知的 `setSubText` 或 `setWhen`），因为本地轮询失败时用户需要知道数据有多旧 —— iOS 靠 `staleDate` 让系统把活动变灰，Android 没有这个机制。这是主动增强，在 plan 里记一笔。

#### 2.5 已定：不做推送，改前台服务本地轮询

`pending-decisions.md:157` 与 `android-implementation-plan.md:7`：Phase 1 不做推送。`android-porting-plan.md:134-135` 已写明做法：「充电时起一个前台服务，自己每分钟拉一次并更新通知，岛就随之更新。**本地通知足以驱动 `ProgressStyle` 和 `miui.focus.param`**」。

对应关系：

| iOS | Android |
| --- | --- |
| `Activity.request(pushType: .token)` | 起前台服务 + `notify(id, notification)` |
| APNs 推送 `ContentState` | 前台服务轮询后重新构建同一个 id 的通知 |
| `matchingActivity.update(content)` | `notify` 同一个 id（覆盖） |
| `activity.end(nil, .immediate)` | `stopForeground(STOP_FOREGROUND_REMOVE)` + `cancel(id)` |
| `staleDate` | 无对应物，改为在通知里显示 `updatedAt` |
| `TimelineView(.periodic(by: 30))` 本地插值 | `setWhen` + `setUsesChronometer(true)` + `setChronometerCountDown(true)`，让系统自己倒计时；见 3.6 |
| per-activity push token / push-to-start token | 不移植 |

#### 2.6 轮询间隔与 5.4 的关系

| 链路 | iOS 充电中的节奏 | Android |
| --- | --- | --- |
| 后台刷新 | 15 分钟（`NinebotBackgroundTaskManager.swift:96-98`） | 5.4 的 WorkManager，**充电期间让位** |
| Widget timeline | 3 分钟（`NinebotWidgetProvider.swift:47`） | 不保留，见 5.3 三 3.6 |
| Live Activity 内容 | APNs 推送（服务端决定） | **前台服务轮询，60 秒** |
| 剩余时间文本 | 每 30 秒本地重算，零网络 | 系统 chronometer 自动倒计时，零网络 |

**60 秒的依据与代价**：沿用 `android-porting-plan.md:135` 的既有写法。充电轮询只拉 `GET /vehicles/{sn}/dashboard` 单个请求（与 1.3 磁贴同一口径，见 `pending-decisions.md` 的 D1），4 小时充电 = 240 个请求 ≈ 1.2 MB。如果按完整 `fetchDashboard` 走（`GET /vehicles` + 每车 dashboard + 月度行程，`NinebotServerClient.swift:80-163`），同样 4 小时会变成 480 个以上的请求。**必须走单车路径。** 是否把 60 秒放宽见 `## 待定` 的 C2。

**5.4 让位的机制**：前台服务运行期间，5.4 的周期 Worker 检测到服务在跑就直接 `Result.success()` 返回、不发请求。理由不只是省流量 —— 两条链路都写同一份快照会打乱 0.3 的历史点去重规则（`shouldAppend`：数值相同时 60 秒内与 300 秒内都跳过，`phase0-foundation-spec.md:185`），出现历史曲线上莫名的疏密不均。判定用一个 `MutableStateFlow<Boolean>` 放在 Application 作用域的单例里即可，不要用 `ActivityManager.getRunningServices`（API 26+ 已只返回自己的服务，但语义不清且有延迟）。

#### 2.7 结束条件

| 触发 | iOS | Android |
| --- | --- | --- |
| `isCharging != true` | `endAll()` 立即消失 | 停服务 + `cancel(id)` |
| `isFullyCharged` | 同上 | 同上，但是否留一条「已充满」通知见 `## 待定` C5 |
| `battery == null` | 同上 | 同上 |
| 系统关闭了实时活动权限 | `areActivitiesEnabled == false` → `endAll()` | 通知权限被拒 → 服务起不来，要在设置页给引导（0.6 已有权限引导框架） |
| 刷新失败 | **不结束**，活动保持旧内容直到 `staleDate` | 不结束，但通知里的 `updatedAt` 会显出来数据变旧 |
| 用户划掉通知 | 不适用（Live Activity 只能长按结束） | **Android 13+ 用户可以划掉前台服务通知**。挂 `setDeleteIntent`，收到就 `stopSelf()` —— 用户划掉就是不想看了，别再弹回来 |
| 前台服务超时 | 不适用 | Android 15+ `dataSync` 每 24 小时累计 6 小时配额，见 3.5 |

### 三 · Android 实现要点

#### 3.1 三条路径分层

**一条通知，三层装饰，按能力叠加。** 不是三套互斥实现 —— `ProgressStyle` 与 `miui.focus.param` 挂在同一个 `Notification` 上互不冲突：AOSP 忽略 extras，HyperOS 忽略它不认的 style。

```kotlin
fun buildChargingNotification(ctx: Context, m: ChargingModel): Notification {
    val b = baseBuilder(ctx, m)                     // 路径 C：所有设备都吃
    if (Build.VERSION.SDK_INT >= 36) applyProgressStyle(b, m)   // 路径 A
    val n = b.build()
    if (isHyperOS()) n.extras.putString("miui.focus.param", focusParamJson(m))  // 路径 B
    return n
}
```

| 条件 | 生效的层 | 预期效果 |
| --- | --- | --- |
| API ≥ 36 | C + A | 原生 Android 16：通知抽屉里的进度条与 tracker 图标；OPPO ColorOS 16 流体云 |
| `Build.MANUFACTURER == "Xiaomi"`（或 Redmi/POCO） | C + A（若 API 36）+ B | HyperOS 3 超级岛 / HyperOS 2 焦点通知 |
| 其余（API 33–35） | C | 常驻进度通知 |

厂商判定用 `Build.MANUFACTURER` / `Build.BRAND`，**不要反射 `android.os.SystemProperties.get` 去读 `ro.miui.ui.version.code`** —— 它在受限名单上。同时在设置页给一个「小米超级岛（实验）」开关，默认按厂商自动开、允许手动关，这样实测不生效时用户能自己关掉。

#### 3.2 路径 A · 标准 `Notification.ProgressStyle`（API 36）

已核对 Android 官方文档确认的 API：`Notification.ProgressStyle` 在 **Android 16（API 36）** 引入，方法为 `setStyledByProgress(boolean)`、`setProgress(int)`、`setProgressTrackerIcon(Icon)`、`setProgressSegments(List<Segment>)`、`setProgressPoints(List<Point>)`，嵌套类 `Notification.ProgressStyle.Segment(length)` 与 `Notification.ProgressStyle.Point(position)`，两者都有 `setColor(int)`。段长之和构成总量，`setProgress` 与段长同单位。

```kotlin
@RequiresApi(36)
private fun applyProgressStyle(b: Notification.Builder, m: ChargingModel) {
    b.setStyle(
        Notification.ProgressStyle()
            .setStyledByProgress(false)
            .setProgress(m.battery)                                  // 0..100
            .setProgressTrackerIcon(Icon.createWithResource(ctx, R.drawable.ic_bolt))
            .setProgressSegments(listOf(
                Notification.ProgressStyle.Segment(80).setColor(GREEN),   // 快充段
                Notification.ProgressStyle.Segment(20).setColor(AMBER),   // 涓流段
            ))
    )
}
```

80/20 的分段正好对上 `fastChargeUpperBound = 80.0`（`NinebotModels.swift:1548`）与 `fastMinutesPerPercent = 4.0` / `taperMinutesPerPercent = 7.0`（:1549-1550）。**iOS 侧没有这个视觉表达，加不加见 `## 待定` C4。** 不加就用单段 `Segment(100)`。

**要在开工第一天核对的一件事**：让通知晋升为 Live Update（状态栏/岛上常驻）需要额外条件，Android 16 文档里叫 promoted visibility，涉及一个 Builder 上的「请求晋升」开关、一个状态栏短文本，以及 `NotificationManager` 上的一个能力查询。**本规格没有核实到方法级，不要照本文猜方法名** —— 打开 API 36 的 `Notification.Builder` 与 `NotificationManager` 参考页逐个确认后再写，并把确认结果补回本节。已知的是：`setStyle(ProgressStyle)` 本身只保证通知抽屉里的进度呈现，不保证晋升。

API 33–35 的降级：`Build.VERSION.SDK_INT < 36` 时不设 `ProgressStyle`，落到路径 C 的 `NotificationCompat.Builder.setProgress(100, battery, false)`。**这意味着原生 Android 13/14/15 上「充电实时活动」的实际形态就是一条常驻进度通知**，没有岛、没有状态栏 chip。这是 minSdk 33 的必然结果，验收口径见 `## 待定` C3。

#### 3.3 路径 B · 小米 `miui.focus.param`

调研结论直接引用 `android-porting-plan.md:246-267` 与 `:298-303`，本节不重新调研，只把数值抄准：

| 项 | 约束 |
| --- | --- |
| 挂载方式 | 原生 `Notification` 的 `extras.putString("miui.focus.param", json)`，然后 `notificationManager.notify(id, notification)`。NotificationCompat 侧用 `Builder.addExtras(bundle)` 等价 |
| JSON 根节点 | **`param_v2`**，内含交互能力 / 大岛内容 / 小岛内容 / 通知内容四部分 |
| payload 上限 | **不超过 3072 字节** |
| 图片 | key 前缀 `miui.focus.pic_*`，值是 **HTTPS URL**；单张 **≤100KB**；宽高比在 **1:1 到 16:9** 之间；单条通知最多 **10 张**；图片参数整体 **≤1024 字节** |
| 锁屏 / AOD | `aodTitle` / `aodPic` |
| 状态栏 | `ticker` / `tickerPic` |
| 岛的可用性 | HyperOS 2 = 焦点通知；**超级岛只在 HyperOS 3 上有**，两者模板不同 |
| 资质 | 焦点通知需向小米申请，邮件 `mipush-permission@xiaomi.com`；系统里存在 `hasFocusPermission()` 查询接口，权限位是用户开关还是应用白名单公开文档没讲清 |
| 可用轮子 | Kotlin DSL 库 [HyperIsland-ToolKit](https://github.com/D4vidDf/HyperIsland-ToolKit)，封装 20+ 模板（含进度条、计时器），自动处理 `miui.focus.pic_` 前缀 |

字段映射（沿用 `android-porting-plan.md:275-280` 的进度条模板方案）：

| 位置 | 内容 | 数据 |
| --- | --- | --- |
| 小岛（收起态） | 闪电图标 + 电量百分比 | 对应 iOS 的 `compactLeading` + `compactTrailing` |
| 大岛（展开态） | 进度条 + 剩余时间 + 充电功率 | 对应 iOS 的展开态，但**只有三项** —— iOS 展开态有车名、续航、进度条和三个指标共六项，超级岛模板塞不下 |
| 锁屏 / AOD | `aodTitle` = 电量 + 续航 + 预计充满时刻 | `estimatedFullChargeClockText` 逻辑（`NinebotModels.swift:1177-1183`） |
| 状态栏 ticker | 电量百分比 | |

**payload 预算**：我们的内容全是文本（车名、电量、剩余、功率、温度、速度、时刻），UTF-8 下几百字节，离 3072 很远。**图片是唯一有风险的部分**：车图要走 HTTPS 且 ≤100KB，而自建服务端可能跑在 HTTP 上（`Info.plist` 开了 `NSAllowsArbitraryLoads`，见 `android-porting-plan.md:230`），九号云返回的 `imageURLString` 协议也不受我们控制。**结论：路径 B 不带车图**，只用文本 + 本地图标资源。这样也顺带绕开 1024 字节的图片参数预算。

**关键未知（阻塞性）**：超级岛是否接受本地通知驱动，还是必须走 MiPush 服务端下发。见 `## 待定` C1，含验证步骤。

#### 3.4 路径 C · 兜底普通通知

```kotlin
private fun baseBuilder(ctx: Context, m: ChargingModel) =
    NotificationCompat.Builder(ctx, CHANNEL_CHARGING)
        .setSmallIcon(R.drawable.ic_bolt)
        .setContentTitle("充电中 · ${m.battery}%")                 // 对齐 iOS 的 Label("充电中")
        .setContentText("${m.rangeText} · 剩余 ${m.remainingText}")
        .setSubText("${m.updatedAtText} 更新")
        .setProgress(100, m.battery, false)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setSilent(true)
        .setColor(GREEN).setColorized(false)
        .setContentIntent(mainActivityPendingIntent(ctx))
        .setDeleteIntent(stopServicePendingIntent(ctx))            // 用户划掉 → 停服务
```

渠道：id `charging_live`，名称「充电实时活动」，`IMPORTANCE_DEFAULT`。用 `IMPORTANCE_LOW` 会更安静，但低于 DEFAULT 的渠道基本不可能被系统晋升成 Live Update，所以选 DEFAULT + 通知级 `setSilent(true)` + `setOnlyAlertOnce(true)` 来做到「不响但可晋升」。**这个渠道与 1.3 的 `tile_feedback`（`IMPORTANCE_LOW`）必须分开**，不要共用。

通知不能像锁屏卡片那样放三个指标格 + 渐变 + 大字号。折衷：标题带电量，正文带续航和剩余，`setSubText` 带更新时刻，功率/温度/速度放进 `NotificationCompat.BigTextStyle` 的展开文本里，一行 `"功率 380W · 温度 28°C · 速度 12km/h"`（单位格式照抄 §一 的四个 `chargingXxxText`，**单位前无空格**）。iOS 卡片的渐变和圆角在通知里做不到，不要用自定义 `RemoteViews` 去硬做 —— 各 ROM 的通知模板差异大，自定义布局是最容易在国产 ROM 上崩形的一条路。

#### 3.5 前台服务

```
manifest:
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
  <service android:name=".charging.ChargingActivityService"
           android:foregroundServiceType="dataSync"
           android:exported="false" />
```

| 项 | 做法 |
| --- | --- |
| 谁起它 | 5.4 的 Worker 或主 App 刷新成功后，命中 §2.1 的条件就 `startForegroundService`。对应 iOS 那三个 `sync` 调用点（`NinebotViewModel.swift:548`、`NinebotBackgroundTaskManager.swift:69`、`NinebotAppIntents.swift:394`） |
| 循环 | `while (isActive) { poll(); delay(60_000) }`，`poll()` 只拉 `GET /vehicles/{sn}/dashboard`，用 1.3 的 8/12 秒 client |
| 每轮做什么 | 写快照仓库 → 重算 `estimatedFullAt = now + minutes*60` → `notify(NOTIF_ID, build(...))` → `refreshWidgets(context)`（5.3 的出口） |
| 失败 | 不停服务、不改通知的数据部分，只让 `updatedAt` 显出来变旧；连续失败次数写进诊断（5.1） |
| 停 | §2.7 六种触发；`stopForeground(STOP_FOREGROUND_REMOVE)` + `cancel(NOTIF_ID)` + `stopSelf()` |
| 配额 | **Android 15+ 起 `dataSync` 前台服务每 24 小时累计上限 6 小时**，到点系统回调 `Service.onTimeout(...)`，必须在其中自行 `stopSelf()`，否则被判 ANR。回调的确切签名（API 34 的单参数版与 API 35 的双参数版）开工时核对文档 |
| 超时降级 | 充电通常 2–4 小时，在配额内。但「充电中断电又插上」会反复起停累计时长。做法：`onTimeout` 里停服务、把通知换成一条非前台的普通进度通知（内容不再更新，标题加「已停止跟踪」），并把剩余的刷新交回 5.4 的 15 分钟周期 |
| 国产 ROM | WorkManager 与前台服务都会被小米/华为/OPPO 的后台管控掐。0.6 已有电池优化白名单引导页，5.5 的设置项里要能直接跳到那一页 |

#### 3.6 自更新倒计时

iOS 的 `TimelineView(.periodic(by: 30))`（`NinebotWidgets.swift:339`）让剩余时间每 30 秒自己重算，不消耗网络也不需要重发通知。Android 的等价物是通知自带的计时器：

```kotlin
b.setWhen(estimatedFullAtMillis)
 .setUsesChronometer(true)
 .setShowWhen(true)
// setChronometerCountDown(true) 让它倒着走
```

这样即使 60 秒才轮询一次，用户看到的剩余时间也是逐秒（或逐分）在动。**但要实测**：chronometer 占用的是通知的 `when` 位置，与 `ProgressStyle` 和各 ROM 的岛模板是否兼容、是否会被岛模板忽略，都得在真机上看。若不兼容，退回「每分钟重发一次通知」—— 一分钟一次的 `notify` 远低于系统的通知频率限制，可以接受，只是多一次 IPC。

超级岛侧不用这个：`param_v2` 模板自带计时器能力（`android-porting-plan.md:267` 提到 HyperIsland-ToolKit 封装了「进度条、计时器」模板），把 `estimatedFullAt` 交给模板即可。

### 四 · 陷阱

1. **`estimatedFullAt` 的基准是「现在」不是 `updatedAt`**（`NinebotChargingLiveActivityManager.swift:105-108`）。前台服务每轮必须重算，不能算一次存起来。

2. **D9 在 5.5 上最容易发作。** 服务端给的充满时刻是和「现在」比的：`serverRemainingChargeMinutes`（`NinebotModels.swift:1607-1613`）在 :1610 用 `estimatedFullAt.timeIntervalSinceNow / 60`，不是和 `updatedAt` 相减。一份放久了的快照，若它记录的预计充满时刻已经过去，剩余分钟数算成 0 → `fullChargeEstimate` 报 `.reached` → 界面报「已充满」，**即使电量只有 50%**。于是 §2.1 的条件里 `isFullyCharged` 变真 → **服务把自己停了**。社区服务端不返回预测所以现在触发不到，换服务端后会。测试里造一份「`estimatedFullAt` 在过去、battery 50%、isCharging true」的快照，钉住 Android 的行为。

3. **`battery` 在 `ContentState` 里是非可选的 `Int`**（`NinebotChargingActivityAttributes.swift:13`），靠 `sync` 的 guard 保证。Android 侧的 `ChargingModel.battery` 也要用非空 `Int`，把可空性挡在服务启动条件里，别一路带着 `Int?` 到通知构建函数。

4. **Android 13+ 用户可以划掉前台服务通知，服务却还在跑。** 不挂 `setDeleteIntent` 的话会得到「一个看不见的、每分钟发请求的服务」。这是最容易漏的一条。

5. **两套指标标签并存**：锁屏卡片是「充电功率/电池温度/充电速度」，展开岛是「功率/温度/速度」。Android 的通知正文用长的，超级岛大岛用短的。别统一。

6. **实时活动的单位格式与 App 内不同。** 这里是 `"--W"` / `"--°C"` / `"--km/h"` / `"--km"`，值形式是 `"380W"` —— **数字与单位之间没有空格**。App 内的同类属性带空格且兜底文案完全不同：`chargingPowerText` → `"{n} W"` / `"接口未返回"`，`batteryVoltageText` → `"{x.x} V"` / `"接口未返回"`，`batteryTemperatureText` → `"{x.x} °C"` / `"接口未返回"`（`NinebotModels.swift:1047-1065`）。两套都要留，别在格式化层合并。

7. **`batteryVoltage` 和 `vehicleModel` 进了数据契约但界面不用。** 别为了「字段齐全」在通知上硬塞一个电压 —— 那会与 iOS 不一致。

8. **`ChargingCompactRemainingText`（324-333）是死代码。** 紧凑态只有闪电和百分比，不要因为看到这个组件就在小岛上加剩余时间。

9. **进度条 0% 时也要有 8dp 的可见宽度**（`NinebotWidgets.swift:414`）。`NotificationCompat.setProgress(100, 0, false)` 会显示完全空的条 —— 系统模板控制不了，接受；但路径 B 的超级岛模板若能控制，按 8dp 下限来。

10. **不做推送意味着 App 被彻底杀死后活动不会自己启动。** iOS 有 push-to-start（`NinebotChargingLiveActivityManager.swift:166-179`），Android 侧没有等价物。用户插上充电器但 App 已被杀 → 没有通知，直到用户打开 App 或 5.4 的 Worker 被系统调起。这是已定决策的必然代价，要在设置页说清楚，别当 bug 修。

11. **一辆车一条通知，通知 id 用固定值而不是按 SN 哈希。** iOS 的单车约束（`NinebotChargingLiveActivityManager.swift:64-76`）是「只保留匹配 `vehicleSN` 的那一个活动，其余 `.immediate` 结束」。Android 侧用固定 `NOTIF_ID` 天然满足；换车时同一个 id 直接被覆盖。用按 SN 生成的 id 会在多车切换时留下孤儿通知。

12. **`Notification.extras` 是在 `build()` **之后**改的**（`android-porting-plan.md:253-256`）。写在 `Builder` 上的 `addExtras` 也可以，但两种写法混用时后者会被 `build()` 里的默认 extras 覆盖一部分。挑一种，建议照调研文档的写法：`build()` → `extras.putString` → `notify`。

### 五 · 验收标准

**通用（所有设备）**

- [ ] 造四组快照：`(charging, 50%)` / `(charging, battery=null)` / `(charging, 100%)` / `(notCharging, 50%)`。只有第一组会起服务，其余三组服务不起或立即停
- [ ] 剩余时间文案边界：`estimatedFullAt = null` → `"--"`；剩 0 秒 → `"0分"`；剩 1 秒 → `"1分"`；剩 60 分 → `"1:00"`；剩 125 分 → `"2:05"`
- [ ] 四种兜底 `"--km"` / `"--W"` / `"--°C"` / `"--km/h"` 各出现一次并截图（**确认无空格**）
- [ ] 前台服务运行期间，5.4 的周期 Worker 不发网络请求（抓包验证）
- [ ] 60 秒轮询：MockWebServer 上 4 分钟内收到 4 个 `GET /vehicles/{sn}/dashboard`，**没有** `GET /vehicles`
- [ ] 轮询失败三次：通知内容不变、`updatedAt` 仍显示最后成功时刻、服务不停
- [ ] 划掉通知 → 服务在 2 秒内停止（`adb shell dumpsys activity services` 验证）
- [ ] 电量走到 100% → 通知消失（或按 C5 的结论显示「已充满」）
- [ ] 拔掉充电器 → 下一轮轮询后通知消失
- [ ] 通知不发声不震动（`setSilent` + `setOnlyAlertOnce` 生效），连续 60 次更新都不响
- [ ] 服务运行期间 widget 的更新时间跟着走（5.3 与 5.5 的耦合点）
- [ ] `adb shell am kill <pkg>` 杀掉 App：服务被拉起或通知消失，不留一条永不更新的僵尸通知
- [ ] 手动把系统时间往后拨 7 小时模拟配额耗尽，`onTimeout` 被调用、服务自停、通知换成「已停止跟踪」
- [ ] 拒绝通知权限时设置页有明确引导，且服务不会崩

**原生 Android 16（Pixel，API 36）**

- [ ] 通知抽屉里 `ProgressStyle` 进度条随电量变化，tracker 图标在正确位置
- [ ] 若分段方案采纳（C4）：80% 处能看到快充段与涓流段的颜色分界
- [ ] 晋升为 Live Update 后状态栏出现常驻标记（**前置：3.2 的 promoted visibility API 已核对并实现**）

**原生 Android 13 / 14 / 15**

- [ ] 常驻进度通知存在，进度随电量变化，`BigTextStyle` 展开后能看到功率/温度/速度
- [ ] 不因为缺少 `ProgressStyle` 而崩或降级成空通知

**OPPO ColorOS 16**

- [ ] 流体云显示充电进度，**未写任何 OPPO 专有代码**（验证 `android-porting-plan.md:290` 的结论）
- [ ] 流体云上的电量与通知里的电量一致

**小米 HyperOS**〔小米〕

- [ ] 〔小米〕HyperOS 3：超级岛出现；小岛显示闪电 + 电量百分比；大岛显示进度条 + 剩余时间 + 充电功率
- [ ] 〔小米〕锁屏 / AOD 显示 `aodTitle`（电量 + 续航 + 预计充满时刻）
- [ ] 〔小米〕状态栏 `ticker` 显示电量百分比
- [ ] 〔小米〕HyperOS 2：焦点通知出现（无岛），内容不缺字段
- [ ] 〔小米〕`miui.focus.param` 实测字节数 < 3072（打日志记录实际值）
- [ ] 〔小米〕设置页的「小米超级岛（实验）」开关关掉后，退化成路径 A/C 且不崩

**其他 ROM（至少一台）**

- [ ] 三星 / vivo / 华为任一台上路径 C 表现正常，通知常驻、不崩、能划掉

---

## 待定

需要人拍板的项。每条写清现状、iOS 怎么做的、分歧点、建议决定时机。

### W1 · Glance 画不出电量环，选哪条变通路

**现状**：`SmallWidgetBatteryRing`（`NinebotWidgets.swift:577-610`）是 30×30 的圆环，`Circle().trim().stroke(lineWidth:5, lineCap:.round)` 加中心挖洞。Glance 没有 `Canvas`、没有 `drawArc`、`CircularProgressIndicator` 只有不确定态转圈。

**iOS 的行为**：Small 档是环形，Medium/Large 是线性条。

**分歧点**：三条路的代价见 §5.3 三 3.3 的表。A（预渲染 Bitmap）视觉最接近但引入位图内存与 Binder 事务两个风险，且每次电量变化都要重画；B（降级成线性条）零风险、与已定决策「电量显示照抄 iOS 的线性细长条」（`pending-decisions.md:168`）自洽，但 Small 档与 iOS 视觉不同；C（多个 `Box` 拼）拼不出圆头，不推荐。

**建议决定时机**：5.3 开工前。这条决定 Small 档的全部布局，不能边做边定。

**要问的**：Small 档你实际会用吗？只放 Medium/Large 的话这条自动消失（Medium/Large 本来就是线性条）。

### W2 · Widget 交互按钮要不要鉴权

**现状**：规格现在的写法是不鉴权，直接执行。

**iOS 的行为**：`OpenBucket` / `EngineStart` / `EngineStop` 三个 Intent 都有 `authenticationPolicy = .requiresAuthentication`（`NinebotWidgetControlIntents.swift:47/59/71`），`RingBell` 没有。

**分歧点**：已定的决策里有「磁贴控车鉴权：不要，设备解锁即可」（`pending-decisions.md:170`），但那是快捷设置磁贴 —— 磁贴要下拉通知栏才能点，桌面 widget 是**解锁后主屏上直接可点**，误触概率更高（一个 4×2 的 widget 上有三个按钮，其中一个是开锁）。而 Glance 的 `ActionCallback` 里弹不出 `BiometricPrompt`（没有 `FragmentActivity`），要鉴权只能拉一个透明 Activity，与 1.3 §陷阱 3 是同一套办法。

**建议决定时机**：5.3 开工时。做法差一个透明 Activity，工时差半天。

**要问的**：桌面上口袋误触不存在（屏幕是解锁后才响应的），但小孩拿手机、或者你自己点错格子这两种情况要不要防？

### W3 · Widget 上要不要显示车辆图片

**现状**：规格现在的写法是保留，Worker 里用 Coil 下到本地文件，`provideGlance` 只读文件。

**iOS 的行为**：Small 档 154×94 溢出裁切、Large 档 142×72（`NinebotWidgets.swift:525/881`），扩展里直接下载，上限 2.5 MB（`NinebotWidgetProvider.swift:128`）。

**分歧点**：位图进 `RemoteViews` 要过 Binder 事务与 `AppWidgetHostView` 的位图内存两道上限；如果 W1 又选了预渲染环形图的路，同一次更新里会有两张位图。砍掉车图能显著降低 5.3 的技术风险，代价是 Small 和 Large 少了主要的视觉元素（Small 档的车图占了右侧一半面积）。

**建议决定时机**：5.3 开工前，和 W1 一起定。

### W4 · 「守卫模式已开启」这条文案照抄不照抄

**现状**：规格现在的写法是照抄。

**iOS 的行为**：`MediumWidgetStatusPill.statusText`（`NinebotWidgets.swift:803`）在 `isLocked == true` 时显示「守卫模式已开启」，`isLocked == false` 时显示「车辆未上锁」。

**分歧点**：这个 App 里**没有任何叫「守卫模式」的功能** —— 全仓其他地方的锁车文案是「已上锁/已解锁」（chip）、「已锁/未锁」（详情行）、「已上锁/未上锁」（吸顶与 `widgetStatusText`）。这是第四套，而且引入了一个不存在的概念名。Widget 上换成「已上锁」就与 `widgetStatusText` 合流，少一套文案。

**建议决定时机**：5.3 实现 Medium 档时，顺手定。

### W5 · 锁屏 accessory ×3 的降级要不要提前

**现状**：`android-porting-plan.md:123` 与 Phase 3 排期把「锁屏 Widget 降级为常驻通知」放在 Phase 3。

**iOS 的行为**：`NinebotLockScreenWidget` 三档（circular / rectangular / inline），文案在 `accessoryRectangularText`（1322-1331）与 `compactWidgetStatus`（1312-1320）。

**分歧点**：5.5 做完之后，常驻通知的全套基础设施（渠道、前台服务、内容构建、更新链路）已经在手上了。这时候加一条「车况常驻通知」是 1–2 天，放到 Phase 3 单独做要重新搭一遍上下文。但它会引入第二条常驻通知，与充电通知同时存在时通知栏有两条。

**建议决定时机**：5.5 收尾时。

### W6 · Widget 的刷新频率

**现状**：规格现在的写法是完全跟随 5.4 的自适应间隔（充电 15 / 使用中 20 / 空闲 30 分钟），另加 `updatePeriodMillis = 1800000` 的 30 分钟心跳作为二次兜底。

**iOS 的行为**：Widget 有独立的一套五档间隔（充电 3 / 使用中 8 / 低电量 10 / 其他 20 / 无数据 30 分钟，`NinebotWidgetProvider.swift:45-51`），与后台刷新那套 15/20/30 并行存在。

**分歧点**：Android 的 `updatePeriodMillis` 下限是 30 分钟，做不出 3 分钟档；硬做两套只会得到两条互相打服务端的链路。跟随 5.4 的代价是充电中 widget 从 3 分钟变 15 分钟 —— 但 5.5 的前台服务在充电时会按分钟级顺手刷 widget，实际反而比 iOS 勤。真正变差的是「骑行中」这一档：iOS 8 分钟，Android 20 分钟。

**建议决定时机**：5.4 定间隔时一起定，两份规格要对齐。

**要问的**：骑行中你会去看桌面 widget 吗？会的话 5.4 的「使用中」档要从 20 分钟压到 10 分钟，代价是耗电。

### C1 · 小米超级岛是否接受本地通知驱动〔阻塞性〕

**现状**：规格按「接受」写的（路径 B 挂在本地通知的 `extras` 上）。

**iOS 的行为**：Live Activity 用 APNs 推送更新（`NinebotChargingLiveActivityManager.swift:85` 的 `pushType: .token`），也支持 push-to-start（:166-179）。

**分歧点**：`android-porting-plan.md:246-256` 记录的做法是本地通知 + `extras`，`:301` 又指出系统里存在 `hasFocusPermission()` 查询接口，说明确实有权限位，「它究竟是用户可开的开关还是小米下发的应用白名单，公开文档没讲清楚」。如果是白名单，本地通知路线走不通，只剩 MiPush 服务端下发 —— 而那要资质（`:300`：需提交通知触发场景截图、焦点通知设计效果图、交互设计、使用期限和使用声明，「面向正式产品，自用未上架的应用大概率走不通」），且与已定的「不做推送」冲突。

**怎么验证**（`:303` 已给方向，这里给可执行步骤）：

1. 写一个独立的 20 行 demo APK：一个按钮，点了就发一条带 `miui.focus.param`（`param_v2` 根节点、最简进度条模板）的本地通知。
2. 装到目标真机上（要确认是 HyperOS 3 才有超级岛，HyperOS 2 只有焦点通知），点按钮。
3. 三种结果分别怎么走：
   - **岛出来了** → 路径 B 可做，按本规格实现，资质申请转为「有则更好」。
   - **岛没出来，但焦点通知出来了** → 记录 HyperOS 版本；超级岛可能确实要 OS3，换机或降级到焦点通知形态。
   - **什么都没出来** → 反射探测 `NotificationManager.hasFocusPermission()` 看返回值；若为 false 则基本确认是白名单，路径 B 判定不可交付，5.5 缩到路径 A + C，工时从 7 天压到 4 天。
4. 无论结果如何，把 HyperOS 版本号、机型、`miui.focus.param` 实际字节数记进 plan。

**建议决定时机**：**5.5 开工前 2 周**。这是唯一会改变 5.5 交付范围和工时的未知，而且验证成本只有半天。

### C2 · 充电轮询间隔定多少

**现状**：规格按 60 秒写的，沿用 `android-porting-plan.md:135`。

**iOS 的行为**：Live Activity 的内容更新完全由服务端 APNs 推送决定，客户端不轮询；客户端侧只有后台刷新的 15 分钟（`NinebotBackgroundTaskManager.swift:96-98`）和 widget timeline 的 3 分钟（`NinebotWidgetProvider.swift:47`）。所以 iOS 没有一个可以直接抄的「轮询间隔」。

**分歧点**：60 秒 × 4 小时 = 240 个请求 ≈ 1.2 MB，对流量无所谓，对耗电有影响（每分钟唤醒一次 radio）。放宽到 3 分钟（对齐 iOS widget 那档）省三分之二的唤醒，代价是电量百分比最多滞后 3 分钟 —— 但剩余时间靠 chronometer 本地倒计时，滞后不明显。放宽到 5 分钟基本无感，因为电动车充电一个百分点通常要 4 分钟以上（`fastMinutesPerPercent = 4.0`，`NinebotModels.swift:1549`）。

**建议决定时机**：5.5 实现前台服务时。

**要问的**：按 `fastMinutesPerPercent = 4.0` 算，60 秒轮询里有四分之三的请求拿回来的是同一个百分比。3 分钟或 4 分钟是更贴合数据变化速率的选择，要不要改？

### C3 · 原生 Android 13/14/15 上「充电实时活动」算不算做完

**现状**：规格写的是落到路径 C（常驻进度通知），并把这条列进验收。

**iOS 的行为**：iOS 16.1 起全都有 Live Activity 和灵动岛（`NinebotWidgets.swift:16` 的 `#available(iOS 16.1, *)`），iOS 侧部署目标已是 26.5，实际上没有降级分支。

**分歧点**：Android 侧 `ProgressStyle` 要 API 36，而 minSdk 是 33（`pending-decisions.md:167`）。API 33–35 的设备上这一项的形态就是一条普通进度通知，没有岛、没有状态栏 chip。如果目标机型是小米，路径 B 能补上岛；如果是三星或原生且系统低于 16，就只有通知。这直接决定「5.5 做完了」这句话在你的机器上意味着什么。

**建议决定时机**：5.5 开工前。取决于你手上的机型和系统版本。

**要问的**：你的主力机是什么品牌、什么系统版本？如果是 HyperOS 3，路径 A 基本用不上，重心全在路径 B；如果是原生 Android 16，重心在路径 A，路径 B 可以不做。

### C4 · `ProgressStyle` 的分段要不要用来表达快充段与涓流段

**现状**：规格写的是分成 `Segment(80)` + `Segment(20)` 两段、不同颜色。

**iOS 的行为**：`ChargingLiveProgressBar`（403-418）是单色的一条，进度恒 green，**没有任何分段表达**。

**分歧点**：80/20 的分界正好对上领域层已有的 `fastChargeUpperBound = 80.0` 与 `fastMinutesPerPercent = 4.0` / `taperMinutesPerPercent = 7.0`（`NinebotModels.swift:1548-1550`），能让用户直观看到「过了 80% 会变慢」。但这是 Android 独有的新增表达，两端视觉不一致；而且社区服务端不返回预测时这两个常数就是本地兜底值，颜色分界会显得比实际更精确。

**建议决定时机**：5.5 实现路径 A 时。不采纳就用单段 `Segment(100)`，改动一行。

### C5 · 充满后要不要留一条「已充满」通知

**现状**：规格写的是照抄 iOS，立即消失。

**iOS 的行为**：`endAll()`（`NinebotChargingLiveActivityManager.swift:98-103`）用 `dismissalPolicy: .immediate` 立即结束，不留残影。

**分歧点**：iOS 那样做是因为 Live Activity 结束后还会在锁屏留一段时间（系统行为），用户有机会看到。Android 的通知一取消就彻底没了 —— 用户睡前插上充电器，早上醒来什么都看不到，不知道几点充满的。留一条可滑掉的普通通知（`setOngoing(false)` + `setAutoCancel(true)`，内容「已充满 · HH:mm 完成」）成本很低。但这是新增行为，两端不一致。

**建议决定时机**：5.5 收尾时。

**要问的**：你会想知道「几点充满的」吗？想的话留一条；不想的话照抄 iOS。
