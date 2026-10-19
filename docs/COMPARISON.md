# MoonVCS 与已有系统：组合价值，不是单项“首次”

资料核对：2026-10-17。下面是官方文档能力比较，不是这些系统的运行测试或性能排名。
“未核对”不代表不存在；Partial Clone 在不同系统中的对象、路径和历史语义不同。

| 系统 | 已存在能力 / 主要关注点 | 与本项目比较时的边界 |
|---|---|---|
| Git Partial Clone | Git 对象过滤、promisor、缺失内容 demand fetch | 非 MoonVCS 格式；过滤 Blob/Tree 与限制 Commit DAG 的 shallow clone 是不同机制 |
| Sapling | 面向大仓库的 VCS 客户端/服务端生态；EdenFS 按需填充工作区文件 | EdenFS 文件虚拟化不等同本项目逐个历史对象 Fetch；组件对外可用性有自己的支持边界 |
| Pijul | 以 changes/patches 为中心；按 change/依赖或 path 进行 partial clone | 不是 MoonVCS 的快照 Commit DAG，也不把它的 partial clone 直接等同我们的历史缓存 |
| Gitleaks | Git、目录、stdin 的 Secret 检测，可接 pre-commit/CI | 是扫描工具，不是这里的 VCS/ObjectStore；本项目不声称检测覆盖或精度超过它 |
| MoonVCS | 自定义 SHA-256 typed objects、文件系统 Lazy Fetch、WIT/MoonBit 策略、显式授权和本地/receive 发布门禁 | 小规模研究原型；无 Git 协议、认证/TLS/ACL/OS 权限分离，规则是 MVP |

Git 的上述语义见 [官方 Partial Clone 文档](https://git-scm.com/docs/partial-clone)。
Sapling/EdenFS 的职责与支持范围见 [官方仓库说明](https://github.com/facebook/sapling)。
Pijul 的 change/path 选项见 [官方 clone 手册](https://pijul.org/manual/reference/clone.html)，
change 模型见 [官方说明](https://pijul.org/manual/why_pijul.html)。
Gitleaks 的模式、Hook/CI 与配置见 [官方仓库](https://github.com/gitleaks/gitleaks)。

## 已存在能力，不作为发明宣称

Lazy Fetch、内容哈希标识、Secret Scanning、生命周期 Hook 都不是 MoonVCS 首创。
本表未逐项审计 Sapling/Pijul 的所有 Hook、扫描集成或第三方沙箱，不用空白格断言“没有”。
Git 本身已有 pre-receive 服务端拒绝机制，不能把服务端策略说成 Git 的空缺。
[Git hooks](https://git-scm.com/docs/githooks)

## 本项目实际探索的组合

1. MoonBit 同时实现 VCS Core 和规则插件，而 Rust 只提供受控 Wasmtime 宿主。
2. 同一个 WIT v1 对接多个插件，Manifest 请求与可信授予分离；Host 只复制授权数据且限制资源。
3. 策略决定实际 Commit/远端 Ref 发布，不是只输出扫描结果；独立服务端不信任本地结果。
4. CommitCandidate 与 verified Lazy ObjectStore 集成，在暂存字节和需要的历史上建立显式验证边界。

这是本项目的工程组合定位，不是经过文献穷尽检索的全球首创结论。
跨宿主 ABI 复用只有潜力声明；实际运行证据限于 Wasmtime。
[逐项宣传证据](CLAIMS.md) · [架构](../ARCHITECTURE.md)

## 与普通 Git Hook 的比较应怎样说

客户端 pre-commit 可以跳过；服务端 pre-receive 能拒绝更新。这两个信任位置必须分开讨论。
Hook 也可以调用 Wasm 或 OS 沙箱程序，不能说“Git Hook 无法安全执行策略”。
MoonVCS 在自己的最小 VCS 内固定了版本/摘要、WIT 请求、授权过滤、预算和门禁一致性，
代价是缺少成熟生态与完整版本控制功能。

没有进行 Git/Sapling/Pijul/Gitleaks 性能测试。尤其不能用 Git full clone 的网络耗时与
MoonVCS 本地 partial clone 相比，来宣传全面更快。[本地基准范围](BENCHMARKS.md)
