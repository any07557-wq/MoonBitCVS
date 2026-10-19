# Branch / Switch：先行安全契约

本文件先于实现建立规则；功能状态和实测证据另见后续验证记录。Linux 原生原型，
不宣称完整 Git checkout、跨平台、对同账户恶意进程的 OS 隔离或真实掉电事务。

## 命令与范围

- `branch`：列出本地分支，当前分支标 `*`，按 UTF-8 字节排序；未出生 HEAD 单独注明。
- `branch <name>`：仅从当前已存在 HEAD Commit 创建；不切换、不覆盖已有 Ref。
- `switch --dry-run <name>`：只读预检，输出目标 Commit 和新增/替换/删除路径；不隐式 Fetch、不创建锁或工作区文件。
- `switch <name>`：切换到已有本地分支；未出生当前 HEAD 允许，但 index 必须为空且目标存在。

没有分支删除/重命名、`switch -c`、任意 Commit/detached HEAD、force、merge、stash、
自动 `--continue/--abort` 或通用 checkout 命令。所需对象必须在本地，缺失时明确失败；
另行通过既有 show/Lazy 验证路径获取后重试，不能据此假设有可信远端承诺。

名称采用有界 ASCII 子集：总长不超过 240，每段 1–64 字符、最多 8 段；
每段以字母/数字开头，其余仅字母/数字/`._-`，不含 `..`，不以 `.` 或 `.lock` 结尾；
`HEAD` 保留。拒绝绝对路径、控制字符、反斜杠和参数式名称，不承诺 Git Ref 名完全兼容。
不存在与已有祖先/后代 Ref 的文件/目录冲突，也不能把悬空链接当作“分支不存在”。

## 切换拒绝条件（全部在工作区写入之前检查）

| 条件 | 行为 |
|---|---|
| HEAD/index/Ref 结构非法、对象缺失/损坏/类型错、危险 Tree 路径 | 拒绝，不修改工作区或引用 |
| index 与当前 HEAD 的完整文件快照不同 | 拒绝；先提交或自行保留暂存改动 |
| 任一当前跟踪文件缺失、内容改变或类型改变 | 拒绝，即使目标不改这个文件；不自动丢弃或合并 |
| 目标新增文件路径已存在任何未跟踪文件/目录/链接 | 拒绝，即使内容相同；无关的未跟踪文件保留 |
| 目标路径祖先不是目录、含链接、路径越界、元数据路径 | 拒绝 |
| 文件 ↔ 目录互换，包括空目录挡住目标文件 | 第一版拒绝；不递归删除目录 |
| 当前或目标含非根空 Tree | 拒绝，避免扁平文件计划遗漏显式目录语义；根空 Tree 表示空快照仍允许 |
| 未完成 switch 事务、未知事务文件、陈旧 index/HEAD/Ref 排他锁 | 拒绝普通写操作；先检查，不盲删 |
| 预算超限，或预检后观察到工作区/元数据/目标 Ref 改变 | 拒绝；写入已开始则转入可识别的未完成状态 |

校验目标 Commit、完整 Tree 和全部 Blob：SHA-256、规范类型编码、规范路径与有界图遍历。
不要求获取祖先历史。路径/对象预算复用只读 snapshot reader：8 MiB Blob、32 MiB 编码对象、
64 MiB 每次 snapshot-reader pass、10000 文件、20000 Tree 条目、4096 路径字节、128 路径层级。
预检、状态复核与完成核验会分别读取，这不是整条命令的 64 MiB 总 IO 或进程 RSS 限额。
计划携带精确起点/目标 Ref、Commit、旧 HEAD/index 和有序变更；新 index 与 manifest 均须在写入前
满足后续 reader/recover 的 4 MiB 上限，避免生成自己无法再次读取的状态。dry-run 不是可直接重放的授权令牌。
磁盘、权限、跨挂载 rename 等 IO 仍可能在运行期失败；预检通过不代表整个操作必然成功。

## 协调与发布顺序

协作的 add、commit、branch 创建、switch 共用稳定的 `.moonvcs/staging-transaction.lock` advisory inode。
receive 最终发布也取得此锁，并在锁内重新检查 Ref/config；锁顺序为 receive-publish → staging → fetch/Ref 排他锁，
其他路径不反向取得 receive-publish。等待有界，死亡由 OS 释放 advisory lock；**永不删除或移动其文件**。
旧版或自行改文件的进程不遵循该协议，不属于并发安全保证。

switch 持锁重新预检并复核原状态，然后按下表执行：

| 状态 | 已发生的变化 | 下一步 / 失败含义 |
|---|---|---|
| Preflight | 无写入，仅完整校验和计划 | 拒绝可安全修复后重试 |
| Preparing | 创建 `.moonvcs/switch-transaction/`，保存 manifest、旧/新 HEAD/index、目标文件 | 此目录一旦存在即阻止其他普通写操作；未完整准备也须检查 |
| Prepared | 文件和目录同步完成，旧工作区未动 | 可开始 applying；没有自动重放 |
| Applying | 逐个将旧文件 rename 到事务 before/，将 after/ 新文件无覆盖 rename 到工作区 | 可能是混合工作区；HEAD/index 仍为旧值，保留实际旧文件和所有证据 |
| IndexPublished | 完整目标工作区验证后，原子替换 index 并同步 | HEAD 可能仍旧；不能 commit/add 或盲重试 |
| HeadPublished | 最后替换 HEAD 并同步；不改任一分支指针 | 可能已切换成功，但事务尚未归档 |
| Completed | 验证目标状态，将整个事务移到 `.moonvcs/switch-history/<transaction-id>/` 并同步 | 普通操作恢复；旧文件备份仍保留，不自动 GC |

写工作区不 truncate、不覆盖 rename。对替换/删除路径，再次检查当前字节，先无覆盖移走原文件，
同步备份和原目录，再无覆盖安装目标文件；对新增路径使用 no-replace。
即使非协作进程在间隙创建碰撞文件，也不能静默覆盖它；移走的旧 inode 保存在事务备份中。
不删除任何工作区目录；新增目录权限 0700，新文件权限 0600。没有可执行位/权限位跟踪；
未改动文件保留原 inode/权限。rename 不修改外部硬链接的内容。

旧数据在成功后也保留，避免以自动清理丢掉晚到的旧 inode 写入；目录受私有权限保护，
没有自动恢复/过期清理或容量回收，磁盘占用会增长。事务记录包含相对路径和哈希，不打印文件内容。
准备区/备份不作为插件输入，不参与新提交。

## 失败、退出码与中断处理

- 正常预检拒绝：退出 1；损坏对象沿用 8；协作锁超时沿用 15。进入准备前不改工作文件/index/HEAD。
- 事务目录存在后失败、取消或进程终止：保留事务及备份；普通写入默认拒绝，显式 `SwitchIncomplete` / 退出 18。
- rename 后目录同步失败：保留 `PublicationUncertain` / 退出 16，**可能已经切换或完成归档**；不当成回滚。
- SIGKILL 不能依赖 defer 清理；阶段记录可能落后于实际文件操作。恢复时必须比较文件/哈希，而不是仅相信 phase。
- HEAD/index 是两次发布，不是单个原子事务。普通读命令发现 pending 也拒绝；它们仍不是全局文件系统快照。

出现 16/18，先停止全部写入者，执行只读 `moonvcs recover --check`，保存完整输出。
报告应给出事务路径、phase、起点/目标 Ref、目标 Commit 和事务 ID，并按保存摘要标明当前 HEAD/index
是 old / target / old_or_target / other / missing；该元数据观察不是完整工作区一致性证明。
未知/不完整 manifest 保留原样并要求人工检查。
备份**整个工作区与 `.moonvcs`**，以及任何未归档候选/备份。不要删除稳定 advisory lock、
不要直接重试 switch，不要用 add/commit 将混合工作区误提交，也不要直接覆盖 HEAD/index。

最小人工处理协议（仅在停止协作写入者、独立保留证据后）：

1. 在副本中核对 manifest 与保存的 old/new HEAD/index、起点/目标对象哈希和实际目标 Ref。
   缺少或不一致的证据按未知处理，不执行写入；备份文件可能包含更新的用户内容，不能只按旧 Blob 覆盖。
2. 工作区、index、HEAD 已全部与目标一致且 Ref 未漂移：在副本中确认完整目标状态，再由操作者
   将该**精确事务目录**保留移出 active 路径，作为完成证据；不能删除它。同步失败还应重新同步并复核。
3. 状态不一致：没有自动 forward/rollback。保留 before/、尚未安装的 after/ 和工作区的每个不同版本，
   在新目录从已核验对象重建所选快照，再逐一合回用户保留内容；不得在原仓库直接批量复制/删除文件。
   完整确认新目录可用后才能考虑弃用旧活动仓库。无法判定时保持 blocked。
4. `recover --check` 不重放、不发布、不清理；普通查询若被 pending 阻止，仅在证据副本中由操作者
   精确保留移出该事务目录后做语义检查。原活动仓库保持不动。

这比自动恢复保守，第一版目标是可识别、保留数据和提供安全处理指引，不是恢复体验终点。
不把进程终止/EIO 注入称作掉电证明，不保证敌对同账户路径替换、旧程序写入或多文件读的原子性。

可重复的拥有者测试演练见 [SWITCH_MANUAL_RECOVERY.md](docs/SWITCH_MANUAL_RECOVERY.md)：
独立保留证据、仅在检查副本中移出精确事务、新目录 clone 核验后由操作者选择用户版本。
它不是产品自动恢复接口，原库 pending 与稳定锁保持不动。`moonvcs --help` 同时提示
成功备份位于 `.moonvcs/switch-history/<transaction-id>/before/`，磁盘占用增长且无自动清理。

## 必须验证

分支列出/从 HEAD 创建、非法名/已存在/Ref 前缀冲突、未出生 HEAD、两个创建者竞争；
正常切换新增/替换/删除、Unicode/空/二进制；脏 index/工作文件/删除、未跟踪与空目录碰撞、
符号链接/FIFO/路径穿越、文件目录互换、缺失/损坏/错误类型、dry-run 不写；
预检后目标 Ref/用户文件变化；应用前/中、index 后、HEAD 后故障/死亡、旧 inode/备份保留、
no-replace 碰撞；pending 阻止 add/commit/branch/receive、稳定锁不被删除、recover 给出明确候选身份。

每次修复补重现测试。最终数量、命令退出码及未验证项写独立验证记录，不回写历史 177/149 项结果。
