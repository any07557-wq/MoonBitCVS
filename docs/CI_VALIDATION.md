# CI 接入：本地验证记录

日期：2026-10-19，Asia/Shanghai。起点为本地 Git 导入提交 560408e。
维护者明确要求 **仅本地独立提交，暂不推送**；本轮没有 push、workflow_dispatch 或远端配置变更。

## 结论与未验证项

- 最终 workflow 的 actionlint 1.7.12 校验退出 0；只校验语法/表达式，不包含 ShellCheck/Pyflakes。
- CI 安装器使用原固定摘要的本地 CAS，在新前缀实际安装 MoonBit；版本查询与 core bundle 完成。
  Rust 1.99.1/rustfmt 已从官方分发源实际安装，公开 Mooncakes registry 初始化成功。
- 在第二个独立源码副本执行与 workflow 相同的 `./scripts/verify.sh`，**退出 0，237 项通过**；
  regression、environment、repeat-smoke 三阶段全为 0，含双轮四场景与额外两次 receive smoke。
- **GitHub-hosted ubuntu-24.04 上的完整安装、运行及 artifact 上传仍未验证。**
  不能将本机 WSL2 结果写成 GitHub CI 已跑通，也没有新 rootfs/当前版本冷安装结果。

本地复用全局 Cargo 依赖缓存与已有 wit-bindgen/wasm-tools，Rust Cargo 设为 offline；
MoonBit 来自校验后的本地归档，而不是本轮重新下载官方 URL。
workflow 则在新 runner 下载固定 MoonBit、安装 Rust/Wasm 工具并初始化 registry；网络可用性和平台差异仍要在首次推送后确认。

## 实际失败、修复与重跑

本轮原始文件保留于 `target/reports/ci-setup.RXW29u/`；旧 rootfs、交付与阶段 7 历史日志未覆盖。

| 步骤 | 实际结果 | 原始文件 |
|---|---|---|
| 初稿 actionlint | **退出 1**；jobs.verify.env 不能使用 runner.temp context | actionlint-before.log |
| 加入重现断言的 CI 专项 | **退出 1**；6 项中 1 项失败，重现同一初稿问题 | ci-audit-before.log |
| 用 RUNNER_TEMP 写 GITHUB_ENV 后 | actionlint 退出 0；6 项专项通过 | actionlint-final.log、ci-audit-final.log |
| MoonBit 私有前缀安装 | 退出 0，长度与原 SHA-256 均核对；仅 installed_not_tested，不把安装等同完整测试 | moon-install-local.json、moon-install-local.log |
| 版本与 core bundle | 退出 0；moon 0.1.20261012、moonc 0.10.15+943464bfa | moon-bundles-local.log |
| 首次 registry 初始化 | 退出 0，索引与 symbols 准备成功 | registry-local.log |
| 首次完整验证 | **退出 1**；仅有 stable 命名缓存，数值版本 1.99.1 需要下载，该次受限进程无法联网；随后阶段未运行 | verify-local.log、verify-run.txt、verify-before.json、regression-before.log |
| 按 workflow 命令补齐数值 Rust 版本 | 退出 0，官方 1.99.1 与 rustfmt 安装完成；未修改全局默认 | rust-pin-install.log |
| 新副本 registry 与完整重跑 | registry 退出 0；完整 verify 退出 0、237 项及演示通过 | registry-local-final.log、verify-local-final.log、verify-final.json、verify-run-final.txt |

workflow 本来就包含 Rust 安装步骤；首次本地失败是准备不完整，不通过删除数值版本约束规避。
两个源码副本、初稿错误、失败报告与最终结果均保留，重跑不覆盖失败。
6 项专项独立重跑、单个测试内的多个 fixture、重复组件构建与演示不重复计数。

## 最终执行与版本绑定

源码副本：`target/ci-local.20TEy4/source/`；没有复制旧项目 target/_build/.mooncakes。
通过 `.toolchains` 链接复用已安装 Rust 工具与全局 registry 缓存，Cargo target 固定为新副本 host/target。
先执行 `moon -C <source>/vcs update`，再从该副本执行：

~~~bash
MOON_HOME=/home/user/MoonBit_Program/target/reports/ci-setup.RXW29u/moon \
MOONVCS_MOON=/home/user/MoonBit_Program/target/reports/ci-setup.RXW29u/moon/bin/moon \
RUSTUP_TOOLCHAIN=1.99.1 CARGO_BUILD_JOBS=2 CARGO_NET_OFFLINE=true \
CARGO_TARGET_DIR=/home/user/MoonBit_Program/target/ci-local.20TEy4/source/host/target \
./scripts/verify.sh
~~~

最终实际 UTC 起止：2026-10-19T10:45:23Z → 10:52:06Z（北京时间 18:45:23 → 18:52:06），403 秒。
regression 394 秒、environment 0 秒（整秒计数）、repeat-smoke 9 秒。这是执行记录，不是新性能基准。
benchmark 与额外 clean-build 参数没有请求；普通 CI 验证不冒充三档基准或独立 rootfs。

237 = 86 native + 26 Rust + 19 Wasm + 9 系统 + 6 验证脚本 + 4 暂存并发 + 7 恢复 +
1 Lazy 逻辑 IO + 7 工具归档/Registry + 20 diff + 40 branch/switch + 6 交付 + 6 CI。
计数从原始 regression-final.log 断言并去重，另存 test-counts.json。

| 对象 | SHA-256 |
|---|---|
| .github/workflows/ci.yml | 28f8007badb8ed56fa1377be00591b67dd59652cb8e5105983ace71dacdc3efa |
| 固定的 163 项代码/配置/测试/工作流清单 tested-source.sha256 | 189b61b6398bf925a2cc611597ff23973e4a7b1a783df9453b53f37f763fc71b |
| 最终 regression-final.log | 37d4d89c7cd6e78df23cd50117ef07559f7e452f37d0829128e2b10057a0e876 |
| 独立副本的新 CLI | 6a8242e3c66e4ddf240a393b7e80b6cc0b1bdd1b3d7959406f56f08a6b15fc30 |

代码清单包含 .github/scripts/tests/vcs/host/plugins/wit/examples 和 BRANCH_SWITCH.md，
不包含工具/构建/缓存目录。原工作区与被测试副本的清单均核对通过，source-check.log 与 copied-source-check.log 保留。
结果文档在运行后补写，未修改被冻结的可执行代码；最终 Git 独立提交另含这些叙述文档，不声称文档也做过编译。

actionlint 来自官方 v1.7.12 linux_amd64 归档，运行前核对公开摘要
`8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8`；未做 attestation/作者签名验证。

## 后续核对与原型边界

~~~bash
sha256sum -c target/reports/ci-setup.RXW29u/tested-source.sha256
sha256sum -c target/reports/ci-setup.RXW29u/evidence.sha256
~~~

target 日志是被 Git 忽略的本机产物，不会随本轮提交自动上传。
将来维护者推送此提交并获得 GitHub 的实际完整成功后，才能更新“GitHub CI 已通过”的状态。
本轮没有发布 Mooncakes、Release、申报书、改变分支保护或更新旧交付归档。
225/231 项与历史 149 项安装结果保持各自版本边界；认证/ACL/TLS/OS 权限分离、Host/JIT 总内存、
GC/自动恢复、Partial Clone inspection 来源依赖等原有限制均未解决，也没有清理任何恢复来源。
