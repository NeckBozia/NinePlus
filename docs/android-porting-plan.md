# 服务端与厂商能力调研

> **这份文档的定位变了。** 它原先是一份按 Phase 1/2/3 划分的移植规划，现在那部分已经被 [android-implementation-plan.md](./android-implementation-plan.md)（Phase 0–5）和八份逐项规格取代。留下来的是它真正独有的内容：**服务端到底是什么、部署在哪、厂商灵动岛怎么做**。
>
> | 要找什么 | 去哪 |
> | --- | --- |
> | 阶段划分、工作分解、工时、里程碑 | [android-implementation-plan.md](./android-implementation-plan.md) |
> | 逐项实现规格 | `phase0-foundation-spec.md` … `phase5-system-spec.md` 共八份 |
> | 能不能移植、难在哪 | [android-portability-assessment.md](./android-portability-assessment.md) |
> | 待拍板的 85 条 | [pending-decisions.md](./pending-decisions.md) |
> | 服务端接口逐条核对 | [community-server-api-check.md](./community-server-api-check.md) |

---

## 一 · 服务端：为什么必须有

### 客户端从来没有直连九号的能力

`main` 分支的 `README.md` 里有一行分支说明：

> `main` is server-only and no longer includes the dual-mode connection path. Use the `nine-proxy` branch when dual-mode support is required.

查过 `origin/nine-proxy` 分支后确认：**它的「双模式」不是「服务端 vs 官方直连」，而是两种自建服务端。** 两边都是用户自己填的 `baseURLString`，全分支搜不到任何九号的域名。

真正懂九号官方协议的是 **`ninecli`**：

- PyPI 上的包（`ninecli==0.1.7`），但装进去的是一个 **8.9 MB 的 Go 编译二进制**
- 元数据写着 MIT 许可，**但没有提供任何源码仓库链接**
- 登录、请求签名、token 刷新、端点路径 —— 全在那个二进制里
- 多平台 wheel：linux / macOS / Windows / musllinux。**没有 Android**，也没有源码可以交叉编译

而且整个生态都在包它，没有第二份实现：

| 项目 | 怎么访问九号 |
| --- | --- |
| 社区适配器 `wuchiawuchi/nineplus-ha-server` | `python -m ninecli --config <dir> <子命令> --json`，subprocess |
| Home Assistant 集成 `hasscc/ninebot` | `manifest.json` 写着 `"requirements": ["ninecli==0.1.7"]`，`api.py` 里的类就叫 `NinebotCliClient`，注释「Async subprocess client for the ninecli package」 |

**所以 Android 直连九号 = 逆向那个 Go 二进制或抓官方 App 的包，把协议在 Kotlin 里重写一遍。** 服务端是必须的。

### 关于封号风险，说清楚

**服务端这条路和直连的封号风险基本相同** —— 都是用你自己的九号账号、以非官方客户端的身份访问九号云。差别不在「有没有风险」，而在：

- `ninecli` 是已经有人在用的实现（这个适配器 + Home Assistant 集成），说明它模仿得足够像、今天能跑通
- 自己重写容易在细节上露馅（User-Agent、签名、请求节奏），更显眼
- 服务端按固定节奏轮询，比手机 App 的请求模式更规律

所以「直连风险更大」这个说法只在「自己重写的实现更容易被识别」这个意义上成立，**不是说走服务端就安全**。真正劝退直连的理由只有一个：**协议是闭源的，得先逆向**。

### 三种服务端形态

| 形态 | 是什么 | 默认端口 | 客户端用哪个模式 | 拿得到吗 |
| --- | --- | --- | --- | --- |
| **NinePlus Platform** | 原作者自己的服务端。多账号、APNs、轮询策略、预测模型、管理后台 | 19009 | 平台模式 | **拿不到**，从未公开 |
| **`ninecli serve`** | ninecli 自带的 REST 服务，官方描述是「把加密的九号 API 暴露成明文 REST」。单账号，可选 bearer token | 127.0.0.1:**18009** | 代理模式 | **能用，但没源码**（就是那个闭源二进制的一个子命令） |
| **社区适配器** | `wuchiawuchi/nineplus-ha-server`，Python，照着客户端调用行为反向对齐 | 19009 | **平台模式** | **能，已定 fork 自己改** |

### 客户端的两种模式（只在 `nine-proxy` 分支上）

`nine-proxy` 分支的设置页有个「代理模式」开关（`NinebotSettingsView.swift:51`），两种模式走不同的登录端点：

| | 平台模式 | 代理模式 |
| --- | --- | --- |
| 登录端点 | `POST /accounts/login`、`/accounts/login-code` | `POST /auth/login`、`/auth/login-code`、`/auth/refresh` |
| 界面上的说明 | 「多账号、APNs 和轮询策略在 NinePlus Platform 后台管理」 | 「单账号直连，适合调试」「会直接登录当前 `ninecli serve`，会替换代理上的单账号会话」 |
| 对应的服务端 | NinePlus Platform 或社区适配器 | `ninecli serve` |

`main` 分支砍掉了代理模式，只保留 `/accounts/login`。**社区适配器只实现了 `/accounts/login`，没有任何 `/auth/*` 路由** —— 所以它是**平台模式**的替代品，正好对上 `main`。

曾经考虑过一条更省事的路子：自用单账号的话，`ninecli serve` 本身就是能跑的服务端，不需要社区适配器那一层。**已放弃**（D12）—— 要给两位朋友用，而 `ninecli serve` 是单账号的，登录会替换掉上一个人的会话。分析过程留在 D12 里，将来若变成单人可以翻出来。

### 从客户端契约推断的 Platform 职责

- 常驻轮询九号云 API，缓存车辆状态（客户端错误提示里有「请在管理端检查该车辆最近一次轮询」）
- 存历史数据、行程记录，按月同步（`/vehicles/{sn}/travel-sync?month=`）
- 跑续航与充电预测模型（`/vehicles/{sn}/prediction`，返回 `model_version`、`sample_count`、`confidence_percent`）
- 签发 App 会话（`/accounts/login` → `X-NinePlus-Session`）
- 推送：设备注册（`/devices/register`）、Live Activity token 注册（`/live-activities/register`），并直接下发 APNs payload
- 有管理端
- 默认端口 19009，有 `/healthz`

### 社区适配器：缺什么、坏在哪

它不是碰巧兼容，是专门为这个 App 写的：README 开篇即写「为 NineBot+ iOS 客户端提供九号云端 API」并附 iPhone 端填写说明；对 `/devices/register` 返回**兼容响应**（自己并不发 APNs）；端口默认 19009 与 App 设置页占位符一致。

时间线也印证来历：上游仓库 7 月 12 日同时出现两个 issue（[#1](https://github.com/JieFuHe/NinePlus/issues/1) 英文、[#2](https://github.com/JieFuHe/NinePlus/issues/2) 中文）都在问「怎么搭建 NinePlus 平台服务器」且无人给出官方答案，9 天后（7 月 21 日）这个适配器出现。

17 个端点逐条核对的结果在 [community-server-api-check.md](./community-server-api-check.md)。摘要：**路径零差异**（Retrofit 接口可直接照 iOS 写），但

| 结论 | 数量 |
| --- | --- |
| 一致 | 7 |
| 字段缺失（功能降级） | 3 |
| 完全缺失（功能不可用） | 4 —— `/prediction`、`/travel-sync`、`/devices/register`、`/live-activities/register` |
| 需实测 | 3 |

**已定 fork 过来自己改**，不提 PR。按收益排序：

| 改什么 | 大概 |
| --- | --- |
| 给 `run()` 加短 TTL 缓存，并去掉重复的车辆列表查询（`server.py:265` 与 `540-541`） | 约 20 行，收益最大 |
| 会话落盘（现在存内存，容器一重启全部 401） | 约 15 行 |
| `travel-sync` 从空桩改成真的调 travel，键名 `records` 改 `list` | 约 5 行 |
| `/healthz` 挪到鉴权闸门之后（现在 Token 填错也显示「连接正常」） | 1 行 |

预测模型缺失不影响可用性 —— 客户端对 `serverPrediction` 做了完整的 nil 兜底，会退回本地常量估算，只是精度下降。推送缺失符合已定的「不做推送」。

---

## 二 · 部署

### 资源需求（个人自用规模）

轮询几台车、单用户，压力极小。**1 核 1G 就够**，瓶颈在常驻可用性而不是算力。

已有的腾讯云 **2C4G / 60GB SSD / 6Mbps / 500GB 月流量** 绰绰有余：

| 资源 | 估算用量 | 结论 |
| --- | --- | --- |
| CPU / 内存 | Python 常驻进程 + 每次请求 fork 一个 Go 二进制，几百 MB | 富余 |
| 磁盘 | 状态快照 + 行程历史，按几台车几年算也只有数百 MB | 富余 |
| 带宽 | 轮询都是 KB 级小请求，峰值远不到 1 Mbps | 富余 |
| 流量 | 每分钟轮询一次 × 5KB ≈ 216 MB/月，加 App 请求撑死几 GB | 用不到 5% |

唯一要留意的是 6 Mbps 是**峰值带宽**。另外那个「每次请求 fork 一个 8.9 MB Go 二进制」的开销，在 1 核机器上会比 CPU 占用数字看起来更疼 —— 加缓存之后就不是问题。

### 网络可达性 —— 这是选型的决定因素

| 服务端位置 | 九号云 API | Google FCM | MiPush / HMS |
| --- | --- | --- | --- |
| 国内 VPS | ✅ 快 | ❌ 不通 | ✅ 快 |
| 家用宽带 + 内网穿透 | ✅ 快 | ❌ 不通 | ✅ 快 |
| 海外 VPS | ⚠️ 慢/不稳 | ✅ 通 | ⚠️ 慢 |

**结论：国内部署。** 只要不用 Google FCM，国内部署没有短板；而一旦选了 FCM，服务端就得出海或加代理，同时轮询九号云会变慢变不稳。这也是「不做推送」这个决定的根本原因之一。

### 部署方案对比

| 方案 | 月成本 | 优点 | 缺点 | 适合 |
| --- | --- | --- | --- | --- |
| **国内轻量云**（阿里云/腾讯云轻量应用服务器 2核2G） | ¥24–40 | 公网 IP、稳定、备案后可上域名+证书 | 需实名，域名要备案 | **推荐** |
| **家用 NAS / 软路由 + 内网穿透**（frp / Tailscale / Cloudflare Tunnel） | ¥0 | 零成本、数据完全自持 | 家宽上行不稳、断电断网即挂、动态 IP | 已有 NAS 且能接受偶发不可用 |
| **国内 VPS + Docker Compose** | ¥30+ | 部署可复现、易迁移 | 同轻量云 | 有运维习惯 |
| 海外 VPS | $5+ | 免备案 | 轮询九号云慢且不稳 | 不推荐 |

### 部署要点

- **HTTPS**：客户端 Info.plist 开了 `NSAllowsArbitraryLoads`，说明目前可能跑在 HTTP 或自签证书上。Android 侧同样要配 `network_security_config.xml` 才能连。**建议直接上 Let's Encrypt + 域名**，两端都省掉降级配置，也避免 Bearer Token 明文过网。
- **不需要 APNs 密钥** —— 已定不做推送。
- **不要暴露管理端到公网**，或至少加独立鉴权。社区适配器的管理端是明文 HTML 表单，会收集九号账号密码。
- **备份**：`accounts.json` 和 ninecli 的 `tokens.json` 丢了要重新登录换令牌；行程历史是长期积累的，配置定期备份。
- **监控**：`/healthz` 接了就用上，配个简单的掉线告警。注意它现在在鉴权之前，只能测「进程活着」，测不了「Token 对不对」。

---

## 三 · 小米超级岛与厂商实时活动

### 调研结论

HyperOS 2 提供**焦点通知**，HyperOS 3 在其之上提供**超级岛**（灵动岛形态）。两者模板不同，岛只在 OS3 上有。

> **⚠️ 下面这套已经实测判定不可做，2026-07-27。** 完整证据见 [hyperos3-island-probe-report.md](./hyperos3-island-probe-report.md)。留着是因为技术细节仍然准确，将来若拿到资质可以直接用。
>
> **结论**：JSON 格式对、模板渲染成功，但 SystemUI 拿 APK 签名 + TrustZone 设备签名**联网到 `hyperos.developer.xiaomi.com` 查该包有没有被授予 scope 20032**，没授予就把通知撤下降级。不是用户开关，也不是本地白名单，**是服务端在线鉴权且绑正式签名**，个人 debug 包拿不到。

**实现方式有两条路，本地通知能把 JSON 送到系统**（不强制走服务端推送），**但过不了鉴权**：

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

**可用轮子**：开源 Kotlin DSL 库 [HyperIsland-ToolKit](https://github.com/D4vidDf/HyperIsland-ToolKit)，封装了 20+ 模板（含进度条、计时器），自动处理 `miui.focus.pic_` 这类系统前缀，可以省掉手拼 JSON。

### 权限：两条路径要分清

- **MiPush 服务端下发焦点通知** —— 确定需要向小米申请资质（邮件 `mipush-permission@xiaomi.com`），要提交通知触发场景截图、焦点通知设计效果图、交互设计、使用期限和使用声明。面向正式产品，自用未上架的应用大概率走不通。而且它与已定的「不做推送」冲突。
- **本地通知 + `miui.focus.param`** —— App 进程活跃时按原生方式发通知并写入 extras 即可，不经过小米服务器。社区实践显示可以自测生效，但系统里存在一个 `hasFocusPermission()` 查询接口，说明确实有权限位；它究竟是用户可开的开关还是小米下发的应用白名单，公开文档没讲清楚。

**这就是 C1 那条阻塞性未知**，已派出实测：装一个 demo APK 发一条带 `miui.focus.param` 的本地通知，看岛出不出来。三种结果各自怎么走写在 [phase5-widget-island-spec.md](./phase5-widget-island-spec.md) 的 C1 里。结论决定 Phase 5.5 是 7 天还是 4 天。

### 覆盖面 —— 标准 API 比想象中管用

先做 **Android 16 `Notification.ProgressStyle`（Live Updates）**，这不只是保底：

| 厂商 | 对应能力 | 标准 API 是否够用 |
| --- | --- | --- |
| OPPO ColorOS 16 | 流体云 | ✅ **够**。已对接 Android 16 Live Updates，遵循 Google 实时活动规范的应用可直接适配，**无需单独接 OPPO** |
| 小米 HyperOS 3 | 超级岛 | ❌ **上不了岛**（实测）。标准 API 发得出通知，但不会进超级岛；私有的 `miui.focus.param` 需要小米服务端授予 scope 20032 且绑正式签名。小米机型上只能是普通通知 |
| 华为 HarmonyOS | 实况窗 | ❌ 需单独接，接口不同 |
| vivo OriginOS | 原子岛 | ❔ 未查证 |
| 其余机型 | 标准通知 | ✅ 至少是常驻进度通知 |

顺序是：**先做 `ProgressStyle`，实测各机型效果，再决定要不要为小米单独写 `miui.focus.param` 分支**。OPPO 基本可以不用管。

注意 minSdk 是 33，而 `ProgressStyle` 是 API 36 —— Android 13/14/15 上这一项只有普通进度通知，那算不算「做完」是 C3。

### 充电场景映射

iOS Live Activity 的 `ContentState` 有 8 个字段：`battery`、`estimatedRange`、`estimatedFullAt`、`chargingPower`、`batteryTemperature`、`batteryVoltage`、`chargingSpeed`、`updatedAt`。其中 `batteryVoltage` 和 `vehicleModel` 进了数据契约但界面一处都没用。

小米超级岛用进度条模板承载：

| 位置 | 内容 |
| --- | --- |
| 小岛（收起态） | 闪电图标 + 电量百分比 |
| 大岛（展开态） | 进度条 + 剩余时间 + 充电功率 |
| 锁屏 / AOD | 电量、续航、预计充满时刻 |
| 状态栏 ticker | 电量百分比 |

触发条件与 iOS 相同（`isCharging && !isFullyCharged && battery != nil`），只是驱动方式从 APNs 换成前台服务本地轮询。

### 前台服务约束

充电通知需要常驻，注意 Android 15+ 对前台服务的限制：`FOREGROUND_SERVICE_DATA_SYNC` 每日有 6 小时配额。充电过程通常 2–4 小时，在配额内，但要处理超时降级。

---

## 四 · 不做推送的论证（结论已定，留论证过程）

推送解决的是「App 完全没运行时也能即时收到变化」。但这个 App 的数据源本来就是自建服务端的轮询结果，客户端并不需要毫秒级即时性：

- 常规刷新 → WorkManager 定时拉，间隔沿用 iOS 那套自适应策略（充电 15 / 使用中 20 / 空闲 30 分钟）
- 充电中的实时活动 → 充电时起一个前台服务，自己定时拉并更新通知。**本地通知足以驱动标准 `ProgressStyle`**；`miui.focus.param` 那条已实测判定不可做（要小米服务端鉴权 + 正式签名）

这样完全不碰推送，省掉厂商 SDK 对接、资质申请、服务端多通道适配三件事。代价是 App 被系统杀死后不会被唤醒 —— 自用可以接受。

如果之后确实要推送，按这个顺序考虑：

1. **厂商推送**（小米 MiPush / 华为 HMS / OPPO）—— 服务端可留国内，且 MiPush 顺带打通超级岛的服务端下发路径
2. **Google FCM** —— 需要能连 `fcm.googleapis.com`。若主服务端在国内，可以让它把推送请求转发给一台海外小机器代发，主链路仍留国内

---

## 五 · 出海（如果以后要）

中文文案比英文短 40–50%，现有卡片布局全按中文宽度调过（大量 `minimumScaleFactor(0.62~0.76)`），要出海得重做布局。领域层抽取时已经把中文从模型层挪到了展示层，算是留了口子，但布局本身没留。

`strings.xml` 的键命名方案和占位符处理见 [string-extraction-inventory.md](./string-extraction-inventory.md)。
