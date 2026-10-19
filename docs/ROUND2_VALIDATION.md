# 第二轮：请求内验证复用、版本化归档与人工恢复协议

本页保留第二轮 146 项宿主回归的完成范围。随后新归档安装验收的失败、续期修复与重跑
单列于 [安装记录](FRESH_INSTALL_VALIDATION.md)，不将历史结果改写为新验收。

本轮不修改 WIT v1、对象编码、策略模块字节或能力模型。没有增加网络部署、身份认证、
ACL、TLS、OS 权限分离、Host/JIT 总 RSS 控制或缺失的 VCS 命令。

## 单次 get 的来源验证

LazyObjectStore.get 在现有 repository fetch lock 内创建 PromiseValidation，退出/异常后即丢弃，
不存到 Store、全局对象或磁盘。已验证来源只保留实际对象类型与 (ObjectId, kind) 边索引，
不保留整个来源对象。目标在校验 hash、规范解码、promise 类型后可作为当前请求的已验证来源。
初始的单条入边检查和 state 走原来的验证路径，不为只用一次的来源建立索引；
索引复用只用于随后批量的出边检查，避免给普通 Blob 读取引入整棵来源 Tree 的索引分配。

每条 promise 的 schema/id/anchor/kind、source 格式、来源文件存在、来源 provenance record
和来源实际类型仍检查；缓存键是来源 ID，边键含目标类型。不会用当前 Tree 的边替代另一来源的边。
同一次协作锁内依赖内容寻址对象不可变；不宣称抵抗绕过锁直接改文件的同账户攻击。
下一次 get 重新读取并验证来源 hash，不接受跨请求的“永久可信”状态。

最多索引 16 个来源和 16384 条原始边；超限走原先的来源读入、hash/解码和线性边检查，
不是跳过校验或新增拒绝。这个计数预算不是精确内存/RSS 配额。

新增 6 个 native 测试覆盖带类型的边键、预算、同一上下文重新核对 provenance/type/存在性、
下次 get 检出已损坏来源、修改 child promise、不同合法来源却没有对应边、超限回退。
独立 CLI/pread 测试先对冻结旧二进制失败（33 次读取），再对新二进制通过（1 次）。
32 文件 fixture 同时断言 promise 元数据读取 66 次，离线重复读取不传输。

## 配对性能结果

从第一轮真实 required-Wasm-policy 数据集复制私有缓存：10000 对象、20 快照、498 文件/快照。
同一 Tree、同一 promisor、两份冻结 CLI，3 组交错 before/after；每组一次 authorized miss 和
3 次 offline hit。miss 只从自建缓存副本去掉目标 Tree；原数据集、promise 与来源对象不变。
输出 SHA-256 相同；每次 miss 恰好传输 1 个 Tree（39862 字节），重复读取零传输。

| 指标 | 修改前 | 修改后 |
|---|---:|---:|
| CLI SHA-256 | bd6ee906a54625700a4ead37c63cdf8f2036447ca95ecb86792afdbc4c8baafc | 903c0bb594f67498537b48c41d2c8a00fa80abbc6e239f9aa01a6d184d70cd2e |
| miss 中位，3 个样本（ms） | 2131.81 | 1005.63 |
| hit 中位，3 组共 9 次（ms） | 2093.86 | 961.39 |
| 同一 Tree 逻辑读取次数 | 499 | 1 |
| 所有对象逻辑读取次数 / 字节 | 500 / 19891329 | 2 / 40053 |
| Promise 逻辑读取次数 / 字节 | 998 / 249502 | 998 / 249502 |

这是同机、暖 OS 缓存下该数据形状的完整 CLI 测量；不是三档正式基准重跑、p99/SLA、
Git 对比、物理磁盘流量或通用“缓存总是更快”的保证。第一轮 Callgrind 是历史指令证据，
本轮没有重新测 CPU 时间占比，也不把所有剩余耗时归因于某条路径。
P7-001 的重复来源验证已针对性缓解，宽 Tree 读取仍接近 1 秒，不能标记为整个性能风险关闭。

~~~bash
python3 scripts/compare-lazy-get.py --profile target/roadmap-profile-01 \
  --before target/lazy-get-round2-before/moonvcs --workdir target/lazy-get-compare-new
~~~

首次数据集建立方式见 [第一轮记录](ROADMAP_PROGRESS.md)，上述命令依赖该数据集与修改前二进制。
最终原始结果在 target/lazy-get-round2-compare-final/result.json、before-io.json、after-io.json，
旧版失败在 target/reports/lazy-get-round2-io-before.log，不覆盖阶段 7/第一轮历史数据。
先前索引初稿的配对记录保留在 target/lazy-get-round2-compare/，当时 hit 为 2121.51 → 971.84 ms；
随后为一次性入边检查避免索引分配，重新编译/配对得到上表，不将旧 CLI 的数据当作最终字节的测量。

## 固定工具归档

按[官方安装器](https://cli.moonbitlang.com/install/unix.sh)的 VERSION 规则，
正确版本是编译器完整版本 0.10.15+943464bfa，不是 moon 日期版本 0.1.20261012。
本轮从 scripts/moonbit-archives.lock.json 中两个明确版本 URL 实际下载并检查长度/SHA-256，
与第一轮已运行工具的 compiler/core 字节完全相同，未重新生成绑定或改插件 pin。
原来按日期拼地址的 403 记录保留；找到新地址不会将原失败改写成成功。

fresh-install.py 默认不再使用 latest；可传 --archive-dir 从维护者保存的内容寻址目录取归档。
本地缺失、损坏、超长或静态符号链接均失败，不回退网络或 latest；verify 不修改目录。
归档有 4 个独立无网络测试，实际本地归档核验也通过。

~~~bash
python3 scripts/toolchain_archives.py download --directory target/moonbit-archive-new
python3 scripts/toolchain_archives.py verify --directory target/moonbit-archive-new
python3 scripts/fresh-install.py prepare --workdir target/roadmap-fresh-new \
  --archive-dir target/moonbit-archive-new
python3 scripts/fresh-install.py verify --workdir target/roadmap-fresh-new
~~~

download 只接受不存在的新目录。维护者应独立备份完整 sha256 目录及源码中的锁文件，
在新机器上先 verify，再 prepare。target 会被清理/忽略且不在源码包中，不能把本机唯一副本当长期归档。
这里没有自动上传或新建公开镜像，也不保证上游永不删除版本 URL；长期托管、备份保留和分发许可仍需安排。
摘要验证不等于作者身份/签名验证；本地 MoonBit 归档也不包含 Rust、镜像层或 registry 的离线分发。

证据：target/moonbit-archive-round2/archive-report.json、
target/reports/toolchain-archive-round2-{download,local-verify}.log。
第一轮隔离 rootfs 的 134 项安装回归保持历史结果；本轮没有重新执行整个 rootfs 安装，
不能把新安装脚本或新增测试称为已通过新的全新环境完整验收。

## 恢复协议

见 [RECOVERY.md](RECOVERY.md) 的人工协议 v1：先停止写入并保留完整状态，在副本做语义检查，
按精确 index/Ref/候选状态决定不重试、正常新操作或停止处理；不直接发布遗留锁或隔离对象。
稳定 advisory-lock inode 不移动；未知归属不清理；确认中止的精确路径只保留到私有证据目录。

7 个恢复测试通过，新增 Ref 发布后 EIO 的真实退出 16；已有测试补充保留 index.lock 后重试 add、
保留已终止 Quarantine 后重新 receive，以及 index 已可见时重新 add 的收敛检查。
这些是临时测试库的受控人工流程，不是自动恢复、日志重放、GC 或掉电证明。

## 当前回归

完整 scripts/test.sh 已实际重跑并退出 0：
146 = 70 native + 26 Rust + 19 Wasm + 9 系统审计 + 6 harness +
4 暂存 + 7 恢复 + 1 读取计数 + 4 归档。另有 CLI 与双轮四场景 smoke，未重复加入测试计数。
原始记录：target/reports/round2-regression.log；避免一次性索引后的最终重跑记录为
target/reports/round2-regression-final.log。没有将分项通过代替整套结果，
也没有把第一轮 rootfs 的 134 项报告改成 146。
