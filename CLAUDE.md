# 项目约定

> **新会话先读 [`docs/当前状态.md`](./docs/当前状态.md)** —— 做到哪了、下一步是什么、有哪些坑，都在那里。这份文件只讲规矩。


## 语言

**Commit message 和 PR（标题与正文）一律用中文。**

代码里的注释、标识符、文档另按下面的规矩来：

| 写什么 | 用什么语言 |
| --- | --- |
| Commit message | **中文** |
| PR 标题与正文 | **中文** |
| `docs/` 下的文档 | 中文 |
| 代码注释 | 跟随所在文件的现有风格 |
| 标识符、枚举 rawValue、持久化的键 | **ASCII**，见下面「中文不能当值用」 |
| 界面文案 | 中文，但要能被抽走 |

## 中文不能当值用

这个项目踩过这个坑，而且不止一次。中文字符串只能用来**显示**，不能承担下面任何一种职责：

- 被 `==` / `contains` / `hasPrefix` 拿去做判断
- 当 `Identifiable` 的 `id`、`ForEach` 的 key、字典的键
- 当分组或去重的依据
- 写进持久化（`UserDefaults` 的 key 或 value、编码进 JSON 存盘）
- 发给服务端

原因是改文案不会报错，只会静默改掉行为。已经修过的实例：

- 下拉刷新指示器靠 `message.contains("刷新车况")` 判断 → 改成 `NinebotLoadingOperation` 枚举
- 诊断中心拿 `accountText == "未绑定账号"` 判断有没有绑定账号 → 改成 `isAccountBound: Bool`
- 车辆按带中文后缀的显示串分组 → 改成 `NinebotVehicleAccount` 枚举
- 告警和洞察用中文串当列表身份 → 改成枚举，文案挪到界面层

**做法**：领域层出枚举（rawValue 用 ASCII），界面层用一个 `private extension` 把枚举映射成文案。`NinebotTripInsight`、`NinebotVehicleWarning`、`NinebotChargingStatus` 都是这个形状，照着写。

完整清单见 [`docs/移植可行性研究/string-extraction-inventory.md`](./docs/移植可行性研究/string-extraction-inventory.md)，还有 146 处没改完。

## 改动前先看这两处

- **待拍板的事** —— [`docs/移植可行性研究/pending-decisions.md`](./docs/移植可行性研究/pending-decisions.md)。D1–D13 是跨阶段的通用决策，后面按区域前缀分（T 行程 / P 传感器 / R 轨迹 / W Widget / C 充电岛 / S 系统 / I 图标 / A 服务端 / L 文案 / V 实测）。**不要替用户做产品决策**，遇到分歧写进这份文档。
- **实现规格** —— `docs/移植可行性研究/phase0-foundation-spec.md` 到 `docs/移植可行性研究/phase5-system-spec.md` 共八份。

## 两条 CI 门禁都会拦

| Job | 编译什么 |
| --- | --- |
| `Unit tests (swift test)` | `mini-ninebot/Shared/` （NineBotCore） |
| `Xcode build` | app target + widget target，**界面层只有这里编译** |

`swift test` **不编译任何界面代码**。改了构造函数签名、协议一致性、属性名之后，只跑单测是看不出来的 —— 有过一次改了 `RideDisplayMetric` 的签名、漏掉视图里 7 个调用点、单测全绿而 Xcode 构建挂掉的事故。

**所以改签名时用全局替换，改完再用正则核验所有调用点**，不要只替换第一处。

## 测试

- 383 个单元测试在 `Tests/NineBotCoreTests/`，只覆盖 `Shared/` 下的平台无关层
- 抽取领域逻辑时**顺手补测试**，抽取的意义之一就是让原本 private 的东西可测
- 发现 iOS 现有行为可疑时，**先用测试把现状钉住再说**，不要顺手改。改不改是产品决策（例：D9、D11）

## 服务端

服务端不在这个仓库里。见 [`docs/移植可行性研究/android-porting-plan.md`](./docs/移植可行性研究/android-porting-plan.md)。要改的补丁放在 [`server-patches/`](./server-patches/)。
