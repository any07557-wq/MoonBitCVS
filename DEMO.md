# 三分钟演示与录制

## 展示主线与边界

聚焦五项已有证据：MoonBit Core、真实 Wasm 策略、显式权限、提交/接收门禁、按需历史。
四个现有场景分别展示策略真正阻止提交、权限过滤与拒绝、校验后的按需获取，
以及本地文件系统/stdio receive 入口独立检查未扫描候选。
不要把它扩展成生产远端安全、完整 Git、缓存加速或所有平台安装已完成的宣称。
全新环境安装、宽 Tree 优化、并发暂存修复和异常恢复按[最新执行记录](docs/ROUND2_VALIDATION.md)
区分完成与待验证；不要把四项整体说成已完成。三分钟仍使用现有五项主线、顺序命令与无害 fixture。

## 台前准备，不计入三分钟

使用无害 fixture；不要编辑真实 SSH Key、HOME 凭据或用户仓库。
从项目根目录构建，再准备 40 次真实策略提交：

~~~bash
export MOONVCS_MOON="$HOME/.moon/bin/moon"
./scripts/build-vcs.sh
python3 scripts/hackathon-demo.py prepare --workdir target/hackathon-demo --commits 40
python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo --only all
~~~

prepare 只接受不存在的目录；已有该目录时直接 run，或选择一个新的工作目录。
run 每次建立独立演示仓库，打印实际命令，并断言返回码、对象/Ref 状态和敏感 fixture 不泄漏。
它调用真实 MoonBit CLI、MoonBit Wasm 和 Wasmtime，不使用 Mock 决策。
构建与准备可能花费较久，不能临场下载工具链。

## 三分钟节奏

| 时间 | 操作与屏幕 | 讲述重点 |
|---|---|---|
| 0–30 秒 | README 的系统架构图 | Hook 可以运行检查，但扩展能看什么、失败能否阻止发布、历史何时下载，是三个独立问题。MoonVCS 探索它们的组合，不是再做完整 Git。 |
| 30–80 秒 | --only secret | 真实暂存内容进入 MoonBit Wasm Scanner；Reject 时 HEAD 不变，修复且重新暂存后才创建 Commit。 |
| 80–125 秒 | --only capability | 同一 WIT v1：授权读取 Pass；缺少 grant 和过量请求都被 Host 拒绝。不是“声明即授权”。 |
| 125–155 秒 | --only lazy | 现场读出 N/M/字节数；旧 Commit 缺失时 Fetch、校验和缓存；重复读无传输。 |
| 155–170 秒 | --only remote | 经 receive 入口提交的未扫描候选仍被 required Wasm policy 拒绝；这不是 OS 权限隔离演示。 |
| 170–180 秒 | 结尾一页 | Core 与策略主要用 MoonBit；Rust 提供窄 Host。独立 rootfs 复现通过，但认证/TLS/OS 权限分离、跨平台和完整恢复仍未完成。 |

这是讲述时间分配，不是性能数据。命令本身在本机只需数秒，应在每段输出后停下来解释。
不要把整段自动输出速度当作观众理解速度。

## Demo 1：Secret Scanner 真正阻止提交

~~~bash
python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo --only secret
~~~

脚本现场创建 config.env，写入无害模拟 API key，实际执行 init、add、commit。
预期看到：

    Commit rejected
    Policy: secret-scanner
    File: config.env | Rule: secret.api-key | Severity: error
    Reason: suspicious credential

此时脚本断言 HEAD 未产生、没有正式 Commit 对象、index 不变。
Blob/Tree 是候选数据，可能已经保存；这不等于已发布 Commit。
随后把内容改为 APP_MODE=demo，重新 add 并 commit，看到：

    Policy passed
    Commit created

讲述：“扫描的是 Stage 快照；只改工作区、不重新 add，仍会拒绝旧的暂存 Secret。”
拒绝输出不包含完整模拟值。Scanner 是演示规则，不是完整 DLP 或 Gitleaks 替代品。

## Demo 2：真实 Capability 边界

~~~bash
python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo --only capability
~~~

Restricted Plugin 也由 MoonBit 编译，并使用与 Scanner 相同的 WIT v1。
它只读取允许文件的字节，确认 commit metadata 已被过滤。

| 场景 | 实际结果 |
|---|---|
| staged_content.read 有 grant，数据已过滤 | 插件返回 Pass |
| 同一插件没有 repository grant | Host 返回 CapabilityDenied，退出 3 |
| 篡改 Manifest 请求 repository.secrets.read | Host 返回“不提供该能力”，退出 3 |

有效能力 = Requested ∩ Granted ∩ Host Available。
这里是“传入已授权数据”的 ABI，没有任意文件读取回调。
repository.secrets.read 根本不是已实现的 Host API；拒绝发生在实例化前，
不能说“插件读取 SSH Key 的回调被拦截了”。

无 imports/空 Linker 和模拟 HOME/SSH 资源测试由安全回归单独证明，
本演示不读取真实敏感文件，也不添加泄漏接口。
权限图见 [sandbox.svg](docs/diagrams/sandbox.svg)。

## Demo 3：Lazy History 的真实数字

~~~bash
python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo --only lazy
~~~

脚本独立遍历对象文件并校验 SHA-256，同时与实际 storage-stats 比较：

| 2026-10-17 的 40 提交演示 | 对象 | 规范编码字节 |
|---|---:|---:|
| 远端完整历史 | 120 | 12976 |
| 初始 clone 的 HEAD + Tree + Blob | 3 | 326 |
| log --max-count 4 后缓存 | 6 | 893 |
| 重复 log 的新增传输 | 0 | 0 |

数字来自该次真实运行；脚本不会硬编码这些预期数字。
如果改变历史长度/文件内容，应以现场结果为准。字节数不包含 Ref/承诺元数据或磁盘块开销。

本演示证明按需获取、校验、缓存及重复读取无新增传输，不证明“缓存读取更快”。
历史 10000 对象、498 文件快照基准中，同一 Tree 的缓存读取约 2.17 秒、首次约 1.86 秒，
是尚未解决的 P7-001。不能用这次小型演示的快速输出掩盖宽 Tree 瓶颈。

旧 Parent 是从已验证 Commit 的直接引用逐步发现的，并非预先知道所有旧 ID。
首次访问出现：

    [Fetch] Local Cache Miss ...
    [Fetch] Remote Fetch ...
    [Fetch] Hash Verified ... bytes=...
    [Fetch] Cached ...

再次读取无 Fetch；--offline 能读缓存，未缓存且有合法 promise 的对象返回
ObjectUnavailableOffline。此处使用显式 offline 标志，不把它描述成拔网线实验；
真正移走模拟远端的用例在阶段 5 测试中。Unknown 对象不会盲目探测远端。
[Lazy 数据流图](docs/diagrams/lazy.svg) · [历史实测与性能限制](docs/BENCHMARKS.md)

## Demo 4：绕过客户端，服务器仍拒绝

~~~bash
python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo --only remote
~~~

先真实提交安全基线并推送到独立初始化的服务器。
测试专用 moonvcs-bypass-client 随后直接编码未扫描的客户端候选对象和 receive bundle，
没有“伪造一个已通过的客户端检查结果”参与服务器放行。

独立 receive 使用服务器配置执行真实 MoonBit Wasm Scanner，返回 Push rejected（退出 12）。
脚本继续断言服务器 HEAD/策略不变、正式对象库存不变、Quarantine 清空，
被拒绝的 Commit 在服务器查询为 Unknown。

讲述：“不信任客户端结果，服务器自己扫描目标可达的全部线性历史快照。”
只支持本地文件系统/stdio 原型、单 Ref、线性历史；同 OS 账户不是安全部署边界，
没有认证、ACL、TLS 或服务端 OS 权限分离。同账户可以直接修改服务器文件，
独立进程不能阻止这种绕过；本演示只验证 receive 入口，不测试或宣称抵抗直接磁盘篡改。
Wasm 插件的能力边界也不等于原生客户端/服务器的 OS 权限边界。不能把演示包装成生产安全服务。

规模说明：只支持单 Ref、线性 fast-forward/新分支；4096 个不同图对象、128 个 Commit 的上限
覆盖候选目标全部可达历史，包括服务器已有祖先，不是仅本次上传。每次仍重扫完整历史快照，
没有审批复用；小型演示不证明长历史接收性能，本地 10000 对象基准也不是 receive 基准。

## 真实终端录制

~~~bash
./scripts/record-demo.sh target/hackathon-demo
~~~

需要 util-linux script。脚本保存真实 PTY 流 terminal.typescript 和 timing.log，
打印 scriptreplay 命令；这是终端录制，不是 MP4，也不是制作出来的终端截图。
每次 demo 还会生成：

    target/reports/phase8-run-*/terminal.txt
    target/reports/phase8-run-*/result.json
    target/reports/phase8-recording.*/terminal.typescript
    target/reports/phase8-recording.*/timing.log

result.json 保存实际 argv、cwd、预期/实际退出码、耗时和状态断言。
录制中提及的路径是当次机器路径，不是可直接在另一台机器复用的仓库。
[source 脚本](scripts/record-demo.sh) · [最终交付报告](docs/PHASE8_DELIVERY.md)

## 现场失败处理

- 工具缺失、摘要漂移或策略无法启动：停止并展示错误，不改 pin、不禁用 required policy。
- 准备目录已存在：复用完整的 demo-state.json，或另选新目录；不删除用户数据。
- 自动脚本非零退出：视为失败，保留 result.json 和日志；不要手工改为 passed。
- 只能回放时：明确标注“此前本机真实运行录制”，不冒充现场成功或新环境验证。

提交拒绝 2、权限错误 3、离线缺失 4、远端策略拒绝 12 是本演示主动断言的子命令退出码。
自动编排全部断言通过时最终返回 0；意外结果则返回非零。
