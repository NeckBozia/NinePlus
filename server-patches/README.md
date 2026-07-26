# 社区服务端的补丁

给 [`wuchiawuchi/nineplus-ha-server`](https://github.com/wuchiawuchi/nineplus-ha-server) 的 fork 用。放在这里是因为 fork 还没建，建好之后直接 apply。

## 基线

补丁是对着 `main` 分支的 `server.py` 做的：

```
sha256  89f24d84b8e5d53abe02fca55e4e4991d1ff425cec55f3a9ee967faf02c58acd
行数    609
```

上游改过就先核对一下再打。打法：

```bash
cd <你的 fork>
git apply --check server-patches/0001-cache-and-persist-sessions.patch   # 先试
git apply        server-patches/0001-cache-and-persist-sessions.patch
```

打不上就照下面「改了什么」手改，改动一共四处，都不长。

---

## 0001 · 请求缓存 + 会话落盘

### 为什么

**一次车况刷新会起 5 到 10 个 ninecli 子进程，串行。**

`DirectNinebotClient.run()` 每次都 `subprocess.run` 起一个新的 8.9 MB Go 二进制，而且被 `self._lock` 串行化。数一下 `GET /vehicles/{sn}/dashboard`：

| 来源 | 调了什么 |
| --- | --- |
| 路由里的 `ensure_vehicle(sn)` | `vehicles` |
| `dashboard()` 里 | `status` |
| | `battery` |
| | `travel --month` |
| | `vehicles`（**第二次**，只为了从列表里挑出这辆车） |

**5 个。** 更糟的是 `GET .../status` 和 `GET .../battery` 各自也会构造一整个 dashboard 再丢掉四分之三 —— 而 iOS 在这个服务端上**恰好走的就是 status + battery 那条兜底分支**（响应里没有 `state` 键），所以一次刷新是 **10 个子进程**。

Widget 那边的超时硬上限是 12 秒。

### 改了什么

**一 · `run()` 加 TTL 缓存**（默认 45 秒，环境变量 `NINEPLUS_CACHE_TTL` 可调，设 0 关闭）

- 只缓存四个读命令：`vehicles`、`status`、`battery`、`travel`
- 其余命令（`login`、`bell`、`buck`、`engine-start`、`engine-stop`）**不缓存，而且会清空缓存** —— 控车指令刚改了车况，缓存的读结果立刻作废。App 在开锁后马上刷新拿到的是新数据，不是旧的
- 锁内二次检查：并发的 N 个刷新只会起 1 个子进程，剩下的等着复用。少了这一步，三个人同时刷新还是三份开销
- 存进缓存和取出来都 `deepcopy`，避免调用方改到缓存里的对象

**二 · `dashboard()` 不再查两遍车辆列表** —— 结果存进局部变量复用。有了缓存这条其实也不会真的多起进程，但少一次调用总是对的。

**三 · `dashboard()` 的月份改用 UTC** —— 原来是 `datetime.now()`，负时区的服务器在每月 1 号会问错月份。

45 秒 TTL 下，一次刷新从 10 个子进程降到 4 个（首次）或 0 个（缓存内）。

### 会话落盘

**为什么**：会话原先只存在内存里的一个 dict。**容器一重启，所有人同时 401**，而 iOS 客户端**完全没有 401 恢复路径**（`clearLoginResult()` 定义了但一个调用点都没有），表现是一直报错，直到手动重新绑定账号。

**改了什么**：会话写到 `<accounts.json 同目录>/sessions.json`，启动时读回来。

- **只存 token → 账号 的映射**，账号记录启动时从 `AccountStore` 重新读 —— 密码哈希和盐不会被复制进这个文件
- 原子写（先写 `.tmp` 再 `replace`），文件权限 `0600`
- 新增了一个 `AccountStore.record_for(account)`，按账号取记录、不校验密码。**只能用于从磁盘恢复已签发的会话，不要在任何登录路径上调它**（注释里也写了）
- 没有加会话过期。iOS 侧没有 401 处理，长期有效的 token 反而是我们想要的；要加过期得先在客户端补 401 处理

管理端会话（`_admin_sessions`）**没有**落盘 —— 重启后要重新登录管理后台，这是对的。

---

## 还没做的两条

按优先级排在这之后，等主要功能推进到那一步再说：

| | 改什么 | 大概 |
| --- | --- | --- |
| `travel-sync` 空桩 | `server.py:556-559` 现在恒返回 `{"month":…, "records": [], "total": 0}`。改成真的调 `travel`，并且键名 `records` 改成 **`list`** —— 客户端读的是 `list`（`NinebotServerClient.swift:532`），现在即便有数据也对不上 | 约 5 行 |
| `/healthz` 在鉴权闸门前面 | 路由在 `server.py:516`，鉴权检查在 `521`。所以 Bearer Token 填错时「测试连接」照样显示「服务器连接正常」。挪到鉴权之后，或者客户端改成打 `GET /vehicles` 测连通 | 1 行 |

---

## 怎么验证这个补丁

```bash
# 语法
python3 -c "import ast; ast.parse(open('server.py').read())"

# 缓存生效：连打三次 dashboard，看第二三次的耗时
time curl -s -H "Authorization: Bearer $TOKEN" -H "X-NinePlus-Session: $SESSION" \
     "http://127.0.0.1:19009/vehicles/$SN/dashboard" > /dev/null
```

四件事要看到：

1. **第二次明显变快**（子进程没起）
2. **控车指令之后立刻刷新，数据是新的**（锁车状态变了）—— 验证缓存清空生效
3. **重启容器之后 App 不用重新登录** —— 验证会话恢复，启动日志里会打印 `restored N app session(s)`
4. **`sessions.json` 里没有任何密码字段**，权限是 `600`
