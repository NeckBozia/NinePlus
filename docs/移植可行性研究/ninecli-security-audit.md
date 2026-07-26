# ninecli 0.1.7 安全审计报告

**审计日期**：2026-07-27
**审计对象**：PyPI 包 `ninecli==0.1.7`，`manylinux_2_17_x86_64` wheel 内的
`ninecli/bin/ninecli`（8.9 MB 静态 Go ELF）
**SHA-256**：`faaa5b841427e8d3018321e6ae7db9b26921600b2ef4c8bafd48640edaac0126`
**审计目的**：判断能否把三个九号账号的密码交给这个闭源二进制
**性质**：纯防御性审计，目标机器为审计者自有

---

## 一、结论

**可以交。** 在静态与动态观测范围内，未发现向 ninebot 以外任何目的地发送数据、
未发现遥测、未发现子进程、未发现自动更新通道、未发现配置目录之外的文件写入。
令牌落盘权限正确（0600），不做证书绑定。

但交之前必须处理两件事。这两件事都**不是**作者恶意，是设计选择与上游接口限制：

### 条件 1：不要运行 `serve` / `mcp --http`

实测确认：当 `tokens.json` 存在且未指定 `--token` 时，本地 HTTP 服务**没有任何
本地访问控制**：

```
POST http://127.0.0.1:18009/vehicles/<SN>/engine/stop
→ 通过本地检查 → 真实打到 ebike.ninebot.com → 上游以令牌无效拒绝(502/401901)
```

三个受保护端点（`/whoami`、`/vehicles`、`/vehicles/<SN>/engine/stop`）全部穿过
本地门到达上游。生产状态下（令牌有效）**同机任何进程都能断电落锁一台真实车辆，
无需任何本地凭据**。MCP 模式同理，且那是给语言模型调用的 tool。

默认只绑 `127.0.0.1:18009`（局域网地址实测直接拒绝），非 loopback 绑定且无
token 时程序会打印警告。若必须运行，**必须**提供 `--token` 或
`NINEBOT_SERVE_TOKEN`。

社区适配器采用「每条命令 fork 一次进程」模式，不使用 serve，因此默认不受影响。

### 条件 2：每个账号只运行一次 `login`

`login -u USER -p PASSWORD` 的密码会进入进程 argv，同机其他用户可通过 `ps`
看到，并会进入 shell history 与 process accounting。

**短信登录不可用**：`login-code` 对真实号码同样返回
`resultCode=90202 "send code need verify"`——九号的短信接口强制要求前置
图形/风控校验，ninecli 未实现该步骤。因此密码路径无法避开。

缓解：密码每个账号只需要用一次。`login` 成功后写入 `tokens.json`，之后所有命令
只读该文件、由 `refresh_token` 续期，密码不再进入任何进程。把 argv 暴露压缩为
建号时的一次性窗口，在可控时刻执行。

若要消除这一次窗口：`serve --token <随机串>` 启动后向 `POST /auth/login` 以
JSON body 提交密码（走 loopback，不进 argv），登录完成后立即停止 serve。

---

## 二、审计方法

| 阶段 | 手段 |
|---|---|
| 溯源 | gitea.com 仓库存在性核查、PyPI 元数据、构建元数据 |
| 静态 | `redress`（pclntab 恢复包/函数/类型）、字符串提取、标准库链接清单、精确版本基线对照 |
| 动态 | 一次性 lima VM（arm64 + Rosetta binfmt）+ mitmproxy 全量抓包 + dnsmasq 全量 DNS 日志 + nftables uid 级默认拒绝 + strace |
| 一致性 | 8 个平台 wheel 的 buildinfo 归一化比对 + amd64/arm64 函数表 diff |

动态环境跑完即销毁（`limactl delete`），未接触任何既有主机。

---

## 三、逐条回答

### 3.1 有没有往 ninebot.com 以外的地方发过任何东西？

**没有。** 四重独立证据：

| 证据层 | 结果 |
|---|---|
| 全二进制 `://` 字符串扫描 | 仅 5 个 ninebot 主机 + 依赖库文档链接（github/json-schema/go.dev）|
| mitmproxy 抓包（14 个子命令 + serve + 真实登录）| 仅 ninebot 主机，无第六个目的地 |
| nftables uid 级默认拒绝 | **0 次**绕过代理的直连尝试 |
| dnsmasq 全量查询日志 | 仅解析 ninebot 域名 |
| serve 空闲 300 秒 | 0 flow、0 DNS、0 外联 |

实测抓到流量的主机与完整 URL：

```
api-passport-bj.ninebot.com   POST /v6/user/login
                              POST /v4/code/phone
                              POST /v5/user
api-jhcx-v6-bj.ninebot.com    POST /user/user/login
ebike.ninebot.com             POST /vehicle/binding/my-vehicle
                              POST /vehicle/vehicle/desktop-component
                              POST /devices/control/engine_stop
steeldust.ninebot.com         POST /vehicle/binding/my-vehicle
```

**注意**：空闲期日志中出现的 8 条 `cdn.fwupd.org` 查询来自 Ubuntu 固件更新服务，
非 ninecli（dnsmasq 日志为全机范围，已核实来源后排除）。

### 3.2 账号密码除了换令牌之外还被用在哪？

**只用在一个请求里**，明文可读（TLS 内明文，非应用层加密——这是九号登录接口
自身的设计）：

```
POST https://api-passport-bj.ninebot.com/v6/user/login
Clientid: vehicle_app_prod   Os: Android   Os_version: 13
Sign: <SHA256>               Timestamp: <ms>

{"areaCode":"86","device":"ANDROID","password":"<明文>","username":"<手机号>"}
```

- **不落盘**：以真实密码全盘 grep，唯一命中是审计自身的 strace 文件。
- **不在 business_login 载荷里**。该请求体是 AES 加密的、明文 grep 无效，
  因此改用结构性实验判定：删除 `tokens.json` 中的 `business_uid`，让
  business_login 在一个**从未持有密码**的进程里通过 auto-fallback 触发——
  **它成功了**（`business_uid` 重新填充）。故 business_login 结构上不需要密码，
  加密载荷中不可能包含密码。
- **结构性论证**：每条命令都是独立短命进程（已证无守护进程、无监听），密码从不
  持久化，因此 `vehicles`/`status`/`battery`/`travel` 的进程中根本不可能存在密码。

### 3.3 令牌存在哪、权限是多少？

路径解析顺序：`$NINEBOT_CONFIG_DIR` → `$XDG_CONFIG_HOME/ninebot` →
`~/.config/ninebot`。

```
drwx------  .config/ninebot/     0700
-rw-------  tokens.json          0600
-rw-------  config.json          0600
-rw-------  vehicles.json        0600
```

目录与文件权限均由程序自己创建（在全新用户下验证，`.config` 此前不存在）。

`tokens.json` 字段：`uuid`、`username`、`phone`、`region`、`areaCode`、
`access_token`(JWT, 592B)、`refresh_token`(JWT, 640B)、`accessTokenValidity`
(13 位毫秒时间戳)、`business_uid`、`saved_at`。

`config.json` 内容（首次运行自动生成，随机 device_id 伪装 Android 设备）：

```json
{"device_id":"<32位随机hex>","region":"bj","area_code":"86",
 "os_version":"13","os_model":"Xiaomi"}
```

程序会主动提示 `replace device_id with a real captured value to mimic a real
device`——作者自己写明这是设备指纹伪装。

**`config.json` 的字段全集中不含任何 host / url / endpoint 项**，
故主机覆盖无法持久化（见 3.6）。

### 3.4 有没有起子进程或写配置目录之外的文件？

**都没有。**

- 14 个子命令全程 `strace -f`：`execve` 仅出现审计自身的 `timeout` 包装与
  ninecli 本身，**零个子进程**；`fork`/`vfork` 零次。
- 静态侧交叉验证：`os/exec` **不在**链接进二进制的 154 个标准库包中。
  （精确表述：`os`/`syscall` 必然被链接，`os.StartProcess` 理论仍可达，
  因此静态侧是强证据、动态 strace 才是确认。）
- 全盘 mtime 扫描：写入仅发生在 `~/.config/ninebot/` 内。

### 3.5 做不做证书绑定？

**不做。** mitmproxy 完整拦截全部流量，客户端拒绝 CA 次数为 **0**。

程序遵循标准代理环境变量（`HTTPS_PROXY`/`HTTP_PROXY`，含小写形式与
`ALL_PROXY`）与 `SSL_CERT_FILE`。设置代理后 **100% 流量经代理、零绕过尝试**。
这一性质是长期封堵方案能够成立的前提。

### 3.6 主机覆盖开关

5 个上游主机各有一个命令行覆盖开关，帮助文本标注 "testing/development"：

| flag | 默认主机 | 用途 |
|---|---|---|
| `--passport-base` | api-passport-bj.ninebot.com | 认证 |
| `--biz-host` | api-jhcx-v6-bj.ninebot.com | business_login |
| `--ebike-host` | ebike.ninebot.com | 车辆信息 + **控制** |
| `--motor-host` | steeldust.ninebot.com | 摩托业务线 |
| `--travel-host` | cn-cbu-gateway.ninebot.com | 骑行记录 |

**这意味着该二进制会把凭据发往这些 flag 指向的任何地方**，默认值只是那 5 个
ninebot 主机。减轻情节：这些开关**只能走命令行**，`config.json` 字段中不存在
对应项（已验证），因此篡改配置文件无法静默重定向凭据。封堵方案的代理层白名单
亦会拦截重定向后的主机名。

---

## 四、控制能力

四个顶层命令可物理操控车辆：

```
bell          POST /devices/control/bell           响铃寻车，无 y/N 确认
buck          POST /devices/control/open_buck      开座桶
engine-start  POST /devices/control/engine_start   上电解锁
engine-stop   POST /devices/control/engine_stop    断电落锁
```

`-y` / `--yes` 可跳过 y/N 确认。实测确认门在**网络调用之前**生效（无令牌时
`Continue? [y/N]` → `aborted.`，未产生任何请求）。帮助文本注明 "ACTUATES the
physical vehicle. Use only with the owner's consent while physically present."

审计过程中**未对任何真实车辆下发控制指令**。控制路径的目的地与请求格式是使用
故意无效的令牌捕获的（上游以 401901 拒绝），无需真实操作即完成取证。
审计包装器亦硬性拒绝这四个命令。

---

## 五、溯源：查不到人

- 模块路径 `gitea.com/ninebot/cli` **在 gitea.com 上不存在**（仓库页、
  `/api/v1/repos`、`/api/v1/orgs`、`/api/v1/users` 全部 404，全站搜索
  `ninebot` 零结果）。gitea.com 是公开注册的托管实例，任何人都可占用 `ninebot`
  这个组织名；而 Go 的 module path 仅是 `go.mod` 中的字符串、从不需要真实存在。
  该路径可能是私有仓库，也可能是编造来蹭官方品牌可信度。
- PyPI 元数据：作者 `ninecli contributors`，无姓名、无邮箱、无维护者、无主页、
  无源码仓库链接；声明 MIT 许可但从未发布源码。
- 8 个版本集中在 2026-06-21 至 07-01，最后更新 07-01。
- `vcs.modified=true`：发布的二进制是从**带未提交改动的工作树**编出来的，
  因此即使源码公开也不能假设二进制等于 commit `3ec468a5a739`。
- **唯一身份线索**：帮助文本泄露了作者本机绝对路径
  `/opt/dev/misc/ninebot/README_ninebot.md:110`（`-trimpath` 无法约束字符串
  字面量）。原句为 "the URL uses the long form, the op field uses the short
  form; see spec /opt/dev/misc/ninebot/README_ninebot.md:110"——这是作者给自己
  写的逆向笔记交叉引用。从事凭据窃取的一方会尽量减少此类独特指纹，这条弱证据
  指向真正在开发非官方客户端的个人开发者。

---

## 六、依赖与构建一致性

依赖清单干净，无第三方 HTTP 客户端、无分析/埋点 SDK：`cobra`/`pflag`（命令行）、
`segmentio/encoding`（快速 JSON）、`modelcontextprotocol/go-sdk` +
`jsonschema-go` + `uritemplate`（MCP 模式）、`x/sys`（系统调用）。

**8 个平台 wheel 全部比对**（8 个 wheel 实为 6 个不同二进制——同架构的
manylinux 与 musllinux 内嵌 ELF 逐字节相同，静态 CGO 关闭构建的正常结果）：

- 归一化 buildinfo（剔除必然不同的 GOOS/GOARCH/GOAMD64/GOARM64）后**只有 2 种**。
- 唯一差异：两个 Windows 构建多一行 `github.com/inconshreveable/mousetrap v1.1.0`。
  这**不是**危险信号而是反向证明——mousetrap 是 cobra 在 `windows` 构建标签下
  才引入的依赖（检测程序是否被资源管理器双击启动），按 GOOS 自动出现，恰好证明
  8 个 wheel 出自同一棵源码树的交叉编译。
- amd64 与 arm64 二进制的应用层函数表**各 197 个、逐条相同**，无按架构分支的代码。
  故 arm64 上取得的 syscall 层证据可外推至 amd64 二进制。

其他负面结论：

- 零遥测：`telemetry|analytics|sentry|bugsnag|posthog|mixpanel|amplitude|umeng|bugly|talkingdata|jpush|getui` 全部零命中。
- **无自动更新通道**：命令集中无 `update`/`selfupdate`，二进制内无远程代码拉取。
  版本只会因手动 `pip install -U` 而变化。

---

## 七、硬编码密钥

**只有一个真实密钥**，48 字节（AES-256 key + IV）：

```
key(32) 6a09224724a70834524ccebb6211ef2dcad448c9e7831265d00da58852c9c9da
iv (16) 67eb9139f288743e1b6efade0a9247de
```

**方向上无害**：这是**对称**密钥，只能与已知对端互相加解密，不具备 RSA/ECDH
公钥那种「单向加密外传给攻击者」的能力。

用途：business/ebike/travel 侧的请求加解密（`internal/crypto/wrapper.go` 的
`AESEncrypt`/`AESDecrypt`/`PKCS7Unpad`）。**passport 侧不使用它**，仅附加一个
`Sign` 头（SHA256）——这一点纠正了「整个客户端共用一套加密」的直觉。

business 请求体格式：

```json
{"d":"<AES密文>","h":"<32位校验>","k":"<128字节密钥封装>","p":"101","t":"0"}
```

响应：`{"v":101,"s":"<128字节>","r":"<密文>"}`

**未逆出明文**。这是本次审计的观测限制，需如实记录。但它不影响外传结论：
所有加密载荷的目的地都在那 5 个 ninebot 主机之内，默认拒绝规则确认不存在
第六个目的地。加密能隐藏的只是「九号自己额外收到了什么」（对九号的隐私问题），
隐藏不了「数据去了别处」。

其余长十六进制串经**精确版本基线对照**（用相同 import 集、相同 go1.25.0 编译
空程序做字符串差集）判定为 Go 标准库常量或泛型 shape 符号
（`go.shape.<64位hex>`），非密钥。

---

## 八、顺带发现的缺陷

`business_uid` 缺失触发 auto-fallback 时，business_login 的 base URL 为空，
报 `unsupported protocol scheme ""`——`--biz-host` 文档标注的默认值
`https://api-jhcx-v6-bj.ninebot.com` 在该路径上未被应用，需显式传参才通。

正常 `login` 路径不受影响（真实登录未传该 flag 即正确到达 api-jhcx-v6-bj）。
安全方向为 fail-closed（请求根本未发出，而非发往错误目的地）。

---

## 九、未覆盖项

如实记录，两项均为覆盖率而非风险：

1. **`cn-cbu-gateway.ninebot.com`（travel 主机）未抓到流量。** 需要有效的车辆
   缓存条目，而缓存 schema 未在假凭据阶段逆出（真实结构为
   `{"vehicles":[{"wnumber":…,"vehicle_name":…,"device_name":…,"business_line":"ebike"}]}`
   ——SN 字段名为 `wnumber` 而非 `sn`）。该主机是帮助文本标注的默认 travel 主机、
   已在白名单内。
2. **`status`/`battery`/`travel` 的完整请求路径未跑通。** 假凭据阶段这些命令在
   参数校验或令牌加载即退出；真实凭据阶段按审计者要求停止深入。

两项的目的地均在已知的 5 个主机内，不影响第一节结论。

---

## 十、长期封堵

配置见同目录 `containment/`，**已在沙箱实测 12/12 通过**。

### 核心设计决策：不能用 nftables 直接写那五个主机名

nftables 匹配 IP 而非域名。这 5 个主机位于 CDN 之后、IP 会轮换，写死 IP 的
白名单在数周内就会开始误杀正常请求——而**误杀日志与真实告警在形态上完全一致**。
规则一旦腐烂，当初安装它所要获取的那条信号反而先失效。故分两层：

| 层 | 文件 | 判定依据 | 为什么必须是这一层 |
|---|---|---|---|
| 域名白名单 | `tinyproxy.conf` + `ninebot-allow.txt` | 主机名 | 只有这一层看得见主机名 |
| 网络默认拒绝 | `nftables-ninecli.conf` | uid + 目的地址 | 使绕过代理不可能，而非仅不推荐 |

- 代理为 **CONNECT 直通**：只检查 CONNECT 行中的主机名然后拼接 TCP 流，
  不终结 TLS，因此无明文、无需安装 CA。
- 白名单正则**两端锚定**，防止 `ebike.ninebot.com.attacker.example` 这类
  后缀伪装（这是白名单退化为放行名单的经典方式）。已在验证脚本中作为用例断言。
- nftables 只陈述一句 IP 无关的规则：ninecli 的 uid 除本地代理外不得连接任何
  地址；**DNS 亦拒绝**（代理代其解析，直接消除 DNS 隧道外传通道）；其余默认
  拒绝并 `log prefix` 留痕。这句规则不依赖任何 IP，永不腐烂。
- input 链按端口封禁 18009/18010 对非 loopback 的访问，防止 `--bind` 误配
  将 serve/MCP 暴露到局域网。

### Docker 变体

出网边界使用 Docker 自身的 `internal: true` 网络，**而非手写防火墙规则**。
理由：Docker 自己生成的规则先执行，手写 nftables 在 Docker 宿主上经常被静默
旁路——看似安装成功、实际什么也没拦。`internal` 网络不可能静默失效，若其失效
则一个请求都出不去。配合非 root（`10001:10001`）、`read_only` 根文件系统、
`cap_drop: ALL`、`no-new-privileges`、唯一可写路径为令牌卷、无 `ports:`。

### 验证纪律

`verify-containment.sh` 通过**主动违反每一条约束**来断言，因为一条不生效的
规则与一条生效的规则从外部观察完全一致——直到出事那天。

装完跑一次，**每次升级 ninecli 后再跑一次**。脚本末尾会汇总这套笼子历史上
拦下的一切（内核日志 + 代理日志），那就是长期哨兵的读数：一次性审计抓不到
定时触发的载荷，只有常驻的默认拒绝规则能在它某天想连别处时留下带日期的痕迹。

### 升级纪律

- `pip install -U ninecli` 之后：重算 SHA-256、重跑 `verify-containment.sh`、
  用 `go version -m` 重新比对依赖清单，出现新依赖则重新审计。
- 无自动更新通道，故版本只会因手动升级而变化。

---

## 十一、这套笼子挡不住的事

1. **凭据本来就要交给九号。** 笼子保证密码只去 `api-passport-bj.ninebot.com`，
   但它确实以明文 JSON 发送（TLS 内，九号接口自身设计）。笼子管不了九号服务端。
2. **`-p` 密码进 argv**，且短信登录不可用（见条件 2），无法从工具侧消除。
3. **`serve`/`mcp --http` 默认无鉴权**（见条件 1）。
4. **5 个 `--*-host` 开关**能把凭据发往任意主机；无法写入 config.json，
   代理层白名单会拦截重定向后的主机名。
