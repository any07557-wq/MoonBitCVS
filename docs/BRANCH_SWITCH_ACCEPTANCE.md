# Branch / Switch 收尾独立验收

日期：2026-10-18，Asia/Shanghai。Linux x86_64 / WSL2，本机已安装工具链及依赖缓存。
本轮完成完整回归、独立源码/CLI 绑定和人工恢复流程演练；不是新冷安装或最终参赛包验收。

## 实际结论

最终统一入口 **退出 0，225 项独立测试通过**，另有既有 CLI smoke 与双轮四场景演示通过。
225 = 86 native + 26 Rust + 19 Wasm + 9 系统审计 + 6 验证脚本 + 4 暂存并发 +
7 恢复检查 + 1 Lazy 逻辑 IO + 7 工具归档/Registry + 20 diff CLI + 40 branch/switch CLI。
相对前一轮 223，只增加帮助提示和人工恢复演练 2 项；独立重跑、子检查、重复构建和演示不重复计数。

统一入口覆盖现有 commit、receive/CAS/Quarantine、Lazy、diff，以及共用锁和 pending 的 Core/CLI 门禁。
本轮未改变共用锁、WIT v1、对象格式或策略权限实现；CLI 增加成功备份成本提示。
在已测试场景中未发现旧路径回归，不将通过结果扩大为全生命周期并发/持久性证明。

## 最终源码与运行产物绑定

所有当次原始文件位于 `target/reports/branch-switch-closeout.VpnM81/`，不覆盖前轮 closure、diff 或冷安装日志。

| 绑定对象 | SHA-256 / 清单 |
|---|---|
| 回归前冻结的 162 项源码/配置/脚本/测试/示例/WIT 与恢复契约清单 | `tested-source-final.sha256`；清单本身摘要 `dffc70594e8132016581ce1ad8bb0bf88719bebd0cd0d06535e2f0c1868d8676` |
| CLI `target/bin/moonvcs` | `2bbc704aea8b18f25ea5597d7f80cb9a7c03eda1a0b3dda86b287994445c1d72` |
| 12 项 CLI/Host/策略配置/Component 运行产物清单 | `tested-runtime.sha256`；清单本身摘要 `d04ab5932c239cf8a14550d20001dfd8b8777262e87d3e7875080418547b3724` |
| 最终完整原始日志 | `regression-final.log`；摘要 `7394352eb70a5a7b43086111948fcb29811fd852c62fce926dba9ebf2f8f4fe5` |
| 成功独立恢复演练结果 | `manual-recovery-02/result.json`；摘要 `8ecfc007afad3abe366c728c8dcfaa093359120d6d25474b83243130309c0701` |

冻结清单包含 vcs/host/plugins/scripts/tests/wit/examples 的项目文件，以及 BRANCH_SWITCH.md、
docs/RECOVERY.md、docs/SWITCH_MANUAL_RECOVERY.md、.gitignore、LICENSE；
排除 target/_build/.mooncakes/__pycache__/.git。回归后逐文件核对，162 项及 12 项运行产物全部 OK，
见 `source-check.log`、`runtime-check.log`。成功独立演练 result 中的 CLI 摘要亦与最终 CLI 相同。

运行结束后只更新结果说明文档；完整交付源文件（含本记录、README、其他文档）的清单另存
`delivered-source.sha256`。它与最终日志/结果/摘要清单一起由 `evidence.sha256` 索引，
不把事后文档编辑描述为重新运行了整套测试。这些是本机内容绑定，不是作者签名、发布来源认证或发行包。

## 命令、顺序与退出码

工作目录为项目根 `/home/user/MoonBit_Program`。最终完整执行的 UTC 起止为
`2026-10-18T13:54:50Z` → `2026-10-18T13:56:44Z`，114 秒，退出 0；
本机耗时不是新性能基准。实际命令、时间和退出码见 `regression-run.txt`。

| 步骤 | 实际结果 | 原始记录 |
|---|---|---|
| `MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/build-vcs.sh` | 退出 0；fmt/check/native 86 项/release build | `../branch-switch-closeout-build-y3yW22V4.log` |
| `MOONVCS_MOON=/home/user/.moon/bin/moon python3 scripts/environment.py --output target/reports/branch-switch-closeout.VpnM81/environment.json` | 退出 0；各工具版本查询成功 | `environment.json`、`environment.log` |
| 独立恢复演练 01 | **退出 1**，在 `status --offline` 处被 CLI 拒绝；此前复制、重建、版本保留已执行，不将其当作通过 | `manual-recovery-01.log`、`manual-recovery-01/commands.jsonl` |
| 首次新增两项回归 | **退出 1**，帮助提示通过，恢复演练因上述参数错误报错 | `new-regressions.log` |
| 修正指引后的全新独立恢复演练 02 | 退出 0，20 项子检查；结果/现场完整保留，不另加为 20 项测试 | `manual-recovery-02.log`、`manual-recovery-02/result.json`、`manual-recovery-02/commands.jsonl` |
| 新增两项回归重跑 | 退出 0，2 项通过 | `new-regressions-final.log` |
| `MOONVCS_MOON=/home/user/.moon/bin/moon CARGO_BUILD_JOBS=2 ./scripts/test.sh` | **退出 0，225 项及全部既有演示通过** | `regression-final.log`、`regression-run.txt` |
| 最终源码/运行产物摘要核对 | 退出 0，全部 OK | `source-check.log`、`runtime-check.log` |

实际完整测试本轮只运行上述一次，发生在恢复指引修正与源码冻结之后。
首次演练使用错误的尾部参数；修正为 `moonvcs --offline status`，不扩展 CLI 的参数接受范围。
docs/RECOVERY.md 的既有错误也一并修正，演练回归实际执行正确命令。旧错误快照清单
`tested-source.sha256` 保留，仅用于首轮失败归因，不能替代最终 `tested-source-final.sha256`。

## 人工恢复演练核验

规则与逐项重现方式见 [SWITCH_MANUAL_RECOVERY.md](SWITCH_MANUAL_RECOVERY.md)。独立实际命令：

~~~bash
python3 tests/switch_recovery_drill.py --output-dir target/reports/branch-switch-closeout.VpnM81/manual-recovery-02
~~~

该命令仅能新建无害 fixture，输出目录必须不存在；重跑必须选择新目录，不能覆盖保留现场。
它按操作员决策路径执行文件保留与现有 CLI，不是产品自动恢复接口，也不接受真实待恢复仓库。

- 从首次 backup 后 SIGKILL 的混合状态开始，模拟旧 fd 的迟到用户写入及原路径用户新文件。
- `recover --check` 确认需处理，`add` 返回 18；完整原库独立复制并逐路径核对字节/类型/权限。
- 原活动库与唯一 evidence 副本保持不动，仅在 inspection 副本把精确事务目录保留移出；不删除或移动原稳定 advisory inode。
- 核对保存的 HEAD/index 与完整 Commit ID，明确选择最后已发布 main；用现有 clone 在新目录重新验证并重建快照。
- 新工作区/index/HEAD 先验证一致，再由操作员选择原路径用户文件合回；旧 inode 修改、发布前内容、未安装目标另存，未跟踪 Unicode 二进制内容也核对保留。
- 最终新库无 pending，用户修改仍未暂存，未自动 add/commit；原库 pending 和全部证据继续保留。

新库是 Partial Clone，后续祖先读取可能依赖保留的 inspection 来源，不能据此删除旧目录。
这覆盖一个已知 backup 中断点与拥有者选择，不证明掉电、跨设备、全部退出 16、证据缺失或未知事务都能恢复。

## 使用成本与旧结果边界

`moonvcs --help` 现明确提示 `.moonvcs/switch-history/<transaction-id>/before/`，
成功切换仍保留备份，磁盘占用增长且 **No automatic cleanup**；帮助本身不写库，有实际回归。
没有新增 GC、清理命令、force、自动 continue/abort、自动回滚或安全删除证明。

历史 177 项本机结果属于 diff 版本；149 项冷安装属于增加 diff 之前的源码。
此前 223 项与 38 项专项仍属于此前版本，均不改写为本轮 225 项，也不替代本轮完整运行。
本轮**没有**新 rootfs 安装、另一目录源码解包重建、参赛包生成、外部工具归档备份或性能基准重跑。
认证/ACL/TLS/服务端 OS 权限分离、Host/JIT 总内存、通用恶意诊断脱敏及缺失 VCS 能力仍未解决。

## 本机证据核对

在保留本轮 target 产物的项目根执行：

~~~bash
sha256sum -c target/reports/branch-switch-closeout.VpnM81/tested-source-final.sha256
sha256sum -c target/reports/branch-switch-closeout.VpnM81/tested-runtime.sha256
sha256sum -c target/reports/branch-switch-closeout.VpnM81/delivered-source.sha256
sha256sum -c target/reports/branch-switch-closeout.VpnM81/evidence.sha256
~~~

target 是本机产物，不保证随源码存在；旧 release/evidence 包未自动更新，不能假设这些日志已被打包或长期备份。
恢复现场即使为无害 fixture 也不应作为真实仓库的自动处置模板；发布证据前只选择已审阅的日志/摘要，不打包整个工作区。
