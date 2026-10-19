# 暂存并发、目录同步与恢复检查

本页描述实际实现，不是完整崩溃恢复协议。GC、自动恢复日志重放、自动清理和真实掉电验证仍未实现。

新增 branch/switch 的手工处置以根目录 [BRANCH_SWITCH.md](../BRANCH_SWITCH.md) 为准。
switch-transaction 存在时普通操作返回 SwitchIncomplete/18；recover --check 只读报告 phase、事务 ID、
起点/目标 Ref/Commit，以及实际 HEAD/index 相对保存摘要的 old/target/other/missing 状态。
退出 16 也可能已经发布 HEAD 或将事务移入 switch-history，不能只看 pending 目录是否存在。
旧文件在失败和成功后都保留；不得删除事务或稳定 advisory lock，不提供自动 continue/abort。
可逐项复现的中断保留/新目录重建/用户版本核对流程见 [人工演练](SWITCH_MANUAL_RECOVERY.md)。
该 fixture 演练不是处理真实仓库的自动恢复程序，独立输出不会自动删除。

## 并发 add

Repository.add 在读取 index 之前获取稳定 inode 的 staging-transaction.lock advisory lock，
直到路径处理、Blob 写入、index 读改写和最终发布完成才释放。失败/取消关闭句柄；
进程终止后的 OS 锁释放不要求删除该文件。等待超过 30 秒返回 StagingBusy（退出 15）。

锁域现扩展为当前版本 add/commit/branch/switch，以及 receive 最终发布（receive-publish → staging）。
这保护协作写入者，不是跨进程文件系统权限边界，也不是工作区多文件快照事务。
不同路径的并发 add 不再因旧 index 快照静默覆盖对方。原有 index.lock 的 CreateNew 检查仍保留，
遇到未知遗留锁不会自动删除或覆盖。

独立回归使用测试专用 LD_PRELOAD pread 屏障；它从真实 index 读取后暂停两个 CLI 进程。
旧二进制两次 add 均退出 0，最终只保留 second.txt；修复后第二个读改写必须等待第一个完成。
屏障没有链接进正式 CLI，没有修改 WIT 或 Policy API。

## 发布和同步顺序

对象与元数据写入的关键顺序是：

    创建临时文件 → 写字节 → 文件 sync → rename → 父目录 sync

新增对象桶/存储目录与仓库初始化也同步相关目录；Ref 发布继续执行旧值 CAS，
并在 rename 后同步父目录。实现使用现有 MoonBit async File.sync，不引入 Rust VCS 逻辑。

如果 rename 已成功、随后目录同步失败，返回 PublicationUncertain（退出 16）。
此时数据可能已经可见，不能把非零退出当作回滚或直接盲重试；应先检查 index/Ref 当前状态。

## 退出 16 的人工处置协议 v1

这是协作维护者的保守操作流程，不是自动恢复实现。退出 16 不包含发布阶段或幂等令牌；
对象、index、策略配置或 Ref 中的某个 rename 可能已经成功，不能只检查一个文件就推断全部状态。
可见状态的检查也不能证明掉电后持久性，不能把这次诊断当成完成了缺失的目录同步。

1. 停止重试并保留原始命令、退出码、预期旧 Ref/目标 ID（如果已知）和候选来源。
   不把没有出现 Commit created / Push accepted 当作“未发布”。不要在日志里保存候选凭据内容。
2. 排除 IO 故障；由仓库所有者停止并协调所有写入者，禁止它们自行重启。
   recover --check 的瞬时 idle/inactive 不是全局维护锁，也不能阻止其他同账户进程重新写入。
3. 对工作区、完整 .moonvcs 和原始 bundle 做独立保留副本，保护权限并确认副本可读。
   保留 Ref、index、配置、promises、对象、锁和 Quarantine，不能只备份 HEAD。
   在原库仅做 recover --check、读取已确认非符号链接的 HEAD/Ref、计算 index/配置文件摘要等检查。
4. 在副本中用 `moonvcs show HEAD --offline`、`moonvcs log --max-count 1 --offline`、
   `moonvcs --offline status` 检查语义。status 不接受尾部参数，不要写成 status --offline。
   后两类普通查询可能修复 promise 或创建 advisory-lock 文件；offline 只是禁止远端获取，
   并不使这些命令成为只读工具。缺失对象、损坏、未知类型、截断检查或无法归因时停止，不尝试强行修复。

| 观察到的状态 | 允许的下一步 |
|---|---|
| add 后 index 已包含预期的精确 Blob ID，工作区仍为所需内容 | 视为已经暂存；必要时在 IO 正常、遗留排他锁已按下节保留处理后重新 add。重新读取工作区是一次新操作，不是旧事务重放 |
| add 后 index 仍为记录的旧快照 | 对照保留副本和原请求检查；解决已确认的遗留锁后，用普通 add 重新暂存，不能直接将 index.lock 改名为 index |
| Ref 已等于已知的预期目标 Commit ID | 本次目标当前已发布，不再次 commit/push 来“补成功”。验证目标对象和策略配置，保留不确定持久性的记录 |
| Ref 仍为已知旧 ID，候选对象部分存在 | 不把对象存在当成审批；在 IO 恢复、状态和候选已确认后走正常 commit/receive 路径，重新运行 required policies 和 CAS |
| Ref 是其他 ID，或没有足够记录确认当前目标属于哪次请求 | 停止并报告冲突/未知。不能覆盖 Ref、使用 Quarantine 发布或仅按相同 message 判断“就是我的提交” |

本地 commit 的目标 ID 可能因异常没有打印。归因需核对 tree、parents、author、timestamp、message
及可重构的对象 ID；缺少预期候选信息时不能自动认领当前 HEAD。重新 commit 的时间戳/Parent 也可能改变，
所以当前没有 exactly-once 或通用安全重试命令。receive 的原始 bundle 明确绑定目标/预期旧 Ref，
也仍要先检查远端当前状态；不能把 lost acknowledgement 当成无条件覆盖许可。

## 遗留锁与隔离区的人工处理

先满足上述停止写入、状态核对和完整备份条件。不要根据 mtime、PID 不存在或一次 try_lock 成功
独自作出清理决定；旧格式和不明来源尤其应停止并请求所有者确认。

| 资源 | 人工处理规则 |
|---|---|
| staging-transaction.lock / lazy-fetch.lock / receive-publish.lock | 稳定 advisory-lock inode，保留原文件；不删除、不移动、不替换，否则旧句柄和新文件可能分裂为两个锁域 |
| 已确认属于中止请求、且不再有写入者的 index.lock 或某个 Ref.lock | 保存内容摘要和完整副本后，只把这一个精确路径移到仓库外、同文件系统的私有证据目录，保留以供核对。不得按通配符批量移动，不直接发布锁文件中的内容；随后重新走正常命令 |
| active Quarantine | 不触碰；先协调/停止实际请求，再重新检查。lease 检查不是服务端 OS 权限边界 |
| 已确认中止请求的 inactive lease Quarantine | 在维护窗口和备份后，将该精确请求目录整体保留到仓库外的私有证据目录；原 bundle 只能经新的 receive 再验证，不拷贝隔离对象到正式库或更新 Ref |
| unknown_owner_or_activity、缺 lease、符号链接或检查错误 | 保留，不能推断为安全垃圾；缺少所有权证据就不处置 |
| 临时/不可达对象及其他元数据 | 保留。没有 promise-aware GC；“当前 Ref 不可达”不是安全删除依据 |

以上仅定义人工维护步骤，没有自动执行这些移动，也不对人工备份/移动提供掉电事务保证。
证据目录可能含未扫描的候选数据，应限制读取权限；不要把它作为公共日志或参赛附件发布。
处置后重新执行 recover --check，对比保留记录，再逐项恢复协作写入；异常持续则停止，不循环重试。

这些步骤增强同步顺序，不等于完整仓库生命周期的掉电证明。
clone 工作区目录树、跨多个对象的 promotion、清理、锁状态与统计都不因此变成单一持久事务；
没有目录级恢复日志、自动回滚、exactly-once 或真实掉电故障注入结果。

## 只读检查命令

在仓库目录执行：

~~~bash
moonvcs recover --check
~~~

它只检查元数据路径与锁状态，不删除、不重放、不发布 Quarantine，也不是完整对象库 fsck。
JSON 中 read_only=true、automatic_recovery=false、journal_replay=false、gc=false，
power_loss_verified=false。退出 0 仅表示检查完成；必须查看 requires_attention 和 truncated。

| finding | 含义与限制 |
|---|---|
| advisory_lock / active | 观察时 try_lock 失败，有协作持锁者；不删除 |
| advisory_lock / idle_file_not_a_stale_lock | 文件存在但此时可获取锁；持久锁文件不等于遗留排他锁 |
| exclusive_lock_or_pending_write / unknown_owner_or_activity | 例如 index.lock；缺乏所有权/恢复日志，保留并要求人工检查 |
| quarantine / active | 当前版本 receive 持有 active.lock lease |
| quarantine / inactive_lease_requires_inspection | lease 可获取；可能异常退出，但不能据此自动删除或发布 |
| quarantine / unknown_owner_or_activity | 旧格式/缺 lease/未知目录，保留 |
| temporary_object / requires_inspection | 临时对象文件，需要检查，不能当作安全 GC 候选 |
| unsupported_kind_preserved / inspection_error | 不跟随元数据符号链接；并发变化或 IO 错误明确报告 |

检查是瞬时观察，不是与所有写入者线性化的恢复事务。
最多访问 20000 项、深度 64、保留 1024 个 finding；超限设置 truncated 和 requires_attention，
不能把截断报告当作“干净”。不会读取并打印对象或 Quarantine 的内容。
本地元数据/仓库所有者仍受信任，静态路径检查不构成防同账户 TOCTOU 攻击的完整边界。

## 已运行的验证

tests/recovery_audit.py 使用拥有的临时仓库和测试专用 fsync gate：

- index 文件同步后、rename 前 SIGKILL：旧 index 保留；检查报告 index.lock，不自动删除。
- index rename 后、父目录同步前 SIGKILL：可见 index 完整；未声称掉电后仍相同。
- Quarantine 校验前暂停/终止：lease 区分活跃与已失活；服务器 Ref 和正式对象不发布。
- 未知隔离区和指向无害模拟资源的符号链接保持不变，输出不读取资源内容。
  元数据根 .moonvcs 本身是符号链接时也明确拒绝遍历；该情况先补测试复现失败，再修复。
- 正常 add 确实调用对象桶与元数据目录同步。
- rename 后注入目录同步 EIO：返回退出 16，并保留已经可见的 index。
- Ref rename 后注入目录同步 EIO：提交返回 16，没有 Commit created，但 HEAD 已指向有效 Commit；
  index 保持不变，检查不能再次创建 Commit。
- 受控停止后保留精确 index.lock 并重新 add；保留已中止 Quarantine 后原 bundle 经正常 receive
  重新执行 required policies；这些人工流程只在拥有的临时仓库测试，不是自动恢复功能。

进程终止不是拔电实验，目录同步调用观察不是存储设备持久性认证。
后续应先定义日志/所有权/重试协议，再实现受控恢复；不要批量删除 .lock、临时对象或 Quarantine。
