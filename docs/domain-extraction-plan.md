# Phase 0：领域层抽取

## 这是在做什么

一句话：**把「算什么」和「怎么画」拆开。**

现在这两件事是混在一起的。举个真实的例子，`NinebotDashboardView.swift` 是个 5420 行的界面文件，但里面藏着这样一段（第 3242 行起）：

```swift
if let peak = peakRideMileage, let averageDailyMileage, peak > averageDailyMileage * 1.8 {
    result.append("有长距离单次骑行，续航预估会更依赖最近行程样本。")
}
if let averageUsedElectricity, averageUsedElectricity > 12 {
    result.append("最近单次平均用电偏高，可以关注胎压、载重和急加速。")
}
```

这是**业务规则**——「单次骑行超过日均 1.8 倍算长途」「平均用电超过 12 Wh 算偏高」。这些判断标准和文案，跟「界面长什么样」没有关系，但它们现在住在界面文件里，而且是 `private` 的，外面谁也看不见、用不上。

## 为什么移植前要做

Android 版要把界面全部重画。如果业务规则粘在界面代码里，就会变成：

- 重画界面时，**顺手把这些规则再抄一遍**
- 抄的过程中难免有偏差，于是 iOS 说「用电偏高」的那辆车，Android 可能说「正常」
- 以后要改阈值（比如 12 Wh 改成 14），得记得两边都改，漏一边就不一致
- 这些规则**没法写测试**，因为它们藏在 private 里，测试碰不到

抽取之后，这些规则变成独立的、可测的、有明确输入输出的东西。Android 那边照着这份「规格」翻译一次就行，而不是从 5000 行界面代码里往外挖。

## 具体动哪些

### 1. `TripTrendAnalysis` — 行程分析引擎

`NinebotDashboardView.swift:3159-3271`。它顶着一个界面辅助类型的名字，其实是完整的领域模型：月里程、日均里程、均速、平均用电、单次最远、每公里能耗，加上上面那套规则引擎。

搬到独立文件，规则阈值提成有名字的常量。

### 2. 32 个自由函数

`NinebotDashboardView.swift` 里散着 32 个 top-level `private func`，分三类：

- **格式化**：`formatDistance`、`formatSpeed`、`formatDuration`、`formatCoordinate`、`formatEnergyWh` 等 14 个
- **状态映射**：`statusColor`、`statusSystemImage`、`compactVehicleStatusText`、`batteryTextColor`、`healthColor`
- **轨迹处理**：`makeSpeedTrackSegments`（按速度给轨迹分段着色）、`bestSpeedTrackPoint`

格式化和状态映射要分开对待：**「这个值该显示成什么」是领域的事，「显示成什么颜色」是界面的事**。前者搬走，后者留下。

### 3. `NinebotRideRecorder` — 传感器采集器

`NinebotRecordingView.swift:129-645`，517 行。它本身写得挺干净（就是个 `ObservableObject`），只是**放错了文件**——它跟界面没关系，是纯粹的传感器数据处理。

单独挪出来。这一步对 Android 尤其重要，因为那 13 个阈值和滤波系数是移植时最需要逐条对照的东西，散在界面文件里根本没法对照。

### 4. 模型层的「孪生属性」

`NinebotModels.swift` 里几乎每个算出来的值旁边，都配了一个直接产出中文的版本：

```swift
var rangeModelSummaryText: String {
    guard let observedKmPerBatteryPercent else { return "等待行程样本" }
    return "\(numberText(...)) km/% · \(rangeEstimateAccuracyText)"
}
```

模型层里有 91 处这样的中文。这等于把「显示层」压进了「数据层」。

改成返回结构化数据 —— 值、单位、来源、置信度 —— 由各端自己决定怎么显示成文字。这样 Android 不用连中文一起搬，也为将来出海留了口子。

### 5. 顺手修掉一处隐患

`NinebotDashboardView.swift:202`：

```swift
private var isDashboardRefreshLoading: Bool {
    guard model.isLoading else { return false }
    let message = model.loadingMessage ?? ""
    return message.contains("刷新车况") || message.contains("解析车辆位置")
}
```

它靠**匹配中文字符串**来决定要不要显示下拉刷新指示器。把「正在刷新车况」这句文案改一个字，转圈动画就会静默失效，而且不会有任何报错。

改成 ViewModel 发布一个枚举，界面判断枚举。顺带这也是文案抽取到 `strings.xml` 时的一个雷 —— 不改的话，谁哪天动了文案就踩上。

## 会不会改坏

**这是纯搬家，不改任何行为。** 每一步都是「把代码从 A 文件移到 B 文件，改一下可见性」，不动逻辑、不动数值、不动文案内容。

三重保险：

1. 现在有 **291 个单元测试**，CI 上跑一次 1 分钟
2. CI 还会做完整的 Xcode 构建（已验证可用）
3. 抽取出来的东西**从 private 变成可测的**，所以每搬一块就能补上针对性的测试 —— 抽取完测试数量应该是净增的

顺序上先搬 `NinebotRideRecorder`（它最独立，纯挪文件），再搬 `TripTrendAnalysis`，最后处理模型层的孪生属性（这块面最广，放最后）。每一步单独提交，CI 绿了再走下一步，随时可以停。

## 两端长期并行带来的两件事

既然 iOS 不是做完 Android 就退役，而是长期并行，有两点要提前定下来。

### 要不要用 Kotlin Multiplatform 共享领域层

**不建议**。KMP 确实能让两端跑同一份领域代码，但代价是：iOS 侧现有的 Swift 领域逻辑要整个重写成 Kotlin，291 个 Swift 测试要跟着搬，Xcode 工程要接入 KMP 构建产物。对一个自用项目来说，维护这套工具链的成本高于收益。

替代做法是**两端各自实现，靠一份规格和一套共享测试数据对齐**：把关键的业务判断（续航估算、充电预测、健康评分、行程洞察规则）的输入输出写成 JSON 夹具放在仓库里，两端的测试都读同一份文件。以后改阈值，改夹具就会让两端测试同时变红，漏改一端会被立刻发现。

这套机制在领域层抽取时顺手就能建起来，额外成本约 1 天。

### 本地骑行记录跨端同步：不做

F14b 产生的轨迹和 G 值数据存在各自手机上，两端各存各的，不互通。已确认可接受。真需要搬运时可以用 GPX 导出（F17）手动处理。

## 工作量

3–5 天（含建立共享测试夹具约 1 天）。产出是：

- 一个不含任何界面代码的领域层，Android 端照着翻译即可
- iOS 侧代码质量提升（5420 行的 Dashboard 会瘦下来不少）
- 测试覆盖率净增
- 修掉字符串驱动 UI 状态那个隐患
