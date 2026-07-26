# NineBot+ 安卓移植可行性评估

评估对象：`mini-ninebot`（main 分支，server-only），26 个 Swift 文件约 16800 行。

> **这份文档的定位**：只回答「能不能移植、难在哪」。**阶段划分与工作分解看 [android-implementation-plan.md](./android-implementation-plan.md)（Phase 0–5）**，逐项实现规格看 Phase 0–5 的八份 spec，待拍板的事看 [pending-decisions.md](./pending-decisions.md)，服务端与厂商调研看 [android-porting-plan.md](./android-porting-plan.md)。
>
> 本文里凡是当初写成「建议」的部分，凡已定的都已改成结论并标注出处。

## 结论

**可行，没有架构级的阻断点。** 这是一个「瘦客户端 + 厚 UI」的应用：续航预测、充电预测这些算法本该在服务端，客户端只做 REST 调用、缓存、格式化和展示。移植的主体是重画 UI，而不是重实现业务。

无法平移的是三项 Apple 独占能力（实时活动/灵动岛、锁屏 Widget、Siri 中文语音短语）。三项都已有处置：灵动岛走 Android 16 Live Updates + 小米超级岛（Phase 5.5），锁屏 Widget 降级成常驻通知，**语音入口已定不做**。

预估工作量：**约 20 周**（见 implementation-plan 的里程碑表）。**设计资源已确认不需要** —— 97 个图标逐个比对 Material Symbols 后无一需要定制（见 [icon-inventory.md](./icon-inventory.md)）。**推送已定不做**，服务端不需要加推送分支。

## 有利条件

| 条件 | 说明 |
| --- | --- |
| 零第三方依赖 | 无 SPM / CocoaPods，无依赖冲突需要处理 |
| 纯 REST 通信 | `NinebotServerClient` 全部走 URLSession + JSON，**没有蓝牙直连**（`nine-proxy` 分支同样没有），客户端侧不存在需要逆向的私有协议栈 |
| 无 Keychain / 无 CoreData | 全部数据是 `UserDefaults(App Group)` + Codable JSON，对应 DataStore 或 Room |
| 无 Apple Charts | 图表是手写 `Path` + `GeometryReader`，可近乎逐行直译到 Compose Canvas |
| Combine 用得浅 | 只有 `ObservableObject` / `@Published`，一对一映射到 StateFlow |
| 设计 token 只有 8 组 | 明暗双色 RGB 字面量写在代码里，直接搬进 Compose ColorScheme |
| App Group 在 Android 不需要 | Glance widget 与主 App 同进程，直接读同一份存储 |
| 图标零定制 | 97 个唯一 SF Symbol 全部有 Material Symbols 对应物（81 直接可用 + 16 近似可用） |
| 领域层已抽出来了 | 见下面「前置重构」，已完成 |

## 代码分层与可移植性

| 层 | 行数 | 处理方式 |
| --- | --- | --- |
| `NinebotServerClient` | 1109 | 直译成 Retrofit + kotlinx.serialization |
| `NinebotModels` | 2098 | 数据结构直译；剩 43 个产出中文的属性要剥离 |
| 领域层（`Shared/` 的 5 个文件 + `Domain/` 的 2 个） | 1208 | 已从 View 里抽出来，Android 照着翻译 |
| `NinebotViewModel` | 765 | 直译成 Kotlin ViewModel + StateFlow |
| `NinebotSharedStore` | 595 | 换成 DataStore；轨迹点改存 Room |
| `NinebotCoordinateTransform` | 57 | 纯数学，原样保留（见下） |
| Dashboard / Recording / Settings 视图 | 7780 | 全部重写，约 127 个自定义组件 |
| Widget + 系统集成 | 2826 | 部分重写，部分降级 |

约 5800 行（35%）可近乎机械直译，风险低且可并行。

## 系统能力对照

### 有良好对应物

- **Control Widget ×5**（刷新/开锁/关锁/开座桶/寻车）→ Quick Settings Tile（`TileService`），概念一一对应，成本低。Phase 1.3。
- **BGTaskScheduler → WorkManager**：自适应刷新间隔（充电 15 分钟 / 使用中 20 分钟 / 空闲 30 分钟）可直接搬。**注意 `PeriodicWorkRequest` 最小间隔 15 分钟且会被 Doze 分桶延后**，所以「使用中」那一档实测会变成约 30 分钟 —— 取舍写在 phase5-system-spec 里。国产 ROM 的后台保活白名单要另做引导。
- **Home Screen Widget**：Glance 覆盖三种尺寸和交互按钮（`Button(intent:)` → `actionRunCallback`）。**Glance 没有 `Canvas`**，电量圆环和渐变进度条必须变通（W1 待定）。
- **APNs**：**已定不做推送**。充电实时活动改由前台服务本地轮询驱动。

### 需要降级或另做

- **实时活动 / 灵动岛**：充电卡片约 350 行 UI。Android 侧走 Android 16 的 `Notification.ProgressStyle`（Live Updates）+ 前台服务，OPPO ColorOS 16 原生就吃这套；小米超级岛需要私有的 `miui.focus.param`，**能不能被本地通知驱动是唯一的阻塞性未知（C1，已派出实测）**。
- **锁屏 Widget ×3**（circular / rectangular / inline）：Android 手机不支持锁屏 widget（Android 15 QPR1 起仅平板恢复）。降级为常驻通知。
- **Siri + 9 个 App Intent + 55 条中文语音短语**：**语音入口已定不做**。意图本身的业务逻辑是薄的 HTTP 包装，落成桌面长按快捷方式（Phase 5.6）。注意 iOS 侧**本来就没有**长按图标快捷方式，5.6 是纯新增。
- **防截屏**：iOS 用了 215 行 `UITextField.isSecureTextEntry` 私有视图 hack，做的是**局部遮蔽**（3 个调用点：两处位置文本、一处位置卡片；车架号与 VIN 不在保护范围内）。**已定与 iOS 行为一致**，所以用 `SurfaceView.setSecure(true)` 而不是窗口级 `FLAG_SECURE`（后者会让整窗在截图里变黑，行为不同）。不是一行代码，排了 3.5 天。

## 三处真实技术风险

### 1. 传感器融合与调参（最高）

`NinebotRideRecorder`（已抽到 `mini-ninebot/mini-ninebot/Domain/NinebotRideRecorder.swift`，556 行）是全项目唯一有原创算法的地方：20 Hz CoreMotion 采样、三轴合成 G 值、一阶低通滤波（系数 0.18）、速率限制（0.08）、死区（0.025），加上一套五档 GPS 质量状态机和回前台时的稳定化冷却机制。

**阈值共 32 个**，不是最初估的 13 个 —— 15 个是有名字的声明常量，另外 **17 个是散在表达式里的裸数字**（滤波系数全在这一类）。只照着有名字的那 15 个实现，等于漏掉一半。逐条清单在 [phase4-sensors-spec.md](./phase4-sensors-spec.md)。

问题在于 `CMDeviceMotion.userAcceleration` 是 Apple 免费提供的融合结果（已去重力、已做 AHRS）。Android 的 `TYPE_LINEAR_ACCELERATION` 是虚拟传感器，各厂商实现质量差异很大，采样率也只是 hint 而非保证，低端机上可能完全不存在。**这套阈值和滤波系数几乎肯定要在真机上骑行实测重调**，这是唯一无法靠翻译代码解决的部分，排 10 天，要求覆盖 3 个品牌 4 台设备。

还有一个 iOS 上碰不到的雷：定位回调若快于 2.2 Hz，距离累计会**永久归零**且不报错（CoreLocation 约 1 Hz 所以撞不上）。Android 侧必须把定位间隔钉在 1000 ms。

### 2. 服务端性能（新发现）

社区服务端每个请求都 `subprocess.run` 起一个新的 `ninecli` 进程（8.9 MB Go 二进制），且被一把锁串行化。**一次车况刷新会打 6 次以上**，其中车辆列表还重复查了两次。而 Widget 的网络预算硬上限是 12 秒。

已定的处置是 **fork 社区服务端自己改**，优先加请求缓存。详见 [community-server-api-check.md](./community-server-api-check.md)。

### 3. 地图换栈

4 处 `Map` + `MapPolyline` + `Annotation`，**已定换高德**（Google Maps 国内不可用）。

**坐标转换要澄清一点**：`NinebotCoordinateTransform` 做的是 WGS-84 → GCJ-02，因为中国区地图底图用的是 GCJ-02。高德底图同样是 GCJ-02，所以**这段代码在 Android 上原样保留即可**，不需要删除也不需要反向改写。

定位 SDK **已定高德优先、回退 Google 融合定位**（D8）。高德直接返回 GCJ-02，走这条路时不需要再转；Google 返回 WGS-84，需要转一次。两条路径的坐标系不同，所以 `ride_points` 表必须带一列记录坐标系。

`NinebotDashboardView.swift:1243` 对系统定位返回的坐标又做了一次 GCJ-02 转换 —— iOS 在中国大陆返回的定位本身可能已是偏移后的坐标，若是则存在双重偏移。**不要照抄，实测确认**，诊断特征写在 phase4-track-spec 里。

## 其他需要投入的部分

- **图标**：97 个唯一 SF Symbol、274 处引用。逐个比对 Material Symbols 官方 codepoints 清单后**无一需要定制**。落地方案已定：内嵌可变字体 + Widget/磁贴/Marker 那 14 个另出 drawable。全清单见 [icon-inventory.md](./icon-inventory.md)。
- **视觉细节**：38 处带颜色和偏移的柔和阴影，Compose 的 `shadow` 只支持单一 elevation，需要逐个用 `drawBehind` 手绘调校（D7：先近似，Phase 5 收尾再调）。两处 `ultraThinMaterial` 毛玻璃需要 `RenderEffect.createBlurEffect`（API 31+）。
- **本地化**：874 行代码含中文字面量，去重 635 条，零本地化文件。搬进 `strings.xml` 是机械劳动，但**不能全局替换** —— **146 处代码站点的中文在参与逻辑判断**，改了会静默失效。完整清单与危险等级见 [string-extraction-inventory.md](./string-extraction-inventory.md)。
- **手写下拉刷新**：Dashboard 主体没用 `.refreshable`，而是 6 个 `@State` 组成的手写状态机。**已定完整复刻 iOS 手势**，Compose 侧用 `nestedScroll` 重写。

## 前置重构（已完成）

动手前先在 iOS 侧做了一轮领域层抽取，结果见 [domain-extraction-plan.md](./domain-extraction-plan.md)：

1. `TripTrendAnalysis`、21 个格式化函数、`NinebotRideRecorder` 从 View 文件里提出来了。
2. 模型层带判断分支的属性抽成了枚举（充电状态、续航预测质量、历史周期）。
3. `message.contains("刷新车况")` 这类用中文字符串驱动 UI 状态的写法改成了枚举。

测试从 291 增到 379，Dashboard 从 5420 行降到 5215 行。抽取过程中还钉出了两个 iOS 现存行为（D9 缓存快照误报「已充满」、D11 时长临界值取整），处置都记在 pending-decisions 里。

**唯一没做的**是共享 JSON 测试夹具（原计划约 1 天）—— 留到 Android 开工时补，那时才知道两端要对齐哪些输入输出。

## 附：项目现状

- **轨迹存储**：原先把全部轨迹点 JSON 塞进 `UserDefaults`，长途骑行会产生数 MB 的 plist。已改为「摘要存 defaults + 每条骑行一个轨迹文件，按需加载」，含旧数据自动迁移。Android 侧直接上 Room 一步到位，两张表天然消掉 iOS 这套机制。
- **凭证明文存储**：登录态、手机号、Bearer Token 明文存在 `UserDefaults`。**已确认为可接受的取舍**（个人自建、单用户场景），Android 侧保持一致，不必强上 EncryptedSharedPreferences。
- **测试与 CI**：`Package.swift` + 379 个单元测试 + GitHub Actions（`swift test` 为门禁，Xcode 构建为参考）。覆盖 `Shared/` 下的平台无关层；UI 层和 Widget 仍无测试。
- `NSAllowsArbitraryLoads = true`，说明服务端可能是 HTTP 或自签证书。Android 需要配 `network_security_config.xml`；更好的做法是服务端直接上 Let's Encrypt。
- 部署目标 iOS 26.5，但代码里的 `@available` 下限实际只到 iOS 18。Android 侧同样激进，**minSdk 33**。
- **服务端是必须的**，不是设计选择 —— 九号官方协议封在闭源的 `ninecli` 二进制里，客户端从来没有过直连能力。详见 [android-porting-plan.md](./android-porting-plan.md) 的服务端一节。
