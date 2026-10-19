# Mooncakes 发布准备

日期：2026-10-19，Asia/Shanghai。状态：**CLI 已识别登录账号 `any07557-wq`；服务端 dry-run 成功，但固定 CLI 退出 255；未发布**。

CI 证据已另作本地提交 `14fadec89b64c1081908dd50eb34da070ef50b1d`
（`docs: 归档首次 GitHub CI 证据并更新验证状态`），未推送。
本页和本轮模块打包修改在该提交之后准备，不混入 CI 归档提交；
GitHub 的 237 项结果仍只绑定 `6d9615736b9b60bc58e1ae3f0cf49bf340231d84`，
不直接替本轮候选包背书。本轮未重跑项目完整测试。

## 已确认的账号与本地候选名

维护者明确提供新注册的 Mooncakes 用户名 `any07557-wq`。
据此将本地候选包从 `moonvcs/core@0.1.0` 改为 **`any07557-wq/moonvcs@0.1.0`**，
使用项目名作为包名；这是可调整的发布候选名，不是已上传、预留或已获服务器授权的名称。
`vcs/cmd/main` 和仓库专用 `cmd/bypass-client` 同步导入新路径，并显式保留 `@core` 别名，
不改 MoonBit 业务函数、对象编码、WIT namespace、Plugin API 或插件摘要。

账号注册本身不等于本机 CLI 已登录；维护者后来亲自完成登录，本轮 `moon whoami` 实际输出
`Logged in as any07557-wq`。这项命令只显示保存的登录身份，不单独证明服务端接受 Token。
不要把 Token、密码或 credentials 文件贴到聊天、仓库或日志；本轮未代为登录或打开凭据正文。
服务端发布预检及其 CLI 异常另见下节；未运行真实 publish 或推送。

官方[模块配置](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html)说明模块名前缀与发布用户名的关系；
[发布教程](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html)说明 register/login 与发布流程。
首次准备时本机没有 credentials 文件，`publish --dry-run` 因缺凭据失败，该历史结果保留。
当前已识别登录，不能再把旧“缺凭据”状态当作当前结论；也不能用本地打包成功代替服务端验证。

## 本地已准备的内容

- `vcs/moon.mod`：候选名称改为 `any07557-wq/moonvcs`，保留版本 `0.1.0` 和原依赖版本，
  补充 readme、repository、description、keywords，并明确模块仅支持 native 后端。
- `vcs/README.md`：说明模块用途、可运行的库导入示例、外部 Host/策略依赖及原型限制。
- `vcs/LICENSE`：与仓库根目录 LICENSE 字节一致的 Apache-2.0 声明。
- `vcs/.moonignore`：排除构建产物、日志、本地凭据和仓库专用 bypass-client；保留忽略规则本身。
  使用官方[`.moonignore` 规则](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html#publishing-files-with-moonignore)，
  再实际核对归档成员，不仅凭 Git 忽略规则推测。

模块包没有 Rust/Wasmtime Host、WIT、编译后的 Wasm 插件、运行配置、完整仓库脚本或预编译 CLI。
依赖安装不等于安装完整 MoonVCS；所附 white-box 测试包含需要完整仓库和构建产物的集成测试。
不声称单独解包后完整测试全部通过，也不发布绕过客户端测试工具。

## 当前候选：账号名迁移后的本地验证

实际记录：`target/reports/mooncakes-namespace.BnZcDV/`，与首次打包目录分开保留。
本轮核验时间：2026-10-19 12:33:15 UTC（北京时间 20:33:15）。

| 检查 | 实际结果 | 原始日志 |
|---|---|---|
| 固定工具 fmt / native deny-warn check | 均退出 0 | fmt.log、check-native.log |
| native 测试 | **86 项通过、0 失败**，退出 0；复用现有真实策略 runtime | test-native.log |
| native release build | 退出 0；main 与仓库 bypass-client 两个 CLI 均实际编译 | build-native.log |
| 新名称 package --list --frozen | 退出 0；33 个文件，没有旧模块名或 bypass-client 成员 | package.log |
| 新目录解包 native deny-warn check | 退出 0；不引用完整项目源码，仅复用依赖缓存 | unpacked-check.log |
| 新名称 README consumer | 实际运行退出 0，空 Blob ID 与既有向量一致 | consumer-run.log |
| 新 CLI --help | 退出 0；使用本轮新编译二进制，不覆盖 target/bin 中旧产物 | cli-help.log |

86 项是既有测试入口中的 native 部分，不是新增测试或整套 237 项重跑。
其中策略集成用例使用现有 Host、Wasm 和策略配置；本轮未重新构建或认证整个插件运行环境。
WIT 摘要仍为 `4b3ff703ed44a679ea8b689e0977867505ec602d159d2f57f9c4773bccc8725d`，
与首次 GitHub 环境报告一致；plugins/host/wit 中没有修改，旧 CI 原包和清单也未改动。

当前候选 ZIP：

- 路径：`target/reports/mooncakes-namespace.BnZcDV/package-build/publish/any07557-wq-moonvcs-0.1.0.zip`
- 33 个文件；75,212 字节；成员原始内容合计 265,964 字节。
- SHA-256：`5006035f75de4f963213a92257bafa3a5d2f751bb117c803c49d9c09f21867d3`。
- 已核对 CRC、路径、文件类型、解压预算；全部成员与当前 vcs 源码及解包副本字节一致。
- consumer 通过 moon.work 引用解包模块，导入 `any07557-wq/moonvcs` 并使用 `@vcs` 别名；
  其示例代码与 README 一致，输出既有空 Blob ID。
- 本地记录见该目录的 `validation.json`；它不是登录成功、版本预留、远程安装或发布成功的证据。

本次只迁移拟发布的 `vcs` 模块；MoonBit Wasm 插件的本地模块名不属于本次 Mooncakes 发布范围，
WIT 的 `moonvcs:policy` namespace 也不跟随发布账号变更。

## 登录后的服务端预检与 CLI 兼容问题

核对时间：2026-10-19 12:52:22 UTC（北京时间 20:52:22）。
本地记录位于 `target/reports/mooncakes-auth-preflight.SnmNn0/`；未覆盖前两轮报告或 CI 证据。

| 操作 | 实际结果 |
|---|---|
| `moon whoami` | 退出 0，显示 `Logged in as any07557-wq`；不显示 Token |
| `publish --dry-run --frozen` | 退出 255；源模块检查通过，解包检查因临时目录缺依赖且 frozen 禁止安装而失败 |
| 正常 `publish --dry-run` | 源模块及解包检查通过；服务端明确返回 **202 Accepted / dry-run 成功且未变更**；但 CLI 仍退出 **255** |
| `moon view any07557-wq/moonvcs@0.1.0 --json` | 退出 255，公开 manifest 请求得到 **404 Not Found**；截至查询时该版本不可见，不是名称/版本预留保证 |

正常 dry-run 的实际命令如下；这是联网服务端预检，不是严格离线或零传输操作，
不能把“未发布/未变更 registry”描述为“完全不向服务端发送待验证数据”。

~~~bash
moon -C vcs publish --dry-run \
  --target-dir /home/user/MoonBit_Program/target/reports/mooncakes-auth-preflight.SnmNn0/normal-build
~~~

服务端的原文观察摘录：

> Server status: 202 Accepted, detail: Dry run completed successfully. No changes were made. The dry-run was made for package any07557-wq/moonvcs version 0.1.0.

CLI 随后输出 `Error: moon publish failed` 并退出 255，因此**没有把这次命令写成退出 0 或完整 CLI 预检成功**。
只读核对了当前 moon 对应官方提交 `748b63c25261be2ec38b2cc70884d5894a456360` 的
[发布适配层](https://github.com/moonbitlang/moon/blob/748b63c25261be2ec38b2cc70884d5894a456360/crates/moon/src/cli/mooncake_adapter.rs)：
外层将后端非零退出报告为命令失败；尚未确认后端内部如何判断 HTTP 202，不能声称已定位或修复该细节。
没有修改已安装工具、取消版本约束或把非零退出强制改为成功。

保留 frozen 失败而不沿用该选项，是因为发布器会在全新的临时解包目录安装依赖并重新 check；
源模块已有缓存并不代表该目录已具备依赖。正常流程实际使用缓存中的 async 0.20.2、sha256 0.18.0、
以及传递依赖 base64 0.16.13，未修改模块名称、版本或依赖声明。
本轮各预检生成 ZIP 的 SHA-256 均为 `5006035f75de4f963213a92257bafa3a5d2f751bb117c803c49d9c09f21867d3`，
与前一轮验证包一致；`vcs/moon.mod` 前后摘要均为
`71d31f217ef23658672faa472487fd3477a4067712540c766c4bd7589789f11a`。

诊断更正：最初两次只保存错误类别的投影，使用了过宽的 `failed to resolve` 匹配，
把依赖图解析失败也归入“网络失败”；这些投影不足以证明发生了网络故障。
后续严格脱敏的错误正文才明确重现 frozen 安装限制；这里不把早期分类当作网络根因。
CLI 原始输出未公开或保存；记录的是脱敏摘录、检查结果和只读版本查询，不含凭据正文或 Token 摘要。

本轮没有执行不带 dry-run 的 publish，没有新提交、推送、全量回归或 registry 安装验收。
若未来正式发布也出现“服务端响应与 CLI 退出码不一致”，须先查 registry 的版本/内容及服务端状态，
不能因为非零退出就盲目重试或断言尚未发布。

## 历史：首次未确认账号时的打包检查

固定工具：moon `0.1.20261012`、moonc `0.10.15+943464bfa`，未升级或替换工具以通过检查。
本地原始日志和各版包保留于 `target/reports/mooncakes-prep.Zd5eCm/`，未覆盖 CI 证据：

| 操作 | 实际结果 | 日志 |
|---|---|---|
| 初始 `package --list --frozen` | 退出 0，但警告缺 readme/repository，且包含仓库 bypass-client | package-before.log |
| `publish --dry-run --frozen` | **退出 255**，缺本地 credentials；未登录或上传 | dry-run-before.log |
| 首次补充元信息 | **fmt/package 均退出 255**，当前固定工具不接受 homepage 键；删除该键，保留 repository | fmt.log、package-candidate.log |
| 元信息格式重查 | **fmt 退出 255**，keywords 数组空格格式；package 退出 0，随后按固定 formatter 修正 | fmt-final.log、package-candidate-final.log |
| 首次解包 consumer | **check 退出 255**，README 示例直接打印 VcsError 而未实现 Show；改用常量错误文本 | unpacked-check.log |
| 首次 consumer run 命令 | **退出 2**，缺 package 参数；后续显式使用 `run .` | consumer-run.log |
| 最终 fmt/package | 均退出 0，无前述元数据缺失警告 | fmt-ready.log、package-ready.log |
| 新目录解包 check | native、deny-warn、frozen，退出 0 | unpacked-check-ready.log |
| 最终 README consumer | native 实际运行退出 0，输出预期空 Blob ID | consumer-run-ready.log |

`moon package --list` 在该版本会先检查并生成 ZIP，不是严格只读列表命令。
先前失败的 consumer 与归档保留原样；最终检查使用新的 `verified/` 工作区，
通过 moon.work 只引用最终 ZIP 的解包模块。复用本机 MoonBit/C 工具与已有依赖缓存，
不挂入完整项目源码、Host 或插件；这不是冷安装或从远程 registry 安装已发布版本的验收。

以下是首次候选包当时的实际命令，仅作历史记录。当前源码已改名，
不要重新执行并覆盖这些旧报告目录；复现应另建新目录。

~~~bash
moon -C vcs fmt --check
moon -C vcs package --list --frozen \
  --target-dir "$PWD/target/reports/mooncakes-prep.Zd5eCm/ready-build"
moon -C target/reports/mooncakes-prep.Zd5eCm/verified/module \
  check --target native --deny-warn --frozen
moon -C target/reports/mooncakes-prep.Zd5eCm/verified/consumer \
  run . --target native --frozen
~~~

consumer 输出：`3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7`。
这只验证导入和对象编码示例，不运行 commit/policy，也不添加到历史 237 项计数。

### 首次候选包绑定（改名前，保留不覆盖）

- 原包：`target/reports/mooncakes-prep.Zd5eCm/ready-build/publish/moonvcs-core-0.1.0.zip`
- 33 个文件；ZIP 75,159 字节；成员原始内容合计 265,824 字节。
- SHA-256：`73be92ba572a4d540c07bdce10d0cace73003fc7ff79acb781fe68b3f5f5a912`。
- 当时逐份核对 ZIP 成员、vcs 源文件和解包副本字节一致；README 示例与 consumer 源码一致。
  该摘要只绑定旧 `moonvcs/core` 候选包，不匹配改名后的当前源码。
- 打包日志、失败记录和候选包都仍是被 Git 忽略的本地 target 产物，尚无异地备份或正式发布。

## 实际发布前的门槛

维护者已确认账号，当前本地候选为 `any07557-wq/moonvcs@0.1.0`，但仍需确认正式包名、
真实发布权限与最终版本状态；不能把用户名确认、或带 CLI 异常的 dry-run，当作正式发布成功。
本次改名需形成独立源码提交并运行 CI；不把旧 CI 证据改绑新模块身份。
CI 附件隐私检查不替代 Mooncakes 源码包审查，包内也保留无害模拟凭据测试源码；发布前仍需核对最终内容。
README 保留“尚未发布”的准确状态；实际发布后再据实更新，不提前声称可从 registry 安装。

维护者已亲自完成账号登录；仍需在获得**明确发布授权**后执行真实 publish，
核对 registry 页面、版本和从新 consumer 的真实下载/导入结果。
公开源码推送、实际发布、标签/Release 和账号设置均不是本轮自动执行的动作；
在未完成前保持“发布准备”，不写成“Mooncakes 已发布”。
