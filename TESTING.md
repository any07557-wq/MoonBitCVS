# 测试、性能与证据

GitHub 实现验证 [CI #4](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39417969230)
在 `597e260` 上 264 项通过，三阶段退出 0；原附件已单独核验并持久归档。
该提交的 [公开库消费 CI](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39419237867)
另有 2 项测试与 README 通过，不并入源码总数。
证据见 [CI_VALIDATION.md](docs/CI_VALIDATION.md)。随后定稿工程文档不回写到这个 CI 提交，
最终归档的全部源码/文档是否重建通过以包旁报告为准，见 [冻结契约](docs/FINAL_DELIVERY.md)。

## 一条命令回归

已有 [固定工具链](INSTALL.md) 后，从根目录执行：

~~~bash
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/test.sh
~~~

统一入口包含构建、单元、CLI 集成、安全、Lazy/Remote demo、独立审计及最终演示 smoke。
任何未预期的非零退出都中止；预期 Reject/Trap/Offline 等错误被显式断言，不当作漏跑。

独立测试计数去重如下；重复构建产生的重复测试输出不重复计数：

| 类别 | 数量 | 入口 |
|---|---:|---|
| MoonBit native Core / Policy / Store / Receive / Diff / Branch/Switch | 86 | vcs 下 moon test --target native --deny-warn |
| Rust Host | 26 | cargo test --locked --manifest-path host/Cargo.toml |
| MoonBit Wasm 插件 | 19 | scripts/build-component.sh |
| 独立 CLI/安全审计 | 9 | tests/system_audit.py |
| 验证脚本回归 | 6 | tests/verification_harness.py |
| 跨进程暂存 | 4 | tests/staging_concurrency.py |
| 只读恢复/故障注入 | 7 | tests/recovery_audit.py |
| 单次 get 逻辑读取 | 1 | tests/lazy_read_audit.py |
| 工具归档来源/完整性及 Registry 续期 | 7 | tests/toolchain_archive_audit.py |
| Diff 独立 CLI | 20 | tests/diff_audit.py |
| Branch/Switch CLI 保护、故障、帮助与人工恢复演练 | 40 | tests/branch_switch_audit.py |
| 交付包/复现输入及持久化证据防护 | 19 | tests/submission_audit.py |
| CI 配置/归档安装防护 | 6 | tests/ci_audit.py |
| 公开包消费脚本/手动 CI 防护（无网络夹具） | 14 | tests/published_consumer_audit.py |
| 合计 | 264 | CI #4 实际通过；不含另列 CLI smoke / 演示或真实 registry consumer 的 2 项；CI #3 仍为旧 245 项 |

另外，scripts/test-hackathon.sh 会准备 8 次真实策略提交，并连续运行两轮四个最终场景，
测试状态不残留、不把第二次运行当首次 clone。它已接入统一入口，但不把这 8 次场景执行加入单元/审计总数。

2026-10-18 收尾已实际重跑当时的 225 项完整入口，退出 0；最终源码/CLI 摘要、原始命令、失败演练及成功结果见
[独立验收](docs/BRANCH_SWITCH_ACCEPTANCE.md)。177 项本机、149 项冷安装与此前 223 项各保留原版本边界。
2026-10-19 交付复现另加入 6 项防护回归，当时入口共 231 项，不把旧 225 项当作此版本的验证。
每份源码包的实际完整结果和摘要由包旁 REPRODUCTION.json/REPRODUCTION.md 给出；只有 status=passed 才算通过。
CI 接入轮另加 6 项归档安装/工作流防护，当时入口共 237 项；本地与 GitHub 运行结论必须分开，
见 [CI 说明](docs/CI.md)与[CI 验证记录](docs/CI_VALIDATION.md)。提交 `6d96157` 的 GitHub 运行 #1 实际成功，
原始附件摘要与 GitHub 元数据一致，独立核对 237 项及三阶段退出 0；本次只核验归档，未在本机重跑完整测试。

后续 Mooncakes 发布轮已独立重建并验证冻结源码 `d5d824211b06b276323dc5c8c27914b76e08ff15`：
2026-10-19 `scripts/verify.sh` 的 regression/environment/repeat-smoke 均退出 0，去重 **237 项通过**，
双轮四场景演示及额外两轮 receive smoke 通过。复用固定已安装工具与缓存，不是新 CI/冷 rootfs。
2026-10-20 新 registry consumer 实际下载 0.1.0，另有 **2 项**外部导入测试和 README 示例通过，
不并入 237 项，也不替代完整仓库集成测试；main 包测试布局的未来兼容性警告保留在日志中。
源码提交、包/安装内容摘要和全部日志见 [发布验收](docs/MOONCAKES_RELEASE.md)。

CI #2 归档后，打包遗漏修复增加 8 项持久化证据防护，submission suite 从 6 增至 14，
入口合计 245。新增范围包括显式清单选择、损坏/缺失、路径/命名空间、链接、预算、
CLI 全量检查后输出、分离解包和旧 target-only 兼容；实际复现结果另见
[打包修复验证](docs/PACKAGING_EVIDENCE_VALIDATION.md)，不改写历史 CI 的 237 项。

后续硬链接修复新增 5 项真实打包/解包回归，submission suite 为 19 项、当前入口为 250 项。
覆盖普通文件、等内容独立文件、硬链接附件/清单/历史报告的早期拒绝；
本轮实际命令、完整回归及旧冻结包保留情况见 [硬链接验收](docs/HARDLINK_PACKAGING.md)。

公开包消费自动化再加 14 项无网络脚本防护，当前源码入口为 264 项。
真实 `any07557-wq/moonvcs@0.1.0` 的 **2 项消费测试 + README 示例**由独立脚本/手动 CI 另报，
不与当前源码完整回归混算；本机命令、失败尝试和摘要见 [消费验收](docs/PUBLISHED_CONSUMER.md)。
原 `MoonVCS CI` 仍负责源码；新增 `Published Mooncakes consumer (0.1.0)` 只手动触发且不发布。
2026-10-20 WSL 恢复后，先保留被中断的 running 报告及两次截断 Cargo 缓存的失败，
定点重建依赖后，在同一验收源码目录重跑完整入口，**264 项、environment/regression 均退出 0**，
另有空 registry 的真实 2 项消费测试和 README 通过。复用工具/缓存，不是新 GitHub CI 或冷安装；
恢复后源码未变，173 个执行源码/配置文件与最终工作区一致，摘要和命令见
[独立记录](docs/PUBLISHED_CONSUMER_VALIDATION.json)。

## 分项执行

~~~bash
./scripts/build-vcs.sh
./scripts/test-policy.sh --built
./scripts/test-security.sh --built
./scripts/test-lazy.sh --built
./scripts/test-receive.sh --built
./scripts/test-hackathon.sh --built
python3 tests/system_audit.py
python3 tests/verification_harness.py
python3 tests/staging_concurrency.py
python3 tests/recovery_audit.py
python3 tests/lazy_read_audit.py
python3 tests/toolchain_archive_audit.py
python3 tests/diff_audit.py
python3 tests/branch_switch_audit.py
python3 tests/submission_audit.py
python3 tests/ci_audit.py
python3 tests/published_consumer_audit.py
~~~

单独调用 build-vcs.sh 前仍需设置 MOONVCS_MOON；--built 仅在产物已构建且 pin 一致时使用。
阶段 8 没有改动 WIT、对象格式或核心运行语义。

## 覆盖与安全证据

- 本地：init/add/status/diff/branch/switch/commit/log/show、空/二进制/Unicode 文件、路径与符号链接策略、
  规范化对象与独立 SHA-256 向量、损坏识别、DAG、Ref CAS。
- Diff：三组快照、路径筛选、新增/修改/删除、二进制和末尾换行；40 对内容的真实 CLI hunk 重建、
  只读文件/metadata/锁清单、Partial Clone 缺失祖先/缓存、损坏和类型检查、并发 index/Ref 屏障、预算回退与终端转义。
  新增 8 项 native 和 20 项 CLI，子案例不重复计数；[契约](docs/DIFF.md)与[运行记录](docs/DIFF_VALIDATION.md)。
- Branch/Switch：新增 8 项 native 和 38 项真实 CLI；创建不覆盖、只读计划、脏 index/工作区、
  未跟踪碰撞、非根空 Tree 拒绝/空根快照支持、目标完整性、no-replace、旧 inode/硬链接保留、
  add 锁屏障、pending 的 Core/CLI 门禁、prepared/backup/index/HEAD 后 SIGKILL 和同步 EIO。
  [先行契约](BRANCH_SWITCH.md)与[含失败和修复的记录](docs/BRANCH_SWITCH_VALIDATION.md)；不是自动恢复或掉电证明。
  收尾另加帮助成本提示与 [人工恢复演练](docs/SWITCH_MANUAL_RECOVERY.md) 2 项，并接入完整回归。
  独立演练可用 `python3 tests/switch_recovery_drill.py --output-dir target/recovery-exercise-01` 重现；
  目录必须不存在，保留全部现场，不接受真实仓库，不把内部子检查重复计数。
- 策略：真实 Pass/Reject/Error、Stage 快照、无法用内部 Mock Pass 绕过 required gate、
  多插件顺序/Warning、完整模拟值不出现在诊断。
- Wasm：恶意无限循环、独立 epoch 超时、初始化循环、memory growth、Trap、非法返回、
  超量输出/日志、输入限制、Manifest/摘要/ABI/权限不匹配、空 Linker。
- Lazy：Local/PromisedRemote/Unknown、合法来源、哈希/type 校验、原子缓存、并发合并、
  重读无传输、缓存离线可用与未缓存离线错误。
- Remote：错误图/哈希、服务器 required policy、绕过客户端、并发 CAS、配置变更、
  全可达线性历史扫描、私有 Quarantine 和失败清理。
- 独立审计包括 167 个恶意协议输入；这是一个测试内部的子案例，不膨胀测试数。
- 恶意 HOME/SSH、网络或秘密资源用模拟路径/fixture，不访问用户真实凭据。

详细安全结论见 [SECURITY.md](SECURITY.md) 与 [阶段 7 审计](docs/PHASE7_SECURITY_AUDIT.md)。
这些测试不是形式化证明、CVE 扫描或生产多租户认证。

### 并发与持久性测试的边界

本轮用读取屏障稳定复现旧版两个 add 均成功却丢失一方修改，并加入完整事务锁。
4 个跨进程回归与 native 取消回归验证当前协作写入者；不是同账户磁盘权限边界。
7 个恢复检查覆盖 index 发布前后 SIGKILL、Quarantine lease、未知资源保留、目录 sync 和 index/Ref 发布后 EIO；
临时仓库验证精确遗留路径保留后的正常 add/receive 重试，不提供自动恢复命令。
对象/元数据/Ref 关键目录同步已加入；恢复日志、自动重放、GC 和真实掉电验证仍缺失。
进程终止不是掉电证明。详情见 [执行记录](docs/ROADMAP_PROGRESS.md) 与 [恢复边界](docs/RECOVERY.md)。

### 安全测试不能推出的额外保证

guest memory growth 拒绝测试不证明 Host/JIT 总内存或总 RSS 已受限；
Manifest/digest/pin 校验测试不证明作者身份、发布来源或签名已验证。
恶意诊断权限/大小测试只证明输出经过相应检查，不证明允许的诊断内容不泄漏数据。
脱敏断言针对提供的 Scanner 与无害 fixture；同时有读取和诊断权限的任意恶意插件仍可回显内容。
总进程内存限制、签名验证、通用敏感内容脱敏均未实现，不能从现有测试中推导为已通过。

## 干净源码重建与统一验证

~~~bash
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/verify.sh --clean-build --benchmark
~~~

阶段 7 的该完整命令实际退出 0，记录五个阶段：regression、environment、repeat-smoke、
clean-build、benchmark。报告保留在 target/reports/phase7-verify.json。
阶段 8 再次运行的是扩展后的完整 test.sh 与最终演示；
没有把阶段 7 的 100/1000/10000 基准冒充阶段 8 重新测量。

clean-build 在临时源码副本中排除项目构建产物/依赖目录，复用现有工具链和缓存，
Cargo 使用 offline；不是无网络空白 OS 安装器验证。
[源代码重建脚本](scripts/clean-build.sh) · [历史完整结果](docs/PHASE7_VALIDATION.md)

第一轮另已通过 scripts/fresh-install.py 的独立 OCI rootfs 安装：不挂载宿主工具或 registry 缓存，
完整 134 项回归与四个真实 Demo 均退出 0。安装中的失败和修复保留，重试只复用隔离环境自己取得的依赖，
不是首遍无错声明。共享内核，不等于物理机器/VM 或跨平台安装。[安装过程与边界](docs/ROADMAP_PROGRESS.md)
第二轮的 146 项本机结果保留为历史。后续实际安装暴露 Registry 401，修复有界续期并增加 3 项回归后，
宿主完整 149 项通过；全新 fresh-03 rootfs 的工具准备、完整 149 项及独立四场景也实际全部退出 0。
旧的 134 项报告和失败 fresh-02 不改写为新成功。[失败、修复和本轮实际记录](docs/FRESH_INSTALL_VALIDATION.md)
固定版本 compiler/core 已实际下载并核对原摘要，本地 CAS 模式验证通过，但不等于新完整安装验收。
以上冷安装对应增加 diff 前的源码；225 项本机收尾与后续源码解包复现不扩大为新源码的冷安装或工具归档备份验收。

## 性能数据怎么解释

正式原始数据：target/reports/phase7-benchmark.json；方法、全表与环境：
[docs/BENCHMARKS.md](docs/BENCHMARKS.md)。

每档 100/1000/10000 个对象，均 20 次实际策略提交、3 个新仓库样本；
快照分别是 3/48/498 个文件。初始 clone 实测只取 5/50/500 个对象，
编码字节为 540/5445/54495。不是 10000 文件快照，也不是远端 push 规模测试。

Host 耗时包含进程/JIT/绑定/验证，不是纯 Wasm CPU 时间。
本地文件系统测试没有网络吞吐结论；没有与 Git 做性能比较。
10000 对象档的同一宽 Tree 缓存命中中位 2165.92 ms，慢于首次 Fetch 的 1856.86 ms，
且重复读无新增传输：传输避免与读取加速是不同结论，后者尚不成立。
本轮 Callgrind/逻辑 IO 证据进一步观察到同一来源 Tree 被读取 499 次；这是指令归因，
不是实际 CPU 时间占比，也没有将全部实际时延确定归因于单一路径。[方法与产物](docs/ROADMAP_PROGRESS.md)
第二轮请求内索引复用已将配对宽 Tree 缓存读取中位 2093.86 ms 降为 961.39 ms，逻辑读取 499 → 1 次；
promise 读取仍为 998。3 组、每组 3 次 hit，不是原三档基准重跑或通用加速承诺。[完整配对证据](docs/ROUND2_VALIDATION.md)
这些数字是独立 CLI 全流程计时，不是单次磁盘操作或纯 ObjectStore.get 耗时。
n=3 不支持 p99、SLA 或工业性能宣传。
服务器 4096 对象图 / 128 Commit 上限不因本地基准改变。
计数范围是候选目标的完整可达图，包括服务器已有祖先；单 Ref、线性 fast-forward/新分支的限制仍在。
每次扫描全部可达 Commit 的完整快照，没有审批结果复用；历史增长会增加工作量。
目前没有接收端随历史长度/快照大小/策略数量增长的性能曲线，不能从本地基准或功能测试推出该结论。

## 报告与失败如何保留

| 文件/目录 | 含义 |
|---|---|
| target/reports/phase7-verify.json | 阶段 7 五阶段状态；含此前完整运行，不是空白安装证明 |
| target/reports/phase7-clean-build.{json,log} | 源码隔离重建记录 |
| target/reports/phase7-benchmark.{json,log} | 正式 9 个性能样本及原始操作 |
| target/reports/phase8-regression.log | 阶段 8 扩展统一入口的实际终端记录 |
| target/reports/phase8-smoke.log | 最新双轮四场景 smoke |
| target/reports/phase8-prepare-*/ | 历史准备命令与真实对象统计 |
| target/reports/phase8-run-*/ | 每次演示 result.json / terminal.txt |
| target/reports/phase8-recording.*/ | 实际 PTY 流与回放时序 |
| target/reports/roadmap-regression-portable.log | 第一轮 134 项独立测试及全部 CLI/演示 smoke |
| target/reports/round2-regression-final.log | 最终版本实际重跑的 146 项完整回归及 CLI/演示 smoke |
| target/reports/fresh03-host-regression.log | 增加 3 项 Registry 续期回归后的 149 项本机完整测试，退出 0 |
| target/reports/diff-regression-final.log | 新增 diff 后 177 项本机完整回归及 CLI/演示 smoke |
| target/reports/branch-switch-baseline.log | 本轮修改前 177 项完整基线，退出 0 |
| target/reports/branch-switch-regression.log | 真实失败：构建中更新断言与旧 CLI 不同步，2 项恢复观察断言失败，退出 1 |
| target/reports/branch-switch-regression-final.log | 修复观察字段后 222 项通过；空 Tree 收尾修复前的快照 |
| target/reports/branch-switch-empty-tree-before.log | 真实失败：原 switch 将非根空 Tree 误解释为文件删除；原字节在备份，需修复预检语义 |
| target/reports/branch-switch-closure-regression.log | 此前实现轮 223 项完整回归、38 项 branch/switch 及全部 smoke，通过；不是后续收尾版本 |
| target/reports/branch-switch-closure-source-sha256.txt | 最后冻结的关键实现/测试/脚本/WIT，不是整份发布包或签名 |
| target/reports/branch-switch-closeout.VpnM81/ | 收尾 225 项完整回归、40 项专项、最终源码/运行产物摘要、恢复演练首败与修正后成功记录 |
| target/reports/diff-cli-initial.log | 初版 20 项真实 CLI diff 回归 |
| target/roadmap-fresh-02/report.json | 本轮安装实际失败：第五层 HTTP 401，未进入工具/项目测试 |
| target/roadmap-fresh-03/report.json | 最终脚本 + 本地归档冷安装通过；149 项与独立四场景全退出 0，installation_verified=true |
| target/lazy-get-round2-compare-final/ | 最终冻结前后 CLI 的配对 raw samples、输出摘要与逻辑 IO；初稿记录另保留 |
| target/reports/lazy-get-round2-io-before.log | 修改前二进制未通过“同一 Tree 只读一次”的回归 |
| target/moonbit-archive-round2/archive-report.json | 两个固定版本归档实际下载及原摘要核对；不是作者签名 |
| target/reports/roadmap-staging-before.json | 旧二进制两个成功 add 的确定性丢失更新 |
| target/roadmap-profile-01/ | 指令、逻辑 IO 与冻结基线；不覆盖历史正式基准 |
| target/roadmap-fresh-01/report.json | 第一轮独立 rootfs 安装通过，134 项，保留原摘要；本轮新结果单列 fresh-03 |

target 默认被忽略；源码包不保证附带这些本机产物。
提交作品时用独立 evidence 包保存报告，运行路径/时间戳只属于当次记录。
[阶段 8 汇总](docs/PHASE8_DELIVERY.md) 给出实际使用的证据索引。

仍未验证：物理空白机器、完全离线 bootstrap、非 Linux 平台、长期 fuzz、依赖 advisory 数据库扫描、
掉电持久性、完整 Host RSS 限额、真实远程认证/TLS/权限分离。
查看 [已知问题](docs/KNOWN_LIMITATIONS.md) 和 [路线图](ROADMAP.md)。
