# 最小 Branch / 安全 Switch 验证

本页保留实现轮 223 项结果及此前真实失败；后续帮助/人工恢复收尾与 225 项完整回归另见
[BRANCH_SWITCH_ACCEPTANCE.md](BRANCH_SWITCH_ACCEPTANCE.md)，不回写本页历史计数。

日期：2026-10-18，Asia/Shanghai；Linux 原生环境，复用已安装工具与依赖缓存。

## 按用户顺序交付

1. 先写根目录 [BRANCH_SWITCH.md](../BRANCH_SWITCH.md)，随后按实现细化持久证据预算与恢复观察字段。
2. MoonBit [checkout.mbt](../vcs/checkout.mbt)：branch 列出、从当前 HEAD 创建；有界名称子集、无覆盖 Ref。
3. 完整只读计划：当前 HEAD/index/工作文件、目标 Commit/Tree/Blob、哈希/类型/路径、碰撞与预算均验证后才执行。
4. switch：共享 staging 事务锁、再次复核、私有 intent/phase/文件准备、旧 inode 无覆盖备份、无覆盖安装，最后 index → HEAD，成功后保留整个事务到 history。
5. [8 项 native 回归](../vcs/checkout_wbtest.mbt)、[38 项真实 CLI/故障回归](../tests/branch_switch_audit.py)与测试专用 [fsync 夹具](../tests/fixtures/switch-gate.c)。

add/commit/branch/switch 与 receive 最终发布使用同一稳定 advisory inode，receive-publish → staging → fetch/Ref。
pending 状态在 Core 写入接口和普通 CLI 均默认拒绝，不能只跳过 CLI 检查绕过；包括内部 Ref 更新和 receive。
recover --check 只读报告事务身份、phase、起点/目标以及按保存摘要观察的 HEAD/index 状态；不自动恢复。

没有修改 WIT v1、规范对象格式或插件 pin；Rust Host 未增加 VCS 操作。核心逻辑与检查仍由 MoonBit 实现。
CLI 场景通过真实默认 Wasm 门禁构造快照；native 单元沿用可信空策略 fixture，不把它当作最终策略演示。

## 实际运行记录

| 步骤 | 实际结果 | 原始记录 |
|---|---|---|
| 修改前完整 scripts/test.sh | 退出 0，177 项基线及演示通过 | target/reports/branch-switch-baseline.log |
| 新实现 native 测试与构建 | native 86 项通过，build-vcs.sh 退出 0 | target/reports/branch-switch-native.log、branch-switch-build.log |
| 首版 CLI 保护/故障测试 | 36 项通过，退出 0 | target/reports/branch-switch-cli-initial.log |
| diff 兼容回归 | 20 项通过，退出 0 | target/reports/branch-switch-diff-compat.log |
| 首次完整扩展回归 | **退出 1，37 项 branch/switch 中 2 项失败**，未运行随后最终演示 smoke | target/reports/branch-switch-regression.log |
| 观察字段修复后的冻结回归 | 退出 0，222 项及全部 smoke 通过；不是随后空 Tree 修复的验收 | target/reports/branch-switch-regression-final.log |
| 非根空 Tree 修复前单项回归 | **退出 1，实际 switch 错误返回 0**，将目标目录扁平化为文件删除；旧文件仍在备份，未发生字节遗失 | target/reports/branch-switch-empty-tree-before.log |
| 空 Tree 修复后最终冻结完整回归 | **退出 0，223 项通过**；native 86、branch/switch CLI 38 及所有既有 smoke/双轮四场景通过 | target/reports/branch-switch-closure-regression.log |

223 = 上轮 177 + 新增 8 native + 38 CLI。重复构建、失败重跑、子案例与演示不重复计数。

该次失败不是最终源码验收：构建进行中追加了 HEAD/index 观察字段和断言，测试已读新断言，
已构建 CLI 仍返回旧格式 summary，因此 HEAD=old/target 断言失败。原日志和失败退出码保留，
不把最初 36 项通过当作最终 37 项结果。随后冻结全部实现/测试，重新构建并跑完整入口，
该轮记录单列 target/reports/branch-switch-regression-final.log。

随后审查用真实 hash-valid 空子 Tree 重现计划遗漏目录语义，补了预检拒绝及“根空快照仍支持”的独立测试。
当前和目标的非根空 Tree 均拒绝；不改变 diff 默认忽略空目录的显示语义。再冻结源码后的最后完整记录为
target/reports/branch-switch-closure-regression.log，不能用此前 222 项替代它。

测试 C 夹具的 snprintf 固定数组长度警告亦已修正，单独以 `-Wall -Wextra -Werror` 编译通过；
不因此宣称第三方 C 代码或全部冷构建零警告。

空 Tree 修复前的摘要保存在 target/reports/branch-switch-source-sha256.txt；
最后冻结的关键实现/测试/脚本/WIT 摘要为 target/reports/branch-switch-closure-source-sha256.txt。
它不是整份源码或发行包的签名清单，不包含长期工具归档备份证明。

## 直接证据与边界

- 分支：unborn、当前 HEAD 创建、不改 index/工作文件、合法名称/前缀冲突/悬空链接、两个创建者无覆盖。
- 计划：精确新增/替换/删除，仓库 inventory 不变；缺失/损坏/错误类型对象和危险 Tree 拒绝，无隐式 Fetch。
- 保护：脏暂存、无关但脏的跟踪文件、删除、同内容未跟踪文件、空目录、链接/FIFO、文件目录互换拒绝。
- 空 Tree：非根空目录结构不静默扁平化；根空快照可以切换，且保留无关未跟踪文件。
- 应用：新增/替换/删除、空/二进制/Unicode 路径往返；无关未跟踪内容、未改文件 inode/权限与外部模拟硬链接保留。
- 资源：8 MiB 工作文件拒绝，深路径宽 Tree 生成的过大目标 index 在准备事务之前拒绝；manifest 的 4 MiB 边界有明确 synthetic native vector，不伪称真实合法长路径。
- 故障：prepared、首次 backup、index 发布后、HEAD 发布后 SIGKILL；prepared 写失败、HEAD 和 archive 目录同步 EIO；不称为掉电测试。
- 竞争：备份后新出现的同名文件不被覆盖；旧 fd 的迟到写入保留在 before/，不自动清理；预检后编辑/Ref 变化拒绝。
- 协调：真实 add 读屏障使 switch 等待，随后拒绝新的 staged 状态；pending 不仅阻止 CLI，也阻止 Core 的 add/commit/branch/Ref/receive。
- 退出 16：HEAD 可能已经目标，甚至 pending 已成功移入 history；只读报告与保留数据支持人工判定，不盲重试。

## 未交付或未验证

没有分支删除/重命名、force、任意版本/通用 checkout、文件目录互换、自动 continue/abort、自动回滚、
备份 GC、通用恢复日志重放或全生命周期掉电事务。成功备份仍保留，磁盘占用增长；
大量历史 manifest 检查没有单独全局 byte/time 配额，成本随保留历史增加。
新/替换文件 0600、新目录 0700；没有模式/可执行位跟踪。权限/磁盘/跨挂载等 IO 仍可导致 partial failure。

所有写入者须使用当前协作协议。编辑器、旧二进制、敌对同账户路径竞态不被完整串行化/隔离；
只读查询不是全局多文件原子快照。恢复状态字段仅观察 metadata，不证明完整工作区一致。
没有验证实际 SIGTERM/任务取消的每个阶段、真实掉电、其他平台、满盘/跨设备的完整组合或长期压力。

本轮没有重跑新源码冷安装、另一目录源码解包重建、最终参赛打包或宽 Tree 性能基准。
历史 149 项 rootfs 与 177 项 diff 报告保持原范围，不自动覆盖新代码。
认证、ACL、TLS、服务端 OS 权限分离、Host/JIT 总内存与外部工具归档保留也没有因此解决。

## 复现命令

~~~bash
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/build-vcs.sh
python3 tests/branch_switch_audit.py
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/test.sh
sha256sum -c target/reports/branch-switch-closure-source-sha256.txt
~~~

target 日志/摘要是本机产物，不随源码自动存在；重跑应保存新日志，不覆盖既有失败和历史安装报告。
