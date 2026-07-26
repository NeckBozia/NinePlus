# 图标清单：SF Symbols → Material Symbols

iOS 侧（`mini-ninebot/`）用的是 Apple SF Symbols，随系统字体分发。Android 侧没有这套字体，每一个都要在 Material Symbols 里找替代物。这份清单把 97 个图标逐个列出来，给出候选名、匹配度、以及它在界面上表达什么。

---

## 一、这份清单是怎么来的

**提取方法**：`mini-ninebot/` 下 26 个 Swift 文件，两种出现形式：

1. `systemImage:` / `systemName:` 参数直接带字面量 —— 260 处
2. `var systemImage: String` 计算属性里 `switch` 返回字面量 —— 14 处，分布在 3 个地方：
   - `App/NinebotRecordingView.swift:102-109` —— `RecordingGPSQuality` 五档 GPS 质量
   - `App/NinebotViewModel.swift:90-96` —— 四个车控指令
   - `NinebotWidgets/NinebotWidgets.swift:1342-1349` —— Widget 状态图标

合计 **274 处引用，去重后 97 个唯一图标**。

第 2 类只用 `systemImage:` 抓不到（写法是 `return "location"`），是单独扫 `return "..."` 字面量补上的 —— `location` 和 `location.slash` 这两个只在那里出现。

**另有 1 个非 SF Symbol 的位图资产**：`Image("LoginVehicle")`（`App/NinebotSettingsView.swift:529`），来自 `mini-ninebot/Assets.xcassets/LoginVehicle.imageset`，直接搬 PNG 即可，不在本清单范围内。

**名字校验方法**：下面每一个 Material Symbols 名字都逐字比对过官方 codepoints 清单（4267 个名字）：

```
https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsOutlined%5BFILL%2CGRAD%2Copsz%2Cwght%5D.codepoints
```

89 个候选名全部命中，**没有需要标「名字待核实」的条目**。要复核就重新拉这个文件比对，方法可重复。

---

## 二、结论摘要

| 匹配度 | 数量 | 含义 |
| --- | --- | --- |
| 直接可用 | 81 | 语义和形状都对得上 |
| 近似可用 | 16 | 语义对，形状有差异，不影响理解 |
| 无对应 | **0** | —— |

**需要定制的图标：0 个。** 97 个 SF Symbol 全都能用 Material Symbols 现成图标覆盖。理由见第五节。

去重到 Material Symbols 后是 **89 个唯一名字**，其中 3 个需要同时准备空心和实心两版（见第七节），**共约 92 个资源文件**。

### 与既有文档的差异

`docs/android-porting-plan.md:79`、`docs/android-implementation-plan.md:117`、`docs/android-porting-plan.md:336` 三处都写着「85 个唯一 SF Symbol、299 处调用，其中约 30–40 个 Material Symbols 缺对应物」，并给「30–40 个定制图标」排了 1 周设计工期，标为关键路径。

本次清点的结果与之不一致，两点都要更正：

- **数量**：97 个唯一图标 / 274 处引用（旧文档 85 / 299）
- **缺对应物**：0 个，不是 30–40 个

那 1 周的图标设计工期和它在关键路径上的位置，可以按 0 定制件重新排。这条影响排期，写进了 `## 待定`。

---

## 三、直接可用（81 个）

「用在哪」一列的文件前缀：`Dash` = `mini-ninebot/App/NinebotDashboardView.swift`，`Set` = `mini-ninebot/App/NinebotSettingsView.swift`，`Rec` = `mini-ninebot/App/NinebotRecordingView.swift`，`W` = `NinebotWidgets/NinebotWidgets.swift`，`Models` = `Shared/NinebotModels.swift`，`VM` = `mini-ninebot/App/NinebotViewModel.swift`，`Tab` = `mini-ninebot/ContentView.swift`。多处使用的只列 2–3 个代表位置。

| SF Symbol | 用在哪（文件:行号 + 语义） | Material Symbols 候选 | 匹配度 | 备注 |
| --- | --- | --- | --- | --- |
| `arrow.clockwise` | `W:62`、`Set:155` —— 「刷新车况」磁贴与快捷指令 | `refresh` | 直接可用 | |
| `arrow.trianglehead.2.clockwise` | `Dash:719`、`Dash:3747` —— 电池「循环」次数 | `autorenew`（备选 `loop`、`cached`） | 直接可用 | 双向循环箭头，语义形状都对 |
| `arrow.up.doc.fill` | `Set:108` —— 按钮「重新上报设备」 | `upload_file`（备选 `file_upload`） | 直接可用 | |
| `arrow.up.forward` | `Rec:239` —— 实时速度卡「MAX xx」前缀 | `north_east`（备选 `arrow_outward`） | 直接可用 | 与 `arrow.up.right` 撞车，见第八节 |
| `arrow.up.right` | `Dash:2900`、`Dash:2956`、`Dash:3200` —— 「最高里程」统计 | `trending_up`（备选 `north_east`） | 直接可用 | 语义是「峰值」，`trending_up` 更贴 |
| `barcode.viewfinder` | `Dash:3802` —— 车辆 VIN 字段 | `barcode_scanner`（备选 `barcode_reader`） | 直接可用 | Symbols 独有，见第七节 |
| `battery.100` | `Dash:1737` 首页 Hero「电量」；`Set:156` 快捷指令「查询电量」；`Models:1456` 健康态「已充满」；`W:1343` | `battery_full` | 直接可用 | |
| `battery.75` | `Dash:975`、`Dash:3762` —— 「充至 80%」预计时间 | `battery_80` | 直接可用 | 文案本身写的是 80%，`battery_80` 比 iOS 原来的 75 档更准 |
| `bell.badge.fill` | `Set:100` —— 按钮「检查权限并上报」 | `notifications_active`（备选 `notification_important`） | 直接可用 | |
| `bell.fill` | `Dash:1089` 地图「寻车鸣笛」；`Dash:3400` 车控盘「寻车」；`W:118`/`W:1058`/`W:1109` 磁贴与 Widget；`VM:92` | `notifications` | 直接可用 | 6 处，全部是寻车 |
| `bicycle` | `W:1160` —— 车辆图片加载失败的兜底图 | `pedal_bike`（备选 `directions_bike`） | 直接可用 | 建议与 `scooter` 统一，见第八节 |
| `bolt.batteryblock.fill` | `Dash:716`、`Dash:1984`、`Dash:3744` 电池「电压」；`W:195` 充电卡 | `battery_charging_full` | 直接可用 | 电池外框 + 内嵌闪电，形状高度一致 |
| `bolt.circle.fill` | `Rec:254`/`Rec:330` 「当前 G」；`Rec:837`、`Dash:3024`/`4239`/`4304` 「最大 G」—— 加速度 | `offline_bolt` | 直接可用 | 实心圆内闪电。与 `bolt.fill` 并列出现，见第八节 |
| `bolt.fill`（充电语义） | `Dash:971`/`1981`/`3749` 「充电功率」；`W:189`/`260`/`156`/`167`/`594` 充电中；`Models:1465` 健康态「充电中」 | `bolt`（备选 `electric_bolt`） | 直接可用 | 另有两种语义，见第八节 |
| `bolt.horizontal.fill` | `Dash:2574` 「本月能耗」；`Dash:2819` 「单公里耗电」；`Dash:4067`/`4114`/`4231` 「能耗」Wh/km | `electric_bolt`（备选 `electric_meter`） | 直接可用 | |
| `calendar` | `Dash:2571`/`2635` 「本月日均」；`Dash:2818` 「活跃天数」；`Dash:2901`/`3202` 「活跃天数」；`W:906` | `calendar_month`（备选 `date_range`） | 直接可用 | `Dash:2275` 那一处语义存疑，见第八节 |
| `chart.bar.xaxis` | `Dash:2899`、`Dash:3201` —— 「日均 / 平均」里程柱状统计 | `bar_chart` | 直接可用 | |
| `chart.xyaxis.line` | `Dash:779` 「等待趋势数据」空态；`Dash:2658` 趋势卡卡头 | `show_chart`（备选 `monitoring`、`timeline`） | 直接可用 | |
| `checkmark` | `Set:487` —— 「保存」按钮 | `check` | 直接可用 | |
| `checkmark.circle.fill` | `Dash:4612`/`4688` 「已复制」；`Set:1398` 成功状态行 | `check_circle` | 直接可用 | |
| `checkmark.shield.fill` | `Models:1501` —— 健康态「状态正常」 | `verified_user` | 直接可用 | 盾牌 + 对勾 |
| `chevron.down` | `Dash:1636` —— 车辆名右侧的「可切换车辆」指示 | `expand_more`（备选 `keyboard_arrow_down`） | 直接可用 | |
| `chevron.down.circle.fill` | `Dash:3971` —— 「显示更多」按钮 | `arrow_drop_down_circle` | 直接可用 | |
| `chevron.right` | 9 处列表跳转指示：`Dash:2256`/`2510`/`2557`/`2682`/`3580`/`3581`/`3675`、`Rec:540`/`992` | `chevron_right`（备选 `keyboard_arrow_right`） | 直接可用 | Android 列表末尾箭头的常规做法 |
| `chevron.up` | `Set:66` —— 「收起」按钮 | `expand_less`（备选 `keyboard_arrow_up`） | 直接可用 | |
| `clock` | `Dash:3317` 「记录周期」；`Dash:3373` 「更新 xx」；`Dash:3770` 「更新时间」；`Set:1090`/`1132` | `schedule` | 直接可用 | 时间家族撞车，见第八节 |
| `clock.arrow.circlepath` | `Dash:1370` 「获取更早月份」按钮；`Dash:2572` 「最近骑行」；`Set:1175` 「历史快照」 | `history` | 直接可用 | 时钟 + 逆时针箭头，形状对得上 |
| `cloud.fill` | `Set:48`/`Set:457` 「服务器地址」输入框；`Set:118` 「连接与通知」入口 | `cloud` | 直接可用 | |
| `doc.on.clipboard.fill` | `Dash:4757` —— 原始返回值复制面板卡头 | `content_paste`（备选 `assignment`） | 直接可用 | |
| `doc.on.doc` | `Dash:4619`、`Dash:4695` —— 「复制」按钮（未点击态） | `content_copy`（FILL 0） | 直接可用 | 与下一行成空心/实心对 |
| `doc.on.doc.fill` | `Dash:4780` 「复制完整返回值」；`Rec:875` 「复制 GPX」；`Set:1213` 「复制全部原始字段」 | `content_copy`（FILL 1，备选 `file_copy`） | 直接可用 | |
| `doc.text.magnifyingglass` | `Set:1086` —— 诊断「详情」（行程详情缓存条数） | `find_in_page`（备选 `plagiarism`） | 直接可用 | |
| `exclamationmark.circle.fill` | `Dash:2520` —— 车况警告文案行 | `error` | 直接可用 | |
| `exclamationmark.triangle.fill` | `Dash:414` 「车辆数据已失效」；`Dash:1882` 「车辆未上电」横幅；`Set:1096`/`1392` 错误行；`Models:1474` 健康态「低电量」；`Rec:108` GPS「定位不可用」 | `warning` | 直接可用 | 6 处，全是警告 |
| `externaldrive.fill` | `Set:1177` —— 「车况缓存」占用字节数 | `hard_drive`（备选 `storage`） | 直接可用 | Symbols 独有，见第七节 |
| `eye.slash.fill` | `Dash:316` 截图保护遮罩提示；`Set:978` 「截图录屏保护」开关 | `visibility_off` | 直接可用 | |
| `gearshape.fill` | `Set:293` —— 登录页右上角「连接设置」 | `settings` | 直接可用 | |
| `info.circle` | `Dash:1782` —— 算法兜底说明按钮 | `info`（FILL 0） | 直接可用 | |
| `info.circle.fill` | `Dash:3657` —— 说明卡的圆形图标 | `info`（FILL 1） | 直接可用 | |
| `iphone` | `Set:234` —— 登录「请输入手机号」输入框 | `smartphone`（备选 `phone_iphone`） | 直接可用 | `phone_iphone` 形状更近，但 Android 产品里放 iPhone 图标不合适 |
| `key.horizontal.fill` | `Set:57`、`Set:466` —— 「访问口令」输入框 | `key`（备选 `vpn_key`） | 直接可用 | Material `key` 本身就是横向的 |
| `link` | `Dash:3025` 「已关联」计数；`Rec:574` 「已关联接口行程」；`Rec:839` 「关联」 | `link` | 直接可用 | |
| `link.badge.plus` | `W:1025` —— Widget 未绑定空态 | `add_link` | 直接可用 | |
| `list.bullet.rectangle` | `Dash:3318` —— 「样本数」 | `list_alt`（备选 `receipt_long`） | 直接可用 | |
| `list.number` | `Dash:2817` —— 「骑行次数」 | `format_list_numbered` | 直接可用 | |
| `location` | `Rec:104` —— GPS 质量「等待 GPS」 | `location_searching`（备选 `near_me` FILL 0） | 直接可用 | `location_searching` 反而比 SF 原图更能表达「正在等」 |
| `location.fill` | `Dash:1052` 地图「我的位置」Marker；`Dash:1077` 「我的距离」；`Dash:3795` 「坐标」；`Rec:406` 「当前位置」Marker；`Set:157` 快捷指令「查询位置」 | `near_me`（备选 `location_on`） | 直接可用 | `near_me` 是实心导航箭头，与 SF 形状一致；用作地图 Marker 时见第七节 |
| `location.slash` | `Rec:107` —— GPS 质量「GPS 弱」 | `location_disabled`（备选 `gps_off`） | 直接可用 | |
| `location.viewfinder` | `Rec:422` —— 「正在获取当前位置」空态 | `my_location`（备选 `point_scan`、`gps_fixed`） | 直接可用 | |
| `lock.fill` | `W:90`/`823`/`1053` 磁贴与 Widget「关锁」；`Set:161` 快捷指令「熄火」；`W:1346`；`VM:95` | `lock` | 直接可用 | `Set:331` 那一处是密码框，语义不同，见第八节 |
| `lock.open.fill` | `W:76`/`821`/`1046` 「开锁」；`Models:1483` 健康态「未锁车」；`W:1347` | `lock_open` | 直接可用 | |
| `map` | `Dash:2139` 地图预览兜底；`Dash:3784`/`3788` 「位置」；`Rec:746` 「这条记录没有轨迹点」 | `map`（FILL 0） | 直接可用 | `Dash:1072`/`3793` 用于「纬度」，语义存疑，见第八节 |
| `map.fill` | `Dash:1099` 「Apple 地图」按钮；`Dash:3791` 「地址来源」；`Dash:4183` 有本地轨迹标记；`Rec:660`；`Set:1085` 「地址」 | `map`（FILL 1） | 直接可用 | `Dash:1073`/`3794` 用于「经度」，语义存疑 |
| `mic.circle.fill` | `Set:150` —— 「打开 Siri 设置」 | `mic`（备选 `keyboard_voice`） | 直接可用 | 图标没问题；这个入口在 Android 对应什么功能本身待定 |
| `network` | `Set:73`、`Set:475` —— 「测试」连接按钮 | `network_check`（备选 `lan`、`public`） | 直接可用 | 语义是「测连通性」，`network_check` 比 `public` 准 |
| `number` | `Dash:3801` 车辆 SN；`Dash:4116` 行程 ID | `numbers`（备选 `tag`） | 直接可用 | |
| `person.crop.circle` | `Tab:60` —— 底部 Tab「我的」 | `account_circle` | 直接可用 | |
| `person.fill` | `Set:1084` —— 诊断「账号」 | `person` | 直接可用 | |
| `photo` | `Dash:3803` —— 车辆图片 URL 字段 | `image`（备选 `photo`） | 直接可用 | |
| `play.circle.fill` | `Rec:762` —— 轨迹回放播放控件 | `play_circle` | 直接可用 | |
| `play.fill` | `Dash:4109`/`4301` 「开始时间 / 开始」；`Rec:717` 地图「开始」Marker；`Rec:832` | `play_arrow` | 直接可用 | 用作地图 Marker 时见第七节 |
| `point.3.connected.trianglepath.dotted` | `Rec:332` 「距离」；`Rec:838`、`Dash:4240` 「轨迹点」；`Dash:3022` 「本地总里程」；`Set:1176` 「本地轨迹」 | `route`（备选 `polyline`） | 直接可用 | 语义是「轨迹 / 折线路径」，`route` 和 `polyline` 都在 Symbols 里 |
| `power` | `Dash:3368` 「电源」；`Dash:3768` 「电源状态」；`W:1345` | `power_settings_new` | 直接可用 | |
| `power.circle.fill` | `Set:160` 快捷指令「上电」；`VM:94` | `power_settings_new` | 直接可用 | Material 无「圆形包裹」变体，靠容器背景补，见第七节 |
| `powerplug.fill` | `Dash:2955` 「平均用电」；`Dash:4068`/`4115`/`4232` 「用电」百分比 | `power`（插头形）（备选 `outlet`、`electrical_services`） | 直接可用 | 注意 Material 的 `power` 是插头，`power_settings_new` 才是电源开关，两者不要混 |
| `questionmark.circle.fill` | `Models:1509` —— 健康态「状态未知」 | `help` | 直接可用 | |
| `scooter` | `Dash:2229` —— 地图上的车辆 Marker | `electric_moped`（备选 `two_wheeler`、`electric_scooter`） | 直接可用 | 三个候选都存在，选哪个取决于车型定位，见 `## 待定` |
| `shippingbox.fill` | `W:104`/`825`/`1057`/`1108` 磁贴与 Widget「开座桶」；`Dash:3422` 车控盘「座桶」；`Set:159`；`VM:93` | `inventory_2`（备选 `package_2`） | 直接可用 | 座桶＝储物箱，方盒子语义对 |
| `speaker.wave.2.fill` | `W:826` —— 中号 Widget「鸣笛」按钮 | `volume_up` | 直接可用 | 同一个「寻车」功能在别处用 `bell.fill`，见第八节 |
| `speedometer` | 14 处：`Dash:1743` Hero「均速」；`Dash:2447`/`2573`/`2633`/`2954`/`3758`/`4069`/`4113`/`4230`/`4303`；`Dash:4438` 极速徽标；`Rec:835`/`966`；`W:907` | `speed` | 直接可用 | 全清单最高频。与 `gauge.with.dots.needle.*` 撞车，见第八节 |
| `stethoscope` | `Set:132` —— 「诊断中心」入口 | `stethoscope` | 直接可用 | 同名同物。Symbols 独有，见第七节 |
| `stop.fill` | `Dash:4110`/`4302` 「结束时间 / 结束」；`Rec:722` 地图「结束」Marker；`Rec:833` | `stop` | 直接可用 | |
| `sun.max.fill` | `Dash:2632` —— 「今日里程」 | `wb_sunny`（备选 `light_mode`） | 直接可用 | |
| `tag.fill` | `Dash:3799` —— 车辆「名称」字段 | `sell`（备选 `label`、`local_offer`） | 直接可用 | `sell` 是斜置吊牌，与 SF 形状最近 |
| `target` | `Dash:2638` 续航准确度说明；`Dash:2760` 「准确率」；`Dash:3757` 「算法参数」 | `target`（备选 `adjust`） | 直接可用 | 同名同物。Symbols 独有，见第七节 |
| `text.bubble.fill` | `Dash:3742` —— 「状态说明」 | `chat_bubble`（备选 `textsms`） | 直接可用 | |
| `thermometer.medium` | `Dash:717`、`Dash:1987`、`Dash:3745` —— 电池「温度」 | `thermometer`（备选 `device_thermostat`） | 直接可用 | Symbols 独有，见第七节 |
| `timer` | `Dash:973`/`3764` 「预计充满」；`Dash:4112`/`4233` 「时长」；`Rec:333`/`834` 「时长」；`Set:1131` 「耗时」 | `timer` | 直接可用 | 同名同物 |
| `trash.fill` | `Rec:595` —— 「删除这条记录」 | `delete` | 直接可用 | |
| `tray.and.arrow.down.fill` | `Set:81` 「保存」按钮；`Rec:1009` 「暂不关联，直接保存」 | `save`（备选 `move_to_inbox`、`download`） | 直接可用 | 两处语义都是「保存」，`save` 比 `download` 准 |
| `xmark.circle` | `Set:1002` —— 「清除当前提示」 | `cancel`（备选 `highlight_off`） | 直接可用 | |

---

## 四、近似可用（16 个）

这一组语义对得上，形状有可见差异，但换上去不影响理解。**这 16 个不需要定制**，和上一组一样直接下资源就能用。

| SF Symbol | 用在哪（文件:行号 + 语义） | Material Symbols 候选 | 匹配度 | 备注 |
| --- | --- | --- | --- | --- |
| `arrow.left.arrow.right` | `Dash:2267` —— 「最近骑行」里程数值卡（主卡） | `swap_horiz`（备选 `compare_arrows`） | 近似可用 | iOS 用双向箭头表示里程，本身就不直观。形状能对上，语义要不要趁移植改，见 `## 待定` |
| `battery.25` | `Models:1492` —— 健康态「电量偏低」（电量 < 25%） | `battery_20`（备选 `battery_low`、`battery_2_bar`） | 近似可用 | Material 电量档位是 20 / 30 / 50 / 60 / 80 / 90，没有 25 档，20 最近 |
| `batteryblock.fill` | `Dash:508` —— 电池详情卡的可折叠卡头 | `battery_std` | 近似可用 | SF 是横向电池块，Material `battery_std` 是竖向。作卡头图标方向差异可接受 |
| `bolt.car.fill` | `Dash:972`/`3761` 「充电速度」；`Dash:3800` 「车型」；`Dash:5163` 车图兜底；`W:940`/`981` 「九号暂无数据」 | 车辆语义 → `electric_moped`；充电语义 → `ev_station` | 近似可用 | 一个图标两种语义混用（车辆本体 vs 充电速度），建议按语境拆两个，见第八节 |
| `bolt.horizontal` | `Set:1130` —— 诊断「来源」（本次刷新的触发来源） | `bolt`（备选 `electric_bolt`） | 近似可用 | 语义是「触发来源」，闪电本身就不贴。与能耗用的 `bolt.horizontal.fill` 撞车 |
| `clock.badge.checkmark` | `Dash:3763` —— 「80% 时间」（充到 80% 的钟点） | `hourglass_check`（备选 `alarm_on`、`event_available`） | 近似可用 | Material 无「时钟 + 角标对勾」，`hourglass_check` 是沙漏 + 对勾，`alarm_on` 是闹钟 + 对勾 |
| `clock.badge.checkmark.fill` | `Dash:974`、`Dash:3765` —— 「满电时间」钟点 | `alarm_on`（备选 `hourglass_check`） | 近似可用 | 与上一行成对，两者要选不同的候选才能区分 |
| `clock.badge.questionmark` | `Dash:976`、`Dash:3766` —— 剩余充电时间（来源不确定时） | `pending`（备选 `hourglass_empty`、`help`） | 近似可用 | Material 无「时钟 + 角标问号」。`pending` 表达「进行中 / 未定」，丢掉了时钟含义 |
| `dot.circle.and.cursorarrow` | `Tab:34` —— 底部 Tab「车控」 | `ads_click`（备选 `touch_app`、`settings_remote`） | 近似可用 | `ads_click` 是光标 + 点击波纹，与 SF 的「圆点 + 光标」构图接近。Tab 图标，值得单独确认 |
| `function` | `Dash:2444`、`Dash:3754` —— 本地预测算法（`predictionModelTitle`） | `functions`（备选 `calculate`） | 近似可用 | SF 是 f(x) 曲线，Material `functions` 是求和符号 Σ。都读作「公式 / 算法」 |
| `gauge.with.dots.needle.33percent` | `Dash:2762` —— 「近期效率」km/% | `speed`（备选 `pace`） | 近似可用 | Material 没有按百分比分档的仪表盘，指针位置信息丢失 |
| `gauge.with.dots.needle.67percent` | `Dash:3023`/`4238` 「本地极速」；`Rec:836` 「最快」；`Tab:50` 底部 Tab「记录」 | `speed`（备选 `pace`、`avg_pace`） | 近似可用 | 与 `speedometer` 落到同一个名字，且并列出现，必须区分，见第八节 |
| `point.topleft.down.curvedto.point.bottomright.up` | `W:908` —— Widget「最近骑行」 | `route`（备选 `polyline`、`trending_flat`） | 近似可用 | SF 是带两个端点的贝塞尔曲线，Material 没有等价物；`route` 语义（一段行程）反而更清楚 |
| `road.lanes` | 11 处：`Dash:1740` Hero「续航」；`Dash:2448`/`2763`/`3320`/`3366`/`3750`/`4111` 里程；`Dash:4014` 行程卡图标；`Dash:2249`、`Tab:42` Tab「行程」；`Set:1174` 「接口行程」 | 里程语义 → `distance`（备选 `straighten`）；导航语义 → `route`（备选 `road`） | 近似可用 | 第二高频。SF 是俯视多车道路面，Material 无等价物。11 处混了两种语义，见第八节 |
| `scope` | `Dash:2634`/`2761` 「有效样本」数；`Rec:105` GPS「校准中」 | `center_focus_weak`（备选 `filter_center_focus`、`adjust`） | 近似可用 | 两种语义差得远（样本量 vs GPS 校准），建议拆开，见第八节 |
| `sparkle.magnifyingglass` | `Dash:2978` —— 趋势分析的洞察文案 | `search_insights`（备选 `insights`、`auto_awesome`） | 近似可用 | Material 无「放大镜 + 星芒」组合。`search_insights` 保留了放大镜，`auto_awesome` 保留了星芒，二者取一 |

---

## 五、无对应（0 个）

**没有需要定制的图标。**

这一组本来是要单独花设计预算的，结果是空的。理由：

1. **97 个 SF Symbol 逐个都找到了可辩护的现成候选**，包括最初看着最难的几个：
   - `stethoscope`、`target`、`thermometer`、`timer` —— Material Symbols 里**同名同物**
   - `barcode.viewfinder` → `barcode_scanner`；`externaldrive.fill` → `hard_drive`；`bolt.batteryblock.fill` → `battery_charging_full` —— 形状高度一致
   - `scooter` → `electric_moped` / `two_wheeler` / `electric_scooter` 三个候选都存在
   - `road.lanes` → `distance` / `route` / `road` / `straighten` 四个候选都存在

2. **本 App 的图标需求集中在电动车仪表盘领域**（电量、充电、EV、里程、地图轨迹、时间、诊断），Material Symbols 在这几块覆盖很密 —— 仅电池相关就有 70 多个名字（`battery_20`…`battery_90`、`battery_charging_*`、`battery_horiz_*`、`battery_vert_*`、`battery_std`、`battery_low`、`battery_alert`、`battery_unknown` 等），EV 相关有 `ev_station`、`ev_charger`、`electric_car`、`electric_moped`、`electric_scooter`、`electric_bike`、`electric_meter`、`charger`、`charging_station`。

3. 第四节那 16 个「近似可用」是形状差异，不是缺失。差异最大的三个（`gauge.with.dots.needle.*` 的指针档位、`clock.badge.*` 的角标、`road.lanes` 的车道面）**丢掉的都是修饰信息，不是主体语义**：仪表盘还是仪表盘，时间还是时间，里程还是里程。配上旁边的中文 title（这个 App 每个图标几乎都带文字标签），识别没有问题。

**唯一真正需要设计出手的，是一件品牌资产不是图标**：`Set:563` 的 `bolt.fill` 用作登录页 App Logo（`NinePlusLoginLogo`，58×58 圆角方块 + 白色闪电，`.weight(.black)`）。这属于品牌标识，不该从图标库拿，写进了 `## 待定`。

---

## 六、分层渲染与多色

**结论：iOS 侧没有任何一处用到 SF Symbols 的多色或分层渲染，Android 侧不需要做叠层。**

全仓库扫过这些 API，命中数为 0：

```
symbolRenderingMode  .hierarchical  .palette  .multicolor
SymbolRenderingMode  symbolVariant  symbolEffect  variableValue
```

274 处引用全部是**单色**，着色统一走 `.foregroundStyle(单个 Color)`。Material Symbols 同样只支持单色，这里是 1:1 对应，没有落差。

有 4 处看着像多色，实际是「容器 + 单色图标」的两层组合，Compose 用 `Box` + 背景就能还原，不涉及图标本身分层：

| 位置 | 构造 | Compose 对应 |
| --- | --- | --- |
| `Dash:1917-1926` | `Circle` 填充 `teslaGreen.opacity(0.16)` + 绿色 `bolt.fill`（带上下浮动动画） | `Box(Modifier.background(green.copy(alpha=0.16f), CircleShape))` + `Icon` |
| `Dash:3653-3661` | `Circle` 填充 `teslaControlBackground` + `info.circle.fill` | 同上 |
| `Dash:4010-4019` | `RoundedRectangle(18, .continuous)` 填充 `teslaGreen.opacity(0.14)` + 绿色 `road.lanes` | `Box` + `RoundedCornerShape(18.dp)` |
| `Set:560-568` | `RoundedRectangle(18, .continuous)` 填充 `loginInk` + 白色 `bolt.fill` | 品牌 Logo，见第五节 |

另外有一批图标是**按状态整体换色**（不是分层）：`Rec:330-333` 的四个 `RecordingMetricTile` 分别传 `.yellow` / `.red` / `teslaGreen` / `teslaSecondaryText`；`RecordingGPSQuality.tint`（`Rec:112-119`）按五档 GPS 质量给整个图标换色。Compose 直接 `Icon(tint = ...)`，一一对应。

---

## 七、Android 侧落地方式

### 7.1 `material-icons-extended` 不够用

`androidx.compose.material:material-icons-extended` 装的是**旧的 Material Icons 集合，不是 Material Symbols**。两点具体问题：

**第一，本清单 89 个候选名里有 10 个它没有。** 拿旧集的官方 codepoints 清单（2235 个名字，`font/MaterialIcons-Regular.codepoints`）比对，这 10 个是 Material Symbols 时代才加的：

```
barcode_scanner   battery_20   battery_80   distance   hard_drive
hourglass_check   search_insights   stethoscope   target   thermometer
```

覆盖的是 VIN 扫码、电量 20/80 档、里程、缓存占用、充电完成时间、趋势洞察、诊断中心、算法准确率、电池温度 —— 都不是边角功能。

**第二，混用两套会看出来。** 旧 Material Icons 和 Material Symbols 是两次独立设计，网格、笔画粗细、圆角处理都不同，也没有可变轴。为了 10 个图标去混两套，等于放弃全局视觉一致性。

结论：**整套走 Material Symbols，不引入 `material-icons-extended`。**

### 7.2 推荐路径：逐个 XML vector drawable

两条路可选，推荐 XML vector drawable（`res/drawable/*.xml`），不是 `ImageVector`。**决定性的理由是 Glance**：

- `docs/android-implementation-plan.md:106` 排了 5.3「桌面 Widget（Glance）」，三种尺寸 + 交互按钮
- Glance 底层是 RemoteViews，`ImageProvider` 只接受 `@DrawableRes` 资源 ID，**不接受 `ImageVector`**
- 本清单至少 12 个图标同时出现在主 App 和 Widget / 磁贴里（`bolt.fill`、`bell.fill`、`lock.fill`、`lock.open.fill`、`shippingbox.fill`、`battery.100`、`power`、`speedometer`、`calendar`、`speaker.wave.2.fill`、`bicycle`、`link.badge.plus`）
- 通知的 `setSmallIcon(iconRes)`（`docs/android-porting-plan.md:250`）同样只吃 drawable 资源

走 `ImageVector` 就得为这 12 个再准备一份 drawable，两份资源手工同步。XML drawable 一份通吃 Compose（`painterResource`）、Glance、通知、快捷方式、地图 Marker。

**取资源**：从 `fonts.google.com/icons` 按图标逐个下 SVG（可在页面上先设定 style / weight / fill / optical size 再导出），或从 `google/material-design-icons` 仓库的 `symbols/web/<name>/materialsymbols<style>/` 目录取。转换用 Android Studio 的 Vector Asset 导入（`File > New > Vector Asset > Local file`），它会直接产出 `<vector>` XML。

**资源组织**：

```
app/src/main/res/drawable/
    ic_battery_full.xml
    ic_bolt.xml
    ic_speed.xml
    ...
```

命名建议 `ic_<material_symbols_名>.xml`，**用 Material 名而不是 SF 名** —— 以后加图标时能直接对上 fonts.google.com 上的名字，不用回来查这张表。

在这之上放一层语义映射，别让业务代码直接写 `R.drawable.ic_speed`：

```kotlin
object NineIcons {
    val AverageSpeed = R.drawable.ic_speed        // speedometer
    val TopSpeed     = R.drawable.ic_avg_pace     // gauge.with.dots.needle.67percent
    val Mileage      = R.drawable.ic_distance     // road.lanes（里程语义）
    val TripEntry    = R.drawable.ic_route        // road.lanes（导航语义）
    // ...
}
```

好处是第八节那些「一个 SF Symbol 两种语义」「两个 SF Symbol 撞一个 Material 名」的决定，集中在一个文件里改，不用翻遍 UI 代码。

**文件数**：89 个唯一 Material 名，其中 3 个要空心 + 实心两版（`info`、`map`、`content_copy` —— iOS 侧同屏并列用了两个变体，见第八节），**共约 92 个 XML 文件**。按每个 1–3 KB 算，总体积 100–250 KB 量级。

### 7.3 备选：内嵌可变字体

把 `MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf` 作为字体资源打进包，用 ligature 渲染图标（写 `Text("battery_full")` 出图标）。

- 优点：一个文件搞定全部 4267 个图标，四个可变轴可在运行时动画（比如充电时让 FILL 从 0 渐变到 1）
- 缺点：字体约 3–4 MB 且无法按用量裁剪（92 个 XML 才 100–250 KB）；Glance / 通知 / 地图 Marker 都用不了字体方案，这几处仍要单独出 drawable；无障碍要手工补 `contentDescription`

除非确定要做可变轴动画，否则 7.2 更划算。这条写进了 `## 待定`。

### 7.4 两个具体的坑

**地图 Marker 要栅格化。** iOS 用 `Marker(_:systemImage:coordinate:)` 直接把 SF Symbol 放进大头针。Google Maps Android SDK 的 `MarkerOptions.icon()` 要 `BitmapDescriptor`，得先把 vector drawable 画到 `Bitmap`（`AppCompatResources.getDrawable()` → `Canvas` → `BitmapDescriptorFactory.fromBitmap()`）。受影响 4 处：

| 位置 | 图标 | 语义 |
| --- | --- | --- |
| `Dash:1052`、`Rec:406` | `location.fill` → `near_me` | 「我的位置」/「当前位置」 |
| `Dash:2229` | `scooter` → `electric_moped` | 地图上的车辆 |
| `Rec:717` | `play.fill` → `play_arrow` | 轨迹「开始」 |
| `Rec:722` | `stop.fill` → `stop` | 轨迹「结束」 |

**磁贴图标被系统强制着色。** `docs/phase1-core-spec.md:921` 已经记了这条：磁贴（Quick Settings Tile）图标只能单色且由系统上色，iOS 用 `.tint` 区分开锁绿 / 关锁灰的做法在 Android 完全丢失。对图标资产的要求是：`lock` 和 `lock_open` 这类成对图标，**光看轮廓就要能区分状态**，不能依赖颜色。这两个 Material 图标本身轮廓差异够大（锁梁开合），没问题。

---

## 八、需要人做判断的两类冲突

这两类不是「找不到图标」，是 iOS 侧原有的图标用法在移植时暴露出的歧义。都汇总进了 `## 待定`，这里给出证据。

### 8.1 一个 SF Symbol 承载多种语义（要拆）

| SF Symbol | 语义 A | 语义 B | 语义 C |
| --- | --- | --- | --- |
| `bolt.fill` | 充电功率 / 充电中（`Dash:971`、`W:189`） | **加速度最大 G**（`Rec:331`） | **App Logo**（`Set:563`） |
| `scope` | 有效样本数（`Dash:2634`/`2761`） | **GPS 校准中**（`Rec:105`） | |
| `lock.fill` | 关锁 / 熄火（`W:90`、`Set:161`） | **登录密码输入框**（`Set:331`） | |
| `map` / `map.fill` | 地图 / 位置（`Dash:2139`/`3784`） | **纬度 / 经度字段**（`Dash:1072`/`1073`、`Dash:3793`/`3794`） | |
| `calendar` | 本月日均 / 活跃天数（`Dash:2571`/`2818`） | **总行程**（`Dash:2275`） | |
| `bolt.horizontal(.fill)` | 能耗 Wh/km（`Dash:2574`，fill 版） | **诊断刷新来源**（`Set:1130`，非 fill 版） | |
| `road.lanes` | 里程数值（`Dash:1740`/`2448`/`4111` 等 7 处） | **行程 Tab / 列表入口**（`Dash:2249`、`Tab:42`、`Dash:4014`） | |
| `gauge.with.dots.needle.67percent` | 本地极速（`Dash:3023`/`4238`、`Rec:836`） | **底部 Tab「记录」**（`Tab:50`） | |
| `bolt.car.fill` | 车型 / 车图兜底（`Dash:3800`/`5163`） | **充电速度**（`Dash:972`/`3761`） | |
| `bell.fill` vs `speaker.wave.2.fill` | 同一个「寻车」功能，主 App 和大号 Widget 用 `bell.fill`，中号 Widget（`W:826`）用 `speaker.wave.2.fill` | | |

另外两处 iOS 原有选择本身就存疑，不是移植带来的：

- `Dash:2275` 用 `calendar`（日历）表示「总行程」里程
- `Dash:2267` 用 `arrow.left.arrow.right`（左右双向箭头）表示「最近骑行」里程
- `Dash:1072`/`1073` 用 `map` / `map.fill` 分别表示「纬度」「经度」，两者只差空心实心

### 8.2 多个 SF Symbol 落到同一个 Material 名（要区分）

按严重程度排：

**① 时间家族 —— 最密集。** `Dash:3763-3766` 四行连续并列：

```
3763  「80% 时间」    clock.badge.checkmark
3764  「预计充满」    timer
3765  「满电时间」    clock.badge.checkmark.fill
3766  「剩余时间」    clock.badge.questionmark
```

再加上 `clock`（更新时间）和 `clock.arrow.circlepath`（历史），6 个 SF 时间图标要在 Material 侧映射成 6 个能相互区分的名字。可用的候选池已核实存在：`schedule`、`timer`、`history`、`alarm_on`、`hourglass_check`、`hourglass_empty`、`pending`、`update`、`av_timer`、`more_time`、`event_available`、`clock_arrow_up`、`clock_arrow_down`、`pending_actions`、`nest_clock_farsight_analog`。够分，但怎么分要设计定。

**② 速度家族。** `speedometer`（14 处）和 `gauge.with.dots.needle.67percent`（4 处）都落到 `speed`，而且**同屏并列**：

- `Rec:835` 「均速」`speedometer` / `Rec:836` 「最快」`gauge.with.dots.needle.67percent`
- `Dash:4230` 「接口速度」`speedometer` / `Dash:4238` 「本地极速」`gauge.with.dots.needle.67percent`

必须区分。三种做法：`speed` 配 FILL 0 / FILL 1；或「最快」改用 `avg_pace` / `pace`；或「最快」用 `speed` + 一个「峰值」修饰（`trending_up`）。

**③ 闪电家族。** `Rec:330` / `Rec:331` **同一行相邻**：

```
330  「当前 G」  bolt.circle.fill  →  offline_bolt
331  「最大 G」  bolt.fill         →  bolt
```

`offline_bolt`（实心圆内闪电）和 `bolt`（裸闪电）轮廓差异够大，按此映射即可，但要确认设计接受。此外 `bolt.horizontal.fill`（能耗）也在这个家族里，映射到 `electric_bolt`。

**④ 靠 FILL 轴区分的 3 组。** iOS 用空心 / 实心成对，Material 只能靠 FILL 轴，视觉差异比 SF 小：

| 空心 | 实心 | Material | 是否同屏并列 |
| --- | --- | --- | --- |
| `map`（`Dash:1072` 纬度） | `map.fill`（`Dash:1073` 经度） | `map` FILL 0 / 1 | **是**，同一 `HStack` |
| `info.circle`（`Dash:1782`） | `info.circle.fill`（`Dash:3657`） | `info` FILL 0 / 1 | 否 |
| `doc.on.doc`（`Dash:4619`） | `doc.on.doc.fill`（`Dash:4780`） | `content_copy` FILL 0 / 1 | 否 |

只有 `map` 那组是并列的，而它同时也是 8.1 里「纬度 / 经度」语义存疑的那一处 —— 如果改成两个真正不同的图标，这个问题一起消掉。

**⑤ 不并列、可以合并的。** 以下撞车不出现在同屏，直接合并到一个资源即可：`arrow.up.right` + `arrow.up.forward` → `trending_up`；`power` + `power.circle.fill` → `power_settings_new`（Material 无圆形包裹变体，需要圆形时靠容器背景补，做法见第六节表格）；`bicycle` + `scooter` → 建议统一到 `electric_moped`。

---

## 九、风格建议

**这是建议，不是决定**，同样写进了 `## 待定`。理由基于对 iOS 侧视觉重量的实测：

| 建议 | 值 | 依据 |
| --- | --- | --- |
| 风格 | **Rounded** | 全仓库 `RoundedRectangle` 的圆角半径分布：18（56 处）、24（29 处）、16（18 处）、22（12 处）、28（5 处）、26（3 处）—— 130 处里 123 处半径 ≥ 16，且几乎全部指定 `style: .continuous`（连续曲率 squircle）。这是一套明确偏软的形状语言，Rounded 的圆头笔画和它同构。Sharp 会打架，Outlined 偏中性但接不住 `.continuous` 的柔和感 |
| `wght` | **500** | 图标字号修饰实测：`.semibold` 147 处、`.medium` 68 处、`.bold` 40 处、`.black` 1 处 —— **没有一处用默认 `.regular`**。SF Symbols 的 `.semibold` 大致对应 Material `wght` 500–600。取 500 作基线，Widget / 磁贴那些小尺寸场景可提到 600 |
| `FILL` | **作状态轴，0 为默认** | 97 个唯一图标里 42 个是 `.fill` 变体（43%），且 iOS 明确用空心 / 实心表达状态（见 8.2 ④）。把 FILL 当状态轴而不是固定值，能省 3 组重复资源，也和 Material 3 的选中态惯例一致 |
| `opsz` | **24**（小尺寸场景 20） | 图标实际渲染尺寸从 `.caption2`（约 11pt）到 `Rec` 的 42pt。绝大多数落在 `.caption`–`.title3`（12–20pt）区间，`opsz 24` 覆盖主体；`Dash:4438` 极速徽标、`Rec` 的 `.caption2` 类小徽标用 `opsz 20` 更清楚 |
| `GRAD` | **0（浅色）/ 25（深色）** | App 是明暗自适应的（`Dash:5160` 的 `prefersDarkImage: colorScheme == .dark`、`W:191` 的 `chargingCardPrimaryText(for: colorScheme)`）。深色底上细笔画会视觉变细，`GRAD 25` 补回来。这条是可选优化，不做也能用 |

一句话：**Material Symbols Rounded，wght 500，opsz 24，FILL 当状态轴。**

---

## 待定

需要人拍板的事项，按优先级排。条目用 **I** 前缀（I = 图标），跨阶段的通用决策在 [pending-decisions.md](./pending-decisions.md) 里用 D 前缀，两套不冲突。

### I1 · 图标设计预算和排期要重排

`docs/android-porting-plan.md:79`、`:336` 和 `docs/android-implementation-plan.md:117` 都写着「约 30–40 个图标缺 Material Symbols 对应物」「定制图标设计 1 周」「在关键路径上」。本次逐个核对的结果是 **0 个缺对应物**，需要设计出手的只有登录页那一件品牌 Logo。

要定的是：这 1 周设计工期取消还是改投别处？关键路径标记是否撤掉？三处文档谁来改？

### I2 · 速度家族怎么区分（`speedometer` vs `gauge.with.dots.needle.*`）

18 处引用落到同一个 `speed`，且 `Rec:835`/`836`、`Dash:4230`/`4238` 是并列出现的「均速 vs 最快」。三个方案：

- (a) `speed` FILL 0（均速）/ FILL 1（极速）—— 资源最省，区分度最弱
- (b) 均速 `speed`，极速 `avg_pace` 或 `pace` —— 区分度好，但 `avg_pace` 字面意思是「平均配速」，和「极速」相反，容易读错
- (c) 均速 `speed`，极速 `speed` + `trending_up` 组合 —— 区分度最好，要做组合图标

### I3 · 时间家族 6 个图标怎么映射

`clock` / `timer` / `clock.arrow.circlepath` / `clock.badge.checkmark` / `clock.badge.checkmark.fill` / `clock.badge.questionmark`。其中后三个在 `Dash:3763-3766` 四行连续并列。

已核实可用的候选池：`schedule`、`timer`、`history`、`alarm_on`、`hourglass_check`、`hourglass_empty`、`pending`、`update`、`av_timer`、`more_time`、`event_available`、`clock_arrow_up`、`clock_arrow_down`、`pending_actions`。要设计挑 6 个并确认相互可辨。

### I4 · iOS 原有的可疑图标用法，照抄还是趁移植修正

五处 iOS 侧图标与语义对不上。照抄能保持两端一致，修正能提升可读性但产生差异（`docs/pending-decisions.md` 里 D2 已经有过同类权衡）：

| 位置 | iOS 现状 | 疑点 |
| --- | --- | --- |
| `Dash:2275` | 「总行程」里程用 `calendar` | 日历表示里程 |
| `Dash:2267` | 「最近骑行」里程用 `arrow.left.arrow.right` | 左右双向箭头表示里程 |
| `Dash:1072`/`1073`、`Dash:3793`/`3794` | 「纬度」`map`、「经度」`map.fill` | 两者只差空心实心，且地图图标不表达经纬度 |
| `Set:1130` | 诊断「来源」用 `bolt.horizontal` | 闪电表示刷新触发来源 |
| `W:826` | 中号 Widget「寻车」用 `speaker.wave.2.fill`，别处同功能用 `bell.fill` | 同一功能两个图标 |

### I5 · 一个 SF Symbol 拆成几个（影响 `NineIcons` 映射层）

- `road.lanes`（11 处）：里程语义 → `distance`，行程导航入口语义 → `route`。拆成 2 个还是统一 1 个？
- `bolt.car.fill`（6 处）：车辆本体 → `electric_moped`，充电速度 → `ev_station`。拆还是不拆？
- `scope`（3 处）：有效样本数 vs GPS 校准中。拆还是不拆？
- `bolt.fill`（13 处）：充电功率 / 最大 G / App Logo 三种。Logo 必须单独出（见 I7），另两种拆不拆？
- `lock.fill`（6 处）：锁车动作 vs 登录密码框。密码框建议改 `password` 或 `key`，要确认。

### I6 · `scooter` 选哪个候选

`electric_moped` / `two_wheeler` / `electric_scooter` 三个都在 Material Symbols 里。取决于九号这台车的产品定位（电动踏板摩托 / 两轮车 / 滑板车）。影响两处：地图车辆 Marker（`Dash:2229`）和车图加载失败兜底（`W:1160` 现在用 `bicycle`，建议一并统一）。这是产品定位问题，不是图标问题。

### I7 · 登录页 App Logo 要单独出设计

`Set:560-568` 的 `NinePlusLoginLogo`：58×58 `RoundedRectangle(18, .continuous)` 填充 `loginInk`，内嵌白色 `bolt.fill`（`.title2.weight(.black)`）。这是品牌标识，不该从图标库拿。是否要设计出一个正式的 App 标记？和 `docs/android-implementation-plan.md:19` 提到的自适应图标（复用根目录 `appicon.PNG`）是同一件事还是两件事？

### I8 · 资源方案二选一

- (a) **逐个 XML vector drawable**，约 92 个文件，100–250 KB —— 本文推荐，理由是 Glance / 通知 / 地图 Marker 只吃 drawable 资源
- (b) **内嵌 Material Symbols 可变字体**，1 个文件 3–4 MB，可运行时动画四个轴，但 Glance / 通知 / Marker 仍需另出 drawable

只有确定要做可变轴动画（比如充电时 FILL 从 0 渐变到 1）才值得考虑 (b)。

### I9 · 风格与可变轴取值

第九节的建议：**Rounded / `wght` 500 / `opsz` 24（小尺寸 20）/ FILL 作状态轴 / `GRAD` 0 浅色·25 深色**。依据是 iOS 侧 130 处圆角里 123 处半径 ≥ 16 且用 `.continuous`，以及图标字重实测无一处用默认 `.regular`（`.semibold` 147 处占多数）。

要设计确认三件事：风格是否用 Rounded；`wght` 500 是否够（对比 iOS 的 `.semibold`）；`GRAD` 深色补偿做不做。

### I10 · `mic.circle.fill` 对应的功能是否保留

`Set:150` 的「打开 Siri 设置」。图标本身 → `mic`，没问题。但 Android 侧对应的是 Google Assistant / App Actions，这个入口保留、改造还是删掉，是功能决策，图标随之定。
