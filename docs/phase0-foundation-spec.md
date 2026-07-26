# Phase 0 · 地基详细规格

3 周。这一阶段不产出任何用户可见功能，但后面每个 phase 都踩在它上面。

目录约定：Android 代码放 `android/`，与 `mini-ninebot/` 并列。

```
android/
  app/                          应用壳、导航、主题
  core/
    network/                    0.1
    model/                      0.2
    storage/                    0.3
    location/                   0.6
  feature/
    dashboard/  trips/  recording/  settings/
```

---

## 0.1 网络层（3 天）

### iOS 现状

`Shared/NinebotServerClient.swift`（1109 行）。一个 struct，持有 `NinebotServerConfiguration` 和 `URLSession`，所有请求走同一个私有 `request(method:path:queryItems:body:)`。

### 要移植的行为

**URL 拼接**（`buildURL`，319-337 行）：baseURL 逐个 `appendPathComponent`，query 用 `URLComponents`。baseURL 为空或无效抛 `invalidBaseURL`。

**请求头**（283-300 行）：
- `Accept: application/json` 恒定
- `bearerToken` 去空白后非空 → `Authorization: Bearer <token>`
- `appSessionToken` 去空白后非空 → `X-NinePlus-Session: <token>`
- 有 body 时加 `Content-Type: application/json`
- 超时 20 秒

**信封解包**（`unwrapEnvelope`，341-355 行）——这是最容易漏的一段：

```
响应根对象含 "ok" 键时：
  ok == true  → 返回 data 字段，data 缺失则返回空对象
  ok != true  → 抛 server 错误，消息优先级：
                error.message → error.code → "NinePlus 服务器请求失败"
不含 "ok" 键 → 原样返回整个响应
```

**HTTP 错误**（307-309 行）：非 2xx 抛 `httpStatus(code, message)`，message 取自响应体，优先级 `error.message` → `error.code` → `message` → 原始文本。

**空响应体**：返回空对象，不报错。

### Android 实现

Retrofit + OkHttp，但**不要直接用 Retrofit 的 Gson/Moshi 转换器做严格反序列化**。服务端类型不稳定：同一个字段可能返回数字、字符串或布尔，`60.5` 可能是 `"60.5"`，`true` 可能是 `1`。

对应 iOS 的 `JSONValue`，Kotlin 侧用 `JsonElement` 加一组扩展：

```kotlin
val JsonElement?.stringValue: String?   // 数字转字符串时整数不带小数点
val JsonElement?.doubleValue: Double?   // 字符串可解析则解析，布尔转 1/0
val JsonElement?.intValue: Int?         // 走 doubleValue 再取整
val JsonElement?.boolValue: Boolean?    // 1/0、"true"/"false"/"yes"/"no"/"on"/"off"
val JsonElement?.objectValue: JsonObject?
val JsonElement?.arrayValue: JsonArray?
```

强制转换规则必须跟 `NinebotModels.swift` 的 `JSONValue` 访问器逐条对齐，现有测试 `JSONValueTests.swift` 就是这套规则的可执行说明。

信封解包放 OkHttp Interceptor 或 Repository 层统一处理，别散在每个接口里。

### 端点清单

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/healthz` | 连通性测试 |
| POST | `/accounts/login` | 登录，body `{account, password}` |
| GET | `/vehicles` | 车辆列表 |
| GET | `/vehicles/{sn}/dashboard` | 聚合状态 |
| GET | `/vehicles/{sn}/status` | 状态（dashboard 缺失时的兜底） |
| GET | `/vehicles/{sn}/battery` | 电池（同上） |
| GET | `/vehicles/{sn}/travel?month=yyyyMM` | 月度行程 |
| POST | `/vehicles/{sn}/travel-sync?month=&page_size=` | 触发同步 |
| GET | `/vehicles/{sn}/travel/{id}` | 行程详情（含轨迹） |
| GET | `/vehicles/{sn}/prediction` | 预测（社区服务端不实现） |
| POST | `/vehicles/{sn}/prediction-settings` | 电池化学参数 |
| POST | `/vehicles/{sn}/bell` `/buck` `/engine/start` `/engine/stop` | 四个控制指令 |
| POST | `/devices/register` | 推送注册（Phase 1 不做，社区服务端返回兼容响应） |

### 陷阱

- `fetchDashboard` 不是单个请求，而是 `GET /vehicles` 后对每辆车再请求，且有三层兜底（见 `NinebotServerClient.swift:80-163`）。这个编排逻辑属于 Repository，不是接口定义。
- 兜底路径里 status 或 battery 为空要抛出中文错误提示，不能静默返回空数据——原代码注释明确写了「Never turn a failed request into an empty, apparently successful dashboard」。

### 验收

- 用 MockWebServer 复刻 `ServerClientTests.swift` 的 70 个用例，行为对齐
- 对着真实服务端跑通登录 + 拉取车辆列表

---

## 0.2 数据模型（3 天）

### iOS 现状

`Shared/NinebotModels.swift`（2051 行）。约 30 个 struct/enum。

### 要移植的行为

**多键名兼容**。取值函数按顺序尝试多个键名，命中即返回：

```swift
firstString(["wnumber", "sn"], in: object)
firstDouble(["dump_energy", "dumpEnergy", "electricity", "battery_percent", "batteryPercent"], ...)
```

服务端 snake_case 和 camelCase 混用，两种都要认。**直译时不要"顺手规范化"成一种**。

**数值归一化**（`NinebotServerClient.swift:665-857`）：

| 函数 | 规则 |
| --- | --- |
| `normalizedCoordinate` | 超出经纬度范围时依次除 1e6、1e7、1e5，仍超范围返回 nil |
| `normalizedBatteryVoltage` | >1000 除 1000；>120 除 10；否则原值 |
| `normalizedBatteryTemperature` | 绝对值 >120 除 10；否则原值 |

**日期解析**（`dateValue` 923-963 行）：纯数字按长度判定（14 位 `yyyyMMddHHmmss`、12 位 `yyyyMMddHHmm`、8 位 `yyyyMMdd`），可转 Double 则按 epoch 判定（>1e12 视为毫秒，>1e9 视为秒），否则依次尝试 10 种格式字符串，最后回退 ISO8601。**全部用 `Asia/Shanghai` 时区和 `en_US_POSIX` locale**。

### Android 实现

`@Serializable` data class，可选字段全部 nullable 并给默认值 null，保证旧数据能解出来。

多键名兼容不适合用 `@SerialName`（它只支持一个名字）。做法是保留原始 `JsonObject`，用取值扩展函数在映射层处理：

```kotlin
fun JsonObject.firstString(vararg keys: String): String? =
    keys.firstNotNullOfOrNull { this[it]?.stringValue?.trim()?.takeIf(String::isNotEmpty) }
```

日期统一用 `kotlinx-datetime`，固定 `Asia/Shanghai`。

### 陷阱

- `NinebotVehicleState` 有 27 个字段几乎全是可选，Kotlin 侧同样全 nullable。它的大量计算属性属于领域层，见 [domain-extraction-plan.md](./domain-extraction-plan.md)。
- `NinebotRecordedRide.pointCount` 是可选的，为了兼容轨迹拆分之前写入的记录。Room 表里也要允许为空并保留同样的兜底语义。

### 验收

移植 `ModelCodingTests.swift` 的编解码往返与向后兼容用例。

---

## 0.3 存储（2 天）

### iOS 现状

`Shared/NinebotSharedStore.swift`（约 590 行）。全部数据是 `UserDefaults(App Group)` + JSON 编码，唯一走文件系统的是车辆图片和骑行轨迹点。

### 拆分方式

| iOS | Android | 理由 |
| --- | --- | --- |
| 配置、登录态、推送 token、开关 | DataStore(Preferences) | 小、扁平、读写频繁 |
| dashboard 快照 | DataStore(Proto) 或单文件 JSON | 整体读写，不查询 |
| 车辆历史点（240 上限） | Room | 要按 SN 查、要按时间排序、要裁剪 |
| 接口行程记录（500 上限） | Room | 同上，且要按 `stableIdentityKey` 去重合并 |
| 本地骑行记录（120 上限） | Room 两张表 | 摘要与轨迹点分离，见下 |
| 车辆图片 | 文件 + Coil 磁盘缓存 | |

**App Group 在 Android 不需要**：Glance widget 与主 App 同进程，直接读同一份 DataStore/Room。

### 骑行记录的两张表

iOS 侧已经把轨迹点从 defaults 挪到独立文件（commit `6bf8930`），Android 直接用 Room 一步到位：

```
rides(id PK, vehicle_sn, associated_ride_id, started_at, ended_at,
      distance_meters, max_speed_kmh, avg_speed_kmh, max_accel_g, point_count)
ride_points(ride_id FK, seq, timestamp, lat, lon, speed_kmh, accel_g, h_accuracy)
```

列表只查 `rides`，详情才 join `ride_points`。`distance_meters` 存**重算后**的值——否则列表为了显示距离会去加载全部轨迹点，懒加载就白做了。这个坑 iOS 侧踩过，见 `NinebotRecordedRide.trackSummary()`。

### 要移植的行为

**历史点去重**（`shouldAppend`，约 520-545 行）：与上一个点的 battery / endurance / totalMileage / isCharging / isLocked / isPoweredOn 全部相同时，间隔 <60 秒跳过，间隔 <300 秒也跳过；数值有变化则立即追加。上限 240 条，超出从头部删。

**接口行程合并**：以 `stableIdentityKey` 为键，新数据覆盖旧数据，排序后取前 500。

**保留上限**：骑行记录 120 条，裁剪时必须同时删掉对应的轨迹点（外键 `ON DELETE CASCADE`）。

### 验收

移植 `SharedStoreTests.swift`（60 个用例）与 `SharedStoreTrackStorageTests.swift`（10 个用例）。

---

## 0.4 ViewModel 骨架与主题（2 天）

### 映射关系

| iOS | Android |
| --- | --- |
| `@MainActor final class NinebotViewModel: ObservableObject` | `@HiltViewModel class ... : ViewModel()` |
| `@Published var x` | `private val _x = MutableStateFlow(...)` + `val x: StateFlow<...>` |
| `await runLoadingOperation(message:)` | 统一的 `suspend fun <T> withLoading(message: String, block: ...)` |

`NinebotViewModel` 有 19 个 `@Published`。Android 侧建议合并成一个 `UiState` data class，避免 19 个独立 Flow 各自触发重组。

**注意**：iOS 版把 `isLoading` + `loadingMessage` 当状态用，界面靠**匹配中文字符串**判断当前在做什么（`NinebotDashboardView.swift:202` 的 `message.contains("刷新车况")`）。Android 侧一开始就用密封类，不要重复这个设计：

```kotlin
sealed interface LoadingKind {
    data object DashboardRefresh : LoadingKind
    data object AddressResolve : LoadingKind
    data class VehicleAction(val action: VehicleAction) : LoadingKind
    data class TravelSync(val month: String) : LoadingKind
    // ...
}
```

### 主题

`NinebotDashboardView.swift:4892-4931` 定义了 8 组明暗双色，直接搬成 Compose ColorScheme：

| token | light | dark |
| --- | --- | --- |
| teslaPageBackground | `#F1F3F5` | `#060708` |
| teslaCardBackground | `#FEFEFF` | `#131418` |
| teslaControlBackground | `#E8ECF0` | `#202226` |
| teslaPrimaryText | `#0E1014` | `#F0F2F6` |
| teslaSecondaryText | `#6B737D` | `#9EA6B0` |
| teslaGreen | `#21D147` | `#33ED61` |
| teslaActionThumb | `#0E1014` | `#21D147` |
| teslaHairline | 黑 6% | 白 10% |

（上表为源码 RGB 分量换算所得，实现时以源码数值为准。）

卡片样式统一成一个 modifier，对应 iOS 的 `NinePlusCardStyle`：圆角 24（部分处 18/22/28）、1px hairline 描边、阴影 `radius 14, y 8, 黑 5%`。

**阴影是这一项里最磨人的部分**。iOS 有 38 处带颜色和偏移的柔和阴影，Compose 的 `Modifier.shadow` 只有单一 elevation，做不出同样效果。要么用 `Modifier.drawBehind` 手绘，要么接受视觉差异。建议先用统一的 elevation 近似，Phase 5 收尾时再逐个调校。

### 验收

跑通一个空壳四 Tab 应用，明暗主题切换正确，卡片样式与 iOS 截图并排比对无明显偏差。

---

## 0.5 登录与服务器配置（2 天）

### 完整链路

服务端用社区适配器，凭据分两套，**别搞混**：

1. 后台 `http://IP:19009/admin` 用 `NINEPLUS_ADMIN_PASSWORD` 登录
2. 后台里新建一个 **NineBot+ 账号**（自定义，服务端存 PBKDF2 哈希）
3. 给它绑定**九号出行账号**（手机号 + 密码，仅用于换取令牌，不落盘）
4. App 里填四项：服务器地址、Bearer Token、NineBot+ 账号、NineBot+ 密码

App 全程不接触九号账号。iOS 版那个输入框标签写的是「手机号」（`NinebotInputError.missingAccount` 提示「请填写手机号」），实际填的是自建账号标识，Android 侧建议改成「账号」。

### 要移植的行为

- `POST /accounts/login` 返回 `session_token`（也认 `sessionToken`），存起来，后续所有请求带 `X-NinePlus-Session`
- 登录成功后立即拉一次 dashboard
- `hasLoginAccount` 判定：phone 和 sessionToken 都非空
- 服务器地址允许不带 scheme，缺失时补 `http://`（见 `NinebotServerConfiguration.baseURL`）

### 明文传输

服务端上 HTTPS 之前，Bearer Token 和密码是明文过公网的。iOS 靠 `NSAllowsArbitraryLoads` 放行，Android 需要 `network_security_config.xml`：

```xml
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">你的服务器域名或IP</domain>
    </domain-config>
</network-security-config>
```

只对自己的服务端放行明文，其余保持禁止。服务端上了 HTTPS 之后把这段删掉。

**凭据存储**：明文存 DataStore，与 iOS 保持一致（已确认为可接受的取舍，个人自建单用户场景）。

### 验收

冷启动 → 填配置 → 登录 → 看到车辆列表；杀进程重启后仍是登录态。

---

## 0.6 定位与前台服务基础设施（3 天）

放进地基是因为 4.2 骑行记录、5.4 后台刷新、5.5 充电实时活动都要用同一套。

### 权限

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

minSdk 33，所以 `POST_NOTIFICATIONS` 是运行时权限，必须显式申请。

**分步申请**，不要一次全要：先 `ACCESS_FINE_LOCATION`（进记录页时），用户同意后再在开始记录时申请 `ACCESS_BACKGROUND_LOCATION`。Android 11+ 后台定位必须单独申请，且系统会跳设置页而不是弹框。

### 前台服务

```xml
<service
    android:name=".core.location.RideRecordingService"
    android:foregroundServiceType="location"
    android:exported="false" />
```

对应 iOS 的 `UIBackgroundModes: location` + `allowsBackgroundLocationUpdates`（iOS 侧已实现，commit `0abd9c4`）。

要点：
- 只在记录期间启动，停止记录立即 `stopSelf()`。iOS 侧同样只在记录期间开后台定位，避免蓝条常驻和耗电
- 通知渠道单独一个，重要性 `IMPORTANCE_LOW`，避免响铃
- 通知内容显示已记录时长和距离，点击回到记录页

### 国产 ROM 保活

WorkManager 和前台服务在小米/华为/OPPO 上会被后台管控掐掉。需要一个引导页，检测并引导用户开启：

- `PowerManager.isIgnoringBatteryOptimizations()` → 请求加入白名单
- 厂商自启动管理页面（各家 Intent 不同，需要按 `Build.MANUFACTURER` 分支，且这些 Intent 不保证长期有效，要 try-catch 兜底到应用详情页）

在设置里放一个「后台刷新不工作？」的排查入口，对应 iOS 诊断中心的定位。

### 定位配置对齐

iOS 侧的 `CLLocationManager` 配置（`mini-ninebot/mini-ninebot/Domain/NinebotRideRecorder.swift:68-71`）：

| iOS | Android `LocationRequest` |
| --- | --- |
| `kCLLocationAccuracyBestForNavigation` | `PRIORITY_HIGH_ACCURACY` |
| `activityType = .automotiveNavigation` | 无对应，忽略 |
| `distanceFilter = 1` | `setMinUpdateDistanceMeters(1f)` |
| `pausesLocationUpdatesAutomatically = false` | 默认不暂停，无需设置 |

**定位 SDK 已定（D8）：高德定位优先，回退 Google `FusedLocationProviderClient`。**
`FusedLocationProviderClient` 依赖 Google Play 服务，无 GMS 的设备上不可用；高德定位 SDK 不依赖 GMS 且直接返回 GCJ-02，能省掉坐标转换。

**遗留一条**：两个都拿不到定位时垫不垫原生 `LocationManager`，见 `phase4-sensors-spec.md` 的 P2，本节 0.6 实测后定。

高德 SDK 没有 `speedAccuracy`，而 iOS 的速度来源判定第一条分支就是看它 —— 走高德路径时速度会全程由位移反推。细节在 `phase4-sensors-spec.md`。

### 验收

- 记录期间锁屏 10 分钟，轨迹点连续无断档
- 前台服务通知正常显示并可点击返回
- 在一台国产 ROM 机器上验证引导页能跳到正确的设置项
