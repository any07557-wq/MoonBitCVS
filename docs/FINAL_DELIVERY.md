# 最终工程交付：冻结契约与验收入口

本页是工程交付包的冻结输入，不是预填的通过报告，也不是本人申报书。
本轮范围为 MoonVCS 原型源码、最终工程文档、经审核的历史/CI/Mooncakes 证据，以及
从确切归档重建后产生的包旁复现报告。正式报名、本人申报书、审核与领奖材料不由本流程代办。

## 版本与证据边界

- 实现基线为 `b361ed475dc0a6699d7116c405f0a79051a59f9a`，测试入口 245 项。
- 新 GitHub CI 的完整提交、运行链接、附件与结果见 [CI_VALIDATION.md](CI_VALIDATION.md)，
  不把旧运行或本地测试结果改绑新提交。
- 冻结前补齐本轮 CI 证据并更新精确 `evidence/SUBMISSION_MANIFEST.sha256`，
  原 ZIP、历史报告和内部摘要不改写。相邻新文件不会自动获得入包资格。
- 最终文档与证据索引单独形成真实本地冻结提交；其完整 SHA 写在包旁 FREEZE.json。
  源包不内嵌自己的 TAR 摘要、冻结提交 SHA 或尚未发生的复现结论，避免自引用。
- 文档冻结后不再为补写成功结果而修改这些源文件。后续实际结果只写在包旁，
  若修改任何冻结输入，就应创建新包、新摘要及新复现结果，不能覆盖旧包。

## 工程包组成

| 文件 | 用途 |
|---|---|
| MoonVCS-source.tar.gz | 全部选定源码、WIT、脚本、测试、示例和定稿工程文档，无旧构建产物 |
| MoonVCS-evidence.tar.gz | 受限白名单选择的历史报告与 CI/Mooncakes 证据，与源码分开解包 |
| SHA256SUMS | 上述两个不可变归档的实际摘要；不包含后生成的报告 |
| FREEZE.json | Git 冻结提交、被测实现基线、归档摘要与输入文件身份；不声称测试已通过 |
| INPUT_MANIFEST.json | 两份归档的逐文件摘要及源文件对应 Git blob，用于核对确切冻结输入 |
| REPRODUCTION.json / REPRODUCTION.md | 该确切归档的实际命令、阶段退出码和结论，须在执行后读取 |
| REPRODUCTION.sha256 | 包旁报告、环境与回归日志等复现证据的实际摘要 |
| FINAL_VALIDATION.json | 独立计数、源码前后/提交匹配、证据成员校验与未验证边界 |
| DELIVERY_SHA256SUMS | 工程包目录中归档、冻结信息和复现报告的整体传输校验清单，不包含自身 |

先检查 SHA256SUMS，再检查 REPRODUCTION.json：只有 status=passed、exit=0，
完整 regression 阶段实际退出 0，且 FINAL_VALIDATION.json 绑定同一源码/证据 TAR 摘要时，
才可称这个包的本机解包复现通过。没有报告、执行中、失败或摘要不一致都不能算通过。

构建命令、工具要求与分离解包位置详见 [SUBMISSION.md](SUBMISSION.md)。
这次使用已安装固定工具和全局依赖缓存；新的项目 source/host/target、vcs/_build 与临时目录独立生成。
它不是新 rootfs、空工具机器、完全离线分发、性能基准或生产安全验收。
工具链归档/长期备份仍按 [INSTALL.md](../INSTALL.md) 由操作者单独保留，工程包不夹带数 GiB 工具或 registry。

## 对外说明不得省略

- Mooncakes `any07557-wq/moonvcs@0.1.0` 仅为 native 核心库源码模块，
  不含完整 Rust Host、Wasm 插件、运行配置或预编译 CLI；完整系统须从工程源码构建。
- 已发布包版本与字节不在本轮改动范围；包内 README 保留冻结时历史措辞，最新状态见
  [Mooncakes 发布记录](MOONCAKES_RELEASE.md)。
- 远端仍为文件系统/stdio 原型，没有认证、ACL、TLS、OS 权限分离。
  Host/JIT 总内存、恢复/GC、缺失 VCS 命令与性能边界继续保留，见 [Known Limitations](KNOWN_LIMITATIONS.md)。
- 普通硬链接证据输入是尚待加固的打包边界；本次冻结前独立核对当前实际输入及归档，
  不以此声称打包器已实现通用硬链接防护。
- 本流程只生成本地包与本地提交，不自动 push、创建标签/Release、重复发布 Mooncakes 或提交赛事表单。

## 尚需本人完成的赛事材料

本人撰写并确认一页项目说明，说明已有基础、本期实质贡献、AI 辅助及可解释的技术选择；
再核对报名表/正式章程的格式、有效提交、团队与时间要求，见
[参赛清单](CONTEST_CLOSEOUT.md)。当前工程包不以自动生成正文冒充本人申报书。
Git 提交计数须读取真实历史，也不等于赛方认定的有效提交数量；不为空凑数、拆历史或伪造时间。

最终包的成功报告即使产生于本页冻结之后，也只能作为包外附件追加，
不会反向证明尚未完成的申报、正式验收或新 GitHub 提交已经通过。
