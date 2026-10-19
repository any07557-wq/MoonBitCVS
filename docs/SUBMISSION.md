# 本地交付与当前版本解包复现

branch/switch 已通过 **本机原型验收**：2026-10-18 的 225 项完整回归、摘要核对和人工恢复演练，
见 [独立记录](BRANCH_SWITCH_ACCEPTANCE.md)。这不是生产远端或新版本冷安装放行。

2026-10-19 的交付工作增加 6 项归档/复现输入防护并接入统一入口，当时完整入口共 231 项。
后续 CI 轮又增加 6 项，当前为 237 项，并将 .github 纳入所有源码复制白名单；
旧 231 项归档不改写，CI 本地验证与远端状态另见 [CI.md](CI.md)。
每次包都是不可变快照；**打包本身不代表测试通过**。具体源码包是否完成另一目录重建，
以包旁 `REPRODUCTION.json` 的 status、stages、源码包摘要及 `REPRODUCTION.md` 为准。
报告缺失、failed 或没有完整 regression 退出 0，均不能称为通过。

## 生成与边界

从保留了既有验收产物的维护者工作区执行：

~~~bash
./scripts/package-submission.sh
~~~

每次创建新 `target/releases/submission.*`，不覆盖旧包，不上传或创建远端发布。
打包脚本需要显式历史证据，不能在仅有源码的新目录直接运行它来伪造旧验收。

| 文件 | 内容 |
|---|---|
| MoonVCS-source.tar.gz | 白名单文档、MoonBit/Wasm/Host 源码、WIT、锁文件、脚本、测试、示例 |
| MoonVCS-evidence.tar.gz | 历史阶段与安装/性能记录、diff/branch/switch 的失败及通过日志、225 项收尾清单和恢复演练摘要 |
| SHA256SUMS | 上述两个不可变归档的实际 SHA-256，用于传输核对，不是身份签名 |

证据中的 225 项及更早的报告各自只覆盖原版本，不能按文件名直接与新源码认同。
旧 delivered-source/tested-source 摘要中的脚本/文档可能与后续版本不同；保留原清单，不为新包回写旧摘要。
当前包的新证据必须通过其实际源码归档重新获得，并绑定归档摘要。

源码包不带 `.toolchains`、`target`、`_build`、`.mooncakes`、`__pycache__`、`.moonvcs`、`.git`
或本机二进制。证据只枚举选择的报告；恢复演练只包含 commands/result/manifest/check 报告，
**不包含** interrupted/evidence/inspection/transaction/用户版本等恢复 fixture 仓库。
同样不打包 rootfs、下载镜像层、工具归档、registry 缓存或用户 HOME/配置附件。
报告仍有本机路径、时间、对象 ID 和无害模拟元数据；发布前应审阅，不直接归档整个工作区。

## 在另一目录重建完整入口

要求已按 [INSTALL.md](../INSTALL.md) 准备固定 MoonBit/Rust/wasm-tools/wit-bindgen、rustfmt、C 编译器、
Python 及可用的全局依赖缓存。先核对包的 `SHA256SUMS`，再使用复现入口：

~~~bash
python3 scripts/reproduce-submission.py \
  --package-dir /absolute/path/to/submission.XXXXXX \
  --workdir /absolute/path/to/new-reproduction \
  --toolchain-dir /absolute/path/to/installed/.toolchains \
  --moon /absolute/path/to/moon
~~~

workdir 必须不存在，父目录须存在；失败也保留，重试使用新目录。建议放在有足够空间的磁盘，
不要默认使用小容量 tmpfs 的 /tmp；Rust 新构建目录可达数 GiB。脚本不自动删除或恢复目录。

复现入口会：

1. 仅接受固定两份归档的唯一 SHA256SUMS 条目，核对实际哈希；摘要不是作者身份认证。
2. 完整检查归档路径/类型/重复项/预算，拒绝越界、链接、特殊文件及源码中的构建/仓库状态；
   仅在新的私有 source 与 evidence 目录解包，不把旧报告或运行产物放回源码构建目录。
3. 记录所有源文件摘要和权限；确认没有项目输出及依赖目录后，运行环境记录与完整 `scripts/test.sh`。
4. 工具从显式安装目录取得；复用全局 Moon/Cargo registry 缓存，Cargo 使用 offline；
   `CARGO_TARGET_DIR` 固定到新 source/host/target，TMPDIR 也放在新工作目录，不共享旧项目编译输出。
5. 构建后复核源码和输入归档未变，记录新的 CLI/Host/配置摘要与每阶段命令、退出码、日志。

解包后的代码会被执行：只对操作者信任并明确选择的本地源码包使用此命令，不将输入防护描述为沙箱。
继承当前 OS/环境、已安装工具与全局缓存；不是新 rootfs、空 registry、全离线 bootstrap、
跨平台测试、依赖签名或 CVE 审计。Moon 的潜在联网没有被此脚本完全禁用，不能把 Cargo offline 扩大为整体断网保证。

输出保留为 `report.json`、source-manifest.json、environment.json、environment.log、regression.log、
独立 source/evidence/tmp 目录。只有实际 status=passed 且完整阶段退出 0 才算该归档的本机解包复现通过。
维护者可将报告和日志复制/选择性打包到同一 submission.* 目录，另写 REPRODUCTION.sha256，
不改原源码或历史证据归档；新增报告应绑定原 `MoonVCS-source.tar.gz` 摘要，避免结论循环。

## 保留的限制

历史 149 项 fresh-03 rootfs 安装属于增加 diff 前的源码，不覆盖 225/231 项版本。
如需宣称当前版本冷安装通过，必须另跑新 rootfs 并保留当前源码清单和实际结果。
旧 submission.* 不追溯更新；包旁报告也不能证明已发布安装包、托管镜像、外部长期归档或作者身份。

人工恢复得到的 Partial Clone 仍可能依赖 `inspection/`；交付打包不移动、删除或备份该来源，
不能据此进行清理。成功 switch 的保留备份、GC/自动恢复、Host/JIT 总内存、真实远端认证/ACL/TLS/OS
权限分离及缺失 VCS 能力仍按 [已知限制](KNOWN_LIMITATIONS.md) 和 [路线图](../ROADMAP.md) 保留。
