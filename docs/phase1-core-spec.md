# Phase 1 · 能用详细规格

2.2 周，累计到第 5.2 周。做完这一阶段就能替代官方 App 做日常车控。

---

## 1.1 车辆状态主卡片（4 天）

### 数据来源

全部来自 `NinebotVehicleState`（`Shared/NinebotModels.swift:1005` 起）。展示字段与兜底文案：

| 展示项 | 属性 | 数据缺失时 |
| --- | --- | --- |
| 电量百分比 | `batteryText` | `--%` |
| 电量比例（画环用） | `batteryFraction` | `0` |
| 续航 | `enduranceText` | `-- km` |
| 官方预估续航 | `officialEstimatedMileageText` | `接口未返回` |
| AI 预估续航 | `aiEstimatedMileageText` | `接口未返回` |
| 锁车状态 | `lockText` | `未知` |
| 电源状态 | `powerText` | 见下 |
| 主状态标题 | `primaryStatusText`（= `health.title`） | `状态未知` |
| 月度里程 | `monthMileageText` | `-- km` |
| 总里程 | `totalMileageText` | `-- km` |
| 剩余充电时间 | `remainingChargeTimeText` | `未知` |
| 位置描述 | `locationText` | `未知位置` |

### `powerText` 的优先级（不是简单的三元判断）

```
isFullyCharged（battery ≥ 100）  → "已充满"
isCharging == true               → "充电中"
isPoweredOn == nil               → "离线"
isPoweredOn == true              → "已上电"
isPoweredOn == false             → "已熄火"
```

注意前两个分支**优先于**上电状态。充电时不管上电与否都显示充电中。

### `lockText`

```
isLocked == nil   → "未知"
isLocked == true  → "已锁"
isLocked == false → "未锁"
```

`isLocked` 的来源有点绕（`NinebotServerClient.swift:572`）：优先取 `loc.lock`，回退到 `lock_status`/`lockStatus`，然后 `== 1` 判定为已锁。

### 健康状态卡片

`health` 返回 `NinebotVehicleHealth(level, title, message, systemImage)`，七个分支的完整判定顺序见 [Phase 2 规格](./phase2-vehicle-control-spec.md)（2.2 节）。Phase 1 只需要展示 `title` 和 `message`，颜色按 `level` 映射。

`level` 五个值与配色：

| level | 颜色 |
| --- | --- |
| good | teslaGreen |
| charging | teslaGreen |
| attention | orange |
| critical | red |
| unknown | teslaSecondaryText |

### 电量环形图

iOS 侧在 Widget 里有 `SmallWidgetBatteryRing`（`NinebotWidgets/NinebotWidgets.swift:577`），主卡片里是类似结构。画法：

- 背景圆环：`Circle().stroke(lineWidth:)`，用 teslaControlBackground
- 进度圆环：`.trim(from: 0, to: batteryFraction)` + `.rotationEffect(.degrees(-90))` 让起点在正上方
- 线帽 `.round`
- 颜色按电量分档（`batteryTextColor`，`NinebotDashboardView.swift:5163` 附近）

Compose 对应：

```kotlin
Canvas(Modifier.size(ringSize)) {
    val stroke = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
    // 底环
    drawCircle(color = trackColor, radius = r, style = stroke)
    // 进度弧：-90 度起点，顺时针
    drawArc(
        color = progressColor,
        startAngle = -90f,
        sweepAngle = 360f * batteryFraction.toFloat(),
        useCenter = false,
        style = stroke,
    )
}
```

电量变化时用 `animateFloatAsState` 让弧长平滑过渡，对应 iOS 的隐式动画。

### 下拉刷新

**iOS 侧没有用 `.refreshable`**，而是一套手写状态机（`NinebotDashboardView.swift:11-17` 的六个 `@State`）：`pullDistance`、`didTriggerPullRefresh`、`isTrackingPullGesture`、`pullGestureStartedAtTop`、`isShowingPullTimestamp`、`pullTimestampDismissID`，配合 `simultaneousGesture` 和 `.onScrollGeometryChange` 判断是否在顶部。

Android 直接用 `PullToRefreshBox`（Material3），不要复刻这套手写逻辑。行为对齐即可：下拉触发刷新、刷新完成后短暂显示「已更新 HH:mm」。

**但有一个坑要避开**：iOS 判断"当前是否在刷新车况"用的是匹配中文字符串（`NinebotDashboardView.swift:202` 的 `message.contains("刷新车况")`）。Android 侧用 Phase 0 定义的 `LoadingKind` 密封类判断，不要重复这个设计。

### 陷阱

- 所有字段都可能为空，且**空值有具体文案**，不是统一显示 `--`。「接口未返回」和「未知」是不同的语义，别统一化。
- `updatedAt` 为 `.distantPast` 时表示从未刷新过，界面要区别于"刚刚刷新"。
- 电量为 0 和电量为 nil 要区分：前者画空环显示 `0%`，后者画空环显示 `--%`。

### 验收

- 造六组输入（正常 / 充电中 / 已充满 / 低电量 / 未锁车 / 字段全空），与 iOS 截图逐项比对文案
- 电量从 20% 变到 80% 时环形图有平滑动画

---

## 1.2 四个控制指令（4 天）

### 指令定义

`NinebotVehicleAction`（`NinebotViewModel.swift:24-107`）四个 case，每个有六套文案。**全部原文照搬**：

| | bell | openBucket | engineStart | engineStop |
| --- | --- | --- | --- | --- |
| 端点 | `POST /vehicles/{sn}/bell` | `/buck` | `/engine/start` | `/engine/stop` |
| `title` | 寻车铃 | 开座桶 | 上电 | 熄火 |
| `subtitle` | 让车辆发出提示音 | 打开座桶 | 车辆进入可骑行状态 | 关闭电源并锁车 |
| `loadingTitle` | 正在寻车鸣笛 | 正在打开座桶 | 正在开锁 | 正在关锁 |
| `resultTitle` | 寻车铃已发送 | 开座桶指令已发送 | 上电指令已发送 | 熄火指令已发送 |
| `confirmationTitle` | 发送寻车铃？ | 打开座桶？ | 车辆上电？ | 车辆熄火？ |
| `confirmationMessage` | 车辆会发出提示音。 | 座桶会被打开，请确认车辆在你身边。 | 车辆会进入上电/解锁状态，请确认车辆在你身边。 | 车辆会进入熄火/锁车状态，请确认不会影响当前骑行。 |
| `isDangerous` | **false** | **true** | **true** | **true** |
| 图标 | bell.fill | shippingbox.fill | power.circle.fill | lock.fill |

### 生物识别

`isDangerous == true` 的三个（开座桶、上电、熄火）需要验证。iOS 是在 App Intent 层用 `authenticationPolicy = .requiresAuthentication` 交给系统处理（`NinebotAppIntents.swift`），App 内则是靠确认对话框。

Android 用 `BiometricPrompt`：

```kotlin
BiometricPrompt.PromptInfo.Builder()
    .setTitle(action.confirmationTitle)
    .setSubtitle(action.confirmationMessage)
    .setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
    .build()
```

`DEVICE_CREDENTIAL` 一定要带上，否则没有指纹的设备无法执行危险操作。

**取消处理**：用户取消验证要静默返回，不能显示错误。`onAuthenticationError` 里的 `ERROR_USER_CANCELED` 和 `ERROR_NEGATIVE_BUTTON` 都算取消。

寻车铃不需要验证，直接执行。

### 执行流程

`perform(_:sn:)`（`NinebotViewModel.swift:373-403`）：

```
1. 设置 activeVehicleAction / activeVehicleActionSN（用于界面高亮当前执行的按钮）
2. 显示 loadingTitle
3. 调用对应端点
4. 成功 → 显示 resultTitle
5. 重新拉取 dashboard（因为指令会改变车辆状态）
6. 缓存车辆图片、刷新地址
7. 重载 Widget
8. defer 清空 activeVehicleAction
```

**第 5 步很重要**：指令执行后必须重新拉状态，否则界面还显示旧的锁车状态。

### 滑动确认控件

`SlideActionControl`（`NinebotDashboardView.swift:3629-3752`）。危险操作用滑动而非点击，防误触。

**几何**：
```
height    = 64
thumbSize = 52
maxOffset = max(容器宽度 - thumbSize - 10, 0)
thumb padding = 5
```

**手势状态机**（三个状态变量：`dragOffset`、`isCommitted`、`isDragging`）：

```
onChanged:
  isDisabled 或 isCommitted → 忽略
  isDragging = true
  dragOffset = clamp(translation.width, 0, maxOffset)

onEnded:
  isDisabled 或 isCommitted → 忽略
  dragOffset >= maxOffset × 0.72  →  提交
      isCommitted = true
      动画 spring(response: 0.28, dampingFraction: 0.86) 把 dragOffset 推到 maxOffset
      触发 onCommit()
      0.45 秒后，动画 spring(response: 0.32, dampingFraction: 0.86) 归零并复位状态
  否则  →  回弹
      动画 spring(response: 0.32, dampingFraction: 0.86) 归零
```

**阈值 0.72** 意味着要滑过 72% 才算确认，滑不到就弹回。

**视觉**：滑块后方有一条渐变轨迹（`color.opacity(0.42)` → `color.opacity(0.16)`，从左到右），宽度 `max(thumbSize + dragOffset, thumbSize)`，只在拖动或已提交时可见。文字区域在忙碌时显示 `completedTitle`，空闲时显示 `title`，右侧有两个叠在一起的 chevron（`spacing: -2`）作为滑动暗示。

**spring 参数换算**（SwiftUI 与 Compose 语义不同）：

SwiftUI 的 `response` 是周期（秒），`dampingFraction` 是阻尼比。Compose 的 `spring(dampingRatio, stiffness)` 里 stiffness 是刚度。换算关系：

```
stiffness = (2π / response)²
dampingRatio = dampingFraction
```

所以：
- `response: 0.28` → stiffness ≈ (2π/0.28)² ≈ **503**，dampingRatio = 0.86
- `response: 0.32` → stiffness ≈ (2π/0.32)² ≈ **386**，dampingRatio = 0.86

Compose 写法：
```kotlin
animateFloatAsState(
    targetValue = target,
    animationSpec = spring(dampingRatio = 0.86f, stiffness = 503f),
)
```

这个换算是近似的（两个框架的积分实现不同），实际手感要在真机上微调。建议先按上面的值实现，然后跟 iOS 版并排滑动对比。

### Android 手势实现

```kotlin
Modifier.draggable(
    orientation = Orientation.Horizontal,
    state = rememberDraggableState { delta ->
        offset = (offset + delta).coerceIn(0f, maxOffset)
    },
    onDragStopped = {
        if (offset >= maxOffset * 0.72f) { /* 提交 */ } else { /* 回弹 */ }
    },
)
```

### 陷阱

- 提交后 0.45 秒才复位，这段时间要**阻止重复触发**（`isCommitted` 守卫）。Android 侧同样需要，否则快速滑两次会发两条指令。
- `isDisabled` 时整个控件透明度 0.55，但 `isLoading` 时不降透明度（正在执行不算禁用）。
- 指令失败时要复位滑块，不能卡在已提交状态。

### 验收

- 滑不到 72% 会回弹，滑过会执行
- 执行中重复滑动不会发第二条指令
- 三个危险指令都弹生物识别，寻车铃不弹
- 取消生物识别后滑块复位且不报错

---

## 1.3 快捷设置磁贴（3 天）

### iOS 现状

五个 Control Widget（`NinebotWidgets/NinebotWidgets.swift:57-125`），全部 iOS 18+ 的 `StaticControlConfiguration` + `ControlWidgetButton`：

| Widget | 对应 intent |
| --- | --- |
| `NinebotRefreshControlWidget` | 刷新车况 |
| `NinebotUnlockControlWidget` | 上电 |
| `NinebotLockControlWidget` | 熄火 |
| `NinebotBucketControlWidget` | 开座桶 |
| `NinebotBellControlWidget` | 寻车铃 |

intent 实现在 `NinebotWidgetControlIntents.swift`，后四个带 `authenticationPolicy = .requiresAuthentication`。

**关键约束**（`NinebotWidgetControlIntents.swift:80-86`）：Widget 扩展用的是独立的 ephemeral `URLSession`，超时设成 **8 秒 / 12 秒**（比主 App 的 20 秒短很多），因为 widget 扩展的执行时间被系统严格限制。

### Android 对应：TileService

五个 `TileService` 子类，`AndroidManifest.xml` 里各自声明：

```xml
<service
    android:name=".tile.BellTileService"
    android:icon="@drawable/ic_bell"
    android:label="@string/action_bell"
    android:permission="android.permission.BIND_QUICK_SETTINGS_TILE"
    android:exported="true">
    <intent-filter>
        <action android:name="android.service.quicksettings.action.QS_TILE" />
    </intent-filter>
</service>
```

### 生命周期约束（与 iOS 不同的地方）

`TileService` 的回调都在主线程，且**服务随时可能被回收**。所以：

- `onClick()` 里**不能直接做网络请求**，要用 `WorkManager` 或 `CoroutineScope` + `goAsync` 模式
- 但 `TileService` 没有 `goAsync()`，正确做法是在 `onClick` 里立即更新磁贴为「执行中」状态，然后把实际工作交给 `WorkManager` 的 `OneTimeWorkRequest`，Worker 完成后通过 `TileService.requestListeningState()` 触发磁贴刷新
- `onStartListening()` / `onStopListening()` 之间才能安全调 `qsTile.updateTile()`

**磁贴状态机**：

```
Tile.STATE_INACTIVE  空闲，可点击
Tile.STATE_ACTIVE    执行成功后短暂显示
Tile.STATE_UNAVAILABLE  未登录或未配置服务器
```

点击后立即置为 `STATE_ACTIVE` 并把 `subtitle` 设成 `loadingTitle`，Worker 回来后改成 `resultTitle` 或错误提示。

### 危险操作的验证

磁贴在锁屏上也能点，所以危险操作必须验证。`TileService` 有 `isSecure` 和 `unlockAndRun {}`：

```kotlin
override fun onClick() {
    if (action.isDangerous) {
        unlockAndRun { enqueueWork() }   // 锁屏时先要求解锁
    } else {
        enqueueWork()
    }
}
```

`unlockAndRun` 只保证设备已解锁，**不等于生物识别**。如果要跟 App 内一致的验证强度，得在 `onClick` 里启动一个透明 Activity 走 `BiometricPrompt`，代价是体验变重。

**建议**：磁贴用 `unlockAndRun`（设备解锁即可），App 内保留 `BiometricPrompt`。理由是磁贴本身在锁屏后就不可用，已经有一层保护；再叠生物识别会让「下拉就能控车」这个卖点消失。这与 iOS 的行为略有差异（iOS 的 Control Widget 是真的走了 `requiresAuthentication`），文档里记一笔。

### 用户添加磁贴

Android 13+ 可以主动请求：

```kotlin
statusBarManager.requestAddTileService(
    ComponentName(context, BellTileService::class.java),
    label, icon, executor, resultCallback,
)
```

在设置页放一个「添加到快捷设置」按钮，比让用户自己去编辑面板找要好得多。

### 超时

对应 iOS 的 8/12 秒，Android 侧给 Worker 设 `OneTimeWorkRequest` + OkHttp 客户端超时 10 秒。Worker 本身有 10 分钟上限，不是瓶颈，瓶颈是用户耐心。

### 陷阱

- 磁贴 icon 必须是单色 `VectorDrawable`，彩色图标会被系统强制染色
- `qsTile` 可能为 null（服务刚创建时），每次用前判空
- 磁贴不支持长按自定义行为，长按会跳到 App 的设置页（系统行为）
- 五个磁贴要五个 Service 类，不能用一个 Service 靠参数区分

### 验收

- 五个磁贴都能从快捷设置面板添加
- 未登录时显示为不可用状态
- 点击后磁贴 subtitle 显示执行进度，成功后显示结果
- 锁屏状态下点危险磁贴会先要求解锁
- 设置页的「添加到快捷设置」按钮可用

---

## 本阶段完成后的状态

能看车况、能控车、能在通知栏下拉直接控车。这是第 5.2 周的里程碑，日常使用已经可以脱离官方 App。

还没有的：地图、行程、图表、Widget、轨迹记录。
