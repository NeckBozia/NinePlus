# 小米超级岛本地通知驱动 — 探针报告

- 日期：2026-07-27
- 设备：Xiaomi 24129PN74C，HyperOS 3（`ro.mi.os.version.name=OS3.0` / `ro.miui.ui.version.name=V816` / code 816），Android 16 / SDK 36
- 探针 APK：`hyperisland-probe-debug.apk`（versionCode 5，SHA-256 `9ede7a356776d69bdcb9047fa27b3c6b3faaf3605143dbc9c6b434049dd3a99a`）
- 源码：本目录 `hyperisland-probe/`

---

## 结论

**超级岛能被本地通知的 `miui.focus.param` 驱动，但需要小米下发的应用资质，而且是服务端在线鉴权，绑正式签名。** 不是用户可开的开关，也不是本地白名单。

判定不是推断，是 adb logcat 抓到的完整鉴权链：JSON 被系统正确解析、模板渲染成功，然后 SystemUI 拿 APK 签名 + TrustZone 设备签名联网到 `hyperos.developer.xiaomi.com` 查该包有没有被授予 **scope 20032**，没授予 → `-300 scope mismatch` → 通知被撤下降级成普通通知。

---

## 1. APK 交付

| 位置 | 路径 |
|---|---|
| NAS / 本目录 | `100.Ongoing/170.NineBotPlus/171.HyperOS3-Island-Probe/hyperisland-probe-debug.apk` |
| 源码工程 | 本目录 `hyperisland-probe/`（Mac 原始位置 `~/Documents/300.Ongoing/310.Code/hyperisland-probe/`） |

`versionCode=5`，SHA-256 `9ede7a356776d69bdcb9047fa27b3c6b3faaf3605143dbc9c6b434049dd3a99a`，debug 签名，无混淆无第三方 SDK。

界面比最初需求多做了 **按钮④（读回已发通知的 extras）** 和诊断区控件坐标 dump —— 这两个是定位到根因的关键工具。

---

## 2. 怎么装 / 按哪个 / 看哪里

**装**：`adb install -r <apk>`，或文件管理器点安装。启动弹 POST_NOTIFICATIONS 授权，不给则按钮全灰。

| 按钮 | 作用 | 看哪里 |
|---|---|---|
| ① 发小米超级岛通知 | 本地通知带 `miui.focus.param` | 屏幕顶部挖孔两侧（超级岛）；此机上只会落进通知栏渲染成普通通知 |
| 复选框「附带本地图标」 | 加 `miui.focus.pics`（纯本地 Icon，不走网络） | 排除「小岛缺图标不渲染」变量 |
| ② 发标准 Live Update | Android 16 `ProgressStyle` + 提升标志 | 状态栏（需 `canPostPromotedNotifications`，此机 false 故不提升） |
| ③ 探测权限位 | 反射调 `hasFocusPermission` 等三路 | 界面「操作结果」区 |
| ④ 读回已发通知 extras | `getActiveNotifications()` 读回自己发的通知 | 确认 param 有没有到达系统 |

每个按钮的结果（成功 / 异常原文 / 发出的 JSON）都直接显示在界面，不依赖 adb。

---

## 3. param_v2 JSON 的来源与实际原文

**来源**：github.com/D4vidDf/HyperIsland-ToolKit，commit `1c0d6d4fbf711f5c1fba2d1a5d7fafb934223d99`（2025-12-19，仓库无 tag）。

没引依赖（它是 Kotlin + kotlinx.serialization，为一段 600 字节 JSON 拖进 Kotlin 工具链不划算），照抄它 `buildJsonParam()` 的输出结构：

- `HyperIslandNotification.kt:761-782` 组装逻辑
- `HyperIslandNotification.kt:191-195` 序列化器配置 `encodeDefaults = true; explicitNulls = false`
- 模板取 `baseInfo(type=2) + progressInfo`，即库的线性进度条模板

**实际发出的 JSON 原文（默认不带图标，604 字节）：**

```json
{"param_v2":{"protocol":3,"business":"charging","updatable":true,"ticker":"正在充电","enableFloat":true,"isShowNotification":true,"islandFirstFloat":false,"param_island":{"islandProperty":1,"islandPriority":2,"islandOrder":false,"dismissIsland":false,"maxSize":false,"needCloseAnimation":true,"bigIslandArea":{"imageTextInfoLeft":{"type":1,"textInfo":{"title":"充电中","content":"67%","showHighlightColor":false}}}},"baseInfo":{"type":2,"title":"正在充电","subTitle":"67%","content":"预计 42 分钟充满"},"progressInfo":{"progress":67,"colorProgress":"#34C759"}},"isShowNotification":true}
```

勾图标是 802 字节，多出两处 `picInfo`，指向 key `miui.focus.pic_app`。生成逻辑在 `hyperisland-probe/app/src/main/java/com/bozia/islandprobe/FocusParam.java`（仅依赖 `org.json`，带 `main()` 自检，可脱离 Android 直接跑，断言全过）。

**这套结构在 HyperOS 3 上依然有效** —— 见第 5 节系统自己的反序列化输出，字段全中。

---

## 4. 诊断信息判读（测试机实测）

```
persist.sys.feature.island = 1             机型支持超级岛
[global] support_dynamic_island = 1
[system] notification_focus_protocol = 3   与 param 里 protocol:3 对应
canShowFocus = true                        库用的粗粒度位，普通 app 默认就 true
focusType = PARAMS                         框架层认出这是焦点通知
POST_NOTIFICATIONS = 已授权
```

**这些全是绿灯，但都不代表能上岛。** `NotificationManager.hasFocusPermission()` 在 HyperOS 3 上反射枚举不到（最初 prompt 里那条线索作废）；真正管事的是服务端鉴权。

---

## 5. 判定链（logcat 实录）

按下按钮①，SystemUI 的 `FocusPlugin`：

```
FocusPlugin: createStandardTemplate
FocusPlugin: onInflateSuccess 0|com.bozia.islandprobe|1001|null|10390   ← JSON 渲染成功
FocusPlugin: inflation Ended
   ↓ 89ms 后
FocusPlugin: onAuthFailed     0|com.bozia.islandprobe|1001|null|10390   ← 鉴权失败
FocusPlugin: removeByKey      0|com.bozia.islandprobe|1001|null|10390   ← 撤下
```

系统自己的反序列化结果（证明 JSON 格式对）：

```
FocusNotificationParamV2(protocol=3, ticker=正在充电,
  baseInfo=(type=2, title=正在充电, subTitle=67%, content=预计 42 分钟充满),
  progressInfo=(progress=67.0, colorProgress=#34C759))
```

鉴权链：

```
SignatureUtils: getCacheResult: com.bozia.islandprobe, result: false
AuthManager: request auth: com.bozia.islandprobe
[XMS][Auth] securityDeviceSign start … end                    TrustZone 设备签名
[XMS][Auth] response: 200 https://hyperos.developer.xiaomi.com/xms/app/auth/query
[XMS][Auth] fetch auth resp: HttpAuthData(statusCode=0, statusMsg=成功,
              packageName=com.bozia.islandprobe, apkSigns=null, scopeInfos=[])
[XMS][Auth] errorCode: -300, errorMsg: Authentication failed because scope mismatch.
```

服务器认得包名（返回「成功」），但 `scopeInfos=[]`、`apkSigns=null` —— 没给任何授权。

**试过没用的三条路（都实测排除）：**

- 改发送姿势（`build()` 前 `addExtras` vs 后写 `notification.extras`）—— param 都完整到达，按钮④验证过
- 写 `secure` 的 `focus_notifs` / `updatable_focus_notifs` 列表 —— 写入包名后重发仍 `onAuthFailed`（测完已恢复 `[]`）
- 冒充美团外卖包名 —— 安装阶段就被签名核验拦掉（`INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match`），根本进不到服务器；签名绑定就是防这个

---

## 6. 附赠：标准 Live Update 对照组

`canPostPromotedNotifications() = false` —— Android 16 的 per-app 提升开关默认关。所以按钮②的 `ProgressStyle` + `FLAG_PROMOTED_ONGOING` 发得出但不提升到状态栏。这是 AOSP 侧的用户开关（设置里搜「实时」），跟小米那套鉴权是两回事。SDK_INT≥36 保护 + 低版本降级逻辑都在。

---

## 7. 想真正用上要做什么

去 `hyperos.developer.xiaomi.com` 注册应用、申请焦点通知/超级岛能力（scope 20032），授权**绑 APK 正式签名**（响应里的 `apkSigns` 字段）。个人 debug 包拿不到。签名绑定绕不过去 —— 绕过去了就是安全漏洞。

---

## 8. 相关

- 本目录 `vault-30-hyperos3-super-island-auth.md`：vault 深度技术记录快照（鉴权链全文、误导性绿灯对照表、复现命令）
- Vault 正源（随 Syncthing 同步）：`30.Tech/30-hyperos3-super-island-auth.md`、`30.Tech/30-scp-to-dsm-sftp-namespace.md`
- 源码构建：`cd hyperisland-probe && JAVA_HOME=<jdk21> ./gradlew assembleDebug`（需 Android SDK platform 36 + build-tools 36，路径见 `local.properties`）
