# 社区服务端接口核对

把 iOS 客户端实际调用的每个服务端接口，与社区适配器 [`wuchiawuchi/nineplus-ha-server`](https://github.com/wuchiawuchi/nineplus-ha-server) 的实现逐个对上，回答一个问题：**Android 端照着 iOS 的调用去实现，会不会有接口不存在、路径不一样、或者返回字段被裁掉。**

配套文档：[安卓移植规划](./android-porting-plan.md)、[Phase 0 地基详细规格](./phase0-foundation-spec.md)

## 本次核对的依据

社区服务端源码**核对成功**，全部结论都能落到具体代码行：

| 来源 | 内容 | 获取方式 |
| --- | --- | --- |
| `server.py`（609 行） | 适配器全部路由与实现 | `raw.githubusercontent.com/wuchiawuchi/nineplus-ha-server/main/server.py` |
| `tests/test_server.py`（167 行） | 9 个单测，含轨迹透传断言 | 同上 `tests/test_server.py` |
| `compose.yaml` / `Dockerfile` / `install.sh` / `.env.example` | 部署与环境变量 | 同上 |
| `ninecli` 0.1.7 | 适配器的下游依赖，PyPI wheel 内的 `METADATA`（即其 README）与 `ninecli/bin/ninecli` 二进制 | `pypi.org/pypi/ninecli/json` → wheel |

一个关键前提：**社区服务端本身几乎不做数据加工**，它是一层薄壳，把 HTTP 请求翻译成 `python -m ninecli <cmd> --json` 子进程调用，再把 stdout 的 JSON 原样塞进信封（`server.py:232-292`）。所以「字段有没有被裁掉」这个问题有两层：

- **第一层（server.py）**：已核对完毕，除 `travel-sync` / `prediction` / `prediction-settings` 三个自造响应外，全部原样透传，无字段改写。
- **第二层（ninecli）**：wheel 里是一个 8.9 MB 的 **Go 编译二进制**（`ninecli/__main__.py` 只是 `os.execv` 的壳），**源码不可读**。其 README 对 `--json` 的说明是「emit raw decrypted JSON instead of human-readable output」，倾向于原样透传；但二进制里能提取出 226 个 `json:"..."` Go 结构体标签，其中车辆与登录相关的字段是**有类型结构体**的，存在再序列化时丢字段的可能。这一层的结论只能靠实测，见第四节。

---

## 一、iOS 侧接口全清单

主源文件 `mini-ninebot/Shared/NinebotServerClient.swift`（1109 行）。共 **17 个接口**。

所有请求共用同一个私有 `request(method:path:queryItems:body:)`（`NinebotServerClient.swift:276-317`），所以下面的公共约定只写一次：

**鉴权**（`NinebotServerClient.swift:286-295`）
- `Accept: application/json` 恒定
- `bearerToken` 去空白非空 → `Authorization: Bearer <token>`
- `appSessionToken` 去空白非空 → `X-NinePlus-Session: <token>`（登录后才有）
- 有 body 时加 `Content-Type: application/json`，body 一律是 `[String: String]`（**全部值都是字符串**，见 `NinebotServerClient.swift:280`）

**超时**
- 主 App / App Intents / 后台刷新：`request.timeoutInterval = 20`（`NinebotServerClient.swift:285`），会话是 `URLSession.shared`
- **Widget 扩展另有一套更紧的预算**：`NinebotWidgets/NinebotWidgetProvider.swift:12-18` 与 `NinebotWidgets/NinebotWidgetControlIntents.swift:80-86` 都用 `URLSessionConfiguration.ephemeral`，设 `timeoutIntervalForRequest = 8`、`timeoutIntervalForResource = 12`。注意这里有个覆盖关系：`URLRequest.timeoutInterval`（20）会盖掉会话的 `timeoutIntervalForRequest`（8），但 `timeoutIntervalForResource = 12` 是整次资源加载的硬上限、不可被单请求覆盖。**所以 Widget 侧的实际预算是每请求 12 秒**，而 `fetchDashboard` 一次要发多个请求，整体没有上限保护。Android 的 Glance / Quick Settings Tile 侧要按同样或更紧的预算设计。

**信封解包**（`NinebotServerClient.swift:341-355`）：根对象含 `ok` 键时，`ok == true` 取 `data`（缺失则空对象），否则抛错（消息优先级 `error.message` → `error.code` → 固定文案）；不含 `ok` 键原样返回。非 2xx 先抛 `httpStatus`（`NinebotServerClient.swift:307-309`）。空 body 返回空对象（`NinebotServerClient.swift:311-313`）。

下表的「期望返回形状」写的是 iOS 实际会去读的键，多个键名用 `/` 分隔表示 iOS 两种都认。

### 1. `GET /healthz`

- **调用**：`NinebotServerClient.swift:30-32`
- **参数**：无
- **期望返回**：任意。iOS 只判断 HTTP 状态码，不读任何字段
- **依赖功能**：设置页「测试连接」按钮（`NinebotViewModel.swift:233-240`，成功文案「服务器连接正常」）

### 2. `POST /accounts/login`

- **调用**：`NinebotServerClient.swift:34-44`，解析在 `370-381`
- **请求体**：`{account: String, password: String}`
- **期望返回**：`uuid: String`、`phone: String`、`area_code: String`、`region: String`、`business_uid: String`、`account_id`/`id: Int`、`session_token`/`sessionToken: String`
- **依赖功能**：登录（`NinebotViewModel.swift:350-370`）。`session_token` 是后续**所有**接口的通行证；`phone` + `sessionToken` 双非空才算已登录（`NinebotViewModel.swift:187`）。`area_code` / `region` / `business_uid` 只用于设置页账号卡片的副标题（`NinebotSettingsView.swift:1320-1326`）

### 3. `POST /vehicles/{sn}/bell`

- **调用**：`NinebotServerClient.swift:46-48`
- **参数**：无 body
- **期望返回**：任意（返回值被 `_ =` 丢弃）
- **依赖功能**：车控页寻车鸣笛（`NinebotViewModel.swift:390`）、Siri 快捷指令（`NinebotAppIntents.swift:336`）、Control Widget（`NinebotWidgetControlIntents.swift:117`）

### 4. `POST /vehicles/{sn}/buck`

- **调用**：`NinebotServerClient.swift:50-52`
- **参数**：无 body
- **期望返回**：任意
- **依赖功能**：开座桶（`NinebotViewModel.swift:392`、`NinebotAppIntents.swift:338`、`NinebotWidgetControlIntents.swift:119`，Widget/Intent 侧需 Face ID）

### 5. `POST /vehicles/{sn}/engine/start`

- **调用**：`NinebotServerClient.swift:54-56`
- **参数**：无 body
- **期望返回**：任意
- **依赖功能**：滑动开锁 / 上电（`NinebotViewModel.swift:394`、`NinebotAppIntents.swift:340`、`NinebotWidgetControlIntents.swift:121`）

### 6. `POST /vehicles/{sn}/engine/stop`

- **调用**：`NinebotServerClient.swift:58-60`
- **参数**：无 body
- **期望返回**：任意
- **依赖功能**：滑动关锁 / 熄火（`NinebotViewModel.swift:396`、`NinebotAppIntents.swift:342`、`NinebotWidgetControlIntents.swift:123`）

### 7. `POST /vehicles/{sn}/prediction-settings`

- **调用**：`NinebotServerClient.swift:62-78`，解析在 `506-520`
- **请求体**：`{battery_chemistry: String, nominal_voltage: String, capacity_wh: String}`（数值也是字符串，见 `numberInputText`，`NinebotServerClient.swift:522-528`；nil 时传空串）
- **期望返回**：`battery_chemistry`/`batteryChemistry` 对象，内含 `configured`（**必需**，否则整体返回 nil）、`effective`、`source`、`nominal_voltage`、`capacity_wh`、`capacity_ah`
- **依赖功能**：设置页手动指定电池化学体系与容量，用于提升续航/充电预测精度（`NinebotViewModel.swift:255-276`）

### 8. `GET /vehicles`

- **调用**：`NinebotServerClient.swift:81`，取数组在 `383-399`，解析单车在 `421-439`
- **参数**：无
- **期望返回**：顶层数组，或含 `vehicles`/`data` 键的对象。每个元素需要：
  - `wnumber`/`sn: String` —— **必需**，缺失则该车被整条丢弃
  - `device_name`/`deviceName`/`ble_name` → 车辆显示名
  - `vehicle_name_en`/`vehicle_name`/`model`/`vehicleModel` → 型号；`vehicle_type` 追加成 `型号 (类型)`
  - `v6_light_img_url`/`img_url`/`img` → 车辆图片
  - `auth_date`/`authDate`/`bind_time`/`bindTime`/`created_at`/`createdAt` → 绑定日期（`NinebotModels.swift:91-92`）
- **依赖功能**：整个车控 Tab 的入口。`auth_date` 额外决定要回溯多少个月的行程（`NinebotServerClient.swift:211`、`988-1011`），进而决定总里程与月度里程图的数据范围

### 9. `GET /vehicles/{sn}/dashboard`

- **调用**：`NinebotServerClient.swift:90`，分支判定在 `99-129`
- **参数**：无
- **期望返回**：iOS 认两种形状，按顺序尝试：
  1. 含 `state`（且 `hasVehicleStatus` 通过）→ 同时读 `travel`、`battery`、`prediction`
  2. 含 `status` + `battery`（两者都要通过 `hasVehicleStatus` / `hasBatteryData`）→ 同时读 `travel`、`prediction`
  3. 两种都不成立 → 退回单独请求 `status` / `battery` / `travel` / `prediction`（第 10、11、12、13 条）
  
  另读 `vehicle`（覆盖车辆信息）、`updated_at`/`updatedAt`（车况时间戳，解析失败回退本机 `Date()`，`NinebotServerClient.swift:141`）
- **`hasVehicleStatus` 通过条件**（`NinebotServerClient.swift:401-409`）：`dump_energy`/`dumpEnergy`/`precise_estimate_mileage`/`estimate_mileage`/`pwr`/`charging`/`lock_status` 至少有一个是数字，**或**存在 `loc`/`locationInfo` 对象
- **`hasBatteryData` 通过条件**（`411-419`）：`electricity`/`dump_energy`/`battery_voltage`/`bms_volt`/`bat_temp`/`charging_power` 至少一个是数字，**或**存在 `battery_list`/`batteryList`/`batteries` 数组
- **依赖功能**：车控 Tab 全部数据（电量、电压、温度、循环次数、充电功率、续航、充放电状态、上电/锁车状态、位置、总里程、月里程、月耗电、最近行程），Widget 全部尺寸，Control Widget 刷新，后台刷新，充电 Live Activity 触发判定

### 10. `GET /vehicles/{sn}/status`

- **调用**：`NinebotServerClient.swift:117`（仅第 9 条第 3 分支触发），字段映射在 `547-663`
- **参数**：无
- **期望返回**：`status`/`vehicle_status`/`vehicleStatus`/`data` 任意层嵌套（最多剥 2 层，`808-817`），需含 `dump_energy`/`dumpEnergy`、`estimate_mileage`/`precise_estimate_mileage`、`ai_estimate_mileage`、`pwr`/`powerStatus`、`lock_status`/`loc.lock`、`total_mileage`/`total_mileages`、`loc{lat, lon}`/`locationInfo{lat, lon, locationDesc, desc}`
- **依赖功能**：dashboard 缺失时车控页的兜底数据源。**返回为空会抛中文错误**「服务器没有返回车辆状态，请在管理端检查该车辆最近一次轮询」（`NinebotServerClient.swift:119-121`），不会静默降级

### 11. `GET /vehicles/{sn}/battery`

- **调用**：`NinebotServerClient.swift:118`（同上，仅第 3 分支）
- **参数**：无
- **期望返回**：`battery`/`batteryInfo`/`battery_info`/`data` 嵌套，或 `battery_list`/`batteryList`/`batteries` 数组，或 `battery_main`/`batteryMain`。字段：`electricity`/`dump_energy`、`battery_voltage`/`bms_volt`/`voltage`（14 个候选键名，`NinebotServerClient.swift:584-599`）、`battery_temperature`/`bat_temp`/`temp`（20 个候选，`606-625`）、`bms_cycle`/`cycle`、`charging_power`/`chargePower`、`charging`/`chargingState`、`remain_charge_time`
- **依赖功能**：同上兜底。为空同样抛错「服务器没有返回电池数据…」（`122-124`）

### 12. `GET /vehicles/{sn}/travel?month=yyyyMM`

- **调用**：`NinebotServerClient.swift:192-198`
- **查询参数**：`month`（`yyyyMM`，按 **Asia/Shanghai** 生成，`975-986`、`1013-1015`）
- **期望返回**：`list: [Object]`（行程数组）、`detail: [Number]`（**按日索引的每日里程数组**，第 0 项即 1 号，`712-729`）、`month: String`、`total_mileages`/`monthMileage`、`ec`/`monthEnergy`、`used_electricity`
- **`list` 元素字段**（`679-710`）：`travel_id`/`ride_id`/`record_id`/`id`、`start_time`/`stime`/`date`/`create_time`、`end_time`/`etime`/`finish_time`、`mileages`/`mileage`/`distance`、`ec`/`energy`/`electricity`/`consume`、`used_electricity`、`duration`/`ride_time`/`cost_time`（**分钟/秒/`HH:MM:SS` 三种都兼容**，`881-895`、`1056-1101`）、`speed`/`avg_speed`
- **依赖功能**：行程 Tab 列表、月度每日里程柱状图、**总里程**（跨月累加，`731-752`）、最近一次骑行卡片。被 `fetchMonthlyTravels`（`205-230`）按 `auth_date` 到今天**逐月循环调用**

### 13. `GET /vehicles/{sn}/prediction`

- **调用**：`NinebotServerClient.swift:200-203`（仅第 9 条第 3 分支），解析在 `463-504`
- **参数**：无
- **期望返回**：`range` 与 `charging` 两个对象（**至少一个非空**，否则整体 nil）。`range`：`estimated_range_km`、`local_range_km`、`official_range_km`、`source`、`km_per_percent`、`estimated_full_range_km`、`sample_count`、`total_used_percent`、`accuracy_percent`、`confidence_percent`、`accuracy_source`、`measured_sample_count`、`ready`。`charging`：`is_charging`、`remaining_minutes`、`estimated_full_at`、`fast_minutes_per_percent`、`taper_minutes_per_percent`、`sample_count`、`accuracy_percent`、`confidence_percent`、`accuracy_source`、`measured_sample_count`、`ready`、`estimated_speed_kmh`。顶层另有 `model_version`、`updated_at`、`battery_percent`、`battery_chemistry`
- **依赖功能**：续航预测卡片、充电剩余时间与预计充满时刻、Live Activity 的 `estimatedRange` / `estimatedFullAt` / `chargingSpeed`。nil 时退回本地常量估算

### 14. `GET /vehicles/{sn}/travel/{travelID}`

- **调用**：`NinebotServerClient.swift:165-178`
- **参数**：路径末段是行程 ID
- **期望返回**：**原样保留整个响应**（`raw: payload`，`NinebotModels.swift:288-302`），iOS 自己在里面递归找轨迹
- **轨迹提取逻辑**：`NinebotModels.swift:316-765`，**整整 450 行**兼容代码。它递归遍历整个响应树，收集任何键名落在这 19 个之一的子节点：`trial`、`trail`、`trace`、`track`、`tracks`、`track_list`/`trackList`、`trajectory`、`trajectory_list`/`trajectoryList`、`points`、`point_list`/`pointList`、`gps`、`gps_list`/`gpsList`、`location_list`/`locationList`、`coordinate_list`/`coordinateList`（`358-401`），然后对每个候选分别按**对象数组 / 数字对数组 / 分隔符字符串 / 嵌套 JSON 字符串**四种形态解析（`403-513`、`471-499`），取解析出点数最多的那个（`340-347`）。单点坐标又认 `lat`/`latitude`/`y`/`gcj_lat`/`wgs_lat` × `lon`/`lng`/`longitude`/`x`/`gcj_lng`/`gcj_lon`/`wgs_lng`/`wgs_lon`（`580-598`），还要处理经纬度顺序颠倒（`600-612`）
- **依赖功能**：行程详情页的轨迹地图回放与速度着色轨迹

### 15. `POST /vehicles/{sn}/travel-sync?month=&page_size=`

- **调用**：`NinebotServerClient.swift:180-190`，解析在 `530-545`
- **查询参数**：`month`（`yyyyMM`）、`page_size`（App 传 100，`NinebotViewModel.swift:284`；client 默认值 20）
- **期望返回**：`list: [Object]`（元素同第 12 条）、`month`、`page`、`page_size`/`pageSize`、`total`、`has_more`/`hasMore`
- **依赖功能**：行程 Tab 的「同步某月行程」手动操作（`NinebotViewModel.swift:278-300`）。结果写入本地接口行程库（`upsertInterfaceRideRecords`），并用 `page.total` 决定状态提示文案

### 16. `POST /devices/register`

- **调用**：`NinebotServerClient.swift:232-242`
- **请求体**：`{token: String, bundle_id: String, environment: String}`（`environment` 是运行时探测的 `aps-environment`，`NinebotPushManager.swift:222`）
- **期望返回**：任意（`_ =` 丢弃），但**非 2xx 会抛错**
- **依赖功能**：APNs 设备 token 上报（`NinebotPushManager.swift:81-95`）。设置页「开启充电通知」会把错误直接呈现给用户（`NinebotViewModel.swift:310-323`）；自动同步路径吞掉错误（`336-348`）

### 17. `POST /live-activities/register`

- **调用**：`NinebotServerClient.swift:244-274`
- **请求体**：`{token, token_kind, bundle_id, environment}` 必填，`activity_id` / `device_token` / `vehicle_sn` 非空时才带上。`token_kind` 取值 `push_to_start`（`NinebotPushManager.swift:105`）或 `activity`（同文件 `118`、`138`）
- **期望返回**：任意，非 2xx 抛错
- **依赖功能**：充电实时活动（灵动岛）的 push token 注册（`NinebotPushManager.swift:191-210`），让服务端能在 App 未运行时 push-to-start 并持续更新充电进度

---

## 二、对照矩阵

| iOS 调用 | 社区服务端有没有 | 路径是否一致 | 返回字段差异 | 依据（对方源码位置） | 结论 |
| --- | --- | --- | --- | --- | --- |
| `GET /healthz` | 有 | 一致 | 返回 `{status, backend, accounts}`；iOS 不读字段 | `server.py:516-520` | **一致** |
| `POST /accounts/login` | 有 | 一致 | 只有 `phone` + `session_token`；缺 `uuid`/`area_code`/`region`/`business_uid`/`account_id` | `server.py:304-311`、`524-530` | **字段缺失（功能降级）** |
| `POST /vehicles/{sn}/bell` | 有 | 一致 | 透传 `ninecli bell` 输出；iOS 丢弃 | `server.py:282-292`、`567-572` | **一致** |
| `POST /vehicles/{sn}/buck` | 有 | 一致 | 同上（`ninecli buck --yes`） | `server.py:283-287`、`567-572` | **一致** |
| `POST /vehicles/{sn}/engine/start` | 有 | 一致 | 同上（`ninecli engine-start --yes`） | `server.py:286`、`569-572`；测试 `test_server.py:32-39` | **一致** |
| `POST /vehicles/{sn}/engine/stop` | 有 | 一致 | 同上（`ninecli engine-stop --yes`） | `server.py:287`、`569-572` | **一致** |
| `POST /vehicles/{sn}/prediction-settings` | 有（回声桩） | 一致 | 把请求体原样套一层返回：`{"battery_chemistry": <请求体>}`。缺 `configured` 键 → iOS 解析结果恒为 nil；**服务端不落盘** | `server.py:563-565`；iOS 判定 `NinebotServerClient.swift:506-511` | **字段缺失（功能降级）** |
| `GET /vehicles` | 有 | 一致 | 信封 `{vehicles: [...]}`，键名与 iOS 首选键一致。元素内容取决于 `ninecli vehicles --json` 是否透传 `v6_light_img_url` / `auth_date` / `vehicle_type` | `server.py:247-250`、`535-537`；测试 `test_server.py:22-29` 的 stdout 为 `[{"wnumber":..,"device_name":..}]` | **需实测** |
| `GET /vehicles/{sn}/dashboard` | 有 | 一致 | 返回 `{vehicle, status, battery, travel, updated_at}`。**无 `state` 键** → 走 iOS 第 2 分支（`status`+`battery`）；**无 `prediction` 键** → 预测恒为 nil，且第 13 条接口永不被调用 | `server.py:256-270`、`542-546` | **字段缺失（功能降级）** |
| `GET /vehicles/{sn}/status` | 有 | 一致 | 返回 `dashboard["status"]`，即 `ninecli status --json` 原样 | `server.py:542-546` | **一致** |
| `GET /vehicles/{sn}/battery` | 有 | 一致 | 返回 `dashboard["battery"]`，即 `ninecli battery --json` 原样 | `server.py:542-546` | **一致** |
| `GET /vehicles/{sn}/travel?month=` | 有 | 一致 | `month` 查询参数被正确读取；返回体是 `ninecli travel --month --json` 原样（非 dict 时兜底成 `{month, list: []}`） | `server.py:272-274`、`551-555` | **需实测** |
| `GET /vehicles/{sn}/prediction` | 有（空桩） | 一致 | **恒返回 `{}`**，HTTP 200 | `server.py:560-562` | **完全缺失（功能不可用）** |
| `GET /vehicles/{sn}/travel/{id}` | 有 | 一致 | server.py 层**零加工**，非 dict 直接抛错。单测明确断言轨迹字段保留 | `server.py:276-280`、`547-550`；测试 `test_server.py:52-65`（用例名 `..._preserves_track`，断言 `detail["trail"][1]["speed"] == 18.0`） | **需实测**（server.py 已确认透传，待验 ninecli 层） |
| `POST /vehicles/{sn}/travel-sync?month=&page_size=` | 有（空桩） | 一致 | **恒返回 `{"month": month, "records": [], "total": 0}`**。`page_size` 被忽略；且键名是 `records`，iOS 读的是 `list`（`NinebotServerClient.swift:532`）——即便将来填了数据也对不上 | `server.py:556-559` | **完全缺失（功能不可用）** |
| `POST /devices/register` | 有（兼容桩） | 一致 | 恒返回 `{"accepted": false, "reason": "APNs is not configured"}`，HTTP 200 → iOS 不报错但推送永不到达 | `server.py:574-576`；README「Push registration responses (no APNs sending)」 | **完全缺失（功能不可用）** |
| `POST /live-activities/register` | 有（兼容桩） | 一致 | 同上，与 `/devices/register` 共用一条分支 | `server.py:574-576` | **完全缺失（功能不可用）** |

**汇总（共 17 个接口）**

| 结论 | 数量 | 接口 |
| --- | --- | --- |
| 一致 | 7 | `/healthz`、`/bell`、`/buck`、`/engine/start`、`/engine/stop`、`/status`、`/battery` |
| 路径不同（可适配） | 0 | —— |
| 字段缺失（功能降级） | 3 | `/accounts/login`、`/dashboard`、`/prediction-settings` |
| 完全缺失（功能不可用） | 4 | `/prediction`、`/travel-sync`、`/devices/register`、`/live-activities/register` |
| 需实测 | 3 | `/vehicles`、`/travel?month=`、`/travel/{id}` |

**最重要的一条好消息：路径不同的接口为 0。** iOS 调用的 17 条路径在社区服务端上全部按同一路径存在，鉴权头名字（`Authorization: Bearer`、`X-NinePlus-Session`）、信封格式（`{ok, data}` / `{ok, error:{message}}`）也完全一致（`server.py:366-374`、`430-432`、`531`）。Android 侧的 Retrofit interface 可以直接照着 iOS 的路径写，不需要任何路径映射层。

### 矩阵之外必须知道的四件事

这四条不是「某个接口缺失」，而是接口都在、但组合起来会出问题。它们对 Phase 0/1 能不能跑起来的影响不小于上表。

#### A. 一次车况刷新会触发 6 次以上 ninecli 子进程，串行执行，撞 20 秒超时

`DirectNinebotClient.run()` 每次调用都 `subprocess.run([sys.executable, "-m", "ninecli", ...], timeout=35)` 起一个新进程（`server.py:232-245`），而 `python -m ninecli` 又是 `os.execv` 到那个 8.9 MB 的 Go 二进制（`ninecli/__main__.py`），每次都要重新握手九号云并做一遍解密。数一下 iOS 一次 `fetchDashboard`（单车）的开销：

| iOS 请求 | 服务端内部的 ninecli 调用 | 次数 |
| --- | --- | --- |
| `GET /vehicles` | `vehicles()` | 1 |
| `GET /vehicles/{sn}/dashboard` | `ensure_vehicle()` → `vehicles()`（`server.py:540-541`） | 1 |
| | `dashboard()` → `status` | 1 |
| | `dashboard()` → `battery` | 1 |
| | `dashboard()` → `travel --month`（`server.py:260-263`） | 1 |
| | `dashboard()` → 又一次 `vehicles()`，只为填 `vehicle` 键（`server.py:265`） | 1 |
| **合计** | | **6** |

而且 `run()` 上有 `self._lock`（`server.py:237`），同一账号的所有调用**互相串行**，`ThreadingHTTPServer` 的并发在这里没用。iOS 侧 20 秒是**每请求**的超时（`NinebotServerClient.swift:285`），整个 `fetchDashboard` 编排没有总预算保护。Widget 侧的 `timeoutIntervalForResource = 12` 更紧。

**更糟的是逐月回溯。** `fetchMonthlyTravels`（`NinebotServerClient.swift:205-230`）会从 `auth_date` 一路循环到本月，每个非当月的月份发一次 `GET /vehicles/{sn}/travel?month=`，而服务端每条这样的请求又是 `ensure_vehicle()` + `travel()` = 2 次 ninecli 调用。绑定 18 个月的车 → 额外 34 次子进程调用，串行。这条路径的失败是静默的（`server.py` 侧超时会变成 HTTP 500，iOS 侧 `catch` 后 `return nil`，`NinebotServerClient.swift:223-228`），不会让刷新失败，但时间照样花掉。

#### B. 会话只存在服务端内存里，服务端一重启，App 端全部 401，且不会自动重登

`self._sessions` 是个普通 dict（`server.py:299`、`308-311`），没有持久化。容器重启 / `docker compose pull` 更新 → 所有已签发的 `session_token` 作废。此后除 `/healthz` 和 `/accounts/login` 之外的每个请求都会命中 `server.py:531-534`，返回 401 + `"登录会话无效，请重新登录"`。

iOS 侧**没有任何 401 处理**：全文只有 `NinebotServerClient.swift:307-309` 一处把非 2xx 抛成 `httpStatus`，没有拦截器、没有自动重登、`NinebotSharedStore.clearLoginResult()`（`NinebotSharedStore.swift:189`）定义了却**没有任何调用点**。用户只能自己回设置页重新输密码点登录。Widget 和后台刷新会持续静默失败。

#### C. dashboard 端点的行程月份用**容器本地时间**，与 iOS 的 Asia/Shanghai 存在 8 小时错位窗口

`server.py:257` 是 `datetime.now().strftime("%Y%m")` —— 无时区，取容器本地时间。`Dockerfile` 基于 `python:3.12-alpine` 且未设 `TZ`，`compose.yaml` 也没有 `TZ` 环境变量 → 容器是 UTC。

iOS 侧 `currentMonthString()` 固定用 Asia/Shanghai（`NinebotServerClient.swift:975-986`、`1013-1015`）。于是每月 1 号的中国时间 00:00–08:00，iOS 认为当前月份是新月，服务端 dashboard 里塞的却是**上个月**的 travel。接着 `fetchMonthlyTravels` 的 `if month == currentMonth, let currentTravel` 分支（`NinebotServerClient.swift:218-221`）会把这份上月数据当成当月数据用掉，而且不会再去请求真正的当月。后果：每日里程柱状图渲染上个月（`dailyMileageRecords` 读的是 payload 自带的 `month`，`NinebotServerClient.swift:714-717`），跨月累加的总里程重复计入上月。

注意单独的 `GET /vehicles/{sn}/travel?month=` **没有**这个问题，它正确读取查询参数（`server.py:552`），只有 dashboard 内嵌的那份 travel 有。

#### D. `/healthz` 不校验 Bearer Token，「测试连接」会假阳性

`server.py` 的路由顺序是：`/admin/*`（第 440-514 行，只靠 admin cookie）→ `/healthz`（516-520）→ **`_authorized()` Bearer 校验**（521-523）→ `/accounts/login`（524-530）→ 会话校验（531-534）→ 其余全部接口。

`/healthz` 在 Bearer 校验**之前**。所以 Bearer Token 填错时，设置页「测试连接」照样显示「服务器连接正常」（`NinebotViewModel.swift:233-240`），而登录和所有数据请求都会 401。这是个会浪费排查时间的坑，Android 侧的连通性测试应该改成一个需要鉴权的请求，或者至少在文案上区分「地址可达」和「凭据有效」。

---

## 三、会瘸的功能清单

### 已知的两条（不重复论证）

见 [android-porting-plan.md](./android-porting-plan.md) 「现成的替代：社区兼容实现」一节及 §1.7：

1. **APNs 推送 / Live Activity 服务端下发** —— 已判定可接受，Phase 1 本就不做推送。本次核对补充依据：`server.py:574-576` 两条注册路由返回 `{"accepted": false, "reason": "APNs is not configured"}` 且 HTTP 200，所以 iOS 侧**不会报错**，用户会以为开启成功。Android 侧若做本地通知方案，不要照抄这个「静默成功」语义，应该显式告知用户当前无服务端推送。
2. **续航 / 充电预测模型** —— 已判定可接受，退回本地常量估算。本次核对补充：不只是 `/prediction` 返回 `{}`（`server.py:560-562`），更关键的是 **`/dashboard` 响应里没有 `prediction` 键**，而 iOS 只在 dashboard 兜底分支才会去请求 `/prediction`（`NinebotServerClient.swift:106`、`113`、`128`）。也就是说在社区服务端下 `/prediction` 这个接口**一次都不会被调用**。Android 侧可以直接不实现这个 endpoint，先把预测能力当作「服务端不提供」处理。

### 本次新发现的

3. **手动同步某月行程 —— 完全不可用**。`server.py:556-559` 是空桩，恒返回 0 条。行程 Tab 的「同步某月行程」按钮会永远提示「YYYY年M月 暂无行程」（`NinebotViewModel.swift:292-293`），本地接口行程库永远不会被这条路径填充。而且键名 `records` ≠ iOS 期望的 `list`，即便社区服务端将来补上实现，也需要改键名或者 Android 侧两个都认。**影响范围有限**：行程列表的主数据来自 `GET /travel?month=`，是可用的（待实测），travel-sync 只是「主动补拉」的增量入口。

4. **电池化学参数设置 —— 写进去等于没写**。`server.py:563-565` 把请求体套一层原样吐回，不落盘。iOS 因为拿不到 `configured` 键，解析恒为 nil（`NinebotServerClient.swift:506-511`），但 `updateBatteryChemistry` 忽略返回值（`NinebotViewModel.swift:263`）并照样显示「已更新XX电池参数」——又一处**假成功**。由于预测模型本身也不存在，这个设置项在社区服务端下没有任何下游消费者。Android 侧建议直接隐藏或标注为不可用。

5. **总里程可能显示成「本月里程」**。这条最容易被当成数据错误而不是缺功能。链路是：`GET /vehicles` 若不返回 `auth_date`（或其 5 个别名）→ `NinebotModels.swift:91-92` 得到 nil → `monthStrings(from: nil, ...)` 只返回当月（`NinebotServerClient.swift:988-991`）→ `fetchMonthlyTravels` 只拿到一个月 → `totalMileage(fromMonthlyTravels:)` 累加出来的就是当月里程（`731-752`）→ 而 `NinebotServerClient.swift:143-145` 会用它**覆盖**掉 status 里的真实总里程。是否发生完全取决于 ninecli 的 vehicles 输出，见第四节 V2。

6. **月度里程柱状图只有当月**。同 5 的根因（`auth_date` 缺失导致不回溯历史月份），历史月份的数据不会被拉取。

7. **车辆图片可能缺失**。`v6_light_img_url` / `img_url` / `img` 若不在 vehicles 输出里，iOS 会退而从 status / battery 响应里翻（`NinebotServerClient.swift:441-461`），翻不到就没有车辆图。Android 侧要准备占位图。同样取决于 ninecli，见 V2。

8. **设置页账号卡片的副标题为空**。`server.py:311` 只返回 `phone` + `session_token`，`area_code` / `region` / `business_uid` 全缺 → `NinebotSettingsView.swift:1320-1326` 的 `detailText` 返回 nil，副标题整行不显示。纯展示性，Android 侧直接不做这个副标题即可。

9. **车况时间戳大概率退化成本机时间**。`server.py:269` 写的是 `datetime.now(timezone.utc).isoformat()`，形如 `2026-07-26T13:41:00.123456+00:00`。iOS `serverDateValue`（`NinebotServerClient.swift:868-879`）先按 `yyyy-MM-dd HH:mm:ss[.SSS]` 试（带 `T` 不匹配），退到 `dateValue`（`923-963`）依次试 10 种格式再退 `ISO8601DateFormatter()`。6 位小数 + `+00:00` 这个组合能否被这套链路吃下去需要实测（见 V5）；若失败则 `NinebotServerClient.swift:141` 回退到本机 `Date()`，每辆车的「车况更新于」显示的是**拉取时刻**而不是服务端采集时刻，历史点去重的时间判定也会受影响。

10. **服务端重启后彻底不可用直到手动重登**。详见上文 B。这不是「某个功能瘸」，是全盘不可用，且 iOS 侧现有代码没有恢复路径。**Android 侧不应照抄这个缺陷**：应该在 Repository 层加 401 拦截，清掉 session 并把用户导到登录页（或用保存的凭据静默重登）。

11. **刷新耗时可能超出 Widget 与后台刷新的预算**。详见上文 A。Widget 的 12 秒资源上限和 WorkManager 的执行窗口都可能不够。Android 侧的应对方向（缓存优先渲染、后台预热、把 `fetchDashboard` 的多请求编排改成有总预算的形式）属于实现决策，不在本文档定。

12. **每月 1 号 00:00–08:00（中国时间）里程数据错月**。详见上文 C。

13. **「测试连接」假阳性**。详见上文 D。

14. **NineBot+ 登录账号被强制要求是 11 位中国手机号**。`server.py:181-186` 的 `add_account` 对 `app_account` 也跑 `_is_mobile_phone()` 校验（`105-107`：11 位、以 1 开头、第二位 3-9），且 `app_password` 至少 8 位。这与 [phase0-foundation-spec.md](./phase0-foundation-spec.md) §0.5 「实际填的是自建账号标识，Android 侧建议改成『账号』」的表述有出入——在社区服务端下它**必须**是手机号格式（虽然可以是任意一个符合格式的号码，不必是真实的九号账号）。Android 侧的输入框校验要按这个约束做。

---

## 四、实测清单

前置：社区服务端已按 `install.sh` 部署，后台里已新增一个 NineBot+ 账号并绑定真实九号账号，至少有一辆车、且该车有历史行程。

```bash
# 每条命令前先设置这三个变量
export BASE=http://你的服务器IP:19009
export TOKEN=部署时生成的 NINEPLUS_BEARER_TOKEN     # .env 里的 NINEPLUS_BEARER_TOKEN
export SN=你的车架号

# 取会话 token（后续每条都要带）
export SESSION=$(curl -sS -X POST "$BASE/accounts/login" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"account":"13900000000","password":"你的NineBot+密码"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["session_token"])')
echo "$SESSION"

# 之后所有请求都用这两个头
alias nine='curl -sS -H "Authorization: Bearer $TOKEN" -H "X-NinePlus-Session: $SESSION"'
```

> 判定用到的原始返回建议全部存盘（`> t1.json` 之类），后面 Android 侧写 MockWebServer 用例时可以直接当 fixture。

### V1 · 轨迹接口的原始返回是否被裁剪（最高优先级）

**为什么最重要**：iOS 侧为了兼容九号返回的不定形状，在 `NinebotModels.swift:316-765` 写了 450 行轨迹解析——19 个候选键名、4 种数据形态、经纬度顺序颠倒兜底。如果社区服务端（或 ninecli）已经把轨迹规整成了单一形状，这 450 行里绝大部分在 Android 侧就是白写的，Phase 0 的工时可以直接砍掉一块。

**怎么测**

```bash
# 1) 先拿一个真实的行程 ID
nine "$BASE/vehicles/$SN/travel?month=$(date +%Y%m)" > t1_travel.json
python3 -c "
import json; d=json.load(open('t1_travel.json'))['data']
print('顶层键:', sorted(d.keys()))
lst=d.get('list') or []
print('list 长度:', len(lst))
if lst: print('首条键:', sorted(lst[0].keys())); print('首条:', json.dumps(lst[0], ensure_ascii=False)[:400])
"

# 2) 用上面 list 里的 travel_id（或 id）拉详情，原样存盘
export TID=上一步拿到的行程ID
nine "$BASE/vehicles/$SN/travel/$TID" > t1_detail.json

# 3) 看轨迹到底长什么样
python3 -c "
import json
d=json.load(open('t1_detail.json'))['data']
KEYS={'trial','trail','trace','track','tracks','track_list','trackList','trajectory',
      'trajectory_list','trajectoryList','points','point_list','pointList','gps',
      'gps_list','gpsList','location_list','locationList','coordinate_list','coordinateList'}
print('顶层键:', sorted(d.keys()))
def walk(v, path=''):
    if isinstance(v, dict):
        for k, c in v.items():
            if k in KEYS:
                print(f'命中候选键 {path}/{k}: type={type(c).__name__}', end='')
                if isinstance(c, list):
                    print(f' len={len(c)} 首元素={json.dumps(c[0], ensure_ascii=False)[:200] if c else None}')
                elif isinstance(c, str):
                    print(f' 字符串前 200 字={c[:200]!r}')
                else:
                    print()
            walk(c, f'{path}/{k}')
    elif isinstance(v, list):
        for i, c in enumerate(v[:3]): walk(c, f'{path}[{i}]')
walk(d)
"
```

**看什么 / 什么算通过**

| 检查项 | 通过标准 |
| --- | --- |
| 轨迹键名 | 命中的候选键**只有一个**，且落在 19 个键名之内。记下具体是哪个（社区单测里是 `trail`，见 `tests/test_server.py:56`） |
| 点的形态 | 是**对象数组**且每个对象有 `lat` / `lon`（或明确的别名）。如果是数字对数组、分号分隔字符串、或嵌套 JSON 字符串，记下具体形态 |
| 点内字段 | 记录每个点实际有哪些键（社区单测显示 `lon`/`lat`/`speed`/`distance`） |
| 是否被裁 | 详情响应里除轨迹外还有哪些字段。`server.py:276-280` 已确认不做任何加工，所以这一步测的其实是 **ninecli 层**是否透传 |

**通过之后可以做的裁剪**（属于实现决策，不在此拍板，只记录可能性）：如果连续三条不同的行程都是同一个键名 + 同一种形态，那么 Android 侧的轨迹解析可以只实现这一条路径，其余 18 个键名和 3 种形态作为「遇到再补」。**但要留一个显式的解析失败日志**，否则将来九号改格式时会静默丢轨迹。

### V2 · vehicles 输出是否透传 `auth_date` / `v6_light_img_url` / `vehicle_type`

**为什么要测**：ninecli 二进制里能提取到 `json:"wnumber"`、`json:"sn"`、`json:"device_name"`、`json:"vehicle_name"`、`json:"vehicles"` 这几个 Go 结构体标签，但**提取不到** `auth_date`、`v6_light_img_url`、`vehicle_name_en`、`img_url`（`vehicle_type` 和 `ble_name` 只以裸字符串出现、无 json 标签）。这说明 vehicles 至少有一份类型化的结构体定义，有可能在序列化时丢字段。而 `auth_date` 缺失会直接导致第三节第 5、6 条（总里程显示成本月里程、月度图只有当月）。

**怎么测**

```bash
nine "$BASE/vehicles" > t2.json
python3 -c "
import json
v=json.load(open('t2.json'))['data']['vehicles'][0]
print('全部键:', sorted(v.keys()))
for group in [['wnumber','sn'],
              ['auth_date','authDate','bind_time','bindTime','created_at','createdAt'],
              ['v6_light_img_url','img_url','img'],
              ['vehicle_type'],
              ['vehicle_name_en','vehicle_name','model','vehicleModel'],
              ['device_name','deviceName','ble_name']]:
    hit=[k for k in group if k in v]
    print(('OK  ' if hit else 'MISS'), group, '->', {k: v[k] for k in hit})
"
```

**通过标准**：`wnumber`/`sn` 必须命中（否则车辆会被 iOS/Android 整条丢弃）；`auth_date` 组命中则第 5、6 条问题不存在；`v6_light_img_url` 组命中则第 7 条不存在。**任何一组 MISS 都要如实记下来**，它决定 Android 侧要不要为总里程另找数据源、要不要准备占位图。

### V3 · 数字 / 布尔的类型是否稳定

**为什么要测**：iOS 侧的 `JSONValue` 对每个取值都做了宽松转换（`doubleValue` 能吃字符串、`boolValue` 能吃 1/0 和 `"true"`/`"yes"`/`"on"`，见 [phase0-foundation-spec.md](./phase0-foundation-spec.md) §0.1），且 `firstBoolLike(..., trueValue: 1)`（`NinebotServerClient.swift:634-635`、`897-921`）明确是在处理「布尔被返回成整数 1/0」。这套宽松层的必要程度决定 Android 侧 `JsonElement` 扩展要写多严。

**怎么测**

```bash
nine "$BASE/vehicles/$SN/dashboard" > t3.json
python3 -c "
import json
d=json.load(open('t3.json'))['data']
print('dashboard 顶层键:', sorted(d.keys()))
def types(obj, keys, label):
    print('---', label)
    for k in keys:
        if k in obj: print(f'  {k:32} = {obj[k]!r:24} ({type(obj[k]).__name__})')
        else:        print(f'  {k:32} 缺失')
st=d.get('status') or {}
# status 可能还有一层嵌套，两层都打
for probe in ('status','vehicle_status','vehicleStatus','data'):
    if isinstance(st.get(probe), dict): st=st[probe]; break
types(st, ['dump_energy','estimate_mileage','precise_estimate_mileage','ai_estimate_mileage',
           'pwr','charging','lock_status','total_mileage','total_mileages'], 'status 数值/布尔')
print('  loc =', json.dumps(st.get('loc'), ensure_ascii=False))
print('  locationInfo =', json.dumps(st.get('locationInfo'), ensure_ascii=False))
bt=d.get('battery') or {}
for probe in ('battery','batteryInfo','battery_info','data'):
    if isinstance(bt.get(probe), dict): bt=bt[probe]; break
types(bt, ['electricity','dump_energy','battery_voltage','bms_volt','voltage',
           'battery_temperature','bat_temp','temp','bms_cycle','cycle',
           'charging_power','charging','remain_charge_time'], 'battery 数值/布尔')
print('  battery_list =', json.dumps(bt.get('battery_list') or bt.get('batteryList'), ensure_ascii=False)[:300])
"
```

**看什么 / 通过标准**

| 检查项 | 通过标准 |
| --- | --- |
| `hasVehicleStatus` 能否通过 | `dump_energy` / `precise_estimate_mileage` / `estimate_mileage` / `pwr` / `charging` / `lock_status` 至少一个是**数字类型**，或存在 `loc` / `locationInfo` 对象。**不通过则车控页在 dashboard 分支就会失败**（`NinebotServerClient.swift:401-409`） |
| `hasBatteryData` 能否通过 | `electricity` / `dump_energy` / `battery_voltage` / `bms_volt` / `bat_temp` / `charging_power` 至少一个是数字，或有 `battery_list` 数组（`411-419`） |
| 数字是不是字符串 | 逐个记 `int` / `float` / `str`。**只要有一个数值字段是 `str`，Android 侧的宽松转换层就必须完整实现，不能用严格反序列化** |
| 布尔是不是 0/1 | `charging` / `pwr` / `lock_status` 的实际类型与取值。若是 `0`/`1` 整数，`firstBoolLike(trueValue: 1)` 的语义必须原样搬 |
| 键名大小写风格 | 记下实际是 snake_case 还是 camelCase。iOS 两种都认，Android 直译时**不要**只保留一种 |
| 单位量级 | `battery_voltage` 是否 >120 或 >1000（触发 `normalizedBatteryVoltage` 的除 10 / 除 1000，`840-849`）；`bat_temp` 是否 >120（除 10，`851-857`）；`loc.lat`/`loc.lon` 是否是放大过的整数（触发 `normalizedCoordinate` 依次除 1e6/1e7/1e5，`665-677`）。**这三条归一化规则是否真的会被触发，直接决定 Android 侧要不要照抄** |

补充一条：**同一个字段在不同时刻类型是否会变**。至少在充电中和未充电两个状态各抓一次 `t3.json` 做对比（`charging`、`charging_power`、`remain_charge_time` 在不充电时可能是 `0`、`null` 或直接缺失）。

### V4 · dashboard 走的是哪个分支，`prediction` 键确实不存在

```bash
python3 -c "
import json
d=json.load(open('t3.json'))['data']
print('有 state 键:', 'state' in d)
print('有 status 键:', 'status' in d)
print('有 battery 键:', 'battery' in d)
print('有 travel 键:', 'travel' in d)
print('有 prediction 键:', 'prediction' in d)
print('有 vehicle 键:', 'vehicle' in d)
print('updated_at =', repr(d.get('updated_at')))
"
```

**通过标准**：`state` 为 False、`status`/`battery`/`travel`/`vehicle`/`updated_at` 为 True、`prediction` 为 False —— 与 `server.py:264-270` 一致。若与预期不符，说明服务端版本与本次核对的 `main` 分支不同，整份文档需要重新核对。

### V5 · `updated_at` 能否被 iOS/Android 的日期解析链吃下去

```bash
python3 - <<'EOF'
import json
raw = json.load(open('t3.json'))['data'].get('updated_at')
print('原始值:', repr(raw))
print('长度:', len(raw) if isinstance(raw, str) else None)
print('含 T:', 'T' in raw if isinstance(raw, str) else None)
print('小数位数:', len(raw.split('.')[1].split('+')[0]) if isinstance(raw, str) and '.' in raw else 0)
print('时区写法:', raw[-6:] if isinstance(raw, str) else None)
EOF
```

再在 iOS 真机上验一次表现：拉一次车况，看车控页某辆车的「车况更新于」时间，与服务端 `date -u` 对比。

**通过标准**：iOS 显示的时间与服务端 `updated_at` 一致 → 解析成功。若显示的是**你点刷新那一刻**的本机时间，说明落到了 `NinebotServerClient.swift:141` 的 `?? Date()` 兜底 —— 那么 Android 侧要么在解析链里补上「6 位小数 + `+00:00`」这种 ISO8601 变体，要么和 iOS 保持一致的兜底行为（**保持一致 vs 修好，是个需要拍板的选择，见「待定」A3**）。

### V6 · 一次完整刷新的真实耗时（决定 Widget / 后台刷新是否可行）

```bash
# 单个 dashboard 请求（服务端内部 5 次 ninecli 调用）
time nine -o /dev/null -w '%{time_total}\n' "$BASE/vehicles/$SN/dashboard"

# 车辆列表（1 次）
time nine -o /dev/null -w '%{time_total}\n' "$BASE/vehicles"

# 单个月行程（2 次）
time nine -o /dev/null -w '%{time_total}\n' "$BASE/vehicles/$SN/travel?month=$(date +%Y%m)"

# 连续跑 5 次 dashboard，看抖动和是否有超时
for i in 1 2 3 4 5; do nine -o /dev/null -w "run$i %{time_total}s http=%{http_code}\n" "$BASE/vehicles/$SN/dashboard"; done
```

**看什么 / 通过标准**

| 场景 | 通过标准 |
| --- | --- |
| 主 App（20 秒/请求） | `GET /dashboard` 的 p95 < 10 秒，且 5 次里没有一次 >20 秒或返回 5xx |
| Widget（12 秒资源上限） | `GET /vehicles` + `GET /dashboard` **两者之和** < 12 秒。超了就说明 Widget 在社区服务端下只能靠缓存渲染，不能指望现场刷新 |
| 逐月回溯 | 如果 V2 显示 `auth_date` 存在，用 `monthStrings` 的逻辑算出实际月份数 N，测 `(N-1)` 次 travel 请求的总耗时。**超过 60 秒就必须在 Android 侧改编排**（本文档不定方案） |
| 并发行为 | 同时发两个 dashboard 请求，观察是否因 `server.py:237` 的 `_lock` 而排队翻倍 |

### V7 · 会话失效后的实际表现

```bash
# 1) 确认当前 session 可用
nine -o /dev/null -w 'before=%{http_code}\n' "$BASE/vehicles"

# 2) 重启服务端
#    在服务器上执行： docker compose restart nineplus

# 3) 用同一个（已失效的）session 再打一次
nine -w '\nafter=%{http_code}\n' "$BASE/vehicles"

# 4) 对照：healthz 不受影响
curl -sS -w '\nhealthz=%{http_code}\n' "$BASE/healthz"
# 5) 对照：故意用错的 Bearer 打 healthz，看是否仍然 200（验证第二节 D）
curl -sS -H "Authorization: Bearer WRONG" -w '\nhealthz_wrong_token=%{http_code}\n' "$BASE/healthz"
```

**通过标准**：`before=200`、`after=401`（消息「登录会话无效，请重新登录」）、`healthz=200`、`healthz_wrong_token=200`。这三条同时成立就确认了第二节 B 和 D 两条结论。然后在 iOS 真机上重复一次，确认 App 是否卡在错误提示不自动恢复 —— 确认后，Android 侧的 401 拦截器就是必须做的（**要不要做静默重登，见「待定」A2**）。

### V8 · 月初时区窗口（可选，但便宜）

不必等到月初：直接在服务器上把容器时区改成 UTC-9 之类，让容器认为的月份与 Asia/Shanghai 不同，然后对比 `GET /dashboard` 里 `travel.month` 与 `GET /travel?month=` 显式传参的结果。

```bash
# 确认容器时区（预期是 UTC）
docker exec nineplus date
docker exec nineplus sh -c 'echo TZ=$TZ'

# 对比 dashboard 内嵌 travel 的月份 vs 显式请求的月份
nine "$BASE/vehicles/$SN/dashboard" | python3 -c "import json,sys; print('dashboard 内嵌 travel.month =', json.load(sys.stdin)['data'].get('travel',{}).get('month'))"
nine "$BASE/vehicles/$SN/travel?month=$(TZ=Asia/Shanghai date +%Y%m)" | python3 -c "import json,sys; print('显式请求返回的 month   =', json.load(sys.stdin)['data'].get('month'))"
```

**通过标准**：`docker exec nineplus date` 显示 UTC 即确认第二节 C 的前提成立。两个 month 在月中应当一致；不一致就直接暴露了错月问题。

### V9 · 空桩接口的实际返回（快速确认，5 分钟）

```bash
echo '--- prediction（预期 {}）'
nine "$BASE/vehicles/$SN/prediction"
echo '--- travel-sync（预期 records/total，注意不是 list）'
nine -X POST "$BASE/vehicles/$SN/travel-sync?month=$(date +%Y%m)&page_size=100"
echo '--- prediction-settings（预期把请求体原样套一层，无 configured 键）'
nine -X POST -H 'Content-Type: application/json' \
  -d '{"battery_chemistry":"lfp","nominal_voltage":"72","capacity_wh":"1440"}' \
  "$BASE/vehicles/$SN/prediction-settings"
echo '--- devices/register（预期 accepted:false）'
nine -X POST -H 'Content-Type: application/json' \
  -d '{"token":"deadbeef","bundle_id":"com.example.app","environment":"development"}' \
  "$BASE/devices/register"
echo '--- live-activities/register（预期同上）'
nine -X POST -H 'Content-Type: application/json' \
  -d '{"token":"deadbeef","token_kind":"push_to_start","bundle_id":"com.example.app","environment":"development"}' \
  "$BASE/live-activities/register"
```

**通过标准**：五条返回分别与 `server.py:560-562`、`556-559`、`563-565`、`574-576` 一致，且 **HTTP 状态码全是 200**。全部一致即确认矩阵里那 4 条「完全缺失」和 1 条「字段缺失」。若某条返回 404，说明服务端版本更旧/更新，需重新核对。

### V10 · 控制指令的真实返回与副作用

```bash
# 从最无害的开始
nine -X POST "$BASE/vehicles/$SN/bell"
```

**通过标准**：HTTP 200，车辆真的鸣笛。返回体形状记录下来备查（iOS 丢弃返回值，Android 也可以丢，但错误路径要能区分「指令下发失败」和「指令下发成功但车没响」）。`buck` / `engine/start` / `engine/stop` 有物理副作用，在**车辆处于安全状态**时再各测一次，重点确认 `--yes` 已经在服务端侧加上（`server.py:283-287`，单测 `tests/test_server.py:32-39` 已断言），不会因为交互式确认提示而卡到 35 秒子进程超时。

---

## 五、和现有规格的差异

[phase0-foundation-spec.md](./phase0-foundation-spec.md) 第 71-87 行有一份「端点清单」。逐条核对后有以下出入。**按要求不修改那个文件**，差异记在这里。

| # | 规格里的写法（行号） | 本次核对的结论 | 性质 |
| --- | --- | --- | --- |
| 1 | 清单共 13 行 | 13 行对应 **16 个** endpoint（第 86 行把 4 条控制指令合并成一行）。iOS 实际有 **17 个** | 计数口径 |
| 2 | 清单里**没有** `POST /live-activities/register` | 这个接口确实存在，`NinebotServerClient.swift:244-274`，且请求体最多 7 个字段（`token`、`token_kind`、`bundle_id`、`environment` 必填，`activity_id`/`device_token`/`vehicle_sn` 条件带上）。这是清单的**遗漏** | **遗漏** |
| 3 | 第 84 行「`/vehicles/{sn}/prediction` 预测（社区服务端不实现）」 | 表述偏轻。它**是**注册了路由的，返回 HTTP 200 + `{}`（`server.py:560-562`），不是 404。Android 侧不能把它当请求失败处理。**更重要的是**：由于 `/dashboard` 响应里没有 `prediction` 键、iOS 只在 dashboard 兜底分支才请求它（`NinebotServerClient.swift:106`/`113`/`128`），在社区服务端下这个接口**一次都不会被调用** | 需补充 |
| 4 | 第 82 行「`POST /vehicles/{sn}/travel-sync?month=&page_size=` 触发同步」 | 「触发同步」会让人以为它能工作。实际是空桩，恒返回 `{"month":…,"records":[],"total":0}`（`server.py:556-559`），且键名 `records` 与 iOS 读取的 `list`（`NinebotServerClient.swift:532`）**不一致**。另外 `page_size` 被完全忽略 | **需修正** |
| 5 | 第 85 行「`POST /vehicles/{sn}/prediction-settings` 电池化学参数」 | 未提及它在社区服务端是**回声桩、不落盘**（`server.py:563-565`），且缺 `configured` 键导致 iOS 解析恒为 nil（`NinebotServerClient.swift:506-511`） | 需补充 |
| 6 | 第 87 行「`POST /devices/register` 推送注册（Phase 1 不做，社区服务端返回兼容响应）」 | 准确。需补充两点：① 这条路由位于会话校验**之后**（`server.py:531` vs `574`），未登录时会 401 而不是「兼容响应」；② 返回 HTTP 200 + `accepted: false`，iOS 侧不报错，会造成「开启成功」的假象 | 需补充 |
| 7 | 第 79-80 行「`/vehicles/{sn}/status`、`/vehicles/{sn}/battery`（dashboard 缺失时的兜底）」 | 路径与用途都准确。未提及在社区服务端上这两个端点**各自都会执行完整的 dashboard 取数**（`server.py:542-546` 调 `dashboard(sn)` 再取其中一个键），也就是每次请求 5 次 ninecli 子进程调用。当作「轻量兜底」来设计重试策略会踩坑 | 需补充 |
| 8 | 第 91 行陷阱「`fetchDashboard` 不是单个请求，而是 `GET /vehicles` 后对每辆车再请求，且有三层兜底（`NinebotServerClient.swift:80-163`）」 | 描述准确但不完整。真正的性能悬崖是 `fetchMonthlyTravels`（`NinebotServerClient.swift:205-230`）：它按 `auth_date` 到今天**逐月**发 `GET /travel?month=`，绑定 18 个月的车就是 17 次额外请求 × 每次 2 个 ninecli 子进程。这条不在陷阱清单里 | **遗漏** |
| 9 | 第 36 行「超时 20 秒」 | 准确，但只覆盖主 App。Widget 扩展另有 `timeoutIntervalForRequest = 8` / `timeoutIntervalForResource = 12`（`NinebotWidgets/NinebotWidgetProvider.swift:12-18`、`NinebotWidgets/NinebotWidgetControlIntents.swift:80-86`），其中 12 秒资源上限不可被单请求覆盖，是 Widget 侧的实际预算 | 需补充 |
| 10 | 第 263 行「`POST /accounts/login` 返回 `session_token`（也认 `sessionToken`）」 | 准确。未提及社区服务端**只**返回 `phone` + `session_token`（`server.py:311`），`uuid`/`area_code`/`region`/`business_uid`/`account_id` 全缺 | 需补充 |
| 11 | 第 259 行「iOS 版那个输入框标签写的是『手机号』…实际填的是自建账号标识，Android 侧建议改成『账号』」 | 与社区服务端实现**冲突**：`server.py:181-186` 的 `add_account` 强制要求 NineBot+ 账号本身也是 11 位中国手机号格式（`_is_mobile_phone`，`server.py:105-107`），密码至少 8 位。它不必是真实的九号账号，但必须符合手机号格式。Android 侧的输入校验不能放开成任意字符串 | **冲突** |
| 12 | 第 96 行验收「用 MockWebServer 复刻 `ServerClientTests.swift` 的 70 个用例」 | 补充：本次实测清单（V1–V3）产出的真实 JSON 可以直接当 MockWebServer 的 fixture，比手写 mock 更能暴露类型不稳定问题。建议把 V1/V2/V3 的存盘文件纳入 Android 仓库的测试资源 | 建议 |

另外，[android-porting-plan.md](./android-porting-plan.md) 第 171 行「已实现」一行里的「行程详情」是准确的，但同一行没有区分「真实现」和「空桩」。按本次核对，那张表的「未实现」一栏除了 APNs 推送、Live Activity、续航/充电预测模型，还应加上 **travel-sync（空桩）** 和 **prediction-settings（回声、不落盘）**。

---

## 待定

需要人拍板，本文档不做决定。条目用 **A** 前缀（A = API），实测清单用 **V** 前缀（V = 验证），跨阶段的通用决策在 [pending-decisions.md](./pending-decisions.md) 里用 D 前缀，三套不冲突。

**A1 · 轨迹兼容代码的裁剪范围。** 若 V1 证实社区服务端下轨迹形态单一（例如恒为 `trail` + 对象数组 + `lat`/`lon`/`speed`），Android 侧要不要只实现这一条路径，把 iOS 那 450 行里的另外 18 个键名和 3 种数据形态砍掉？砍了省工时，但九号云一改格式就静默丢轨迹；不砍则要在 Android 侧重写 450 行没有已知触发场景的兼容代码。中间选项是「只实现命中的一条 + 解析失败时上报诊断日志」。

**A2 · 会话失效的恢复策略。** 社区服务端的会话存内存，重启即失效（第二节 B），iOS 侧没有任何恢复路径。Android 侧三个选择：① 照抄 iOS 的行为（用户自己去重登）；② 加 401 拦截器，清 session 并跳登录页；③ 用 DataStore 里已明文保存的账号密码静默重登。②③ 都偏离 iOS 行为，③ 还涉及「明文凭据被更频繁地使用」这一安全取舍（[phase0-foundation-spec.md](./phase0-foundation-spec.md) 第 283 行已确认明文存储可接受，但没讨论自动重登）。

**A3 · 两端行为不一致时以哪边为准。** 本次发现至少三处 iOS 现有行为可以判定为缺陷：`updated_at` 解析失败静默回退本机时间（第三节第 9 条）、`/healthz` 假阳性连通性测试（第二节 D）、`auth_date` 缺失导致总里程被本月里程覆盖（第三节第 5 条）。Android 侧是「与 iOS 逐位对齐（便于双端对照测试）」还是「顺手修好（两端行为分叉）」？这条会反复出现，建议先定一条总原则。

**A4 · 是否为社区服务端提交 PR 而不是在 Android 侧绕。** 有四处是服务端几行代码就能修好的：`travel-sync` 的 `records` 改 `list`、`dashboard()` 里重复的两次 `vehicles()` 调用（`server.py:265` 与 `540-541`）、`datetime.now()` 加时区（`server.py:257`）、会话持久化。改上游一次性收益覆盖两端，但引入对外部仓库维护者的依赖（该仓库目前 19 个提交、0 star、0 issue，维护活跃度未知）。

**A5 · Widget / 后台刷新在社区服务端下的降级形态。** 如果 V6 显示 Widget 的 12 秒预算不够，Widget 是「只渲染缓存、完全不发请求」，还是「发请求但接受经常超时」，还是「由主 App 或 WorkManager 预热缓存、Widget 只读」？这决定 Glance 和 Quick Settings Tile 的数据流设计，属于 Phase 0.4 之前要定的事。

**A6 · 电池化学参数设置项的去留。** 在社区服务端下这个设置写不进、也没有下游消费者（预测模型不存在）。Android 侧是照搬做出来（等将来换服务端）、隐藏、还是做成只读的说明文案？

**A7 · 总里程的数据源。** 若 V2 证实 `auth_date` 缺失，`NinebotServerClient.swift:143-145` 的覆盖逻辑会让总里程显示成本月里程。可选：不做这个覆盖（直接用 status 的 `total_mileage`）、要求服务端补 `auth_date`、或让用户手动指定一个起始月份。
