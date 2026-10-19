# GitHub Actions：检查、构建与完整验证

配置：[.github/workflows/ci.yml](../.github/workflows/ci.yml)，名称 MoonVCS CI。
**配置存在不等于 GitHub 已通过。** 接入时按维护者要求仅本地提交，不推送；
后续已核对运行 #1 为 success，并将维护者下载的原始附件归档：ZIP 摘要匹配，237 项通过，三阶段退出码均为 0。
实际运行链接、提交、到期时间及历史本地结果见 [CI_VALIDATION.md](CI_VALIDATION.md)。

## 触发与范围

- push 到 main、面向 main 的 pull_request，以及 workflow_dispatch 手动触发。
- 单个 GitHub-hosted ubuntu-24.04 job，60 分钟上限；同一 ref 的新运行取消旧运行。
- 固定 MoonBit compiler/core：复用 scripts/moonbit-archives.lock.json 中的版本 URL、长度和 SHA-256。
  scripts/ci_install_moon.py 先校验两份归档，再安装到新的私有前缀；拒绝覆盖，不回退 latest。
- 固定 Rust 1.99.1 + rustfmt、wit-bindgen-cli 0.63.0、wasm-tools 1.262.0；两个 Cargo 工具均 --locked 安装。
- 显式生成 core bundles，并执行 moon -C vcs update 初始化新 runner 的 Mooncakes registry。
- 运行现有 scripts/verify.sh：regression（scripts/test.sh，含 fmt/check/build）、environment、
  repeat-smoke（两次 receive）；完整测试已包含双轮四场景演示。新 CI 6 项防护加入后入口共 237 项。

依赖服务、固定归档或 registry 不可用会失败，不通过删 pin、替换版本或跳过测试使状态变绿。
第一版不启用 CI 缓存，避免用缓存命中掩盖准备步骤；这不是完全锁定 OS/系统包的可重现镜像。
runner 自带 rustup/系统环境，APT 安装 C/Python 等依赖；不称为空白 OS、独立 rootfs 或全离线安装。

## 权限与证据

GITHUB_TOKEN 仅 contents:read，checkout 不持久化凭据，不使用 secrets、pull_request_target、
发布权限、PR 标题/正文拼接 shell 或 continue-on-error。两个官方 Action 固定完整 commit SHA：

- [actions/checkout v7.0.1](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1)
- [actions/upload-artifact v7.0.0](https://github.com/actions/upload-artifact/commit/bbbca2ddaa5d8feaa63e36b76fdaad77386f024f)

遵循 [GitHub 安全建议](https://docs.github.com/en/actions/reference/security/secure-use) 中的最小权限与 SHA 固定原则。
这不构成执行任意 PR 代码的 OS 沙箱或作者身份验证；fork PR 仍遵循 GitHub/仓库的运行审批策略。

成功/失败都会尝试上传选定 artifact，名称包含 run ID 和 attempt，保留 14 天：

    target/ci/*.json、*.log
    target/reports/phase7-verify.json
    target/reports/phase7-regression.log
    target/reports/phase7-environment.json、phase7-environment.log
    target/reports/phase7-repeat-smoke.log

不会上传整个 target、工具链、registry、对象库、恢复现场或用户配置。
checkout/准备阶段过早失败时报告可能不全，先看失败步骤的 job 日志；缺报告不能当通过。
artifact 不是长期备份、签名或当前 rootfs 安装验收。超时/取消也不能解释为已完成验证。
本次附件已另存 `evidence/ci/39241926009-attempt-1/`，不依赖 GitHub 的 14 天保留期；
原包、解包报告、核对记录及 SHA256SUMS 一并保存；截至本次归档核验时（2026-10-19 12:02:34 UTC）
尚未提交/推送或建立异地备份。后续另做了新增附件隐私检查并形成本地归档提交，不代表已推送。

## 公开验证结果与历史触发边界

接入时仅本地提交，没有代维护者推送或触发运行。后续公开运行已由 GitHub 记录，见
[本次 MoonVCS CI #1](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39241926009)。
本次只核验并本地归档证据，没有推送或触发新运行。
只有完整 job 实际成功才可以宣称 GitHub CI 跑通；不从本地测试或 YAML 解析结果推断。

本轮不自动推送、修改分支保护、上传 Release、发布 Mooncakes 或代写个人申报书。
维护者已确认 Mooncakes 用户名 `any07557-wq`；本地候选包与后续认证/发布边界见 [MOONCAKES.md](MOONCAKES.md)，尚未发布。

## 本地复核

~~~bash
python3 tests/ci_audit.py
# 可选，固定 actionlint 版本并先核对下载摘要
actionlint -shellcheck= -pyflakes= .github/workflows/ci.yml
# 已准备固定工具和 registry 时，统一入口
MOONVCS_MOON=/actual/path/to/moon ./scripts/verify.sh
~~~

verify.sh 会写入 target/reports/phase7-*；保留旧验收的工作区应在独立源码副本中执行，
不能覆盖旧日志后宣称旧版本已重新通过。本轮本地验证采用单独副本和单独原始日志。

安装器可使用已独立保留的归档做本地验证：

~~~bash
python3 scripts/ci_install_moon.py --directory /new/parent/moon \
  --report /new/report.json --archive-dir /path/to/operator-cas
~~~

前缀和报告均须不存在；仅 installed_not_tested，不运行 Rust 安装/registry/完整测试，不宣称 GitHub 或冷安装通过。
GitHub workflow 不传 archive-dir，使用原锁文件的官方固定 URL。升级工具应重新验证组件摘要与完整测试，不能静默 repin。
