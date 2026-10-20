# Mooncakes 0.1.0：冻结、验证与发布记录

当前状态（2026-10-20，Asia/Shanghai）：**0.1.0 已正式发布，新 registry consumer 验收通过**。
正式发布发生在北京时间 **2026-10-19 21:19:34**，不是本次续办日期。
本文件在执行发布前建立，初始的“冻结候选、待验证、尚未发布”状态已由下列实际结果更新。
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

## 最终源码与完整验证

独立本地源码提交：`d5d824211b06b276323dc5c8c27914b76e08ff15`
（`release: 冻结 Mooncakes 原生核心库 0.1.0 候选包`）。
从该提交执行 `git archive`，导出到独立目录；开始时没有 target、host/target、vcs/_build 或 vcs/.mooncakes，
重新构建 Host、组件与 CLI，复用已安装的固定工具链和全局依赖缓存。
导出 TAR SHA-256：`801f02700f40d945ef21140dedb74f494e648fd11c7ea740e94c5e5743782d93`。
运行后逐一核对该提交全部 **235 个跟踪文件**与被测试副本的 Git blob 身份，全部一致。

实际命令（下列目录保留为本次历史位置；复现须用新目录，不覆盖旧日志）：

~~~bash
git archive d5d824211b06b276323dc5c8c27914b76e08ff15 \
  -o target/reports/mooncakes-release.4J7nF4/frozen-source.tar
# 将 TAR 解到该报告目录的 source/，复用已安装 .toolchains；随后在 source/ 执行：
MOONVCS_MOON=/home/user/.moon/bin/moon \
RUSTUP_TOOLCHAIN=1.99.1 CARGO_BUILD_JOBS=2 CARGO_NET_OFFLINE=true \
CARGO_TARGET_DIR=/home/user/MoonBit_Program/target/reports/mooncakes-release.4J7nF4/source/host/target \
./scripts/verify.sh
~~~

2026-10-19 13:09:55 UTC 开始，统一入口退出 **0**：

| 阶段 | 实测时间 | 退出码 |
|---|---:|---:|
| regression | 398 秒 | 0 |
| environment | 0 秒（脚本整数计时） | 0 |
| repeat-smoke | 8 秒 | 0 |

去重计数为 **237 项通过**：native 86 + Rust 26 + Wasm 19 + Python 106。
重复构建产生的第二批 Wasm 输出不再计数；双轮四场景演示和额外两轮 receive smoke 另列，不充入 237。
未请求 benchmark/clean-build 可选阶段；没有新 rootfs 冷安装，也没有推送或新 GitHub Actions 运行。
完整报告见 [project/phase7-verify.json](../evidence/mooncakes/0.1.0/results/project/phase7-verify.json)
与同目录原始回归、环境、repeat-smoke 日志。

## 发布前门禁与唯一一次正式发布

`moon whoami` 识别 `any07557-wq`，服务端 dry-run 接受该账号/模块/版本的候选；
最终只读版本查询为 404。404 不代表名称已预留，因此正式响应和发布后读回仍必须检查。

| 观察 | 实际结果 |
|---|---|
| 最终服务端 dry-run | HTTP **202**，明确成功且不变更；CLI **255**，如实保留兼容异常 |
| 发布前版本查询 | CLI 255 / 404 Not Found |
| 唯一正式 `moon publish` | CLI **0**；CLI 捕获的服务端响应 **200 OK**；未超时 |
| 发布后立即 `moon view … --json` | success；0.1.0、未撤回、checksum 匹配 |
| 次日新 consumer 后再次查询 | success；版本/摘要仍一致 |

正式命令是在 `/tmp/moonvcs-publish-order.AUkuwa/` 内执行：

~~~bash
moon publish --target-dir \
  /home/user/MoonBit_Program/target/reports/mooncakes-release.4J7nF4/publish-final-build
~~~

捕获器执行前以排他创建的 `PUBLISH_INVOCATION.json` 防止协调流程重复调用，
校验冻结 ZIP、源码、完整验证、最终 dry-run 与发布前版本查询。
原始认证命令输出只在内存中处理，落盘的是脱敏日志；200 是 CLI 所报告的响应，不是原始 HTTP 抓包。
详见 [publish-once.json](../evidence/mooncakes/0.1.0/results/publish-once.json)、
[publish-once.log](../evidence/mooncakes/0.1.0/results/publish-once.log) 和
[registry-after-first.json](../evidence/mooncakes/0.1.0/results/registry-after-first.json)。

### 被内容门禁拦下的两次打包结果

未隐藏失败，也没有替换获授权的 ZIP：

1. 在被忽略的 target 路径内解包后重打包，得到 22 字节、0 个成员的空 ZIP，SHA-256
   `8739c76e681f900923b900c9df0ef75cf421d39cabb54650c4b9ad19b6a76d85`。内容检查拒绝，未发布。
2. 移到 /tmp 后得到相同 33 份内容、但成员顺序不同的 ZIP，SHA-256
   `98b37a18bbe5e900142d504c87ff50d8738bf861482a1b715edc4b9a3465e5e9`。逐字节检查仍拒绝，未发布。
3. 在新的 /tmp 目录按反向创建次序还原文件，官方打包器重现原始成员顺序。
   最终打包、dry-run、真实 publish 生成的 ZIP 均与冻结包逐字节一致，摘要始终为 `5006035f…21867d3`。

这只是复现原包的目录枚举顺序，没有修改版本、源码、依赖或 ZIP 内容。
失败打包日志和摘要保留在 [results/](../evidence/mooncakes/0.1.0/results/)。

## 发布后：真实 registry 下载与新 consumer

发布成功后首轮下载审批因审批服务额度中断，**动作没有执行**，不是包下载失败或安全否决。
2026-10-20 续办只进行了下载、查询和验证，**没有再次发布**。

从官方公开下载地址取得 ZIP：

~~~bash
curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 \
  --output registry-downloaded.zip \
  https://download.mooncakes.io/user/any07557-wq/moonvcs/0.1.0.zip
sha256sum registry-downloaded.zip
cmp any07557-wq-moonvcs-0.1.0.zip registry-downloaded.zip
~~~

下载命令、cmp 均退出 0。直接下载 ZIP、Moon 自动下载的 registry 缓存 ZIP、冻结包三者完全相同；
registry index 的 checksum 一致，安装到 consumer 的 **全部 33 个文件**与包内逐文件摘要一致。

新 consumer 没有 moon.work 或本地 override，直接固定依赖 `any07557-wq/moonvcs@0.1.0`。
单独 MOON_HOME 起初无 registry、模块缓存或 credentials；仅链接已安装的 MoonBit bin 和标准库。
`moon whoami` 在该 home 中输出 `Not logged in`；公开依赖下载无需复用登录凭据。
实际记录包含四个模块的 Downloading 输出：moonvcs、sha256 0.18.0、async 0.20.2、base64 0.16.13。
这是空 registry 缓存验收，**不是空白 OS/工具链安装验收**。

~~~bash
export MOON_HOME=/home/user/MoonBit_Program/target/reports/mooncakes-release.4J7nF4/consumer-moon-home
moon -C registry-consumer update
moon -C registry-consumer check --target native --deny-warn
moon -C registry-consumer test --target native --deny-warn
moon -C registry-consumer run . --target native
~~~

四条命令均退出 **0**；2 项外部导入测试通过（空 Blob 已知向量、二进制 Blob 编解码）。
README 示例输出 `3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7`。
工具对 executable/main 包中的 `_test.mbt` 输出未来兼容性警告，check/test 日志原样保留；
不声称零警告，也未为消除警告而修改已发布模块。没有执行包中所有 white-box 集成测试；
这 2 项 consumer 测试不并入完整仓库 237 项。

复现用的 consumer 源码和命令日志见 [results/consumer/](../evidence/mooncakes/0.1.0/results/consumer/)。
复制该目录到仓库外新目录、不要复制 _build/.mooncakes，再执行上述命令；需 native C 工具与公开 registry 可用。

## 证据与剩余边界

机器结果：[RELEASE.json](../evidence/mooncakes/0.1.0/results/RELEASE.json)；
证据清单：[SHA256SUMS](../evidence/mooncakes/0.1.0/results/SHA256SUMS)；
保留范围：[证据说明](../evidence/mooncakes/0.1.0/results/README.md)。
新增附件单独做了凭据模式与上下文检查，不沿用旧 CI 附件的隐私结论；
没有保存凭据正文、Token 指纹或认证命令原始输出。模式扫描不是完整 DLP。
收尾链接检查首次先于 SHA256SUMS 生成而失败；保留该次记录，调整清单检查顺序后复核，未改发布包。

包内 README 的“Not published yet”是授权冻结时原文，故意不改。
当前实际状态以本记录、registry 元数据和包摘要为准。
公开入口：[Mooncakes 模块页](https://mooncakes.io/docs/any07557-wq/moonvcs)；
网页渲染不是本次证据来源，结论来自实际 CLI/下载/编译运行。

本次没有 GitHub push、Release、标签、工具链升级、性能评测或新 CI 运行。
认证/ACL/TLS/服务端 OS 权限分离、Host/JIT 总内存、恢复/GC 及缺失 VCS 命令的既有边界均未改变。
证据和后续文档在包外归档，不把文档收尾提交重新描述成已做完整回归或已推送。
