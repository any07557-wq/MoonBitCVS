# 最终安装脚本与本地归档的隔离验收

这是增加 diff 之前的源码/149 项测试快照。后续本机 diff 回归见
[DIFF_VALIDATION.md](DIFF_VALIDATION.md)；本报告不自动覆盖新功能的全新安装验收。

状态：fresh-03 全部通过，status=passed、installation_verified=true；fresh-02 失败报告原样保留。
fresh-02 第五层返回 HTTP 401，前四层摘要通过；prepare 退出 1、installation_verified=false，未执行测试或演示。
修复后的 fresh-03 在全新目录完成工具准备、完整 149 项回归和独立四场景，所有阶段退出 0。
没有以工具准备或旧报告代替项目验收，也没有将失败的 fresh-02 改成通过。

## 范围

本轮验证最终脚本的端到端安装，仅修复实际暴露的安装鉴权续期，并新增对应回归；
不修改 Core、Host、插件、WIT、对象格式或恢复协议。
新建独立 rootfs，不复用第一轮 rootfs、已安装工具或宿主 registry 缓存。
MoonBit compiler/core 是明确允许的本地原始归档输入，经长度/SHA-256 校验后重新解包安装，
不是挂载宿主 Moon 安装。Rust、GCC 和 Python 来自固定摘要的下载基础镜像。

共享宿主内核和网络，不是独立物理机器或 VM。镜像、Rust 组件和 registry 下载仍需网络，
本地 MoonBit 归档模式不等于完整离线安装。摘要绑定字节，不证明作者签名或永久上游保留。

## 实际命令与固定输入

~~~bash
python3 scripts/toolchain_archives.py verify --directory target/moonbit-archive-round2
python3 scripts/fresh-install.py prepare --workdir target/roadmap-fresh-03 \
  --archive-dir target/moonbit-archive-round2
python3 scripts/fresh-install.py verify --workdir target/roadmap-fresh-03
~~~

prepare 使用不存在的新目录。第一轮 target/roadmap-fresh-01 的 134 项报告与失败日志保留，
不能替代本轮结果。原 146 项加 3 项安装续期回归：宿主完整 scripts/test.sh 已退出 0，149 项及
另外的 CLI/演示 smoke 通过；新 rootfs 中同样实际完成了该完整入口和独立四场景，均退出 0。
宿主记录为 target/reports/fresh03-host-regression.log；隔离环境按下表单列，不将两者混用。

## 最终实际结果（2026-10-18）

| 阶段 | 退出码 | 阶段用时（秒） | 日志 |
|---|---:|---:|---|
| 工具准备，空初始 registry | 0 | 641.87 | toolchain-prepare-1.log |
| Mooncakes 索引初始化 | 0 | 16.14 | moon-registry-bootstrap-2.log |
| 干净源码构建、149 项完整回归及双轮 smoke | 0 | 362.98 | fresh-regression-3.log |
| 40 次真实提交准备与四个独立 Demo | 0 | 14.69 | fresh-four-demos-4.log |

这些是 report.json 的阶段计时，不包含外层基础镜像下载/解包，不能将相加值称为完整安装墙钟耗时。
Registry 续期实际发生 1 次；两份 moon_downloads 都为 operator-local-cas，host_toolchain_or_registry_mounted=false。
原生工具记录为 moon 0.1.20261012 / moonc 0.10.15+943464bfa、Rust/Cargo 1.99.1、
GCC 12.2.0、Python 3.11.2；wit-bindgen 0.63.0、wasm-tools 1.262.0 由本次安装编译。

149 = 70 native + 26 Rust + 19 Wasm + 9 系统审计 + 6 harness + 4 暂存 + 7 恢复 +
1 读取计数 + 7 归档/Registry。相对原 146 项，仅增加本轮安装实际问题对应的 3 项回归。
CLI/演示 smoke 与重复构建输出不重复计入测试数。

独立 Demo 实测远端 120 对象 / 12976 编码字节；clone 3 / 326，历史缓存 6 / 893，重复传输 0。
WIT 和五个组件均通过原 pin 检查；新环境中的 Scanner/License SHA 与已有结果一致。
GNU 12.2 仍报告第三方 async C 的 posix_spawn_*_np 声明警告，未修改依赖缓存或宣称 C 零警告。

实际被测试源码 192 个文件；清单 SHA-256：
286ca64727556dcea4b0ddcfe854206e6fe04e01aeffbd3ec5b0aec3c85d69c6。
验收后仅更新说明文档与证据打包清单；运行代码、安装脚本和测试保持该清单的字节。
编译器不同导致原生二进制可能不同，不把跨 GCC 的二进制摘要相同作为验收条件。

| 输入 | SHA-256 |
|---|---|
| scripts/fresh-install.py，失败的 fresh-02 | fef03fc8f11b91e2137da8fe272f43544ac89c5ab49bc7850aa2aa11bd45f9c2 |
| scripts/fresh-install.py，修复后的 fresh-03 | 1d77076e73248337663c47a4b480436c9abb510d1a806111ea26b15b3ee4fdde |
| tests/toolchain_archive_audit.py，7 项归档/续期测试 | 355e0239cd998fc675f9187de47d8d51b99e714c298bb1365aa6ed3c57f13967 |
| scripts/toolchain_archives.py | 7b939e27e6c5fdcb14b611f884f71ef8787d660b0c73ad9a19b8f5aadcc9dedd |
| scripts/moonbit-archives.lock.json | ab91e375e6e5f0adcffe5a5e9e0ae9886cc78b9e9d1c6844557b58ceee2f4023 |
| 第一轮 report.json，验收前 | 9ed0626b99d567e2b806a56f8aea837e6245a54466df149a20c4343009911113 |
| 失败的 fresh-02 report.json | ea73298e23642976e06edfe07e928ec56c1f85fde20907c5e34ddab87cd7c3e0 |

基础镜像：docker.io/library/rust@sha256:5f29c3b4cb8ad8c6f10df979595582dd67dd146ffebc70718e24ff2e5b4a194d。
两个归档的版本、长度与摘要由 scripts/moonbit-archives.lock.json 固定；
prepare 的 moon_downloads 应记录 operator-local-cas，缺失/损坏不得回退网络或 latest。

## 证据

- target/reports/fresh02-controller.json：外部命令、安装脚本/锁文件初始摘要和最终核对。
- target/reports/fresh03-controller.json：修复后脚本摘要、真实退出码、清单与报告最终核对。
- target/reports/fresh02-original/scripts/fresh-install.py：从上一轮不可变源码包提取的原安装脚本，SHA 与失败的 fresh-02 记录一致。
- target/reports/fresh02-archive-preflight.log：本地归档实际预检。
- target/roadmap-fresh-02/report.json：实际阶段命令、退出码、耗时及安装状态。
- target/roadmap-fresh-02/source-manifest.json：无构建产物源码副本的文件摘要。
- target/roadmap-fresh-03/*.log：实际工具准备、依赖、构建、完整回归与独立演示日志。

fresh-02 未进入工具阶段，因此没有这些阶段的日志。修复后的 fresh-03 各阶段将保存在
target/roadmap-fresh-03/，与失败目录分开，源码清单也只属于实际执行的该次副本。
最终 fresh-03 report.json SHA-256：78740ef7b898c48b8d26da078dd3dc903473ccdeaac57026bc6e734a1731254a。
第一轮与 fresh-02 报告在验收后重新核对，均与上表原始摘要相同。

## 本轮实际问题与修复

fresh-02 完成四层下载/校验后，第五层返回 401。诊断中新取匿名令牌的 expires_in=300 秒，
同一层用新令牌 HEAD 返回 200；旧脚本整个下载过程只取一次令牌且耗时超过该有效期。
这支持过期判断，但没有保存/解析原令牌或声称验证其签名。诊断不记录任何 Bearer 凭据。
[官方协议](https://docs.docker.com/reference/api/registry/auth/)描述了 401 后取令牌重试及令牌有效期字段。

修复仅对同一 Registry 请求的 401 重新取固定匿名 pull scope 的令牌，并重试一次；
再次 401、403 或取令牌失败仍返回错误。不会改镜像/层摘要，不跟随 challenge 请求未知授权服务器，
也不绕过原始 SHA-256 校验。新增三个无网络回归检查成功续期、第二次 401 失败和 403 不重试。
这不是给 MoonVCS receive 实现身份认证，也不代表解决了用户远端的认证/ACL/TLS。

工具准备通过并不等于产品通过；任何中间失败均保留，不改写为成功。
本轮不重新测量宽 Tree 性能，也不据安装验收扩大安全、持久性或功能声明。
