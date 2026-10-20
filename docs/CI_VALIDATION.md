# CI 验证记录

## 最新：597e260 的完整 CI #4 与独立消费验证已持久归档（2026-10-20）

两项远端运行都为 completed / success，官方运行页完整提交均为
**`597e260287f7c9b6937a1bb1fdcd53dbeae5021e`**；不是沿用本机或旧 CI 的结论。
维护者完成 main 同步并手动触发消费工作流；本轮只归档，不再次触发、推送或发布。

| 项目 | 完整源码 CI | 公开库独立消费 |
|---|---|---|
| 运行 | [MoonVCS CI #4](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39417969230) | [Published Mooncakes consumer](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39419237867) |
| 触发 | push / main，11:51:37 UTC | workflow_dispatch / main，12:02:09 UTC |
| 附件 ID | `12262777158` | `12262552042` |
| 原 ZIP 字节 | 34,898，8 份报告 | 9,416，21 份报告 |
| ZIP SHA-256 | `e51f354ed97692704b87ce55d4853c8e7b8f5ec20c4c2a27fda479d3f35edf64` | `36d7d4404328f91d596b11ad1deea4c7edeb2321777b84d6deec76497f3043f6` |
| 实际结果 | **264 项**：86 native + 26 Rust + 19 Wasm + 133 Python | 空 registry、匿名下载固定 **0.1.0**；**2 项测试 + README** 通过 |
| 范围 | 当前 Core、Host、Wasm、CLI、审计与演示 | 已发布 native 核心库；不等于完整工程或预编译 CLI 安装 |

完整 CI 的 regression / environment / repeat-smoke 均退出 0，分别记录 463 / 0 / 26 秒；
11 组 Python 为 `9,6,4,7,1,7,20,40,19,6,14`。重复构建的第二批 19 项 Wasm 不重复计数，
双轮四场景与额外 receive smoke 另列。消费的 2 项不并入 264。
消费报告的实际八条命令均退出 0，下载 75,212 字节、包摘要与冻结 0.1.0 相同，33 个安装文件一致。
环境报告的 Cargo.lock/WIT/moon.mod 摘要已与 `597e260` Git blob 核对；消费脚本摘要也匹配该提交。

原始 ZIP、原字节解包报告、官方网页语义元数据、摘要、原核验结果及新的隐私检查分别保存于：

- [完整 CI 归档](../evidence/ci/39417969230-attempt-1/)
- [消费验证归档](../evidence/ci/39419237867-attempt-1/)

GitHub 元数据来自官方公开 HTML 的运行/附件字段，不伪装成 REST API 原响应。
原附件通过公开 nightly.link 转发下载，先匹配独立观察的 GitHub 摘要再使用；
本次持久归档直接复制已经保留的原 ZIP，不重打包、不重复下载、不保存临时签名 URL。
新扫描覆盖全部 29 份文本成员及旁文件，未发现规则覆盖的凭据、私钥、签名 URL 或完整模拟密钥。
首次入包预检拒绝消费附件原始目录里的 `target` 路径组件；没有放宽白名单，
派生解包文件改存 `extracted/install/`、`extracted/consumer/`，原成员路径映射保存在 artifact-metadata.json。
原 ZIP 和所有成员字节不变，旧派生目录保留于本轮 target 报告目录，不作为成功入包证据。
保留 GitHub runner、Linux 自有工作区/临时路径及工具/对象摘要；不是完整 DLP 或作者签名验证。
工作流配置保留 14 天，未取得精确 expires_at；现在证据已不依赖 target/reports 或附件保留期。

```bash
(cd evidence/ci/39417969230-attempt-1 && sha256sum -c SHA256SUMS)
(cd evidence/ci/39419237867-attempt-1 && sha256sum -c SHA256SUMS)
```

安装器的 `installed_not_tested`、consumer 自身的 `github_actions_verified: false` 等原值保留：
脚本不独立认证 GitHub 状态，远端完成依据是官方运行记录与真实后续测试报告，不能篡改原报告来表示通过。
本次归档/冻结提交不是 `597e260`，其完整源码/文档/证据包是否复现成功，必须另看包旁新报告。
旧 `ec287d1` 包保留；没有新 rootfs、性能基准、重复 Mooncakes 发布或正式赛事提交。

## 历史：运行 #3 已核验归档（2026-10-20）

[MoonVCS CI #3 / attempt 1](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39378888384)
在完整提交 **`b361ed475dc0a6699d7116c405f0a79051a59f9a`** 上实际成功，覆盖本轮打包证据遗漏修复。
远端 main 已通过 git ls-remote 独立核对，触发为 push / main。
GitHub 公开运行页显示触发时间 2026-10-20 06:10:36 UTC（北京时间 14:10:36），
总耗时 13 分 42 秒，job 13 分 39 秒，唯一附件 ID `12245371256`。

| 项目 | 实际结果 |
|---|---|
| 原始附件 | moonvcs-ci-39378888384-1.zip，33,100 字节（网页显示 32.3 KB） |
| ZIP SHA-256 | `935d9312b2e6bddfa07262bbd555503d1731cc86ce3f115e8b01b5637a75d030`，与 GitHub 页面独立公布摘要一致 |
| 完整性 | 8 个 UTF-8 报告，147,613 字节；CRC、路径/类型/预算与成员字节均核对 |
| 测试 | **245 项通过**：86 native + 26 Rust + 19 Wasm + 114 Python |
| verify | 06:16:20 UTC 开始；regression 448 秒、environment 0 秒、repeat-smoke 25 秒，全部退出 0 |
| 演示 | 双轮四场景与额外两轮 receive smoke 均通过，不增加测试计数 |
| 版本绑定 | 工具查询退出 0；安装归档与锁文件相符；Cargo.lock/WIT/moon.mod 与 b361ed4 的 Git 对象相符 |

10 组 Python suite 分别为 9、6、4、7、1、7、20、40、14、6；重复构建的第二批 19 项 Wasm 不重复计算。
匿名 REST API 实际仍为 403 限流；公开 job-groups 诊断请求为 400，未作为完成依据。
最终成功结论来自 GitHub 公开运行页及原始报告，不假装取得完整 API 响应或 job 控制台日志。
官方匿名附件地址实际 404；沿用 #2 已说明的公开 nightly.link 转发方式，下载后先核对 GitHub 固定摘要，
通过后才解包使用。没有登录、安装/授权 GitHub App、读取浏览器凭据或保存临时签名跳转 URL。
该第三方服务不构成发布者身份/签名验证；获取方式、失败尝试、摘要与边界均另存。

证据：[evidence/ci/39378888384-attempt-1/](../evidence/ci/39378888384-attempt-1/)。
本次独立检查新增全部报告及语义元数据，原始 ZIP 不重打包，解包内容与 ZIP 字节一致。
规则未发现其覆盖的凭据、签名 URL、私钥或完整模拟密钥；runner/临时路径与工具/对象摘要保留。
这不是完整 DLP、CVE 审计、新 rootfs 或性能基准；精确附件到期字段未取得，工作流仍配置 14 天保留。

~~~bash
(cd evidence/ci/39378888384-attempt-1 && sha256sum -c SHA256SUMS)
~~~

后续工程文档定稿与新证据索引属于另一个冻结提交，不把它标成已经跑过本轮 GitHub CI。
其最终源码包应按 [FINAL_DELIVERY.md](FINAL_DELIVERY.md) 冻结，并以包旁实际 REPRODUCTION/FINAL_VALIDATION
记录完整文档与实现的解包重建结果；不要为补写通过结论而改写已冻结文档。

## 历史：运行 #2 与附件已核验归档（2026-10-20）

[MoonVCS CI #2 / attempt 1](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39373597127)
在提交 **`58bade3725f17e71e47ae4eee1d765ed730e762f`** 上实际成功，触发为 push / main。
本轮旧的匿名 API 查询返回 403（限流）；改读 GitHub 公开运行页，确认完整提交链接、Success、
总耗时 9 分 23 秒、job 9 分 19 秒和唯一附件的名称/ID/摘要。
页面触发时间为 2026-10-20 05:11:54 UTC（北京时间 13:11:54）。
没有把网页观察伪装成完整 REST API 响应，也没有沿用 #1 的成功推断 #2。

| 项目 | 实际结果 |
|---|---|
| 附件 | `moonvcs-ci-39373597127-1`，ID `12242429705` |
| ZIP 实测字节 | **32,637**；网页显示 31.9 KB，未获取 API 的精确大小字段 |
| ZIP SHA-256 | `6a8e5cdef96b013f72c1d80a4730b1a1d76fc88b012948cde39a959931e9568d`，与 GitHub 页面一致 |
| 解包 | 8 个 UTF-8 报告，合计 144,850 字节；CRC、路径、文件类型、预算与逐成员字节校验通过 |
| 完整测试 | **237 项通过**，86 native + 26 Rust + 19 Wasm + 106 Python，重复 Wasm 输出不再计数 |
| verify | 05:16:13 UTC 开始；regression 286 秒 / environment 0 秒 / repeat-smoke 14 秒，全部退出 0 |
| 额外 smoke | 双轮四场景演示与两次 receive smoke 通过，不增加测试计数 |
| 保留期限 | 工作流配置 14 天；本次未取得 API 精确 expires_at，不虚构到期时间 |

官方匿名附件链接实际返回 404。随后通过公开 [nightly.link 附件转发](https://nightly.link/)
下载原 ZIP，仅在匹配**独立从 GitHub 页面取得的摘要**后才解包使用。
该服务不是 GitHub 官方服务；本轮没有登录、授权/安装 GitHub App、读取本地凭据或保存临时签名跳转 URL。
这条获取路径及之前的 403/404 均保留于 acquisition.json；未隐藏失败或重新打包原 ZIP。

证据目录：[`evidence/ci/39373597127-attempt-1/`](../evidence/ci/39373597127-attempt-1/)。
run-observation.json 保存公开页面的语义字段，不保存带实时订阅字段的原始 HTML；
artifact-metadata.json 保存官方页面观察，validation.json 记录独立计数、完整性与未验证项，
privacy-review.json 是对**本次新增附件**另做的检查，SHA256SUMS 绑定原 ZIP、解包文件及旁文件。
没有保存完整 job 控制台日志。安装报告的 installed_not_tested 仍只是安装步骤状态，不改写为验证通过。
已把源码 Cargo.lock/WIT/moon.mod 的摘要与 `58bade3` 对应 Git 对象核对，工具归档与版本查询也通过。
规则扫描未发现其覆盖的凭据值、签名 URL、个人目录或完整模拟密钥；保留 runner、/tmp、工具版本及对象摘要。
这不是完整 DLP、第三方审计、新 rootfs 或性能基准。

~~~bash
(cd evidence/ci/39373597127-attempt-1 && sha256sum -c SHA256SUMS)
~~~

本次归档没有重跑项目测试、重复发布 Mooncakes 或上传 Release。
**截至归档核验时，后续打包修复尚未实施，也不属于本轮 CI 被测范围。**
归档后的文档/代码提交应分别注明自己的本地验证和是否又运行了 CI，不改绑本轮成功。

## GitHub Actions：运行与附件已核验归档（2026-10-19）

已通过 GitHub REST API 核对本次运行，**运行状态为 completed，结论为 success**：

| 项目 | 实际记录 |
|---|---|
| 运行 | [MoonVCS CI #1 / attempt 1](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39241926009) |
| 提交 | [`6d9615736b9b60bc58e1ae3f0cf49bf340231d84`](https://github.com/any07557-wq/MoonBitCVS/commit/6d9615736b9b60bc58e1ae3f0cf49bf340231d84)，CI 被测源码提交；后续文档归档提交不改变此绑定 |
| 触发 / 分支 | push / main |
| 工作流 | `.github/workflows/ci.yml`，MoonVCS CI |
| 开始 / 最后更新 | 2026-10-19 11:04:03 / 11:18:46 UTC（北京时间 19:04:03 / 19:18:46） |
| 唯一报告附件 | `moonvcs-ci-39241926009-1`，artifact ID `12182476716`，32,666 字节 |
| ZIP 实测 SHA-256（与 GitHub 元数据一致） | `dc991ef6e100d275fe4fec1a5439ba35a47419a775589fe7223bfbca5be2ed6e` |
| 附件过期 | 2026-11-02 11:18:43 UTC（北京时间 **11 月 2 日 19:18:43**），14 天保留期 |
| 报告实际结果 | **237 项通过**；regression、environment、repeat-smoke 三阶段退出码均为 0 |
| 本次归档核验 | 2026-10-19 12:02:34 UTC（北京时间 20:02:34），未在本机重新执行完整测试 |

原 origin 使用 `MoonBit_Program`；GitHub API 返回的当前仓库名称及规范运行链接为
`any07557-wq/MoonBitCVS`。本次未修改 origin，也未推送、触发工作流或更改远端配置。

已保存的证据位于 [`evidence/ci/39241926009-attempt-1/`](../evidence/ci/39241926009-attempt-1/)：

- [`moonvcs-ci-39241926009-1.zip`](../evidence/ci/39241926009-attempt-1/moonvcs-ci-39241926009-1.zip)：原始附件，未重新打包。
- `extracted/ci/` 与 `extracted/reports/`：8 份报告，共 144,855 字节；每份均核对与 ZIP 成员字节一致。
- `run.json`：此前下载的原始运行响应；`artifact-metadata.json`：成功返回的附件列表字段摘录。
- [`validation.json`](../evidence/ci/39241926009-attempt-1/validation.json)：本次核对结果、计数和未验证边界。
- [`privacy-review.json`](../evidence/ci/39241926009-attempt-1/privacy-review.json)：新增附件独立隐私检查的范围、发现和限制。
- `SHA256SUMS`：原 ZIP、8 份报告、运行/附件元数据及本次核对/隐私检查结果的完整摘要清单，不包含清单自身。

首次匿名 API 下载实际遇到 HTTP 403 `API rate limit exceeded`，当时只保存了运行元数据，未把失败当成功。
随后维护者用浏览器下载并提供本地附件路径，本次从其旁的原始 ZIP 复制归档；未修改用户下载目录。
本机没有 `unzip` 命令，改用 Python 标准库 `zipfile`：先核对 ZIP 大小、SHA-256、CRC、路径、
文件类型和解压预算，再解包；没有执行附件中的内容。没有再次请求网络下载。
`artifact-metadata.json` 末尾的 false/阻塞说明保留首次核对时的历史状态，当前状态以 `validation.json` 为准。

`phase7-verify.json` 记录从 11:09:56 UTC 开始，regression 497 秒、environment 0 秒（整秒计数）、
repeat-smoke 29 秒，三阶段记录合计 526 秒，全部退出 0；这不是新的性能基准。
从 `phase7-regression.log` 独立核对：86 native + 26 Rust + 19 Wasm + 106 Python = **237**；
10 组 Python suite 分别为 9、6、4、7、1、7、20、40、6、6，均为 OK。
重复构建时第二次运行的同一批 19 项 Wasm 测试不重复计数；双轮四场景 demo 与额外两次 receive smoke 均成功，另列而不增加总数。

安装报告显示固定 MoonBit 两份官方版本 URL 归档均核对原锁文件摘要；环境报告中的所有工具版本查询成功，
MoonBit/Rust/Wasm 工具与固定版本一致。Cargo.lock、WIT、moon.mod 三份源码摘要与运行提交中的 Git 对象逐项匹配。
安装器报告自身仍是 `installed_not_tested`，其中完整验证相关 false 标记只表示安装步骤未运行测试，未修改原报告；
完整通过依据是后续 `phase7-verify.json`、原始日志和 GitHub 的 success 结论，而非安装器标记。

从仓库根目录复核保存内容（只读、不联网、不重跑项目测试）：

~~~bash
(cd evidence/ci/39241926009-attempt-1 && sha256sum -c SHA256SUMS)
~~~

此目录不在被忽略的 `target/` 中，GitHub 附件到期不影响本地归档。
**截至本次归档核验时（2026-10-19 12:02:34 UTC）**，这些证据尚未提交、推送或创建异地备份；
`validation.json` 中相应布尔值也仅记录这一时间点，不表示后续提交状态。
随后在新增附件隐私检查后单独本地提交本组文档和证据；本地提交不等于已推送或建立异地备份。
未保存完整 job 控制台日志，只有工作流选定上传的报告。

### 新增附件的独立隐私检查

2026-10-19 12:17:48 UTC，针对原 ZIP 的全部 8 份 UTF-8 文本成员，以及 `run.json`、
`artifact-metadata.json`、`validation.json`、`SHA256SUMS` 四份旁文件另做检查，未沿用此前源码包的检查结论。
已逐份确认解包内容与 ZIP 成员一致；检查 GitHub/cloud token、私钥块、认证头、凭据赋值、
URL 内嵌凭据/签名参数、JWT、SSH/凭据路径、个人 Windows/HOME 路径和完整模拟 token，未发现这些匹配。
另检查了邮箱、IP、外链主机和策略诊断：唯一邮箱为仓库已有的公开 GitHub noreply 提交地址，
外链限 GitHub API/仓库/头像和官方 MoonBit 下载域；其余路径是 GitHub runner 与 `/tmp` 测试目录。
保留这些公开身份、工具版本、对象摘要和临时路径；无需为本次公开归档修改原报告或重新打包 ZIP。
检查是规则扫描和上下文核对，不是完整 DLP、第三方安全审计或“绝无敏感信息”的证明；
本轮不运行项目完整测试，也不扩大生产安全保证。

GitHub 的成功结论只绑定上述提交和运行，不扩大到新 rootfs 冷安装、三档性能基准或生产安全保证。

## 历史：CI 接入时的本地验证

日期：2026-10-19，Asia/Shanghai。起点为本地 Git 导入提交 560408e。
维护者明确要求 **仅本地独立提交，暂不推送**；本轮没有 push、workflow_dispatch 或远端配置变更。

### 结论与未验证项

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

### 实际失败、修复与重跑

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

### 最终执行与版本绑定

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

### 后续核对与原型边界

~~~bash
sha256sum -c target/reports/ci-setup.RXW29u/tested-source.sha256
sha256sum -c target/reports/ci-setup.RXW29u/evidence.sha256
~~~

以上为接入时的历史核对命令。旧 `evidence.sha256` 包含当时的本文；
本次补记 GitHub 结果后，应使用提交 `6d9615736b9b60bc58e1ae3f0cf49bf340231d84` 中的原文核对该项，
不要为匹配当前文档而改写旧清单。可执行代码与旧运行日志未改动。

target 日志是被 Git 忽略的本机产物，不会随本轮提交自动上传。
接入时尚无 GitHub 实际成功；后续的运行核对与附件状态见本文开头，不改写本节历史结论。
本轮没有发布 Mooncakes、Release、申报书、改变分支保护或更新旧交付归档。
225/231 项与历史 149 项安装结果保持各自版本边界；认证/ACL/TLS/OS 权限分离、Host/JIT 总内存、
GC/自动恢复、Partial Clone inspection 来源依赖等原有限制均未解决，也没有清理任何恢复来源。
