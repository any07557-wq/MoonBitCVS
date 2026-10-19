# 阶段 8：黑客松最终交付记录

这是此前阶段 8 交付与随后风险审查的历史快照；当前代码修复、安装复现和测试数量以
[当前状态](STATUS.md) 为准。以下历史数字和审查时的状态不追溯改写。
后续已新增只读 diff，见 [验证记录](DIFF_VALIDATION.md)；下文“diff 未实现”是当时的历史范围。

实际验证日期：2026-10-17，Asia/Shanghai；Linux x86_64 / WSL2。
本阶段整理已有实现、增加可重复的最终演示与本地交付流程，不新增大型 VCS 功能。
没有改动 WIT、对象编码、插件版本/摘要或既有 Core/Host 安全语义。

范围澄清（2026-10-18，仅文档）：所谓“八阶段完成”仅指当前收敛后原型范围内的验证与交付，
不是原始功能愿景全部完成。diff/branch/switch/merge、通用 checkout 和 Git 协议均未实现。
clone 只在初始化时物化固定 HEAD；Ref/CAS 不等于分支管理命令。此前测试通过不覆盖这些缺口。

部署风险澄清（2026-10-18，仅文档）：远端仍是本地文件系统/stdio 原型，
没有认证、ACL、TLS 或服务端 OS 权限分离。独立 receive 进程仅独立执行入口验证，
不能阻止同账户直接修改服务器对象、Ref、策略或运行文件。现有绕过测试不证明能抵抗这种文件篡改。

性能风险澄清（2026-10-18，仅文档）：历史 10000 对象、498 文件快照基准中，
同一 Tree 缓存读取中位 2165.92 ms，首次读取 1856.86 ms。零新增传输成立，读取更快尚不成立；
P7-001 尚未修复。本次未重新测量或优化，重复来源校验的耗时占比也未经过 CPU 剖析确认。

可靠性风险澄清（2026-10-18，仅文档）：并发 add 的完整 index 读改写未串行化，
可能丢失一方暂存修改；Ref CAS 不能覆盖此问题。文件 sync/rename 不等于目录 fsync 或掉电可恢复。
没有恢复日志或 GC；进程死亡可能残留排他锁文件、临时对象或 Quarantine。
普通异常/取消清理不是崩溃恢复保证，本次没有修复或新增故障注入测试。

安全保证澄清（2026-10-18，仅文档）：Wasm guest 限额不覆盖 Host/JIT 总内存或总 RSS；
插件摘要和名称/版本 pin 不证明作者身份或发布来源，没有插件签名验证。
获准读取候选内容并输出诊断的恶意插件仍可能在大小合规的诊断中回显内容；
Host 没有通用敏感内容脱敏机制，Scanner 的脱敏测试不代表任意插件都不泄漏数据。
这些限制尚未解决，本次没有新增资源控制、签名认证或输出保密机制。

接收规模澄清（2026-10-18，仅文档）：仅支持单 Ref、线性 fast-forward/新分支，
候选目标完整可达图上限为 4096 个不同对象、128 个 Commit，包括服务器已有祖先，
而非只计算新增上传，也不是仓库全局对象总数上限。每次仍重扫所有可达 Commit 的完整快照，
没有审批结果复用，历史增长会增加校验工作。现有 10000 对象本地基准不是接收端规模证据；
本次未放宽限制或新增接收性能测量。

## 交付导航

- [README](../README.md)：定位、问题、MoonBit/Wasm 价值、Quick Start、已实现功能与限制。
- [ARCHITECTURE](../ARCHITECTURE.md)：语言职责、Commit/权限/Lazy/Receive 的实际数据流。
- [SECURITY](../SECURITY.md)：TCB、已有/未有防护、安全假设及非生产边界。
- [ROADMAP](../ROADMAP.md)：已完成与未来计划分开，优先安装复现/权限分离/性能问题。
- [INSTALL](../INSTALL.md)、[TESTING](../TESTING.md)：固定版本、项目本地工具目录约定、回归和重建范围。
- [DEMO](../DEMO.md)：三分钟节奏、四个分段命令、真实输出解释和失败预案。
- [竞品比较](COMPARISON.md)、[技术摘要](HACKATHON.md)、[最终七问](CLAIMS.md)。
- 四张自包含 SVG：[系统](diagrams/system.svg)、[提交](diagrams/commit.svg)、
  [Wasm 权限](diagrams/sandbox.svg)、[Lazy Fetch](diagrams/lazy.svg)。
- [交付包说明](SUBMISSION.md)：源码与实际测试证据分包；保留现有 [LICENSE](../LICENSE)。

## 本阶段实际执行

| 命令 | 结果与范围 |
|---|---|
| MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test.sh | 退出 0；扩展后的完整阶段 1–8 入口；122 项独立测试及 CLI/演示 smoke |
| ./scripts/test-hackathon.sh --built | 退出 0；8 次真实策略提交，四个场景连续跑两轮；也已接入上述统一入口 |
| python3 scripts/hackathon-demo.py prepare --workdir target/hackathon-demo --commits 40 | 退出 0；40 个真实 required-policy Commit，不是预制对象 |
| python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo --only all | 退出 0；四个真实场景和状态断言通过 |
| ./scripts/record-demo.sh target/hackathon-demo | 退出 0；真实终端录制，可读取时序、命令与退出状态 |
| bash -n、Python AST、SVG XML 与文档本地链接检查 | 作为交付静态检查；不是额外的 Core 测试数量 |
| ./scripts/package-submission.sh | 源码/证据白名单分包；SHA256SUMS 验证通过，检查无绝对/父级路径、符号链接或私有工具/仓库目录 |

122 = 63 MoonBit native + 26 Rust + 19 MoonBit Wasm + 9 独立系统审计 + 5 验证脚本回归。
四场景两轮 smoke 另列，不重复计算插件重建时再次出现的测试输出。
静态 SVG 校验不是截图视觉审查；交付的是矢量架构图与真实终端录制，不是假造截图。

### 四个 Demo 的证据

| 场景 | 真实观察与断言 |
|---|---|
| Secret Scanner | add 后 commit 退出 2；HEAD 未产生、index 不变、无 Commit 对象；修复且重新 add 后 Pass/Commit |
| Capability | Restricted MoonBit guest 获得过滤后的授权内容并 Pass；缺 grant 与不支持能力均由 Host 返回 CapabilityDenied，退出 3 |
| Lazy History | 远端 120 对象 / 12976 编码字节；初始 clone 3 / 326；log 四条后缓存 6 / 893；重复读新增传输 0；offline 缺失退出 4 |
| Remote Policy | 未扫描客户端对象进入独立 receive，真实服务端 Scanner 拒绝，退出 12；服务器 HEAD、策略与正式对象不变，Quarantine 空 |

对象/字节是实际 loose-object 编码总量，不含 Ref/provenance 元数据、文件系统块或网络协议。
Capability 拒绝在实例化前，repository.secrets.read 没有实现为 Host 回调。
离线演示使用 --offline；阶段 5 另有物理移走模拟远端的测试。
Remote 测试运行于同一 OS 账户，仅证明接收入口不可由本地扫描结果绕过，不证明服务器磁盘权限隔离。

### 本机原始产物索引

以下路径是实际生成文件，随 evidence 包交付；源码仓库默认忽略 target，不依赖它们才能构建：

| 路径 | 内容 |
|---|---|
| target/reports/phase8-regression.log | 本阶段完整回归实际输出，最后为 phases 1–8 tests passed |
| target/reports/phase8-smoke.log | 最新双轮最终演示 smoke |
| target/reports/phase8-prepare-qay3607i/ | 40 提交准备的命令、返回码、对象统计 |
| target/reports/phase8-run-u377nxw8/ | 四场景现场运行 result.json / terminal.txt |
| target/reports/phase8-run-o7t54mds/ | advanced 时序录制所对应的四场景证据 |
| target/reports/phase8-recording.NaBAnE/ | terminal.typescript / timing.log；scriptreplay summary 显示 EXIT_CODE 0 |
| target/hackathon-demo/ | 已准备的真实 40 提交远端与各轮演示仓库，仅本机保留，不放进 evidence 包 |

这些记录包含实际命令与预期错误退出；不能只统计“出现非零”就判定演示失败，
也不能把任何未预期错误伪称演示中的预期拒绝。编排结果会明确记录 passed/failed。

另外故意对已存在的 target/hackathon-demo 再次执行 prepare，实际退出 1，
原 demo-state.json 摘要保持不变，验证不会覆盖已有目录。
该预期的保护性失败保留在 target/reports/phase8-prepare-d1jkuv53/，
其中 status=failed 是 prepare 正确拒绝这次请求，不是把失败删除后只展示成功记录。

## 复用的历史测试与性能数据

阶段 7 的完整 verify --clean-build --benchmark 实际退出 0，五阶段均成功。
源码隔离重建耗时 311 秒，复用了已安装工具链和缓存；未验证空白机器安装。
正式性能实验为每档 100/1000/10000 对象、20 快照、3 轮，9 个样本均完成。
本阶段未重新运行该完整基准，不把历史数据改写成新的测量。

[原始范围和表格](BENCHMARKS.md)、[阶段 7 结果](PHASE7_VALIDATION.md) 与
[已复现问题修复](PHASE7_FIXES.md) 保持原始语义：
Host 时间包含启动/JIT；10000 对象宽 Tree 在该次实测中缓存命中慢于 miss，没有 Git 性能比较。

## ABI 与组件内容标识（非作者身份认证）

构建再次核对，以下 SHA-256 未变化：

| 文件 | SHA-256 |
|---|---|
| wit/policy.wit | 4b3ff703ed44a679ea8b689e0977867505ec602d159d2f57f9c4773bccc8725d |
| secret-scanner.component.wasm | 3743537dad366b6af66d0b36d27eb77f47bee2b4669475e2d4a7b0fca5023cf2 |
| hello-policy.component.wasm | 8b6eb6b86ee378033088a252d856e6e902f5ff256c0d6dd7e608fca9c2fe6d4a |
| adversarial-fixture.component.wasm | d12bcf043b33e1ec15a0c98630c7819761d6ff8bad18d0bab8b02a1ff36698c6 |
| license-check.component.wasm | 444639aeeac8c19b143dc438dc36c27e45f98881d3b9f0e2555c5ce45ff7375a |
| restricted-plugin.component.wasm | 3d83dd0450ceb8a3bd4abf108f1760cc224349916025f2d0689b411f834f0df0 |

## 剩余不足，不能用交付包装掩盖

1. 没有认证、ACL、TLS、服务端 OS 权限分离、总 Host/JIT RSS 限额或签名分发。
2. Receive 只支持完整服务端、单 Ref、线性 fast-forward/新分支，图上限 4096 对象 / 128 Commit。
3. Scanner/License 是 MVP 规则，不是完整凭据检测、法律合规或数据防泄漏系统。
4. 宽 Tree 来源验证开销较高；没有 GC/LRU、promotion journal、目录 fsync 或完整掉电恢复。
5. 构建依赖项目本地工具布局及绝对路径配置；空白 OS/空缓存安装、其他平台未验证。
6. 没有长期 fuzz、依赖 advisory/CVE 数据库审计或形式化沙箱证明。
7. 没有 diff/branch/switch/merge、通用 checkout、Git 协议、Rebase、HTTP Remote 或浏览器 UI；
   最初功能愿景未全部完成，不宣传为完整 Git 替代品。

结论：MoonBit Core、真实 MoonBit Wasm、显式权限、实际提交拒绝、Lazy History 和独立远端门禁
都有代码与运行证据。新环境复现只验证到“已有固定工具和缓存的干净源码重建”，不能承诺零准备安装。
