# NineBot+ 安卓移植规划

配套文档：[安卓移植可行性评估](./android-portability-assessment.md)

分三期。Phase 1 是能日常用的完整客户端，Phase 2 补厂商级系统集成（超级岛等），Phase 3 打磨与扩面。

---

## Phase 0：前置准备

### 0.1 iOS 侧领域层抽取（3–5 天）

移植前先把业务逻辑从 View 里拆出来，两端共享同一份规格：

- `TripTrendAnalysis`（`NinebotDashboardView.swift:3159-3271`）——含硬编码中文规则引擎和 1.8x / 12Wh / 35Wh-km / 5 样本这些业务阈值
- 32 个 top-level `private func` 格式化与状态映射函数
- `NinebotRideRecorder`（`NinebotRecordingView.swift:129-645`）——517 行传感器采集，本身是干净的 `ObservableObject`，只是放错了文件
- Model 层的 `...Text` 孪生属性拆成 `(value, unit, source)`，展示格式化交给各端
- 消除 `message.contains("刷新车况")`（`NinebotDashboardView.swift:202`）这类用中文文案驱动 UI 状态的写法

### 0.2 服务端准备

见下面「服务端部署」一节。Phase 1 开工前必须确定部署位置和推送通道，因为这两件事互相牵制。

### 0.3 技术选型基线

| 项 | 选择 | 理由 |
| --- | --- | --- |
| UI | Jetpack Compose + Material 3 | 与 SwiftUI 声明式模型同构，迁移成本最低 |
| minSdk | 33（Android 13） | iOS 侧部署目标已是 26.5，Android 同样可以激进；33 起 `POST_NOTIFICATIONS` 是运行时权限，省掉旧分支 |
| targetSdk | 最新稳定版 | |
| 网络 | Retrofit + OkHttp + kotlinx.serialization | 对应 URLSession + Codable |
| 存储 | DataStore（配置/状态）+ Room（轨迹） | 见 1.3 |
| 地图 | 高德或腾讯 | Google Maps 国内不可用 |
| 后台 | WorkManager | 对应 BGTaskScheduler |
| Widget | Glance | 对应 WidgetKit |
| 依赖注入 | Hilt | |

---

## Phase 1：Android 基础版

目标：车控、行程、记录、设置四个 Tab 全部可用，Widget 和快捷磁贴可用，推送可用。

### 1.1 数据层（1–2 周）

近乎机械直译，风险最低，先做以打通链路：

| iOS | Android |
| --- | --- |
| `NinebotServerClient`（1109 行） | Retrofit interface + Repository |
| `NinebotModels` 数据结构（2051 行） | `@Serializable` data class |
| `NinebotSharedStore`（493 行） | DataStore + Room |
| `NinebotViewModel`（750 行） | Kotlin ViewModel + StateFlow |
| `NinebotCoordinateTransform`（57 行） | 原样搬（纯数学） |

两个要留意的地方：

- **`JSONValue`**：服务端类型不稳定（数字可能是字符串、布尔可能是 0/1），iOS 用了一个自定义 enum 兜底。Kotlin 侧用 `JsonElement` + 一组扩展函数复刻这套强制转换，不要指望严格反序列化能直接吃下去。
- **多键名兼容**：`firstString(["wnumber", "sn"], ...)` 这类同时认 snake_case 和 camelCase 的取值逻辑遍布全文件，直译时不要"顺手规范化"，服务端两种都会返回。

### 1.2 UI 层（5–7 周，可多人并行）

约 127 个自定义组件。按 Tab 切分并行：

| 模块 | 组件数 | 备注 |
| --- | --- | --- |
| 车控 Dashboard | ~84 | 工作量主体，含滑动确认控件、手写下拉刷新、电池历史折线图 |
| 设置 / 登录 / 诊断 | ~25 | 结构清晰，卡片式，最好上手 |
| 骑行记录 | ~18 | 含环形速度表 |

要点：

- **设计 token 直接搬**：`NinebotDashboardView.swift:4892-4931` 的 8 组明暗双色 RGB 字面量，直接写成 Compose 的 light/dark ColorScheme。
- **图表可直译**：折线图和环形表都是手写 `Path` / `.trim()`，对应 Compose 的 `drawPath` / `drawArc`，逻辑几乎一致。
- **阴影要重做**：38 处带颜色和偏移的柔和阴影，Compose 的 `shadow` 只有单一 elevation，需要 `Modifier.drawBehind` 手绘。看着小，实际磨人。
- **毛玻璃**：2 处 `ultraThinMaterial`，用 `RenderEffect.createBlurEffect`（API 31+）。
- **下拉刷新**：iOS 是 6 个 `@State` 组成的手写状态机，不是 `.refreshable`。Compose 侧用 `nestedScroll` 重写。
- **图标**：85 个唯一 SF Symbol、299 处调用，其中约 30–40 个（`scooter`、`gauge.with.dots.needle.67percent`、`bolt.batteryblock.fill`、`road.lanes` 等）Material Symbols 里没有，需要设计师定制。这条要尽早启动，是并行关键路径。
- **文案**：886 行硬编码中文搬进 `strings.xml`。**不能全局替换**——有的中文是逻辑标识不是 UI 文案（见 0.1）。

### 1.3 轨迹存储用 Room（含在数据层工时内）

iOS 侧当前把全部轨迹点 JSON 塞进 UserDefaults，长途骑行会产生数 MB 的 plist。已在 iOS 侧改成「摘要存 UserDefaults + 每条骑行一个轨迹文件」缓解，Android 侧建议直接上 Room 一步到位：

```
rides        (id, vehicle_sn, associated_ride_id, started_at, ended_at,
              distance_meters, max_speed_kmh, avg_speed_kmh, max_accel_g, point_count)
ride_points  (ride_id FK, seq, timestamp, lat, lon, speed_kmh, accel_g, h_accuracy)
```

列表查 `rides` 即可，详情才 join `ride_points`。距离字段存重算后的值，避免列表页为了显示距离去加载全部轨迹点。

### 1.4 传感器与骑行记录（2 周，含真机路测）

**这是唯一无法靠翻译代码解决的部分。**

`NinebotRideRecorder` 的 13 个 GPS 阈值、一阶低通滤波（系数 0.18）、速率限制（0.08）、死区（0.025）、20 Hz 采样，全是针对 iPhone 调出来的。Apple 的 `CMDeviceMotion.userAcceleration` 是免费的融合结果（已去重力、已做 AHRS），Android 的 `TYPE_LINEAR_ACCELERATION` 是虚拟传感器，各厂商质量参差，采样率只是 hint。

做法：先直译逻辑结构，再在真机上骑行采样、对比 iPhone 基线、重调参数。至少覆盖两个不同厂商的机型。

好消息是 iOS 侧记录是**纯前台**的（没申请后台定位），所以 Phase 1 不需要处理 `ACCESS_BACKGROUND_LOCATION` 和它的商店审核。如果想顺手修掉这个缺陷，Android 加前台服务比 iOS 顺，但会引入新的权限引导工作。

### 1.5 地图（1 周）

4 处地图：车辆位置、位置预览小图、两个轨迹回放。换高德或腾讯 SDK。

**坐标系**：`NinebotCoordinateTransform` 做的是 WGS-84 → GCJ-02。高德和腾讯的底图同样是 GCJ-02，所以**这段代码原样保留**，不要删也不要反向改写。

**一个待验证的疑点**：`NinebotDashboardView.swift:1243` 对系统定位返回的坐标又做了一次 GCJ-02 转换。iOS 在中国大陆返回的定位本身可能已是偏移后的坐标，若是，这里存在双重偏移（约 500m）。Android 的 `FusedLocationProvider` 返回 WGS-84，需要转一次。两端行为不同，**不要照抄，实测确认**。

### 1.6 系统集成（1.5 周）

| iOS | Android | 说明 |
| --- | --- | --- |
| Control Widget ×5 | Quick Settings Tile ×5 | 概念一一对应，性价比最高，优先做 |
| Home Screen Widget（小/中/大） | Glance | 交互按钮 `Button(intent:)` → `actionRunCallback` |
| APNs | 厂商推送（见下）| |
| BGTaskScheduler | WorkManager | 自适应间隔（充电 15 / 使用中 20 / 空闲 30 分钟）直接搬 |
| 防截屏（局部遮蔽） | `FLAG_SECURE` | 一行代码，但是整窗级；局部遮蔽需产品重新定义粒度 |
| App Intents 危险操作需 Face ID | `BiometricPrompt` | 开锁、开座桶、上电、熄火四个操作 |
| Siri 语音短语 ×57 | 降级 | 保留 `ShortcutManager` 动态快捷方式，语音入口放弃 |
| Lock Screen Widget ×3 | 降级为常驻通知 | Android 手机不支持锁屏 widget |

**国产 ROM 保活**：WorkManager 在小米/华为/OPPO 上会被后台管控掐掉。需要加电池优化白名单引导页，并在设置里提供「后台刷新不工作？」的排查入口。

### 1.7 推送通道选型

**自用单用户场景，最省事的答案是：先不做推送。**

推送解决的是「App 完全没运行时也能即时收到变化」。但这个 App 的数据源本来就是自建服务端的轮询结果，客户端并不需要毫秒级即时性：

- 常规刷新 → WorkManager 定时拉，间隔沿用 iOS 那套自适应策略（充电 15 / 使用中 20 / 空闲 30 分钟）
- 充电中的实时活动 → 充电时起一个前台服务，自己每分钟拉一次并更新通知，岛就随之更新。**本地通知足以驱动 `ProgressStyle` 和 `miui.focus.param`**，不需要任何推送通道

这样 Phase 1 完全不碰推送，省掉厂商 SDK 对接、资质申请、服务端多通道适配三件事。代价是 App 被系统杀死后不会被唤醒——对自用来说通常可以接受，真需要时再补。

如果之后确实要推送，按这个顺序考虑：

1. **厂商推送**（小米 MiPush / 华为 HMS / OPPO）—— 服务端可留国内，且 MiPush 顺带打通超级岛的服务端下发路径
2. **Google FCM** —— 需要能连 `fcm.googleapis.com`。若主服务端在国内，可以让它把推送请求转发给一台海外小机器代发，主链路（轮询九号云、存数据、APNs）仍留国内，两边各自走最优网络

---

## 服务端部署

> 服务端（NinePlus Platform）**不在本仓库内**。`.gitignore` 排除了 `platform/` 和 `ninecli-source/` 两个本地目录，而全部 16 次提交、三个分支的历史里从未出现过服务端代码 —— 它只存在于作者本地。以下按客户端观察到的契约推断需求。

### 从客户端契约推断的服务端职责

- 常驻轮询九号云 API，缓存车辆状态（客户端错误提示里有「请在管理端检查该车辆最近一次轮询」）
- 存历史数据、行程记录，按月同步（`/vehicles/{sn}/travel-sync?month=`）
- 跑续航与充电预测模型（`/vehicles/{sn}/prediction`，返回 `model_version`、`sample_count`、`confidence_percent`）
- 签发 App 会话（`/accounts/login` → `X-NinePlus-Session`）
- 推送：设备注册（`/devices/register`）、Live Activity token 注册（`/live-activities/register`），并直接下发 APNs payload
- 有管理端
- 默认端口 19009，有 `/healthz`

### 资源需求（个人自用规模）

轮询几台车、单用户，压力极小。**1 核 1G 就够**，瓶颈在常驻可用性而不是算力。数据库用 SQLite 或 PostgreSQL 均可；预测模型是轻量统计回归（从 `km_per_percent`、`fast_minutes_per_percent` 这些字段看），不需要 GPU。

已有的腾讯云 **2C4G / 60GB SSD / 6Mbps / 500GB 月流量** 绰绰有余：

| 资源 | 估算用量 | 结论 |
| --- | --- | --- |
| CPU / 内存 | Node 或 Python 常驻进程 + 轻量数据库，几百 MB | 富余一个数量级 |
| 磁盘 | 状态快照 + 行程历史，按几台车几年算也只有数百 MB | 富余 |
| 带宽 | 轮询与推送都是 KB 级小请求，峰值远不到 1 Mbps | 富余 |
| 流量 | 每分钟轮询一次 × 5KB ≈ 216 MB/月，加 App 请求撑死几 GB | 用不到 5% |

唯一需要留意的是 6 Mbps 是**峰值带宽**，如果以后往同一台机器上塞别的服务再评估。

### 网络可达性——这是选型的决定因素

| 服务端位置 | 九号云 API | APNs | Google FCM | MiPush / HMS |
| --- | --- | --- | --- | --- |
| 国内 VPS | ✅ 快 | ✅ 通 | ❌ 不通 | ✅ 快 |
| 家用宽带 + 内网穿透 | ✅ 快 | ✅ 通 | ❌ 不通 | ✅ 快 |
| 海外 VPS | ⚠️ 慢/不稳 | ✅ 通 | ✅ 通 | ⚠️ 慢 |

**结论：国内部署 + 厂商推送通道是唯一自洽的组合。** 只要不用 Google FCM，国内部署没有短板；而一旦选了 FCM，服务端就得出海或加代理，同时轮询九号云会变慢变不稳。这也是 1.7 建议放弃 FCM 的根本原因。

### 部署方案对比

| 方案 | 月成本 | 优点 | 缺点 | 适合 |
| --- | --- | --- | --- | --- |
| **国内轻量云**（阿里云/腾讯云轻量应用服务器 2核2G） | ¥24–40 | 公网 IP、稳定、备案后可上域名+证书 | 需实名，域名要备案 | **推荐** |
| **家用 NAS / 软路由 + 内网穿透**（frp / Tailscale / Cloudflare Tunnel） | ¥0 | 零成本、数据完全自持 | 家宽上行不稳、断电断网即挂、动态 IP | 已有 NAS 且能接受偶发不可用 |
| **国内 VPS + Docker Compose** | ¥30+ | 部署可复现、易迁移 | 同轻量云 | 有运维习惯 |
| 海外 VPS | $5+ | 免备案、FCM 可达 | 轮询九号云慢且不稳 | 只有在必须用 FCM 时才考虑 |

### 部署要点

- **HTTPS**：客户端 Info.plist 开了 `NSAllowsArbitraryLoads`，说明目前可能跑在 HTTP 或自签证书上。Android 侧同样要配 `network_security_config.xml` 才能连。**建议直接上 Let's Encrypt + 域名**，两端都省掉降级配置，也避免 Bearer Token 明文过网。
- **APNs 密钥**：服务端需要 `.p8` 密钥文件，注意区分 development / production 环境（客户端会运行时探测 `aps-environment` 并上报）。
- **不要暴露管理端到公网**，或至少加独立鉴权。
- **备份**：历史数据和行程记录是长期积累的，配置定期备份。
- **监控**：`/healthz` 接了就用上，配个简单的掉线告警。

---

## Phase 2：小米超级岛与厂商系统集成

### 2.1 小米超级岛调研结论

HyperOS 2 提供**焦点通知**，HyperOS 3 在其之上提供**超级岛**（灵动岛形态）。两者模板不同，岛只在 OS3 上有。

**实现方式有两条路，本地通知也能触发**（不强制走服务端推送）：

```kotlin
val notification = Notification.Builder(context, channelId)
    .setContentTitle(title)
    .setContentText(text)
    .setSmallIcon(iconRes)
    .build()

val islandParams = """{ "param_v2": { ... } }"""
notification.extras.putString("miui.focus.param", islandParams)

notificationManager.notify(id, notification)
```

- 岛数据是挂在原生 Notification 上的 JSON，根节点 `param_v2`，包含交互能力、大岛内容、小岛内容、通知内容四部分
- `miui.focus.param` **不超过 3072 字节**
- 图片走 `miui.focus.pic_*` key，值是 HTTPS URL，单张 ≤100KB，宽高比 1:1 到 16:9 之间，单条通知最多 10 张，图片参数整体 ≤1024 字节
- 锁屏展示用 `aodTitle` / `aodPic`，状态栏用 `ticker` / `tickerPic`
- 另一条路是走 **MiPush** 服务端下发，适合 App 未运行时拉起（对应 iOS 的 push-to-start）

**权限**：需要向小米申请焦点通知资质，发邮件到 `mipush-permission@xiaomi.com`。这是**卡工期的外部依赖，要最先启动**。

**可用轮子**：开源 Kotlin DSL 库 [HyperIsland-ToolKit](https://github.com/D4vidDf/HyperIsland-ToolKit)，封装了 20+ 模板（含进度条、计时器），自动处理 `miui.focus.pic_` 这类系统前缀，可以省掉手拼 JSON。

### 2.2 充电场景映射

iOS Live Activity 的 `ContentState` 有 8 个字段：`battery`、`estimatedRange`、`estimatedFullAt`、`chargingPower`、`batteryTemperature`、`batteryVoltage`、`chargingSpeed`、`updatedAt`。

小米超级岛用进度条模板承载：

| 位置 | 内容 |
| --- | --- |
| 小岛（收起态） | 闪电图标 + 电量百分比 |
| 大岛（展开态） | 进度条 + 剩余时间 + 充电功率 |
| 锁屏 / AOD | 电量、续航、预计充满时刻 |
| 状态栏 ticker | 电量百分比 |

服务端下发逻辑可以直接复用现有的 Live Activity 那套——判断条件相同（`isCharging && !isFullyCharged && battery != nil`），只是 payload 格式不同。iOS 侧已有的 token 管理、staleDate 策略、单车约束都可以照搬思路。

### 2.3 覆盖面 —— 标准 API 比想象中管用

先做 **Android 16 `Notification.ProgressStyle`（Live Updates）**，这不只是保底：

| 厂商 | 对应能力 | 标准 API 是否够用 |
| --- | --- | --- |
| OPPO ColorOS 16 | 流体云 | ✅ **够**。ColorOS 16 的流体云已对接 Android 16 Live Updates，遵循 Google 实时活动规范的应用可直接适配，**无需单独接 OPPO** |
| 小米 HyperOS 3 | 超级岛 | ⚠️ 待实测。HyperOS 3 基于 Android 16，标准 API 本身可用，但小米主推私有的 `miui.focus.param`，是否自动映射到超级岛官方没说明 |
| 华为 HarmonyOS | 实况窗 | ❌ 需单独接，接口不同 |
| vivo OriginOS | 原子岛 | ❔ 未查证 |
| 其余机型 | 标准通知 | ✅ 至少是常驻进度通知 |

所以顺序是：**先做 `ProgressStyle`，实测各机型效果，再决定要不要为小米单独写 `miui.focus.param` 分支**。OPPO 基本可以不用管。

### 2.4 关于小米权限：两条路径要分清

- **MiPush 服务端下发焦点通知** —— 确定需要向小米申请资质（邮件 `mipush-permission@xiaomi.com`），要提交通知触发场景截图、焦点通知设计效果图、交互设计、使用期限和使用声明。面向正式产品，自用未上架的应用大概率走不通。
- **本地通知 + `miui.focus.param`** —— App 进程活跃时按原生方式发通知并写入 extras 即可，不经过小米服务器。社区实践显示可以自测生效，但系统里存在一个 `hasFocusPermission()` 查询接口，说明确实有权限位；它究竟是用户可开的开关还是小米下发的应用白名单，公开文档没讲清楚。

**自用场景的正确做法是先实测**：写个二十行的 demo，发一条带 `miui.focus.param` 的本地通知，在自己的机器上看岛出不出来。这比任何调研都准，成本也低。

### 2.4 前台服务约束

充电通知需要常驻，注意 Android 15+ 对前台服务的限制：`FOREGROUND_SERVICE_DATA_SYNC` 每日有 6 小时配额。充电过程通常 2–4 小时，在配额内，但要处理超时降级。

**工时估算**：保底 ProgressStyle 1 周 + 小米超级岛 1.5 周 + 权限申请等待（不占开发工时但卡上线）。

---

## Phase 3：打磨与扩面

- 锁屏 Widget 的降级方案（常驻通知）落地
- 华为 / OPPO / vivo 实时活动（按用户分布决定）
- 平板适配（iOS 侧 `TARGETED_DEVICE_FAMILY = "1,2"` 已含 iPad）
- Wear OS 表盘复杂功能（iOS 侧没有，属于新增）
- 后台定位与真正的全程记录（修掉 iOS 侧的前台限制）
- 出海准备：中文文案比英文短 40–50%，现有卡片布局全按中文宽度调过（大量 `minimumScaleFactor(0.62~0.76)`），要出海得重做布局

---

## 工时汇总

| 阶段 | 内容 | 工时 |
| --- | --- | --- |
| Phase 0 | 领域层抽取 + 服务端准备 | 1 周 |
| Phase 1 | 数据层 | 1–2 周 |
| | UI 层（可并行） | 5–7 周 |
| | 传感器 + 真机调参 | 2 周 |
| | 地图 | 1 周 |
| | 系统集成（Widget / Tile / 推送 / 后台） | 1.5 周 |
| | 联调测试 | 2 周 |
| Phase 2 | ProgressStyle 保底 + 小米超级岛 | 2.5 周 |
| 并行 | 图标设计（30–40 个） | 1 周 |

单人全职约 4–5 个月，两人约 2.5–3 个月。图标设计和小米权限申请要最先启动，它们在关键路径上。

---

## 待确认

1. 服务端技术栈和当前部署方式——影响部署选型的具体建议
2. 是否接受 Phase 1 放弃 Google FCM、改走厂商推送
3. 目标机型分布——决定 Phase 2 除小米外还要接哪些厂商
4. 是否出海——影响是否现在就为多语言布局留口子
