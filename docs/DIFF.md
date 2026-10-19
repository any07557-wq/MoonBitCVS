# 提交前检查：diff

MoonBit 实现位于 [diff.mbt](../vcs/diff.mbt)，CLI 调用同一个 Repository.diff 接口。
不修改 WIT、插件 pin、对象编码或提交门禁。

## 三种比较

| 命令 | 旧侧 → 新侧 | 用途 |
|---|---|---|
| moonvcs diff | 暂存区 → 工作区 | 看尚未暂存的改动 |
| moonvcs diff --staged（或 --cached） | HEAD → 暂存区 | 看下一次提交实际包含的改动 |
| moonvcs diff HEAD | HEAD → 工作区 | 看已暂存和未暂存改动合并后的结果 |

HEAD 尚无 Commit 时视为空快照。暂存区保存完整文件快照，不是差异列表。
默认 diff 只比较 index 跟踪的路径；HEAD 模式比较 HEAD 与 index 的路径并集。
纯未跟踪文件不展示，先用 status 查找，再 add 后用 --staged 检查。
已暂存删除的路径若在工作区重新出现：默认 diff 仍忽略它，HEAD 模式比较实际内容。

可用 `-- <path>...` 限定文件或目录。路径是相对于当前工作目录的字面路径，
不支持 glob、Git pathspec 或 `..`，绝对路径和仓库元数据路径被拒绝。
没有筛选时从任意子目录运行均比较整个仓库；`-- .` 只比较当前目录。
不存在或未跟踪的筛选路径没有结果。目录过滤按完整路径段匹配，不会把 dir2 当作 dir。

~~~bash
moonvcs init
printf 'mode=base\n' >example.txt
moonvcs add example.txt
moonvcs diff --staged             # 空 HEAD → 新增 example.txt
moonvcs commit -m initial
printf 'mode=staged\n' >example.txt
moonvcs add example.txt
printf 'mode=working\n' >example.txt
moonvcs diff                      # -mode=staged / +mode=working
moonvcs diff --staged             # -mode=base / +mode=staged
moonvcs diff HEAD -- example.txt  # -mode=base / +mode=working
~~~

## 显示契约

路径按 UTF-8 字节稳定排序；新增、修改、删除均有明确 change 标记。
文本使用行级差异、3 行上下文和准确的旧/新行号；缺少末尾换行有单独标记，
CRLF 中的 CR 显示为 `\r`。空文件的新增/删除仍有文件头与 change 标记。
含 NUL 或无效 UTF-8 的任意一侧按二进制处理，仅显示类型、两侧路径和字节数，不打印 payload。

控制字符、反斜杠及所列 bidi 格式字符经过显示转义，普通 Unicode 保留。
例如 ESC 显示为 `\u{1b}`，TAB 为 `\t`，LF 文件名为 `\u{a}`。
这是人工检查视图，**不是可交给 Git apply/patch 的补丁协议**；没有 apply 命令。
文本内容是用户主动请求的原文差异，不提供 Secret 脱敏：分享 diff 日志前需自行审查。

相同内容没有输出；有差异与没有差异均退出 0，不提供 --exit-code。
参数、缺失本地对象、超限或观察到并发变更时退出 1；损坏对象沿用 ObjectCorrupt/退出 8。
结果全部构造成功才写到 stdout；失败不会先打印一部分补丁。

## 只读与完整性

不调用 LazyObjectStore.get，不创建对象、锁、promise 或统计，不写 index、HEAD、Ref、工作区，
不执行插件，也不联系远端。普通文件读取可能引发 OS atime 更新，不属于“零文件系统影响”保证。
本地读取仍核对 SHA-256、类型、规范编码和比较所需的 Tree/Blob；
Tree 路径和 index 文件/目录冲突受检查。相同两侧 ObjectId 仍读取并验证一次 Blob。
不遍历旧 Commit 的 parents，也不是全仓库 fsck。

Partial clone 的当前快照已缓存时可直接使用，包括全局 `--offline diff`。
必要对象不在本地时明确报 missing local object，并给出 `moonvcs show <id>` 提示。
show 是独立的、会按现有 promise/provenance 校验决定是否 Fetch 的命令；
它可能失败，diff 不承诺该对象存在可授权远端来源。
diff 本身只检查本地内容，不认证远端 Ref 或审计/修复 promise 元数据，
不能从 diff 成功推出所有 promisor 元数据有效或来源可信。

工作路径逐段 lstat，拒绝现存或悬空符号链接及特殊文件，不读取模拟外部目标。
被目录替换的已跟踪文件、被普通文件替换的已跟踪目录后代显示为删除；
新路径仅在进入暂存区后才作为跟踪文件展示。不记录空目录、权限位或 rename。
读取前后检查文件 size/mtime/ctime，并在输出前复核读过的 index/HEAD/Ref 字节；
观察到变化则要求重试。没有全局文件系统快照，不保证检测所有竞态或 ABA，
也不提供对同账户恶意并发替换的 race-proof 路径隔离。

## 预算

| 资源 | 当前上限/行为 |
|---|---|
| 工作文件 / Blob payload | 每侧每文件 8 MiB |
| 单个规范对象 | 沿用 adapter 的 32 MiB |
| index / HEAD、Ref | 4 MiB / 4 KiB |
| 总读取（含最终元数据复核） | 64 MiB；超限失败 |
| HEAD Tree 条目 / 跟踪文件并集 | 20000 / 10000 |
| 路径 UTF-8 字节 / 路径层级 | 4096 / 128 |
| 文本 LF 数 | 每文件每侧 100000 |
| 行级 LCS | 去掉公共首尾后，每文件最多 1000000 cells、每命令累计 8000000 cells |
| LCS 超预算 | 显示变化中段的完整删除/新增，保留首尾上下文；不是最小编辑保证 |
| 总显示输出 | 8 MiB；超限失败，不静默截断 |

这些是原型算法/IO 预算，不是进程总 RSS 或实时执行时限。

## 验证

~~~bash
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/build-vcs.sh
python3 tests/diff_audit.py
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/test.sh
~~~

8 项 native formatter/预算回归、20 项独立真实 CLI 测试；其中一项以固定随机种子的
40 对内容重建工作文件，另一项用既有测试专用 LD_PRELOAD 屏障验证并发 index/Ref 变化不输出部分结果。
子案例不额外膨胀测试计数。运行结果与安装验收边界见 [DIFF_VALIDATION.md](DIFF_VALIDATION.md)。
