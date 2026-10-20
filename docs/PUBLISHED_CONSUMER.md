# 已发布 Mooncakes 0.1.0：独立消费验收

## 验证什么

这项检查只验证公开 registry 中的 **`any07557-wq/moonvcs@0.1.0` native 核心库**。
不是当前源码完整回归，不含 Rust Host、Wasm 插件、安全提交端到端或预编译 CLI 的验收。
不登录、不发布、不使用本地 `vcs/`、历史 ZIP 或本地 module override 替代下载。

固定公开包 SHA-256：
`5006035f75de4f963213a92257bafa3a5d2f751bb117c803c49d9c09f21867d3`。
与原发布档案一致；不提供版本/摘要覆盖选项，下载内容漂移时直接失败。
这是维护者记录的内容完整性绑定，不是作者签名或 registry 身份认证。

## 本地运行

先准备 [固定工具链](../INSTALL.md)、native core bundles、系统 C 编译器及 Python 3.12+。
使用 Linux 环境，指定安装好的 `bin/moon`；不需要 Rust/Wasmtime 或 Mooncakes 登录。

```bash
# 首次工具安装后，在工具的 core 目录生成 native bundles：
/actual/toolchain/bin/moon -C /actual/toolchain/lib/core bundle --warn-list -a --target native --quiet

# 父目录须已存在，最终目录须不存在，并位于本源码仓库/其他 MoonBit workspace 外。
python3 scripts/verify-published-consumer.py --moon /actual/toolchain/bin/moon \
  --workdir /tmp/moonvcs-public-consumer-unique
```

脚本创建全新 `moon-home/`，初始没有 registry/index/cache 或凭据；仅链接已安装的
`bin/` 和标准库 `lib/core/`。不读取原 Moon home 的 registry/登录状态，不继承 MOON 配置变量。
复用编译器/标准库不是全新 OS 安装，也不清除系统网络、DNS 或 OS 页缓存。
子进程采用最小环境，不转发代理/自定义 CA 环境变量；受限网络下可能直接连接失败。
普通 curl 的成功不能代替脚本网络路径的真实下载结果，不把下载失败改写为成功。

脚本仅复制五个明确的 [consumer 文件](../examples/released-consumer/)，并严格检查模块声明。
依次保留版本、C 编译器、匿名状态、`moon update`、native check、依赖树、native test 和 README run 的
真实 argv/cwd/退出码、独立 stdout/stderr。下载所得 ZIP 必须匹配固定摘要；安装目录的所有文件
必须与 ZIP 成员逐字节相同，不能是本地源码链接。测试后再次复核包和 consumer 源文件。
两项测试必须恰好 `2 passed / 0 failed`；README 输出必须是已知空 Blob 哈希。

任何命令、下载、摘要、安装内容、测试计数或示例结果异常均非零退出。
每命令默认 300 秒，超时终止该进程组并失败；无自动重试、跳过或缓存回退。
失败目录与 `report.json`、原始日志全部保留。不要覆盖/复用它；修复后选择新目录，重新从空缓存下载。
目录创建前的参数/祖先 workspace/已有目录错误仅报 stderr，不覆写现有目录以补造报告。

## 独立手动 CI

配置：[published-consumer.yml](../.github/workflows/published-consumer.yml)。
名称 **Published Mooncakes consumer (0.1.0)**，只允许 `workflow_dispatch`，
不在 push/PR 时绑定公开 registry 可用性，也不替换原 `MoonVCS CI` 的源码回归。
工具安装复用已有 SHA 固定安装器；不使用 Actions registry 缓存，消费目录在 runner 临时目录中。

同步配置后在 GitHub Actions 选该工作流 → Run workflow。需要默认分支上存在工作流；参见
[GitHub 手动运行文档](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。
不需要仓库 secrets。checkout/upload-artifact 均固定完整 SHA，contents 权限只读。
成功/失败都上传选定的 JSON/log，保留 14 天；不上传 registry、凭据、全部工作区或工具。
请及时独立检查并归档附件；配置/本机通过不代表该 workflow 在 GitHub 已通过。
接入后的真实手动运行现已成功，见下节；本机验收记录与实际远端结果不混用。

## 实际远端消费验收与持久归档

[运行 39419237867](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39419237867)
由维护者手动触发，在 `597e260` 上 completed / success。
空 registry、匿名下载固定 0.1.0，八条命令全部退出 0，2 项测试与 README 通过；
原 ZIP 为 9,416 字节，SHA-256 为
`36d7d4404328f91d596b11ad1deea4c7edeb2321777b84d6deec76497f3043f6`，匹配 GitHub 官方页面。
21 份报告及元数据/核验/隐私检查已存入
[evidence/ci/39419237867-attempt-1/](../evidence/ci/39419237867-attempt-1/)，
不依赖 target/reports 或 GitHub 14 天附件保留期；获取路径与限制见 [CI 验证记录](CI_VALIDATION.md)。
这是已发布 native 核心库消费证明；完整源码的 264 项由 CI #4 另行报告。

## 无网络脚本回归与真实公开包结果分开

`python3 tests/published_consumer_audit.py` 的 14 项使用显式标记 FAKE 的自建子进程/小 ZIP，
覆盖空缓存编排、命令失败、CLI 非零、摘要/安装差异、错误计数/输出、超时、目录保护、匿名要求、
模块声明防漂移与手动 CI 边界。它们接入 `scripts/test.sh`，但不证明公开 registry 可访问或真实库可编译。

## 历史：2026-10-20 恢复后的本机验收

WSL 磁盘空间故障恢复后，先核对 HEAD 仍为 `4527af5`、9 次提交，未提交代码及原冻结包保持不变。
中断前完整回归只有 `running` 报告与截断日志，不能算通过；当时 consumer 的成功终端记录仍在，
但 `/tmp` 中详细报告已消失，因此不沿用它作为本轮证据。没有隐藏此前的依赖布局错误或下载连接重置，
这些中断前命令的外层日志仍在 `target/reports/published-consumer.9L7qNw/`。

恢复后执行（父目录由 `mktemp -d` 新建，acceptance 开始时不存在）：

```bash
python3 scripts/verify-published-consumer.py --moon /home/user/.moon/bin/moon \
  --workdir /tmp/moonvcs-consumer-resumed.MVGiTA/acceptance
```

实际 **11:11:49–11:12:03 UTC（北京时间 19:11:49–19:12:03）**，CLI 退出 0。
8 个命令均退出 0；初始 registry 不存在，匿名状态为 `Not logged in`，
**2 项消费测试和 README 示例通过**。实际下载 75,212 字节，固定 ZIP 摘要匹配，33 个安装文件逐字节相同；
依赖树为 0.1.0 / sha256 0.18.0 / base64 0.16.13 / async 0.20.2。

完整新报告、真实 argv/版本和 stdout/stderr 已立即从临时目录复制到持久工作区，随后做了选定日志的
隐私规则检查、常规内容复核与校验归档：
[report.json](../evidence/mooncakes/0.1.0/consumer-automation-20261020/report.json)、
[原始命令](../evidence/mooncakes/0.1.0/consumer-automation-20261020/invocation.json)、
[SHA256SUMS](../evidence/mooncakes/0.1.0/consumer-automation-20261020/SHA256SUMS)。
只保存 19 份明确报告/日志、隐私检查和校验清单，不复制 registry、凭据、依赖源码或构建缓存；
Linux 自有工具/临时目录路径保留，规则检查不等于完整 DLP。
原始 `cc --version` stdout 末尾自带空行，按原字节保留；源码仍做严格 whitespace 检查，
仅审查这批原始报告时忽略 Git 的 `blank-at-eof` 提示，不格式化或改写证据。

14 项无网络脚本回归及两个 workflow 的本地 actionlint 复核也已通过。
当前源码完整回归另见 [PUBLISHED_CONSUMER_VALIDATION.json](PUBLISHED_CONSUMER_VALIDATION.json)，
不把上述 2 项消费测试算进源码总数。历史发布时结果仍见
[MOONCAKES_RELEASE.md](MOONCAKES_RELEASE.md)，不回写成新的发布或 GitHub CI。

## 恢复后的完整源码回归

继续使用中断前保留的 `reproduction/source/`，未创建新的源码副本，复用安装好的工具、
全局依赖及该目录的项目编译缓存；Cargo offline、单构建任务。不是新 rootfs 或完全冷构建。
执行前核对 236 个源码快照文件，执行后快照不变；其中 173 个执行源码/配置文件与当前工作区一致。
报告文档在结果确定后补写，不把中断前验证包重命名成新的最终交付包。

恢复后首次、第二次重跑均真实失败：链接器依次识别 Wasmtime、Cranelift 的截断 `.rlib`。
保留两次完整失败日志，仅用 `cargo clean -p wasmtime` 和 `cargo clean -p cranelift-codegen`
清理该验收目录内约 101.0 / 161.6 MiB 的可重建缓存；没有删除源码、原报告或交付包。
只读归档成员边界检查定位了后者的成员末尾超出文件长度；它不是完整对象码校验。

最终完整入口实际 **11:14:45–11:20:16 UTC（北京时间 19:14:45–19:20:16）**，
environment/regression 均退出 0：**264 项通过 = native 86 + Rust 26 + Wasm 19 + Python 133**。
11 个 Python suite 为 `9,6,4,7,1,7,20,40,19,6,14`；CLI 与双轮四场景演示通过。
完整新日志及失败现场保留在 `target/reports/published-consumer.9L7qNw/resume.aFNEb0/`，
通过轮为 `attempt-03/`，与原中断的 `reproduction/report.json: running` 分开，不覆盖旧结论。

物理 E 盘空间在每阶段前检查、执行中定期监测：启动阶段至少 6 GiB，低于 4 GiB 则中止本轮进程组。
本轮实测最低 **14,848,331,776 字节（约 13.83 GiB）**，未触发停止；不能用 WSL 虚拟盘显示的
数百 GiB 空闲代替 Windows 宿主盘剩余空间。旧最终交付外层包及内部清单再次核对通过。

上述本机验收当时未推送或远程触发；后续同步及手动工作流结果由前节独立记录，没有重新发布 0.1.0。
旧 `ec287d1` 包保留不变。新版统一冻结按 [契约](FINAL_DELIVERY.md) 执行，
真实通过与否以新包旁报告为准，不能把中断前验证包称为新的最终参赛包。
