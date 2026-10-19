# Mooncakes 0.1.0：冻结、验证与发布记录

本文件在执行发布前建立；初始状态为 **冻结候选、待完整验证，尚未发布**。
维护者于 2026-10-19 明确授权：本地独立提交候选源码；约定验证、内容/摘要/身份/版本检查全部通过后，
公开发布已记录的 `any07557-wq/moonvcs@0.1.0`，随后由新 consumer 从 registry 下载验证。
禁止擅自改版本、替换内容、推送 GitHub、上传 Release 或泄露凭据。

## 不可变候选与交付范围

- 原 ZIP 保留为 [`evidence/mooncakes/0.1.0/any07557-wq-moonvcs-0.1.0.zip`](../evidence/mooncakes/0.1.0/any07557-wq-moonvcs-0.1.0.zip)。
- SHA-256：`5006035f75de4f963213a92257bafa3a5d2f751bb117c803c49d9c09f21867d3`。
- 33 个文件，75,212 字节，解压内容合计 265,964 字节；逐文件摘要见
  [ARCHIVE_MEMBERS.sha256](../evidence/mooncakes/0.1.0/ARCHIVE_MEMBERS.sha256)，冻结说明见
  [CANDIDATE.json](../evidence/mooncakes/0.1.0/CANDIDATE.json)。
- 本次仅发布 **原生核心库源码模块**。其中有 native CLI 源码，但没有完整 Rust Host、
  Wasm 插件、WIT、运行配置或预编译 CLI；依赖安装不等于安装完整 MoonVCS。
- 不为更新发布措辞而修改冻结包中的 README；包内“尚未发布”属于冻结时状态，
  后续实际发布结论只记录在包外，不静默替换同一 0.1.0 内容。

发布前新增包检查覆盖全部 33 个 UTF-8 成员，核对大小、CRC、路径、文件类型、源码字节及摘要。
凭据规则扫描唯一命中 `policy_integration_wbtest.mbt:164`，是明确的 harmless 测试输入；
未发现扫描规则覆盖的 GitHub/cloud token、私钥正文、认证头或个人 Windows 下载路径。
保留无害测试源码，不改获授权内容；这不是完整 DLP 或“绝无敏感信息”的证明。

## 验证和发布门禁

先创建独立本地源码提交；从该提交导出不含旧构建产物的干净副本，使用已安装固定工具和缓存，
运行 `scripts/verify.sh` 的 regression、environment、repeat-smoke，核对完整测试计数与所有退出码。
这不是新 GitHub Actions 运行、冷安装或新性能基准；历史 GitHub 237 项结果仍绑定原提交。
再核对冻结包、提交中源码、最终实际待发布 ZIP 一致，检查当前账号、服务端 dry-run 与版本不存在。

已知固定工具问题：服务端 dry-run 返回 202 成功时 CLI 仍可能退出 255；
不能单凭 CLI 退出码断言发布状态，也不将非零 CLI 结果改写成 0。
真实发布只执行一次；若响应与 CLI 状态不一致，先只读查询 registry 版本和包内容，不盲目重试。
发布后新 consumer 不使用 moon.work、本地模块 override 或本地候选 ZIP 作为依赖来源，
必须从 registry 下载指定版本，核对下载内容/摘要并实际编译、运行 README 导入示例。

执行日志使用独立目录 `target/reports/mooncakes-release.4J7nF4/`；
完整结果及实际发布状态在执行后补记，不提前声称通过。
