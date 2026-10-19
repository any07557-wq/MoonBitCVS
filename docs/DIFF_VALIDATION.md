# Diff：实现与本机验证

这是 diff 轮的 177 项历史源码快照。后续最小 branch/switch 与共享 reader 的兼容验证见
[当前产品验证](BRANCH_SWITCH_VALIDATION.md)；不追溯更改本页当时的数量和产物。

日期：2026-10-18，Asia/Shanghai。范围：本轮产品闭环优先级 1，未实现 branch/switch/checkout。

## 交付

- [MoonBit diff](../vcs/diff.mbt)：只读本地快照、哈希/类型/规范编码验证、行差异与二进制摘要。
- [CLI](../vcs/cli.mbt)：diff、--staged/--cached、HEAD 和字面路径过滤；帮助与明确的 Diff failed 错误。
- [8 项 native 回归](../vcs/diff_wbtest.mbt)与[20 项真实 CLI 回归](../tests/diff_audit.py)，接入 scripts/test.sh。
- [使用与预算契约](DIFF.md)、README Quick Start、架构、路线图、状态与已知限制同步。

WIT 仍为 v1，SHA-256 `4b3ff703ed44a679ea8b689e0977867505ec602d159d2f57f9c4773bccc8725d`。
五个组件 pin、对象序列化和 required-policy 提交/接收门禁未改。
Rust 未增加 VCS diff 逻辑，算法与只读仓库比较均在 MoonBit。

## 已执行命令

| 命令 | 实际结果 | 原始记录 |
|---|---|---|
| MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/build-vcs.sh | 退出 0；native check/test/release 使用 --deny-warn，78 项 native 通过 | target/reports/diff-build.log |
| python3 tests/diff_audit.py（初版） | 退出 0，20 项通过 | target/reports/diff-cli-initial.log |
| MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test.sh（首次） | 退出 0；177 项及 CLI/安全/Lazy/Remote/双轮四场景 smoke 通过 | target/reports/diff-regression.log |
| python3 tests/diff_audit.py DiffAudit.test_partial_clone_cache_hit_and_miss_are_strictly_read_only | 退出 0；补强缺失祖先场景后再验证；不重复加计测试数量 | target/reports/diff-partial-snapshot.log |
| MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test.sh（冻结后收尾复验） | 退出 0；最终 177 项及全部 smoke 再次通过，包含缺失祖先与 Ref 父目录子案例 | target/reports/diff-regression-final.log |
| moon -C vcs fmt --check；bash -n scripts/test.sh scripts/package-submission.sh；关键文件 sha256sum -c | 均退出 0 | 检查结果由本轮终端记录；摘要清单另存 |

日志中的预期 Reject/Trap/CapabilityDenied/Offline 由测试显式断言，不代表完整入口失败。

最后冻结的关键源码与本机 CLI SHA-256 位于 target/reports/diff-source-sha256.txt，
可从仓库根目录执行 `sha256sum -c target/reports/diff-source-sha256.txt` 核对。
这是关键实现/测试文件清单，不是整份源码、最终发布包、签名或工具归档备份。
同一最终代码的收尾完整回归日志为 target/reports/diff-regression-final.log。

当前独立计数为 177：78 native、26 Rust、19 Wasm 插件、9 系统审计、6 验证脚本、
4 跨进程暂存、7 恢复、1 Lazy 逻辑读取、7 工具归档/Registry、20 diff CLI。
相对上轮 149 项只新增 8 native + 20 CLI；重复构建、40 对随机输入、
子案例、单项重跑和重复演示不额外计数。[统一入口与分项计数](../TESTING.md)。

## 验证到的行为

- 同一文件有 HEAD/base、index/staged、工作区/working 三种字节时，三个命令输出不同且正确。
- 未出生 HEAD、新增/修改/删除、暂存删除后重建、空文件、Unicode、CRLF、无末尾换行、NUL/无效 UTF-8。
- 文件/目录替换与字面路径筛选；纯未跟踪文件不泄漏进候选差异。
- 文本 hunk 范围、重复行、远距离插入/删除；固定种子 40 对真实 CLI 输出能重建工作文件。
- LCS 超预算完整替换，行数/文件/输出预算显式失败，不能用截断结果伪称完整 diff。
- 三个模式和 --offline 前后，工作文件、metadata 内容、mode、inode、mtime/ctime 与锁清单不变；不检查 OS atime。
- 部分克隆缺少祖先仍能比较当前已缓存快照；当前 Blob 缺失时不 Fetch/创建锁/改统计，
  而是提示对象 ID 与独立 show 步骤；按现有 Lazy 验证正常 Fetch 后 diff 恢复。
- 损坏 Blob 即使两侧 ID 相同仍被识别；HEAD/Tree/index 类型错、缺失 Tree、非法路径/Ref 父目录拒绝。
- 叶节点/祖先/悬空 symlink、metadata symlink 和 FIFO 拒绝；均使用临时模拟资源，不读取真实凭据。
- 测试专用读取屏障稳定制造 index/Ref 并发变化：退出 1，stdout 不包含部分差异。
- 路径和文本中的 ESC、C0/C1、所列 bidi 控制及反斜杠显示转义；不是全局 Unicode 混淆证明。

## 不能扩大解释的边界

本机复用了既有固定工具和依赖缓存。这不是新源码的空白 rootfs 安装、另一目录解包重建或完整离线证明。
此前 fresh-03 的 149 项与四场景仍是增加 diff 之前的源码快照，报告和旧提交包未追溯改写。
本轮没有重新生成最终参赛包、外部备份工具归档或重跑宽 Tree 性能基准。

diff 不联系远端，不审计/修复 promise，也不认证原始 Ref/作者。只比较当前所需快照，不是 fsck。
缺失本地对象会失败；文本经过显示转义，不是可 apply 的补丁，也不做 Secret 脱敏。
没有全局工作区原子快照、race-proof 同账户路径隔离、权限位/空目录/rename 跟踪或实时/RSS 限额。

branch/switch、安全 checkout、剩余约 1 秒宽 Tree 剖析、同版本最终交付与退出 16 体验仍按路线图后续推进。
认证、ACL、TLS、服务端 OS 权限分离、Host/JIT 总内存与自动恢复也未因 diff 而解决。
