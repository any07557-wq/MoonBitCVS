# 路线图执行记录 — 2026-10-18

本页保留第一轮快照；当前请求内优化、固定版本归档、恢复协议及 146 项回归见
[第二轮验证](ROUND2_VALIDATION.md)。下文“未优化”和 134 项只属于第一轮，不覆盖后续修改。

本轮从计划进入实际代码与验证。WIT v1、规范对象编码和五个插件 pin 不变，
没有开放网络接收服务、认证/ACL/TLS 或服务端 OS 权限分离。

## 工作包状态

| 工作包 | 本轮进展 | 剩余边界 |
|---|---|---|
| 全新环境安装 | 已通过独立 OCI rootfs 工具安装、134 项完整回归和四场景演示；未挂载宿主工具/registry 缓存 | 共享宿主内核；不是物理空白机器、全平台或离线分发证明；安装修复与失败日志保留 |
| 宽 Tree 剖析 | 完成独立数据集、Callgrind 指令计数和逻辑 pread 计数 | P7-001 未优化；不是新的正式三档基准，也不是采样 CPU 时间占比 |
| 并发暂存 | 稳定复现旧二进制丢失更新；修复完整读改写事务锁 | 只保护协作的当前版本写入者，不解决敌对同账户磁盘访问 |
| 异常恢复 | 关键目录同步、Quarantine lease、只读 recover --check、受控 SIGKILL/EIO 检查 | 没有日志重放、自动清理、GC、完整掉电恢复；此工作包仅部分完成 |

## 1. 新环境与安装可移植性

scripts/fresh-install.py 从官方 Rust OCI 镜像下载隔离 rootfs，经 bwrap 运行，
仅共享宿主内核，没有挂载宿主用户目录、工具安装或依赖缓存。
基础系统内的 GCC/Python/Rust 来自下载镜像，不是宿主对应安装。
镜像清单/层按 SHA-256 校验；编译器/核心归档也固定 SHA-256，不静默追随 latest 更新。

- Rust Linux/amd64 image:
  docker.io/library/rust@sha256:5f29c3b4cb8ad8c6f10df979595582dd67dd146ffebc70718e24ff2e5b4a194d
- MoonBit archive SHA-256:
  24b93a5409d2a4fb8e3d1b84b473f27b63476cef4418094764df96cb26b03c09
- Core archive SHA-256:
  96d30f4dbcc6a9e1736ef26fbdd0e8fb0e97cb01d50e55d2a0072208b8061ae5
- Compiler: moon 0.1.20261012 / moonc 0.10.15；Rust/Cargo 1.99.1；
  image 内 GCC 12.2.0、Python 3.11.2。

第一轮按 moon 日期版本拼接的 MoonBit URL 返回 403；当时采用官方 latest 路由加固定摘要，内容漂移即失败。
编译器摘要对照了官方发布校验和；core 摘要来自本次 HTTPS 下载后的本地锁定，
不是声称独立验证过发布者签名。基础镜像的内容校验同样不等于签名/作者身份认证。
未来若旧内容从 latest 消失，安装会明确失败，仍需要长期可获取的归档方案。

首次准备失败：编译器归档依赖安装器额外设置可执行权限，本轮手动解包漏掉了该步骤。
已修正脚本并保留原失败日志；不会将失败记录删除。首次完整回归又发现最小 Rust 镜像缺少 rustfmt，
实际停止于 cargo fmt；已将该组件加入安装前提，并保留失败日志/源码快照后重新构建。
之后还实际复现了空 Mooncakes registry 无法解析 gmlewis/sha256、moonbitlang/async；
验证流程已显式加入 moon -C vcs update。此失败同样保留，没有用宿主 registry 替代。
随后安全测试真实暴露了写死 .toolchains/cargo/bin/wasm-tools 的路径，回归退出 127；
已修正安全脚本、独立 imports 审计、环境记录和绑定生成脚本的 PATH 回退，
补充显式路径/项目本地/PATH 三种工具解析顺序的回归。旧失败日志继续保留。
镜像内 GCC 12.2 还报告第三方 moonbitlang/async C 代码的 posix_spawn_*_np 隐式声明警告；
没有编辑下载依赖，也不宣称 C 编译零警告。它与 MoonBit --deny-warn 是不同检查。
工具安装日志、后续冷源码构建与演示结果
位于 target/roadmap-fresh-01/report.json 及其 stage log。

最终报告 status=passed、installation_verified=true：

| 阶段 | 退出码 | 用时（秒） | 日志 |
|---|---:|---:|---|
| 工具准备 | 0 | 594.71 | toolchain-prepare-2.log |
| 补装 rustfmt | 0 | 3.07 | install-rustfmt-4.log |
| 最终源码副本 registry 初始化 | 0 | 13.81 | moon-registry-bootstrap-8.log |
| 完整回归，134 项及 CLI/smoke | 0 | 322.41 | fresh-regression-9.log |
| 40 次真实提交准备 + 四个 Demo | 0 | 16.97 | fresh-four-demos-10.log |

安装不是首遍无错：上文四类问题分别对应原始非零阶段，均留在报告中。
初始 registry 从空开始；重试只使用此隔离安装自行下载的依赖缓存，每轮源码均无项目构建产物。
最终 Demo 实测远端 120 对象 / 12976 字节，clone 3 / 326，历史读取后 6 / 893，重复传输 0。
被测试的 184 个源码文件清单 SHA-256：
1f74820d4fd07c9e1b0b30e25d1523378120e2bca37858e4b52fcc684c9ec67a。
结果后只更新交付文档和证据打包清单；运行代码、测试和构建逻辑与该源码清单一致。

构建脚本现在在没有项目 .toolchains 时支持 PATH 中的 Cargo/wit-bindgen/wasm-tools，
已有项目本地工具优先，显式指定的工具仍必须通过版本检查。

~~~bash
python3 scripts/fresh-install.py prepare --workdir target/roadmap-fresh-new
python3 scripts/fresh-install.py verify --workdir target/roadmap-fresh-new
~~~

要求 Linux、bwrap、宿主 Python 3.12+（安全 tar filter）与网络；新目录必须不存在。
网络或命名空间不可用应报告失败，不回退为宿主缓存安装。prepare 成功仅为工具准备，
只有 verify 的完整回归和四个实际演示成功才设置 installation_verified=true。
这不是 Windows/macOS、独立物理机器或脱离共享内核的 VM 安装证明。

参考：[MoonBit 下载与校验](https://www.moonbitlang.com/download/)、
[Rustup 自定义目录](https://rust-lang.github.io/rustup/installation/index.html)、
[OCI Registry API](https://distribution.github.io/distribution/spec/api/)。

## 2. 宽 Tree：从推断到指令/IO 证据

脚本冻结本轮修改前的 CLI：
539c4b61fb3ce2d1e7dfcfda03eecfa53698124279c7c494b19029df765f78af。
用真实 required-Wasm-policy 提交构造 20 个快照、每个 498 文件、10000 个对象。
在同一历史 Tree 上读取，独立验证缓存/来源对象的 SHA-256 和实际传输计数。

这是一档剖析数据集，不重写阶段 7 的三档/三样本历史基准。
本次非插桩完整 CLI 的首次 Tree 读取 1797.76 ms，三次缓存读取中位 2116.95 ms；
重复读取仍零新增传输。数据形状相同，但机器调度/同时进行的构建不同，不能当作严格前后性能比较。

CPU 采样计时器不可用，gprofng 记录 itimer could not be set；
保留该失败/IO-only 实验，不把默认函数表当作 CPU 采样。
随后改用 [Callgrind](https://valgrind.org/docs/manual/cl-manual.html) 指令计数：

| 指标 | 实测 |
|---|---:|
| 整个进程指令数 Ir | 5,817,457,165 |
| decode_verified_storage_object inclusive Ir 占比 | 95.18% |
| decode_object inclusive Ir 占比 | 54.22% |
| object_id_for_bytes inclusive Ir 占比 | 40.96% |
| 同一个约 39862 字节 Tree 的逻辑读取次数 | 499 |
| 同一 Tree 的逻辑读取总字节 | 19,891,138 |
| 所有对象的逻辑读取次数 / 字节 | 500 / 19,891,329 |
| Promise 元数据读取次数 / 字节 | 998 / 249,502 |
| 额外远端传输 | 0 |

inclusive 指令归因不是 CPU 时间百分比，父子调用路径有包含关系，不能任意相加。
异步调度/线程池也影响调用归因；不声称精确测出每个路径的实际时延占比。
逻辑 IO 通过独立 LD_PRELOAD pread 观察器计数，不记录文件内容，未链接入正式程序；
这些是逻辑读取，不是物理磁盘流量，也不能用插桩后的耗时作加速基准。

直接证据支持：已有 promise 的逐边验证反复读取同一个来源 Tree，并重复执行哈希/解码。
本轮仅分析，没有缓存信任机制优化，不跳过完整性/provenance 检查，P7-001 保持未解决。

后续优化候选是单次 get 内复用已经验证的来源对象及其直接边索引，避免为每个子项重读整个 Tree。
这尚未实现，必须继续检查每份 promise、类型、来源关系和损坏数据；不应直接增加跨请求的永久信任缓存。

~~~bash
python3 scripts/profile-wide-tree.py --workdir target/profile-new --objects 10000
~~~

需要 gprofng、Valgrind/Callgrind、cc。完整原始记录：
target/roadmap-profile-01/result.json、callgrind.out、cpu-instructions.txt、io-counts.json。
CPU 采样不可用时使用指令计数；输出会区分两种口径。

## 3. 暂存：已复现并修复

tests/staging_concurrency.py 与测试专用 C 屏障在实际 pread 之后同步两个旧 CLI 进程：
两者均退出 0，但 index 最终只有 second.txt。原始记录：
target/reports/roadmap-staging-before.json。

修复在读取 index 前取得 staging-transaction.lock，并持有到完整读改写结束。
等待有 30 秒上限，冲突返回 StagingBusy（15）；普通异常、取消和进程死亡不依赖删锁文件释放 OS 锁。

验证包含：确定性交错、8 个进程写入不同路径、失败 add 保留 index、持锁进程 SIGKILL 后可继续，
以及取消等锁任务的 native 回归。旧 index.lock 依旧保留；不知道归属的文件不会自动清理。

## 4. 恢复：有边界的第一步

对象/元数据/Ref 关键发布路径增加目录同步。
rename 后目录同步失败明确返回 PublicationUncertain（16），避免将已可见状态误称回滚。
Quarantine 增加 active.lock lease；recover --check 可区分活跃、已失活 lease 与未知旧格式，
但只读，不删除、不重放、不发布。详情见 [RECOVERY.md](RECOVERY.md)。

6 个独立故障/检查测试覆盖 index 发布前后 SIGKILL、Quarantine 活跃/终止、未知目录/模拟符号链接、
实际目录同步调用、rename 后 EIO。测试只使用自建临时仓库，不接触真实敏感资源。
模拟符号链接检查同时覆盖 .moonvcs 根目录；新增子案例稳定暴露了首版检查遗漏，已修复并保留失败记录。

没有恢复日志、自动恢复、GC 或真实掉电测试；不能将本轮同步/进程终止检查描述成完整持久事务。

## 回归与产物

本机最新完整 scripts/test.sh 退出 0：134 项独立测试
= 64 native + 26 Rust + 19 Wasm + 9 系统审计 + 6 验证脚本 + 4 暂存并发 + 6 恢复检查。
CLI 与双轮四场景 smoke 另列。阶段 7/8 历史报告、基准和旧交付包保持原快照。

- target/reports/roadmap-baseline.log：修改前完整回归，122 项独立测试。
- target/reports/roadmap-regression.log：本轮早先完整回归，133 项。
- target/reports/roadmap-regression-final.log：补齐恢复检查的 metadata-root 符号链接拒绝后的完整回归，133 项。
- target/reports/roadmap-regression-portable.log：补齐工具 PATH 解析回归后的最新完整回归，134 项，退出 0。
- target/reports/recovery-root-symlink-before.log：新增恢复检查曾遗漏顶层元数据符号链接，已先复现失败再修复。
- target/reports/roadmap-staging-before.json：旧二进制确定性丢失更新。
- target/roadmap-profile-01/：本轮剖析、冻结二进制与数据集，仅小型证据文件参与交付。
- target/roadmap-fresh-01/：通过的独立 rootfs 安装/验证报告及全部失败/成功日志；不打包镜像层、工具或依赖缓存。

现有 WIT、插件 pin、对象格式不变。没有新增真实网络接收端、Git 命令、认证、ACL、TLS、
OS 权限分离、总 Host/JIT RSS 限额或恶意插件通用脱敏机制。
