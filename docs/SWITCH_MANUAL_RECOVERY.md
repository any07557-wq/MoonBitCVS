# Switch 中断后的人工恢复演练

本页将 [BRANCH_SWITCH.md](../BRANCH_SWITCH.md) 的“不一致状态保留后在新目录重建”规则落实为
可重复的操作员演练。不是自动恢复命令，不接受真实待恢复仓库，不包含掉电验证。
执行结果与最终源码/CLI 的绑定另见独立验收记录；仅有本页不能当作测试通过证明。

## 重现入口与安全范围

先构建 CLI，然后选择一个**尚不存在**的输出目录（父目录须存在）：

~~~bash
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/build-vcs.sh
python3 tests/switch_recovery_drill.py --output-dir target/recovery-exercise-01
~~~

该脚本只新建无害测试仓库、编译测试专用 fsync gate、终止自己启动的 switch 子进程。
输出目录权限 0700，默认完整保留，不自动清理；已有目录一律拒绝，不操作用户仓库。
真实恢复前必须另行协调所有写入者、排除 IO 故障并由仓库所有者选择保留版本。

## 演练状态及人工决策

1. 构造 `old`、`main` 两个已通过真实 Wasm 提交门禁的快照，并放置无关的未跟踪 Unicode 二进制笔记。
   从 `main` 切到 `old`，在第一个旧文件移入 `before/` 后暂停；通过旧 fd 写入模拟用户修改，
   随后 SIGKILL 并等待子进程退出、关闭编辑器 fd。模拟用户在原路径另建一个不同内容的文件。
   从此停止所有演练写入者，原库只做只读诊断与备份。
2. 运行 `recover --check`，保留 JSON；确认 pending 门禁拒绝 `add`。
   phase 可能滞后，不能仅凭 `applying` 决定恢复；旧 fd 的修改已不等于原 Blob，必须额外保留。
3. 将**整个** `interrupted/` 独立复制为 `evidence/`，包括工作区、`.moonvcs`、锁、对象与事务。
   逐路径核对内容摘要、类型和权限；复制不是硬链接。将清单保存为 `evidence-manifest.json`。
   `interrupted/` 的原始 inode/mtime/ctime/内容清单在后续步骤仍须不变；不删除/移动稳定 advisory lock。
4. 从 `evidence/` 再建 `inspection/`。**仅在此检查副本**，把精确的
   `inspection/.moonvcs/switch-transaction/` 保留移动为同文件系统的
   `inspection-transaction-preserved/`；原库与证据库的 pending 均保留不动。
   在检查副本运行 `show HEAD --offline`，核对完整 Commit ID 及保存的 old HEAD/index。
   普通查询可能修改本地元数据，故不能在原库或唯一证据副本执行这些语义检查。
5. 操作员明确选择**最后已发布的 main 快照**，不是未完成的 old 目标。
   用既有 `clone inspection rebuilt` 在不存在的新目录重建；clone 读取已保存 Ref、校验 Commit/Tree/Blob，
   不依赖混合工作区内容，也不导入远端可执行策略配置。
   这是操作员在拥有并核对的本地副本上使用既有 clone，不是从 Quarantine 人工发布对象。
6. 在 `rebuilt/` 核对完整 HEAD ID、预期文件字节，确认 `diff` 与 `diff --staged` 都为空：
   此时工作区、index、HEAD 对应所选快照。克隆可以是 Partial Clone，未来祖先读取仍依赖
   `inspection/`，因此保留该来源，不宣称所有历史已转移或可删除旧目录。
7. 操作员将原路径的用户新文件合回新工作区，恢复未跟踪笔记；将旧 inode 的迟到修改、
   原已发布内容和未安装目标内容分别保留到私有的 `user-versions/`，不猜测哪个版本应被丢弃。
   检查各版本字节/摘要，`diff` 应显示用户未暂存修改，`diff --staged` 仍为空。
   最后执行 `moonvcs --offline status` 和 `recover --check`，确认新库无 pending；不自动 add/commit。
   `status` 不接受尾部选项，不能写成 `status --offline`；这与 `show`、`log` 的参数处理不同。

独立执行的实际命令、cwd、退出码和 CLI 输出逐项写入 `commands.jsonl`，包括故障子进程的 `-9`。
`result.json` 记录 CLI 摘要、事务/Ref/Commit、完成检查和边界。
与测试入口中的临时演练不同，独立入口不删除输出，适合在本机逐项人工复核。

## 通过条件与限制

- 旧文件、迟到 inode 写入、原路径用户文件、未跟踪二进制数据及未安装目标均保留。
- 原活动仓库和唯一证据副本未被“修复”；原稳定 advisory inode 不被移动/删除。
- 新库先验证干净快照，再明确合回用户修改；合回后故意为未暂存状态，不冒充全工作区干净。
- 不需要直接覆盖原 HEAD/index、删除锁、重放 journal、重新 publish Quarantine 或盲重试 switch。

这只覆盖一个已知 backup 阶段、进程停止后的人工选择路径，不证明所有 IO 故障、敌对同账户路径竞态、
跨设备移动、真实掉电、证据丢失或未知事务均可安全恢复。真实仓库无法确定所有权/目标/内容时必须继续阻止写入。
保留副本和成功 switch 备份都会增加磁盘占用，没有自动清理或 GC；不得把“可保留”解释为“可安全批量删除”。
