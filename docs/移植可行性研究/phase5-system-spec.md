# Phase 5 · 系统集成 详细规格（5.1 / 5.2 / 5.4 / 5.6）

本文覆盖 Phase 5 里的四项：诊断中心（5.1）、防截屏（5.2）、后台定时刷新（5.4）、应用快捷方式（5.6）。
**5.3 桌面 Widget 与 5.5 充电实时活动在 [phase5-widget-island-spec.md](./phase5-widget-island-spec.md)**，本文只在 5.4 里定义与它们的接口边界。

目录约定延续 Phase 0 / Phase 1：

```
android/
  feature/diagnostics/     5.1  诊断中心页面 + DiagnosticsSnapshot 组装
  core/secure/             5.2  SecureSurfaceHost（AndroidView + SurfaceView + SurfaceControlViewHost）
  core/work/               5.4  DashboardRefreshWorker（1.3 已建这个目录，复用）
  app/src/main/res/xml/    5.6  shortcuts.xml
  app/.../shortcut/        5.6  ShortcutPublisher、ShortcutTrampolineActivity
```

---

## 本阶段依赖什么、能并行做什么

### 依赖

| 项 | 硬依赖 | 说明 |
| --- | --- | --- |
| 5.1 | 0.3 存储、0.4 ViewModel/DI；**1.2 / 1.3 / 5.4 的事件写入点** | 诊断中心本身只是读端。没有写入点它就是三张空卡片。可以先做界面 + 假数据，写入点由 1.2 / 1.3 / 5.4 各自落地 |
| 5.2 | **1.1**（主卡片地址行）、**2.1**（车辆位置卡与地图预览） | iOS 全仓只有 3 个保护点，两个在 1.1 的 hero 里，一个在 2.1 的位置卡里。2.1 没做完就无法验收第 3 个点 |
| 5.4 | 0.1 网络、0.2 模型、0.3 存储、**0.6**（国产 ROM 保活引导） | 刷新链路本身就是 `fetchDashboard` + 落盘，Phase 0 完成即可开工 |
| 5.6 | 1.2 的 `VehicleCommandRepository`；主界面的 tab 路由 | 控车类快捷方式复用 1.2 的仓库，不要另写网络调用 |

### 能并行

- **5.1 / 5.2 / 5.6 互不依赖**，三个人可以同时开工。
- **5.2 必须最早拿到真机**。`SurfaceView` 的位置同步、圆角、z-order 在不同 GPU 与 ROM 上表现不同，模拟器上看不出问题。3.5 天工时里应该有 1 天是真机调试，且至少两个品牌。
- **5.4 与 5.3 / 5.5 的耦合只在「刷新完成之后通知谁」这一处**。先按下文 §5.4 三 · 3.4 的接口把回调声明出来，5.3 / 5.5 各自实现，两边不必等对方。
- **5.1 与 5.4 有一处双向关系**：5.4 要写刷新事件给 5.1 看，5.1 要读 WorkManager 的调度状态给用户看。把 `RefreshEventStore`（5.1 定义）和 `WorkStatusReader`（5.1 定义，实现只调 WorkManager API）两个接口先定下来即可。

### 一处需要提前说清的口径

**「诊断中心」这个页面在 iOS 上不只是诊断。** 防截屏开关（5.2）就挂在这个页面里（`NinebotSettingsView.swift:974-984`），不在设置根页。5.2 的开关落在哪里应当与 iOS 一致，5.1 与 5.2 的负责人要就这一格协调好，不要各自画一个开关。

---

## 5.1 诊断中心（3 天）

### 一 · iOS 现状

入口在设置页：`NinebotSettingsView.swift:126-138`，`NavigationLink` → `NinebotDiagnosticsView`，行文案 `title: "诊断中心"` / `subtitle: "刷新、缓存、Widget 和原始字段"` / `systemImage: "stethoscope"`，外层 `padding(16)` + `ninePlusCard(cornerRadius: 24)`。

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| `NinebotDiagnosticsView` | `NinebotSettingsView.swift:961-1042` | 页面容器 |
| `DiagnosticsHeroCard` | `:1044-1110` | 连接态 + 车辆数 + 三个计数 pill |
| `DiagnosticsEventCard` | `:1112-1156` | 单条刷新事件（用两次） |
| `DiagnosticsCacheCard` | `:1158-1188` | 四格缓存计数 |
| `DiagnosticsRawCopyCard` | `:1190-1247` | 「复制全部原始字段」 |
| `DiagnosticMetricPill` | `:1249-1274` | 通用小格 |
| `NinebotDiagnosticsSnapshot` | `NinebotViewModel.swift:109-126` | 16 字段数据载体 |
| `diagnosticsSnapshot()` | `NinebotViewModel.swift:489-516` | 组装函数 |
| 四个格式化函数 | `NinebotSettingsView.swift:1425-1467` | 日期 / 时间 / 耗时 / 字节 / JSON |
| `NinebotRefreshEvent` | `NinebotModels.swift:58-69` | 事件模型 |

**页面结构**（`:969-1017`，`ScrollView` → `VStack(alignment:.leading, spacing:16)`，`padding(16)`，背景 `teslaPageBackground`，`navigationTitle("诊断中心")`，`navigationBarTitleDisplayMode(.inline)`）：

```
1. DiagnosticsHeroCard
2. Toggle「截图录屏保护」            ← 5.2 的开关，就在这里
3. DiagnosticsEventCard("App / 快捷指令", lastAppRefreshEvent)
4. DiagnosticsEventCard("桌面小组件",     lastWidgetRefreshEvent)
5. DiagnosticsCacheCard
6. Button「清除当前提示」（role: .destructive）
7. DiagnosticsRawCopyCard
```

顶部 toast 覆盖层（`:1021-1033`）：`overlay(alignment:.top)`，`footnote/semibold`，`padding(h:14, v:9)`，`.regularMaterial` 背景，`Capsule` 裁切，`padding(.top, 8)`，`transition(.move(edge:.top).combined(with:.opacity))`，`animation(.easeInOut(duration: 0.18))`。

### 二 · 要移植的逻辑

#### 2.1 记录了哪些事件

**事件模型**（`NinebotModels.swift:58-69`），6 个字段 + 1 个派生：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `source` | `String` | 自由字符串，**不是枚举**。全仓实际取值：`"App"` / `"Shortcut"` / `"Background"` / `"Widget"` / `"Tile"`（`"Tile"` 是 Android 侧 1.3 新增的） |
| `operation` | `String` | 同样是自由字符串，见下表 |
| `startedAt` | `Date` | |
| `endedAt` | `Date` | |
| `success` | `Bool` | |
| `message` | `String?` | 成功时通常是车名，失败时是 `error.localizedDescription` |
| `durationSeconds` | `Double`（派生） | `max(endedAt.timeIntervalSince(startedAt), 0)`，**下界 clamp 到 0** |

**保留条数上限 = 每个 key 1 条，全局共 2 条。** 不是列表。`saveRefreshEvent`（`NinebotSharedStore.swift:417-420`）直接 `defaults.set(data, forKey:)` 整体覆盖；`loadRefreshEvent`（`:412-415`）解码单个对象。两个 key：

- `ninebot.last.app.refresh.event`（`NinebotSharedStore.swift:11`）
- `ninebot.last.widget.refresh.event`（`:12`）

**全仓 10 个写入点**（`saveLastAppRefreshEvent` / `saveLastWidgetRefreshEvent` 的全部调用处）：

| 写入点 | 落哪个 key | `source` | `operation` | `message` |
| --- | --- | --- | --- | --- |
| `NinebotViewModel.swift:662-669`（成功） | app | `"App"` | `kind.message` | `statusMessage`（可能是 nil） |
| `NinebotViewModel.swift:675-682`（失败） | app | `"App"` | `kind.message` | `error.localizedDescription` |
| `NinebotAppIntents.swift:405-412` | app | `"Shortcut"` | 调用方传入 | 车名或错误 |
| `NinebotBackgroundTaskManager.swift:54-61`（未配置） | app | 传入的 source（实际 `"Background"`） | `"后台刷新"` | `"未配置数据源"` |
| `NinebotBackgroundTaskManager.swift:70-77`（成功） | app | 同上 | `"后台刷新"` | `primaryVehicle?.vehicle.name` |
| `NinebotBackgroundTaskManager.swift:82-89`（失败） | app | 同上 | `"后台刷新"` | `error.localizedDescription` |
| `NinebotWidgetProvider.swift:60-67`（未配置） | widget | `"Widget"` | `"刷新小组件"` | `"未配置服务器"` |
| `NinebotWidgetProvider.swift:80-87`（成功） | widget | `"Widget"` | `"刷新小组件"` | `primaryVehicle?.vehicle.name` |
| `NinebotWidgetProvider.swift:97-104`（失败） | widget | `"Widget"` | `"刷新小组件"` | `error.localizedDescription` |
| `NinebotWidgetControlIntents.swift:161-176` | widget | `"Widget"` | 调用方传入 `action.title` | 车名 / 错误 |

`operation` 实际会出现的字符串（**三套并存，混在同一个 `operation` 列里**）：

| 来源 | 取值 |
| --- | --- |
| App 内操作（`NinebotLoadingOperation.message`，`NinebotLoadingOperation.swift:22-43`） | `"正在测试连接"` / `"正在刷新车况"` / `"正在更新电池类型"` / `"正在获取 {月份} 行程"` / `"正在解析车辆位置"` / `"正在开启充电通知"` / `"正在上报设备 Token"` / `"正在密码登录"` / **车控四条走 `action.loadingTitle`**：`"正在寻车鸣笛"` / `"正在打开座桶"` / `"正在开锁"` / `"正在关锁"` |
| Shortcut（`NinebotAppIntents.swift:270/288/315/347`） | `"刷新车况"` / `"查询电量"` / `"查询位置"` / **`action.title`**：`"寻车铃"` / `"开座桶"` / `"上电"` / `"熄火"` |
| 后台 / Widget | `"后台刷新"` / `"刷新小组件"` / Widget 私有枚举的 `title`：`"寻车"` / `"开座桶"` / `"开锁"` / `"关锁"`（`NinebotWidgetControlIntents.swift:5-19`） |

> Phase 1 的 1.2 里写「`title` 写进诊断中心的 `operation`」，那句只对 **Shortcut** 路径成立（`NinebotAppIntents.swift:347`）。App 内路径写的是 `loadingTitle`（经 `NinebotLoadingOperation.swift:41`），Widget 路径写的是 Widget 私有枚举的 `title`。同一个「上电」动作在三个来源下记出三个不同的 `operation` 字符串（`正在开锁` / `上电` / `开锁`）。Android 照抄这套，不要统一。

**事件卡渲染**（`:1112-1156`）：

| 元素 | 规则 |
| --- | --- |
| 标题 | 传入的 `title`：`"App / 快捷指令"` 或 `"桌面小组件"` |
| 右上角状态 | `event?.success == true ? "成功" : "待检查"`，绿 / 橙。**`event == nil` 与 `success == false` 都显示「待检查」，两态不可分** |
| 三个 pill | 「来源」`event.source` / 「耗时」`formatDiagnosticsDuration(durationSeconds)` / 「时间」`formatDiagnosticsTime(endedAt)` |
| 详情行 | 仅 `message` 非空时出现，文案是 `"{operation} · {message}"`，用 `·`（U+00B7）连接，两侧各一个空格 |
| 空态 | `"还没有记录到刷新事件"`，`subheadline`，secondary |

卡片样式：`padding(16)`，`teslaCardBackground`，圆角 **18**，hairline stroke 1pt，**无阴影**。注意这与设置页那些 `ninePlusCard(cornerRadius: 24)` 不同 —— 诊断中心里的四张卡片是手写的圆角 18 无阴影，只有防截屏开关和「清除当前提示」两格用 `ninePlusCard(24)`。

#### 2.2 缓存占用是怎么算出来的

`DiagnosticsCacheCard`（`:1158-1188`）是一个 `LazyVGrid` 两列（`GridItem(.flexible(), spacing: 10)` ×2，行 `spacing: 10`），四格：

| 格 | 值 | 单位 | 出处 |
| --- | --- | --- | --- |
| 接口行程 | `interfaceRideCount` | 条 | Σ 全部车辆 `store.interfaceRideCount(sn:)`（`NinebotViewModel.swift:491-493`；`NinebotSharedStore.swift:365-367` → `loadInterfaceRideRecords(sn:).count`） |
| 历史快照 | `historyPointCount` | 条 | Σ 全部车辆 `store.historyCount(sn:)`（`NinebotViewModel.swift:494-496`；`NinebotSharedStore.swift:361-363` → `loadHistory(sn:).count`） |
| 本地轨迹 | `recordedRideCount` | 条 | `store.recordedRideCount()`（`NinebotSharedStore.swift:378-380` → `loadRecordedRides().count`） |
| 车况缓存 | `formatDiagnosticsBytes(dashboardCacheBytes)` | 字节 | `store.storedDashboardByteCount()`（`NinebotSharedStore.swift:382-384`） |

**只有「车况缓存」是字节，其余三格是条数。**

`storedDashboardByteCount()` 的实现是一行：

```swift
defaults.data(forKey: Key.dashboard)?.count ?? 0
```

也就是**只算 `ninebot.dashboard.snapshot` 这一个 key 的 `Data` 字节数**（`JSONEncoder` 编出来的整份 `NinebotDashboard`）。以下都**不算进去**：

- `ninebot.vehicle.history.{sn}`（每车最多 240 条，`NinebotSharedStore.swift:429-431`）
- `ninebot.vehicle.interface.rides.{sn}`（每车最多 500 条，`:472`）
- `ninebot.vehicle.image.{sn}`（车辆图，单张上限 2 500 000 字节，`:396`；优先写磁盘文件，写不进去才落 UserDefaults，`:395-409`）
- `RideTracks/` 下的轨迹点文件
- 配置、登录态、地址缓存、Live Activity token 记录（最多 12 条，`:561`）

**`recordedTrackBytes` 是死字段。** `NinebotDiagnosticsSnapshot.recordedTrackBytes`（`NinebotViewModel.swift:125`）由 `store.recordedTrackByteCount()`（`NinebotSharedStore.swift:288-299`，遍历 `RideTracks/` 目录逐文件取 `.size` 求和）计算，每次打开诊断中心都会跑一次目录遍历，但**界面上没有任何地方渲染它**。Android 侧要么补上一格（本地轨迹字节数），要么不要算 —— 别照抄「算了不显示」。

**字节格式化**（`formatDiagnosticsBytes`，`:1448-1457`）：

```
bytes <= 0            → "0 B"
bytes >= 1024*1024    → String(format: "%.1f MB", Double(bytes)/1024/1024)
bytes >= 1024         → String(format: "%.1f KB", Double(bytes)/1024)
else                  → "{bytes} B"
```

**1024 进制、单位写 KB/MB**（不是 KiB/MiB），保留 1 位小数，`%.1f` 是 HALF_UP 舍入。

#### 2.3 Hero 卡的每一格

`DiagnosticsHeroCard`（`:1044-1110`）：

| 元素 | 规则 | 出处 |
| --- | --- | --- |
| 44×44 圆形徽标 | `hasConfiguration` → 绿色 `opacity(0.14)` 底 + `"checkmark.seal.fill"`；否则橙色 + `"link.badge.plus"` | `:1050-1057` |
| 主标题 | `selectedVehicleName` = `dashboard.primaryVehicle?.vehicle.name ?? "暂无车辆"`，`headline`，`lineLimit(1)` | `:1060-1063`、`NinebotViewModel.swift:503` |
| 副标题 | `serverText` = `baseURLString.trimmed.isEmpty ? "服务器未配置" : "服务器 · \(baseURLString.trimmed)"`，`caption`，`lineLimit(1)`，**`truncationMode(.middle)`** | `:1064-1068`、`NinebotViewModel.swift:526-528` |
| 右上角数字 | `vehicleCount`，`title3.monospacedDigit().weight(.bold)`，下方 `"车辆"` `caption2` | `:1073-1080` |
| pill「账号」 | `accountText == "未绑定账号" ? "0" : "1"`，`person.fill` | `:1084` |
| pill「地址」 | `resolvedAddressCount`，`map.fill` | `:1085` |
| pill「详情」 | `rideDetailCount`，`doc.text.magnifyingglass` | `:1086` |
| 更新时间行 | `dashboardUpdatedAt != nil` 时 `Label("车况更新 {MM-dd HH:mm}", systemImage: "clock")` | `:1089-1093` |
| 错误行 | `lastError` 非空时橙色 `exclamationmark.triangle.fill` + 原文，`fixedSize(horizontal:false, vertical:true)`（允许多行） | `:1095-1100` |

三个计数的来源要分清 —— 两个是内存态，一个是磁盘态：

| 字段 | 来源 | 是否落盘 |
| --- | --- | --- |
| `resolvedAddressCount` | `resolvedAddresses.count`（ViewModel 内存字典，`init` 时按 `source == addressGeocodingSource` 过滤过，`NinebotViewModel.swift:169`） | 落盘但读的是过滤后的内存副本 |
| `rideDetailCount` | `rideDetails.count`（纯内存，`NinebotViewModel.swift:151`） | **不落盘，杀进程清零** |
| `accountText` | `currentAccountDisplay` = `savedPhone.isEmpty ? "未绑定账号" : savedPhone`（`NinebotViewModel.swift:182-185`） | 落盘 |

**「账号」pill 是靠字符串等值判出来的**（`diagnostics.accountText == "未绑定账号"`，`:1084`）。Android 侧改用布尔判断（`hasLoginAccount`，对应 `NinebotViewModel.swift:187-190`：phone 与 sessionToken 双非空），不要照抄比字符串。

`dashboardUpdatedAt` 有一道 sentinel 处理（`NinebotViewModel.swift:504`）：

```swift
dashboardUpdatedAt: dashboard.updatedAt == .distantPast ? nil : dashboard.updatedAt
```

`.distantPast` 是空 dashboard 的默认 `updatedAt`（Phase 1 的 1.1 陷阱 1 已记）。这里靠这一行挡住 `"01-01 00:00"`。

`lastError` 的取值是 `errorMessage ?? store.loadLastError()`（`NinebotViewModel.swift:507`）—— 内存优先，内存为 nil 才读磁盘。注意 `saveDashboard` 成功时会 `defaults.removeObject(forKey: Key.lastError)`（`NinebotSharedStore.swift:203`），所以磁盘上那条错误会被下一次成功刷新自动清掉。

#### 2.4 「复制原始返回值」复制的是什么

`DiagnosticsRawCopyCard`（`:1190-1247`）：

| 元素 | 内容 |
| --- | --- |
| 标题 | `"原始字段"`，`headline` |
| 右上角 | `snapshot == nil ? "无车辆" : "可复制"`，橙 / 绿 |
| 说明 | `"复制当前车辆、状态、电池和行程返回值，方便排查字段。"`，`caption` |
| 按钮 | `Label("复制全部原始字段", systemImage: "doc.on.doc.fill")`，`subheadline/semibold`，`frame(maxWidth:.infinity)` + `height 46`，`.borderedProminent`，`tint(Color.green)`，`.disabled(snapshot == nil)` |
| 反馈 | toast `"已复制原始字段"`，**1.3 秒**后清空（`Task.sleep(nanoseconds: 1_300_000_000)`，`:1243`） |

`copyRawPayload()`（`:1231-1246`）复制的是**当前 primaryVehicle 的 4 组原始 JSON 拼成的一个对象**：

```swift
let payload: [String: JSONValue] = [
    "vehicle": .object(snapshot.vehicle.raw    ?? [:]),   // NinebotModels.swift:76
    "status":  .object(snapshot.state.rawStatus ?? [:]),  // NinebotModels.swift:1032
    "battery": .object(snapshot.state.rawBattery ?? [:]), // NinebotModels.swift:1034
    "travel":  .object(snapshot.state.rawTravel ?? [:])   // NinebotModels.swift:1033
]
UIPasteboard.general.string = diagnosticsJSONString(.object(payload))
```

- **只有当前选中那一辆车**，不是全部车辆。
- 4 个 key 固定，缺失的原始字典退化为空对象 `{}`（不是省略这个 key）。
- 序列化走 `diagnosticsJSONString`（`:1459-1467`）：`JSONEncoder` + `outputFormatting = [.prettyPrinted, .sortedKeys]`，编码失败返回字符串 `"{}"`。

**这里有第二套复制，不要合并。** `RawPayloadCopyPanel`（`NinebotDashboardView.swift:4750-4799`，属于 Phase 2 的 2.7）：

| | 5.1 诊断中心 | 2.7 原始字段面板 |
| --- | --- | --- |
| 标题 | `"原始字段"` | `"原始返回值"` |
| 说明 | `"复制当前车辆、状态、电池和行程返回值，方便排查字段。"` | `"复制车辆、状态、行程接口的完整 JSON，方便排查新字段。"` |
| 按钮 | `"复制全部原始字段"` | `"复制完整返回值"` |
| payload key | vehicle / status / **battery** / travel（4 个） | vehicle / status / travel（**3 个，没有 battery**） |
| 编码 | `[.prettyPrinted, .sortedKeys]` | `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`（`NinebotFormatting.swift:115-123`） |
| toast 文案 | `"已复制原始字段"` | `"已复制完整返回值"` |
| toast 时长 | 1.3 秒 | **1.6 秒**（`DispatchQueue.main.asyncAfter(deadline: .now() + 1.6)`） |

**复制出去的内容含敏感数据。** 这份 JSON 是服务端原始返回，实测会包含：

- `sn`（车架序列号，`NinebotVehicleInfo.sn`）
- 可能的 `vin`（`NinebotVehicleInfo.vin`，`NinebotModels.swift:80-82`，从 raw 里认 `["vin","VIN","vehicle_vin","vehicleVin","car_vin","carVin"]` 六个键名）
- `latitude` / `longitude`（车辆当前坐标）
- 服务端可能透传的账号标识

#### 2.5 「清除当前提示」

`:991-1009`。`Button(role: .destructive)`，行文案 `title: "清除当前提示"` / `subtitle: "移除页面上的状态或错误提示"` / `systemImage: "xmark.circle"` / `tint: .red`，`buttonStyle(.plain)`，`padding(16)` + `ninePlusCard(cornerRadius: 24)`。

动作：`model.clearMessages()`（`NinebotViewModel.swift:477-480`，把 `errorMessage` 与 `statusMessage` 双置 nil），然后 toast `"已清除当前提示"`，1.3 秒后清空。

**它只清内存里的两个提示，不清磁盘上的 `ninebot.last.error`。** 所以点完之后 Hero 卡的错误行可能还在（因为 `lastError = errorMessage ?? store.loadLastError()`，内存清空后回落到磁盘那条）。iOS 既有行为。

#### 2.6 三个时间/耗时格式

`:1425-1446`，全部 `Locale("zh_CN")` + `TimeZone("Asia/Shanghai")`，**不是设备时区**：

| 函数 | 格式 | 用在 |
| --- | --- | --- |
| `formatDiagnosticsDate` | `"MM-dd HH:mm"` | Hero 卡「车况更新」 |
| `formatDiagnosticsTime` | `"HH:mm"` | 事件卡「时间」pill |
| `formatDiagnosticsDuration` | `seconds >= 10 → "{Int(rounded())}s"`；否则 `"%.1fs"` | 事件卡「耗时」pill |

耗时的分界是 **10 秒**：`9.94` → `"9.9s"`，`10.0` → `"10s"`，`12.5` → `"13s"`（`.rounded()` 是 HALF_AWAY_FROM_ZERO）。

### 三 · Android 实现要点

#### 3.1 存储：事件用 DataStore，计数用 Room + DataStore 混合

对齐 iOS 的「每来源 1 条」：**事件用 Proto DataStore，不要为 2 条记录建 Room 表。**

```kotlin
// core/data/diagnostics/RefreshEventStore.kt
enum class RefreshSource { App, Shortcut, Background, Widget, Tile }

@Serializable
data class RefreshEvent(
    val source: RefreshSource,
    val operation: String,          // 自由字符串，照抄 iOS 那三套
    val startedAtEpochMs: Long,
    val endedAtEpochMs: Long,
    val success: Boolean,
    val message: String?,
) {
    // 对齐 NinebotModels.swift:66-68 的下界 clamp
    val durationSeconds: Double get() = ((endedAtEpochMs - startedAtEpochMs).coerceAtLeast(0L)) / 1000.0
}

interface RefreshEventStore {
    val appEvent: Flow<RefreshEvent?>       // key: last_app_refresh_event
    val widgetEvent: Flow<RefreshEvent?>    // key: last_widget_refresh_event
    suspend fun recordApp(event: RefreshEvent)
    suspend fun recordWidget(event: RefreshEvent)
}
```

两个 slot 的分派规则照抄 iOS：`App` / `Shortcut` / `Background` → app slot；`Widget` / `Tile` → widget slot。`Tile` 是 Android 新增来源，1.3 的规格已经在用它，归到 widget slot（磁贴与 Widget 都是「App 外触发」，与 iOS 把 Control Widget 归到 widget key 同一口径）。

**`source` 用枚举而不是 `String`，`operation` 保持 `String`。** `source` 在 iOS 侧只有 5 个取值且用于分派；`operation` 有三套二十来个取值且会随功能增长，做成枚举只会在每次加操作时改两处。

计数与字节：

| 诊断项 | Android 数据源 |
| --- | --- |
| 接口行程 | Room：`SELECT COUNT(*) FROM interface_ride`（0.3 已建表） |
| 历史快照 | Room：`SELECT COUNT(*) FROM vehicle_history` |
| 本地轨迹 | Room：`SELECT COUNT(*) FROM recorded_ride`（不是轨迹点表） |
| 车况缓存字节 | 见 3.2 |

三个 `COUNT(*)` 写成 `Flow<Int>` 的 `@Query`，让页面自动更新，不要像 iOS 那样每次 body 求值重算。

#### 3.2 车况缓存字节怎么量

iOS 量的是 `UserDefaults` 里 `ninebot.dashboard.snapshot` 那个 `Data` 的 `count`，即 `JSONEncoder` 编出来的 JSON 字节数。Android 侧 dashboard 快照按 0.3 的规格存在 DataStore 里（序列化后的 JSON 字符串），**在写入时把长度一起记下来**，读的时候 O(1)：

```kotlin
// 写快照的地方（DashboardSnapshotStore）
suspend fun save(snapshot: DashboardSnapshot) {
    val json = json.encodeToString(snapshot)
    dataStore.edit {
        it[KEY_SNAPSHOT] = json
        it[KEY_SNAPSHOT_BYTES] = json.toByteArray(Charsets.UTF_8).size   // 与 iOS 的 Data.count 同语义
    }
}
```

不要去量 DataStore 的 `.preferences_pb` 文件大小 —— 那里面混着配置、登录态、地址缓存，还有 protobuf 的框架开销和未回收的旧值，量出来跟 iOS 完全不是一回事。

**两端数值不会相同，也不要求相同。** 同一辆车的同一份数据，Swift `JSONEncoder` 与 `kotlinx.serialization` 编出来的字节数会差几个百分点（键顺序、`Date` 编码策略 —— Swift 默认 `.deferredToDate`，即以 2001-01-01 为基准的 `Double` 秒数；Kotlin 侧按 0.2 的规格存 epoch 毫秒 `Long`）。验收只要求单位规则一致、量级一致。

字节格式化逐条对齐：

```kotlin
fun formatDiagnosticsBytes(bytes: Int): String = when {
    bytes <= 0            -> "0 B"
    bytes >= 1024 * 1024  -> "%.1f MB".format(bytes / 1024.0 / 1024.0)
    bytes >= 1024         -> "%.1f KB".format(bytes / 1024.0)
    else                  -> "$bytes B"
}
```

`"%.1f".format()` 在 Kotlin 里默认走 `Locale.getDefault()`，**德语/法语区域会输出 `1,5 MB`**。这里必须显式给 locale：`"%.1f".format(Locale.US, x)`，或者用 §3.3 里那个统一的 `DecimalFormat`。iOS 的 `String(format:)` 不受 locale 影响，两端才一致。

耗时同理：

```kotlin
fun formatDiagnosticsDuration(seconds: Double): String =
    if (seconds >= 10) "${seconds.roundToInt()}s"           // Kotlin roundToInt = HALF_UP，对上 Swift .rounded()
    else "%.1fs".format(Locale.US, seconds)
```

#### 3.3 时区固定

`formatDiagnosticsDate` / `formatDiagnosticsTime` 两个必须钉死时区与 locale，与 Phase 1 的 1.1 陷阱 9 同一口径：

```kotlin
private val DiagnosticsZone: ZoneId = ZoneId.of("Asia/Shanghai")
private val DiagnosticsLocale: Locale = Locale.SIMPLIFIED_CHINESE

private val DateFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MM-dd HH:mm", DiagnosticsLocale).withZone(DiagnosticsZone)
private val TimeFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("HH:mm", DiagnosticsLocale).withZone(DiagnosticsZone)
```

#### 3.4 剪贴板：必须标敏感位

复制的内容含车架号（`sn`）、可能的 `vin`、以及车辆经纬度。minSdk 33，`ClipDescription.EXTRA_IS_SENSITIVE` 在 API 33 就有，**无需版本判断，无条件标上**：

```kotlin
fun copyRawPayload(context: Context, json: String) {
    val clip = ClipData.newPlainText(/* label = */ "NineBot+ 原始字段", json)
    clip.description.extras = PersistableBundle().apply {
        putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
    }
    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
}
```

标上之后，系统在 Android 13+ 弹出的剪贴板预览气泡里**不会显示内容明文**，只显示「已复制」。不标的话，车架号和经纬度会直接出现在屏幕底部那个气泡里，而这正是用户可能在录屏或投屏时点的按钮。

三个必须处理的点：

1. **`label` 参数会被系统气泡与部分输入法显示出来**，不要把 JSON 塞进 label。上面写成固定文案。
2. **大 payload 会炸 Binder。** `setPrimaryClip` 走跨进程调用，整段 JSON 超过约 500 KB 就有 `TransactionTooLargeException` 风险（Binder 事务上限 1 MB，且是进程内共享）。单车的四组 raw 通常几 KB，但服务端如果把整月行程塞进 `rawTravel` 就会超。加一道保护：超过 **256 KB** 时改走 `Intent.ACTION_SEND` 系统分享（`text/plain`），并在按钮下方提示「内容过大，已改用分享」。这是新增行为，iOS 侧没有（iOS 的 `UIPasteboard` 没有这个限制）。
3. **不要再自己弹 toast。** Android 13+ 系统自己会给一个复制确认气泡，App 再弹一个「已复制原始字段」就是两层重复反馈。iOS 的那个 1.3 秒 toast 在 Android 上应当去掉 —— 但文案仍然要进 `strings.xml`，用于 `Modifier.semantics { }` 的 TalkBack 播报（系统气泡不一定被读屏读出来）。**这条是可见的行为差异，见文末 `## 待定` S1。**

#### 3.5 页面结构

`LazyColumn`（不是 `Column` + `verticalScroll`，卡片数量会随 Android 新增项增长）：

```kotlin
LazyColumn(
    contentPadding = PaddingValues(16.dp),
    verticalArrangement = Arrangement.spacedBy(16.dp),
) {
    item { DiagnosticsHeroCard(state) }
    item { CapturePrivacyToggleCard(state.captureProtectionEnabled, onToggle) }   // 5.2 的开关
    item { DiagnosticsEventCard(stringResource(R.string.diag_event_app), state.appEvent) }
    item { DiagnosticsEventCard(stringResource(R.string.diag_event_widget), state.widgetEvent) }
    item { DiagnosticsCacheCard(state.cache) }
    item { BackgroundRefreshStatusCard(state.workStatus) }                        // Android 新增，见 5.4 §3.6
    item { ClearMessagesCard(onClear) }
    item { RawCopyCard(state.canCopy, onCopy) }
}
```

toast 覆盖层用 `SnackbarHost` 或自绘的 `AnimatedVisibility` + `Modifier.align(Alignment.TopCenter)`。iOS 那个是页面顶部浮出的胶囊，不是底部 Snackbar；要视觉对齐就自绘，`enter = slideInVertically { -it } + fadeIn()`，`tween(180)` 对上 `easeInOut(0.18)`。

卡片样式两套并存，别统一：

| 样式 | 用在 | 参数 |
| --- | --- | --- |
| A（手写） | Hero / 两张事件卡 / 缓存卡 / 原始字段卡 | `padding(16.dp)`，`RoundedCornerShape(18.dp)`，`border(1.dp, hairline)`，**无 elevation** |
| B（`ninePlusCard`） | 防截屏开关格、清除提示格 | `RoundedCornerShape(24.dp)` + 阴影，走 Phase 0 建的 `ninePlusCard` modifier |

#### 3.6 状态组装：一次性快照 vs Flow

iOS 的 `diagnostics` 是计算属性（`NinebotSettingsView.swift:965-967`），**每次 `body` 求值都重新调 `diagnosticsSnapshot()`**，而后者会做 2N 次 UserDefaults 解码（N = 车辆数）、2 次事件解码、1 次 `RideTracks/` 全目录遍历。在 SwiftUI 里这是每帧潜在重算。

Android 侧不要照抄这个形状。用 `combine` 把各路 Flow 汇成一个 `DiagnosticsUiState`：

```kotlin
val uiState: StateFlow<DiagnosticsUiState> = combine(
    dashboardStore.snapshot,               // 车名、车辆数、updatedAt、cacheBytes
    configStore.config,                    // hasConfiguration、serverText
    authStore.account,                     // accountText / hasLoginAccount
    refreshEventStore.appEvent,
    refreshEventStore.widgetEvent,
    diagnosticsDao.counts(),               // 三个 COUNT(*) 合成一个 data class
    workStatusReader.status,               // 5.4 的 WorkManager 状态
) { ... }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DiagnosticsUiState.Loading)
```

`combine` 最多 5 个参数有重载，超过要嵌套或用 `combine(vararg flows)` 后自己取下标 —— 上面 7 路必须拆两层，别指望一个 `combine` 收下。

### 四 · 陷阱

1. **`operation` 三套字符串混在同一列。** 同一个「上电」在 App 内记 `"正在开锁"`、Shortcut 记 `"上电"`、Widget 记 `"开锁"`。看着像 bug，是 iOS 既有行为（`NinebotLoadingOperation.swift:41` / `NinebotAppIntents.swift:347` / `NinebotWidgetControlIntents.swift:5-19` 三处各自取值）。不要做归一化映射表，否则诊断中心就丧失了「区分是哪条链路发的」这个唯一用途。

2. **事件卡「待检查」是二义的。** `event?.success == true ? "成功" : "待检查"`（`:1123`）—— 从没跑过和跑失败了显示同一个词。Android 要区分（`null` → 「暂无记录」，`false` → 「失败」）就是主动改行为，写进 plan 记一笔；照抄的话必须在验收里明确两态视觉相同。

3. **`durationSeconds` 有下界 clamp 但没上界。** `max(endedAt - startedAt, 0)`。设备在请求过程中改了系统时间，可能记出几万秒。`formatDiagnosticsDuration` 对大数没有处理，`"86400s"` 会原样显示并把 pill 挤变形（iOS 靠 `minimumScaleFactor(0.68)` 顶住，`:1263`）。Android 侧 pill 也要给缩放或截断。

4. **「车况缓存」不含图片，而图片是最大的一块。** 单张车辆图上限 2 500 000 字节（`NinebotSharedStore.swift:396`），两辆车明暗两套就可能到 10 MB，而「车况缓存」显示的可能只有 40 KB。用户看到「车况缓存 40 KB」会以为 App 没占空间。这不是要修的 bug（iOS 就这样），但 Android 侧如果补一格图片字节，就要在 plan 里记为主动增项。

5. **`recordedTrackBytes` 算了不显示。** 别照抄「每次进页面都遍历一遍轨迹目录然后把结果扔掉」。

6. **`rideDetailCount` 是纯内存计数。** 杀进程重启后必然是 0，跟「缓存」这个语义不符（它在 Hero 卡的 pill 里叫「详情」）。Android 如果把行程详情落了 Room，这一格的数字会与 iOS 行为不同（iOS 重启归零，Android 不归零）。选哪个都要在 plan 里写明。

7. **「清除当前提示」清不掉 Hero 卡上的错误。** 见 §2.5。用户点了没反应，会以为按钮坏了。

8. **`serverText` 的 `truncationMode(.middle)`**（`:1068`）—— 服务器地址中间省略，不是尾部。Compose 的 `TextOverflow` 没有 middle，`TextOverflow.MiddleEllipsis` 在 Compose 1.8+ 才有；低于该版本要自己截。别退化成 `Ellipsis`（尾部），那样 `https://xxx.example.com/very/long/pa…` 把端口和路径全砍掉，反而看不出配到哪了。

9. **`ninebot.last.error` 会被下一次成功刷新自动删掉**（`NinebotSharedStore.swift:203`）。Android 的 `saveDashboard` 等价实现里这一步不能漏，否则一条陈旧错误会永远挂在 Hero 卡上。

10. **原始字段复制按钮的 `disabled` 条件是 `primaryVehicle == nil`**，不是 `hasConfiguration == false`。有配置但还没刷到车时按钮也是灰的。

### 五 · 验收标准

- [ ] 5 种 `source` 各触发一次（App 刷新 / Shortcut / 后台 Worker / Widget / 磁贴），事件落到正确的 slot：前三个进 app slot，后两个进 widget slot
- [ ] 同一个「上电」分别从 App 内、快捷方式、磁贴发起，诊断中心的 `operation` 分别显示 `"正在开锁"` / `"上电"` / `"开锁"`
- [ ] 连续触发 3 次 App 刷新，app slot 里**只有最后一条**（验证覆盖语义，不是追加）
- [ ] 耗时 pill：0.4s → `"0.4s"`；9.9s → `"9.9s"`；10.0s → `"10s"`；12.5s → `"13s"`
- [ ] 字节格式：0 → `"0 B"`；1 → `"1 B"`；1023 → `"1023 B"`；1024 → `"1.0 KB"`；1536 → `"1.5 KB"`；1048576 → `"1.0 MB"`
- [ ] 设备语言切德语（`de-DE`），字节与耗时仍输出 `"1.5 KB"` / `"0.4s"`（小数点是 `.` 不是 `,`）
- [ ] 设备时区改 UTC-8，「车况更新」与事件「时间」仍显示北京时间
- [ ] 空 dashboard 时不显示「车况更新」这一行（不是显示 `01-01 00:00`）
- [ ] 「原始字段」复制出的 JSON 顶层恰好 4 个 key（`battery` / `status` / `travel` / `vehicle`，按 `sortedKeys` 排序），缺失的原始字典是 `{}` 而不是缺 key
- [ ] 复制后系统气泡**不显示 JSON 明文**（验证 `EXTRA_IS_SENSITIVE` 生效），且屏幕上没有 App 自己的第二个 toast
- [ ] 构造一份 300 KB 的 `rawTravel`，复制走系统分享而不是崩 `TransactionTooLargeException`
- [ ] 无车辆时复制按钮为禁用态（视觉可见），有配置但未刷新过也是禁用态
- [ ] 打开诊断中心页面，Systrace 里**没有**主线程磁盘 IO（三个 `COUNT(*)` 与字节数都走 Flow，不在 composition 里读）
- [ ] 「清除当前提示」点击后内存提示消失；若磁盘上有 `last_error`，Hero 卡错误行仍在（与 iOS 一致）
- [ ] 系统最大字号 + 360dp 宽：Hero 卡三个 pill 不重叠，缓存卡 2×2 网格不换行溢出

---

## 5.2 防截屏（3.5 天）

> **已定的决策**（`pending-decisions.md` 已定表）：**与 iOS 一致 —— 屏幕正常显示、截图与录屏为空**，用 `SurfaceView.setSecure(true)`，**不用**窗口级 `FLAG_SECURE`。
>
> 两者不是同一个行为：`FLAG_SECURE` 让整个窗口在截图里变纯黑、在最近任务缩略图里也变黑、并且直接禁掉全部投屏；`SurfaceView.setSecure` 只让那一块 surface 在非安全输出上呈现为黑/空，页面其余部分照常出现在截图里。iOS 的行为是后者。

### 一 · iOS 现状

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| `ScreenCaptureProtectedView` | `ScreenCaptureProtectedView.swift:4-50` | `UIViewControllerRepresentable` 外壳 |
| `CaptureProtectedHostingController` | `:52-102` | 托两个 `UIHostingController`（内容 + 占位） |
| `CaptureProtectedContainerView` | `:104-215` | 真正干活的 `UIView` |
| `CapturePrivacyProtectionModifier` | `NinebotDashboardView.swift:283-305` | SwiftUI 侧的 `ViewModifier` |
| `CapturePrivacyPlaceholder` | `NinebotDashboardView.swift:307-327` | 占位视图 |
| `.capturePrivacyProtected(...)` | `NinebotDashboardView.swift:329-343` | 便捷扩展 |
| 开关持久化 | `NinebotSharedStore.swift:18`、`:63-69` | key `ninebot.capture.privacy.protection.enabled` |
| 开关状态与写入 | `NinebotViewModel.swift:145`、`:171`、`:482-487` | |
| 录屏检测 | `NinebotDashboardView.swift:18`、`:142`、`:154-156`、`:180-185` | |

#### 机制

iOS 侧用的是一个众所知的取巧手法：`UITextField(isSecureTextEntry: true)` 的**第一个 subview** 是一个受系统保护的 layer，把它摘出来当画布，装进去的任何内容都会在截图与录屏里缺失，但屏幕上正常渲染。

```swift
// ScreenCaptureProtectedView.swift:209-214
private static func makeSecureCanvas(from textField: UITextField) -> UIView? {
    guard let canvas = textField.subviews.first else { return nil }   // ← 可能为 nil
    canvas.subviews.forEach { $0.removeFromSuperview() }
    canvas.isUserInteractionEnabled = false
    return canvas
}
```

`secureCanvas` 是 `UIView?`，**可能拿不到**（`:115`、`:158`、`:168`）。拿不到时 `shouldUseSecureCanvas` 恒为 false，内容装进普通容器，等于保护静默失效 —— 没有任何提示。

#### 三层容器与状态机

容器（`:113-118`）：`placeholderContainer`、`publicContainer`、`secureCanvas?`，三者在 `setupUI()`（`:146-164`）里全部 `addSubview` 并四边 pin 满，`isUserInteractionEnabled = false`，`backgroundColor = .clear`，外层 `clipsToBounds = false`。

`updateProtectionState()`（`:166-189`）：

```
guard contentView != nil                                     // 内容还没装进来就整个跳过
hasSecureCanvas        = (secureCanvas != nil)
shouldUseSecureCanvas  = isProtectionEnabled && hasSecureCanvas
targetContainer        = shouldUseSecureCanvas ? secureCanvas : publicContainer

若 contentView.superview !== targetContainer → install(contentView, in: targetContainer)   // 搬家 + 重建约束

placeholderContainer.isHidden = !isProtectionEnabled
publicContainer.isHidden      = shouldUseSecureCanvas
secureCanvas?.isHidden        = !shouldUseSecureCanvas || isObscured

isObscured → bringSubviewToFront(placeholderContainer)
否则       → bringSubviewToFront(shouldUseSecureCanvas ? secureCanvas : publicContainer)
```

四个状态：

| `isProtectionEnabled` | `isObscured` | 屏幕上看到 | 截图/录屏里 |
| --- | --- | --- | --- |
| false | — | 内容（在 `publicContainer`） | 内容 |
| true | false | 内容（在 `secureCanvas`） | **空** |
| true | true | **占位**（secureCanvas 被隐藏，placeholder 提到最前） | 占位 |

**注意第三行**：正在录屏时，本机屏幕上用户自己也看不到内容了，换成占位。这是有意的 —— iOS 想让人知道「这块被藏了」，而不是自己看着有、录出来没有。

`isObscured` 来源（`NinebotDashboardView.swift:176-178`）：

```swift
private var isCapturePrivacyObscured: Bool {
    model.capturePrivacyProtectionEnabled && isScreenCaptured
}
```

`isScreenCaptured`（`:18` 声明，`:142` 与 `:154-156` 更新）由 `UIScreen.capturedDidChangeNotification` 驱动，读 `currentScreenIsCaptured`（`:180-185`）：

```swift
let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
return scenes.first(where: { $0.activationState == .foregroundActive })?.screen.isCaptured
    ?? scenes.first?.screen.isCaptured
    ?? false
```

**内容完全不可交互。** `setupHost`（`:96-101`）给两个 host 的 view 都设 `isUserInteractionEnabled = false`；`setContentView`（`:133-137`）、`setPlaceholderView`（`:139-144`）、容器自身（`:147`）也都设成 false。所以点击事件由**外层**的 `NavigationLink` 承担（`:1653-1673`、`:2097-2108`），包装体纯显示。

#### 保护的具体范围 —— 全仓只有 3 个调用点

| # | 位置 | 被包住的东西 | `cornerRadius` | `message` |
| --- | --- | --- | --- | --- |
| 1 | `NinebotDashboardView.swift:1667-1671` | 主卡片地址行，**有坐标分支**（`NavigationLink` 的 label 里那个 `Text(resolvedAddress)`，`caption2/medium`，`lineLimit(1)`，`truncationMode(.tail)`） | 6 | **nil** |
| 2 | `NinebotDashboardView.swift:1681-1685` | 主卡片地址行，**无坐标分支**（纯 `Text`，字体同上） | 6 | **nil** |
| 3 | `NinebotDashboardView.swift:2178-2183` | `VehicleLocationSummaryCard` 里的整个 `ZStack`：地图预览 `VehicleLocationPreviewMap` + 底部渐变 + `locationTitle` 文本；这个 ZStack 自己已经 `clipShape(UnevenRoundedRectangle(topLeading:18, bottomLeading:24, bottomTrailing:24, topTrailing:18))` | 18 | **`"位置已隐藏"`** |

`message == nil` 时占位是 `Color.clear`（`NinebotDashboardView.swift:323-325`）—— 前两处保护点在录屏时**就是一片空白**，没有任何「已隐藏」提示。只有第 3 处的地图块有那个胶囊标签。

**明确不在保护范围内**（Android 要对齐同一份范围，不要多保护也不要少保护）：

- 车架号 `sn` 与 `vin` —— `identifierSummaryText`（`NinebotModels.swift:84-89`，输出 `"SN {sn} · VIN {vin}"`）在车辆详情里裸显示，**没有保护**
- 地图详情页 `NinebotVehicleMapView` 整页
- 吸顶摘要 `CompactVehicleHeader`、主卡片的「更新 yyyy-MM-dd HH:mm」（地址为空时才出，`:1687-1692`，**这一支没包保护**）
- 行程列表 / 行程详情 / 本地轨迹里的任何坐标
- 5.1 诊断中心复制出去的原始 JSON（含 `vin` 与经纬度）
- Widget、磁贴、通知、实时活动里的任何内容

设置项副标题写的是 `"隐藏首页地址、车辆位置地图和地址"`（`NinebotSettingsView.swift:977`），与上面这 3 处一致。

#### 开关

- key：`ninebot.capture.privacy.protection.enabled`（`NinebotSharedStore.swift:18`）
- 读：`defaults.bool(forKey:)`（`:63-65`），**未设置时返回 false，即默认关闭**
- 写：`setCapturePrivacyProtectionEnabled`（`NinebotViewModel.swift:482-487`）—— 置内存 + 落盘 + `statusMessage = isEnabled ? "截图录屏保护已开启" : "截图录屏保护已关闭"` + `errorMessage = nil`
- UI：诊断中心里的 `Toggle`（`NinebotSettingsView.swift:974-984`），行文案 `title: "截图录屏保护"` / `subtitle: "隐藏首页地址、车辆位置地图和地址"` / `systemImage: "eye.slash.fill"` / `tint: .blue`

#### 动画

`CapturePrivacyProtectionModifier`（`:291-303`）在包装体上挂 `.animation(.easeInOut(duration: 0.18), value: isObscured)` —— 只对 `isObscured` 的切换（内容 ↔ 占位）做 180ms 过渡。`isEnabled` 的切换**没有动画**，因为 `isEnabled == false` 时整个包装体不存在（`else { content }`，`:301-303`），是 View 层级的增删而不是属性变化。

### 二 · 要移植的逻辑

#### 2.1 行为矩阵（必须逐格对齐）

| # | 开关 | 是否正在录屏/投屏 | 屏幕 | 截图 | 录屏 |
| --- | --- | --- | --- | --- | --- |
| A | 关 | — | 内容 | 内容 | 内容 |
| B | 开 | 否 | **内容** | **空** | **空** |
| C | 开 | 是 | **占位** | 占位 | 占位 |

B 是这一项的全部意义：**屏幕正常显示，截图为空**。如果实现出来是「屏幕也黑了」或「截图里也有内容」，这一项就没做成。

#### 2.2 保护点清单（Android 侧照抄这 3 处）

| # | Android 位置 | cornerRadius | 占位 message |
| --- | --- | --- | --- |
| 1 | `feature/dashboard` 主卡片地址行（有坐标，外层可点进地图） | 6.dp | 无（空白） |
| 2 | `feature/dashboard` 主卡片地址行（无坐标） | 6.dp | 无（空白） |
| 3 | `feature/dashboard` 位置卡里的地图预览块（2.1 交付） | 18.dp | `"位置已隐藏"` |

#### 2.3 占位视觉

```
message == null → 完全透明（Color.Transparent），什么都不画
message != null → RoundedRectangle(cornerRadius) 填充「超薄材质」
                  + 居中 Row{ Icon(VisibilityOff) + Text(message) }
                    caption/semibold，primaryText 色
                    padding(horizontal 12, vertical 8)
                    背景「常规材质」，Capsule 裁切
```

iOS 的 `.ultraThinMaterial` / `.regularMaterial` 在 Compose 里没有对应物。用 `Modifier.blur(radius)` + 半透明色近似，或者按 Phase 0 的设计 token 直接给两档半透明填充。这一处不追求像素级一致（它只在录屏时出现），但**不能做成不透明纯色** —— 那样在暗色主题下会变成一个突兀的方块。

### 三 · Android 实现要点

#### 3.1 核心：`SurfaceView.setSecure(true)` + `SurfaceControlViewHost`

`SurfaceView.setSecure(boolean)` 让 surface 被标为安全内容，不进入截图、录屏和非安全显示输出（与 `WindowManager.LayoutParams.FLAG_SECURE` 同一套底层机制，但作用域是这一个 surface）。

`SurfaceView` 本身不能直接装 Compose 内容 —— 它只有一个 `Surface`。要把一棵真实的 View/Compose 树渲进那个安全 surface，需要 `SurfaceControlViewHost`（API 30+，minSdk 33 满足）：

```kotlin
// core/secure/SecureSurfaceHost.kt
@Composable
fun SecureSurface(
    enabled: Boolean,
    obscured: Boolean,
    cornerRadius: Dp,
    placeholderMessage: String?,
    content: @Composable () -> Unit,
) {
    if (!enabled) {                      // 对齐 CapturePrivacyProtectionModifier:301-303
        content()                        // 关闭时完全不包装，零开销
        return
    }
    Box {
        AndroidView(
            factory = { ctx ->
                SurfaceView(ctx).apply {
                    setSecure(true)                  // ← 必须在附加到 window 之前，见 3.2
                    setZOrderMediaOverlay(true)      // 绝不用 setZOrderOnTop(true)，见 3.4
                    holder.setFormat(PixelFormat.TRANSLUCENT)
                }
            },
            update = { /* 见 3.3：把 ComposeView 挂进 SurfaceControlViewHost */ },
            modifier = Modifier.fillMaxWidth(),
        )
        if (obscured) {
            CapturePrivacyPlaceholder(cornerRadius, placeholderMessage)   // 画在 SurfaceView 之上
        }
    }
}
```

挂载侧（在 `update` 或 `SurfaceHolder.Callback.surfaceCreated` 里）：

```kotlin
val display = context.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
val host = SurfaceControlViewHost(context, display, surfaceView.hostToken)
val composeView = ComposeView(context).apply {
    setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
    setContent { content() }
}
host.setView(composeView, width, height)
surfaceView.setChildSurfacePackage(host.surfacePackage!!)
```

`setChildSurfacePackage` 是 API 30+。尺寸变化时要 `host.relayout(width, height)`，否则内容按首次尺寸拉伸。

**内嵌视图默认收不到触摸**（`SurfaceControlViewHost` 的输入需要单独转发），这**正好对上 iOS**（`isUserInteractionEnabled = false`，`ScreenCaptureProtectedView.swift:99/135/141/147`）。不要去费劲转发输入 —— 点击一律由外层 Compose 的 `clickable` / 导航承担，与 iOS 的 `NavigationLink` 在包装体外面同一结构。

#### 3.2 `setSecure` 必须在附加到 window 之前 —— 怎么重建

`SurfaceView.setSecure` 的约束是：**必须在这个 SurfaceView 所属的窗口被添加到 WindowManager 之前调用**。也就是说，不是「在 `addView` 之前」，而是「在 Activity 的窗口 attach 之前」。运行时把开关从关切到开，需要让承载它的窗口重新 attach。

三条路，代价不同：

| 方案 | 做法 | 代价 | 评价 |
| --- | --- | --- | --- |
| **A · 恒建（推荐）** | 无论开关是否打开，**Activity 创建时就无条件创建那 3 个 `SurfaceView` 并 `setSecure(true)`**，开关只切换「内容渲进安全 surface 还是渲在普通 Compose 层」，`SurfaceView` 只是 `isVisible` 变化 | 常驻 3 个 `SurfaceView` + 3 个 `SurfaceControlViewHost`，即使功能关闭；每个约几百 KB 图形内存 | **与 iOS 完全同构** —— iOS 也是在 `setupUI()`（`:146-164`）里无条件建好三层容器，开关只决定内容装进哪一层（`install(contentView, in: targetContainer)`，`:172-174`）。切换零延迟、无闪屏、不丢状态 |
| B · 重建 Activity | 开关变化时 `activity.recreate()` | 整屏重建 200–400ms 白/闪；`ViewModel` 通过 `ViewModelStore` 存活，滚动位置需要 `rememberSaveable`；正在进行的 `BiometricPrompt`、Snackbar、导航动画会中断 | 实现最省事，但用户在设置页切一下开关就整屏闪一次，且诊断中心自身会被重建、滚动位置跳回 |
| C · 独立窗口 | 把受保护内容放进一个自己的窗口（`Dialog` 或 `WindowManager.addView` 的浮层），只重建那个窗口 | 浮层要自己跟随滚动定位，位置同步比方案 A 的 `SurfaceView` 更差；`Dialog` 会夺焦 | 不建议。3 个保护点里有 2 个是嵌在滚动列表里的一行文字，用独立窗口跟随滚动是自找麻烦 |

**规定走方案 A。** 具体形状：

```kotlin
// 常驻，与开关无关
@Composable
fun SecureSurface(enabled: Boolean, obscured: Boolean, ...) {
    Box {
        // 普通层：开关关时显示
        if (!enabled) content()

        // 安全层：始终存在（setSecure 在 factory 里，只调一次），靠可见性切换
        AndroidView(
            factory = { ctx -> SurfaceView(ctx).apply { setSecure(true); ... } },
            modifier = Modifier
                .fillMaxWidth()
                .then(if (enabled && !obscured) Modifier else Modifier.alpha(0f)),
        )
        if (enabled && obscured) CapturePrivacyPlaceholder(...)
    }
}
```

用 `Modifier.alpha(0f)` 而不是 `if (enabled)` 包住 `AndroidView` —— 后者会把 `SurfaceView` 从 View 树里摘掉，下次再加回来时 `setSecure` 已经晚了。**注意 `alpha(0f)` 对 `SurfaceView` 不保证生效**（surface 是独立图层，`View.alpha` 不一定传导到 surface 合成），所以要双管：`alpha(0f)` + 在 `update` lambda 里 `view.visibility = if (show) VISIBLE else INVISIBLE`。用 `INVISIBLE` 而不是 `GONE`：`GONE` 会触发 detach 路径，某些 ROM 上等价于销毁 surface。

**必须实测的一条**：在目标机型上验证「`setSecure(true)` 的 SurfaceView 在 Activity 窗口 attach 之后才被 `addView` 进 Compose 树」这种情形下保护是否仍然生效。方案 A 里 `SurfaceView` 是随 Compose 首帧创建的，而 Activity 窗口在那之前已经 attach 了。如果实测发现这种时序下 `setSecure` 无效（截图里能看到内容），就必须退到方案 B，工期 +0.5 天。**这是 5.2 的最大技术风险，第一天就要写一个最小 demo 验掉。**

#### 3.3 圆角、材质、尺寸

**`Modifier.clip()` / `clipToOutline` 对 `SurfaceView` 的 surface 无效。** surface 是独立的合成图层，父 View 的裁切不作用于它。所以 iOS 的 `cornerRadius: 6` / `cornerRadius: 18` **必须画在被托管的内容里面**，不是画在 `AndroidView` 外面：

```kotlin
host.setView(
    ComposeView(context).apply {
        setContent {
            NinePlusTheme {            // 内嵌树是独立的 composition，主题/密度/字号都要重新提供
                Box(Modifier.clip(RoundedCornerShape(cornerRadius))) { content() }
            }
        }
    },
    width, height,
)
```

内嵌 composition **不继承外层的 `LocalDensity` / `LocalConfiguration` / 主题 / `LocalLifecycleOwner`**。至少要显式提供：主题、`LocalDensity`（否则 dp 换算在高密度屏上错）、`LocalLifecycleOwner` 与 `LocalSavedStateRegistryOwner`（缺了 `ComposeView` 会抛 `IllegalStateException: ViewTreeLifecycleOwner not found`）。用 `ViewTreeLifecycleOwner.set(composeView, lifecycleOwner)` 与 `ViewTreeSavedStateRegistryOwner.set(...)` 手动挂。

尺寸：iOS 的 `sizeThatFits`（`ScreenCaptureProtectedView.swift:89-94`）把 proposal 交给 `contentHost.sizeThatFits(in:)`，也就是**包装体的尺寸由内容决定**。Compose 侧 `AndroidView` 默认不会按内嵌内容自适应高度 —— `SurfaceControlViewHost` 里的树在另一个 composition 里测量，外层不知道它多高。两条路：

- 保护点 1、2 是**单行文字**，高度可算：外层给 `Modifier.height(lineHeightDp)`，用 `LocalTextStyle` 的 `lineHeight` 折算。简单可靠。
- 保护点 3 是**固定高度块**（父容器 `frame(height: 198)`，`NinebotDashboardView.swift:2083`，位置卡填满剩余高度），外层直接给死高度。

也就是说：**3 个保护点全部走固定/可算高度，不做内容自适应**。这避免了跨 composition 的测量回传，是这一项能压在 3.5 天的前提。

#### 3.4 z-order 与叠放

| API | 效果 | 用不用 |
| --- | --- | --- |
| 默认（不调） | surface 在窗口**之下**，窗口在该区域打一个透明洞露出 surface；Compose 里画在它之后（上面）的内容会盖住它 | 可用 |
| `setZOrderMediaOverlay(true)` | 同上，但排在其他 SurfaceView 之上，仍在窗口之下 | **用这个**（页面上还有高德地图的 SurfaceView / TextureView，要保证次序确定） |
| `setZOrderOnTop(true)` | surface 在**窗口之上**，Compose 内容画不到它上面 | **禁用**。用了之后 `obscured` 时的「位置已隐藏」占位、以及位置卡底部的渐变遮罩和文字都会被 surface 盖住 |

因为 surface 在窗口之下靠「打洞」露出，**打洞区域的窗口背景必须是透明的**。如果祖先链上任何一层给了不透明背景（例如卡片的 `Modifier.background(cardBackground)`），洞就被填上，surface 看不见 —— 表现为「那块地方是纯色，内容不见了」。位置卡本身有 `background(Color.teslaCardBackground)`（`NinebotDashboardView.swift:2186`），所以受保护的地图块必须在卡片背景**之上**的层级，且它自己那块区域不再叠不透明背景。这一条在真机上第一次跑必然踩到。

另外：**`SurfaceView` 的位置在滚动/动画时可能落后主 View 树一到两帧**。surface 的位置更新走单独的 `SurfaceControl.Transaction`，与窗口帧不总是同步。保护点 1、2 在主滚动列表里，快速滑动时那一行地址会「拖影」。缓解手段：

- API 33+ 的 `SurfaceView.setSurfaceLifecycle(SURFACE_LIFECYCLE_FOLLOWS_ATTACHMENT)` 只影响 surface 生命周期，**不解决位置同步**，别指望它
- 真正有效的是让受保护区域**不在快速滚动的路径上**，或者接受这个瑕疵。保护点 3（位置卡）本身尺寸大、滚动中不显眼；保护点 1、2 是主卡片里的一行小字，滚动时的错位会被看见
- **`TextureView` 位置同步完美，但没有 `setSecure`，用它等于没做防截屏。** 不是可选项

这一条要在验收里明确：**滚动中允许受保护区域有不超过 2 帧的位置滞后**。

#### 3.5 录屏检测（`isObscured`）—— minSdk 33 上做不到

`UIScreen.isCaptured` 在 Android 上的对应物：

| 方案 | API | 可用性 |
| --- | --- | --- |
| `WindowManager.addScreenRecordingCallback(executor, callback)` → `SCREEN_RECORDING_STATE_VISIBLE` / `_INVISIBLE` | **API 34（Android 14）** | 需要在 manifest 声明 `android.permission.DETECT_SCREEN_RECORDING`。**API 33 上不存在** |
| `DisplayManager` 监听非默认 display（`Display.FLAG_PRESENTATION`） | 全版本 | 只能发现「投屏/外接显示」，发现不了本机录屏。误报率高（连了车机 / 桌面模式都会命中） |
| 检测别的 App 在跑 `MediaProjection` | — | 无此 API，系统不暴露 |

结论：**minSdk 33，`isObscured` 只能在 API 34+ 实现，Android 13 上恒为 false。**

后果：Android 13 上矩阵里的 **C 行永远不会发生** —— 开关打开时，屏幕上一直显示内容，截图/录屏为空，但用户不会看到「位置已隐藏」那个提示。B 行（真正的保护）在 33 和 34+ 上都正常。

写法：

```kotlin
// core/secure/ScreenRecordingMonitor.kt
interface ScreenRecordingMonitor { val isRecording: Flow<Boolean> }

// API 34+
class Api34ScreenRecordingMonitor(private val windowManager: WindowManager) : ScreenRecordingMonitor {
    override val isRecording: Flow<Boolean> = callbackFlow {
        val cb = Consumer<Int> { state -> trySend(state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE) }
        val initial = windowManager.addScreenRecordingCallback(mainExecutor, cb)
        trySend(initial == WindowManager.SCREEN_RECORDING_STATE_VISIBLE)
        awaitClose { windowManager.removeScreenRecordingCallback(cb) }
    }
}

// API 33
object NoopScreenRecordingMonitor : ScreenRecordingMonitor {
    override val isRecording: Flow<Boolean> = flowOf(false)
}
```

`addScreenRecordingCallback` 的返回值就是当前状态，对应 iOS 在 `onAppear` 里主动读一次 `currentScreenIsCaptured`（`NinebotDashboardView.swift:142`）—— 不要只依赖回调，否则「先开录屏再进 App」这一种情形检测不到。

**`DETECT_SCREEN_RECORDING` 是否需要运行时授权、以及国产 ROM 上是否真的会回调，必须实测。** 声明在 manifest 里用 `<uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING" />` + `android:maxSdkVersion` 不加限制。

#### 3.6 开关的存储与文案

DataStore Preferences，key 名与 iOS 语义一致（不必字面一致，两端不共享存储）：

```kotlin
val CAPTURE_PROTECTION_ENABLED = booleanPreferencesKey("capture_privacy_protection_enabled")
// 默认 false，对齐 defaults.bool(forKey:) 的行为（NinebotSharedStore.swift:63-65）
```

切换时的提示文案照抄 `NinebotViewModel.swift:485`：`"截图录屏保护已开启"` / `"截图录屏保护已关闭"`。

开关格放在**诊断中心页面里**（对齐 `NinebotSettingsView.swift:974-984`），行文案：

| 字段 | 值 |
| --- | --- |
| title | `"截图录屏保护"` |
| subtitle | `"隐藏首页地址、车辆位置地图和地址"` |
| icon | 对应 `eye.slash.fill` 的自绘图标（Material Symbols 的 `visibility_off` 可用） |
| tint | 蓝（`.blue`） |
| 容器 | `padding(16.dp)` + `ninePlusCard(cornerRadius = 24.dp)` |

### 四 · 陷阱

1. **`setSecure` 的时序是这一项的成败点。** 见 §3.2。方案 A（恒建）依赖「Activity 窗口 attach 之后创建的 SurfaceView 仍能 setSecure 成功」，这一点文档没有保证。第一天必须写 demo 验：开关打开 → 系统截图 → 看那块区域是不是空的。验不过就退方案 B（`recreate()`），工期 +0.5 天。

2. **`FLAG_SECURE` 是个诱人的陷阱。** 一行代码就能让截图变黑，但它同时会：整个窗口在截图与最近任务缩略图里变纯黑、禁掉所有投屏（包括用户自己想投到电视上看地图）。行为与 iOS 完全不同，已定的决策明确排除。**不要因为 SurfaceView 方案调不出来就偷偷换成 FLAG_SECURE**，那是把「隐藏一行地址」变成「整个 App 不能截图」。

3. **`Modifier.clip()` 裁不到 surface。** 圆角必须画在内嵌内容里（§3.3）。表现为「地图块四角是方的，压在圆角卡片上露出直角」。

4. **打洞区域被不透明背景填掉。** 祖先链上任何不透明 `background` 都会挡住 surface（§3.4）。表现为「那块是纯色，内容不见了」，很容易误判成 `setSecure` 失效。排查顺序：先注掉 `setSecure(true)` 看内容是否出现，再查背景层。

5. **`setZOrderOnTop(true)` 会让占位层和渐变遮罩失效。** 位置卡底部有一层 `LinearGradient` + 地址文字压在地图上（`NinebotDashboardView.swift:2145-2167`），surface 在窗口之上就全被盖住了。

6. **内嵌 composition 不继承任何 `CompositionLocal`。** 少给 `LocalDensity` → dp 算错；少给 `ViewTreeLifecycleOwner` → 直接抛异常。这是 `SurfaceControlViewHost` + `ComposeView` 组合最常见的接入崩溃。

7. **`GONE` 会销毁 surface。** 隐藏安全层用 `INVISIBLE`，不要 `GONE`，也不要把 `AndroidView` 从 Compose 树里 `if` 掉（§3.2）。

8. **`isObscured` 在 Android 13 上恒 false。** 矩阵 C 行不会出现。别在验收里安排「Android 13 上开录屏看占位」这一步，它做不到。

9. **iOS 的 `secureCanvas` 可能为 nil，保护静默失效**（`ScreenCaptureProtectedView.swift:210`）。Android 侧对应的失效点是 `host.surfacePackage` 为 null 或 `SurfaceControlViewHost` 构造失败。**必须给出可见反馈** —— 至少在诊断中心显示一行「防截屏不可用」，不要像 iOS 一样静默降级成不保护。这是 Android 必须比 iOS 好的地方。

10. **被保护的内容不可点。** 与 iOS 一致（§一 · 机制）。所以外层的点击热区必须完整覆盖 —— 保护点 1 的外层是 `NavigationLink`（点进地图），Android 侧 `Modifier.clickable` 要挂在 `SecureSurface` 的**外面**，且 `SurfaceView` 不能消费触摸（默认不会，但如果为了输入转发做了额外工作就会）。

11. **每个保护点都是独立的 surface。** 3 个保护点 = 3 个 `SurfaceView` + 3 个 `SurfaceControlViewHost`。别想着共用一个。保护点 1 和 2 是同一行地址的两个互斥分支（有坐标 / 无坐标），实际同时只存在一个，但代码上是两处。

12. **两端行为一致性的口径是「截图为空」，不是「截图为黑」。** `setSecure` 的实际呈现由 ROM 决定：多数是纯黑，也有实现为纯白或不透明底色。iOS 的 secure canvas 在截图里是**透明/背景色**。验收标准写「不含可读内容」，不要写「必须是黑色」。

### 五 · 验收标准

- [ ] 开关打开，用系统截图（电源+音量下）截首页：地址行与位置卡地图块**不含可读内容**，页面其余部分（车名、电量、续航、三联指标、按钮）**完整可见**
- [ ] 同一状态下屏幕上**肉眼能正常看到**地址与地图（这是与 `FLAG_SECURE` 的分水岭）
- [ ] 开关打开，用系统录屏录 10 秒并回放：同上两条
- [ ] 开关打开，投屏到外接显示器 / Chromecast：受保护区域为空，其余可见，投屏**不被整体禁止**
- [ ] 最近任务缩略图里 App 界面**正常显示**（不是纯黑，验证没有误用 `FLAG_SECURE`）
- [ ] 开关关闭：截图、录屏、投屏中三处内容全部正常出现
- [ ] 在设置里连续切换开关 6 次，每次都立即生效，且**不发生 Activity 重建**（Logcat 里无 `onCreate` 重复、诊断中心滚动位置不跳）
- [ ] 3 个保护点逐个验收：主卡片地址（有坐标 / 无坐标两分支各一次）、位置卡地图块
- [ ] 位置卡地图块的四角圆角为 18dp（左上/右上 18，左下/右下 24 的不等圆角照 2.1 的规格），无直角露出
- [ ] 地图块上的底部渐变与地址文字**压在**受保护区域之上正常可见（验证 z-order 未用 `setZOrderOnTop`）
- [ ] 快速滑动首页 10 次，受保护区域的位置滞后不超过 2 帧，无明显拖影残留
- [ ] 暗色主题下受保护区域与周围背景无色差方块
- [ ] API 34 设备：开始录屏后 1 秒内，位置卡显示「位置已隐藏」胶囊，地址行变空白；停止录屏后恢复；切换有 180ms 过渡
- [ ] API 34 设备：**先开录屏再启动 App**，进首页即为占位态（验证读了 `addScreenRecordingCallback` 的初始返回值）
- [ ] API 33 设备：录屏时屏幕上仍显示内容（占位不触发），但录屏文件里受保护区域为空
- [ ] 至少两个品牌真机（含一台国产 ROM）跑完上面全部条目
- [ ] 人为让 `SurfaceControlViewHost` 构造失败（可用测试开关注入），诊断中心显示「防截屏不可用」而不是静默不保护

---

## 5.4 后台定时刷新（3 天）

### 一 · iOS 现状

`NinebotBackgroundTaskManager.swift`，全文 104 行，一个 `enum` 五个静态成员。

| 成员 | 行号 |
| --- | --- |
| `refreshIdentifier` | `:6` |
| `register()` | `:8-16` |
| `scheduleRefresh(after:)` | `:18-27` |
| `handle(_:)` | `:29-44` |
| `refreshDashboard(source:)` | `:46-92` |
| `defaultRefreshInterval` | `:94-103` |

标识符 `"com.example.NineBotPlus.refresh"`（`:6`），在 `Config/mini-ninebot-Info.plist:23-26` 的 `BGTaskSchedulerPermittedIdentifiers` 里登记。

#### 注册与排程

```swift
// :8-16
BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
    guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false); return
    }
    handle(refreshTask)
}

// :18-27
static func scheduleRefresh(after interval: TimeInterval = defaultRefreshInterval) {
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date().addingTimeInterval(interval)
    do { try BGTaskScheduler.shared.submit(request) }
    catch { /* 系统可能拒绝重复或暂时不可用的请求 —— 静默吞掉 */ }
}
```

**`submit` 的错误被完全吞掉**（`:24-26`），没有日志也没有事件。所以「后台刷新根本没排上」这件事在 iOS 上是不可见的。

调用点 4 处：

| 位置 | 时机 |
| --- | --- |
| `mini_ninebotApp.swift:16-17` | App `init`：先 `register()` 再 `scheduleRefresh()` |
| `ContentView.swift:67` | 根视图 `.task` |
| `ContentView.swift:74` | `scenePhase` → `.active` |
| `ContentView.swift:77` | `scenePhase` → `.background` |

#### 任务执行

```swift
// :29-44
private static func handle(_ task: BGAppRefreshTask) {
    scheduleRefresh()                                    // ← 第一件事就是排下一次
    let operation = Task { await refreshDashboard(source: "Background") }
    task.expirationHandler = { operation.cancel() }
    Task {
        let success = await operation.value
        task.setTaskCompleted(success: success)
    }
}
```

**`scheduleRefresh()` 在刷新之前调**（`:30`），所以下一次的间隔是用**这一次刷新之前的旧状态**算出来的。车刚插上充电，这一轮排的还是 20 或 30 分钟，要等下一轮才收敛到 15 分钟。

#### 刷新链路

`refreshDashboard(source:)`（`:46-92`），`@discardableResult`，返回 `Bool`：

```
startedAt = now
store   = NinebotSharedStore()
cached  = store.loadDashboard()
config  = store.loadConfiguration() ?? NinebotServerConfiguration(baseURLString: "", bearerToken: "")

若 !config.isUsable:
    记事件（source: 传入值, operation: "后台刷新", success: false, message: "未配置数据源"）
    return false

try:
    dashboard = NinebotServerClient(configuration: config).fetchDashboard(selectedSN: cached?.selectedSN)
    archived  = store.saveDashboard(dashboard)
    NinebotChargingLiveActivityManager.sync(with: archived)          // ← 先同步实时活动
    记事件（success: true, message: archived.primaryVehicle?.vehicle.name）
    WidgetCenter.shared.reloadAllTimelines()                          // ← 再刷 Widget
    return true
catch:
    store.saveLastError(error.localizedDescription)
    记事件（success: false, message: error.localizedDescription）
    return false                                                     // ← 失败时不刷 Widget
```

**顺序有意义**，Android 要照抄：落盘 → 充电实时活动 → 记事件 → 刷 Widget。失败路径**不刷 Widget**（Widget 自己有独立的 timeline 刷新，`NinebotWidgetProvider.swift:45-51`）。

`saveDashboard`（`NinebotSharedStore.swift:199-206`）的四个副作用：

1. 归档接口行程（`dashboardWithArchivedInterfaceRides`，每车上限 500 条）
2. 写 `ninebot.dashboard.snapshot`
3. **删除 `ninebot.last.error`**（`:203`）
4. `saveHistorySnapshots`（`:422-436`，每车上限 240 条，且有 `shouldAppend` 去重）

`fetchDashboard`（`NinebotServerClient.swift:80` 起）是 `GET /vehicles` **加上每辆车若干请求**，串行。单请求超时 `request.timeoutInterval = 20`（`:285`）。

**后台刷新不发任何用户通知。** 失败只写 `saveLastError` + 事件，用户下次打开 App 才在诊断中心/首页看到。

#### 自适应间隔 —— 逐字核对过的三档

```swift
// NinebotBackgroundTaskManager.swift:94-103
private static var defaultRefreshInterval: TimeInterval {
    let state = NinebotSharedStore().loadDashboard()?.primaryVehicle?.state
    if state?.isCharging == true, state?.isFullyCharged != true {
        return 15 * 60
    }
    if state?.isLocked == false || state?.isPoweredOn == true {
        return 20 * 60
    }
    return 30 * 60
}
```

| 档 | 精确条件 | 间隔 |
| --- | --- | --- |
| 1 | `isCharging == true` **且** `isFullyCharged != true` | **15 分钟**（900 秒） |
| 2 | `isLocked == false` **或** `isPoweredOn == true` | **20 分钟**（1200 秒） |
| 3 | 其余（含 `state == nil`） | **30 分钟**（1800 秒） |

三个数确认为 15 / 20 / 30 分钟。四条要点：

- **档 2 的第一个条件是 `isLocked == false`（明确未上锁），`nil` 不命中。** 三态语义，与 Phase 1 陷阱 2 同一口径，不能写成 `!isLocked`。
- **`isFullyCharged` 是派生属性**（`NinebotModels.swift:1203-1206`）：`battery != nil && battery >= 100`。`battery == nil` 时为 `false`，所以「在充电且电量未知」命中档 1。
- **只看 `primaryVehicle`**，多车时其余车辆的状态不参与。
- **它是一个 `static var`（计算属性），被用作默认参数值。** Swift 的默认参数表达式在每个调用点求值，所以每次 `scheduleRefresh()` 都会重新 `loadDashboard()` 读一次磁盘。不是「App 启动时算一次」。

#### 与 App 内自动刷新的区别（别混）

`refreshAutomaticallyIfPossible()`（`NinebotViewModel.swift:208-219`）是**另一套东西**：

```swift
guard hasConfiguration else { return }
guard !isLoading else { return }
if let lastAutomaticRefreshAt, now.timeIntervalSince(lastAutomaticRefreshAt) < 8 { return }
lastAutomaticRefreshAt = now
await refreshDashboard()
```

**8 秒**节流，由 `refreshOnLaunchIfPossible()`（`:196-200`）与 `refreshWhenActiveIfPossible()`（`:202-206`）调用，对应 App 冷启动与回到前台。这一条在 Phase 0/1 已归属，5.4 不重复实现，但**必须知道它存在** —— 回到前台时 App 内刷新和后台任务可能几乎同时跑，两者共用同一份 `saveDashboard`。

#### Widget 侧还有第四套间隔（属于 5.3，写在这里防混淆）

`NinebotWidgetProvider.refreshIntervalMinutes(for:)`（`NinebotWidgetProvider.swift:45-51`）：

```
state == nil                                          → 30
isCharging == true && !isFullyCharged                 → 3
isLocked == false || isPoweredOn == true              → 8
battery != nil && battery < 20                        → 10
其余                                                   → 20
```

**四档 3 / 8 / 10 / 20 分钟，还多一个「电量 < 20% → 10 分钟」的档**，是后台任务那三档没有的。这套归 5.3，5.4 不要照它写。

### 二 · 要移植的逻辑

#### 2.1 三档间隔（照抄，不改数值）

```kotlin
// core/work/RefreshInterval.kt —— 纯 Kotlin，可单测
object RefreshInterval {
    val CHARGING: Duration = 15.minutes    // 900s
    val IN_USE:   Duration = 20.minutes    // 1200s
    val IDLE:     Duration = 30.minutes    // 1800s

    fun forState(state: VehicleState?): Duration = when {
        state?.isCharging == true && state.isFullyCharged != true -> CHARGING
        state?.isLocked == false || state?.isPoweredOn == true    -> IN_USE
        else                                                     -> IDLE
    }
}
```

`isLocked`/`isPoweredOn`/`isCharging` 保持 `Boolean?`，**禁止 `?: false`**（Phase 1 陷阱 2）。`isFullyCharged` 走领域层已抽出的派生属性。

#### 2.2 刷新链路顺序（照抄）

```
1. 读配置；不可用 → 记事件(success=false, message="未配置数据源") → 结束
2. fetchDashboard(selectedSn = 缓存里的 selectedSn)
3. saveDashboard(含：归档行程 500 上限 / 写快照 / 删 lastError / 追加历史 240 上限)
4. 通知充电实时活动（5.5）
5. 记事件(source="Background", operation="后台刷新", message=车名)
6. 通知 Widget（5.3）
失败：写 lastError + 记事件(success=false, message=错误文案)，不通知 Widget
```

`operation` 恒为字符串 `"后台刷新"`，`source` 恒为 `RefreshSource.Background`。

#### 2.3 不发用户通知

后台刷新成功或失败都**不弹通知**。唯一例外是 5.5 的充电实时活动（那是常驻通知，由充电状态而非刷新结果驱动）。这一条要写进代码注释，否则「后台刷新失败了应该告诉用户吧」是个很自然的错误改动 —— 在国产 ROM 上后台任务被掐是常态，那会变成每天几条失败通知。

### 三 · Android 实现要点

#### 3.1 WorkManager 的硬约束，以及怎么在这套约束下拿到三档间隔

三条事实：

1. **`PeriodicWorkRequest` 的最小周期是 15 分钟**（`PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS = 900_000`），最小 flex 是 5 分钟（`MIN_PERIODIC_FLEX_MILLIS = 300_000`）。传更小的值会被静默抬到 15 分钟。**iOS 的充电档正好等于这个下限**，一点余量都没有。
2. **周期性任务的间隔改不了。** 想换间隔只能 `cancel` + 重新 `enqueue`，或者 `enqueueUniquePeriodicWork(..., ExistingPeriodicWorkPolicy.UPDATE, ...)` —— 但 `UPDATE` 会重置周期计时，频繁调用等于永远不触发。
3. **实际间隔由系统决定，不由你决定。** Doze 与 App Standby 分桶会把任务延后。官方文档给出的分桶延后上限：

| App Standby 分桶 | 任务可被延后 |
| --- | --- |
| active | 基本不限制 |
| working_set | 约 2 小时 |
| frequent | 约 8 小时 |
| rare | 约 24 小时 |
| restricted（Android 12+） | 约每天 1 次 |

进入深度 Doze 后，任务只在维护窗口执行，窗口间隔随待机时长递增（分钟级 → 小时级）。**国产 ROM 会在这套之上再加自己的管控，实测比 AOSP 更激进。**

**规定实现：15 分钟周期心跳 + Worker 内部按三档判定是否真的发请求。**

```kotlin
// core/work/DashboardRefreshScheduler.kt
private const val UNIQUE_NAME = "dashboard_periodic_refresh"

fun schedule(context: Context) {
    val request = PeriodicWorkRequestBuilder<DashboardRefreshWorker>(
        repeatInterval = 15, repeatIntervalTimeUnit = TimeUnit.MINUTES,   // = 系统下限
        flexTimeInterval = 5, flexTimeIntervalUnit = TimeUnit.MINUTES,    // = 系统下限
    )
        .setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()                        // 只要网络，别的都不要，见下
        )
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        .build()

    WorkManager.getInstance(context).enqueueUniquePeriodicWork(
        UNIQUE_NAME,
        ExistingPeriodicWorkPolicy.KEEP,        // KEEP，不是 UPDATE —— UPDATE 会重置周期计时
        request,
    )
}
```

Worker 里做闸门：

```kotlin
class DashboardRefreshWorker(...) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val snapshot = dashboardStore.snapshotOrNull()
        val required = RefreshInterval.forState(snapshot?.primaryVehicle?.state)
        val since = clock.now() - (snapshot?.updatedAt ?: Instant.DISTANT_PAST)
        // 留 60 秒容差：WorkManager 的实际触发点会在 flex 窗口内浮动，
        // 严格比较会让「差 3 秒到点」的那一轮白跑一次，下一轮又要等 15 分钟
        if (since < required - 60.seconds) return Result.success()

        return withTimeout(45.seconds) { refresh() }   // 见 3.2
    }
}
```

这样：

- 充电时（要求 15 分钟）每次心跳都会真刷 —— 与 iOS 的充电档等价。
- 使用中（20 分钟）每两次心跳刷一次，实际落在 30 分钟附近（15 的整数倍里第一个 ≥ 20 的是 30）。**比 iOS 的 20 分钟慢**。要更贴近就得把心跳降到 5 分钟 —— 但 `PeriodicWorkRequest` 做不到，只能靠自排链（见下）。
- 空闲时（30 分钟）每两次心跳刷一次，正好 30 分钟。

**为什么不用「一次性任务自排链」照抄 iOS。** 字面对应 iOS 的做法是 `OneTimeWorkRequest.setInitialDelay(interval)`，Worker 跑完再排下一个（正好对上 `handle` 里第一行的 `scheduleRefresh()`）：

| | 周期心跳 + 闸门（选它） | 一次性自排链 |
| --- | --- | --- |
| 间隔精度 | 只能是 15 的倍数 | 任意值，20 分钟能精确排 |
| 断链风险 | 无，周期任务系统自己维护 | **有**。任何一次没跑到（进程被杀、任务被丢弃、异常没接住）链条就永久断掉，之后再也不刷，且没有任何迹象 |
| 重启恢复 | WorkManager 自动 | WorkManager 也会恢复，但如果断链发生在恢复之前就没救 |
| 与 iOS 的相似度 | 低 | 高 |

**在一个后台任务本来就被 ROM 各种掐的平台上，「断了就永久不刷」是不能接受的风险。** 选周期心跳。这个偏离要在 plan 里记一笔：使用中档的实际间隔从 20 分钟变为约 30 分钟。

`Constraints` 里**不要**加这三个：

| 约束 | 为什么不要 |
| --- | --- |
| `setRequiresCharging(true)` | **这指的是手机在充电，不是车在充电。** iOS 那个 15 分钟档是「车辆在充电」，两回事。加上它，车在充电但手机没插电时后台刷新完全不跑 —— 正好把最需要的场景干掉 |
| `setRequiresDeviceIdle(true)` | 只在设备空闲时跑，直接与「骑行中每 20 分钟刷一次」矛盾 |
| `setRequiresBatteryNotLow(true)` | 手机低电量时不刷，看着合理，但它会让「用户手机快没电、想确认车锁没锁」这个场景失效 |

`setRequiresCharging` 唯一的正当用法：**如果**将来要做「手机充电时提高刷新频率」，那是新增功能，不是移植 iOS 的三档。现在不做。

`setExpedited` 不适用 —— 它只对 `OneTimeWorkRequest` 有效，且有严格配额，不是给周期刷新用的。

#### 3.2 Worker 的超时

| | iOS | Android |
| --- | --- | --- |
| 系统给的执行窗口 | `BGAppRefreshTask` 约 30 秒，超时走 `expirationHandler`（`:36-38`）→ `operation.cancel()` | `CoroutineWorker` **10 分钟**，之后 `isStopped` 置真并被停掉 |
| 单请求超时 | 20 秒（`NinebotServerClient.swift:285`） | 主 App 的 OkHttpClient 20 秒（Phase 1 的 1.3 已定：`@Named("app")`） |

Android 的 10 分钟窗口远比 iOS 宽，但**不能真用满** —— 一个卡住的请求占着 Worker 十分钟，会拖累 WorkManager 的配额并让下一次心跳错过。显式加 `withTimeout(45.seconds)`：`fetchDashboard` 是 1 + N 个串行请求，单个 20 秒，两辆车最坏 60 秒；45 秒是「单车正常 + 一次重试」的余量。超时 → `Result.retry()`（走 `setBackoffCriteria` 的指数退避，起点 30 秒）。

退避的边界：`WorkRequest.MIN_BACKOFF_MILLIS = 10_000`（10 秒），`MAX_BACKOFF_MILLIS = 18_000_000`（5 小时）。给 30 秒起点、`EXPONENTIAL`，第 5 次重试就到 8 分钟量级，够了。**`Result.retry()` 的次数没有内建上限**，要靠 `runAttemptCount` 自己截断：超过 3 次直接 `Result.success()`（放弃这一轮，等下次心跳），否则一个持续挂掉的服务端会让 Worker 一直退避重试到 5 小时间隔。

#### 3.3 刷新完之后通知谁 —— 接口边界

5.4 **不直接 import** Glance、通知、ViewModel 里的任何类型。在 `core/work` 里声明两个接口，5.3 与 5.5 各自实现并通过 Hilt 多绑定注入：

```kotlin
// core/work/DashboardRefreshListener.kt
/** 一次后台刷新的结果。落盘已完成，监听者只负责把它推给自己那块 UI。 */
sealed interface RefreshOutcome {
    data class Success(val snapshot: DashboardSnapshot) : RefreshOutcome
    data class Failure(val message: String) : RefreshOutcome
    data object NotConfigured : RefreshOutcome
}

interface DashboardRefreshListener {
    /** 在 IO 线程调用，允许挂起。抛异常不影响其他监听者，也不影响 Worker 的返回值。 */
    suspend fun onRefreshed(outcome: RefreshOutcome)

    /** 决定调用顺序，小的先调。见下表。 */
    val priority: Int
}
```

Worker 里：

```kotlin
private suspend fun refresh(): Result {
    // ... fetch + dashboardStore.save(...)  ← 落盘必须在通知之前
    listeners.sortedBy { it.priority }.forEach {
        runCatching { it.onRefreshed(outcome) }
            .onFailure { e -> Log.w(TAG, "listener ${it::class.simpleName} failed", e) }
    }
    refreshEventStore.recordApp(event)     // 见下表的顺序
    return Result.success()
}
```

**顺序照抄 iOS**（`NinebotBackgroundTaskManager.swift:68-78`）：

| # | 步骤 | iOS 对应 | 归属 |
| --- | --- | --- | --- |
| 1 | 落盘快照（含删 lastError、追加历史、归档行程） | `store.saveDashboard(dashboard)`（`:68`） | 5.4 |
| 2 | 通知充电实时活动 | `NinebotChargingLiveActivityManager.sync(with: archived)`（`:69`） | **5.5** 实现 `DashboardRefreshListener`，`priority = 10` |
| 3 | 记刷新事件 | `store.saveLastAppRefreshEvent(...)`（`:70-77`） | 5.4 调 5.1 的 `RefreshEventStore` |
| 4 | 刷 Widget | `WidgetCenter.shared.reloadAllTimelines()`（`:78`） | **5.3** 实现 `DashboardRefreshListener`，`priority = 20` |
| — | UI | **无**。iOS 靠下次进 App 重新 `loadDashboard()` | 5.4 什么都不做 —— DataStore/Room 写入会自动让 ViewModel 的 Flow 发射，UI 自然更新 |

三条边界规定：

1. **失败与未配置时不通知 Widget。** iOS 的 `WidgetCenter.reloadAllTimelines()` 只在成功路径（`:78`）。所以 5.3 的实现里 `onRefreshed(Failure)` / `onRefreshed(NotConfigured)` 应当直接返回。这一条写在接口注释里，5.3 那边照做。
2. **5.5 的充电实时活动在失败时也要收到通知。** iOS 的 `sync` 只在成功路径调，但那是因为失败时 dashboard 没变。Android 侧 `Failure` 时也调 listener，让 5.5 自己决定要不要结束活动（比如连续失败很久、不该再显示「充电中 3 分钟前」）。**这是 5.5 的决定，5.4 只负责把事件送到。**
3. **5.4 绝不 post 通知。** 见 §2.3。

反向依赖（5.1 要读 5.4 的调度状态）也用接口，实现放 5.4：

```kotlin
// core/work/WorkStatusReader.kt
data class BackgroundRefreshStatus(
    val state: WorkInfo.State?,           // ENQUEUED / RUNNING / SUCCEEDED / FAILED / CANCELLED / BLOCKED
    val runAttemptCount: Int,
    val nextScheduleTimeMillis: Long?,    // WorkInfo.nextScheduleTimeMillis，WorkManager 2.9+
    val standbyBucket: Int?,              // UsageStatsManager.getAppStandbyBucket()
    val ignoringBatteryOptimizations: Boolean,
)

interface WorkStatusReader { val status: Flow<BackgroundRefreshStatus> }
```

#### 3.4 国产 ROM 的电池优化

**保活引导的规格在 Phase 0 的 0.6**（`docs/phase0-foundation-spec.md:326-333`）：`PowerManager.isIgnoringBatteryOptimizations()` 检测 + 白名单请求、按 `Build.MANUFACTURER` 分支跳厂商自启动管理页（Intent 不保证长期有效，要 try-catch 兜底到应用详情页）。**引用它，5.4 不重写。**

5.4 额外需要的只有三件，全部是「让不工作变得可见」，都落在 5.1 的诊断中心页面里（新增一张卡）：

1. **实际调度状态**。`WorkManager.getInstance(ctx).getWorkInfosForUniqueWorkFlow(UNIQUE_NAME)` → `WorkInfo.state`、`runAttemptCount`、`nextScheduleTimeMillis`（WorkManager 2.9+ 才有这个字段）。这是唯一能回答「系统到底有没有在跑」的东西。iOS 侧完全没有对应物（`submit` 的错误被吞了，`:24-26`）。
2. **App Standby 分桶**。`context.getSystemService(UsageStatsManager::class.java).appStandbyBucket`（API 28+，**读自己的分桶不需要 `PACKAGE_USAGE_STATS` 权限**）。返回 `STANDBY_BUCKET_ACTIVE`(10) / `WORKING_SET`(20) / `FREQUENT`(30) / `RARE`(40) / `RESTRICTED`(45)。落到 `RARE` 或 `RESTRICTED` 就直接解释了「为什么一天只刷了一次」。映射成中文档位显示，并给出上表的延后上限。
3. **电池优化白名单状态**。`PowerManager.isIgnoringBatteryOptimizations(packageName)` 在这张卡上再显示一次（0.6 负责引导流程，这里只是读数），不在白名单时给一个跳转按钮复用 0.6 的引导。

`RESTRICTED` 桶只有在用户手动限制或系统判定后才进入，一旦进入，即使加了白名单也要等系统重新评估。这一点要在文案里说清，否则用户加了白名单发现没变化会以为白加了。

#### 3.5 怎么表达「间隔是建议不是保证」

两端都是「建议」：iOS 的 `earliestBeginDate` 只是最早可执行时间，`BGAppRefreshTask` 由系统按使用习惯调度，可能几小时不跑；Android 的偏差更大且更常见（分桶 + Doze + ROM 三重管控）。

三个层面：

| 层面 | 做法 |
| --- | --- |
| 设置页文案 | 在后台刷新那一格的 subtitle 里写清是估计值。建议文案：**「后台刷新 · 约 15/20/30 分钟一次」**，说明行：**「实际间隔由系统电池策略决定，可能明显长于此值。想要即时数据请下拉刷新。」** |
| 诊断中心 | §3.4 的那张卡，把「下次预计」「上次结果」「待机分桶」「白名单状态」四项摊开。这是唯一诚实的表达 —— 不解释机制，直接把系统给的数字摆出来 |
| 不做的事 | **不要**在设置里给用户一个「刷新间隔」滑块。间隔是由车辆状态自动决定的三档，给滑块等于承诺一个做不到的精度 |

**具体文案与要不要在设置页展开说明，属于产品决定，见文末 `## 待定` S2。** 上面是建议写法。

#### 3.6 排程的触发点

对齐 iOS 的四处（`mini_ninebotApp.swift:16-17`、`ContentView.swift:67/74/77`）：

| Android 时机 | 做什么 |
| --- | --- |
| `Application.onCreate()`（或 `Configuration.Provider` 的初始化之后） | `schedule(context)`，`ExistingPeriodicWorkPolicy.KEEP` |
| `MainActivity` `ON_START` | `schedule(context)`（KEEP 保证不会重置周期） |
| 进入后台（`ON_STOP`） | 不需要额外做。周期任务本来就在跑 |
| 登录成功 / 配置保存成功 | `schedule(context)`。iOS 靠 `scenePhase` 顺带覆盖，Android 明确加这一处 —— 首次配置完成时应该立刻把任务排上 |
| 退出登录 | `WorkManager.cancelUniqueWork(UNIQUE_NAME)`。iOS 没有这一步（配置不可用时后台任务照排、跑起来记一条「未配置数据源」失败事件，`:53-63`）。Android 直接取消更省电；**照抄 iOS 的话就是每 15 分钟白跑一次并记一条失败事件**。规定取消，并在重新登录时重排 |

`ExistingPeriodicWorkPolicy` 必须是 `KEEP`。用 `UPDATE` 的话，每次 `onStart` 都会重置周期计时 —— 用户每十分钟打开一次 App，后台刷新就永远不会触发。这是这一项最容易犯且最难发现的错。

### 四 · 陷阱

1. **`setRequiresCharging` 指手机不指车。** 见 §3.1 的表。加上它等于把充电场景的后台刷新彻底关掉。

2. **`ExistingPeriodicWorkPolicy.UPDATE` 会重置周期计时。** 用 `KEEP`。症状：后台刷新在测试机上「从来没触发过」，而日志里 `enqueue` 每次都成功。

3. **`PeriodicWorkRequest` 最小 15 分钟，且充电档正好等于 15 分钟。** 没有余量。如果将来 iOS 侧把充电档调到 10 分钟，Android 侧无法跟随（只能改用一次性自排链，见 §3.1 的对比表）。

4. **下一次的间隔用的是刷新前的旧状态。** iOS 在 `handle` 第一行就 `scheduleRefresh()`（`:30`）。Android 的周期心跳方案里这个问题自动消失（心跳恒 15 分钟，闸门每次都读最新状态），**这是偏离 iOS 但更正确的地方**，在 plan 里记一笔。

5. **`isLocked == false` 不等于 `!isLocked`。** 档 2 的条件是「明确未上锁」，`nil` 不命中。写成 `!(state.isLocked ?: true)` 才等价 —— 但更该直接写 `state?.isLocked == false`。

6. **`Result.retry()` 没有内建重试上限。** 靠 `runAttemptCount > 3` 自己截断，否则服务端持续 500 会让退避一路涨到 5 小时。

7. **`CoroutineWorker` 的 10 分钟窗口不是许可。** 显式 `withTimeout(45.seconds)`。没有它，一个 TCP 层面挂住的连接会占满窗口。

8. **失败路径不能刷 Widget。** 见 §3.3 边界 1。刷了会让 Widget 用旧数据重新渲染一遍，白耗一次 Glance 更新配额。

9. **后台刷新不发通知。** 见 §2.3。在国产 ROM 上后台任务被掐是常态，「刷新失败」通知会变成每天几条噪音。

10. **退出登录要取消任务。** iOS 不取消（照排、跑起来记失败），Android 取消。这是有意偏离。

11. **`saveDashboard` 的四个副作用一个都不能漏**，尤其是「删 `lastError`」（`NinebotSharedStore.swift:203`）。漏了它，一条陈旧错误会永久挂在诊断中心和首页上。

12. **两套间隔容易混。** 后台任务是 15/20/30（三档），Widget timeline 是 3/8/10/20（四档，多一个电量 <20% 档）。前者归 5.4，后者归 5.3。写成两个独立函数，放在各自的模块里，不要放同一个文件。

13. **`WorkInfo.nextScheduleTimeMillis` 需要 WorkManager 2.9+。** 版本低于此拿不到「下次预计」，诊断卡上那一格要能优雅缺失。

14. **`getAppStandbyBucket()` 读自己不需要权限，读别人需要。** 别为它去申请 `PACKAGE_USAGE_STATS`（那是需要用户去特殊访问权限页手动开的），读自己的分桶直接调就行。

### 五 · 验收标准

- [ ] `RefreshInterval.forState` 单测覆盖 12 组输入：`isCharging` × `isFullyCharged` × `isLocked` × `isPoweredOn` 的 `null/true/false` 组合，输出与 iOS 三档表**逐个相同**
- [ ] 专项验证四个边界：`isCharging=true, battery=null` → 15 分钟；`isCharging=true, battery=100` → 落到档 2 或 3（不是 15）；`isLocked=null, isPoweredOn=null` → 30 分钟；`state=null` → 30 分钟
- [ ] `adb shell cmd jobscheduler run -f <pkg> <jobId>` 强制触发一次，Worker 完整跑通：落盘 → 5.5 listener → 记事件 → 5.3 listener，**顺序与日志一致**
- [ ] 未配置服务器时触发：记一条 `success=false, message="未配置数据源", operation="后台刷新", source=Background` 的事件，**不通知 Widget**
- [ ] 网络失败时触发：写 `lastError`、记失败事件、**不通知 Widget**、5.5 的 listener 仍被调用
- [ ] 快照 `updatedAt` 距今 5 分钟 + 车辆空闲（要求 30 分钟）：Worker 直接 `Result.success()` 返回，**不发任何网络请求**（用 MockWebServer 断言零请求）
- [ ] 快照 `updatedAt` 距今 14 分 10 秒 + 车辆在充电（要求 15 分钟）：**发请求**（验证 60 秒容差生效）
- [ ] 在 `MainActivity` 的 `onStart` 里连续 `schedule()` 10 次，`WorkInfo` 的 `id` 与 `nextScheduleTimeMillis` **不变**（验证 `KEEP` 而非 `UPDATE`）
- [ ] 退出登录 → `getWorkInfosForUniqueWork` 返回 `CANCELLED`；重新登录 → 重新 `ENQUEUED`
- [ ] 服务端返回 500，`runAttemptCount` 涨到 4 时 Worker 返回 `success` 而不是继续 `retry`
- [ ] 构造一个永不响应的服务端，Worker 在 45 秒内返回 `retry`（不是占满 10 分钟）
- [ ] `Constraints` 里确认**没有** `requiresCharging` / `requiresDeviceIdle` / `requiresBatteryNotLow`（代码断言或 review checklist）
- [ ] 后台刷新成功与失败各一次，通知栏**均无新增通知**
- [ ] 诊断中心的后台刷新卡显示：`WorkInfo.state`、`runAttemptCount`、下次预计时刻、待机分桶中文档位、白名单状态
- [ ] `adb shell am set-standby-bucket <pkg> rare` 后，诊断卡显示「低频（可能延后约 24 小时）」
- [ ] 一台国产 ROM 真机：飞行模式 12 小时后开网，记录实际触发次数与预期次数的差距，写进 plan 作为基线（**这一条不是通过/失败，是采数**）
- [ ] 设备重启后 `WorkInfo` 仍为 `ENQUEUED`（WorkManager 自动恢复）

---

## 5.6 应用快捷方式（1 天）

### 一 · iOS 现状

对应物在 `NinebotAppIntents.swift`（422 行）。**先说清一件事：iOS 侧没有「长按图标的快捷入口」。** `Config/mini-ninebot-Info.plist` 里**没有 `UIApplicationShortcutItems`** 这个键（已确认全文无此键）。iOS 的 Home Screen Quick Actions 完全没做。

iOS 暴露给系统的入口是 **App Intents / App Shortcuts**：9 个 `AppIntent` + 一个 `AppShortcutsProvider`（`:126-258`），出现在 Siri、聚焦搜索、快捷指令 App、以及 iOS 18 的控制中心。`NinebotAppShortcutsProvider.updateAppShortcutParameters()` 在 App `init` 里调（`mini_ninebotApp.swift:18`），`shortcutTileColor = .lime`（`:127`）。

#### 9 个 Intent 全表

| # | 类型 | `title` | `openAppWhenRun` | `authenticationPolicy` | `shortTitle` | `systemImageName` | 语音短语数 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `NinebotRefreshStatusIntent`(19-28) | 刷新九号车况 | false | — | 刷新车况 | `arrow.clockwise` | 9（`:132-142`） |
| 2 | `NinebotBatteryStatusIntent`(30-39) | 查询九号电量 | false | — | 查电量 | `battery.100` | 6（`:149-156`） |
| 3 | `NinebotVehicleLocationIntent`(41-50) | 查询九号位置 | false | — | 查位置 | `location.fill` | 6（`:163-170`） |
| 4 | `NinebotRingBellIntent`(52-62) | 九号寻车铃 | false | **`.requiresAuthentication`**(`:56`) | 寻车铃 | `bell.fill` | 6（`:177-184`） |
| 5 | `NinebotOpenBucketIntent`(64-74) | 打开九号座桶 | false | **✓**(`:68`) | 开座桶 | `shippingbox.fill` | 6（`:191-198`） |
| 6 | `NinebotEngineStartIntent`(76-86) | 九号上电 | false | **✓**(`:80`) | 上电 | `power.circle.fill` | 6（`:205-212`） |
| 7 | `NinebotEngineStopIntent`(88-98) | 九号熄火 | false | **✓**(`:92`) | 熄火 | `lock.fill` | 6（`:219-226`） |
| 8 | `NinebotOpenRecordingIntent`(100-111) | 打开九号记录 | **true** | — | 开始记录 | `gauge.with.dots.needle.67percent` | 6（`:233-240`） |
| 9 | `NinebotOpenTripsIntent`(113-124) | 打开九号行程 | **true** | — | 行程 | `road.lanes` | 5（`:247-252`） |

**`title` 与 `shortTitle` 是两套文案**，都要移植：`title` 是完整名（带「九号」前缀，用在快捷指令 App 的动作列表里），`shortTitle` 是短标签（用在 Siri 建议磁贴上）。

`description`（`IntentDescription`）原文：

| # | description |
| --- | --- |
| 1 | 刷新已登录九号车辆的电量、续航和状态。 |
| 2 | 查询当前选中九号车辆的电量、预估续航和状态。 |
| 3 | 查询当前选中九号车辆的位置和最后更新时间。 |
| 4 | 通过九号接口让当前选中的车辆发出寻车提示音。 |
| 5 | 打开当前选中九号车辆的座桶。 |
| 6 | 让当前选中的九号车辆进入上电状态。 |
| 7 | 让当前选中的九号车辆进入熄火状态。 |
| 8 | 打开 NineBot+ 的记录页面，准备开始记录 GPS 速度、加速 G 值和轨迹。 |
| 9 | 打开 NineBot+ 的行程页面查看接口行程、趋势和详情。 |

返回的 dialog 文案：

| # | dialog |
| --- | --- |
| 1 | `"{车名} 车况已刷新"`，车名兜底 `"九号"`（`:272`） |
| 2 | `"{车名} 当前电量 {batteryText}，预估续航 {localEstimatedMileageText}，状态 {powerText}。"`（`:287`） |
| 3 | `"{车名} 位置：{locationText}。更新于 {HH:mm}。"`（`:314`） |
| 4 | `"{车名} 寻车铃已发送"`（`:60`） |
| 5 | `"{车名} 开座桶指令已发送"`（`:72`） |
| 6 | `"{车名} 上电指令已发送"`（`:84`） |
| 7 | `"{车名} 熄火指令已发送"`（`:96`） |
| 8 | `"已打开记录页面"`（`:109`） |
| 9 | `"已打开行程页面"`（`:122`） |

第 3 条的 `locationText` 三段兜底（`:305-313`）：已解析地址（trim 后非空）→ `"{%.6f}, {%.6f}"` 经纬度 → `"暂无位置"`。时间走 `shortcutTime`（`:415-421`）：`"HH:mm"`，`zh_CN` + `Asia/Shanghai`。

错误文案（`NinebotShortcutError`，`:5-17`）：

- `.missingConfiguration` → `"请先在 App 的“我的”页面配置数据源并登录"`（注意用的是中文全角引号 `“”`）
- `.missingVehicle` → `"没有找到可操作的车辆，请先打开 App 刷新车况"`

#### 两类 Intent 的执行路径

**A · 不开 App 的 7 个**（`openAppWhenRun = false`）走 `NinebotShortcutRunner`（`:260-422`，`@MainActor private enum`）：

| 方法 | 行号 | 编排 |
| --- | --- | --- |
| `refreshDashboard()` | `:262-277` | `client(from:)` → `fetchDashboard(selectedSN: cached?.selectedSN)` → `saveDashboardAndSync` → 记事件 → `reloadAllTimelines()` → 返回车名或 `"九号"` |
| `batteryStatus()` | `:279-295` | `refreshedDashboardIfPossible` → 拼文案 → 记事件 → `reloadAllTimelines()` |
| `locationStatus()` | `:297-322` | 同上 + 读 `store.loadResolvedAddresses()[sn]?.address` |
| `perform(_:)` | `:324-354` | `client(from:)` → `dashboardForOperation` → POST 对应端点 → `fetchDashboard(selectedSN: vehicle.sn)` → `saveDashboardAndSync` → 记事件(`operation: action.title`) → `reloadAllTimelines()` |

`dashboardForOperation`（`:364-378`）：**缓存里有 `primaryVehicle` 就直接用，零网络请求**；否则 `fetchDashboard(selectedSN: nil)` + 落盘，仍无车则抛 `.missingVehicle`。与 1.3 磁贴的编排同一套。

`saveDashboardAndSync`（`:392-396`）：`store.saveDashboard` + `NinebotChargingLiveActivityManager.sync`。

`recordShortcutEvent`（`:398-413`）：`source` 恒为 `"Shortcut"`，落 app slot。

**注意 Shortcut 路径没有 Widget 扩展那套压缩超时。** 它跑在主 App 进程里，用的是 `NinebotServerClient` 默认的 `URLSession.shared` + 20 秒（`NinebotServerClient.swift:285`），不是 Widget 的 8/12 秒（`NinebotWidgetControlIntents.swift:82-83`）。

**B · 开 App 的 2 个**（`openAppWhenRun = true`，#8 #9）走「写一个待处理路由 + 让系统打开 App」：

```swift
// :106-109（记录）/ :119-122（行程）
await MainActor.run { NinebotSharedStore().savePendingAppRoute(.recording) }   // 或 .trips
return .result(dialog: "已打开记录页面")
```

`NinebotPendingAppRoute`（`NinebotModels.swift:8-13`）有 **4 个 case**：`dashboard` / `trips` / `recording` / `settings`，**但只有 `trips` 与 `recording` 有 Intent 用到**，另两个是预留。

存取：key `ninebot.pending.app.route`（`NinebotSharedStore.swift:19`），`savePendingAppRoute`（`:71-73`）写 `rawValue`，`consumePendingAppRoute`（`:75-82`）读后**立即 `removeObject`**（一次性消费）。

消费点两处（`ContentView.swift:84-95`）：根视图 `.task`（`:66`）与 `scenePhase` → `.active`（`:73`），映射到 `selectedTab`。

### 二 · 要移植的逻辑

#### 2.1 iOS 暴露了哪些动作 —— 归成三类

| 类 | iOS Intent | 特征 |
| --- | --- | --- |
| **查询类**（3 个） | 刷新车况 / 查电量 / 查位置 | 不开 App，返回一句话结果，无鉴权 |
| **控车类**（4 个） | 寻车铃 / 开座桶 / 上电 / 熄火 | 不开 App，**全部 `.requiresAuthentication`** |
| **导航类**（2 个） | 打开记录 / 打开行程 | 开 App，跳到对应 tab |

**控车四条在 App Intents 里全部要鉴权，包括寻车铃。** 这与 Control Widget 侧不一致 —— Control Widget 的寻车铃**不要求鉴权**（`NinebotWidgetControlIntents.swift:32-41` 无 `authenticationPolicy`），且 `NinebotVehicleAction.bell` 的 `isDangerous == false`（`NinebotViewModel.swift:99-106`，Phase 1 的 1.2 §2.2 已列全表）。Phase 1 已定：**Android 以 `isDangerous` 为准，寻车铃不鉴权。**

#### 2.2 Android 快捷方式的名额

`ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)` 在 AOSP 上返回 **5**（静态 + 动态合计的上限，按 activity 计）。实际启动器长按图标菜单里通常只展示 **4 个左右**（Pixel Launcher 4 个，各家 ROM 不一，还要给「应用信息」「小组件」这些系统项留位置）。

**9 个 iOS 动作对 4 个可见名额。** 必须挑，这是产品决定，见文末 `## 待定` S3。下面给出建议方案与实现形状。

建议入选 4 个：

| 位 | 快捷方式 | 对应 iOS | 类型 | 理由 |
| --- | --- | --- | --- | --- |
| 1 | 寻车铃 | #4 `NinebotRingBellIntent` | 动态 | 最高频，且已定不鉴权，一按即响 |
| 2 | 刷新车况 | #1 `NinebotRefreshStatusIntent` | 动态 | 无副作用，配合后台刷新不可靠这一点，手动刷的入口有价值 |
| 3 | 开始记录 | #8 `NinebotOpenRecordingIntent` | **静态** | 纯导航，无运行时数据 |
| 4 | 行程 | #9 `NinebotOpenTripsIntent` | **静态** | 同上 |

不入选的 5 个及理由（供拍板时参考）：

- **上电 / 熄火 / 开座桶**：长按图标菜单没有确认环节，手指一滑就执行。1.2 给这三条配了「滑动 + BiometricPrompt」的双层保护，快捷方式绕过它与设计意图冲突。
- **查电量 / 查位置**：iOS 上它们的价值是**语音播报一句话**。Android 快捷方式点了只能打开 App 或弹 Toast，等于「打开 App 看首页」，与直接点图标无区别。

**iOS 那 56 条中文语音短语没有移植目标。** Android 的对应物是 App Actions（`shortcuts.xml` 里的 `<capability>` + `shortcuts.xml` 绑定 BII），需要接 Google Assistant、且中文支持有限，明确**不在 5.6 的 1 天工时内**。

#### 2.3 文案映射

| iOS | Android | 上限 |
| --- | --- | --- |
| `shortTitle`（刷新车况 / 寻车铃 / 开始记录 / 行程） | `setShortLabel` | 建议 ≤ 10 字符 |
| `title`（刷新九号车况 / 九号寻车铃 / 打开九号记录 / 打开九号行程） | `setLongLabel` | 建议 ≤ 25 字符 |
| `description` | 无对应物，丢弃（Android 快捷方式没有描述字段） | — |
| `systemImageName` | `setIcon(IconCompat)`，走「全程并行」那批定制图标 | — |

**短标签超长会被启动器截断，而不是缩小字号。** 上面 4 个短标签最长 4 个汉字，安全。

### 三 · Android 实现要点

#### 3.1 静态还是动态：两者都用，各管一半

| | 静态（`res/xml/shortcuts.xml`） | 动态（`ShortcutManagerCompat`） |
| --- | --- | --- |
| 生存期 | 随 APK，装上就有，卸载才没 | 代码推送，可增删改禁用 |
| 标签本地化 | `@string/` 自动跟随系统语言 | **要在 `ACTION_LOCALE_CHANGED` 时重新推送** |
| 能否带运行时数据 | 不能 | 能（车名、SN） |
| 能否条件隐藏 | 不能 | 能（`disableShortcuts` / `removeDynamicShortcuts`） |
| 排序 | XML 顺序 | `setRank`（仅动态有效，rank 小的靠前） |

**规定：导航类走静态，控车/刷新类走动态。**

导航类（记录、行程）不依赖任何运行时状态，静态最省事且永不失效：

```xml
<!-- res/xml/shortcuts.xml -->
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
    <shortcut
        android:shortcutId="open_recording"
        android:enabled="true"
        android:icon="@drawable/ic_shortcut_recording"
        android:shortcutShortLabel="@string/shortcut_recording_short"   <!-- 开始记录 -->
        android:shortcutLongLabel="@string/shortcut_recording_long">    <!-- 打开九号记录 -->
        <intent
            android:action="android.intent.action.VIEW"
            android:targetPackage="com.nineplus.android"
            android:targetClass="com.nineplus.android.MainActivity" />
        <categories android:name="android.shortcut.conversation" />
    </shortcut>
    <!-- open_trips 同构 -->
</shortcuts>
```

静态快捷方式的 `<intent>` **不能带 extra**（XML 里 `<extra>` 只支持有限类型且易错）。用 `android:action` 区分目标 —— 给两个自定义 action（`com.nineplus.android.action.OPEN_RECORDING` / `OPEN_TRIPS`），`MainActivity` 在 `onCreate` / `onNewIntent` 里读 `intent.action` 映射到 tab。

在 `MainActivity` 的 manifest 声明里挂上：

```xml
<meta-data android:name="android.app.shortcuts" android:resource="@xml/shortcuts" />
```

动态类（寻车铃、刷新车况）需要在无配置/无车辆时消失，且标签里可以带车名：

```kotlin
// app/.../shortcut/ShortcutPublisher.kt
suspend fun publish(context: Context, snapshot: DashboardSnapshot?) {
    val hasVehicle = snapshot?.primaryVehicle != null
    if (!hasVehicle) {
        // 用 disable 而不是 remove：已被用户固定（pinned）到桌面的那份会变灰并给出理由，
        // remove 只是让它变成一个点了没反应的死图标
        ShortcutManagerCompat.disableShortcuts(
            context,
            listOf(ID_BELL, ID_REFRESH),
            context.getString(R.string.shortcut_disabled_no_vehicle),  // "没有找到可操作的车辆，请先打开 App 刷新车况"
        )
        return
    }
    ShortcutManagerCompat.setDynamicShortcuts(context, listOf(
        buildShortcut(context, ID_BELL, rank = 0),
        buildShortcut(context, ID_REFRESH, rank = 1),
    ))
}
```

禁用文案直接复用 iOS 的 `NinebotShortcutError` 原文（`NinebotAppIntents.swift:12-14`）：无配置用 `"请先在 App 的“我的”页面配置数据源并登录"`，无车辆用 `"没有找到可操作的车辆，请先打开 App 刷新车况"`。

`publish` 的调用时机：

| 时机 | 原因 |
| --- | --- |
| `Application.onCreate()` | 每次冷启动重建（动态快捷方式不参与备份恢复，换机后必须重推） |
| dashboard 快照变化（Flow 收集） | 车名变了、车没了 |
| 登录 / 退出登录 | 退出登录必须清 —— **标签里可能有车名，属于用户数据** |
| `ACTION_LOCALE_CHANGED` 广播 | 动态快捷方式的标签是快照字符串，不跟随系统语言 |
| `ACTION_MY_PACKAGE_REPLACED` 广播 | 升级后动态快捷方式可能丢失 |

#### 3.2 点击后怎么执行

**导航类**：Intent 直达 `MainActivity`，`launchMode` 用清单里已有的配置，`onNewIntent` 里读 action 切 tab。

**不要照抄 iOS 的 `savePendingAppRoute` 那套存储中转。** iOS 需要它是因为 App Intent 跑在独立进程/扩展里，拿不到 App 的运行时状态，只能通过 App Group 的 `UserDefaults` 传话。Android 的快捷方式直接投递 Intent 给 Activity，用 Intent action 传就行。多一层 DataStore 中转反而引入「写了没被消费」的状态残留。

**控车/刷新类**：不能直接把 `MainActivity` 拉起来（长按图标点「寻车铃」不应该把 App 打开到首页）。用一个无界面的中转 Activity：

```xml
<activity
    android:name=".shortcut.ShortcutTrampolineActivity"
    android:exported="true"
    android:excludeFromRecents="true"
    android:taskAffinity=""
    android:noHistory="true"
    android:theme="@android:style/Theme.NoDisplay" />
```

```kotlin
class ShortcutTrampolineActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent.action
        ShortcutManagerCompat.reportShortcutUsed(this, shortcutIdFor(action))   // 影响启动器排序，别漏
        // 复用 1.3 磁贴那套 Worker，不要在这里写网络调用
        enqueueCommandWorker(action)
        finish()                            // 立刻结束，不留任何界面
        overridePendingTransition(0, 0)
    }
}
```

**必须 `exported="true"`**（快捷方式由启动器进程投递），所以要防第三方 App 伪造调用：`ShortcutTrampolineActivity` 只接受自定义 action，且在 `enqueueCommandWorker` 前不做任何鉴权豁免 —— 参见 §3.3。

**执行复用 1.3 的 `VehicleCommandRepository` 与磁贴 Worker。** 不要在快捷方式这条路上另写一份网络调用。1.3 的磁贴编排（`docs/phase1-core-spec.md` 的 1.3 §2.3）已经处理了「读配置 → 取 SN（缓存优先零请求）→ POST → 只刷选中车 → 写 DataStore → 记 `RefreshEvent(source = Tile)` → 通知栏反馈」。

一处需要改的：`RefreshEvent.source`。快捷方式不是磁贴，应该记成 `RefreshSource.Shortcut`（对齐 iOS 的 `"Shortcut"`，`NinebotAppIntents.swift:407`），落 **app slot**。1.3 的 Worker 要把 source 做成入参而不是硬编码 `Tile`。

反馈方式：iOS 的 App Intent 返回 `dialog` 由系统朗读/展示。Android 快捷方式没有返回通道，只能靠通知栏 —— 复用 1.3 的通知反馈路径，文案对齐 iOS：`"{车名} 寻车铃已发送"` / `"{车名} 车况已刷新"`。

超时用哪个 client：**用主 App 的 20 秒那个**（`@Named("app")`）。快捷方式跑在主进程的 Activity/Worker 里，没有 Widget 扩展那 12 秒的执行预算 —— 与 iOS 的 Shortcut 路径一致（走 `URLSession.shared` + 20 秒，不是 Widget 的 8/12 秒）。

#### 3.3 鉴权

已定的决策：**磁贴控车不鉴权，设备解锁即可。**

快捷方式与磁贴的处境不完全一样：

| | 快捷设置磁贴（1.3） | 应用快捷方式（5.6） |
| --- | --- | --- |
| 锁屏上能不能点 | 能（磁贴在锁屏下拉面板里）——所以 1.3 用了 `TileService.unlockAndRun` 强制先解锁 | **不能**。长按图标菜单要求设备已解锁并在启动器上 |
| 误触概率 | 中（下拉面板一屏十几个磁贴） | 中（长按图标弹出的 2-4 项，手指抬起位置决定选中哪个） |
| 是否有系统级鉴权钩子 | 有（`unlockAndRun`） | **没有**。`ShortcutManagerCompat` 没有任何鉴权入口 |

所以「与磁贴同一套口径」在技术上意味着：**快捷方式什么鉴权都不做**（因为设备已解锁是前提，而 `unlockAndRun` 那一层在这里既不存在也不需要）。

按建议入选的 4 个（寻车铃 / 刷新车况 / 记录 / 行程）来看，这个口径没有问题 —— 寻车铃已定不鉴权，刷新和两个导航都无副作用。**但如果拍板决定把上电/熄火/开座桶放进快捷方式，就必须重新讨论鉴权**（那三条在 App 内是「滑动 + BiometricPrompt」双层）。可行的折中是让快捷方式**只拉起 App 并预置好待确认动作**（`openAppWhenRun = true` 的语义），由 App 内走完整的滑动 + 鉴权 —— 这样快捷方式只是「少点两下」，不绕过任何保护。

**这一条要拍板，见文末 `## 待定` S4。**

#### 3.4 其它必须处理的

| 项 | 做法 |
| --- | --- |
| `reportShortcutUsed` | 每次执行都调（`ShortcutManagerCompat.reportShortcutUsed(context, id)`）。不调的话启动器的排序永远按 `rank`，用得最多的那个不会浮上来 |
| 图标 | 静态用 vector drawable 资源；动态用 `IconCompat.createWithResource(...)`。**不要用 `createWithBitmap`**（会被裁成圆形且不适配主题图标）。走「全程并行」那批 30-40 个定制图标 |
| 固定快捷方式（pinned） | 用户可以把快捷方式拖到桌面。拖出去的那份**独立存在**，动态列表变化不影响它，要用 `ShortcutManagerCompat.updateShortcuts` 同步标签，用 `disableShortcuts` 给禁用理由。`removeDynamicShortcuts` 不会移除 pinned 的那份 |
| 备份恢复 | 快捷方式不参与 Android 备份。换机 / 恢复出厂后动态那两个不存在，靠 `Application.onCreate` 重推 |
| 上限检查 | 推送前读 `getMaxShortcutCountPerActivity(context)`，静态 2 个 + 动态 2 个 = 4，低于 AOSP 的 5。**如果某 ROM 返回小于 4，`setDynamicShortcuts` 会抛 `IllegalArgumentException`** —— 要按返回值裁剪并 try-catch |

### 四 · 陷阱

1. **iOS 没有长按图标快捷方式，所以这一项没有「照抄」的对象。** 参照物是 9 个 App Intent 的动作集合，不是任何一份 iOS 的 UI。别去找 `UIApplicationShortcutItems`，Info.plist 里没有。

2. **`setDynamicShortcuts` 在超过上限时抛 `IllegalArgumentException`，不是静默截断。** 静态快捷方式也计入同一上限。静态 2 + 动态 3 在上限为 4 的 ROM 上直接崩。必须先读 `getMaxShortcutCountPerActivity` 再裁。

3. **静态快捷方式的 `<intent>` 带不了可靠的 extra。** 用自定义 action 区分，不要试图在 XML 里塞 `<extra>`。

4. **中转 Activity 必须 `exported="true"`，所以是攻击面。** 只认自定义 action、不接受任何来自 Intent 的参数（SN、URL 一律从本地存储读），`finish()` 之前不做任何有网络副作用的同步操作（都丢给 Worker）。

5. **`Theme.NoDisplay` 的 Activity 如果在 `onCreate` 里没 `finish()` 会崩。** 系统要求 `Theme.NoDisplay` 的 Activity 在首帧前结束。所有耗时操作必须走 `WorkManager` 或 `goAsync` 类机制，绝不能在 `onCreate` 里 `runBlocking`。

6. **动态快捷方式的标签不跟随系统语言。** 它存的是推送那一刻的字符串。必须监听 `ACTION_LOCALE_CHANGED` 重推。静态的没有这个问题。

7. **退出登录必须清动态快捷方式。** 标签里可能含车名，属于用户数据；且清完之后长按图标不会再出现一个点了报错的入口。

8. **`removeDynamicShortcuts` 不影响 pinned。** 用户拖到桌面的那份会留在桌面并变成点了没反应的死图标。要用 `disableShortcuts(ids, reason)` 给出理由文案。

9. **不要把 iOS 的 `savePendingAppRoute` 中转搬过来。** 见 §3.2。Android 用 Intent action 直传。iOS 需要那个 key 是因为进程隔离。

10. **`RefreshEvent.source` 要记 `Shortcut` 不是 `Tile`。** 1.3 的 Worker 里 source 是硬编码的，5.6 复用它时必须把 source 提成入参，否则诊断中心分不出「磁贴发的」和「快捷方式发的」—— 而这正是诊断中心存在的意义。

11. **9 个 iOS 动作里有 5 个在 Android 侧无入口。** 建议方案只放 4 个。这不是「漏了」，是名额限制下的取舍，要在 plan 里写明哪 5 个被舍弃、为什么，避免后来的人以为是遗漏又加回去把上限撑爆。

### 五 · 验收标准

- [ ] 长按桌面图标，弹出菜单里出现 4 个快捷方式，短标签为「寻车铃」「刷新车况」「开始记录」「行程」（顺序按 rank / XML 顺序）
- [ ] 点「开始记录」：App 打开并停在记录 tab；App 已在后台运行时点，切到记录 tab 而不是重建 Activity（验证 `onNewIntent` 生效）
- [ ] 点「行程」：同上，落在行程 tab
- [ ] 点「寻车铃」：**不打开任何界面**，车辆响铃，通知栏出现「{车名} 寻车铃已发送」
- [ ] 点「寻车铃」后最近任务列表里**没有**中转 Activity 的卡片（验证 `excludeFromRecents` + `noHistory`）
- [ ] 点「刷新车况」：不打开界面，刷新完成，通知栏出现「{车名} 车况已刷新」，诊断中心 app slot 记到 `source = Shortcut` 的事件
- [ ] 诊断中心能区分「磁贴发的寻车铃」（widget slot，`source = Tile`）与「快捷方式发的寻车铃」（app slot，`source = Shortcut`）
- [ ] 未配置服务器时长按图标：动态两项为禁用态，点击给出「请先在 App 的“我的”页面配置数据源并登录」；静态两项仍可用
- [ ] 已配置但无车辆时：动态两项禁用，理由文案为「没有找到可操作的车辆，请先打开 App 刷新车况」
- [ ] 退出登录后长按图标：动态两项消失，静态两项仍在
- [ ] 把「寻车铃」拖到桌面成为 pinned 快捷方式，然后退出登录：桌面那个图标变为禁用态并显示理由（不是点了无反应）
- [ ] 系统语言切英文再切回中文，四个标签都正确（静态自动、动态经 `ACTION_LOCALE_CHANGED` 重推）
- [ ] 升级安装（`ACTION_MY_PACKAGE_REPLACED`）后动态两项仍存在
- [ ] 一台把 `getMaxShortcutCountPerActivity` 返回值改小的模拟环境下，`setDynamicShortcuts` 不崩（按返回值裁剪 + try-catch）
- [ ] 用 `adb shell am start -a <自定义 action> -n <pkg>/.shortcut.ShortcutTrampolineActivity` 从外部调用：能执行（说明 exported 正常），且传入任何伪造 extra 都不影响执行的 SN（SN 只从本地读）
- [ ] 连续点 5 次「寻车铃」，服务端只收到 1 个请求（复用 1.2 的 `Mutex` 去重）

---

## 待定

以下四条是本文范围内需要人拍板的地方。都写清了现状、iOS 行为、分歧点与决定时机，实现到那一步时带上下文再定。本文的条目用 **S** 前缀独立编号（S = 系统集成），跨阶段的通用决策在 [pending-decisions.md](./pending-decisions.md) 里用 D 前缀，两套不冲突。

---

### S1 · 复制原始字段后要不要弹自己的提示

**规格现在的写法**：不弹。依赖 Android 13+ 系统自带的剪贴板确认气泡，App 侧只保留 `strings.xml` 里的文案用于 TalkBack 播报。

**iOS 的行为**：弹一个顶部胶囊 toast，文案 `"已复制原始字段"`，**1.3 秒**后消失（`NinebotSettingsView.swift:1241-1245`）。同仓另一处（2.7 的原始字段面板）是 `"已复制完整返回值"`、**1.6 秒**（`NinebotDashboardView.swift:4775-4778`）。

**分歧点**：Android 13 起系统会在屏幕底部自动弹一个剪贴板预览气泡，App 再弹一个就是两层重复反馈，Google 的平台指引也是让 App 不要重复提示。但诊断中心里另外三个动作（清除当前提示等）仍然用这个 toast，只有复制这一处不用，页面内反馈方式就不统一了。

**决定时机**：Phase 5 的 5.1，实机看过系统气泡的样子之后。

**要问的**：你在自己手机上点一下任意 App 的复制，看那个系统气泡明不明显。够明显就不弹了；如果你的 ROM 把它做得很淡甚至没有（部分国产 ROM 改过这块），那就照 iOS 弹。

---

### S2 · 后台刷新的间隔要不要在设置里说明

**规格现在的写法**：在设置页的后台刷新格里写「后台刷新 · 约 15/20/30 分钟一次」，副说明「实际间隔由系统电池策略决定，可能明显长于此值。想要即时数据请下拉刷新。」；同时在诊断中心加一张卡，摊开 `WorkInfo.state`、下次预计时刻、App Standby 分桶、电池优化白名单状态四项。

**iOS 的行为**：**什么都不说**。设置里没有任何关于后台刷新的条目，`BGTaskScheduler.submit` 失败也被静默吞掉（`NinebotBackgroundTaskManager.swift:24-26`），用户无从知道后台刷新有没有在跑。

**分歧点**：三条路。

| 方案 | 效果 |
| --- | --- |
| 照抄 iOS，一句不提 | 最省事。但 Android 上后台任务被 ROM 掐是常态，用户会以为 App 坏了 |
| 只在诊断中心摊开状态，设置页不提 | 不打扰普通用户，排查时找得到。**规格当前偏这个 + 设置页一句话** |
| 设置页展开完整说明 | 最诚实，但「实际间隔不可控」这句话读起来像在推卸责任 |

另一个附带问题：**要不要把「使用中」那一档实际会变成约 30 分钟这件事写出来？** `PeriodicWorkRequest` 的 15 分钟下限让 20 分钟档只能落到 15 的倍数（30 分钟）。写出来是三档变两档半，不写就是文案上的 20 分钟与实际的 30 分钟不符。

**决定时机**：Phase 5 的 5.4，在你自己的机器上跑一周、看过诊断中心那张卡的真实数字之后。那时候你会知道你的 ROM 到底延后多少。

---

### S3 · 4 个快捷方式名额放哪 4 个

**规格现在的写法**：寻车铃（动态）、刷新车况（动态）、开始记录（静态）、行程（静态）。

**iOS 的行为**：iOS **没有长按图标的快捷入口**（Info.plist 里没有 `UIApplicationShortcutItems`）。参照物是 9 个 App Intent：刷新车况 / 查电量 / 查位置 / 寻车铃 / 开座桶 / 上电 / 熄火 / 打开记录 / 打开行程（`NinebotAppIntents.swift:19-124`）。iOS 全放，因为 Siri 和快捷指令 App 没有名额限制。

**分歧点**：Android 上限是 5（静态+动态合计），启动器实际只显示 4 个左右。9 选 4。

被舍弃的 5 个及理由：

- **上电 / 熄火 / 开座桶**：长按菜单没有确认环节，手指抬起位置就决定了执行哪一项。1.2 特意给这三条配了「滑动 + BiometricPrompt」，快捷方式绕过去与设计意图冲突。**如果要放，见 S4。**
- **查电量 / 查位置**：iOS 上的价值是语音播报一句话。Android 快捷方式没有返回通道，点了只能打开 App 或弹通知，等于「打开 App 看首页」，与直接点图标无区别。

**决定时机**：Phase 5 的 5.6。这一项只有 1 天工时，改配置很便宜（改 `shortcuts.xml` 加改一个 list），甚至可以先按建议方案发出去，用一周之后按你实际点的频率调整。

**要问的**：你日常最想「不打开 App 就做完」的是哪两件事？如果答案里有「开座桶」，就要先定 S4。

---

### S4 · 控车类快捷方式要不要鉴权

**规格现在的写法**：按建议入选的 4 个（寻车铃 / 刷新车况 / 记录 / 行程）**都不鉴权** —— 与已定的「磁贴控车不鉴权、设备解锁即可」同一口径。这是因为长按图标菜单本身要求设备已解锁，且入选的 4 项里没有危险动作。

**iOS 的行为**：App Intents 里**控车四条全部 `.requiresAuthentication`**，包括寻车铃（`NinebotAppIntents.swift:56/68/80/92`）。但 Control Widget 侧的寻车铃**不要求鉴权**（`NinebotWidgetControlIntents.swift:32-41`），且 `NinebotVehicleAction.bell` 的 `isDangerous == false`（`NinebotViewModel.swift:99-106`）。Phase 1 已定「以 `isDangerous` 为准，寻车铃不鉴权」，三票对一票。

**分歧点**：两件事没定。

1. **「与磁贴同一套口径」在快捷方式上具体等于什么？** 磁贴那边是 `TileService.unlockAndRun`（强制先解锁再执行），因为磁贴能在锁屏下拉面板里点到。快捷方式点不到锁屏 —— 长按图标要求设备已解锁、且在启动器上。所以「设备解锁即可」在这里是自动满足的，技术上等于「什么鉴权都不做」。这个推论对不对，需要你确认这就是你的意思，而不是「快捷方式也应该有一道确认」。

2. **如果 S3 决定把上电 / 熄火 / 开座桶放进快捷方式，鉴权怎么办？** `ShortcutManagerCompat` 没有任何鉴权钩子，只有三条路：
   - 不鉴权，直接执行（与磁贴口径一致，但绕过 1.2 的双层保护）
   - 中转 Activity 弹 `BiometricPrompt`（会短暂闪出一个界面，快捷方式就不再是「不打开 App」了）
   - 快捷方式只**拉起 App 并预置待确认动作**，App 内走完整的滑动 + 鉴权（对应 iOS `openAppWhenRun = true` 的语义，快捷方式只是少点两下，不绕过任何保护）

**决定时机**：Phase 5 的 5.6，且**必须在 S3 之后**。如果 S3 只放建议的 4 个，这一条就只需要确认第 1 点（一句话）；如果 S3 要加危险动作，第 2 点必须先定，工期从 1 天变 1.5 天。
