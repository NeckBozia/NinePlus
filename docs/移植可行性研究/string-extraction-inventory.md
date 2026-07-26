# 中文字面量清点与搬迁分类

面向 Android 移植：把 iOS 侧硬编码在源码里的中文，分类标出哪些能直接进 `strings.xml`、哪些不能。

所有引用都是 `文件:行号`，路径相对仓库根。B 类每条附了做比较/写入的那行代码原文。

---

## 0 · 统计口径与总量

统计范围：`mini-ninebot/` 下全部 `.swift`（App + Widget 扩展 + Shared）。`Tests/` 单独统计，见第 6 节。纯注释行（以 `//`、`///`、`*` 开头）不计入。

| 指标 | 数量 |
| --- | --- |
| 含中文的行（含注释行） | 880 |
| 含中文**字面量**的代码行 | 874 |
| 中文字面量出现处数 | 909 |
| 去重后的中文字面量 | **635** |

去重后的 635 条拆成四份，互不重叠，可加和：

| 分类 | 去重条数 | 说明 |
| --- | --- | --- |
| A · 纯显示文案 | **455** | 只用来显示，进 `strings.xml` 零风险 |
| B · 参与逻辑（非插值部分） | **56** | 见第 2 节 |
| B · Siri 语音短语 | **55** | 见 2.5，属 B 但形态特殊，单列 |
| C · 带插值或单位 | **69** | 其中 5 条同时属 B（statusMessage / loading 文案） |
| 合计 | 455 + 56 + 55 + 69 = **635** | ✅ |

B 类对应的**代码站点**是 **146 处**（一条字面量可能出现在多个站点，一个站点也可能牵连多条字面量），逐条清单见第 2 节。

D 类是**结构分类**而不是第四个互斥的桶：它标记的是「已经做成枚举 + 文案表」的那 93 处文案，这些文案本身已经分别计入上面的 A / B / C。不要把 93 重复加进 635。

复现命令（ripgrep 的 `\p{Han}` 比 `grep -P` 的码点区间可靠）：

```
rg -c '\p{Han}' -g '*.swift' mini-ninebot/          # 每文件行数
rg -N --no-filename '\p{Han}' -g '*.swift' mini-ninebot/ | wc -l   # 880
```

> 与先前记录的「约 638 条」差 3 条。差异来源是嵌套引号插值串的切分方式：`"\(x ?? "--") 小时"` 这种字面量里套了一个 `"--"`，按不同的切分规则会算成 1 条或 3 条。本文档按「一个完整的 Swift 字符串字面量算 1 条」统计，`mini-ninebot/Shared/NinebotModels.swift:1703`、`:1705` 是这类的两处。

---

## 1 · A 类 · 纯显示文案（455 条去重）

只进 `Text()`、`Label()`、`.navigationTitle()`、`placeholder`、`accessibilityLabel` 一类的显示位置，不参与任何判断、不写进持久化、不发给服务端。按界面模块归类给数量和代表条目，不逐条列全。

### 1.1 按模块的出现处数

统计维度是「出现处数」（比去重条数更容易核对：直接数文件里的行）。**这张表覆盖全部 909 处**（A + B + C 混在一起按界面模块切），不是只有 A 类 —— 按模块分批搬迁时看的是这个粒度，而 B 类要挑出来单独处理，见第 2 节。

| 模块 | 主要文件 | 处数 | 代表条目 |
| --- | --- | --- | --- |
| 原始字段名映射表 | `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:4967-5093` | 115 | `:4974` `"battery": "电量"`、`:5047` `"lat": "纬度"`、`:5062` `"pwr": "电源状态"` |
| 车况详情 / 原始面板 | 同上 `:3729-3901`、`:4560-4700` | 约 50 | `:3744` `"电池电压"`、`:3768` `"电源状态"`、`:4612` `"已复制"` |
| 趋势分析（月度） | 同上 `:2584-3230` | 约 70 | `:2723` `"趋势分析"`、`:2817` `"骑行次数"`、`:2972` `"算法提示"`、`:3190` `"暂无每日里程数据"` |
| 行程列表 / 行程详情 | 同上 `:1261-1420`、`:3903-4250` | 约 45 | `:3915` `"行程列表"`、`:4125` `"行程详情"`、`:4261` `"本地轨迹"` |
| 车控首页（Hero / 控制 / 地图） | 同上 `:389-2130`、`:3337-3650` | 约 60 | `:1112` `"车辆位置"`、`:1934` `"正在充电"`、`:3399` `"寻车"`、`:3421` `"座桶"` |
| 电池详情 / 电池类型设置 | 同上 `:454-1020`；`mini-ninebot/Shared/NinebotModels.swift:167-181` | 约 30 | `:974` `"满电时间"`、`NinebotModels.swift:177` `"仅在接口明确返回类型时自动采用"` |
| 我的 / 连接设置 | `mini-ninebot/mini-ninebot/App/NinebotSettingsView.swift:40-200`、`:440-500` | 约 30 | `:46` `"服务器地址"`、`:88` `"多账号、APNs 和轮询策略在 NinePlus Platform 后台管理；后台未设置 App Bearer Token 时可留空。"` |
| 诊断中心 | 同上 `:970-1250` | 约 35 | `:1019` `"诊断中心"`、`:1142` `"还没有记录到刷新事件"`、`:1206` `"复制当前车辆、状态、电池和行程返回值，方便排查字段。"` |
| 登录页 | 同上 `:220-700` | 约 20 | `:539` `"欢迎登录"`、`:684` `"我已阅读并同意《用户协议》和《隐私政策》"` |
| 本地记录（GPS / 轨迹） | `mini-ninebot/mini-ninebot/App/NinebotRecordingView.swift` 全文 | 61 | `:377` `"实时轨迹"`、`:489` `"结束一次记录后会出现在这里"`、`:852` `"轨迹导出"` |
| 桌面小组件 | `mini-ninebot/NinebotWidgets/NinebotWidgets.swift:30-1100` | 约 45 | `:37` `"九号车况"`、`:906` `"本月日均"`、`:940` `"九号暂无数据"` |
| 灵动岛 / 充电实时活动 | 同上 `:170-360` | 约 18 | `:173` `"充电时在锁屏和灵动岛显示电量、预计时间和电池状态。"`、`:219` `"剩余时间"` |
| 底部标签栏 | `mini-ninebot/mini-ninebot/ContentView.swift:34-60` | 5 | `:34` `"车控"`、`:42` `"行程"`、`:50` `"记录"`、`:60` `"我的"` |
| 车况文案（模型层计算属性） | `mini-ninebot/Shared/NinebotModels.swift:1040-1530` | 约 76 | `:1048` `"接口未返回"`、`:1242` `"未知位置"`、`:1304` `"等待行程样本"` |
| 定位错误提示（仅 @Published，不落盘） | `mini-ninebot/mini-ninebot/Domain/NinebotRideRecorder.swift:115,126,149,156,161` | 5 | `:126` `"需要定位权限才能显示实时位置"`、`:156` `"请允许定位后再开始记录"` |

各文件精确处数（脚本产出，可复核；同样是 A + B + C 合计）：`NinebotDashboardView.swift` 393、`NinebotAppIntents.swift` 102、`NinebotModels.swift` 93、`NinebotSettingsView.swift` 86、`NinebotWidgets.swift` 63、`NinebotRecordingView.swift` 61、`NinebotViewModel.swift` 49、`NinebotWidgetControlIntents.swift` 24、`NinebotLoadingOperation.swift` 8、`NinebotServerClient.swift` 5、`ContentView.swift` 5、`NinebotRideRecorder.swift` 5、`NinebotWidgetProvider.swift` 4、`NinebotBackgroundTaskManager.swift` 4、`NinebotPushManager.swift` 4、`NinebotFormatting.swift` 3。合计 909。

### 1.2 A 类里唯一需要留意的一处

`friendlyRawFieldName`（`mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:4967-5093`）一个人占了 115 处、约 100 条去重文案。整张表 122 个条目，其中 7 个的 value 是 ASCII（`"and_mac": "Android MAC"`、`"id": "ID"`、`"sn": "SN"`、4 个映射到 `"VIN"`），剩下 115 个是中文。它的**键全是 ASCII 接口字段名，中文只出现在 value**，所以搬迁是安全的（不属于「字典的键是中文」那条 B 类判据）。但它是一张 122 条的查表，Android 侧做成 122 条 `strings.xml` 还是一张代码里的 `Map<String, Int>`，需要拍板 → 见 `## 待定` L7。

### 1.3 App 之外还有两条

`mini-ninebot/Config/mini-ninebot-Info.plist:37`、`:39` 各有一条权限用途说明：

- `:37` `NSSiriUsageDescription` → `用于通过 Siri 和快捷指令刷新车况、查询电量、查询位置、寻车铃、开座桶、上电和熄火。`
- `:39` `NSLocationWhenInUseUsageDescription` → `用于记录骑行轨迹、实时速度和加速 G 值。开始记录后即使锁屏或切换到其他应用也会继续记录，状态栏会显示蓝色指示条。`

Android 没有 `Info.plist` 的对应物，这两条会变成 App 自己画的权限说明弹窗文案，属于新写的 UI 文案 → 见 `## 待定` L9。

---

## 2 · B 类 · 参与逻辑（146 处代码站点，涉及 116 条字面量）

**这一节必须逐条看完。** 这些中文不是（或不只是）用来显示的，全局替换会静默失效。

已有先例：下拉刷新指示器原先靠 `message.contains("刷新车况")` 判断要不要转圈，改一个字动画就没了。该处已改成枚举，`mini-ninebot/mini-ninebot/Domain/NinebotLoadingOperation.swift:5-8` 的注释记录了这件事，`:50-58` 的 `showsDashboardRefreshIndicator` 是替代实现。下面列的是**同类里还没改的部分**。

各子类站点数：B1 2 + B2 6 + B3 29 + B4 52 + B5 56 + B6 1 = **146**。

### 2.1 B1 · 直接与中文字面量做 `==` / `!=` 比较（2 处）

**最危险的两处。** 两个文件各写了一份 `"未绑定账号"`，必须逐字相同，编译器不会检查。

1. `mini-ninebot/mini-ninebot/App/NinebotSettingsView.swift:1084`

```swift
                DiagnosticMetricPill(title: "账号", value: diagnostics.accountText == "未绑定账号" ? "0" : "1", systemImage: "person.fill")
```

对比对象 `diagnostics.accountText` 来自 `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:184`：

```swift
        return savedPhone.isEmpty ? "未绑定账号" : savedPhone
```

改动任一侧：诊断中心的「账号」指标永远显示 `1`，即使没绑定账号。不报错。

2. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:1530`

```swift
    if !fallback.isEmpty, fallback != "未绑定账号" {
```

改动任一侧：车辆选择器的分组标题变成 `未绑定账号 账号`（`:1531` 是 `return "\(fallback) 账号"`）。不报错。

### 2.2 B2 · 中文（间接）参与分组、去重、列表身份（6 处）

这几处的中文不在比较那一行，而是被一个返回中文的函数产出后当键用。grep 中文关键字扫不出来，只能顺着调用链读。

3. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:1481`

```swift
            if let index = groups.firstIndex(where: { $0.title == title }) {
```

`title` 来自 `:1480` 的 `vehicleAccountTitle(for:fallback:)`，该函数三个返回分支分别是 `:1524` `"\(value) 账号"`、`:1531` `"\(fallback) 账号"`、`:1533` `"当前九号账号"`。车辆按这个**带中文后缀的显示串**分组。改掉「账号」二字或改掉 `"当前九号账号"`，分组行为会变（本来该合并的分开、本来该分开的合并）。

4. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:1496`

```swift
    var id: String { title }
```

`VehiclePickerAccountGroup` 的 `Identifiable` id 就是上面那个中文串。SwiftUI 用它做 diff；Compose 侧对应 `LazyColumn` 的 `key`。两个分组文案撞车 → 列表行为异常。

5. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:1998-2000`

```swift
    var id: String {
        title
    }
```

`ChargingMetric` 的 id 是 `title`。这三个 title 是 `:1981` `"功率"`、`:1984` `"电压"`、`:1987` `"温度"`。

6. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:4079-4081`

```swift
    var id: String {
        "\(title)-\(value)-\(systemImage)"
    }
```

`RideDisplayMetric` 的 id 把中文 title 拼进去。title 是 `:4067` `"能耗"`、`:4068` `"用电"`、`:4069` `"速度"`。

7. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:2519`

```swift
                    ForEach(warnings, id: \.self) { warning in
```

`warnings` 是 `:2481` 的 `snapshot.state.warningTexts`，定义在 `mini-ninebot/Shared/NinebotModels.swift:1513-1527`，四条中文告警（`:1516` `"电量低于 15%，建议尽快充电"`、`:1518`、`:1521`、`:1524`）。中文串本身就是列表身份。两条告警文案改成一样 → SwiftUI 里 id 重复。

8. `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:2977`

```swift
                ForEach(analysis.insightTexts, id: \.self) { insight in
```

`insightTexts` 来自 `mini-ninebot/Shared/NinebotTripTrend.swift` 的枚举，文案在 `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:3150-3167`。同上，中文串当身份。这一处的修法很直接：`ForEach` 改成遍历枚举（`NinebotTripInsight` 已经是 `Identifiable`，`id` 是 ASCII `rawValue`），而不是遍历它的文案。

### 2.3 B3 · 中文被写进持久化 —— 写入 / 读回站点（29 处）

`NinebotSharedStore` 的 UserDefaults **键全是 ASCII**（`mini-ninebot/Shared/NinebotSharedStore.swift:4-23`，如 `"ninebot.dashboard.snapshot"`），这一条不用担心。**问题在 value**：`NinebotRefreshEvent` 是 `Codable`，它的 `operation` 和 `message` 两个字段装的是中文，会被 JSON 编码进 UserDefaults。

结构定义 `mini-ninebot/Shared/NinebotModels.swift:58-69`：

```swift
struct NinebotRefreshEvent: Codable, Equatable {
    var source: String
    var operation: String
```

`source` 一直是 ASCII（`"App"` / `"Widget"` / `"Shortcut"`），`operation` 一直是中文。

**`operation` 写入点（20 处）**

| 站点 | 写入的值 |
| --- | --- |
| `mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:270`、`:274` | `"刷新车况"` |
| `mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:288`、`:292` | `"查询电量"` |
| `mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:315`、`:319` | `"查询位置"` |
| `mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:347`、`:351` | `action.title`（4 条中文，见 B4） |
| `mini-ninebot/NinebotWidgets/NinebotWidgetControlIntents.swift:96`、`:100` | `"刷新车况"` |
| `mini-ninebot/NinebotWidgets/NinebotWidgetControlIntents.swift:128`、`:132` | `action.title`（4 条中文，见 B4） |
| `mini-ninebot/NinebotWidgets/NinebotWidgetProvider.swift:62`、`:82`、`:99` | `"刷新小组件"` |
| `mini-ninebot/mini-ninebot/App/NinebotBackgroundTaskManager.swift:56`、`:72`、`:84` | `"后台刷新"` |
| `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:664`、`:677` | `kind.message`（8 条中文，见 B4） |

代表原文 —— `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:662-669`：

```swift
            store.saveLastAppRefreshEvent(NinebotRefreshEvent(
                source: "App",
                operation: kind.message,
                startedAt: startedAt,
                endedAt: Date(),
                success: true,
                message: statusMessage
            ))
```

这一处最要紧：`kind.message` 就是 `NinebotLoadingOperation` 的中文文案（那个为了修下拉刷新 bug 才抽出来的枚举），它的显示文案被原样落盘了。**Android 侧这里应该存枚举的 ASCII 名，展示时再查文案表**，否则「显示文案」和「持久化格式」被焊在一起，改文案就等于改数据格式。

`mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:347`：

```swift
            recordShortcutEvent(store: store, startedAt: startedAt, operation: action.title, success: true, message: vehicle.name)
```

**`message` 字段里的中文字面量（2 处）**

- `mini-ninebot/mini-ninebot/App/NinebotBackgroundTaskManager.swift:60` → `message: "未配置数据源"`
- `mini-ninebot/NinebotWidgets/NinebotWidgetProvider.swift:66` → `message: "未配置服务器"`

（`message` 的另外两个来源是变量：`statusMessage` 和 `error.localizedDescription`，它们的中文来源见 B4。）

**`Key.lastError` 的中文 value —— 写 3 处 / 读回 4 处（7 处）**

写：

- `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:674` → `store.saveLastError(message)`
- `mini-ninebot/mini-ninebot/App/NinebotBackgroundTaskManager.swift:81` → `store.saveLastError(error.localizedDescription)`
- `mini-ninebot/NinebotWidgets/NinebotWidgetProvider.swift:96` → `store.saveLastError(message)`

读回（跨进程：Widget 扩展读 App 写的值，App 冷启动读上次写的值）：

- `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:167` → `self.errorMessage = store.loadLastError()`
- `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:507` → `lastError: errorMessage ?? store.loadLastError()`
- `mini-ninebot/NinebotWidgets/NinebotWidgetProvider.swift:71`、`:108` → `errorMessage: store.loadLastError()` / `errorMessage: message`

风险形态和 B1 不同：不是判断失效，而是**旧的中文值在 App 升级后依然会被读出来显示**。Android 侧只要有一处按「存的就是当前文案」处理，就会出现新旧文案混排。

### 2.4 B4 · 会流入持久化的中文文案定义点（52 处）

这些文案本身写在源码里、只当文案用，但它们最终会经 B3 的通道落盘。搬进 `strings.xml` 前得先确定「落盘存什么」（→ `## 待定` L1、L2），否则搬完就出现「资源改了、盘里的旧值改不了」。

**`NinebotLoadingOperation.message`（8 条）** —— `mini-ninebot/mini-ninebot/Domain/NinebotLoadingOperation.swift`

`:25` `"正在测试连接"`、`:27` `"正在刷新车况"`、`:29` `"正在更新电池类型"`、`:31` `"正在获取 \(displayMonth) 行程"`、`:33` `"正在解析车辆位置"`、`:35` `"正在开启充电通知"`、`:37` `"正在上报设备 Token"`、`:39` `"正在密码登录"`。

**`NinebotVehicleAction.title`（4 条，被写进 `operation`）** —— `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift`

`:34` `"寻车铃"`、`:35` `"开座桶"`、`:36` `"上电"`、`:37` `"熄火"`。

**`NinebotWidgetVehicleAction.title`（4 条，被写进 `operation`）** —— `mini-ninebot/NinebotWidgets/NinebotWidgetControlIntents.swift`

`:13` `"寻车"`、`:14` `"开座桶"`、`:15` `"开锁"`、`:16` `"关锁"`。

注意这四条和上面四条**指同一批指令但用词不同**（寻车铃/寻车、上电/开锁、熄火/关锁），落盘后是两套值 → `## 待定` L11。

**`NinebotVehicleAction.resultTitle`（4 条，经 `statusMessage` 写进 `message`）** —— 同文件 `:43-46`

`"寻车铃已发送"`、`"开座桶指令已发送"`、`"上电指令已发送"`、`"熄火指令已发送"`。

**`statusMessage` 赋值点（14 处，全部经 `:668` 写进 `message`）** —— `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift`

`:230` `"服务器配置已保存"`、`:238` `"服务器连接正常"`、`:250` `"已更新 \(...)"`、`:273` `"已更新\(chemistry.title)电池参数"`、`:293` `"\(...) 暂无行程"`、`:295` `"已获取 \(...) \(page.total) 条行程"`、`:306` `"车辆位置已解析"`、`:317` `"充电通知已开启"`、`:319` `"已允许通知，系统返回设备 Token 后会自动上报"`、`:331` `"设备 Token 已上报"`、`:367` `"登录成功"`、`:464` `"骑行记录已保存"`、`:470` `"骑行记录已删除"`、`:485` `"截图录屏保护已开启"` / `"截图录屏保护已关闭"`。

**中文 `errorDescription`（18 处，经 `error.localizedDescription` 写进 `message` 和 `lastError`）**

| 类型 | 位置 |
| --- | --- |
| `NinebotInputError` | `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:15`、`:17`、`:19` |
| `AppleGeocodingError` | `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:729`、`:731` |
| `NinebotShortcutError` | `mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:12`、`:14` |
| `NinebotWidgetIntentError` | `mini-ninebot/NinebotWidgets/NinebotWidgetControlIntents.swift:186`、`:188` |
| `NinebotPushError` | `mini-ninebot/mini-ninebot/App/NinebotPushManager.swift:14`、`:16`、`:18`、`:20` |
| `NinebotServerError` | `mini-ninebot/Shared/NinebotServerClient.swift:12`、`:14`、`:120`、`:123`、`:353` |

### 2.5 B5 · Siri 语音短语（56 处 / 55 条去重）

`mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift` 的 `AppShortcutsProvider.appShortcuts`：

- `:133-141`（9 条，刷新车况）
- `:150-155`（6 条，查电量）
- `:164-169`（6 条，查位置）
- `:178-183`（6 条，寻车）
- `:192-197`（6 条，开座桶）
- `:206-211`（6 条，上电）
- `:220-225`（6 条，熄火）
- `:234-239`（6 条，开始记录）
- `:248-252`（5 条，行程）

代表原文 `:133-136`：

```swift
                "\(.applicationName)刷新车况",
                "用\(.applicationName)刷新车况",
                "在\(.applicationName)刷新车况",
                "让\(.applicationName)刷新车况",
```

**为什么归 B**：这些不是给人看的文案，是拿去和**语音输入做匹配**的输入语法。当成显示文案搬进 `strings.xml` 再随手改措辞，等于把语音入口改掉了 —— 界面上什么都看不出来。同一组里的 9 条也不是重复文案，是刻意穷举的同义说法，不能合并去重。

同文件里各 Intent 的 `title` / `shortTitle` / `IntentDescription`（如 `:20` `"刷新九号车况"`、`:143` `"刷新车况"`、`:21` `"刷新已登录九号车辆的电量、续航和状态。"`）是显示文案，属 A 类。

### 2.6 B6 · 服务端下发的中文（1 处，不能进 `strings.xml`）

`mini-ninebot/Shared/NinebotServerClient.swift:350-354`：

```swift
        let error = object["error"]?.objectValue
        let message = error?["message"]?.stringValue
            ?? error?["code"]?.stringValue
            ?? "NinePlus 服务器请求失败"
        throw NinebotServerError.server(message)
```

服务端返回的 `error.message` 原样抛出、原样显示。`Tests/NineBotCoreTests/ServerClientTests.swift:208` 断言 `"设备离线"`、`:535` 断言 `"账号或密码错误"` —— 这两条中文**不在 App 源码里**，来自服务端。同理车辆名（`:750` `"我的九号"`）、车型（`:751`）、位置描述（`:1000` `"陆家嘴"`）也来自服务端。

只有 `:353` 那条兜底文案是 App 的、可以进 `strings.xml`。清点时别把服务端下发的中文误算成漏抽的字面量。

### 2.7 已核实**不存在**的 B 类形态

按判据逐条扫过，以下四类在本仓库里是空的，不用花时间：

| 判据 | 扫描命令 | 结果 |
| --- | --- | --- |
| `switch` 的 `case` 是中文字符串 | `rg -n 'case\s+"[^"]*\p{Han}'` | 0 命中 |
| 字典的**键**是中文 | `rg -n '"[^"]*\p{Han}[^"]*"\s*:'` | 命中全是三元表达式和 `friendlyRawFieldName` 的 value，无中文键 |
| 中文当参数发给服务端 | `rg -n '(URLQueryItem\|addValue\|setValue\|httpBody\|value:)[^)]*\p{Han}'` | 0 个网络站点命中 |
| 中文参与排序比较 | `rg -n '(sorted\|filter\|first\(where\|firstIndex\|allSatisfy)[^)]*\p{Han}'` | 0 命中（B2 那 6 处是间接的，靠读调用链找到的，不是这条命中的） |

`contains(` / `hasPrefix(` / `hasSuffix(` / `range(of:` 带中文：App 代码里已清零（唯一残留是 `NinebotLoadingOperation.swift:7` 注释里记录的那个历史写法），命中的 6 处都在 `Tests/`，见第 6 节。

---

## 3 · C 类 · 带插值或单位（69 条）

搬到 `strings.xml` 要改成占位符。逐条列出，标明占位符类型和数量。

### 3.1 空格约定 —— 先看这个

项目习惯是「数字和单位之间带一个半角空格」：`12.3 km`、`45 分钟`、`52.3 V`。这个空格集中在 `mini-ninebot/Shared/NinebotFormatting.swift:135-147`：

```swift
func formatNumber(
    _ value: Double?,
    unit: String,
    maximumFractionDigits: Int = 6,
    minimumFractionDigits: Int = 0
) -> String {
    guard let value else { return "--\(unit)" }
```

调用方把空格写进 `unit` 参数里：`:70` `" km"`、`:78` `" Wh"`、`:86` `" km/h"`、`:90` `" G"`、`:116` `" 小时"`、`:118` `" 分钟"`。**例外**：`:82` `formatPercent` 用 `"%"`，不带空格。

> **AAPT2 会吃掉前导空格。** `<string name="unit_km"> km</string>` 编译后是 `"km"`，渲染成 `12.3km`。凡是资源值以空格开头/结尾，必须用双引号包住整个值：`<string name="unit_km">" km"</string>`。空格在字符串中间（如 `%1$s 分钟`）不受影响。这正是「漏了会显示成 12.3km」的成因。

单位在 Android 侧建议不进 `strings.xml`，直接做成格式化函数的常量，理由：它不是文案而是排版规则，而且 `%1$s km` 这种 key 数量会爆炸。这属于实现选择而不是产品决定，但涉及 key 规模，一并写进 `## 待定` L6。

### 3.2 逐条清单

占位符类型按 Android 写法标注：`%1$s`（字符串 / 已格式化好的数值）、`%1$d`（整数）。iOS 侧数值大多先经 `NumberFormatter` 变成 `String` 再插值，所以多数是 `%1$s` 而不是 `%1$.1f`。

**语序警告**：下面标了 ⚠ 的条目，中文语序和英文不同，占位符位置不能照抄。

| # | 位置 | 原文 | 占位符 |
| --- | --- | --- | --- |
| 1 | `NinebotWidgetControlIntents.swift:28`、`NinebotAppIntents.swift:26` | `"\(vehicleName) 车况已刷新"` | 1 × `%1$s` |
| 2 | `NinebotWidgetControlIntents.swift:39` | `"\(vehicleName) 寻车指令已发送"` | 1 × `%1$s` |
| 3 | `NinebotWidgetControlIntents.swift:51`、`NinebotAppIntents.swift:72` | `"\(vehicleName) 开座桶指令已发送"` | 1 × `%1$s` |
| 4 | `NinebotWidgetControlIntents.swift:63` | `"\(vehicleName) 开锁指令已发送"` | 1 × `%1$s` |
| 5 | `NinebotWidgetControlIntents.swift:75` | `"\(vehicleName) 关锁指令已发送"` | 1 × `%1$s` |
| 6 | `NinebotAppIntents.swift:60` | `"\(vehicleName) 寻车铃已发送"` | 1 × `%1$s` |
| 7 | `NinebotAppIntents.swift:84` | `"\(vehicleName) 上电指令已发送"` | 1 × `%1$s` |
| 8 | `NinebotAppIntents.swift:96` | `"\(vehicleName) 熄火指令已发送"` | 1 × `%1$s` |
| 9 | `NinebotAppIntents.swift:287` | `"\(name) 当前电量 \(battery)，预估续航 \(range)，状态 \(power)。"` | 4 × `%1$s`~`%4$s` ⚠ |
| 10 | `NinebotAppIntents.swift:314` | `"\(name) 位置：\(loc)。更新于 \(time)。"` | 3 × `%1$s`~`%3$s` ⚠ |
| 11 | `NinebotWidgets.swift:356` | `"\(minutes)分"` | 1 × `%1$d`，**无空格**（与 `formatDuration` 的 `" 分钟"` 不一致） |
| 12 | `NinebotWidgets.swift:705`、`:875` | `"\(formatWidgetTime(...)) 更新"` | 1 × `%1$s` ⚠ 时间在前 |
| 13 | `NinebotWidgets.swift:1272` | `"\(estimatedRangeShortText(state))(预估)"` | 1 × `%1$s`，半角括号紧贴 |
| 14 | `NinebotWidgets.swift:1317` | `"充电 \(state.estimatedFullChargeTimeText)"` | 1 × `%1$s` |
| 15 | `NinebotWidgets.swift:1325` | `"\(estimatedRangeText(...)) · 已充满"` | 1 × `%1$s`，分隔符 `·` 两侧各一空格 |
| 16 | `NinebotWidgets.swift:1328` | `"充电中 · \(...)充满"` | 1 × `%1$s`，**占位符和「充满」之间无空格**（与 #23 不一致） |
| 17 | `NinebotModels.swift:1059` | `"\(batteryCycleCount) 次"` | 1 × `%1$d` |
| 18 | `NinebotModels.swift:1188` | `"充电中 · 约 \(estimatedFullChargeTimeText) 充满"` | 1 × `%1$s` |
| 19 | `NinebotModels.swift:1293` | `"实测预测误差 · \(verifiedCount) 次已验证行程"` | 1 × `%1$d` |
| 20 | `NinebotModels.swift:1295` | `"算法服务端 · \(sampleCount) 次有效行程"` | 1 × `%1$d` |
| 21 | `NinebotModels.swift:1357` | `"算法服务端结合官方预估和 \(Self.sampleText(sampleCount)) 持续校准。"` | 1 × `%1$s`（嵌套，见 #24） |
| 22 | `NinebotModels.swift:1359` | `"服务端默认算法基于 \(Self.sampleText(sampleCount)) 计算。"` | 1 × `%1$s`（嵌套） |
| 23 | `NinebotModels.swift:1391` | `"\(numberText(value, 1)) km/日"` | 1 × `%1$s` + 单位 `km/日` |
| 24 | `NinebotModels.swift:1464` | `"约 \(fullChargeTimeText) 充满，\(fullChargeClockText) 左右"` | 2 × `%1$s`/`%2$s` ⚠ |
| 25 | `NinebotModels.swift:1473` | `"当前 \(battery)%，建议尽快充电"` | 1 × `%1$d`，紧跟 `%` → XML 里要写 `%1$d%%` |
| 26 | `NinebotModels.swift:1491` | `"当前 \(battery)%，续航约 \(enduranceText)"` | `%1$d%%` + `%2$s` ⚠ |
| 27 | `NinebotModels.swift:1500` | `"车辆已停放，续航约 \(enduranceText)"` | 1 × `%1$s` |
| 28 | `NinebotModels.swift:1530` | `"\($0) 次有效行程"` | 1 × `%1$d`（`sampleText`，被 #21/#22 嵌套） |
| 29 | `NinebotModels.swift:1703` | `"\(decimalFormatter.string(...) ?? "--") 小时"` | 1 × `%1$s` + `" 小时"` |
| 30 | `NinebotModels.swift:1705` | `"\(decimalFormatter.string(...) ?? "--") 分钟"` | 1 × `%1$s` + `" 分钟"` |
| 31 | `NinebotModels.swift:1772` | `"\(numberText(days, 1)) 天"` | 1 × `%1$s` + `" 天"` |
| 32 | `NinebotModels.swift:1774` | `"\(numberText(hours, 1)) 小时"` | 1 × `%1$s` + `" 小时"` |
| 33 | `NinebotModels.swift:1776` | `"\(numberText(minutes, 0)) 分钟"` | 1 × `%1$s` + `" 分钟"` |
| 34 | `NinebotDashboardView.swift:616` | `"保存后按\(selection.title)计算续航与充电时间"` | 1 × `%1$s`，**占位符两侧都无空格** ⚠ |
| 35 | `NinebotDashboardView.swift:618` | `"当前生效：\(effectiveTitle) · \(specificationText)"` | 2 × `%1$s`/`%2$s` |
| 36 | `NinebotDashboardView.swift:1357` | `"当前 \(tripMonthDisplayName(...))"` | 1 × `%1$s` |
| 37 | `NinebotDashboardView.swift:1372` | `"获取 \(tripMonthDisplayName(...))"` | 1 × `%1$s` |
| 38 | `NinebotDashboardView.swift:1524` | `"\(value) 账号"` | 1 × `%1$s`（同时属 B2） |
| 39 | `NinebotDashboardView.swift:1531` | `"\(fallback) 账号"` | 1 × `%1$s`（同时属 B1/B2） |
| 40 | `NinebotDashboardView.swift:1688`、`:3373` | `"更新 \(formatDate(...))"` | 1 × `%1$s` ⚠ |
| 41 | `NinebotDashboardView.swift:1838` | `"电量进度 \(Int(value * 100))%"` | `%1$d%%`（a11y 标签） |
| 42 | `NinebotDashboardView.swift:1936` | `"约 \(state.estimatedFullChargeTimeText) 充满"` | 1 × `%1$s` ⚠ 中文包夹 |
| 43 | `NinebotDashboardView.swift:2124` | `"更新自\(formatTime(...))"` | 1 × `%1$s`，**无空格** |
| 44 | `NinebotDashboardView.swift:2473` | `"剩余电量 \(Int(batteryFraction * 100))%"` | `%1$d%%` |
| 45 | `NinebotDashboardView.swift:2634`、`:2761` | `"\(observedRangeSampleCount) 次"` | 1 × `%1$d` |
| 46 | `NinebotDashboardView.swift:2873` | `"最近 \(visibleRecords.count) 天"` | 1 × `%1$d` ⚠ |
| 47 | `NinebotDashboardView.swift:2901`、`:3202` | `"\(records.count) 天"` | 1 × `%1$d` |
| 48 | `NinebotDashboardView.swift:2935` | `"最近 \(analysis.recentRides.count) 次"` | 1 × `%1$d` ⚠ |
| 49 | `NinebotDashboardView.swift:3010` | `"\(records.count) 次"` | 1 × `%1$d` |
| 50 | `NinebotDashboardView.swift:3025` | `"\(records.filter { ... }.count) 次"` | 1 × `%1$d` |
| 51 | `NinebotDashboardView.swift:3667` | `"\(vehicle.model) · 更新 \(formatTime(...))"` | 2 × `%1$s`/`%2$s` |
| 52 | `NinebotDashboardView.swift:3932` | `"\(tripMonthDisplayName(...)) 暂无行程"` | 1 × `%1$s` |
| 53 | `NinebotDashboardView.swift:4021`、`NinebotRecordingView.swift:985` | `"行程 \(index + 1)"` | 1 × `%1$d` |
| 54 | `NinebotDashboardView.swift:4027` | `"结束 \($0.formatted(.dateTime.hour().minute()))"` | 1 × `%1$s` ⚠ |
| 55 | `NinebotDashboardView.swift:4240` | `"\(localRecord.trackPointCount) 个"` | 1 × `%1$d` |
| 56 | `NinebotRecordingView.swift:381` | `"\(points.count) 点"` | 1 × `%1$d` |
| 57 | `NinebotRecordingView.swift:704` | `"\(record.trackPointCount) 点"` | 1 × `%1$d` |
| 58 | `NinebotRecordingView.swift:838` | `"\(record.trackPointCount) 个"` | 1 × `%1$d`（和 #57 同一个数据，量词不同） |
| 59 | `NinebotRecordingView.swift:862` | `"\(record.trackCoordinates.count) 点"` | 1 × `%1$d` |
| 60 | `NinebotSettingsView.swift:192` | `"服务器已配置 · \(pushDeviceToken == nil ? "APNs 未上报" : "APNs 已就绪")"` | 1 × `%1$s`，嵌套两条 A 类文案 |
| 61 | `NinebotSettingsView.swift:755` | `"车辆 \(vehicleCount) 台"` | 1 × `%1$d` ⚠ 量词后置 |
| 62 | `NinebotSettingsView.swift:1090` | `"车况更新 \(formatDiagnosticsDate(...))"` | 1 × `%1$s` ⚠ |
| 63 | `NinebotViewModel.swift:250` | `"已更新 \(timeFormatter.string(...))"` | 1 × `%1$s` ⚠ |
| 64 | `NinebotViewModel.swift:273` | `"已更新\(chemistry.title)电池参数"` | 1 × `%1$s`，**两侧无空格**、中文包夹 ⚠ |
| 65 | `NinebotViewModel.swift:293` | `"\(displayMonth(month)) 暂无行程"` | 1 × `%1$s` |
| 66 | `NinebotViewModel.swift:295` | `"已获取 \(displayMonth(month)) \(page.total) 条行程"` | `%1$s` + `%2$d` ⚠ |
| 67 | `NinebotViewModel.swift:527` | `"服务器 · \(baseURLString.trimmed)"` | 1 × `%1$s` |
| 68 | `NinebotViewModel.swift:693` | `"\(year)年\(monthValue)月"` | 2 × `%1$s`/`%2$s`，**无空格** ⚠ 纯中文语序 |
| 69 | `NinebotLoadingOperation.swift:31` | `"正在获取 \(displayMonth) 行程"` | 1 × `%1$s` ⚠ 中文包夹（同时属 B4） |

### 3.3 C 类里已经不一致的地方

搬迁时会撞上这些，先记下来：

- **同一个「小时/分钟」有两套实现**：`NinebotFormatting.swift:113-119` 的 `formatDuration`（分钟位 0 位小数、按 0 位小数判桶）和 `NinebotModels.swift:1697-1706` 的 `NinebotVehicleState.durationText`（1 位小数、按 1 位小数判桶）。输出形状一样，进位阈值不同（`59.9` 分钟前者出 `1 小时`，后者出 `59.9 分钟`）。Android 侧照搬时要明确留哪个 → `## 待定` L10。
- **空格不一致**：#11 `"\(minutes)分"`、#16 `"...\(x)充满"`、#43 `"更新自\(x)"`、#64 `"已更新\(x)电池参数"`、#68 `"\(year)年\(month)月"` 都不带空格，其余带。
- **量词不一致**：轨迹点数在 `NinebotRecordingView.swift:704` 是「点」，在 `:838` 和 `NinebotDashboardView.swift:4240` 是「个」，是同一个 `trackPointCount`。

---

## 4 · D 类 · 已经做成枚举 + 文案表的部分（93 处）

领域层抽取过一轮，一批中文从「散落在计算属性的 if 链里」变成了「枚举定义在 Shared，文案表单独一处」。**Android 侧照同样的形状做**：`enum class` 携带 `@StringRes` 或配一张 `when` 文案表，规则和文案分离。

再次强调：这 93 处文案已经计入 A/B/C，不另计。

### 4.1 枚举 → 文案表 对应关系

| 枚举 | 定义位置 | 文案表位置 | 文案条数 | 形态 |
| --- | --- | --- | --- | --- |
| `NinebotTripInsight` | `mini-ninebot/Shared/NinebotTripTrend.swift:6-22` | `mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:3150-3167`（`private extension`） | 6 | ✅ **最干净的样板**：文案在界面层的 private extension，规则和阈值在 `NinebotTripTrend.swift:40-48`、`:129-159` |
| `NinebotPowerStatus` | `mini-ninebot/Shared/NinebotChargingStatus.swift:9-17` | `mini-ninebot/Shared/NinebotModels.swift:1095-1103`（`powerText`） | 5 | 文案仍在 Shared，未挪到界面层 |
| `NinebotChargingState` | 同上 `:20-26` | `NinebotModels.swift:1185-1192`（`chargeSummaryText`）、`:1194-1201`（`chargingStateText`） | 8 | 一个枚举两张文案表 |
| `NinebotChargeEstimate` | 同上 `:29-42` | `NinebotModels.swift:1135-1142`、`:1168-1175` | 6 | 两张表 |
| `NinebotChargeClock` | 同上 `:45-51` | `NinebotModels.swift:1144-1150`、`:1177-1183` | 2 | 两张表 |
| `NinebotRangeEstimateQuality` | `mini-ninebot/Shared/NinebotRangeEstimate.swift:8-20` | `NinebotModels.swift:1308-1321`（`rangeModelInsightText`） | 5 | |
| `NinebotRangeAccuracyDetail` | 同上 `:23-32` | `NinebotModels.swift:1290-1301` | 4 | 含 2 条 C 类插值 |
| `NinebotLocalEstimateBasis` | 同上 `:35-42` | `NinebotModels.swift:1354-1363` | 3 | 含 2 条 C 类插值 |
| `NinebotHistoryPeriod` | `mini-ninebot/Shared/NinebotHistoryPeriod.swift:10-45` | `NinebotModels.swift:1767-1778`（`periodText`） | 4 | 含 3 条 C 类插值；判桶阈值 `:18-25` |
| `NinebotLoadingOperation` | `mini-ninebot/mini-ninebot/Domain/NinebotLoadingOperation.swift:9-59` | 同文件 `:22-43`（`message`） | 8 | 文案挂在枚举自身；`:50-58` 的 `showsDashboardRefreshIndicator` 是「不靠文案判断」的样板 |
| `NinebotVehicleAction` | `mini-ninebot/mini-ninebot/App/NinebotViewModel.swift:24-107` | 同文件 `:32-88`（6 张表：`title`/`resultTitle`/`loadingTitle`/`subtitle`/`confirmationTitle`/`confirmationMessage`） | 24 | 文案挂在枚举自身 |
| `NinebotBatteryChemistry` | `mini-ninebot/Shared/NinebotModels.swift:160-182` | 同文件 `:167-181`（`title`/`detail`） | 6 | |
| `NinebotBatteryChemistryInfo` | 同上 `:184-217` | 同上 `:192-198`（`effectiveTitle`） | 3 | ✅ 值得学：`switch` 的 case 是 `NinebotBatteryChemistry.lithium.rawValue` 这种 ASCII 常量，**没有拿中文去比** |
| `RecordingGPSQuality` | 枚举在 Recorder 侧 | `mini-ninebot/mini-ninebot/App/NinebotRecordingView.swift:91-100`（`extension`） | 5 | ✅ 界面层 extension，形态同 `NinebotTripInsight` |
| `NinebotWidgetVehicleAction` | `mini-ninebot/NinebotWidgets/NinebotWidgetControlIntents.swift:5-19` | 同文件 `:11-18`（`title`） | 4 | 和 `NinebotVehicleAction` 重复且用词不同 |

合计 93。

### 4.2 三处「长得像 D 类但没抽」的反例

同一件事（车辆当前状态该显示什么）在仓库里有**五套并行的 if 链**，各自带自己的一份中文、各自的优先级顺序：

| 实现 | 位置 | 条数 | 优先级顺序 | 用词 |
| --- | --- | --- | --- | --- |
| `NinebotVehicleState.powerText` | `NinebotModels.swift:1095-1103` | 5 | 由 `NinebotPowerStatus` 决定（满电 > 充电 > 离线 > 上电/熄火） | 已上电 / 已熄火 |
| `compactVehicleStatusText` | `NinebotDashboardView.swift:4942-4956` | 4 | 满电 > 充电 > 上锁 > 未上锁 | 已上锁 / 未上锁 |
| `widgetStatusText` | `NinebotWidgets.swift:1333-1340` | 5 | 满电 > 充电 > **上电** > 上锁 > 未上锁 | 混用 |
| `MediumWidgetStatusPill.statusText` | `NinebotWidgets.swift:800-806` | 4 | 满电 > 充电 > 上锁 > 未上锁 | 电量已充满 / 正在充电 / 守卫模式已开启 / 车辆未上锁 |
| `compactWidgetStatus` | `NinebotWidgets.swift:1312-1320` | 2 | 满电 > 充电 > `health.title` | 已充满 |

另外 `NinebotVehicleHealth`（`NinebotModels.swift:1450-1511`）是同样的形态但更彻底没抽：一条 6 分支的 if 链，每个分支现场构造 `title` + `message` 共 12 条中文，其中 4 条带插值。它和上面五套是第六个版本。

Android 侧把这些各自照搬会把不一致固化下来；合并成一个枚举就得先定哪套是对的 → `## 待定` L3、L4。

---

## 5 · 重复文案清单

### 5.1 完全相同、应该合并成一个 key（139 条重复字面量，下面列出现 ≥ 3 次的）

| 出现次数 | 文案 | 建议 key | 位置（截断） |
| --- | --- | --- | --- |
| 18 | `电池温度` | `field_battery_temperature` | `NinebotWidgets.swift:241`；`NinebotDashboardView.swift:3745`、`:4984-4987`、`:4992-4995`、`:4998-5001`、`:5011-5014` |
| 13 | `电池电压` | `field_battery_voltage` | `NinebotDashboardView.swift:3744`、`:4980-4983`、`:4990-4991`、`:4996-4997`、`:5007-5010` |
| 10 | `已充满` | `status_charge_full` | `NinebotModels.swift:1097`、`:1172`、`:1180`、`:1187`、`:1196`、`:1454`；`NinebotWidgets.swift:1314`、`:1334`；`NinebotDashboardView.swift:692`、`:4944` |
| 9 | `刷新车况` | 见下方注 | `NinebotWidgetControlIntents.swift:22`、`:96`、`:100`；`NinebotWidgets.swift:62`、`:66`；`NinebotAppIntents.swift:143`、`:270`、`:274`；`NinebotSettingsView.swift:155` |
| 7 | `充电中` | `status_charging` | `NinebotModels.swift:1098`、`:1197`、`:1463`；`NinebotWidgets.swift:189`、`:260`、`:1335`；`NinebotDashboardView.swift:4947` |
| 7 | `行程` | `nav_trips` | `ContentView.swift:42`；`NinebotAppIntents.swift:254`；`NinebotDashboardView.swift:771`、`:1275`、`:1322`、`:2249`、`:2556` |
| 6 | `接口未返回` | `common_no_data_from_api` | `NinebotModels.swift:1048`、`:1053`、`:1058`、`:1063`、`:1080`、`:1085` |
| 5 | `充电功率` | `field_charging_power` | `NinebotWidgets.swift:240`；`NinebotDashboardView.swift:971`、`:3749`、`:5021`、`:5022` |
| 5 | `时长` | `common_duration` | `NinebotRecordingView.swift:333`、`:834`；`NinebotDashboardView.swift:4112`、`:4233`、`:5036` |
| 5 | `暂无车辆` | `common_no_vehicle` | `NinebotWidgets.swift:503`、`:738`、`:920`；`NinebotViewModel.swift:503`；`NinebotRecordingView.swift:135` |
| 5 | `最大 G` | `rec_max_g` | `NinebotRecordingView.swift:331`、`:837`；`NinebotDashboardView.swift:3024`、`:4239`、`:4304` |
| 5 | `最快` | `common_fastest` | `NinebotRecordingView.swift:836`；`NinebotDashboardView.swift:4284`、`:4303`、`:4359`、`:4458` |
| 5 | `温度` | `field_temperature` | `NinebotWidgets.swift:316`；`NinebotDashboardView.swift:717`、`:1987`、`:5088`、`:5089` |
| 5 | `电量` | `field_battery` | `NinebotDashboardView.swift:770`、`:1737`、`:3743`、`:4974`、`:5194` |
| 5 | `里程` | `field_mileage` | `NinebotDashboardView.swift:4111`、`:4196`、`:5031`、`:5057`、`:5058` |
| 4 | `AI 预估续航` | `field_ai_range` | `NinebotDashboardView.swift:4969-4972` |
| 4 | `寻车` | `action_find_short` | `NinebotWidgetControlIntents.swift:13`；`NinebotWidgets.swift:118`、`:1058`；`NinebotDashboardView.swift:3399` |
| 4 | `开座桶` | `action_open_bucket_short` | `NinebotWidgetControlIntents.swift:14`；`NinebotWidgets.swift:104`；`NinebotAppIntents.swift:199`；`NinebotViewModel.swift:35` |
| 4 | `打开座桶` | `action_open_bucket` | `NinebotWidgetControlIntents.swift:44`；`NinebotWidgets.swift:108`；`NinebotSettingsView.swift:159`；`NinebotViewModel.swift:62` |
| 4 | `接口轨迹` | `field_api_track` | `NinebotDashboardView.swift:4348`、`:5076-5078` |
| 4 | `未充电` | `status_not_charging` | `NinebotModels.swift:1137`、`:1170`、`:1189`、`:1198` |
| 4 | `未知` | `common_unknown` | `NinebotFormatting.swift:150`；`NinebotModels.swift:1090`、`:1120`、`:1199` |
| 4 | `电压` / `纬度` / `经度` / `能耗` / `速度` | `field_*` | 各 4 处，均在 `NinebotDashboardView.swift`（`:716`/`:1072`/`:1073`/`:4067`/`:4069` 等）+ 字段表 |
| 3 | `上电` `充电状态` `充电速度` `关锁` `刷新小组件` `剩余充电时间` `后台刷新` `寻车铃` `寻车鸣笛` `已上锁` `座桶` `开始` `开始时间` `开锁` `循环次数` `我的` `最近骑行` `未绑定账号` `本月日均` `查询位置` `查询电量` `正在充电` `熄火` `用电` `电池管理` `电源状态` `算法预估` `结束` `结束时间` `行程均速` `轨迹点` | — | 各 3 处 |

精确分布：出现 > 1 次的字面量共 **139 条**，其中出现 ≥ 3 次的 58 条（上表覆盖），恰好 2 次的 81 条（`保存`、`取消`、`关闭`、`复制`、`已复制`、`测试`、`我的九号`、`服务器地址`、`访问口令（可选）`、`http://服务器IP:19009`、`滑动开锁`、`滑动关锁`、`已超过 80%`、`计算中`、`官方预估`、`锂电池`、`铅酸电池` …）。完整名单可由本文档 0 节的脚本口径复现。

> **`刷新车况` 的 9 处不能一律合并。** 其中 `NinebotWidgetControlIntents.swift:96`、`:100` 和 `NinebotAppIntents.swift:270`、`:274` 是 B3 的持久化值，`NinebotAppIntents.swift:143` 是 Siri 的 `shortTitle`，剩下 4 处是显示文案。合并 key 之前先把 B3 那 4 处改成 ASCII 标识。同理 `查询电量`、`查询位置`、`寻车铃`/`开座桶`/`上电`/`熄火` 也各自跨了显示和持久化两种用途。

### 5.2 只差标点或空格、应该统一（4 组）

| 组 | 写法 A | 写法 B | 差异 |
| --- | --- | --- | --- |
| 删除确认 | `"删除这条记录"` `NinebotRecordingView.swift:595` | `"删除这条记录？"` `:629` | 一个问号（按钮 vs 对话框标题，可能是有意的，但 key 要分开命名而不是靠标点区分） |
| 开座桶确认 | `"打开座桶"` `NinebotViewModel.swift:62`（+3 处） | `"打开座桶？"` `NinebotViewModel.swift:71` | 同上 |
| 小时单位 | `" 小时"` `NinebotFormatting.swift:116` | `NinebotModels.swift:1703` 内联的 `" 小时"` | 两套实现（见 3.3） |
| 分钟单位 | `" 分钟"` `NinebotFormatting.swift:118` | `NinebotModels.swift:1705` 内联的 `" 分钟"` | 同上 |

### 5.3 语义相同但用词不同（不是重复文案，是不一致，要人拍板）

- 指令名：`寻车铃`（`NinebotViewModel.swift:34`）vs `寻车`（`NinebotWidgetControlIntents.swift:13`）；`上电`（`:36`）vs `开锁`（`:15`）；`熄火`（`:37`）vs `关锁`（`:16`）。
- 锁车状态**三套用词**：`已锁`/`未锁`/`未知`（`NinebotModels.swift:1090-1091` 的 `lockText`）vs `已上锁`/`未上锁`（`NinebotDashboardView.swift:4950`、`:4953`；`NinebotWidgets.swift:1337-1338`）vs `已上锁`/`已解锁`/`锁车未知`（`NinebotDashboardView.swift:1874-1875` 的 `lockTitle`）。第三套的「已解锁」只在这一处出现。
- 未连接态：`未配置服务器`（`NinebotWidgetProvider.swift:66`、`NinebotDashboardView.swift:5104`）vs `服务器未配置`（`NinebotViewModel.swift:527`）vs `未配置数据源`（`NinebotBackgroundTaskManager.swift:60`）。
- 轨迹点量词：`点` vs `个`（见 3.3）。

→ `## 待定` L11。

---

## 6 · 测试里钉死的文案（68 处，不是 B 类，是安全网）

`Tests/` 下有 68 处断言直接写了中文期望值。改文案会让测试**变红**，不会静默失效 —— 这是好事，不归 B 类，而是「怎么验证没漏」的现成工具（见第 9 节）。

按文件：

| 文件 | 处数 | 断言内容 |
| --- | --- | --- |
| `Tests/NineBotCoreTests/ChargingStatusTests.swift` | 22 | `:61-65` `powerText` 五态、`:78-81` `chargingStateText` 四态、`:86-89` `chargeSummaryText`、`:121-124`、`:138`、`:172`、`:181-183` 时长文案 |
| `Tests/NineBotCoreTests/FormattingTests.swift` | 10 | `:60-74` `formatDuration` 的小时/分钟进位、`:86-88` `boolText` |
| `Tests/NineBotCoreTests/HistoryPeriodTests.swift` | 9 | `:64-69`、`:76-77`、`:84` 天/小时/分钟判桶边界 |
| `Tests/NineBotCoreTests/ModelCodingTests.swift` | 8 | `:247`、`:249`、`:262` 电池类型、`:763`、`:816` `periodText`、`:819`/`:823`/`:827` 单位后缀 |
| `Tests/NineBotCoreTests/VehicleStateTests.swift` | 8 | `:72-76` `powerText`、`:80-82` `lockText` |
| `Tests/NineBotCoreTests/RangeEstimateTests.swift` | 7 | `:90`、`:113`、`:119`、`:128`、`:140`、`:166`、`:173` 续航算法文案 |
| `Tests/NineBotCoreTests/ServerClientTests.swift` | 4 | `:331`、`:332` 错误文案；`:923`、`:941` 子串断言 |

**其中 6 处是子串断言**，比等值断言更脆（改了空格或分隔符也会红，但红得不明显）：

```
Tests/NineBotCoreTests/ChargingStatusTests.swift:89
        XCTAssertTrue(state(battery: 50, isCharging: true).chargeSummaryText.hasPrefix("充电中 · 约 "))
Tests/NineBotCoreTests/ModelCodingTests.swift:819
        XCTAssertEqual(minutes?.hasSuffix(" 分钟"), true)
Tests/NineBotCoreTests/ModelCodingTests.swift:823
        XCTAssertEqual(hours?.hasSuffix(" 小时"), true)
Tests/NineBotCoreTests/ModelCodingTests.swift:827
        XCTAssertEqual(days?.hasSuffix(" 天"), true)
Tests/NineBotCoreTests/ServerClientTests.swift:923
        XCTAssertTrue(message.contains("车辆状态"), message)
Tests/NineBotCoreTests/ServerClientTests.swift:941
        XCTAssertTrue(message.contains("电池数据"), message)
```

`ChargingStatusTests.swift:89` 和 `ModelCodingTests.swift:819/823/827` 正好在守 3.1 节那个空格约定 —— 这四条断言是「12.3 km 不能变成 12.3km」现成的护栏，Android 侧应该移植。

另有 7 处断言的是**服务端下发或夹具里的**中文（`ServerClientTests.swift:208`、`:232`、`:333`、`:535`、`:750`、`:751`、`:1000`），不是 App 文案，移植时不要当资源处理。

---

## 7 · key 命名方案

### 7.1 命名规则

```
<模块>_<对象>[_<用途>][_fmt]
```

1. 全小写 `snake_case`。不用驼峰，不用连字符。
2. **模块段取自白名单**，只有这些前缀合法：

   | 前缀 | 覆盖范围 |
   | --- | --- |
   | `common_` | 跨模块复用（保存 / 取消 / 关闭 / 复制 / 未知 / 暂无车辆） |
   | `nav_` | 底部标签栏和导航标题 |
   | `dash_` | 车控首页（Hero、控制、地图、位置卡） |
   | `battery_` | 电池详情、电池类型设置 |
   | `trips_` | 行程列表、月份筛选 |
   | `trend_` | 趋势分析 |
   | `ride_` | 单次行程详情 |
   | `rec_` | 本地记录（GPS、轨迹、导出） |
   | `settings_` | 我的、连接设置 |
   | `diag_` | 诊断中心 |
   | `login_` | 登录页 |
   | `widget_` | 桌面小组件 |
   | `island_` | 充电实时活动 / 灵动岛对应物 |
   | `intent_` | 快捷指令 / App Actions 的展示名 |
   | `action_` | 车辆指令（D 类枚举 `NinebotVehicleAction`） |
   | `status_` | 状态类文案（D 类，powerStatus / chargingState / rangeQuality / historyPeriod / gpsQuality / tripInsight） |
   | `err_` | 错误提示 |
   | `field_` | 原始字段名映射表 |
   | `unit_` | 单位（带前导空格，值必须加引号） |

3. **带占位符的 key 一律以 `_fmt` 结尾**，不带占位符的一律不带。这样看 key 就知道该用 `getString(id)` 还是 `getString(id, args)`，少一类崩溃。
4. **D 类枚举的文案 key = `status_<枚举名>_<case 名>`**，一个 case 一个 key，绝不为了省 key 把两个 case 合并 —— 合并了就没法用穷尽 `when` 兜住新增的 case（见第 9 节）。同一个枚举的多张文案表用后缀区分：`status_charge_estimate_full_summary` vs `status_charge_estimate_full_clock`。
5. **相同文案跨模块出现 → 提到 `common_`，全仓库只留一个 key**（对应 5.1 的清单）。但 5.1 注里那几条跨了「显示」和「持久化」两种用途的，先拆用途再合并 key。
6. **不允许在代码里拼接两条资源**。`"服务器 · " + url` 这种一律走 `_fmt`，因为分隔符和空格属于文案的一部分。
7. 无障碍标签用 `_a11y` 后缀，和视觉文案分开（iOS 侧 `NinebotDashboardView.swift:1838`、`:1649`、`NinebotSettingsView.swift:300`、`:755` 是这类）。
8. 单位 key 的值必须用双引号包住（AAPT2 会吃前导空格，见 3.1）。

### 7.2 样例 `strings.xml`（32 条，A/B/C/D 各取几条）

不是完整清单 —— 638 条的逐条落地是实施阶段的事。这里只固化命名形状和几个坑的写法。

```xml
<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">

    <!-- ============ A 类 · 纯显示 ============ -->
    <!-- ContentView.swift:34,42,50,60 -->
    <string name="nav_control">车控</string>
    <string name="nav_trips">行程</string>
    <string name="nav_recording">记录</string>
    <string name="nav_profile">我的</string>
    <!-- 5.1 的高频合并项 -->
    <string name="common_unknown">未知</string>
    <string name="common_no_vehicle">暂无车辆</string>
    <string name="common_no_data_from_api">接口未返回</string>
    <!-- NinebotDashboardView.swift:5104,5107 空态 -->
    <string name="dash_empty_no_vehicle_title">暂无车辆数据</string>
    <string name="dash_empty_no_server_desc">到“我的”填写服务器地址并绑定账号后即可读取车辆</string>
    <!-- NinebotSettingsView.swift:1206 -->
    <string name="diag_raw_field_desc">复制当前车辆、状态、电池和行程返回值，方便排查字段。</string>
    <!-- NinebotDashboardView.swift:4974,5047,5062 原始字段表；见 L7 -->
    <string name="field_battery">电量</string>
    <string name="field_latitude">纬度</string>
    <string name="field_power_status">电源状态</string>

    <!-- ============ D 类 · 枚举文案表 ============ -->
    <!-- 一个 case 一个 key。NinebotChargingStatus.swift:9-17 → NinebotModels.swift:1095-1103 -->
    <string name="status_power_fully_charged">已充满</string>
    <string name="status_power_charging">充电中</string>
    <string name="status_power_offline">离线</string>
    <string name="status_power_powered_on">已上电</string>
    <string name="status_power_powered_off">已熄火</string>
    <!-- NinebotTripTrend.swift:6-22 → NinebotDashboardView.swift:3150-3167 -->
    <string name="status_trip_insight_long_ride_dominates">有长距离单次骑行，续航预估会更依赖最近行程样本。</string>
    <string name="status_trip_insight_normal">当前趋势正常，继续积累行程后可以看到更稳定的变化。</string>
    <!-- NinebotViewModel.swift:34-37 · 同一枚举的多张表用后缀区分 -->
    <string name="action_bell_title">寻车铃</string>
    <string name="action_bell_result">寻车铃已发送</string>
    <string name="action_bell_loading">正在寻车鸣笛</string>
    <string name="action_bell_confirm_message">车辆会发出提示音。</string>

    <!-- ============ C 类 · 占位符 ============ -->
    <!-- 单位：值必须加引号，否则 AAPT2 吃掉前导空格 → "12.3km" -->
    <string name="unit_km">" km"</string>
    <string name="unit_minute">" 分钟"</string>
    <string name="unit_hour">" 小时"</string>
    <!-- NinebotModels.swift:1188 · 中文包夹，占位符在中间 -->
    <string name="status_charge_summary_charging_fmt">充电中 · 约 <xliff:g id="duration" example="45 分钟">%1$s</xliff:g> 充满</string>
    <!-- NinebotModels.swift:1491 · %% 转义 + 两个占位符，中文语序 -->
    <string name="status_health_low_battery_message_fmt">当前 <xliff:g id="percent" example="22">%1$d</xliff:g>%%，续航约 <xliff:g id="range" example="18.4 km">%2$s</xliff:g></string>
    <!-- NinebotViewModel.swift:693 · 纯中文语序，占位符两侧无空格 -->
    <string name="trips_month_display_fmt"><xliff:g id="year">%1$s</xliff:g>年<xliff:g id="month">%2$s</xliff:g>月</string>
    <!-- NinebotSettingsView.swift:755 · 量词后置 -->
    <string name="diag_vehicle_count_a11y_fmt">车辆 <xliff:g id="count">%1$d</xliff:g> 台</string>
    <!-- NinebotAppIntents.swift:26 -->
    <string name="intent_refresh_done_fmt"><xliff:g id="vehicle">%1$s</xliff:g> 车况已刷新</string>

    <!-- ============ B 类 · 只有「显示」那一半进这里 ============ -->
    <!-- NinebotViewModel.swift:184 · 判断改走 hasBoundAccount:Boolean，
         这个 key 只负责显示；NinebotSettingsView.swift:1084 那处 == 比较必须删掉 -->
    <string name="settings_account_unbound">未绑定账号</string>
    <!-- NinebotDashboardView.swift:1533 · 分组键改走 accountId，不再用这个串 -->
    <string name="dash_vehicle_picker_current_account">当前九号账号</string>

</resources>
```

`unit_*` 三条在 3.1 节里建议不进资源、直接做成格式化函数的常量，样例里保留是为了演示引号写法。哪种做法进正式实现见 `## 待定` L6。

---

## 8 · 实施顺序建议

顺序的依据只有一条：**B 类决定数据结构，A/C/D 只是搬字符串。数据结构没定就搬文案，等于把「显示文案」和「持久化格式」焊死，后面每改一个字都要写迁移。** 所以 B 排最前。

### 第 0 步 · 先立规矩（0.5 天）

1. 把 7.1 的命名规则写进 `CONTRIBUTING.md` 或 Android 侧的 `docs/`。
2. 建 `unit_*` 的引号约定 + 3.1 那个 AAPT2 陷阱的单元测试：`assertEquals("12.3 km", formatDistance(12.3))`、`assertEquals("45 分钟", formatDuration(45.0))`。这两条断言在 iOS 侧已经存在（`Tests/NineBotCoreTests/FormattingTests.swift:60`、`ModelCodingTests.swift:819`），直接移植。
3. 上第 9 步的 CI grep 闸门（此时全仓库都是 Kotlin 新代码，闸门从 0 违规起步，比事后补便宜得多）。

### 第 1 步 · 拆 B 类（3-4 天，不搬任何 strings.xml）

按危险度倒序：

1. **B1 的 2 处**（`NinebotSettingsView.swift:1084`、`NinebotDashboardView.swift:1530`）：`NinebotDiagnosticsSnapshot` 加 `hasBoundAccount: Boolean`，两处比较全删。文案照旧显示。
2. **B2 的 6 处**：
   - `:1481` / `:1496` 的分组：分组键换成账号标识本身（`vehicleAccountTitle` 里 `:1500-1518` 那 17 个 ASCII 候选 key 取出来的原始 `value`），标题只做显示。
   - `:1998`、`:4079` 的 `id`：换成枚举或稳定的 ASCII 标识（`ChargingMetric` / `RideDisplayMetric` 都是 3 个固定项，直接做成 enum）。
   - `:2519` 的 `warnings`：`warningTexts: [String]` 改成 `warnings: [NinebotVehicleWarning]`（枚举），`ForEach` 遍历枚举。这一步顺手把 `NinebotModels.swift:1513-1527` 也变成 D 类形状。
   - `:2977` 的 `insightTexts`：`NinebotTripInsight` 已经是 `Identifiable`（`NinebotTripTrend.swift:21`，`id` 是 ASCII `rawValue`），`ForEach` 直接遍历 `insights` 而不是 `insightTexts`。**这一处成本最低、收益最直接。**
3. **B3 / B4**：`RefreshEvent.operation` 从中文改成 ASCII 枚举名（`refresh_dashboard`、`sync_widget`、`background_refresh`、`vehicle_action_bell` …），展示时查文案表。同时决定旧数据怎么办 → 这是 `## 待定` L2，**不要自己定**。
4. **B5 的 56 条 Siri 短语**：Android 的 App Actions 走 `shortcuts.xml` + capability，短语的组织方式和 iOS 不同 → `## 待定` L5，第 1 步先跳过。
5. **B6**：确认服务端下发的中文一律走「原样显示」通道，不进资源、不做兜底替换。

**B 类怎么处理（枚举 vs 常量）是需要拍板的，见 `## 待定` L1。** 上面写的「改成枚举」是按已有先例（`NinebotLoadingOperation`）推的默认方向，不是决定。

### 第 2 步 · D 类 93 处（2-3 天）

照 4.1 表逐个枚举做成 `enum class X { A, B }` + `@StringRes` 映射（或 `when` 文案表）。顺序：先做已经是干净形态的（`NinebotTripInsight`、`RecordingGPSQuality`），把形状固化成模板，再做 `NinebotModels.swift` 里那批文案还挂在 Shared 层的。

`4.2` 那五套并行状态文案 + `NinebotVehicleHealth` 要不要合并成一个枚举，是 `## 待定` L3、L4，**卡住就先各自照搬**，别在这一步做产品决策。

### 第 3 步 · A 类 455 条（3-5 天）

纯机械，按 1.1 的模块分批，一个模块一个 PR。合并 5.1 的重复项（注意那条注：跨用途的先别合）。

`friendlyRawFieldName` 那 115 处单独一批 —— 它占 A 类的 1/4，而且如果「原始字段调试面板」被砍掉（`docs/pending-decisions.md` 的 D4），整表作废。**建议放到最后做**，等 D4 有结论。

### 第 4 步 · C 类 69 条（2 天）

逐条对照第 3 节的表改占位符。三件必须逐条核的事：

1. **空格**：占位符和中文之间有没有空格，照原文，不要「顺手统一」（3.3 列了 5 处本来就没空格的）。
2. **`%` 转义**：#25、#26、#41、#44 四条里数字后面紧跟 `%`，XML 里必须写 `%%`。漏了 `getString` 直接抛 `UnknownFormatConversionException`。
3. **语序**：⚠ 标记的 18 条，占位符位置和英语相反或被中文包夹（`"正在获取 %1$s 行程"`、`"已更新%1$s电池参数"`、`"%1$s年%2$s月"`）。用 `%1$s`/`%2$s` 位置化占位符，绝不用 `%s`。

### 第 5 步 · 收口（1 天）

CI 闸门从「警告」转「阻断」，跑一遍第 9 节的四种检查。

---

## 9 · 怎么验证没漏（能在编译期或测试里暴露的手段）

按「能不能挡住」排序，前两条是硬的，后两条是补充。

### 9.1 类型约束 —— 编译期挡住（最硬）

把接受文案的参数从 `String` 改成 `@StringRes Int`：

```kotlin
// 之前：谁都能塞字面量
@Composable fun MetricTile(title: String, value: String)
// 之后：塞中文字面量直接编译不过
@Composable fun MetricTile(@StringRes titleRes: Int, value: String)
```

这条覆盖不到「用 `stringResource()` 取出来后再拼字符串」的情况，所以要配 9.2。

### 9.2 枚举穷尽性 —— 编译期挡住

D 类的每个枚举，文案映射写成**没有 `else` 分支的 `when`**：

```kotlin
val NinebotPowerStatus.labelRes: Int get() = when (this) {
    FULLY_CHARGED -> R.string.status_power_fully_charged
    CHARGING      -> R.string.status_power_charging
    OFFLINE       -> R.string.status_power_offline
    POWERED_ON    -> R.string.status_power_powered_on
    POWERED_OFF   -> R.string.status_power_powered_off
    // 故意不写 else：新增一个 case，这里编译报错
}
```

Kotlin 对 `enum class` / `sealed` 的穷尽 `when` 在有返回值时是强制的 —— 新增状态忘了配文案，编译期就红。这正是 7.1 规则 4「一个 case 一个 key、不合并」的原因：合并了就没法用这条。

### 9.3 CI grep 闸门 —— 提交时挡住

最便宜也最直接：Kotlin 源码里不允许出现中文字面量，只有一个白名单文件例外。

```bash
# 命中即失败。白名单只放 Compose Preview 的假数据
rg -n '"[^"]*\p{Han}' app/src/main/java \
   --glob '!**/PreviewData.kt' \
   && { echo "发现硬编码中文，请移到 strings.xml"; exit 1; }
```

注意 Android Studio 自带的 `HardcodedText` lint **只查 XML 布局，不查 Compose 的 `Text("中文")`**，光靠它兜不住。要么上这条 grep，要么写自定义 Lint detector（成本高一档，好处是能在 IDE 里实时提示）。

### 9.4 测试 —— 运行时挡住

1. **资源覆盖测试**：对每个 D 类枚举跑参数化测试，断言每个 case 的 `context.getString(labelRes)` 非空白，且**同一枚举内两个 case 不共用同一个资源 id**（共用了会让 9.2 的穷尽性形同虚设，也会在按文案做 key 的列表里静默合并 —— 就是 B2 那类 bug）。
2. **格式化字符串参数数量测试**：遍历所有 `_fmt` 结尾的资源，解析出占位符个数和类型，和调用点声明的参数对上。挡的是「改文案时少写一个 `%2$s`」。
3. **移植 iOS 那 68 处断言**（第 6 节）：`ChargingStatusTests` 22 条、`FormattingTests` 10 条、`HistoryPeriodTests` 9 条、`VehicleStateTests` 8 条是现成的文案 + 单位 + 空格护栏，直接抄成 Kotlin 测试，一条不落。其中 `ChargingStatusTests.swift:89`、`ModelCodingTests.swift:819/823/827` 四条专门守 3.1 的空格约定。
4. **持久化 schema 测试**：断言写进 DataStore/SharedPreferences 的 `operation` 字段匹配 `^[a-z_]+$`（不含中文），再加一条「读到旧的中文值不崩」的解码测试。挡的是 B3 那条通道被重新打开。

---

## 待定

需要人拍板的，一条都没在上面替你定。条目用 **L** 前缀（L = 文案），跨阶段的通用决策在 [pending-decisions.md](./pending-decisions.md) 里用 D 前缀，两套不冲突。

**L1 · B 类的改造手法：枚举、常量，还是稳定 ID？**
现状：`NinebotLoadingOperation`（`mini-ninebot/mini-ninebot/Domain/NinebotLoadingOperation.swift`）是唯一改过的，走的是「枚举 + 文案表」。剩下的 B1/B2 共 8 处还没改。
分歧点：枚举最彻底（编译期能兜住新增 case，见 9.2），但每处要新增一个类型；`const val ACCOUNT_UNBOUND = "未绑定账号"` 最省事，可是只把字面量搬到一个地方，比较本身还在拿中文比，改文案照样静默出错；「稳定 ID」（比如给分组键换成账号标识）改动最小但只适用于 B2 那种间接场景。
要问的：这 8 处统一用一种，还是按场景分开？如果按已有先例走枚举，`NinebotVehicleWarning`、`ChargingMetric`、`RideDisplayMetric` 三个新枚举要不要放进 Shared 层（跨 Widget 复用）还是留在界面层？

**L2 · 持久化里的中文（`RefreshEvent.operation`）换成 ASCII 后，旧数据怎么办？**
现状：20 处写入点把中文写进 UserDefaults 的 JSON（见 2.3）。Android 侧是全新的库，不存在旧数据。
分歧点：如果 Android 从第一天就存 ASCII 枚举名，那没有迁移问题；但 iOS 侧要不要一起改？不改的话两端的诊断记录格式不同，将来做「诊断信息上报」时对不上。
要问的：iOS 侧一起改吗？只改 Android 的话，接受两端诊断格式不一致吗？

**L3 · 五套并行的车辆状态文案，哪套是对的？**
现状：`powerText`、`compactVehicleStatusText`、`widgetStatusText`、`MediumWidgetStatusPill.statusText`、`compactWidgetStatus` 各有一套用词和优先级（4.2 的表）。`widgetStatusText` 把「上电」排在「上锁」前面，`compactVehicleStatusText` 完全不提上电。
分歧点：合并成一个枚举能少 20 处文案、少一类不一致，但会改变某些场景下小组件显示的字（比如现在满电时首页显示「已充满」、中号小组件显示「电量已充满」）。
要问的：合并吗？合并的话以哪套用词为准？还是保留「首页/小组件/灵动岛各一套」的现状？

**L4 · `NinebotVehicleHealth` 要不要照 D 类抽成枚举？**
现状：`mini-ninebot/Shared/NinebotModels.swift:1450-1511`，6 分支 if 链，现场构造 12 条中文（含 4 条插值），另有 `NinebotVehicleHealthLevel` 枚举只管颜色不管文案。
分歧点：抽成枚举后形状和其他 D 类一致、可测；但它是唯一一个 title + message 成对出现的，枚举要带两个 `@StringRes`，模板和别的不一样。
要问的：抽还是照搬？

**L5 · 55 条 Siri 短语怎么落到 Android？**
现状：`mini-ninebot/mini-ninebot/App/NinebotAppIntents.swift:133-252`，9 个入口共 55 条穷举的同义说法。
分歧点：Android 的 App Actions 用 `shortcuts.xml` + `capability` + built-in intent，短语由 Google Assistant 侧的 BII 语法决定，不是 App 写死一串。照搬 55 条既没地方放也没意义；但完全不做就丢了语音入口。
要问的：Android 侧要不要做语音入口？要做的话是走 App Actions（需要 Assistant 支持，工期不小）还是只做桌面快捷方式（`shortcuts.xml` 的静态 shortcut，几乎零成本但没有语音）？

**L6 · 单位（`" km"` / `" 分钟"`）进 `strings.xml` 还是留在代码里？**
现状：iOS 侧作为 `formatNumber(unit:)` 的参数传入（`mini-ninebot/Shared/NinebotFormatting.swift:70-90`、`:116-118`）。
分歧点：进资源便于将来加英文（英文的 `km` 前也有空格，但 `%` 前没有，规则不同）；留代码里少一堆 key、也躲开 AAPT2 吃空格那个坑（3.1）。
要问的：会有英文版吗？不会的话留代码里更省事。

**L7 · `friendlyRawFieldName` 那 125 条字段名映射进资源还是进代码 Map？**
现状：`mini-ninebot/mini-ninebot/App/NinebotDashboardView.swift:4967-5093`，115 处、约 100 条去重文案，占 A 类的四分之一。键是 ASCII 接口字段名。
分歧点：进 `strings.xml` 是 125 条 key（`field_*` 段一下占掉一大块），且这些「文案」其实是技术术语，不是给普通用户看的；留在代码里当 `Map<String, Int>` 或 `Map<String, String>` 更贴合它的用途。
另外它依赖 `docs/pending-decisions.md` 的 **D4（原始字段调试面板要不要做）**：D4 砍掉的话整表作废。
要问的：先定 D4。D4 保留的话，这表进资源还是进代码？

**L8 · 服务端下发的中文要不要做兜底？**
现状：`mini-ninebot/Shared/NinebotServerClient.swift:350-354` 把服务端的 `error.message` 原样显示，只有全都取不到时才用 App 自己的 `"NinePlus 服务器请求失败"`。
分歧点：社区服务端返回的 message 可能是英文、可能是技术堆栈、也可能是空。App 侧要不要按错误码映射成自己的中文文案（那就得维护一张错误码表）？
要问的：见过服务端返回难看的 message 吗？没见过就保持原样显示。

**L9 · `Info.plist` 那两条权限说明怎么落地？**
现状：`mini-ninebot/Config/mini-ninebot-Info.plist:37`（Siri）、`:39`（定位）。
分歧点：Android 没有对应物。定位那条会变成 App 自己画的权限说明弹窗（minSdk 33 下前台定位 + 后台记录还涉及 `ACCESS_BACKGROUND_LOCATION` 的二次授权，文案不止一条）。Siri 那条如果 L5 决定不做语音入口，就直接作废。
要问的：定位权限的说明弹窗要写几条（首次请求 / 被拒后再请求 / 后台定位）？照抄 iOS 那一条还是重写？

**L10 · 时长格式化留哪个实现？**
现状：`mini-ninebot/Shared/NinebotFormatting.swift:113-119`（`formatDuration`，分钟 0 位小数）和 `mini-ninebot/Shared/NinebotModels.swift:1697-1706`（`durationText`，1 位小数）两套，输出形状一样、进位阈值不同。`59.9` 分钟前者出 `1 小时`、后者出 `59.9 分钟`，两者都有测试钉着（`FormattingTests.swift:72` vs `ChargingStatusTests.swift:182`）。
分歧点：合并成一个就得改掉一批断言和一批界面上的显示值。
要问的：合并吗？合并的话保留几位小数？

**L11 · 同义不同词的几组要不要统一？**
现状（详见 5.3）：`寻车铃`/`寻车`、`上电`/`开锁`、`熄火`/`关锁`（App 一套、Widget 一套）；锁车状态三套用词（`已锁`/`未锁` vs `已上锁`/`未上锁` vs `已上锁`/`已解锁`）；`未配置服务器`/`服务器未配置`/`未配置数据源`；轨迹点的`点`/`个`。
分歧点：统一之后 key 能合并（5.1 里能少十几条），但小组件上的字会变（`寻车` 两个字换成 `寻车铃` 三个字，小尺寸 widget 的排版可能撑不住 —— iOS 侧用短词大概是有意的）。
要问的：哪几组统一、哪几组是有意为之要保留？特别是 Widget 那套短词。

**L12 · 数量文案要不要用 `<plurals>`？**
现状：C 类里有 12 条「数字 + 量词」（`%1$d 次`、`%1$d 天`、`%1$d 点`、`%1$d 台` …）。
分歧点：中文没有单复数，`<plurals>` 只需要 `other` 一项，现在写等于纯开销；但如果将来加英文，这 12 条全要返工成 `<plurals>`。
要问的：和 L6 一起定 —— 会不会有英文版？
