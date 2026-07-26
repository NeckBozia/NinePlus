# 对话原始记录

这个 Android 移植项目的全部规划、调研和 iOS 侧改动都出自一次会话。这里是那次会话的**原始记录**，不是整理稿 —— `docs/` 下其他文档是从它产出的结论，这里是产出过程。

会话日期：2026-07-26。

## 文件

| 文件 | 大小 | 内容 |
| --- | --- | --- |
| `main.jsonl` | 8.3 MB / 2609 行 | 主对话。每行一条 JSON 记录 |
| `subagents/agent-*.jsonl` | 7.3 MB / 20 个 | 每个子 agent 的完整过程 |
| `subagents/agent-*.meta.json` | — | 对应 agent 的元信息（任务描述等） |
| `attachment-hyperos3-island-probe-report.md` | — | 会话中上传的小米超级岛真机探针报告 |

## 格式

JSONL —— **一行一条 JSON**，不是一整个 JSON 文档。所以不能 `json.load(整个文件)`，要逐行解析：

```python
import json
for line in open("main.jsonl"):
    record = json.loads(line)
    ...
```

`main.jsonl` 里的记录类型分布：

| 条数 | `type` | 是什么 |
| --- | --- | --- |
| 1177 | `assistant` | 助手的回复与工具调用 |
| 668 | `user` | 用户消息与工具返回结果 |
| 202 | `last-prompt` | 提示快照 |
| 176 | `mode` | 模式切换 |
| 154 | `queue-operation` | 消息队列事件 |
| 137 | `attachment` | 附件（上传的文件等） |
| 79 | `system` | 系统消息 |

只想看人类可读的对话，过滤 `type` 为 `user`/`assistant` 且内容是文本的记录即可。工具调用与返回也在这两类里，量很大。

## 子 agent 索引

按记录大小排序。**最后五个只有 4 行** —— 那是启动后立刻被取消的批次，没有实际内容，重跑的结果在前面那些里。

| ID | 任务 | 行数 | 大小 |
| --- | --- | --- | --- |
| `aedc7fd681bb773de` | 写 Phase 3 行程规格 | 190 | 843 KB |
| `ade9bb37e7f59adda` | 中文文案清点 | 223 | 727 KB |
| `aff022f71178cbcbf` | 写 Phase 4 轨迹规格 | 128 | 700 KB |
| `afd3c2435ad255240` | 写 Phase 5 Widget 与充电岛规格 | 151 | 675 KB |
| `a057be4e8b8d57bb8` | 写 Phase 5 系统集成规格 | 139 | 604 KB |
| `af1ed463671be2a05` | Phase 1 详细规格（重试） | 104 | 498 KB |
| `a1cb3156742b4b02e` | 社区服务端 API 逐条核对 | 107 | 489 KB |
| `ae7597b7b20caf87d` | 写模型解析层测试 | 109 | 476 KB |
| `a9ccdaa2609dafda6` | 写 ServerClient 网络层测试 | 90 | 437 KB |
| `a061023f4c5b57bf5` | 写 Phase 4.2 传感器规格 | 73 | 431 KB |
| `a87e3b1f661378037` | 图标清点与映射 | 104 | 385 KB |
| `a85846a7d4b10c1ff` | 写 CI 流程与存储层测试 | 105 | 311 KB |
| `a77b0c0469efe85a3` | 分析 Dashboard 与 Recording 视图 | 90 | 283 KB |
| `a1a5bd4bebb8c4295` | 分析 Widgets 与系统集成 | 76 | 248 KB |
| `ae185368e324cd874` | 查 GitHub runner 的 Xcode 版本 | 42 | 72 KB |
| `a5d4ada9aad59e411` | Phase 5 系统集成规格（已取消） | 4 | 19 KB |
| `a1cf962473ceca30f` | Phase 4 本地记录规格（已取消） | 4 | 19 KB |
| `a0e698eb3e2bc9f6c` | Phase 3 与轨迹回放规格（已取消） | 4 | 19 KB |
| `a53e4bcaa8fdd58a8` | Phase 2 详细规格（已取消） | 4 | 18 KB |
| `a9bedddf911d65321` | Phase 1 详细规格（已取消） | 4 | 17 KB |

## 里面有什么，要知道

提交前扫过一遍，**没有任何真实凭据**。唯一命中告警模式的是 `ninebot_password=password`，那是社区服务端 `server.py` 源码里的一个 Python 关键字参数，不是密码。没有 GitHub token，没有 Bearer token。

但这是原始记录，所以确实包含：

- **仓库所有者的邮箱**（1 处，来自会话上下文）
- **运行环境的绝对路径**（`/home/user/…`、`/root/.claude/…`）和内部 session ID
- **系统提示与工具协议细节**
- **被读取过的文件的完整内容**，包括这个仓库的源码、社区服务端的 `server.py`、`ninecli` 二进制的元数据
- 助手的思考过程

自用归档没问题。**要公开这个仓库的话，先决定这个目录留不留。**

## 为什么留原始文件而不是整理稿

结论已经写在 `docs/` 下的其他文档里了 —— 那些是给人看的。这份留的是**过程**：某个数字是怎么查出来的、某条结论推翻了什么、哪些路走过发现是死的。

有几件事只有过程里才有：

- **小米超级岛**为什么判定不可做（鉴权链的完整 logcat 证据）
- **那 450 行轨迹兼容代码**为什么可能不用移植（社区适配器的单测断言）
- **图标从「30–40 个要定制」变成「0 个」**的逐个比对过程
- **传感器阈值从 13 个变成 32 个**是怎么数出来的
- 中间被推翻的几个判断（封号风险的说法、`ninecli serve` 那条路、`#if canImport(ActivityKit)` 的误判）

## 迁到新仓库时

计划是新建一个把服务端和客户端放一起的仓库，这个仓库废弃。搬的时候这些要一起走：

| 目录 | 内容 |
| --- | --- |
| `docs/` | 全部规划与规格（含本目录） |
| `server-patches/` | 社区服务端的补丁，对着上游 `main` 的 `server.py`（sha256 记在 README 里） |
| `Tests/` + `Package.swift` | 383 个单元测试与 SPM 配置 |
| `.github/workflows/ci.yml` | 两个门禁 job |
| `mini-ninebot/` | iOS 客户端本体 |

**已定：以 `claude/android-portability-research-daro6y` 这个分支的状态作为新仓库的起点**，不先合回本仓库的 `main`。

理由是新仓库反正要重新组织目录（客户端与服务端并列），合一次 `main` 再拆一次是白做。这个分支上有尚未合并的**代码**改动，不只是文档：领域层抽取（7 个新文件）、中文标识修复、时长精度统一、383 个单元测试、两条 CI 门禁、`server-patches/`。`main` 上这些都没有。

本仓库在新仓库建好之后废弃。
