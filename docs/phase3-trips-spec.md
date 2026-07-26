# Phase 3 · 行程 详细规格

2 周，累计到第 11 周。做完这四项，行程 Tab 与 iOS 功能对等：能按月拉取九号云归档的行程、看单次行程详情、看里程柱状图、看那套中文洞察。

数据全部来自九号云（服务端代拉），**手机不用开着**，与 Phase 4 的本地 GPS 记录是两条独立数据源。

目录约定延续 Phase 0：

```
android/
  core/domain/trip/     TripTrend / TripInsight / RideIdentity / TripMonth（3.1 键、3.4 规则）
  core/storage/         InterfaceRideEntity + InterfaceRideDao（3.1）
  core/data/            TripRepository / RideDetailRepository（3.1、3.2）
  feature/trips/        TripsScreen / TripListSection / TripMonthFilterPanel
                        TripTrendScreen / TrendBarChart / RideDetailScreen（3.1–3.4）
```

---

## 依赖与并行

### 本阶段依赖什么

| 依赖 | 来自 | 用在哪 | 缺了会怎样 |
| --- | --- | --- | --- |
| `JsonElement` 宽松取值扩展（`stringValue`/`doubleValue`/`intValue`/`boolValue`） | Phase 0 · 0.1 | 3.1 行程记录解析、3.2 详情解析、去重键 | 3.1/3.2 全部无法开工 |
| 多键名取值 `firstString/firstDouble/firstDate` + `Asia/Shanghai` 日期解析 | Phase 0 · 0.2 | 同上 | 同上 |
| Room 数据库实例 + 迁移框架 | Phase 0 · 0.3 | 3.1 的 `interface_ride` 表 | 同上 |
| 4 个 travel 端点（`GET /travel`、`POST /travel-sync`、`GET /travel/{id}`、`GET /dashboard`） | Phase 0 · 0.1 | 3.1、3.2 | 同上 |
| `formatDistance / formatSpeed / formatEnergyWh / formatPercent / formatDuration / formatDate / numberText` | Phase 1 · 1.1 §2.5 | 3.1–3.4 全部数字 | 文案与 iOS 逐字符不一致 |
| `observedRangeSampleCount`、`rangeEstimateAccuracyText`、`rangeEstimateAccuracyDetailText`、`rangeModelInsightText`、`localEstimatedMileageText`、`rangePerBatteryPercentText`、`isUsingDefaultAlgorithmFallback` | Phase 2 · 2.3 | 3.1 的 `TripHeroPanel`、3.3 所在页的 `TripTrendRangeModelCard`、3.4 的 `fewRangeSamples` 规则 | 行程首屏顶卡与趋势页顶部两张卡做不出来；`fewRangeSamples` 规则无输入 |
| 原始字段折叠面板（`RawFieldSection` / `RawJSONSection` / `friendlyRawFieldName`） | Phase 2 · 2.7 | 3.2 行程详情底部两张卡 | 详情页少两张卡，见待定 T6 |
| `NinebotRecordedRide`（本地记录） | Phase 4 · 4.2/4.4 | 3.4 的 `unlinkedLocalRides` 规则、趋势页「本地记录」卡、3.2 详情页的本地轨迹面板 | **不阻塞**：Phase 3 阶段这个列表恒为空，规则恒不触发、卡片恒不显示。按空列表实现并单测规则本身 |
| 接口轨迹解析（`interfaceTrackPoints`） | Phase 4 · 4.1 | 3.2 详情页的接口轨迹地图 | **不阻塞**：3.2 只做除两张地图面板以外的全部内容 |

**明确划界**：`NinebotRideDetail` 里那约 450 行轨迹提取代码（`NinebotModels.swift:316-765`）属于 **Phase 4.1**，不在 3.2 范围内。3.2 只负责 `NinebotRideDetail` 的 `raw` / `parsedRecord` / `id` / `rawObject` 四个成员和详情页的非地图部分。`RideDetailParsingTests.swift` 里 52 个测试拆成两个 class：后一个 `RideRecordIdentityTests`（`:535-728`，**19 个**）是 **3.1 的**（去重键），前一个 `RideDetailParsingTests`（`:14-530`，**33 个**）是 4.1 的。

### 能并行做什么

- **3.4 的规则引擎可以第一天就开工**，和 3.1 完全并行。`core/domain/trip/TripTrend.kt` 是纯 Kotlin，唯一输入是 `VehicleState`（Phase 0 已有）+ `List<RecordedRide>`（可传空表），没有 UI、没有 Room、没有网络依赖。`TripTrendTests.swift` 的 19 个用例可以直接照抄成 JVM 单测。
- **3.3 的 `TrendBarChart` 可以并行**。它只吃 `List<TrendBarValue>`，用 Compose Preview 喂假数据就能做到像素级对齐，不等 3.1 的 Room。
- **3.1 → 3.2 有顺序**（列表要先有行才有详情入口），但 3.2 的 `RideDetailScreen` 可以先对着手写的 `RideRecord` fixture 做，只在联调时接上导航。
- 图标：本阶段界面共引用 **28 个** SF Symbol（去重后）—— `road.lanes`、`chart.xyaxis.line`、`chevron.right`、`chevron.down.circle.fill`、`clock.arrow.circlepath`、`sun.max.fill`、`speedometer`、`scope`、`calendar`、`target`、`list.number`、`bolt.horizontal.fill`、`arrow.up.right`、`chart.bar.xaxis`、`powerplug.fill`、`sparkle.magnifyingglass`、`gauge.with.dots.needle.33percent`、`gauge.with.dots.needle.67percent`、`point.3.connected.trianglepath.dotted`、`bolt.circle.fill`、`link`、`play.fill`、`stop.fill`、`timer`、`number`、`doc.on.doc`、`checkmark.circle.fill`、`map.fill`。与 Phase 1/2 有重叠（`speedometer`、`calendar`、`timer`、`bolt.horizontal.fill`、`road.lanes`、`target` 等），交付前先和已有清单去重。其中 `sparkle.magnifyingglass`（洞察卡每一行的前缀图标）和 `gauge.with.dots.needle.33percent` 在 Material Symbols 里没有对应物，需要定制。

---

## 3.1 行程列表 + 按月同步（4 天）

### 一 · iOS 现状

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| `NinebotTripsTabView` | `NinebotDashboardView.swift:1261-1279` | Tab 入口，无车时落到 `EmptyDashboardView` |
| `NinebotTripsView` | `:1281-1340` | 行程页容器，持有 `selectedMonth` |
| `TripMonthFilterPanel` | `:1342-1414` | 月份 chip 横滑条 + 「获取上一月」按钮 |
| `tripMonthDisplayName` | `:1417-1422` | `"202607"` → `"2026.07"` |
| `RideListSection` | `:3903-4002` | 列表本体，`visibleLimit` 分页 |
| `RideRecordRow` | `:4004-4072` | 单行 |
| `RideDisplayMetric` | `:4074-4082` | 行内小指标的值类型 |
| `RideMetric` | `:4546-4576` | 行内小指标胶囊 |
| `TripHeroPanel` | `:2584-2648` | 页面顶部「行程概要」卡 |
| `TripTrendEntryCard` | `:2650-2696` | 「查看趋势」入口卡 |

数据侧：

| 逻辑 | 位置 |
| --- | --- |
| `NinebotRideRecord` | `NinebotModels.swift:266-276` |
| `NinebotTravelPage` | `:278-286` |
| **`stableIdentityKey`** | **`:767-822`** |
| `NinebotDailyMileageRecord` | `:824-829` |
| `state.rides`（读时去重） | `:1442-1444` |
| `deduplicatedRideRecords` | `:1580-1592` |
| `NinebotDashboard.primaryVehicle` | `:1816-1821` |
| `tripMonthString(for:)` ×2、`previousTripMonth` | `NinebotFormatting.swift:11-36` |
| `syncTravelMonth`（客户端） | `NinebotServerClient.swift:180-190` |
| `fetchTravel` | `:192-198` |
| `fetchMonthlyTravels` | `:205-230` |
| `travelPage(from:fallbackMonth:)` | `:530-545` |
| `rideRecord(from:index:)` | `:679-710` |
| `dailyMileageRecords(from:)` | `:712-729` |
| `monthStrings(from:through:)` | `:988-1011` |
| `syncTravelMonth`（ViewModel） | `NinebotViewModel.swift:278-300` |
| `displayMonth` | `:689-694` |
| `saveDashboard`（ViewModel 侧） | `:544-550` |
| `saveDashboard`（Store 侧） | `NinebotSharedStore.swift:199-206` |
| **`dashboardWithArchivedInterfaceRides`** | **`:438-461`** |
| `upsertInterfaceRideRecords` | `:369-376` |
| `mergeInterfaceRideRecords` | `:477-492` |
| `saveInterfaceRideRecords`（500 上限） | `:471-475` |
| `sortedInterfaceRideRecords` | `:504-513` |
| `NinebotLoadingOperation.syncTravelMonth` | `NinebotLoadingOperation.swift:13`、`:30-31`、`:54-56` |

**页面骨架**（`:1287-1324`）

```
ScrollView
└─ VStack(alignment:.leading, spacing:16)   padding(16)
   ├─ TripHeroPanel(snapshot)
   ├─ NavigationLink → TripTrendView        label: TripTrendEntryCard
   ├─ TripMonthFilterPanel
   └─ RideListSection
背景 teslaPageBackground.ignoresSafeArea()，navigationTitle "行程"，displayMode .inline
```

**没有下拉刷新**。行程页是纯 `ScrollView`，没挂 `.refreshable`、也没有 1.1 那套自定义手势。唯一的拉取入口是月份面板右上角那个按钮。

### 二 · 要移植的逻辑

#### 2.1 去重键 `stableIdentityKey` —— 五级瀑布（`NinebotModels.swift:767-822`）

这是整个 Phase 3 最关键的一段。**Room 的主键必须和它逐字符一致**，否则同步出来的条数会和 iOS 不一样。

先看取值助手（`:803-812`）：

```swift
private func firstRawText(_ keys: [String]) -> String? {
    guard let raw else { return nil }              // raw == nil → 直接 nil
    for key in keys {
        if let text = raw[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return "\(key)=\(text)"                // ← 注意返回值里带 key 名
        }
    }
    return nil
}
```

**返回值是 `"键名=值"`，不是裸值。** 同一趟行程在两次返回里一次用 `travel_id` 一次用 `travelId`，键会不同，会被当成两条。`stringValue` 会把数字转成字符串（整数不带小数点，`NinebotModels.swift:1994-2008`），所以 `travel_id: 4321` → `"travel_id=4321"`。

两个数值格式化助手（`:814-821`）：

```
timestampText(date) = String(Int(date.timeIntervalSince1970))       // 秒，截断取整
metricText(value, scale) = value == nil ? "none" : String(Int((value * scale).rounded()))
```

五级瀑布，命中即返回：

| 级 | 触发条件 | 键的形状 | 行号 |
| --- | --- | --- | --- |
| 1 | raw 里有 `travel_id` / `travelId` | `travel:{键名}={值}` | 769-771 |
| 2 | raw 里有 `ride_id` / `rideId` / `record_id` / `recordId` / `id` | `id:{键名}={值}` | 773-775 |
| 3 | raw 里有 `start_time` / `startTime` / `begin_time` / `beginTime` / `stime` / `date` / `day` / `create_time` / `createTime` | `raw:start={..}\|end={..}\|km={..}\|used={..}` | 777-782 |
| 4 | 上面都没有，但 `startedAt != nil` | `start:{秒}\|end:{秒或 none}\|km:{里程×100 取整}\|used:{用电×100 取整}` | 784-791 |
| 5 | 兜底 | `fallback:{id}\|km:{×100}\|energy:{×10}\|used:{×100}\|duration:{×10}\|speed:{×10}` | 793-800 |

第 3 级的四个分量各自有兜底：

```
start  = firstRawText(["start_time","startTime","begin_time","beginTime","stime","date","day","create_time","createTime"])   ← 必然非 nil（进这一级的前提）
end    = firstRawText(["end_time","endTime","stop_time","stopTime","etime","finish_time","finishTime"]) ?? "none"
km     = firstRawText(["mileages","mileage","distance","rideMileage"])        ?? metricText(mileage, scale: 100)
used   = firstRawText(["used_electricity","usedElectricity","usedElectric","useElectricity"]) ?? metricText(usedElectricity, scale: 100)
```

所以第 3 级的 `km=` 后面可能是 `"mileage=12.5"`（原文），也可能是 `"1234"`（算出来的）。两种都要能生成。

**已知坑（必须原样保留）**：第 4 级 —— 也就是 raw 为 `nil` 或 raw 里既没有 id 也没有时间键、但 `startedAt` 解析成功的情况 —— 键由 **起始时间 / 结束时间 / 里程 / 耗电** 四项组成，**不含 `id`、不含 `energy`**。后果：两条起止时间和里程都一样、只有能耗不同的记录会被合并成一条。`TripTrendTests.testRidesWithTheSameTimestampAndMileageCollapse`（`Tests/NineBotCoreTests/TripTrendTests.swift:165-177`）专门钉住这个行为：

```
ride(id:"a", minuteOffset:0, mileage:10, energy:200)
ride(id:"b", minuteOffset:0, mileage:10, energy:300)
→ rideCount == 1
```

同一文件 `:9-13` 的注释解释了为什么该文件所有 fixture 都要把 `minuteOffset` 拉开。

第 5 级把 `id` 和 `energy` 都算进去了，所以只有第 4 级有这个合并问题。第 4 级在实践中什么时候会走到？`rideRecord(from:index:)`（`NinebotServerClient.swift:679-710`）永远会把整个 object 塞进 `raw`，所以线上数据几乎总走 1/2/3 级；第 4/5 级主要是从 Room/缓存里解出来的、raw 丢了的旧记录，以及 `NinebotRideRecord(id:mileage:)` 这类手工构造。**但它是测试和缓存迁移的实际路径，不能省。**

19 个针对这个键的用例在 `RideDetailParsingTests.swift:535-728`（`RideRecordIdentityTests`），其中这几条是必须逐字符对齐的期望值：

| 输入 | 期望键 | 行号 |
| --- | --- | --- |
| `raw: ["travel_id": .string("T-1")]` | `travel:travel_id=T-1` | 562-565 |
| `raw: ["travelId": .string("T-1")]` | `travel:travelId=T-1` | 567-572 |
| `raw: ["travel_id": .number(4321)]` | `travel:travel_id=4321` | 574-579 |
| `raw: ["record_id": .number(42)]` | `id:record_id=42` | 595-600 |
| `raw: ["id": "X", "ride_id": "R"]` | `id:ride_id=R`（`ride_id` 在查找顺序里更前） | 602-606 |
| `mileage:12.34, usedElectricity:4, raw:["start_time":"2024-05-01 08:00:00"]` | `raw:start=start_time=2024-05-01 08:00:00\|end=none\|km=1234\|used=400` | 610-617 |
| 同上但 raw 里带 `mileage:"12.5"`、`used_electricity:3` | `raw:start=start_time=A\|end=end_time=B\|km=mileage=12.5\|used=used_electricity=3` | 619-631 |
| `startedAt:1700000000, endedAt:1700000600, mileage:12.34, used:4` | `start:1700000000\|end:1700000600\|km:1234\|used:400` | 635-643 |
| 只有 `startedAt:1700000000` | `start:1700000000\|end:none\|km:none\|used:none` | 645-648 |
| `id:"abc", mileage:12.34, energy:200, used:4, duration:10, speed:27.6` | `fallback:abc\|km:1234\|energy:2000\|used:400\|duration:100\|speed:276` | 652-662 |
| `raw: [:]`（空字典，无日期） | 落到第 5 级 | 671-676 |
| `raw: ["travel_id": .string("   ")]` + `ride_id` | 空白值跳过 → `id:ride_id=R-9` | 680-686 |
| `raw: ["travel_id": .null]` + `ride_id` | null 跳过 → `id:ride_id=R-9` | 688-694 |
| `raw: ["travel_id": .string("  T-1  ")]` | 两端裁剪 → `travel:travel_id=T-1` | 696-701 |

#### 2.2 归档：合并、排序、500 上限（`NinebotSharedStore.swift:369-517`）

```
upsertInterfaceRideRecords(records, sn):
    records 为空 → 直接返回（不写盘）                        :370
    merged = mergeInterfaceRideRecords(incoming: records, stored: load(sn))
    save(merged, sn)

mergeInterfaceRideRecords:                                  :477-492
    dict = [:]
    先写 stored，再写 incoming                              ← 同键：incoming 覆盖 stored
    返回 sorted(dict.values)

sortedInterfaceRideRecords:                                 :504-513
    key1 = startedAt ?? endedAt ?? Date.distantPast，降序（新的在前）
    key2 = stableIdentityKey，升序（时间相同时的稳定排序）

saveInterfaceRideRecords:                                   :471-475
    sorted(dedup(records)).prefix(500)                      ← 只留最新 500 条

loadInterfaceRideRecords:                                   :463-469
    解码失败 → []（不抛错）
    读出来再走一遍 dedup + sort
```

**「incoming 覆盖 stored」和 `state.rides` 的「保留首次出现」是两套语义。** `deduplicatedRideRecords`（`NinebotModels.swift:1580-1592`）用 `Set` 记已见键，命中就 `continue`，**保留第一条**；而 store 用字典赋值，**保留最后一条**。归档路径走 store 那套。同一批 incoming 里出现重复键时，两者结果不同。

#### 2.3 快照与归档的合流（`NinebotSharedStore.swift:438-461`）

每次 `saveDashboard` 都过一遍这段，它是「本地归档怎么和新拉的合并」的答案：

```
对每辆车：
  incoming = snapshot.state.rides          ← 注意：读的是去重后的 rides，不是 rideRecords
  incoming 为空：
      stored = load(sn)
      stored 非空 → snapshot.state.rideRecords = stored      ← 用归档把快照补回来
      （stored 也空 → 什么都不做，rideRecords 保持 nil）
  incoming 非空：
      merged = merge(incoming, stored)
      save(merged, sn)                                        ← 落盘
      snapshot.state.rideRecords = merged.isEmpty ? nil : merged
返回改写后的 dashboard
```

`NinebotViewModel.saveDashboard`（`:544-550`）把返回值赋回 `self.dashboard`，所以界面看到的永远是**合流后的、跨月的、按时间倒序的、最多 500 条**的列表。冷启动时 `store.loadDashboard()`（`init`，`:166`）读的也是这份已合流的快照，所以**不联网就能看到全部已归档月份**。

对应测试 `SharedStoreTests.swift`：`:394-407`（快照带的行程被归档）、`:409-420`（空快照被归档补回）、`:376-392`（incoming 覆盖 stored，mileage 从 1 变 9）、`:422-443`（600 条只留 500，最新的那条留下）。

#### 2.4 「按月同步」的完整链路（`NinebotViewModel.swift:278-300`）

```
1. runLoadingOperation(.syncTravelMonth(displayMonth(month)))       加载条文案「正在获取 2026年07月 行程」
2. syncingTravelMonth = month（defer 清空）                          月份面板的按钮据此转圈+禁用
3. POST /vehicles/{sn}/travel-sync?month={yyyyMM}&page_size=100     ← 无 body，pageSize 由 ViewModel 传 100
4. store.upsertInterfaceRideRecords(page.records, sn:)              写归档
5. GET fetchDashboard(selectedSN: sn)                              ← 完整刷新，1 + N + M 个请求
6. saveDashboard → cacheVehicleImages → refreshResolvedAddresses
7. page.total == 0 → statusMessage "2026年07月 暂无行程"
   否则          → statusMessage "已获取 2026年07月 37 条行程"
8. errorMessage = nil；WidgetCenter.reloadAllTimelines()
```

`NinebotLoadingOperation.showsDashboardRefreshIndicator` 对 `.syncTravelMonth` 返回 **false**（`NinebotLoadingOperation.swift:54-56`），所以主页那个下拉刷新指示器不会因为月同步而出现。

**一次拉几个月？** 答案是：**行程列表一次只拉一个月，而且只拉第一页。**

- `syncTravelMonth` 每次只带一个 `month`，没有循环。
- `NinebotTravelPage`（`NinebotModels.swift:278-286`）解出了 `page` / `pageSize` / `total` / `hasMore` 四个分页字段，但**全仓只有 `total` 被用过**（用于那句 statusMessage）。`hasMore` / `page` / `pageSize` **没有任何读取点**（已全仓 grep 确认）。**iOS 永远不请求第 2 页。** 一个月超过 100 条就会缺数据，且界面不提示。
- `travelPage(from:fallbackMonth:)`（`NinebotServerClient.swift:530-545`）的兜底：`month` 缺失用请求的月份、`page` 缺失为 1、`pageSize` 缺失取 `page_size`→`pageSize`→`records.count`、`total` 缺失取 `records.count`、`hasMore` 缺失取 `has_more`→`hasMore`→`false`。`list` 不是数组时为空数组。测试 `ServerClientTests.swift:632-671`（全字段）与 `:673-684`（全缺失）。

**「怎么判断某个月已经拉全」** —— iOS **不判断**。没有任何 per-month 的「已同步完」状态位。用户只能靠列表条数自己看。

**另一条容易看漏的月份循环**：`fetchDashboard` 里的 `fetchMonthlyTravels`（`NinebotServerClient.swift:205-230`）会把 `monthStrings(from: vehicle.authDate, through: Date())` 这一整串月份**逐个串行 GET** 一遍。但它的返回值**只喂给 `totalMileage(fromMonthlyTravels:)`（`:731-752`）算总里程**，`rideRecords` 完全不从这里来。所以：

- 一辆去年绑定的车，每次刷新车况都会打十几个 `GET /vehicles/{sn}/travel?month=`，却一条行程都不入库。
- `monthStrings`（`:988-1011`）：`authDate == nil` → 只返回当月；start > end 或构造失败 → 只返回当月；否则从 start 月到 end 月逐月递增（`Asia/Shanghai` 日历）。
- 任何一个月的请求抛错 → `fetchMonthlyTravels` 整个返回 `nil` → `totalMileage` 不覆盖（`:225-227`）。当月那一份如果已在 dashboard 里则复用，不重复请求（`:218-221`）。

#### 2.5 月份选项与「翻到更早」（`NinebotDashboardView.swift:1326-1339`）

```swift
selectedMonth 初值 = tripMonthString(for: Date())            // :1285，当月

monthOptions:                                                 // :1326-1331
    Set(state.rides.compactMap(tripMonthString(for:)))        // 归档里出现过的月份
      ∪ { tripMonthString(for: Date()) }                      // 当月
      ∪ { selectedMonth }                                     // 当前选中
    再 sorted(by: >)                                          // 字符串降序 == 时间降序

filteredRecords = state.rides.filter { tripMonthString(for: $0) == selectedMonth }   // :1333-1335

nextFetchMonth = previousTripMonth(before: monthOptions.min() ?? selectedMonth)      // :1337-1339
```

`tripMonthString(for record:)`（`NinebotFormatting.swift:11-14`）取 `startedAt ?? endedAt`，两个都 nil 返回 **nil** —— 这种记录**在任何月份筛选下都不显示**（`nil != selectedMonth`），但仍然占着归档的 500 个位子。

`tripMonthString(for date:)`（`:16-23`）：`yyyyMM`，日历 gregorian，locale `en_US_POSIX`，时区**恒 `Asia/Shanghai`**。

`previousTripMonth(before:)`（`:25-36`）：长度不是 6 或前 4 位/后 2 位不是数字 → 返回**当月**；否则在 `Asia/Shanghai` 日历上构造该月 1 号再 `-1 month`。测试 `FormattingTests.swift:142-145`：`202607→202606`，`202601→202512`。

按钮点击（`:1303-1309`）：先 `selectedMonth = nextFetchMonth`，再 `Task { syncTravelMonth }`。**先切月再拉**，所以点下去立刻看到「2026.06 暂无行程」，几秒后数据才填进来。

因为 `selectedMonth` 被并进了 `monthOptions`，连点这个按钮会一个月一个月往前走：拉完 202606（哪怕 0 条）→ min 变成 202606 → 下次目标 202605。

#### 2.6 列表本体（`NinebotDashboardView.swift:3903-4002`）

标题区（`:3913-3928`）：`"行程列表"` + 副标题 `"点击行程查看详情和本地轨迹"`，右侧 `Text("\(records.count)")` —— 是**当前月份筛选后的条数**，不是总数。

空态（`:3930-3946`，注意是卡片而不是 `EmptyTrendState`）：
- 主文案 `"{2026.07} 暂无行程"`（用 `tripMonthDisplayName`，点号格式）
- 副文案 `"可以切换已有月份，或继续向前获取服务器归档。"`

分页（`:3909`、`:3949`、`:3966-3988`、`:3992-3994`）：

```
@State visibleLimit = 30
渲染 records.prefix(visibleLimit)，ForEach id: \.element.id
records.count > visibleLimit → 显示「显示更多」按钮
    图标 chevron.down.circle.fill + 文案 "显示更多" + 剩余条数（monospacedDigit）
    点击 visibleLimit += 30
selectedMonth 变化 → visibleLimit 重置回 30
```

**`ForEach` 的 id 用的是 `record.id`（`NinebotRideRecord.id`），不是 `stableIdentityKey`。** 归档按 identityKey 去重，但 `id` 仍可能重复（比如两条都落到「用 startedAt 秒数当 id」的兜底），SwiftUI 会报重复 id 并丢行。Android 侧的 `key` 必须用 identityKey。

单行 `RideRecordRow`（`:4004-4072`）：

```
VStack(alignment:.leading, spacing:12)   padding(14)
├─ HStack(alignment:.top, spacing:12)
│  ├─ ZStack 42×42：RoundedRectangle(18) fill teslaGreen@14% + road.lanes（headline/semibold, teslaGreen）
│  ├─ VStack(alignment:.leading, spacing:4)
│  │  ├─ startedAt → formatRideDate（"2026-07-26 14:32"）；nil → "行程 {index+1}"
│  │  │  headline/semibold, primaryText, lineLimit1
│  │  └─ HStack(spacing:6){ 结束时间 · "·" · formatDuration(durationMinutes) }
│  │     caption/medium, secondaryText, lineLimit1, minimumScaleFactor 0.8
│  ├─ Spacer()
│  └─ formatDistance(mileage)  title3/monospacedDigit/bold, primaryText, lineLimit1
└─ metrics 非空时 HStack(spacing:10){ RideMetric × n }
teslaCardBackground，圆角 18 continuous，1pt hairline 描边，阴影 黑4% r12 y6
```

`metrics`（`:4065-4071`）是 `compactMap`，**值为 nil 的整格不出现**，最多 3 格：

| 顺序 | 条件 | title | value |
| --- | --- | --- | --- |
| 1 | `energy != nil` | 能耗 | `formatEnergyWh`（0 位小数 + `" Wh"`） |
| 2 | `usedElectricity != nil` | 用电 | `formatPercent`（1 位小数 + `"%"`） |
| 3 | `speed != nil` | 速度 | `formatSpeed`（1 位小数 + `" km/h"`） |

**结束时间那一格是 iOS 侧的时区不一致**（`:4027`）：

```swift
Text(record.endedAt.map { "结束 \($0.formatted(.dateTime.hour().minute()))" } ?? "结束时间未知")
```

`.formatted(.dateTime.hour().minute())` 走**设备 locale 与设备时区**，而同一行上方的开始时间走 `formatRideDate` → `formatDate`（`NinebotFormatting.swift:38-44`，恒 `zh_CN` + `Asia/Shanghai`）。设备设成美国时区时，同一行会显示北京时间的开始 + 本地时间的结束，还可能带 AM/PM。见待定 T5。

#### 2.7 两张顶部卡的字段来源

`TripHeroPanel`（`:2584-2648`）：

| 位置 | 取值 | 备注 |
| --- | --- | --- |
| 标题 | `"行程概要"` headline | |
| 副标题 | `snapshot.vehicle.name` caption/medium lineLimit1 | |
| 右上数字 | `state.rangeEstimateAccuracyText` title3/monospacedDigit/bold **teslaGreen** | Phase 2.3；无预测时是 `"样本不足"` |
| 右上标签 | `"预估准确率"` caption2/medium | |
| 巨型数字 | `state.localEstimatedMileageText` **42pt** semibold rounded monospacedDigit lineLimit1 minScale 0.72 | |
| 巨型数字后缀 | `"预计可行驶"` footnote/medium，`lastTextBaseline` 对齐，spacing 8 | |
| 2×2 格（`BasicInfoTile`，间距 10） | 今日里程 `todayMileageText` / 平均速度 `averageSpeedText` / 有效样本 `"{observedRangeSampleCount} 次"` / 本月日均 `dailyAverageMileageText` | 图标 `sun.max.fill` / `speedometer` / `scope` / `calendar` |
| 底部一行 | `Label(state.rangeEstimateAccuracyDetailText, systemImage:"target")` caption/medium lineLimit1 | |

卡片：padding 16，teslaCardBackground，圆角 **28** continuous，阴影 黑5% r14 y8，**无描边**。

注意这里的 `averageSpeedText` 是 **`NinebotVehicleState.averageSpeed`**（`NinebotModels.swift:1426-1430`），它走 `rideSpeed(_:)`（`:1686-1695`）：`speed > 0` 优先，否则用 `mileage / (durationMinutes / 60)`（两者都 > 0 才算）。**这和 3.4 里 `NinebotTripTrend.averageSpeed` 不是同一个算法**，后者只认 `speed` 字段。同一个页面上「行程概要 · 平均速度」和「趋势页 · 平均速度」可能是两个不同的数。两套都要实现，不要合并。

`dailyAverageMileageText`（`:1387-1392`）：`monthMileage == nil → "-- km/日"`；否则 `monthMileage / max(day(updatedAt), 1)`，1 位小数 + `" km/日"`。**分母是 `updatedAt` 的「日」，不是活跃天数**，与 3.4 的 `averageDailyMileage`（除以活跃天数）又是两回事。

`todayMileage`（`:1394-1404`）：先找 `dailyMileages` 里 `date` 命中 `Calendar.current.isDateInToday` 的**最后一条**；没找到再找 `day == day(updatedAt)` 的最后一条。注意这里用的是 `Calendar.current`（设备日历/时区），而 `date` 是在 `Asia/Shanghai` 构造的（`NinebotServerClient.swift:965-973`），跨时区设备上第一条匹配会失效并落到第二条。

`TripTrendEntryCard`（`:2650-2696`）：42×42 圆形（teslaGreen@14% 填充 + `chart.xyaxis.line`）+ `"查看趋势"` headline + `"里程、用电、速度和续航估算表现"` caption/medium lineLimit1 minScale 0.78 + 右侧 `state.monthMileageText`（subheadline/monospacedDigit/bold）与 `chevron.right`。圆角 24，1pt hairline，阴影 黑5% r14 y8。

`monthMileageText`（`NinebotModels.swift:1109-1112`）用 `decimalFormatter`（最多 1 位、最少 0 位），兜底 `"-- km"`。

#### 2.8 行程记录解析（`NinebotServerClient.swift:679-710`）

`travel-sync` 的 `list` 和 dashboard 的 `travel.list` 走**同一个** `rideRecord(from:index:)`。非 object 元素返回 nil 被 `compactMap` 丢掉。

| 字段 | 键顺序（命中即止） |
| --- | --- |
| `startedAt` | `start_time`, `startTime`, `begin_time`, `beginTime`, `stime`, `date`, `day`, `create_time`, `createTime` |
| `endedAt` | `end_time`, `endTime`, `stop_time`, `stopTime`, `etime`, `finish_time`, `finishTime` |
| `mileage` | `mileages`, `mileage`, `distance`, `rideMileage` |
| `energy` | `ec`, `energy`, `electricity`, `consume` |
| `usedElectricity` | `used_electricity`, `usedElectricity`, `usedElectric`, `useElectricity` |
| `speed` | `speed`, `avg_speed`, `avgSpeed`, `average_speed`, `averageSpeed` |
| `durationMinutes` | 见 3.2 §2.2 |
| `id` | `travel_id`, `travelId`, `ride_id`, `rideId`, `record_id`, `recordId`, `id` → 兜底 `String(Int(startedAt.timeIntervalSince1970))` → 兜底 `"\(index)"` |
| `raw` | 整个 object 原样保留 |

**`mileages` 是复数、在 `mileage` 之前**；**`ec` 是能耗的第一顺位键**。`electricity` 同时是能耗的第三顺位键，又是电量百分比的第三顺位键（`vehicleState`，`:581`）—— 同名不同义，别把两处的解析共用一个函数。

`vehicleState` 侧还派生了三个「上一次骑行」字段（`:577`、`:652-654`）：`lastMileage/lastEnergy/lastUsedElectricity` 取 `rideRecords.first`，即**接口 list 的第 0 个元素**（不是排序后的最新一条）。测试 `ServerClientTests.swift:1127-1146`。

### 三 · Android 实现要点

#### 3.1 去重键（纯 Kotlin，先写这个）

```kotlin
// core/domain/trip/RideIdentity.kt
object RideIdentity {
    private val TRAVEL_KEYS = listOf("travel_id", "travelId")
    private val EXPLICIT_KEYS = listOf("ride_id", "rideId", "record_id", "recordId", "id")
    private val START_KEYS = listOf(
        "start_time", "startTime", "begin_time", "beginTime",
        "stime", "date", "day", "create_time", "createTime",
    )
    private val END_KEYS = listOf(
        "end_time", "endTime", "stop_time", "stopTime",
        "etime", "finish_time", "finishTime",
    )
    private val MILEAGE_KEYS = listOf("mileages", "mileage", "distance", "rideMileage")
    private val USED_KEYS = listOf(
        "used_electricity", "usedElectricity", "usedElectric", "useElectricity",
    )

    fun stableKey(record: RideRecord): String {
        val raw = record.raw                                     // JsonObject?
        firstRawText(raw, TRAVEL_KEYS)?.let { return "travel:$it" }
        firstRawText(raw, EXPLICIT_KEYS)?.let { return "id:$it" }
        firstRawText(raw, START_KEYS)?.let { start ->
            val end = firstRawText(raw, END_KEYS) ?: "none"
            val km = firstRawText(raw, MILEAGE_KEYS) ?: metricText(record.mileage, 100.0)
            val used = firstRawText(raw, USED_KEYS) ?: metricText(record.usedElectricity, 100.0)
            return "raw:start=$start|end=$end|km=$km|used=$used"
        }
        record.startedAt?.let { start ->
            return listOf(
                "start:${timestampText(start)}",
                "end:${record.endedAt?.let(::timestampText) ?: "none"}",
                "km:${metricText(record.mileage, 100.0)}",
                "used:${metricText(record.usedElectricity, 100.0)}",
            ).joinToString("|")
        }
        return listOf(
            "fallback:${record.id}",
            "km:${metricText(record.mileage, 100.0)}",
            "energy:${metricText(record.energy, 10.0)}",
            "used:${metricText(record.usedElectricity, 100.0)}",
            "duration:${metricText(record.durationMinutes, 10.0)}",
            "speed:${metricText(record.speed, 10.0)}",
        ).joinToString("|")
    }

    private fun firstRawText(raw: JsonObject?, keys: List<String>): String? {
        if (raw == null) return null
        for (key in keys) {
            val text = raw[key]?.stringValue?.trim()
            if (!text.isNullOrEmpty()) return "$key=$text"       // ← 带键名
        }
        return null
    }

    // Swift: String(Int(date.timeIntervalSince1970)) —— 向零截断，不是 floor
    private fun timestampText(instant: Instant): String =
        (instant.toEpochMilliseconds() / 1000).toString()

    // Swift: String(Int((value * scale).rounded())) —— .rounded() 是「远离零的四舍五入」
    private fun metricText(value: Double?, scale: Double): String {
        if (value == null) return "none"
        val scaled = value * scale
        val rounded = if (scaled < 0) -floor(-scaled + 0.5) else floor(scaled + 0.5)
        return rounded.toLong().toString()
    }
}
```

三条容易写错的换算：

1. **`Double.rounded()` 是 `.toNearestOrAwayFromZero`**，`0.5 → 1`、`-0.5 → -1`。Kotlin 的 `Math.round()` 对负数是 `-0.5 → 0`（向上），`roundToLong()` 同理。里程/耗电通常为正，但 `12.345 * 100 = 1234.4999…` 这类边界会差 1，直接改变主键。用上面的显式实现或 `BigDecimal(RoundingMode.HALF_UP)`。
2. **`Int(timeIntervalSince1970)` 是向零截断**，1970 年之前的时间戳与 `floor` 结果不同。用整数除法（Kotlin 的 `/` 对 Long 也是向零截断）而不是 `floor`。
3. **`stringValue` 对数字的格式化**：整数值必须输出不带 `.0`（`4321.0 → "4321"`）。Phase 0 §0.1 的 `JsonElement.stringValue` 已经定了这条规则，这里只是强调它直接决定主键。非整数值 Swift 用 `String(Double)`、Java 用 `Double.toString()`，两者在大数量级上格式不同（Swift `1e+21` / Java `1.0E21`）；travel id 实践中都是整数，但要用共享 fixture 钉一条非整数用例，防止将来悄悄分叉。

#### 3.2 Room 表

```kotlin
@Entity(
    tableName = "interface_ride",
    primaryKeys = ["vehicle_sn", "identity_key"],
    indices = [Index(value = ["vehicle_sn", "trip_month", "sort_at"])],
)
data class InterfaceRideEntity(
    @ColumnInfo(name = "vehicle_sn") val vehicleSn: String,
    @ColumnInfo(name = "identity_key") val identityKey: String,   // RideIdentity.stableKey 原文
    @ColumnInfo(name = "ride_id") val rideId: String,             // RideRecord.id，不参与主键
    @ColumnInfo(name = "started_at") val startedAtEpochSec: Long?,
    @ColumnInfo(name = "ended_at") val endedAtEpochSec: Long?,
    @ColumnInfo(name = "sort_at") val sortAtEpochSec: Long,       // startedAt ?: endedAt ?: DISTANT_PAST
    @ColumnInfo(name = "trip_month") val tripMonth: String?,      // yyyyMM @ Asia/Shanghai，可空
    val mileage: Double?,
    val energy: Double?,
    @ColumnInfo(name = "used_electricity") val usedElectricity: Double?,
    @ColumnInfo(name = "duration_minutes") val durationMinutes: Double?,
    val speed: Double?,
    val raw: String?,                                             // 原始 JSON 文本，去重键要用
) {
    companion object {
        /** 对齐 Swift 的 Date.distantPast（0001-01-01T00:00:00Z）。 */
        const val DISTANT_PAST_EPOCH_SEC = -62_135_596_800L
    }
}
```

三个派生列的必要性：

- **`sort_at`** —— iOS 的排序键是 `startedAt ?? endedAt ?? distantPast`。在 SQL 里写成 `COALESCE(...)` 就用不上索引，且 `distantPast` 的常量必须精确到秒。存成 NOT NULL 列。
- **`trip_month`** —— iOS 每次筛选都在内存里对 500 条算一遍 `tripMonthString`。Android 存成列，月份筛选变成 `WHERE`，Paging 才能下推。**必须用完全相同的规则算**：`startedAt ?: endedAt`，`Asia/Shanghai`，`yyyyMM`；两者都为 null 时列为 NULL。
- **`raw`** —— 不存 raw，重启后 `stableKey` 会从第 1/2/3 级掉到第 4/5 级，同一条行程算出不同的键，归档立刻双份。这是最容易犯的致命错误。

DAO：

```kotlin
@Dao
interface InterfaceRideDao {
    @Upsert                                     // 主键冲突时 incoming 覆盖 stored
    suspend fun upsert(rides: List<InterfaceRideEntity>)

    @Query("""
        DELETE FROM interface_ride
        WHERE vehicle_sn = :sn AND identity_key NOT IN (
            SELECT identity_key FROM interface_ride WHERE vehicle_sn = :sn
            ORDER BY sort_at DESC, identity_key ASC LIMIT 500
        )
    """)
    suspend fun trimTo500(sn: String)

    @Transaction
    suspend fun upsertAndTrim(sn: String, rides: List<InterfaceRideEntity>) {
        if (rides.isEmpty()) return             // 对齐 upsertInterfaceRideRecords 的空批直接返回
        upsert(rides)
        trimTo500(sn)
    }

    @Query("""
        SELECT * FROM interface_ride
        WHERE vehicle_sn = :sn AND trip_month = :month
        ORDER BY sort_at DESC, identity_key ASC
    """)
    fun pagingSource(sn: String, month: String): PagingSource<Int, InterfaceRideEntity>

    @Query("SELECT COUNT(*) FROM interface_ride WHERE vehicle_sn = :sn AND trip_month = :month")
    fun countForMonth(sn: String, month: String): Flow<Int>

    @Query("""
        SELECT DISTINCT trip_month FROM interface_ride
        WHERE vehicle_sn = :sn AND trip_month IS NOT NULL
        ORDER BY trip_month DESC
    """)
    fun monthsWithRides(sn: String): Flow<List<String>>

    @Query("SELECT COUNT(*) FROM interface_ride WHERE vehicle_sn = :sn")
    suspend fun count(sn: String): Int          // 诊断中心 interfaceRideCount
}
```

`@Upsert` 在有冲突时执行 UPDATE，对齐「incoming 覆盖 stored」。**一批里出现重复 identityKey 时，Room 按列表顺序逐条执行，最后一条生效** —— 与 iOS 的字典赋值一致。

上限修剪必须和 upsert 在**同一个** `@Transaction` 里，否则中途崩溃会留下超限的表；`trimTo500` 的 `ORDER BY` 必须和 `pagingSource` 完全一致，否则「留下哪 500 条」和 iOS 不同。

#### 3.3 月份筛选与选项列表

```kotlin
// feature/trips/TripsViewModel.kt
private val selectedMonth = MutableStateFlow(TripMonth.current())   // yyyyMM @ Asia/Shanghai

val monthOptions: StateFlow<List<String>> = combine(
    dao.monthsWithRides(sn), selectedMonth,
) { withRides, selected ->
    (withRides + TripMonth.current() + selected).distinct().sortedDescending()
}.stateIn(...)

val nextFetchMonth: StateFlow<String> =
    monthOptions.map { TripMonth.previous(it.minOrNull() ?: selectedMonth.value) }.stateIn(...)
```

`sortedDescending()` 对 `yyyyMM` 字符串就是时间倒序（定长补零），和 iOS 的 `sorted(by: >)` 等价。

#### 3.4 Paging

```kotlin
val rides: Flow<PagingData<RideRow>> = selectedMonth.flatMapLatest { month ->
    Pager(
        config = PagingConfig(
            pageSize = 30,
            initialLoadSize = 30,      // 默认是 3×pageSize=90，必须显式改成 30 对齐 iOS 首屏
            prefetchDistance = 10,
            enablePlaceholders = false,
        ),
    ) { dao.pagingSource(sn, month) }.flow.map { it.map(::toRow) }
}.cachedIn(viewModelScope)
```

`LazyColumn` 侧 `items(rides, key = { it.identityKey })` —— **key 用 identityKey，不是 rideId**（见 §2.6 的坑）。`flatMapLatest` 保证换月时旧的 `PagingSource` 被取消，等价于 iOS 的 `visibleLimit = 30` 重置。

**「显示更多」按钮 vs 无限滚动是 UX 分叉，见待定 T2。** 若保留按钮，就别用 Paging，改成 `MutableStateFlow(30)` + `LIMIT :limit` 查询；若用 Paging，页脚放 `loadState.append` 的进度条。

#### 3.5 同步与合流

`fetchDashboard` 的合流逻辑（§2.3）在 Android 侧改成：**Room 是唯一真相，dashboard 快照不再携带行程列表**。

```kotlin
// core/data/TripRepository.kt
class TripRepository(
    private val api: NinebotApi,
    private val dao: InterfaceRideDao,
    @ApplicationScope private val externalScope: CoroutineScope,
) {
    private val _syncingMonth = MutableStateFlow<String?>(null)
    val syncingMonth: StateFlow<String?> = _syncingMonth.asStateFlow()

    /** 对应 fetchDashboard 时把 travel.list 落库那一半。 */
    suspend fun archive(sn: String, records: List<RideRecord>) =
        dao.upsertAndTrim(sn, records.map { it.toEntity(sn) })

    /** 对应 NinebotViewModel.syncTravelMonth。 */
    fun syncMonth(sn: String, month: String): Job = externalScope.launch {
        _syncingMonth.value = month
        try {
            val page = api.travelSync(sn, month, pageSize = 100)
            dao.upsertAndTrim(sn, page.records.map { it.toEntity(sn) })
            dashboardRepository.refresh(selectedSn = sn)   // iOS 在这一步做完整刷新
            status.emit(
                if (page.total == 0) "${displayMonth(month)} 暂无行程"
                else "已获取 ${displayMonth(month)} ${page.total} 条行程"
            )
        } catch (t: Throwable) {
            error.emit(t.readableMessage())
        } finally {
            _syncingMonth.value = null
        }
    }
}
```

用 **application-scoped 协程**（不是 `viewModelScope`）：用户点了「获取 2026.06」后立刻返回上一屏，归档写入不能被取消 —— 否则 `page.total` 报了 37 条却什么都没入库。进度状态放 Repository，配置变更后按钮的转圈不丢。

不必上 WorkManager：这是用户主动触发、前台可见的操作，WorkManager 的调度延迟只会让按钮看着像没反应。

**两套月份文案都要有**（缺一个就有位置显示错）：

| 函数 | 输出 | 用在哪 | iOS 位置 |
| --- | --- | --- | --- |
| `tripMonthDisplayName` | `"2026.07"` | 月份 chip、`"当前 2026.07"`、`"获取 2026.06"`、`"2026.07 暂无行程"` | `NinebotDashboardView.swift:1417-1422` |
| `displayMonth` | `"2026年07月"` | 加载条 `"正在获取 2026年07月 行程"`、状态条 `"已获取 2026年07月 37 条行程"` / `"2026年07月 暂无行程"` | `NinebotViewModel.swift:689-694` |

两者都在 `month.length != 6` 时原样返回入参。

#### 3.6 月份面板

```kotlin
// 卡片：padding 14，圆角 24，1pt hairline，阴影 黑5% r14 y8
Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Row(verticalAlignment = Alignment.Top) {                       // firstTextBaseline 对齐
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("月份筛选", style = headline)
            Text("当前 ${tripMonthDisplayName(selectedMonth)}", style = caption, color = secondary)
        }
        Spacer(Modifier.weight(1f))
        OutlinedButton(onClick = onFetchOlder, enabled = !isSyncing) {   // .buttonStyle(.bordered) + tint green
            if (isSyncing) CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
            else Icon(ClockArrowCirclepath, null)
            Text("获取 ${tripMonthDisplayName(nextFetchMonth)}")          // caption/semibold
        }
    }
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {         // 无滚动条
        items(months) { month ->
            // 选中：teslaGreen 底 + 白字 + 无描边
            // 未选：teslaCardBackground 底 + primaryText + 1pt hairline 描边
            // Capsule，padding(h:12, v:8)，caption/semibold
        }
    }
}
```

`isSyncing` 用 `syncingMonth != null`（**任何月份**在同步中都禁用按钮），不是 `syncingMonth == thisMonth`。iOS 就是这么传的（`:1301`）。

### 四 · 陷阱

1. **500 条上限会静默吞掉刚拉到的旧月份。** `saveInterfaceRideRecords`（`NinebotSharedStore.swift:471-475`）保留的是**最新** 500 条。当近几个月已经攒满 500 条时，用户点「获取 2024.03」，服务端返回 37 条、状态条显示「已获取 2024年03月 37 条行程」，但这 37 条在同一个事务里被修剪掉，列表仍是「2024.03 暂无行程」。上限是全车共享的、跨月的，不是 per-month。见待定 T3。

2. **一次月同步会打 `2 + N + M` 个请求。** `POST travel-sync` 1 个，`fetchDashboard` 里 `GET /vehicles` 1 个、每辆车 `GET dashboard` 1 个，再加 `fetchMonthlyTravels` 对「绑定月到当月」逐月各 1 个 `GET travel`（当月那份复用）。一辆去年绑定的车、慢网下很容易十几秒。而这些月度 travel 请求**只用来算总里程**，一条行程都不入库。Android 侧要么按 iOS 原样保留，要么把总里程计算拆出来降频，见待定 T4。

3. **不存 `raw` 就会双份。** 去重键的前三级全部读 `raw`。冷启动后如果 raw 没了，同一条行程从「第 1 级 `travel:travel_id=T-1`」掉到「第 4 级 `start:...`」，与线上新拉的那条键不同，归档里出现两条完全一样的行程。Room 里 `raw` 列必须存原始 JSON 文本。

4. **`rounded()` 换算差 1 就换主键。** `metricText` 用的是 Swift 的 `.rounded()`（远离零的四舍五入）。Kotlin 的 `roundToLong()` / `Math.round()` 对负数不同、`Math.round(-0.5) == 0`。里程一般为正，但 `12.345 × 100` 这种在二进制里落到 `1234.4999999999998` 的值，`.rounded()` 给 1234 而某些实现给 1235。用显式的 `floor(x + 0.5)` 实现或 `BigDecimal.setScale(0, HALF_UP)`。

5. **`ForEach` 的 id 是 `record.id` 不是 identityKey**（`:3949`）。两条不同的行程可以有相同的 `id`（都落到「用 startedAt 秒当 id」的兜底），iOS 在这种情况下会丢行。Android 的 `key` 必须用 identityKey，这是主动修正。

6. **行程行的结束时间用设备时区**（`:4027`），开始时间用 `Asia/Shanghai`（`NinebotFormatting.swift:38-52`）。见待定 T5。

7. **`total`、`page`、`hasMore` 三个字段的 `intValue` 走 `Int(doubleValue)`**（`NinebotModels.swift:2023-2026`）。Swift 的 `Int(Double.nan)` / `Int(Double.infinity)` **会崩**。服务端若返回 `"total": "abc"` 则 `doubleValue` 为 nil、走兜底不崩；但返回 `"total": "nan"` 时 `Double("nan")` 成功、`Int(nan)` 崩溃。Kotlin 的 `.toInt()` 对 NaN 返回 0 不崩 —— 这个差异对 Android 是好事，但要显式写清 `intValue` 的实现（先取 double，非有限值返回 null），不要照抄成会抛异常的版本。

8. **`monthOptions` 里没有行程的月份切走就消失。** 空月份只靠 `selectedMonth` 撑在选项里（`:1329`）。用户拉了 2026.06（0 条）→ 切回 2026.07 → 2026.06 的 chip 消失，`nextFetchMonth` 直接跳回「min 的上一月」，那个空月份要重新拉一次才能再出现。行为原样保留（跟 iOS 一致），但要在测试里钉住，别在实现 Room 查询时「顺手修正」成保留历史选项。

9. **没有下拉刷新。** 行程页只有一个数据入口（那个按钮）。不要因为 1.1 做了自定义下拉手势就顺手给行程页也挂上 —— 挂上就得决定「下拉刷新是刷当月还是刷选中月」，那是新的产品决策。

10. **`startedAt` 和 `endedAt` 都为 nil 的记录会入库、占上限位子、但任何月份都看不到**（`tripMonthString` 返回 nil，`nil != selectedMonth`）。`trip_month` 列为 NULL 时不要用 `= :month` 之外的写法「顺手」把它们归到当月。

11. **`state.rides` 的「保留首次」与归档的「保留最后」是两套语义**（`NinebotModels.swift:1580-1592` vs `NinebotSharedStore.swift:477-492`）。Android 只走归档那条，用 `@Upsert`（后写覆盖）。别把两处抽成一个公共去重函数。

### 五 · 验收标准

- [ ] 把 `RideDetailParsingTests.swift:535-728` 的 19 个用例逐条移成 JVM 单测，期望字符串**逐字符相同**（含 `travel:travel_id=4321`、`raw:start=start_time=2024-05-01 08:00:00|end=none|km=1234|used=400`、`fallback:abc|km:1234|energy:2000|used:400|duration:100|speed:276`）
- [ ] 移 `TripTrendTests.testRidesWithTheSameTimestampAndMileageCollapse`：起止时间与里程相同、能耗不同的两条 → Room 里只剩 1 行；`minuteOffset` 拉开到 90 分钟 → 2 行
- [ ] 移 `SharedStoreTests.swift:337-443` 的 8 个归档用例：未知 SN 计数为 0、空批不写盘、不同 `travel_id` 存两条、同 `travel_id` 不同 `id` 只存一条、incoming 覆盖 stored（mileage 1→9）、快照携带的行程被归档、空快照被归档补回、600 条只留 500 且最新那条在
- [ ] `metricText` 边界：`12.345 × 100`、`0.005 × 100`、负值各一条，与 Swift 输出比对
- [ ] 杀进程重启：同一条行程的 `identityKey` 不变（验证 `raw` 落库生效），归档条数不翻倍
- [ ] 月份 chip 顺序为时间倒序；当月与当前选中月**恒在**选项里；无行程的月份切走后消失（与 iOS 一致）
- [ ] 连点「获取上一月」5 次，目标月份逐月后退（`202607→202606→…→202602`），不跳月不重复
- [ ] `previousTripMonth`：`202601 → 202512`；入参 `"2026"`（长度 5）→ 返回当月
- [ ] 设备时区改成 UTC-8，`trip_month` 仍按 `Asia/Shanghai` 计算：北京时间 8 月 1 日 02:00 的行程归到 `202608` 而不是 `202607`
- [ ] `travel-sync` 请求是 `POST /vehicles/{sn}/travel-sync?month=yyyyMM&page_size=100`，**无 body**
- [ ] MockWebServer 复刻 `ServerClientTests.swift:632-684`：全字段解析（`month=202312` 覆盖请求的 `202401`、`page=2`、`pageSize=10`、`total=37`、`hasMore=true`）与全缺失兜底（`month` 回落请求值、`page=1`、`pageSize=0`、`total=0`、`hasMore=false`）
- [ ] `total == 0` → 状态条「2026年07月 暂无行程」；`total == 37` → 「已获取 2026年07月 37 条行程」；加载条「正在获取 2026年07月 行程」
- [ ] 月份筛选的 chip 用 `2026.07`、状态/加载文案用 `2026年07月`，两套格式各截图归档
- [ ] 首屏 30 行，滚到底加载下一页；换月后回到第 1 页（`initialLoadSize` 确认是 30 不是 90）
- [ ] 点「获取上一月」后立刻返回上一屏，10 秒后回来：那个月的行程已在列表里（验证 application scope）
- [ ] 同步中「获取上一月」按钮禁用且转圈；同步失败后按钮恢复可点
- [ ] 空月份卡片文案：`"2026.07 暂无行程"` + `"可以切换已有月份，或继续向前获取服务器归档。"`
- [ ] 单行三个小指标（能耗/用电/速度）按 nil **整格消失**，只有速度时只显示 1 格
- [ ] `startedAt == nil` 的行显示 `"行程 1"`（index+1）；`endedAt == nil` 显示 `"结束时间未知"`
- [ ] 灌 600 条行程，列表滚动不掉帧；`interfaceRideCount` 诊断值为 500

---

## 3.2 行程详情（2 天）

### 一 · iOS 现状

| 组件 | 位置 |
| --- | --- |
| `NinebotRideDetailView` | `NinebotDashboardView.swift:4084-4160` |
| `RideDetailHero` | `:4162-4246` |
| `DetailSection` / `DetailRow` | `:3843-3860` / `:3862-3901` |
| `BasicInfoTile` | `:3690-3728` |
| `RawJSONSection` | `:4643-4717` |
| `RawFieldSection` | `:4578-4641` |
| `RawFieldRow` | `:4719-4748` |
| `friendlyRawFieldName`（122 条映射） | `:4967-5093` |
| `RideTrackMapPanel`（本地轨迹，Phase 4） | `:4248-4336` |
| `InterfaceRideTrackMapPanel`（接口轨迹，Phase 4.1） | `:4337-4416` |

数据侧：

| 逻辑 | 位置 |
| --- | --- |
| `NinebotRideDetail` | `NinebotModels.swift:288-302` |
| `fetchTravelDetail` | `NinebotServerClient.swift:165-178` |
| `rideRecord(from:index:)` | `:679-710` |
| `firstDurationMinutes` 及其四个助手 | `:881-895`、`:1056-1108` |
| `dateValue` / `structuredChinaDateValue` / `epochDateValue` | `:923-963`、`:1027-1044`、`:1046-1054` |
| `JSONValue` 访问器 | `NinebotModels.swift:1984-2071` |
| `refreshRideDetail` | `NinebotViewModel.swift:441-459` |
| `rideDetail(vehicleSN:rideID:)` / `rideDetailKey` | `:433-435` / `:539-541` |

**页面骨架**（`:4096-4131`）

```
ScrollView
└─ VStack(alignment:.leading, spacing:16)   padding(16)
   ├─ RideDetailHero(effectiveRecord, detailLocalRecord)
   ├─ 有本地轨迹 → RideTrackMapPanel .id(points.count)      ← Phase 4
   │  否则有接口轨迹点 → InterfaceRideTrackMapPanel          ← Phase 4.1
   ├─ DetailSection("接口行程") { 8 × DetailRow }
   ├─ RawJSONSection("行程详情完整返回值", remoteDetail?.raw)
   └─ RawFieldSection("列表原始字段", record.raw)
背景 teslaPageBackground，navigationTitle "行程详情"，displayMode .inline
.task(id: "{vehicleSN}|{record.id}") { loadLocalTrack(); await loadRemoteDetail() }
```

### 二 · 要移植的逻辑

#### 2.1 「列表记录」与「详情记录」的双源覆盖

```
remoteDetail    = model.rideDetail(vehicleSN:, rideID: record.id)     :4142-4145
effectiveRecord = remoteDetail?.parsedRecord ?? record                :4147-4149
```

`parsedRecord` 是详情返回值走**同一个** `rideRecord(from:index:0)` 解出来的（`NinebotServerClient.swift:176`）。所以详情页打开的瞬间显示列表行那份数据，请求回来后整页字段被详情那份替换。两份的解析规则完全一样，但键可能不同（列表返回 `mileages`、详情返回 `mileage`），数值也可能不同。

**唯一的例外**：`DetailRow("行程 ID")` 用的是 `record.id`（列表那份），不是 `effectiveRecord.id`（`:4116`）。其余 7 行全用 `effectiveRecord`。

请求闸门（`NinebotViewModel.swift:441-459`）：

```
key = "{vehicleSN}|{rideID}"
!force && rideDetails[key] != nil → 直接返回（内存里有就不再请求）
loadingRideDetailKeys 含 key      → 直接返回（同一条不并发）
成功 → rideDetails[key] = detail; errorMessage = nil
失败 → errorMessage = 错误描述     ← 不写 statusMessage、不记诊断事件、不显示加载条
```

`rideDetails` 是纯内存 `@Published` 字典，**从不落盘**（全仓无 `saveRideDetail`）。冷启动后每条详情都要重新请求一次。

`isLoadingRideDetail(vehicleSN:rideID:)`（`:437-439`）**是死代码**，没有任何调用点。详情页**没有加载指示器**，唯一的「正在加载」提示是 `RawJSONSection` 在 `value == nil` 时那句 `"详情返回后会显示完整字段"`（`:4674`）。

#### 2.2 宽松取值 —— 这是 3.2 的核心

九号返回的形状不稳定，iOS 的容错分三层。

**第一层：`JSONValue` 访问器**（`NinebotModels.swift:1984-2042`，规则在 Phase 0 §0.1 已定，这里只列会影响 3.2 的部分）

| 访问器 | 规则 |
| --- | --- |
| `stringValue` | `.string` 原样；`.number` 且 `rounded() == 值` → `String(Int(值))`，否则 `String(Double)`；`.bool` → `"true"`/`"false"`；其他 → nil |
| `doubleValue` | `.number` 原样；`.string` → `Double(字符串)`；`.bool` → 1/0；其他 → nil |
| `intValue` | `Int(doubleValue)`（截断；Swift 对 NaN/Inf 会崩，见 3.1 陷阱 7） |
| `boolValue` | `.bool` 原样；`.number` → `!= 0`；`.string` 裁剪+小写后在 `{1,true,yes,on}` → true、`{0,false,no,off}` → false、其他 → nil |
| `displayText` | object → 按 key 升序 `"k: v"` 逗号连接、空 → `"{}"`；array → 逗号连接、空 → `"[]"`；number 整数去小数点；null → `"null"` |

**`Double(字符串)` 的 Swift/Java 差异必须处理。** Swift 的 `Double.init(String)` 严格：不接受首尾空白、不接受 `"12.5d"`/`"12.5f"` 后缀。Java 的 `Double.parseDouble`（Kotlin `toDouble()`）两者都接受。所以 `{"mileage": " 12.5 "}` 在 iOS 是 nil（走兜底 `"-- km"`），在 Android 会解成 12.5。用带正则门槛的实现：

```kotlin
private val SWIFT_DOUBLE = Regex("""^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$""")

fun swiftDouble(text: String): Double? = when {
    SWIFT_DOUBLE.matches(text) -> text.toDoubleOrNull()
    text.equals("inf", true) || text.equals("infinity", true) -> Double.POSITIVE_INFINITY
    text.equals("-inf", true) || text.equals("-infinity", true) -> Double.NEGATIVE_INFINITY
    text.equals("nan", true) -> Double.NaN
    else -> null                                   // 十六进制浮点 0x1p3 之类不管，实践中不出现
}
```

**第二层：多键名 + 归一化**（键顺序见 3.1 §2.8，逐字符不能错）

**第三层：时长的三级推断**（`NinebotServerClient.swift:881-895`）

```
derived = durationMinutes(startedAt, endedAt)                          :1084-1089
        = (end - start)/60，且必须 0 < m <= 2880（48 小时），否则 nil

1. firstDurationValue(["durationMinutes","duration_min","durationMin"])
     → saneDuration(值, fallback: derived)
2. firstDurationValue(["duration_seconds","durationSeconds","ride_seconds","riding_seconds"])
     → saneDuration(值/60, fallback: derived)
3. firstDurationValue(["duration","ride_time","rideTime","riding_time","ridingTime",
                       "use_time","useTime","cost_time","costTime"])
     → saneDuration(ambiguousDurationMinutes(值, derived), fallback: derived)
4. 都没有 → derived
```

三个助手：

```
firstDurationValue(keys, object):                                      :1056-1067
    逐键：先试 clockDurationMinutes（含冒号的字符串）
          再试 doubleValue > 0
    都不成立换下一个键

clockDurationMinutes(value):                                           :1069-1082
    字符串且含 ":" 才处理；按 ":" 切分并全部转 Double
    2 段 → parts[0] + parts[1]/60          ← 按「分:秒」解！"1:30" = 1.5 分钟
    3 段 → parts[0]*60 + parts[1] + parts[2]/60   ← 按「时:分:秒」解，"01:30:00" = 90 分钟
    其他段数 → nil

ambiguousDurationMinutes(value, derived):                              :1091-1101
    derived == nil → value > 300 ? value/60 : value      ← 大于 300 猜是秒
    否则 → 在 {value, value/60} 里选离 derived 更近的那个

saneDuration(value, fallback):                                         :1103-1108
    0 < value <= 2880 → value；否则 fallback
```

**2 段按「分:秒」、3 段按「时:分:秒」** 是最容易写反的一处。`"45:00"` 会解成 45 分钟（45 + 0/60），恰好看起来对；但 `"1:30"` 解成 1.5 分钟而不是 90 分钟。原样照抄。

时长有关的既有测试：`ServerClientTests.swift:632-671`（start/end 相差 30 分钟 → `durationMinutes == 30`）与 `:686-709`（详情端点，20 分钟）。

**日期解析**（`:923-963`，规则在 Phase 0 §0.2 已定）走 `dateValue`：只接受字符串形态（`stringValue`），依次试「纯数字按长度」→「epoch」→「10 种格式」→「ISO8601」。要注意 `startedAt` 的键列表里有 `"day"` 和 `"date"`：`{"day": 15}` → `stringValue` `"15"` → 长度不是 14/12/8 → `Double("15")=15` → 不 > 1e9 → nil，安全落空；`{"date": "20240115"}` → 8 位 → `yyyyMMdd` → 解出来。别把 `"day"` 从列表里删掉，也别把它当日期加工。

#### 2.3 `RideDetailHero`（`:4162-4246`）

```
VStack(alignment:.leading, spacing:18)   padding(16)
├─ HStack
│  ├─ VStack(alignment:.leading, spacing:4)
│  │  ├─ startedAt → formatRideDate；nil → "行程详情"     headline, primaryText
│  │  └─ localRecord != nil → "已关联本地轨迹"             caption/medium, teslaGreen
│  ├─ Spacer()
│  └─ localRecord != nil → map.fill                       title3/semibold, teslaGreen
├─ HStack(alignment:.lastTextBaseline, spacing:8)
│  ├─ formatDistance(mileage)  system(size:40, weight:.semibold, design:.rounded)
│  │                           monospacedDigit lineLimit1 minimumScaleFactor 0.72
│  └─ "里程"                    footnote/medium, secondaryText
└─ metrics 非空 → LazyVGrid(gridColumns, spacing:10){ BasicInfoTile × n }
teslaCardBackground，圆角 18 continuous，阴影 黑4% r14 y8，无描边
```

`gridColumns`（`:4218-4226`）：`metrics.count <= 1` → **1 列**；否则 2 列，间距 10。

`metrics`（`:4228-4245`）—— 前四项 `compactMap`（nil 整格消失），后三项只在有本地记录时无条件追加：

| 顺序 | 条件 | title | value | 图标 |
| --- | --- | --- | --- | --- |
| 1 | `speed != nil` | **接口速度** | `formatSpeed` | `speedometer` |
| 2 | `energy != nil` | 能耗 | `formatEnergyWh` | `bolt.horizontal.fill` |
| 3 | `usedElectricity != nil` | 用电 | `formatPercent` | `powerplug.fill` |
| 4 | `durationMinutes != nil` | 时长 | `formatDuration` | `timer` |
| 5 | 有本地记录 | 本地极速 | `formatSpeed(maxSpeedKmh)` | `gauge.with.dots.needle.67percent` |
| 6 | 有本地记录 | 最大 G | `formatAccelerationG(maxAccelerationG)` | `bolt.circle.fill` |
| 7 | 有本地记录 | 轨迹点 | `"{trackPointCount} 个"` | `point.3.connected.trianglepath.dotted` |

第 1 格标题是 **「接口速度」**，不是列表行里的「速度」。别统一。

#### 2.4 「接口行程」8 行（`:4108-4117`，顺序与文案照抄）

| # | title | value | 图标 |
| --- | --- | --- | --- |
| 1 | 开始时间 | `startedAt → formatDate` / `"--"` | `play.fill` |
| 2 | 结束时间 | `endedAt → formatDate` / `"--"` | `stop.fill` |
| 3 | 里程 | `formatDistance(mileage)` | `road.lanes` |
| 4 | 时长 | `formatDuration(durationMinutes)` | `timer` |
| 5 | 速度 | `formatSpeed(speed)` | `speedometer` |
| 6 | 能耗 | `formatEnergyWh(energy)` | `bolt.horizontal.fill` |
| 7 | 用电 | `formatPercent(usedElectricity)` | `powerplug.fill` |
| 8 | 行程 ID | **`record.id`**（列表那份） | `number` |

这两行的兜底不一样：1/2 行是 `"--"`（`.map` + `?? "--"`），3–7 行是各 formatter 自己的兜底（`"-- km"` / `"--"` / `"-- km/h"` / `"-- Wh"` / `"--%"`）。别统一成一种。

`DetailRow`（`:3862-3901`）：图标 20pt 宽、title 固定 82pt 宽左对齐、value 右对齐 `lineLimit(3)` `minimumScaleFactor(0.72)` 可选中；`value.isEmpty → "--"`；行 padding(h:12, v:9)。`DetailSection`（`:3843-3860`）：标题 subheadline/semibold secondary，内容 `VStack(spacing:0)` 套 `tertiarySystemGroupedBackground` + 圆角 18。

#### 2.5 两张原始字段卡

`RawJSONSection("行程详情完整返回值", remoteDetail?.raw)`（`:4643-4717`）：

```
value == nil            → "详情返回后会显示完整字段"（subheadline, secondary）
value 是非空 object     → 按 key 的 localizedStandardCompare 升序，每键一个 RawFieldRow
value 是空 object 或非 object → 整段 displayText，footnote.monospaced，可选中，
                          padding 12 + tertiarySystemGroupedBackground + 圆角 18
```

`RawFieldSection("列表原始字段", record.raw)`（`:4578-4641`）：同样的排序，`fields` 为 nil 或空 → `"暂无数据"`。

两者的「复制」交互一致：标题行右侧一个 `.bordered` `.small` 的 `Label("复制", systemImage:"doc.on.doc")`，点击后写系统剪贴板、切成 `Label("已复制", systemImage:"checkmark.circle.fill")`（teslaGreen），**1.4 秒**后恢复（`:4634-4640`、`:4710-4716`）。复制内容是 `formattedJSON`（`NinebotFormatting.swift:115-123`）：`prettyPrinted` + `sortedKeys` + `withoutEscapingSlashes`，编码失败退回 `displayText`。

`RawFieldRow`（`:4719-4748`）：`friendlyRawFieldName(key)` 作为主标题（footnote/semibold），**中文名和原键不同时**在下面补一行原键（caption2.monospaced，tertiary，可选中），再是值（footnote，可选中，可换行）；值为空串显示 `"--"`。

`friendlyRawFieldName`（`:4967-5093`）是 122 条 `[String: String]` 字典，查不到**原样返回键名**。与行程相关的条目：`travel_id`→行程 ID、`begin_time`/`beginTime`→开始时间、`cost_time`/`costTime`→用时、`speed`→速度、`total_mileages`→**本月里程**、`total_mileage`/`totalMileage`→总里程、`times`→骑行次数、`used_electricity`→已用电量、`track`/`trail`/`trial`→接口轨迹。注意 `total_mileage`（总里程）和 `total_mileages`（本月里程）只差一个 s、含义完全不同。

### 三 · Android 实现要点

#### 3.1 详情仓库

```kotlin
// core/data/RideDetailRepository.kt
class RideDetailRepository(private val api: NinebotApi) {
    private val cache = MutableStateFlow(emptyMap<String, RideDetail>())
    private val inFlight = mutableSetOf<String>()          // 由 Mutex 保护
    private val mutex = Mutex()

    fun detail(sn: String, rideId: String): Flow<RideDetail?> =
        cache.map { it["$sn|$rideId"] }.distinctUntilChanged()

    suspend fun load(sn: String, rideId: String, force: Boolean = false) {
        val key = "$sn|$rideId"
        mutex.withLock {
            if (!force && cache.value.containsKey(key)) return
            if (!inFlight.add(key)) return
        }
        try {
            val detail = api.travelDetail(sn, rideId)       // GET /vehicles/{sn}/travel/{id}
            cache.update { it + (key to detail) }
        } catch (t: Throwable) {
            errorBus.emit(t.readableMessage())              // 与 iOS 一致：只报错，不改 status
        } finally {
            mutex.withLock { inFlight.remove(key) }
        }
    }
}
```

`RideDetail.id` = `"$vehicleSn|$rideId"`（`NinebotModels.swift:295-297`），键格式和 `rideDetailKey`（`NinebotViewModel.swift:539-541`）一致，两处必须同一个函数。

Repository 单例（不是 ViewModel 字段）持有 cache，这样返回列表再进详情不重复请求，对齐 iOS 的 `@Published rideDetails`。**是否落 Room 见待定 T7。**

页面侧：

```kotlin
LaunchedEffect(sn, record.id) {           // 对齐 .task(id: "{sn}|{id}")
    repo.load(sn, record.id)
}
val remote by repo.detail(sn, record.id).collectAsStateWithLifecycle(null)
val effective = remote?.parsedRecord ?: record
```

`canLoadRemoteDetail`（`:4138-4140`）：`vehicleSN` 非空且非空串、`record.id` 非空。两个条件都要，不然会打出 `GET /vehicles//travel/`。

#### 3.2 宽松取值放哪

`swiftDouble` / `stringValue` / `intValue` / `boolValue` 属于 Phase 0 §0.1 的 `JsonElement` 扩展，3.2 不重复实现，但 3.2 是它们第一次被真实的畸形数据压测的地方。把 `RideDetailParsingTests` 里那些形状（数字/字符串/布尔互换、snake/camel 并存、嵌套包裹）做成 JSON fixture 文件放共享目录，两端同一批文件跑。

`durationMinutes` 的三级推断属于领域层：

```kotlin
// core/domain/trip/RideDuration.kt —— 纯 Kotlin，可单测
object RideDuration {
    private const val MAX_MINUTES = 48.0 * 60          // 2880
    fun resolve(obj: JsonObject, startedAt: Instant?, endedAt: Instant?): Double? { ... }
    internal fun derived(startedAt: Instant?, endedAt: Instant?): Double?
    internal fun clockMinutes(value: JsonElement): Double?     // 2 段=分:秒，3 段=时:分:秒
    internal fun ambiguous(value: Double, derived: Double?): Double
    internal fun sane(value: Double, fallback: Double?): Double?
}
```

#### 3.3 界面

- `RideDetailScreen`：`Column` + `verticalScroll`，`Arrangement.spacedBy(16.dp)`，`padding(16.dp)`。
- 40sp 巨型里程：`BasicText` + `TextAutoSize.StepBased(minFontSize = 29.sp, maxFontSize = 40.sp)`（0.72 × 40 ≈ 29），或退化成 `maxLines = 1, overflow = Ellipsis`。
- `metrics.size <= 1` 时单列：`if (metrics.size <= 1) Column {} else LazyVGrid(2 列)`；行数固定且很少（最多 7），用 `Column` + `Row` 手排，不用 `LazyVerticalGrid`（放在可滚动 `Column` 里会因高度无界崩）。
- 两张原始字段卡用 `ExpandableCard`（对应 `DisclosureGroup`），默认折叠。key 排序用 `Collator.getInstance(Locale.CHINA)` 近似 `localizedStandardCompare`（它对 `"item2"` / `"item10"` 做数字感知排序，纯 `compareTo` 会把 `item10` 排在 `item2` 前）。
- 复制走 `ClipboardManager.setText`，1.4 秒后用 `LaunchedEffect(didCopy) { delay(1400); didCopy = false }` 恢复。**Android 13+ 系统自己会弹「已复制」气泡**，界面里那个「已复制」标签会和它重复；保留（与 iOS 一致），必要时改成只保留一个，属于收尾细节。
- `friendlyRawFieldName` 的 122 条映射进 `strings.xml`？**不要**。键名是数据不是文案，放 Kotlin `mapOf` 常量（`core/domain/RawFieldNames.kt`），不然 `strings.xml` 里会多 122 个永不本地化的条目。

### 四 · 陷阱

1. **`"1:30"` 是 1.5 分钟不是 90 分钟。** `clockDurationMinutes` 的 2 段分支按「分:秒」解（`NinebotServerClient.swift:1078-1080`）。照直觉写成「时:分」会让所有短行程的时长放大 60 倍。

2. **`Double(字符串)` 的 Swift/Java 松紧不同。** Java 接受首尾空白和 `d`/`f` 后缀，Swift 不接受。`{"speed": " 25 "}` 两端会得到不同结果（iOS `"-- km/h"`，Android `"25 km/h"`）。用带正则门槛的 `swiftDouble`。

3. **详情页没有加载指示器。** `isLoadingRideDetail` 是死代码（`NinebotViewModel.swift:437-439`，无调用点）。iOS 的表现是：打开详情先显示列表行那份数据，几百毫秒后整页字段悄悄换成详情那份。Android 若要加骨架屏就是主动改动，改之前先确认 —— 无声替换会让用户看到数字跳变。

4. **「行程 ID」那一行用列表的 `record.id`**（`:4116`），其余 7 行用 `effectiveRecord`。详情返回的 id 和列表的 id 不同时（列表用 `travel_id`、详情走到了 `"\(index)"` 兜底），界面显示的是列表那个。原样保留。

5. **`total_mileage` 与 `total_mileages` 差一个 s，含义分别是「总里程」和「本月里程」**（`friendlyRawFieldName`，`:5072-5074`）。原始字段面板里两个都可能出现，映射表不能合并。

6. **`electricity` 一键两义**：在行程记录里是能耗（第三顺位，`:690`），在车辆状态里是电量百分比（第三顺位，`:581`）。两处的取值函数不能共用。

7. **详情缓存不落盘**，冷启动每条都重新请求。10 条行程逐个点开就是 10 个请求，来回翻则每次都命中内存缓存。别在 Android 侧把 cache 放进 `ViewModel`（进程死亡后 `SavedStateHandle` 存不下 JSON），要么放 Repository 单例（对齐 iOS），要么落 Room（见待定 T7）。

8. **`intValue` 不要照抄成会抛异常的版本**（见 3.1 陷阱 7）。

9. **`LazyVerticalGrid` 不能放进 `verticalScroll` 的 `Column`**，会抛「Vertically scrollable component was measured with an infinity maximum height」。指标格最多 7 个，直接 `Column` + `Row` 手排。

10. **`localizedStandardCompare` 是数字感知的**，`"battery_2"` 排在 `"battery_10"` 前面。用 `compareTo` 会得到不同的行顺序。

### 五 · 验收标准

- [ ] 造 12 份畸形 JSON fixture（数字↔字符串互换、布尔↔0/1、snake/camel 同存、`list` 不是数组、字段整段缺失、`mileages` 与 `mileage` 同时出现），两端解析出的 `RideRecord` 每个字段**完全相同**（用共享 fixture 目录，不靠肉眼）
- [ ] 时长三级各命中一次：`durationMinutes: 30`、`duration_seconds: 1800`、`duration: 1800`（有 derived 时选 30）、`duration: 1800`（无 derived 时 > 300 → 30）、`duration: "01:30:00"` → 90、`duration: "1:30"` → **1.5**
- [ ] `saneDuration` 边界：`0` → 落 derived；`2880` → 取用；`2881` → 落 derived；derived 也无 → nil → `"--"`
- [ ] `derived` 边界：end == start → nil；end - start = 48h → 2880；48h + 1s → nil
- [ ] `" 25 "` 与 `"25f"` 解析结果与 Swift 一致（都是 nil）
- [ ] 移 `ServerClientTests.swift:686-709`：`GET /vehicles/SN1/travel/T9` → `id == "SN1|T9"`、`parsedRecord.id == "T9"`、`mileage == 3.2`、`durationMinutes == 20`
- [ ] 移 `ModelCodingTests.swift:368-396`：`RideDetail` 编解码往返、缺 `parsedRecord` 时为 null、`fetchedAt` 为 epoch 秒时能解
- [ ] 详情请求闸门：同一条连点 5 次只发 1 个请求；返回后再进不发请求；`force = true` 重新发
- [ ] `vehicleSN` 为空串或 `record.id` 为空串时**不发请求**（不能出现 `/vehicles//travel/`）
- [ ] 「接口行程」8 行的顺序、标题、兜底逐字符与表格一致（第 1/2 行 `"--"`，第 3–7 行各自的 formatter 兜底）
- [ ] 「行程 ID」显示列表那份 id：构造「列表 id = T-1、详情 id = 0」的场景，界面显示 `T-1`
- [ ] `metrics` 只有 1 项时单列铺满；4 项时 2×2；有本地记录时 7 项（3 行 + 1 个占半格）
- [ ] 第 1 格标题是「接口速度」不是「速度」
- [ ] 两张原始字段卡：key 按数字感知升序（`f_2` 在 `f_10` 前）；中文名与原键不同时补一行灰色原键；空值显示 `"--"`
- [ ] 复制后标签 1.4 秒内是「已复制」并恢复；剪贴板内容是 `prettyPrinted` + key 升序 + 不转义 `/`
- [ ] `RawJSONSection` 的三种形态：nil → 「详情返回后会显示完整字段」；非空 object → 逐键行；数组/标量 → 整段等宽文本
- [ ] 设备时区改 UTC-8，开始/结束时间仍显示北京时间（`formatDate` 恒 `Asia/Shanghai`）
- [ ] 系统最大字号 + 360dp：40sp 巨型里程不被裁，`DetailRow` 的 82dp 标题列不挤压右侧数值

---

## 3.3 里程趋势柱状图（2 天）

### 一 · iOS 现状

`TrendBarChart` 是手写的 `GeometryReader`，两处复用：

| 组件 | 位置 | 喂什么 |
| --- | --- | --- |
| `TrendBarValue` | `NinebotDashboardView.swift:3035-3040` | `id` / `label` / `value` / `tint` |
| **`TrendBarChart`** | **`:3042-3101`** | `[TrendBarValue]` |
| `TripRecentRideBars` | `:3103-3116` | 最近 8 次骑行 → `TrendBarValue` |
| `EmptyTrendState` | `:3118-3130` | 空数据兜底 |
| `TripTrendDailyCard` | `:2863-2923` | 每日里程（近 14 天），`frame(height: 176)` |
| `TripTrendRideCard` | `:2925-2965` | 最近骑行，`frame(height: 168)` |
| `ControlMetricPill` | `:2031-2054` | 图表下面那排 3 个小胶囊 |
| `shortTrendValue` | `NinebotFormatting.swift:93-101` | 柱顶数字 |
| `dailyMileageRecords(from:)` | `NinebotServerClient.swift:712-729` | 每日里程的数据来源 |
| `analysis.dailyRecords` | `NinebotTripTrend.swift:52-59` | 排序 |

另有一个 `DailyMileagePanel`（`:3169-3225`）+ `DailyMileageLineChart`（`:3227-3291`）—— 折线版的每日里程卡。**`DailyMileagePanel` 在全仓没有任何使用点，是死代码**（`DailyMileageLineChart` 只被它引用）。**不要移植这两个**，Phase 2.5 的电池历史折线图是另一份代码。

**趋势页没有月份选择器。** `TripTrendView`（`:2698-2726`）的入参只有 `snapshot` 和 `recordedRides`，图表数据来自 `snapshot.state.dailyMileages`，而那是 dashboard 的 `travel` 载荷（当月）解出来的。行程页顶部那个月份筛选**不影响**趋势页。

### 二 · 要移植的逻辑

#### 2.1 坐标计算（`:3042-3101`，可 1:1 直译）

外层修饰（`:3096-3099`）：`.padding(.horizontal, 10)` `.padding(.vertical, 12)`，背景 `teslaControlBackground`，圆角 **18** continuous。

`padding` 写在 `GeometryReader` 之后，所以 `proxy.size` 是**扣掉 padding 后**的尺寸：

```
proxy.width  = 卡片内容宽 - 20
proxy.height = frame 高度 - 24
```

三个派生量（`:3047-3049`）：

```
maxValue    = max(values.map(\.value).max() ?? 0, 1)        ← 分母至少 1
chartHeight = max(proxy.height - 42, 1)                     ← 42 = 柱顶数字 + 底部标签 + 两个 6pt 间距
barWidth    = min(max(proxy.width / max(count, 1) * 0.24, 4), 11)   ← 夹在 [4, 11]
```

两处调用的实际值：

| 卡片 | `frame(height:)` | `proxy.height` | `chartHeight` |
| --- | --- | --- | --- |
| `TripTrendDailyCard`（每日里程） | 176 | 152 | **110** |
| `TripTrendRideCard`（最近骑行） | 168 | 144 | **102** |

网格线（`:3052-3060`）：

```swift
VStack(spacing: 0) {
    ForEach(0..<4) { _ in
        Divider().opacity(0.55)
        Spacer(minLength: 0)
    }
}
.padding(.horizontal, 4)
.padding(.bottom, 20)
```

4 条 1pt 水平线 + 4 个等分 Spacer，作用区高度 = `proxy.height - 20`。等价于：在 `[0, proxy.height - 20]` 区间里画 **4** 条线，位置为 `i × (proxy.height - 20) / 4`（`i = 0..3`），**最底下没有线**，左右各内缩 4pt，不透明度 0.55。

柱子（`:3062-3093`），整体在 `ZStack(alignment: .bottom)` 里贴底：

```
HStack(alignment: .bottom, spacing: count > 10 ? 7 : 10)
└─ 每项 VStack(spacing: 6).frame(maxWidth: .infinity)      ← 等宽平分
   ├─ Text(shortTrendValue(value))
   │    caption2 · monospacedDigit · semibold · secondaryText · lineLimit1 · minScale 0.55
   ├─ ZStack(alignment: .bottom)
   │  ├─ Capsule fill secondaryText@10%   width barWidth  height chartHeight     ← 轨道
   │  └─ Capsule fill LinearGradient([tint@72%, tint], .bottom → .top)
   │       width barWidth  height max(6, chartHeight × value / maxValue)          ← 实柱
   └─ Text(label)
        caption2 · monospacedDigit · medium · secondaryText · lineLimit1
```

**实柱高度下限是 6pt**：`value == 0` 时仍然是一个 6pt 高的胶囊，不是完全空。轨道恒为 `chartHeight` 满高。柱宽固定 `barWidth`，居中在等宽的 slot 里（`frame(maxWidth: .infinity)` 默认居中）。

**没有动画**、没有点击、没有 tooltip、没有坐标轴文字（只有柱顶数字和柱底标签）。

#### 2.2 柱顶数字：`shortTrendValue`（`NinebotFormatting.swift:93-101`）

```
value >= 100 → formatNumber(value, unit:"", maximumFractionDigits: 0)
value >= 10  → formatNumber(value, unit:"", maximumFractionDigits: 1)
其他         → formatNumber(value, unit:"", maximumFractionDigits: 1)
```

后两个分支的实现完全相同，**净效果就是：≥100 取整，其余保留 1 位小数**。原样保留这个三分支写法没有意义，写成两分支即可，但阈值 100 和位数 0/1 必须精确。`formatNumber` 的最少小数位是 0，所以 `12.0 → "12"`、`0 → "0"`、`105.4 → "105"`。

#### 2.3 每日里程卡（`TripTrendDailyCard`，`:2863-2923`）

| 位置 | 取值 |
| --- | --- |
| 标题 | `"每日里程趋势"` headline |
| 副标题 | 空 → `"等待接口返回本月 detail"`；否则 `"最近 {visibleRecords.count} 天"` |
| 右上数字 | `formatDistance(records.map(\.mileage).max())` headline/monospacedDigit/semibold **teslaGreen** |
| 空态 | `EmptyTrendState("暂无每日里程趋势")` |
| 图表 | `visibleRecords.map { TrendBarValue(id: $0.id, label: "\($0.day)", value: $0.mileage, tint: teslaGreen) }`，`frame(height: 176)` |
| 胶囊 1 | 日均 `formatDistance(averageMileage)` `chart.bar.xaxis` |
| 胶囊 2 | 最高 `formatDistance(peakMileage)` `arrow.up.right` |
| 胶囊 3 | 活跃 `"{records.count} 天"` `calendar` |

```
visibleRecords = Array(records.suffix(14))          :2911-2913   ← 最后 14 天
averageMileage = 空 ? nil : sum / count             :2915-2918   ← 分母是「全部」记录数，不是 14
peakMileage    = records.map(\.mileage).max()       :2920-2922   ← 同样是全部
```

**副标题里的天数是 14（可见），三个胶囊和右上数字是全部。** 一个 31 天的月份会显示「最近 14 天」+「活跃 31 天」，两个数字不一样。原样保留。

标签是 `record.day`（1–31），不是序号，所以 x 轴读作「几号」。

卡片：padding 16，teslaCardBackground，圆角 24 continuous，阴影 黑5% r14 y8，**无描边**。

#### 2.4 数据来源与「月份」（`NinebotServerClient.swift:712-729`）

```
detail = travelObject["detail"]?.arrayValue，缺失 → []（卡片进空态）
month  = travelObject["month"]（字符串）
limit  = (month == 当月) ? min(detail.count, 今天几号) : detail.count
逐项：index + 1 = 日；value.doubleValue 解不出来则丢掉该项（日号不重排）
      id   = "{month ?? "month"}-{day}"
      date = date(month:day:)（Asia/Shanghai 构造，month 长度不是 6 → nil）
```

**当月会按「今天几号」截断**，所以本月后面还没到的日子不会画成一堆 0 柱。`Calendar.current.component(.day, from: Date())` 用的是**设备时区**，而 `date(month:day:)` 用 `Asia/Shanghai` —— 跨时区设备在月初/月末会差一天。

排序在 `NinebotTripTrend.dailyRecords`（`NinebotTripTrend.swift:52-59`）：两条都有 `date` 时按 `date` 升序，否则按 `day` 升序。测试 `TripTrendTests.swift:153-159`（倒序输入 → 输出 `[1,2,3]`）。

**趋势页的图表恒为「dashboard 当次拉到的那个月」，通常是当月。** 没有任何路径能让它显示 2024.03 的每日里程。

#### 2.5 最近骑行卡（`TripTrendRideCard`，`:2925-2965`）

| 位置 | 取值 |
| --- | --- |
| 标题 | `"最近骑行表现"` |
| 副标题 | 空 → `"等待行程列表"`；否则 `"最近 {recentRides.count} 次"` |
| 右上数字 | `formatSpeed(analysis.averageSpeed)` headline/monospacedDigit/semibold teslaGreen |
| 空态 | `EmptyTrendState("暂无最近骑行数据")` |
| 图表 | `TripRecentRideBars(records: analysis.recentRides)`，`frame(height: 168)` |
| 胶囊 1 | 平均速度 `formatSpeed(averageSpeed)` `speedometer` |
| 胶囊 2 | 平均用电 `formatPercent(averageUsedElectricity)` `powerplug.fill` |
| 胶囊 3 | 最高里程 `formatDistance(peakRideMileage)` `arrow.up.right` |

`TripRecentRideBars`（`:3103-3116`）：

```
id    = ride.id                                    ← 不是 stableIdentityKey
label = "\(index + 1)"                             ← 1 = 最新那次（rides 是时间倒序）
value = ride.mileage ?? 0                          ← nil 里程画成 0（6pt 短柱），不跳过
tint  = usedElectricity == nil ? teslaGreen
        : (usedElectricity > 15 ? Color.orange : teslaGreen)
```

**`Color.orange` 是系统橙，不是设计 token 里的颜色**；阈值 **15**（严格大于）是这里唯一的内联字面量，没有命名常量。

`recentRides` 最多 8 条（`NinebotTripTrend.recentRideDisplayCount`），所以 `count > 10` 恒为 false，间距恒 **10**；每日里程那张 14 条时间距恒 **7**。

**胶囊 3「最高里程」是全部行程的最大值**（`peakRideMileage`，`NinebotTripTrend.swift:104-106`），不是这 8 条的最大值。图表里最高的柱子和这个数字可能不一致。

`EmptyTrendState`（`:3118-3130`）：subheadline secondaryText 左对齐，padding 12，`teslaControlBackground`，圆角 18。

### 三 · Android 实现要点

#### 3.1 `TrendBarChart`（Compose，直译）

```kotlin
// feature/trips/TrendBarChart.kt
data class TrendBarValue(val id: String, val label: String, val value: Double, val tint: Color)

private const val LABEL_BLOCK_HEIGHT = 42.dp        // 柱顶数字 + 柱底标签 + 2×6dp 间距
private const val GRID_BOTTOM_INSET = 20.dp
private const val MIN_BAR_HEIGHT = 6.dp
private const val TRACK_ALPHA = 0.10f
private const val GRID_ALPHA = 0.55f

@Composable
fun TrendBarChart(values: List<TrendBarValue>, modifier: Modifier = Modifier) {
    Box(
        modifier
            .clip(RoundedCornerShape(18.dp))
            .background(NinePlusTheme.colors.controlBackground)
            .padding(horizontal = 10.dp, vertical = 12.dp),      // ← 内容区 = 外框 - 20/-24
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val maxValue = maxOf(values.maxOfOrNull { it.value } ?: 0.0, 1.0)
            val chartHeight = (maxHeight - LABEL_BLOCK_HEIGHT).coerceAtLeast(1.dp)
            val barWidth = (maxWidth / maxOf(values.size, 1) * 0.24f)
                .coerceIn(4.dp, 11.dp)
            val spacing = if (values.size > 10) 7.dp else 10.dp

            // 网格：[0, maxHeight - 20] 区间 4 条线，i × H/4，左右内缩 4dp
            Canvas(Modifier.fillMaxWidth().height(maxHeight - GRID_BOTTOM_INSET).padding(horizontal = 4.dp)) {
                repeat(4) { i ->
                    val y = size.height * i / 4f
                    drawLine(gridColor.copy(alpha = GRID_ALPHA), Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
                }
            }

            Row(
                Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(spacing),
                verticalAlignment = Alignment.Bottom,            // ← ZStack(alignment:.bottom)
            ) {
                values.forEach { item ->
                    Column(
                        Modifier.weight(1f),                     // ← frame(maxWidth: .infinity)
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        AutoShrinkText(shortTrendValue(item.value), minScale = 0.55f, /* caption2 semibold mono */)
                        Box(contentAlignment = Alignment.BottomCenter) {
                            Box(Modifier.width(barWidth).height(chartHeight)
                                .clip(CircleShape).background(secondary.copy(alpha = TRACK_ALPHA)))
                            Box(Modifier.width(barWidth)
                                .height(maxOf(MIN_BAR_HEIGHT, chartHeight * (item.value / maxValue).toFloat()))
                                .clip(CircleShape)
                                .background(Brush.verticalGradient(   // 注意方向
                                    0f to item.tint, 1f to item.tint.copy(alpha = 0.72f),
                                )))
                        }
                        Text(item.label, /* caption2 medium mono */ maxLines = 1)
                    }
                }
            }
        }
    }
}
```

三处最容易出错：

1. **渐变方向反了**。SwiftUI 是 `startPoint: .bottom, endPoint: .top`，颜色数组第 0 项（`tint@72%`）在**底部**。Compose 的 `verticalGradient` 的 0f 是**顶部**，所以数组要倒过来：`0f to tint`（顶部满色）、`1f to tint@72%`（底部半透）。写顺了就是上下颠倒，肉眼可见。
2. **`padding` 的顺序决定 `BoxWithConstraints` 量到多少**。必须 `background` → `padding` → `BoxWithConstraints`，让约束是扣掉 10/12 之后的值。顺序写反，`chartHeight` 会大 24dp，柱子会顶出圆角。
3. **`Canvas` 里 `size.height * i / 4f` 只画 4 条线，最底下那条不画**（`i = 0..3`）。写成 `repeat(5)` 会多一条压在柱子底部。

`AutoShrinkText`：Compose 没有 `minimumScaleFactor`。用 `BasicText` + `TextAutoSize.StepBased(minFontSize = caption2Size * 0.55f, maxFontSize = caption2Size)`（Compose 1.8+），或退化成 `maxLines = 1, overflow = Ellipsis, softWrap = false`。柱顶数字在 14 柱 + 360dp 屏下 slot 只有约 15dp 宽，**一定会缩到 55%**，这不是异常。

#### 3.2 两个卡片

```kotlin
// core/domain/trip/TripTrendUi.kt —— 派生逻辑放领域层，Compose 只读
fun dailyBars(records: List<DailyMileageRecord>): List<TrendBarValue> =
    records.takeLast(14).map {
        TrendBarValue(it.id, it.day.toString(), it.mileage, GreenToken)
    }

fun recentRideBars(rides: List<RideRecord>): List<TrendBarValue> =
    rides.mapIndexed { index, ride ->
        TrendBarValue(
            id = ride.identityKey,                      // ← 修正：iOS 用 ride.id，可能重复
            label = (index + 1).toString(),
            value = ride.mileage ?? 0.0,
            tint = when {
                ride.usedElectricity == null -> GreenToken
                ride.usedElectricity > 15.0 -> SystemOrange   // 阈值 15，严格大于
                else -> GreenToken
            },
        )
    }
```

`SystemOrange` 用 `Color(0xFFFF9500)`（iOS `Color.orange` 亮色值）/ 暗色 `Color(0xFFFF9F0A)`，**不要**用 Material 的 `error` 或 `tertiary`。

卡片高度：`TrendBarChart(Modifier.height(176.dp))` / `.height(168.dp)`，不要用 `fillMaxHeight` 或 `aspectRatio`，`chartHeight` 是从固定高度倒推的。

### 四 · 陷阱

1. **`DailyMileagePanel` 和 `DailyMileageLineChart`（`:3169-3291`）是死代码，别移植。** 全仓无使用点。看到它们和 `TripTrendDailyCard` 长得像，会以为是「折线版」需要一起搬。

2. **趋势页没有月份切换。** 图表恒显示 dashboard 那次拉到的月份（当月）。行程页的月份筛选只影响列表。若要给趋势页加月份切换，就得先决定「每日里程从哪来」—— `dailyMileageRecords` 只从 `travel.detail` 出，而归档里只存行程不存每日里程。见待定 T8。

3. **`value = 0` 和 `value = null` 在图上完全一样**（都是 6pt 短柱 + 柱顶写 `"0"`）。`ride.mileage ?? 0`（`:3111`）把「接口没返回里程」和「真的骑了 0 公里」画成同一个东西。原样保留，但别在 UI 里补「无数据」灰柱 —— 那是改行为。

4. **`maxValue` 的分母下限是 1**，所以全 0 的一个月里每根柱子都是 6pt（`0/1 × 110 = 0` → `max(6, 0)`），看着像一排小点而不是空图。

5. **副标题的天数（14）和胶囊/右上角的天数（全部）不是一回事**（`:2873` vs `:2901`）。会被当成 bug 上报。

6. **「最高里程」胶囊统计全部行程，图表只画 8 条**（`NinebotTripTrend.swift:104-106` vs `:65-67`）。同理「平均速度」右上角与胶囊是同一个值但都是全部行程的平均，不是这 8 条的。

7. **`Color.orange` 是系统色不是 token**。橙柱在暗色下要用 `#FF9F0A`，直接抄亮色值会偏亮刺眼。

8. **`shortTrendValue` 的阈值是 100，不是 1000。** `105.4 → "105"`、`99.9 → "99.9"`。位数换错会让 x 轴挤爆（3 位小数点的数字在 15dp 宽的 slot 里放不下）。

9. **`chartHeight` 里那个 42 是硬编码的**（`:3048`）。它假设柱顶数字 + 柱底标签 + 两个 6pt 间距刚好 42pt。Compose 的 caption2 行高与 SwiftUI 不同（约 16sp vs 13pt），42dp 可能不够，柱子会被标签挤。**先量一次实际文本高度**，若不够就把常量调到实测值，但要在两端并排截图确认柱高比例仍一致。

### 五 · 验收标准

- [ ] `shortTrendValue`：`0 → "0"`、`4.55 → "4.5"`、`12.0 → "12"`、`99.9 → "99.9"`、`100 → "100"`、`105.4 → "105"`
- [ ] `barWidth` 三档：1 根柱（宽被夹到 11）、14 根柱（约 5.3）、40 根柱（被夹到 4）
- [ ] 间距：14 根柱为 7dp、8 根柱为 10dp、11 根柱为 7dp（`> 10` 是严格大于）
- [ ] `chartHeight`：176dp 卡片下为 110dp、168dp 卡片下为 102dp（用 UiAutomator 量柱轨道高度）
- [ ] 网格 4 条线，最上一条贴内容区顶、最下一条在 `(H-20) × 3/4` 处，**底部无线**，左右内缩 4dp
- [ ] 全 0 数据：每根柱 6dp 高、柱顶写 `"0"`，不是空图
- [ ] 单根柱 value == maxValue 时柱高等于轨道高，无溢出圆角
- [ ] 渐变方向：柱**顶**满色、柱**底** 72% 透明度，与 iOS 截图并排比对
- [ ] 每日里程卡：31 天数据时图表画 14 根、副标题「最近 14 天」、活跃胶囊「31 天」
- [ ] 每日里程卡的 x 轴标签是「日号」（如 `18 19 20 …`），不是 `1 2 3 …`
- [ ] 当月数据被截断到今天：本地日期设为 15 号，31 项 detail 只画 15 根
- [ ] 倒序输入的 `dailyRecords` 输出为 `day` 升序（移 `TripTrendTests.swift:153-159`）
- [ ] 最近骑行卡：8 次数据、标签 `1..8` 且 `1` 是最新那次
- [ ] `usedElectricity` 为 `15` → 绿柱；`15.1` → 橙柱；`null` → 绿柱
- [ ] 空数据两种文案：「暂无每日里程趋势」/「暂无最近骑行数据」；副标题「等待接口返回本月 detail」/「等待行程列表」
- [ ] 系统最大字号 + 360dp + 14 根柱：柱顶数字缩到 55% 不被裁、柱底日号不换行、图表不横向溢出
- [ ] 暗色模式下轨道（secondary@10%）可见、橙柱不刺眼
- [ ] 图表**无动画**：数据变化时柱子直接跳变（与 iOS 一致）

---

## 3.4 行程分析洞察（中文规则引擎，2 天）

### 一 · iOS 现状

规则和数值已经全部抽到领域层：**`mini-ninebot/Shared/NinebotTripTrend.swift`（160 行）**。文案留在界面层。

| 内容 | 位置 |
| --- | --- |
| `NinebotTripInsight`（6 个 case） | `NinebotTripTrend.swift:6-22` |
| **5 个命名阈值常量** | **`:40`、`:42`、`:44`、`:46`、`:48`** |
| 数据源集合（`dailyRecords`/`rides`/`recentRides`/`rideCount`/`activeDayCount`） | `:52-75` |
| 聚合量（`monthMileage`/`averageDailyMileage`/`averageSpeed`/`averageUsedElectricity`/`peakRideMileage`/`energyPerKm`） | `:79-123` |
| **`insights`（规则引擎本体）** | **`:129-159`** |
| `energyPerKmText` / `energyPerKmShortText` / `insightTexts`（视图层扩展） | `NinebotDashboardView.swift:3134-3148` |
| **`NinebotTripInsight.text`（6 条中文文案）** | **`NinebotDashboardView.swift:3150-3167`** |
| `TripTrendInsightCard`（渲染） | `:2967-2991` |
| `TripTrendView`（趋势页容器） | `:2698-2726` |
| `TripTrendHeroCard` | `:2773-2827` |
| `TrendHeroMetric` | `:2829-2861` |
| `TripTrendRangeModelCard` | `:2728-2771` |
| `TripTrendRecordedCard` | `:2993-3033` |
| 19 个单元测试 | `Tests/NineBotCoreTests/TripTrendTests.swift` |

`NinebotTripTrend` 的构造只要两样东西（`:29-31`）：`snapshot: NinebotVehicleSnapshot` 和 `recordedRides: [NinebotRecordedRide]`。`TripTrendView` 每次 `body` 求值都新建一个（`:2702-2704`，计算属性，无缓存）。

**趋势页骨架**（`:2706-2725`）

```
ScrollView
└─ VStack(alignment:.leading, spacing:16)   padding(16) + padding(.bottom, 12)
   ├─ TripTrendHeroCard(snapshot, analysis)
   ├─ TripTrendRangeModelCard(snapshot)                 ← Phase 2.3 的字段
   ├─ TripTrendDailyCard(analysis.dailyRecords)         ← 3.3
   ├─ TripTrendRideCard(analysis)                       ← 3.3
   ├─ TripTrendInsightCard(analysis)                    ← 3.4
   └─ recordedRides 非空 → TripTrendRecordedCard         ← Phase 4 之前恒不显示
navigationTitle "趋势分析"，displayMode .inline
```

### 二 · 要移植的逻辑

#### 2.1 五个命名阈值常量（值、单位、判定方向）

| 常量 | 值 | 单位 | 判定方向 | 行号 |
| --- | --- | --- | --- | --- |
| `longRidePeakRatio` | **1.8** | 倍（无量纲） | `peakRideMileage > averageDailyMileage × 1.8` —— **严格大于** | `:40` |
| `highAverageElectricityWh` | **12.0** | 常量名写 Wh，**实际比的是 `usedElectricity`，界面按 `%` 显示** | `averageUsedElectricity > 12.0` —— 严格大于 | `:42` |
| `highEnergyPerKmWh` | **35.0** | Wh/km | `energyPerKm > 35.0` —— 严格大于 | `:44` |
| `sufficientRangeSampleCount` | **5** | 次（有效行程样本数） | `observedRangeSampleCount < 5` → **触发**（「样本不够」，方向是小于） | `:46` |
| `recentRideDisplayCount` | **8** | 条 | `rides.prefix(8)`，不参与任何判定，只决定图表画几根柱 | `:48` |

**`highAverageElectricityWh` 的单位是矛盾的**：常量名和注释写 Wh，但它比的是 `NinebotRideRecord.usedElectricity`，而界面上这个字段一律用 `formatPercent` 渲染成百分比（列表行「用电」`:4068`、详情「用电」`:4115`、趋势胶囊「平均用电」`:2955`）。数值行为照抄 12.0，**不要**为了「修单位」去改成 12% 或做换算。文案侧那句洞察本身不带单位（见 §2.3），所以对用户不可见。见待定 T9。

`sufficientRangeSampleCount` 的方向和其他四个相反：它是「不足则触发」。`observedRangeSampleCount`（`NinebotModels.swift:1270-1276`）在 `serverPrediction?.range.sampleCount > 0` 时取服务端值，否则 **0**。**社区服务端不返回预测**，所以 `fewRangeSamples` 在当前部署下**恒触发**。测试 `TripTrendTests.swift:203-205` 钉了这一条。

#### 2.2 六个 case 与规则（`NinebotTripTrend.swift:6-22`、`:129-159`）

```swift
var insights: [NinebotTripInsight] {
    var result: [NinebotTripInsight] = []

    if let peak = peakRideMileage, let averageDailyMileage,
       peak > averageDailyMileage * Self.longRidePeakRatio {
        result.append(.longRideDominates)                              // :132-136
    }
    if let averageUsedElectricity, averageUsedElectricity > Self.highAverageElectricityWh {
        result.append(.highAverageElectricity)                         // :138-140
    }
    if let energyPerKm, energyPerKm > Self.highEnergyPerKmWh {
        result.append(.highEnergyPerKm)                               // :142-144
    }
    if snapshot.state.observedRangeSampleCount < Self.sufficientRangeSampleCount {
        result.append(.fewRangeSamples)                               // :146-148
    }
    if recordedRides.contains(where: { $0.associatedRideID == nil }) {
        result.append(.unlinkedLocalRides)                            // :150-152
    }
    if result.isEmpty { result.append(.normal) }                       // :154-156
    return result
}
```

| case | rawValue | 触发条件 | 定义行 |
| --- | --- | --- | --- |
| `longRideDominates` | `longRideDominates` | 单次最长里程 > 日均里程 × 1.8（两者都非 nil） | `:9` |
| `highAverageElectricity` | `highAverageElectricity` | 单次平均用电 > 12.0 | `:11` |
| `highEnergyPerKm` | `highEnergyPerKm` | 单公里耗电 > 35.0 | `:13` |
| `fewRangeSamples` | `fewRangeSamples` | 有效样本数 < 5 | `:15` |
| `unlinkedLocalRides` | `unlinkedLocalRides` | 存在 `associatedRideID == nil` 的本地记录 | `:17` |
| `normal` | `normal` | **仅当上面五条都没触发** | `:19` |

`NinebotTripInsight` 是 `String, Codable, CaseIterable, Identifiable`，`id` = `rawValue`（`:21`）。

**顺序是固定的**（就是上面的表格顺序），且**列表永不为空**。测试：`:215-229`（有足够样本时恰为 `[.normal]`）、`:231-242`（五条全中且不含 `.normal`）、`:244-259`（顺序逐项相等）。

#### 2.3 六条中文文案（`NinebotDashboardView.swift:3150-3167`，原文照抄）

文案已从领域层剥离，放在界面文件末尾的 `private extension NinebotTripInsight`：

| case | 文案 |
| --- | --- |
| `longRideDominates` | `"有长距离单次骑行，续航预估会更依赖最近行程样本。"` |
| `highAverageElectricity` | `"最近单次平均用电偏高，可以关注胎压、载重和急加速。"` |
| `highEnergyPerKm` | `"单公里耗电偏高，后续可以结合温度和速度继续校准。"` |
| `fewRangeSamples` | `"有效续航样本还不多，多记录几次后准确率会更稳定。"` |
| `unlinkedLocalRides` | `"有本地记录尚未关联接口行程，关联后趋势会更完整。"` |
| `normal` | `"当前趋势正常，继续积累行程后可以看到更稳定的变化。"` |

六条都以中文句号 `。`（U+3002）结尾。`insightTexts`（`:3145-3147`）就是 `insights.map(\.text)`。

`TripTrendInsightCard`（`:2967-2991`）：

```
VStack(alignment:.leading, spacing:12)   padding(16)
├─ Text("算法提示")  headline, primaryText
└─ VStack(alignment:.leading, spacing:9)
   └─ ForEach(insightTexts, id: \.self)
      Label(text, systemImage: "sparkle.magnifyingglass")
        subheadline/medium, secondaryText, fixedSize(horizontal:false, vertical:true)  ← 允许换行
frame(maxWidth:.infinity, alignment:.leading)
teslaCardBackground，圆角 24 continuous，阴影 黑5% r14 y8，无描边
```

**卡片标题是「算法提示」不是「洞察」。** `ForEach` 的 id 是**文案字符串本身**（`id: \.self`）—— 六条文案互不相同所以不会撞，但 Android 侧用 case 的 name 作 key 更稳。

#### 2.4 聚合量（`NinebotTripTrend.swift:52-123`）

规则的输入全在这里，每一个都要能单独测。

```
dailyRecords                                                          :52-59
    state.dailyMileages 排序：两条都有 date → date 升序；否则 day 升序

rides = state.rides                                                   :61-63   ← 已按 identityKey 去重
recentRides = rides.prefix(8)                                         :65-67
rideCount = rides.count                                               :69-71
activeDayCount = dailyRecords.count                                   :73-75

monthMileage                                                          :79-85
    state.monthMileage 非 nil → 用它
    否则 dailyRecords 为空 → nil
    否则 → dailyRecords 的 mileage 求和（不做非负裁剪）

averageDailyMileage                                                   :87-90
    monthMileage 为 nil 或 dailyRecords 为空 → nil
    否则 monthMileage / dailyRecords.count          ← 分母是「活跃天数」

averageSpeed                                                          :92-96
    rides.compactMap(\.speed).filter { $0 > 0 } 的算术平均；空 → nil
    ← 只认 speed 字段，不做 mileage/duration 推算

averageUsedElectricity                                                :98-102
    rides.compactMap(\.usedElectricity).filter { $0 > 0 } 的算术平均；空 → nil

peakRideMileage = rides.compactMap(\.mileage).max()                    :104-106

energyPerKm                                                           :110-123
    monthMileage > 0 且 (monthUsedElectricity ?? monthEnergy) 非 nil
        → energy / monthMileage                     ← 月度总量优先
    否则 逐条算 energy / mileage（两者都 > 0 才算），取算术平均；无样本 → nil
```

四处 `> 0` 过滤（不是 `>= 0`、不是「非 nil」）：`averageSpeed`、`averageUsedElectricity`、`energyPerKm` 的两个分子分母。测试 `:109-117`（0 值样本被丢掉，`[10, 0, 20]` 的平均是 15 而不是 10）、`:134-144`（`mileage == 0` 的那条不参与）。

**`NinebotTripTrend.averageSpeed` 与 `NinebotVehicleState.averageSpeed` 是两个不同的算法**（后者见 3.1 §2.7）。趋势页用前者，行程页顶卡用后者。

`monthMileage` 优先 `state.monthMileage`（来自 `travel.total_mileages` / `monthMileage`，`NinebotServerClient.swift:649`），只在它缺失时才拿每日里程求和。测试 `:90-102`。

`energyPerKm` 的「月度总量优先」里，`monthUsedElectricity` 压过 `monthEnergy`（测试 `:128-132`：`monthEnergy: 999` 被 `monthUsedElectricity: 400` 盖掉）。

#### 2.5 趋势页顶部两张卡

`TripTrendHeroCard`（`:2773-2827`）:

| 位置 | 取值 |
| --- | --- |
| 左上 | `snapshot.vehicle.name` headline lineLimit1 / `"趋势分析"` caption/medium |
| 右上 | `state.rangeEstimateAccuracyText` headline/monospacedDigit/bold **teslaGreen** / `"预估准确率"` caption2/medium，外套 padding(h:10, v:7) |
| 巨型数字 | `formatDistance(analysis.monthMileage)` **44pt** semibold rounded monospacedDigit lineLimit1 **minScale 0.68** |
| 巨型数字下 | `"当月行程"` caption/medium，与数字 spacing **2** |
| 三联（spacing 10） | 骑行次数 `"{rideCount}"` + 后缀 `"次"` `list.number` / 活跃天数 `"{activeDayCount}"` + `"天"` `calendar` / 单公里耗电 `energyPerKmShortText` + `"Wh/km"` `bolt.horizontal.fill` |

卡片圆角 **28**，padding 16，阴影 黑5% r14 y8。

`TrendHeroMetric`（`:2829-2861`）：图标（caption/semibold secondary）→ `HStack(firstTextBaseline, spacing:3){ 值 subheadline/monospacedDigit/bold minScale 0.68; 后缀 caption2/medium }` → 标题 caption2/medium。padding 10，`frame(maxWidth:.infinity, alignment:.leading)`，`teslaControlBackground`，圆角 16。

`energyPerKmShortText`（`:3140-3143`）= `formatNumber(energyPerKm, unit: "", maximumFractionDigits: 1)`，nil → `"--"`。**注意这里单位在后缀里单独渲染**，所以是 `"27.5"` + `"Wh/km"` 两个 Text；而 `energyPerKmText`（`:3135-3138`，nil → `"-- Wh/km"`）**在全仓没有使用点**，是抽取时留下的死代码 —— 移植时可以省掉，但如果实现了就要保持一致。

`TripTrendRangeModelCard`（`:2728-2771`）全部字段来自 Phase 2.3：`AlgorithmEstimateTitle(isUsingDefaultAlgorithm: state.isUsingDefaultAlgorithmFallback)` + `state.rangeModelInsightText` + `state.localEstimatedMileageText`，2×2 格是 准确率 `rangeEstimateAccuracyText` `target` / 有效样本 `"{observedRangeSampleCount} 次"` `scope` / 近期效率 `rangePerBatteryPercentText` `gauge.with.dots.needle.33percent` / `state.estimatedMileageSourceTitle`（恒 `"官方预估"`）`officialEstimatedMileageText` `road.lanes`。

`TripTrendRecordedCard`（`:2993-3033`，**Phase 4 之前恒不显示**）：标题「本地记录」+「记录页生成的轨迹统计」+ 右侧 `"{count} 次"`，2×2 格为 本地总里程 `formatDistance(Σ distanceKilometers)` / 本地极速 `formatSpeed(max maxSpeedKmh)` / 最大 G `formatAccelerationG(max maxAccelerationG)` / 已关联 `"{已关联条数} 次"`。

### 三 · Android 实现要点

#### 3.1 领域层（第一天就能写完，无任何 Android 依赖）

```kotlin
// core/domain/trip/TripInsight.kt
enum class TripInsight {
    LongRideDominates,
    HighAverageElectricity,
    HighEnergyPerKm,
    FewRangeSamples,
    UnlinkedLocalRides,
    Normal,
}

// core/domain/trip/TripTrend.kt
data class TripTrend(
    val state: VehicleState,
    val recordedRides: List<RecordedRide>,
) {
    companion object {
        /** 单次里程超过日均这个倍数算长途。 */
        const val LONG_RIDE_PEAK_RATIO = 1.8
        /** 单次平均用电高于此值算偏高。iOS 常量名写 Wh，实际比的是 usedElectricity（界面按 % 显示）。 */
        const val HIGH_AVERAGE_ELECTRICITY = 12.0
        /** 单公里耗电高于此值算偏高，单位 Wh/km。 */
        const val HIGH_ENERGY_PER_KM_WH = 35.0
        /** 有效续航样本少于此数算不足。注意判定方向是「小于则触发」。 */
        const val SUFFICIENT_RANGE_SAMPLE_COUNT = 5
        /** 最近骑行图表画几根柱。不参与任何判定。 */
        const val RECENT_RIDE_DISPLAY_COUNT = 8
    }

    val dailyRecords: List<DailyMileageRecord> = state.dailyMileages.sortedWith(
        Comparator { a, b ->
            val l = a.date; val r = b.date
            if (l != null && r != null) l.compareTo(r) else a.day.compareTo(b.day)
        }
    )
    // ⚠️ 这个 Comparator 不满足传递性（date 有无混杂时），见陷阱 3

    val rides: List<RideRecord> get() = state.rides            // 已去重
    val recentRides: List<RideRecord> get() = rides.take(RECENT_RIDE_DISPLAY_COUNT)
    val rideCount: Int get() = rides.size
    val activeDayCount: Int get() = dailyRecords.size

    val monthMileage: Double? get() = state.monthMileage
        ?: dailyRecords.takeIf { it.isNotEmpty() }?.sumOf { it.mileage }

    val averageDailyMileage: Double? get() {
        val total = monthMileage ?: return null
        if (dailyRecords.isEmpty()) return null
        return total / dailyRecords.size
    }

    val averageSpeed: Double? get() = rides.mapNotNull { it.speed }
        .filter { it > 0 }.takeIf { it.isNotEmpty() }?.average()

    val averageUsedElectricity: Double? get() = rides.mapNotNull { it.usedElectricity }
        .filter { it > 0 }.takeIf { it.isNotEmpty() }?.average()

    val peakRideMileage: Double? get() = rides.mapNotNull { it.mileage }.maxOrNull()

    val energyPerKm: Double? get() {
        val month = monthMileage
        val energy = state.monthUsedElectricity ?: state.monthEnergy
        if (month != null && month > 0 && energy != null) return energy / month
        return rides.mapNotNull { ride ->
            val km = ride.mileage; val wh = ride.energy
            if (km != null && km > 0 && wh != null && wh > 0) wh / km else null
        }.takeIf { it.isNotEmpty() }?.average()
    }

    val insights: List<TripInsight> get() {
        val result = mutableListOf<TripInsight>()
        val peak = peakRideMileage
        val avgDaily = averageDailyMileage
        if (peak != null && avgDaily != null && peak > avgDaily * LONG_RIDE_PEAK_RATIO) {
            result += TripInsight.LongRideDominates
        }
        averageUsedElectricity?.let { if (it > HIGH_AVERAGE_ELECTRICITY) result += TripInsight.HighAverageElectricity }
        energyPerKm?.let { if (it > HIGH_ENERGY_PER_KM_WH) result += TripInsight.HighEnergyPerKm }
        if (state.observedRangeSampleCount < SUFFICIENT_RANGE_SAMPLE_COUNT) {
            result += TripInsight.FewRangeSamples
        }
        if (recordedRides.any { it.associatedRideId == null }) {
            result += TripInsight.UnlinkedLocalRides
        }
        if (result.isEmpty()) result += TripInsight.Normal
        return result
    }
}
```

`TripTrend` 用 `data class` + `get()` 计算属性，和 iOS 的 struct 语义一致（每次读都重算）。若 profiling 显示 `rides` 上的重复遍历成为瓶颈，改成 `by lazy`；此时必须保证实例在数据变化后被重建（iOS 每次 `body` 新建，Android 用 `remember(state, recordedRides) { TripTrend(...) }`）。

#### 3.2 文案

文案进 `strings.xml`（六条都是纯展示文本，无逻辑标识作用）：

```xml
<string name="insight_long_ride_dominates">有长距离单次骑行，续航预估会更依赖最近行程样本。</string>
<string name="insight_high_average_electricity">最近单次平均用电偏高，可以关注胎压、载重和急加速。</string>
<string name="insight_high_energy_per_km">单公里耗电偏高，后续可以结合温度和速度继续校准。</string>
<string name="insight_few_range_samples">有效续航样本还不多，多记录几次后准确率会更稳定。</string>
<string name="insight_unlinked_local_rides">有本地记录尚未关联接口行程，关联后趋势会更完整。</string>
<string name="insight_normal">当前趋势正常，继续积累行程后可以看到更稳定的变化。</string>
```

映射函数放界面层（对齐 iOS 把文案留在 view 文件的做法）：

```kotlin
// feature/trips/TripInsightText.kt
@StringRes
fun TripInsight.textRes(): Int = when (this) {
    TripInsight.LongRideDominates -> R.string.insight_long_ride_dominates
    TripInsight.HighAverageElectricity -> R.string.insight_high_average_electricity
    TripInsight.HighEnergyPerKm -> R.string.insight_high_energy_per_km
    TripInsight.FewRangeSamples -> R.string.insight_few_range_samples
    TripInsight.UnlinkedLocalRides -> R.string.insight_unlinked_local_rides
    TripInsight.Normal -> R.string.insight_normal
}
```

**领域层不许 import `R`**，`TripInsight` 里不能带 `@StringRes` 字段，否则 JVM 单测跑不起来。

#### 3.3 洞察卡

```kotlin
Column(
    Modifier.fillMaxWidth().ninePlusCard(cornerRadius = 24.dp),   // padding 16 + 卡底 + 阴影
    verticalArrangement = Arrangement.spacedBy(12.dp),
) {
    Text(stringResource(R.string.trend_insight_title), style = headline)   // "算法提示"
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        insights.forEach { insight ->
            key(insight.name) {                                   // ← 用 enum name 而非文案字符串
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(SparkleMagnifyingGlass, null, tint = secondary)
                    Text(
                        stringResource(insight.textRes()),
                        style = subheadline.copy(fontWeight = FontWeight.Medium),
                        color = secondary,
                        // fixedSize(vertical) 的等价：不设 maxLines，允许换行
                    )
                }
            }
        }
    }
}
```

洞察文案是**唯一允许多行**的地方（`.fixedSize(horizontal: false, vertical: true)`，`:2981`）。别顺手加 `maxLines = 1`，最长那条 25 个汉字在 360dp 屏上一定会换行。

### 四 · 陷阱

1. **五个阈值全是「严格大于」，只有样本数那条是「小于」。** 边界值不触发：`peak == avgDaily × 1.8` 不算长途、`avg == 12.0` 不算偏高、`energyPerKm == 35.0` 不算偏高；而 `sampleCount == 5` **不**触发不足（`< 5` 才触发）。测试 `TripTrendTests.swift:182-199` 把 18 / 18.1、12 / 12.1、350 / 351（÷10 km = 35 / 35.1）都钉了。改成 `>=` 会让几乎所有月份都报告「用电偏高」。

2. **`.normal` 是「兜底」不是「一票」。** 它只在其他五条一条都没中时出现，永远不与别的 case 共存。测试 `:231-242`（五条全中时 `insights.size == 5` 且不含 `.normal`）。写成 `if (result.isEmpty()) result += Normal` 而不是「先算 normal 再看要不要删」。

3. **`dailyRecords` 的比较器不满足传递性。** iOS 的 `sorted { if let l = $0.date, let r = $1.date { l < r }; return $0.day < $1.day }` 在「有的有 date、有的没有」时会给出不一致的比较结果。`Array.sorted` 对此不报错，但 Kotlin 的 `sortedWith` 底下是 `java.util.Arrays.sort` (TimSort)，**遇到不一致的 Comparator 会抛 `IllegalArgumentException: Comparison method violates its general contract!`**。实际数据里 `date` 只在 `month` 字段缺失时才为 null（`NinebotServerClient.swift:725`），要么全有要么全无，所以线上撞不到；但混合输入的单测会直接崩。**用 `sortedWith(compareBy(nullsLast()) { it.date }.thenBy { it.day })` 是「修正」而非直译**，会改变混合输入下的顺序。稳妥做法：先按 `date == null` 分区，各自排序再拼接，并在测试里明确记下「混合输入的顺序是未定义的」。

4. **`fewRangeSamples` 在社区服务端上恒触发。** `observedRangeSampleCount` 无预测时返回 0（`NinebotModels.swift:1270-1276`）。所以「算法提示」卡永远至少有一条，且永远包含「有效续航样本还不多」。别把它当 bug 优化掉 —— 换成带预测的服务端后它就会自己消失。

5. **`unlinkedLocalRides` 在 Phase 4 之前恒不触发**（`recordedRides` 恒空）。规则和文案要在 Phase 3 实现并单测（喂假的 `RecordedRide`），但界面上验不到。测试 `:207-213`。

6. **`highAverageElectricityWh` 的单位名与实际显示不一致。** 常量名和注释说 Wh，比的字段界面上按 `%` 渲染。照抄 12.0，别做 ÷1000 之类的「单位修正」。见待定 T9。

7. **两个 `averageSpeed` 不能合并。** `TripTrend.averageSpeed`（`NinebotTripTrend.swift:92-96`）只认 `speed` 字段；`VehicleState.averageSpeed`（`NinebotModels.swift:1426-1430`）会用 `mileage / (duration/60)` 兜底。同一屏上「行程概要 · 平均速度」和「趋势 · 平均速度」是两个数。

8. **`averageDailyMileage` 除的是活跃天数，`dailyAverageMileageText` 除的是当月第几天**（`NinebotTripTrend.swift:87-90` vs `NinebotModels.swift:1387-1392`）。前者喂长途规则，后者只显示在行程页顶卡。两个都要，不能互相替代 —— 用错会改变 `longRideDominates` 的触发频率。

9. **`ForEach(insightTexts, id: \.self)` 用文案当 key**（`:2977`）。Android 用 `insight.name`。如果将来有两条文案相同，iOS 会丢一条，Android 不会 —— 这是主动修正。

10. **`energyPerKmText`（`:3135-3138`）是死代码**，全仓无使用点。趋势页三联用的是 `energyPerKmShortText`（无单位，单位在后缀 Text 里）。别把两个搞混，否则会出现 `"27.5 Wh/km"` + `"Wh/km"` 的双单位。

11. **洞察文案必须能换行。** `.fixedSize(horizontal: false, vertical: true)` 的意思是「宽度随容器、高度按内容撑开」。Compose 里就是**不要**设 `maxLines`，也不要 `softWrap = false`。

### 五 · 验收标准

- [ ] 移 `TripTrendTests.swift` 全部 19 个用例到 JVM 单测，全绿
- [ ] 五个阈值常量在 Kotlin 里是命名常量（不是内联字面量），值分别为 `1.8` / `12.0` / `35.0` / `5` / `8`
- [ ] 边界：`peak == avgDaily × 1.8` 不触发、`× 1.8 + ε` 触发（移 `:182-189`，18 / 18.1 + 日均 10）
- [ ] 边界：`avgUsedElectricity == 12` 不触发、`12.1` 触发（移 `:191-194`）
- [ ] 边界：`energyPerKm == 35` 不触发、`35.1` 触发（移 `:196-199`，`monthMileage = 10` + `monthUsedElectricity = 350 / 351`）
- [ ] 边界：`observedRangeSampleCount` 为 `4` 触发、`5` 不触发
- [ ] `insights` 永不为空；无预测 + 无数据时至少含 `FewRangeSamples`
- [ ] 五条全中时 `insights.size == 5` 且不含 `Normal`；顺序为 长途 → 用电偏高 → 单公里耗电偏高 → 样本不足 → 未关联本地记录（移 `:244-259`）
- [ ] 足够样本 + 正常数据时 `insights == [Normal]`（移 `:215-229`）
- [ ] 六条中文文案与表格**逐字符相同**，含结尾的中文句号
- [ ] `monthMileage`：优先 `state.monthMileage`（99 压过日均和 15）；缺失时取每日求和（4+6+10 = 20）；两者都无 → null（移 `:90-102`）
- [ ] `averageDailyMileage` 分母是活跃天数：`[10,20,30]` → 20（移 `:104-107`）
- [ ] `> 0` 过滤：`usedElectricity [10, 0, 20]` → 15、`speed [20, 0, 40]` → 30（移 `:109-117`）
- [ ] `energyPerKm` 月度优先：`monthUsedElectricity 400` 压过 `monthEnergy 999`，20 km → 20（移 `:128-132`）
- [ ] `energyPerKm` 逐条兜底：`(10km,200Wh)` + `(10km,300Wh)` + `(0km,100Wh)` → 25（移 `:134-144`）
- [ ] `recentRides` 上限 8（12 条输入 → `rideCount == 12`、`recentRides.size == 8`，移 `:146-151`）
- [ ] `dailyRecords` 倒序输入 → `day` 升序（移 `:153-159`）；**混合 date 有/无的输入不抛 `IllegalArgumentException`**
- [ ] `unlinkedLocalRides`：`associatedRideId = "travel-1"` 不触发、`null` 触发（移 `:207-213`）
- [ ] 洞察卡标题是「算法提示」；每行前缀 `sparkle.magnifyingglass`；行间距 9dp
- [ ] 最长那条文案在 360dp + 最大字号下**换行显示完整**，不截断不省略号
- [ ] 五条全中时卡片显示 5 行，顺序与 `insights` 一致
- [ ] 趋势页 `TripTrendHeroCard`：44sp 巨型月里程、三联「骑行次数/活跃天数/单公里耗电」的值与后缀分离渲染（`"27.5"` + `"Wh/km"`，不是 `"27.5 Wh/km"`）
- [ ] `energyPerKm` 为 null 时三联第三格显示 `"--"` + `"Wh/km"`
- [ ] `recordedRides` 为空时「本地记录」卡**不出现**

---

## 待定

### T1 · 去重键会把两条真实行程合并成一条 —— 要不要修

**现状是什么**：`stableIdentityKey` 的第 4 级（`NinebotModels.swift:784-791`）由 起始时间 / 结束时间 / 里程 / 耗电 四项组成，**不含 `id`、不含 `energy`**。两条起止时间和里程都一样、只有能耗不同的记录会被合并，列表少一条、`rideCount` 少一次、趋势和洞察的分母跟着变。规格现在的写法是**原样照抄**，Room 的复合主键与之逐字符一致。

**iOS 怎么做的**：合并。`TripTrendTests.testRidesWithTheSameTimestampAndMileageCollapse`（`Tests/NineBotCoreTests/TripTrendTests.swift:165-177`）用测试把这个行为钉住了，并在注释里写明「Android has to reproduce this or ride counts will diverge」。

**分歧点**：第 1/2/3 级都用了 raw 里的显式标识，所以线上数据几乎不会走到第 4 级 —— 它主要出现在缓存迁移和手工构造的路径上。把 `id` 加进第 4 级就能消掉这个合并，风险是：`id` 在两次拉取之间可能变（`rideRecord` 的兜底会用 `startedAt` 秒数甚至数组下标当 id，`NinebotServerClient.swift:695-697`），加进键之后同一条行程可能出现两份，比合并更糟。所以「修」不是无脑加字段，要先确定 `id` 在这条路径上是否稳定。

**建议决定时机**：3.1 实现完、拿真实服务端灌满一个月归档之后。届时统计一下有多少条记录落到第 4/5 级 —— 如果是 0，这条就永远不用管；不是 0 再决定。**在那之前一律照抄，别提前"优化"。**

---

### T2 · 列表分页用「显示更多」按钮还是无限滚动

**现状是什么**：规格里 3.1 §3.4 写的是 Paging 3 + `initialLoadSize = 30`，滚到底自动加载下一页。

**iOS 怎么做的**：`RideListSection` 用 `@State visibleLimit = 30`，超出时在列表底部显示一个「显示更多」按钮，上面写着还剩多少条（`NinebotDashboardView.swift:3966-3988`），点一次 +30；切换月份时重置回 30（`:3992-3994`）。**不是无限滚动**。

**分歧点**：Paging 3 是 Android 的标准做法，能省内存、能配合 Room 的 `PagingSource` 增量更新，但会让「还剩 N 条」这个信息消失，而且用户失去「我看到底了」的明确边界。保留按钮则要放弃 Paging，改成 `MutableStateFlow(limit)` + `LIMIT :limit` 查询 —— 一个月最多 500 条，一次全查也不会有性能问题，所以技术上没必要上 Paging。

**建议决定时机**：3.1 开工前。这决定 DAO 返回 `PagingSource` 还是 `Flow<List<...>>`，中途改要动 DAO、ViewModel、Composable 三层。

---

### T3 · 500 条上限是全车共享的，会静默吞掉刚拉到的旧月份

**现状是什么**：规格照抄 iOS —— 每辆车的归档上限 500 条，按 `sort_at` 降序保留**最新** 500 条，修剪与写入在同一事务里。

**iOS 怎么做的**：`saveInterfaceRideRecords`（`NinebotSharedStore.swift:471-475`）`prefix(500)`。后果是：近几个月已攒满 500 条时，用户点「获取 2024.03」，状态条显示「已获取 2024年03月 37 条行程」（`page.total` 是服务端给的，不是入库数），但这 37 条在同一事务里被修剪掉，列表仍显示「2024.03 暂无行程」。**成功提示 + 空列表**，用户无从判断哪里出了问题。

**分歧点**：三种走法 —— (a) 原样照抄，两端一致地保留这个怪行为；(b) 提高上限（Room 存 500 条行程只有几百 KB，放到 5000 条毫无压力，但两端的「能翻多久」不一样了）；(c) 保留 500 但改成 per-month 上限（老月份不再被新月份挤掉，代价是总量上限变成「月数 × 500」，不可控）。另外无论选哪个，「入库 0 条却提示成功 37 条」这个提示都该修 —— 至少把状态条改成入库后的实际条数。

**建议决定时机**：3.1 的归档层写完、能实测出「攒满 500 条大概要几个月」之后。先量出真实密度（一天几趟车）再定上限，别拍数字。

---

### T4 · 同步一个月要不要仍触发完整 `fetchDashboard`

**现状是什么**：规格照抄 iOS 的顺序 —— `POST travel-sync` 之后紧接一次完整的 `dashboardRepository.refresh(selectedSn)`。

**iOS 怎么做的**：`NinebotViewModel.syncTravelMonth:287` 调 `fetchDashboard(selectedSN:)`。这一次调用是 `GET /vehicles`（1）+ 每辆车 `GET dashboard`（N）+ `fetchMonthlyTravels` 对「绑定月到当月」逐月各一次 `GET travel`（M-1，当月复用）。一辆去年绑定的车、两辆车的账号，一次「获取上一月」能打出 20 个串行请求。而那 M-1 个月度 travel 请求**只用来算总里程**（`NinebotServerClient.swift:731-752`），一条行程都不入库。

**分歧点**：照抄能保证两端的总里程口径完全一致，代价是慢网下「获取上一月」要转十几秒，且大部分请求是纯浪费。改法有两种：(a) 同步月份后只刷当前那辆车的 dashboard，不跑 `fetchMonthlyTravels`（总里程沿用上次的值，可能偏旧）；(b) 把 `fetchMonthlyTravels` 拆成独立的低频任务（比如每天一次 WorkManager），与刷新解耦。两种都会让 `totalMileage` 的更新时机和 iOS 不同。

**建议决定时机**：3.1 联调时，拿真实服务端量一次「获取上一月」的端到端耗时。如果只有一辆车、绑定不久，这条无所谓。

---

### T5 · 行程行的结束时间用设备时区（iOS 侧的时区不一致）

**现状是什么**：规格记录了现状，未改：同一行的开始时间走 `Asia/Shanghai`，结束时间走设备时区。

**iOS 怎么做的**：`RideRecordRow:4021` 的开始时间用 `formatRideDate` → `formatDate`（`NinebotFormatting.swift:38-44`，恒 `zh_CN` + `Asia/Shanghai` + `"yyyy-MM-dd HH:mm"`）；`:4027` 的结束时间用 `$0.formatted(.dateTime.hour().minute())`，走**设备 locale 与设备时区**。整个仓库其他所有时间显示都固定在 `Asia/Shanghai`（`NinebotFormatting.swift:8-9` 的注释明确说这是刻意的），只有这一处例外。

**分歧点**：这看起来是漏改而不是设计 —— 但改掉之后，把手机时区设成非中国的用户会看到结束时间「变了」。同时还有格式问题：`.formatted(.dateTime.hour().minute())` 在 `en_US` 下输出 `"2:32 PM"`，在 `zh_CN` 下输出 `"14:32"`，Android 若照抄这个「跟随设备」的行为就得同时跟随 12/24 小时制，实现成本反而更高。

**建议决定时机**：3.1 实现列表行的时候。顺手统一到 `Asia/Shanghai` + `HH:mm` 的成本几乎为零，但要确认 iOS 侧是否一起改 —— 只改 Android 会造成两端同一行显示不同时间。

---

### T6 · 行程详情底部两张原始字段卡跟着 D4 走

**现状是什么**：规格里 3.2 完整写了 `RawJSONSection`（「行程详情完整返回值」）和 `RawFieldSection`（「列表原始字段」）两张折叠卡，含 122 条 `friendlyRawFieldName` 映射和 1.4 秒的「已复制」反馈。

**iOS 怎么做的**：有，在行程详情页底部两张，默认折叠。

**分歧点**：这两张卡是 [pending-decisions.md](./pending-decisions.md) **D4**（原始字段调试面板要不要做）的一部分。D4 若砍掉，3.2 就少两张卡、省掉 122 条映射表，工时从 2 天降到约 1.5 天；但行程详情是这个面板最有价值的地方 —— 社区服务端的 travel 返回和官方的差异最大，「为什么这条行程没有速度」几乎只能靠它排查。另外 D4 挂在 Phase 2.7 上，而 3.2 会先用到它，所以决定时机要往前挪。

**建议决定时机**：**提前到 3.2 开工前**，不要等 Phase 2.7。若 D4 倾向砍掉，也建议在行程详情这一处保留（只做 `RawJSONSection`，不做 122 条中文映射，键名原样显示），这样成本降到几小时而排查能力还在。

---

### T7 · 行程详情要不要落盘

**现状是什么**：规格里 3.2 §3.1 写的是 Repository 单例持有内存 cache，对齐 iOS。

**iOS 怎么做的**：`NinebotViewModel.rideDetails` 是纯内存 `@Published` 字典（`:151`），**从不落盘**（全仓无对应的 store 方法）。冷启动后每条详情都要重新请求；诊断中心里的 `rideDetailCount`（`:511`）统计的就是这个内存字典的大小。

**分歧点**：落 Room 的好处是离线可看、翻回去不重复请求、Phase 4.1 的接口轨迹回放不用每次重新拉（一条轨迹的 JSON 可能几十 KB 到几百 KB）。代价是要定失效策略（`fetchedAt` 多久算过期？行程数据其实是不变的，理论上永久有效）和存储上限（轨迹 JSON 会长，500 条详情可能几十 MB），而 iOS 没有这些概念，两端的「打开详情要不要联网」表现会不同。

**建议决定时机**：**Phase 4.1 之前**，和接口轨迹回放一起定 —— 那时才知道一条轨迹的实际体积。Phase 3 阶段先按内存 cache 实现，接口层留好「详情从哪来」的抽象（`RideDetailRepository.detail()` 返回 `Flow`），换成 Room 不动界面。

---

### T8 · 趋势页要不要支持看历史月份

**现状是什么**：规格照抄 iOS —— 趋势页没有月份选择器，每日里程柱状图恒显示 dashboard 当次拉到的那个月（通常是当月）。

**iOS 怎么做的**：`TripTrendView`（`:2698-2726`）的入参只有 `snapshot` 和 `recordedRides`，`TripTrendDailyCard` 吃 `analysis.dailyRecords`，而那来自 `state.dailyMileages` ← `travel.detail` ← 当月的 travel 载荷。行程页顶部的月份筛选**不传给趋势页**。

**分歧点**：用户已经能在行程页翻到 2024.03 的行程列表，翻到趋势页却只能看当月的柱状图，观感上是断裂的。但要支持历史月份就得**把每日里程也存下来** —— 现在归档只存行程记录（`interface_ride`），`dailyMileageRecords` 是 `travel.detail` 的派生物，从不落盘。补这个要加一张 `daily_mileage(vehicle_sn, month, day)` 表，并且 `travel-sync` 的返回里未必带 `detail`（`GET /travel` 才带），可能需要在同步一个月时额外打一次 `GET /travel?month=`。工时约 +1 天。

**建议决定时机**：3.3 做完、能看到实际效果之后。也可能结论是「趋势页本来就是看当月，不需要翻历史」。

---

### T9 · `highAverageElectricityWh` 的单位矛盾

**现状是什么**：规格照抄 12.0 这个数值，并在 Kotlin 常量的注释里写明「iOS 常量名写 Wh，实际比的是 `usedElectricity`（界面按 % 显示）」。数值行为不动。

**iOS 怎么做的**：`NinebotTripTrend.swift:41-42` 的注释是 `Average electricity per ride above this (Wh) counts as high.`，常量名 `highAverageElectricityWh`；但它比的是 `averageUsedElectricity`，即 `NinebotRideRecord.usedElectricity` 的平均，而这个字段在界面上一律用 `formatPercent` 渲染成百分比（列表行「用电」`:4068`、详情「用电」`:4115`、趋势胶囊「平均用电」`:2955`）。所以判定语义实际是「单次平均掉电超过 12%」，不是「12 Wh」。

**分歧点**：对用户不可见 —— 洞察文案「最近单次平均用电偏高，可以关注胎压、载重和急加速。」不带单位，所以行为上没有 bug。但常量名和注释是错的，会误导后续维护者做单位换算（比如"修"成 12000 Wh 或除以 1000）。三种走法：(a) Android 保留原名和原注释，忠实照抄错误；(b) 改名成 `HIGH_AVERAGE_USED_PERCENT`、注释写清是百分比，数值仍 12.0，两端常量名不一致；(c) 两端一起改名。

**建议决定时机**：3.4 开工时顺手定，几分钟的事。倾向 (c)：iOS 侧改个常量名和注释是零风险的重命名，改完两端都不会再有人被误导。

---

### T10 · 柱状图区分不了「里程为 0」和「接口没返回里程」

**现状是什么**：规格照抄 iOS —— `TripRecentRideBars` 用 `ride.mileage ?? 0`，两种情况都画成 6dp 短柱、柱顶写 `"0"`。

**iOS 怎么做的**：`NinebotDashboardView.swift:3111` 的 `value: ride.mileage ?? 0`。同一条行程在列表行里显示的是 `formatDistance(nil)` = `"-- km"`（能区分），到了柱状图就变成 `"0"`（不能区分）。

**分歧点**：改法很轻（`TrendBarValue.value` 改成 `Double?`，null 画成灰色轨道 + 柱顶 `"--"`），能消掉一处信息丢失。但这会引入一个 iOS 没有的视觉状态，两端截图对不上；而且 `maxValue` 的分母、`averageSpeed` 之类的聚合都不受影响，所以纯粹是显示层面的改善，收益有限。

**建议决定时机**：3.3 做完之后，看真实数据里到底有多少条行程缺 `mileage`。如果是 0（服务端总是返回 `mileages`），这条直接作废。
