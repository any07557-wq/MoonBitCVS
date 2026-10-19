# 最终验收：宣传与可验证证据

以下“是”只表示表内明确范围，不表示生产级安全或所有平台支持。
实际运行摘要、具体产物与日期见 [阶段 8 记录](PHASE8_DELIVERY.md)。

优先风险：原始功能愿景尚未全部完成。“八阶段完成”仅指当前收敛后的原型范围验证与交付。
diff 已补齐有界、只读的工作区/暂存区/HEAD 比较，见 [diff 验证](DIFF_VALIDATION.md)。
最小 branch 与已有本地分支的保守 switch 已实现，见 [先行契约](../BRANCH_SWITCH.md)与[验证](BRANCH_SWITCH_VALIDATION.md)。
merge、通用 checkout 和 Git 协议仍未实现；switch 不支持 dirty/force/自动回滚或任意版本。
下列测试结论不涵盖这些未实现功能。

下表 149 项隔离安装是增加 diff 之前的源码快照，不自动覆盖新功能的全新安装或最终打包。

| 最终问题 | 结论 | 可检查证据与边界 |
|---|---|---|
| 是否真的用 MoonBit 实现核心能力？ | 是 | vcs 的模型、编码、存储、提交、Policy Engine、Lazy/Receive/Diff/Branch/Switch；86 项 native 测试；Rust 不是 VCS Core。 |
| 是否真的运行 MoonBit 编译的 Wasm Plugin？ | 是 | 五个 MoonBit 组件实际构建/校验；19 项插件测试；最终演示真实调用 Wasmtime；Scanner/License 不是 Mock。 |
| 是否真的存在权限隔离？ | 是，限已实现边界 | 显式能力交集、过滤输入、真实 CapabilityDenied、无 imports/空 Linker、资源预算；不是 OS 级多租户隔离。未实现的 repository.secrets.read 在实例化前拒绝，不伪称回调拒绝。 |
| 是否真的可以拒绝提交？ | 是 | Scanner Reject 时 HEAD/index 不变且不写 Commit；修复且重新 add 后成功；Required policy 错误默认拒绝。 |
| 是否真的可以按需获取历史？ | 是 | 40 提交真实演示：120 个远端对象，初始 3 个；旧 Commit Fetch 后缓存 6 个，重读零传输；哈希独立校验。 |
| 是否所有宣传都能通过代码或测试验证？ | 对本次限定后的已实现声明，有证据 | README/架构/安全/比较均区分已实现、历史实测、计划和未验证。没有“第一”“全面优于 Git”“生产安全”“纯客体执行更快”等无证据主张。未来工作不作完成承诺。 |
| 是否能在新环境中复现演示？ | 是，限独立 Linux/amd64 rootfs | 最终脚本 + 本地归档从新目录安装，149 项与独立四场景实际通过；不挂载宿主工具/registry。原 134 项与实际 401 失败分别保留，修复仅增加 3 项续期回归。共享内核/网络，非物理空白 OS、其他平台或完整离线证明。[当前证据](FRESH_INSTALL_VALIDATION.md) |

## 交付物清单

| 交付物 | 入口 |
|---|---|
| 开发者/评委 README | [README.md](../README.md) |
| 实际架构与四张图 | [ARCHITECTURE.md](../ARCHITECTURE.md)、[diagrams](diagrams/) |
| 安全边界与威胁模型 | [SECURITY.md](../SECURITY.md)、[THREAT_MODEL.md](THREAT_MODEL.md) |
| 未来计划 | [ROADMAP.md](../ROADMAP.md) |
| 现场演示与终端录制 | [DEMO.md](../DEMO.md)、[record-demo.sh](../scripts/record-demo.sh) |
| 测试/安装 | [TESTING.md](../TESTING.md)、[INSTALL.md](../INSTALL.md) |
| 许可证 | [LICENSE](../LICENSE)，保留既有 Apache-2.0 授权声明 |
| MoonBit Core / 插件源码 | [vcs](../vcs/)、[plugins](../plugins/) |
| Host / WIT | [host](../host/)、[policy.wit](../wit/policy.wit) |
| 构建、测试、示例 | [scripts](../scripts/)、[tests](../tests/)、[examples](../examples/) |
| 竞争差异与技术摘要 | [COMPARISON.md](COMPARISON.md)、[HACKATHON.md](HACKATHON.md) |
| 本地源码/证据包 | [SUBMISSION.md](SUBMISSION.md)、[package-submission.sh](../scripts/package-submission.sh) |

## 不能从这些证据推出什么

- SHA-256 提供完整性假设，不提供作者/服务器身份认证，也未证明不存在碰撞。
  插件摘要和名称/版本 pin 只绑定所批准的组件字节，不验证作者、发布者或签名，也不证明代码无恶意。
- 无 imports 不等于消除 Wasmtime/JIT/OS 漏洞；guest 线性内存预算不覆盖 Host/JIT 总内存或总 RSS，
  当前没有 OS 级总进程内存限额。
- Secret Scanner 的模拟规则不保证发现所有凭据。恶意插件若获准 staged_content.read 与 diagnostic.emit，
  仍可能在大小合规的诊断里回显获准内容；输出有界、JSON/显示转义不等于保密。
  Host 没有通用敏感内容脱敏机制；Scanner 的脱敏测试不代表任意插件的输出安全。
- 远端仅是本地文件系统/stdio 原型，没有认证、ACL、TLS 或服务端 OS 权限分离。
  独立 receive 进程不能阻止同账户直接修改服务器对象、Ref、策略或运行文件；
  绕过客户端扫描的测试只证明 receive 入口会重新验证，不证明能抵抗入口外的文件篡改。
- 10000 对象本地性能样本不等于支持同规模 receive，不等于工业性能优势。
  接收端只支持单 Ref、线性 fast-forward/新分支；4096 图对象、128 Commit 上限计入候选目标全部可达历史，
  包括服务器已有祖先，而非仅新增上传，也不是仓库全局对象数上限。
  每次仍重扫全部可达 Commit 的完整快照，没有审批复用；这些上限不是时延/吞吐量保证。
- 零新增传输不证明缓存读取更快。历史 10000 对象、498 文件快照基准中，同一 Tree 的缓存读取
  中位 2165.92 ms，首次读取 1856.86 ms。第二轮请求内优化已使独立配对缓存读取 2093.86 → 961.39 ms，
  Tree 读取 499 → 1；仍约 1 秒，不是原三档基准重跑。不能将历史指令比例当作 CPU 时间比例或关闭所有性能风险。
- 当前协作的 add 读改写已用事务锁修复；对象/元数据/Ref 关键目录同步也已加入，
  但仍没有恢复日志、自动重放或 GC。进程死亡可能残留排他锁文件、临时对象或 Quarantine。
  新增 SIGKILL/EIO 和只读 recover --check 不等于真实掉电恢复，也不能据此批量删除残留文件。
- 终端录制是真实运行记录，不等于在另一台全新机器实时运行；SVG 是架构示意，不是假造截图。
