# NineBot+ 安卓移植可行性评估

评估对象：`mini-ninebot`（main 分支，server-only），19 个 Swift 文件约 16100 行。

## 结论

**可行，没有架构级的阻断点。** 这是一个「瘦客户端 + 厚 UI」的应用：续航预测、充电预测、健康评分等真正的算法都在服务端，客户端只做 REST 调用、缓存、格式化和展示。移植的主体是重画 UI，而不是重实现业务。

真正无法平移的是三项 Apple 独占能力（实时活动/灵动岛、锁屏 Widget、Siri 中文语音短语），这是产品取舍问题，不是工程问题。

预估工作量：单人全职 4–5 个月，两人 2.5–3 个月，另需设计资源约 1 周（并行）。服务端需要增加一条 FCM 推送分支。

## 有利条件

| 条件 | 说明 |
| --- | --- |
| 零第三方依赖 | 无 SPM / CocoaPods，无依赖冲突需要处理 |
| 纯 REST 通信 | `NinebotServerClient` 全部走 URLSession + JSON，**没有蓝牙直连**（`nine-proxy` 分支同样没有），不存在需要逆向的私有协议栈 |
| 无 Keychain / 无 CoreData | 全部数据是 `UserDefaults(App Group)` + Codable JSON，对应 DataStore 或 Room |
| 无 Apple Charts | 图表是手写 `Path` + `GeometryReader`，可近乎逐行直译到 Compose Canvas |
| Combine 用得浅 | 只有 `ObservableObject` / `@Published`，一对一映射到 StateFlow |
| 设计 token 只有 8 组 | 明暗双色 RGB 字面量写在代码里，直接搬进 Compose ColorScheme |
| 骑行记录是纯前台的 | 无后台定位模式，Android 侧省掉 `ACCESS_BACKGROUND_LOCATION` 及其商店审核 |
| App Group 在 Android 不需要 | Glance widget 与主 App 同进程，直接读同一份存储 |

## 代码分层与可移植性

| 层 | 行数 | 处理方式 |
| --- | --- | --- |
| `NinebotServerClient` | 1109 | 直译成 Retrofit + kotlinx.serialization |
| `NinebotModels` | 2051 | 数据结构直译；需剥离 91 处中文展示字符串 |
| `NinebotViewModel` | 750 | 直译成 Kotlin ViewModel + StateFlow |
| `NinebotSharedStore` | 493 | 换成 DataStore；建议轨迹点改存 Room |
| `NinebotCoordinateTransform` | 57 | 纯数学，原样保留（见下） |
| Dashboard / Recording / Settings 视图 | 8497 | 全部重写，约 127 个自定义组件 |
| Widget + 系统集成 | 3200 | 部分重写，部分降级 |

约 4500 行（28%）可近乎机械直译，风险低且可并行。

## 系统能力对照

### 有良好对应物

- **Control Widget ×5**（刷新/开锁/关锁/开座桶/寻车）→ Quick Settings Tile（`TileService`），概念一一对应，成本低。
- **APNs → FCM**：服务端 `POST /devices/register` 接口可原样复用，把 `environment` 字段填 `fcm` 即可。
- **BGTaskScheduler → WorkManager**：自适应刷新间隔（充电 15 分钟 / 使用中 20 分钟 / 空闲 30 分钟）可直接搬。Android 这块实际上比 iOS 更可控，但需要处理国产 ROM 的后台保活白名单。
- **防截屏**：iOS 用了 215 行 `UITextField.isSecureTextEntry` 私有视图 hack，Android 一行 `FLAG_SECURE` 就够。唯一需要注意的是 iOS 这套是**局部遮蔽**（只挡车牌和位置），`FLAG_SECURE` 是整窗生效，需要产品重新定义粒度。
- **Home Screen Widget**：Glance 可以覆盖三种尺寸和交互按钮（`Button(intent:)` → `actionRunCallback`）。电量圆环、渐变进度条需要用 Glance Canvas 或预渲染 Bitmap 变通。

### 无对应物（产品需决策）

- **实时活动 / 灵动岛**：充电卡片约 350 行 UI，含 push-to-start token 和服务端直推 ContentState 的完整契约。最接近的是 Android 16 的 `Notification.ProgressStyle`（Live Updates）配合前台服务，锁屏卡片能还原约七成，灵动岛只能砍掉。
- **锁屏 Widget ×3**（circular / rectangular / inline）：Android 手机不支持锁屏 widget（Android 15 QPR1 起仅平板恢复）。只能降级为常驻通知。
- **Siri + 9 个 App Intent + 57 条中文语音短语**：Google 已弃用 App Actions built-in intents。意图本身的业务逻辑是薄的 HTTP 包装，很好搬；损失的是语音入口。设置页里那整块能力展示 UI 需要重新设计。

## 两处真实技术风险

### 1. 传感器融合与调参

`NinebotRideRecorder`（`NinebotRecordingView.swift:129-645`，517 行）是全项目唯一有原创算法的地方：20 Hz CoreMotion 采样、三轴合成 G 值、一阶低通滤波（系数 0.18）、速率限制（0.08）、死区（0.025），加上 13 个 GPS 过滤阈值和一套五档质量状态机，以及回前台时的稳定化冷却机制。

问题在于 `CMDeviceMotion.userAcceleration` 是 Apple 免费提供的融合结果（已去重力、已做 AHRS）。Android 的 `TYPE_LINEAR_ACCELERATION` 是虚拟传感器，各厂商实现质量差异很大，采样率也只是 hint 而非保证。**这套阈值和滤波系数几乎肯定要在真机上骑行实测重调**，这是唯一无法靠翻译代码解决的部分，预留 2 周含路测。

### 2. 地图换栈

4 处 `Map` + `MapPolyline` + `Annotation`，需换成高德或腾讯 SDK（Google Maps 国内不可用）。

**关于坐标转换需要澄清一点**：`NinebotCoordinateTransform` 做的是 WGS-84 → GCJ-02，因为中国区地图底图用的是 GCJ-02。高德和腾讯的底图同样是 GCJ-02，所以**这段代码在 Android 上原样保留即可**，不需要删除也不需要反向改写。只有在改用 Google Maps 海外版时才应该去掉。

另有一处需要在移植时验证：`NinebotDashboardView.swift:1243` 对 `CLLocationManager` 返回的坐标又做了一次 GCJ-02 转换。iOS 在中国大陆返回的定位本身可能已是偏移后的坐标，如果是，这里存在双重偏移。Android 上 `FusedLocationProvider` 返回 WGS-84，需要转一次——两端行为不同，不要照抄，要实测确认。

## 其他需要投入的部分

- **SF Symbols**：85 个唯一符号、299 处调用。`scooter`、`gauge.with.dots.needle.67percent`、`bolt.batteryblock.fill`、`road.lanes` 等约 30–40 个在 Material Symbols 里没有对应物，需要设计师定制。
- **视觉细节**：38 处带颜色和偏移的柔和阴影，Compose 的 `shadow` 只支持单一 elevation，需要逐个用 `drawBehind` 手绘调校。两处 `ultraThinMaterial` 毛玻璃需要 `RenderEffect.createBlurEffect`（API 31+）。
- **本地化**：886 行含硬编码中文，零本地化文件。搬进 `strings.xml` 是机械劳动，但**不能全局替换**——`NinebotDashboardView.swift:202` 用 `message.contains("刷新车况")` 来判断是否显示下拉刷新指示器，把 UI 文案当成了逻辑标识。这类地方要人工甄别。
- **手写下拉刷新**：Dashboard 主体没用 `.refreshable`，而是 6 个 `@State` 组成的手写状态机，Compose 侧要用 `nestedScroll` 重写。

## 建议的前置重构

动手前先在 iOS 侧做一轮领域层抽取，约 3–5 天：

1. 把 `TripTrendAnalysis`（`NinebotDashboardView.swift:3159-3271`，含硬编码的中文规则引擎和 1.8x / 12Wh / 35Wh-km / 5 样本这些业务阈值）、32 个 top-level `private func` 格式化与状态映射函数、`NinebotRideRecorder` 从 View 文件里提出来，放进独立的 Domain 模块。
2. 把 Model 层的 `...Text` 孪生属性拆成 `(value, unit, source)` 结构化数据，展示格式化交给各端。
3. 顺手消除 `message.contains("刷新车况")` 这类用中文字符串驱动 UI 状态的写法，改成 enum。

这一步同时改善 iOS 代码质量，并给 Android 端一份清晰的移植规格。不做的话，业务逻辑会在 Android 端以同样的方式二次散落在 Composable 里。

## 建议的移植顺序

1. 网络 + 模型 + 存储 + ViewModel（可直译，先跑通数据链路）
2. 主 UI 四个 Tab（工作量主体，可多人并行）
3. Quick Settings Tile（对应 Control Widget，性价比最高）
4. FCM + WorkManager
5. Glance Home Widget
6. 骑行记录与传感器调参（需真机路测，尽早开始）
7. 地图接入
8. 实时活动降级为进度通知，锁屏 Widget 与语音入口做产品降级

## 附：项目现状中值得注意的问题

这些不是移植障碍，但两端都应修：

- 登录态、手机号、Bearer Token 以明文存在 `UserDefaults`（`NinebotSharedStore.swift:184-187`），没有用 Keychain。Android 侧建议直接上 EncryptedSharedPreferences 或 Keystore。
- 轨迹点全量 JSON 存进 `UserDefaults`，长途骑行会产生数 MB 的 plist。Android 侧建议直接用 Room 绕开这个隐患。
- `NSAllowsArbitraryLoads = true`，说明服务端可能是 HTTP 或自签证书。Android 需要配 `network_security_config.xml`。
- 无单元测试、无 CI。
- 部署目标 iOS 26.5，但代码里的 `@available` 下限实际只到 iOS 18。Android 侧可以同样激进（minSdk 33/34），省掉大量兼容分支。
