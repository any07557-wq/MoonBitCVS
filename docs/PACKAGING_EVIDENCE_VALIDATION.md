# CI 归档后的打包证据遗漏修复

日期：2026-10-20（Asia/Shanghai）。执行顺序：CI #2 成功 → 下载/校验/归档 → 修复打包。
CI #2 的 237 项仍只覆盖 `58bade3`；归档独立本地提交为 `79eed2d`。
本次不修改 MoonBit 核心、WIT、插件或 Mooncakes 已发布包，不重新发布或上传 Release。

## 真实重现与修复

旧脚本实跑生成 `target/releases/submission.A92MA2/`，包命令退出 0，
但独立检查发现证据包的 evidence/ci、evidence/mooncakes 成员数为 **0**，断言退出 1。
旧证据包 SHA-256：`b0ee34954581cabe369c787feb0d25945eb9fe4f48d81e4d07013eb1b1fa05be`。
新增 8 项测试在实现 helper 前均因模块缺失报错，旧 6 项通过；不把这 8 个脚手架错误冒称成 8 个不同产品漏洞。
补齐实现后专项 **14 项通过**，`bash -n` 和 diff 空白检查通过。

修复由三部分组成：

1. `evidence/SUBMISSION_MANIFEST.sha256` 明确批准 68 个文件；加清单自身共 69 个持久化成员。
2. 打包前逐一验证摘要、路径、普通文件及预算；不递归收集目录，不输出半份选择列表。
3. 复现器识别同样的受限命名空间，并验证带持久化记录的包的完整清单；保持旧 target-only 兼容。

原 ZIP/内部清单/历史报告均保持原字节。文件白名单不是隐私自动判断或发布者签名，
新记录仍需独立审核后明确纳入。具体预算与维护方法见 [SUBMISSION.md](SUBMISSION.md)。

## 验证包与另一目录重建

实现验证包：`target/releases/submission.bQDElz/`，不是更新旧包。

| 文件 | SHA-256 |
|---|---|
| MoonVCS-source.tar.gz | `9378fa984aec2159db97018a6c31c5f08e7eb1db14a55649dc6f9c67cc13d258` |
| MoonVCS-evidence.tar.gz | `b1b10f80dfb1489232e024cddccc9b0a7014f67ac034157461bdc620d0b812f9` |
| 持久化证据总清单 | `438fdb9fbecc437b3c62234773582a6e879505d4a46c97366b1180332083629d` |

实际执行：

~~~bash
RUSTUP_TOOLCHAIN=1.99.1 python3 scripts/reproduce-submission.py \
  --package-dir /home/user/MoonBit_Program/target/releases/submission.bQDElz \
  --workdir /home/user/MoonBit_Program/target/reproduction-ci2-packing-01 \
  --toolchain-dir /home/user/MoonBit_Program/.toolchains \
  --moon /home/user/.moon/bin/moon
~~~

实际结果：**passed，退出 0，245 项通过**。UTC 起止为
2026-10-20 05:42:57.420546 → 05:49:43.784401；environment 0.779 秒、regression 404.108 秒，均退出 0。
完整计数为 native 86 + Rust 26 + Wasm 19 + Python 114，10 组 Python 分别为
9、6、4、7、1、7、20、40、14、6，重复构建的第二批 Wasm 不重复计数。
双轮四场景演示通过，不加进 245；这里不是 verify.sh 的三阶段或额外两轮 receive 重跑。
证据包实际 298 个成员，其中新增持久化成员 **69 个**，集合、摘要及每个成员字节与仓库一致。
220 份冻结源文件在构建前后不变；其中 166 份实现/配置/测试/示例在本次结果文档补写后，
仍逐份匹配当前工作区，防止测试旧实现后修改代码。

机器绑定结果见 [PACKAGING_EVIDENCE_VALIDATION.json](PACKAGING_EVIDENCE_VALIDATION.json)。
包旁已另存 REPRODUCTION.json、源清单、环境、原始回归日志及 REPRODUCTION.sha256，
没有改写两份原始 TAR 或旧 SHA256SUMS。
这是复用已安装工具与全局依赖缓存的独立项目构建，不是新 rootfs、空工具环境、
整体离线保证或新 GitHub CI。Cargo offline 不代表 Moon 不能联网。
实现验证包冻结在本报告及后续结果文档补写前；不把它称作包含最终文档的最终参赛源码包。

旧包、实际遗漏断言、专项前后日志、命令和报告保留于
`target/reports/ci-second-closeout.09gewu/`；重建目录失败也保留，不覆盖旧结果。
后续文档若更新，最终参赛交付仍应重新冻结源码/证据并绑定对应复现报告。

## 收尾范围

本次本地实测 14 项打包专项和 6 项 CI 防护也单独通过，不与完整 245 项重复相加。
新增 68 项文件白名单的全部摘要、CI #2 附件内部清单及已发布核心库原 ZIP 均已复核。
CI #2 的证据归档先行提交为 `79eed2d`；本次实现修复另作独立本地提交，不凑空提交。
没有自动推送或生成新 GitHub CI 结果，也没有上传 Release、改动库版本或重新发布。
后续同步修复后仍需检查那个新提交的 CI；最终材料与源码包的冻结是下一项独立交付工作。
