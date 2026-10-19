# 安装与复现边界

## 已验证到哪一步

已验证 Linux x86_64 / WSL2 上的源码构建、225 项本机独立测试和实际 Wasm 演示；
冷安装另为增加 diff 前的 149 项源码快照，不能混同。
阶段 7 还在不带 target、_build、.mooncakes 的源码副本中完成了重建与回归，
但复用了已安装工具链和 registry 缓存。这不等于验证过空白机器安装或完全离线分发。

第一轮独立下载的 OCI rootfs 安装已通过：未挂载宿主工具/registry 缓存，固定工具安装、
五个组件 pin、134 项完整回归与四场景演示均实际验证。
初始缓存为空，修复后重试只复用该隔离安装自行下载的依赖；所有失败日志保留。
共享宿主内核，不是物理空白 OS 或跨平台证明。[实际记录](docs/ROADMAP_PROGRESS.md)
本轮最终脚本 + 本地归档的完整安装已实际通过：fresh-02 镜像下载 401 的失败原样保留；
有界续期修复及 3 项回归后，fresh-03 从新目录完成工具安装、149 项完整测试和四场景演示，全部退出 0。
宿主也独立重跑 149 项通过，不用它替代隔离结果。[本轮实际记录](docs/FRESH_INSTALL_VALIDATION.md)

该隔离安装验收对应 diff 实现之前的源码。后续 diff 的本机构建/测试单独记录于
[DIFF_VALIDATION.md](docs/DIFF_VALIDATION.md)，branch/switch 另见 [本机验证](docs/BRANCH_SWITCH_VALIDATION.md)
与 [收尾独立验收](docs/BRANCH_SWITCH_ACCEPTANCE.md)；
不把旧 rootfs 或旧源码包视作新功能安装验收。
当前交付入口新增 6 项归档/复现防护，共 231 项；在另一目录解包后使用已安装工具和全局缓存重建，
仍不等于冷安装。具体包的完整运行结果见包旁 REPRODUCTION.json，方法见 [SUBMISSION.md](docs/SUBMISSION.md)。

当前没有发布安装包、容器镜像或托管仓库下载地址。先取得项目源码，不要复制文档中不存在的发布链接。
当前机器的版本、系统和插件摘要见 target/reports/phase7-environment.json；
源码侧固定要求见 scripts/build-component.sh、host/Cargo.lock 和各插件 plugin.toml。

## 固定工具链

| 工具 | 本项目验证的版本 |
|---|---|
| MoonBit | moon 0.1.20261012、moonc 0.10.15 |
| Rust / Cargo | 1.99.1 |
| Wasmtime | Rust crate 49.0.3，由 Cargo.lock 固定；不需要 Wasmtime CLI |
| wit-bindgen-cli | 0.63.0，含 MoonBit 绑定生成器 |
| wasm-tools | 1.262.0 |
| 原生工具 | GCC 15.2.0、Bash、Python 3.14.4、coreutils |
| Mooncakes | gmlewis/sha256 0.18.0、moonbitlang/async 0.20.2 |
| 可选终端录制 | util-linux script / scriptreplay（本机 2.41.3） |

生成的 WIT/MoonBit 绑定已包含在 plugins 下，正常构建无需重新生成。
升级 MoonBit 或绑定生成器可能改变组件字节；摘要漂移应当中止构建，不能直接删除 pin 检查。
独立镜像使用 GCC 12.2.0/Python 3.11.2；其固定 async 依赖有 posix_spawn_*_np C 声明警告，
不应把 MoonBit --deny-warn 或测试通过宣传成所有依赖的 C 构建零警告。

## 工具链目录约定

构建脚本当前使用项目本地布局：

    .toolchains/cargo/bin/cargo
    .toolchains/cargo/bin/wit-bindgen
    .toolchains/cargo/bin/wasm-tools
    .toolchains/rustup/

存在项目本地 Cargo 时，build-policy-runtime.sh 使用上述 Cargo/Rustup home；
没有项目本地工具时，现在支持 PATH 中的 Cargo/wit-bindgen/wasm-tools，或显式的 MOONVCS_* 工具路径。
不会无条件将外部 Cargo 指向空的项目本地 home；已有项目本地工具优先，版本检查仍保持。
MOONVCS_MOON 指向实际 moon 可执行文件。构建需 C 编译器和可用的 Mooncakes 依赖。

新机器应从 [MoonBit 官方下载页](https://www.moonbitlang.com/download/) 和
[Rustup 官方安装说明](https://rust-lang.github.io/rustup/installation/index.html) 获取工具。
官方默认安装的最新版未必等于上述验证版本。本轮已实际下载并校验完整版本
0.10.15+943464bfa 的 compiler/core，摘要与原工具一致；地址与长度见 scripts/moonbit-archives.lock.json。
不能用 moon 日期版本 0.1.20261012 代替该归档版本。[归档证据](docs/ROUND2_VALIDATION.md)

下面只是匹配当前目录约定的 Rust 工具安装示例，**未在空白机器验证**。
先根据官方说明取得并检查 rustup-init，然后在项目根目录执行：

~~~bash
export CARGO_HOME="$PWD/.toolchains/cargo"
export RUSTUP_HOME="$PWD/.toolchains/rustup"
# rustup-init 是你从官方取得的安装器，不是本项目提供的脚本。
./rustup-init --no-modify-path --profile minimal --default-toolchain 1.99.1 -y
"$CARGO_HOME/bin/rustup" component add rustfmt
"$CARGO_HOME/bin/cargo" install --locked wit-bindgen-cli --version 0.63.0
"$CARGO_HOME/bin/cargo" install --locked wasm-tools --version 1.262.0
~~~

这些安装步骤需要网络与工具链/registry 可用性，不是已验证的离线 bootstrap。
不要为绕过无法取得的版本而悄悄改写 Manifest 摘要。

## 已有固定工具后的构建

在项目根目录：

~~~bash
export MOONVCS_MOON="$HOME/.moon/bin/moon"  # 按实际安装位置调整
"$MOONVCS_MOON" -C vcs update  # 全新安装需 registry 索引；已有离线缓存时可跳过
./scripts/build-vcs.sh
export PATH="$PWD/target/bin:$PATH"
./scripts/test.sh
~~~

build-vcs.sh 会生成、校验五个组件及异常 fixture，构建锁定依赖的 Rust Host，
检查/测试/构建 MoonBit native Core，并安装：

    target/bin/moonvcs
    target/bin/moonvcs-policy-host
    target/bin/moonvcs-bypass-client     # 仅用于恶意客户端测试
    target/bin/moonvcs-default-policy.json
    target/components/*.component.wasm

Host 当前采用 Cargo dev/debug 构建，Core 采用 native release。
源码目录移动后请重新构建；默认策略含实际绝对路径，不是可任意移动的二进制发行版。
已经初始化的演示仓库可能仍引用原来的路径，应重新创建演示仓库。

需要重新生成绑定时，先阅读 scripts/regenerate-bindings.sh 的操作范围；
这不是正常运行演示的前置步骤。WIT 与 ABI 迁移规则见
[阶段 4 报告](docs/PHASE4_VALIDATION.md)。

## 快速演示与干净源码重建

~~~bash
python3 scripts/hackathon-demo.py prepare --workdir target/hackathon-demo-new --commits 40
python3 scripts/hackathon-demo.py run --workdir target/hackathon-demo-new --only all
MOONVCS_MOON="$HOME/.moon/bin/moon" ./scripts/verify.sh --clean-build
~~~

prepare 的目录必须不存在；重复演示只重新执行 run。
clean-build 仍依赖已安装工具和缓存，完整范围见 [TESTING.md](TESTING.md)。
独立 rootfs 内的空 registry 下载/安装已验证；Windows/macOS、物理空白操作系统、跨架构、
完全离线 bootstrap 和可重定位二进制分发均未验证。

## 独立 rootfs 安装检查

需要 Linux、bwrap、宿主 Python 3.12+ 和网络；不用 Docker daemon，不挂载宿主工具/registry 缓存：

~~~bash
python3 scripts/fresh-install.py prepare --workdir target/roadmap-fresh-new
python3 scripts/fresh-install.py verify --workdir target/roadmap-fresh-new
~~~

prepare 下载摘要锁定的官方 Rust Linux/amd64 OCI rootfs 与 MoonBit 归档，安装 rustfmt 和两项 Wasm 工具。
verify 拷贝无构建产物的源码，初始化 Mooncakes registry，再运行完整回归和四个真实演示；
报告仅在全部通过后标记 installation_verified=true。空 registry 不会由普通 build 自动填充，不能省略此步骤。
镜像内已有的 Rust/GCC/Python 来自下载的基础镜像；后续依赖来自该隔离安装过程，不是宿主缓存。
命名空间共享宿主内核，不能称为独立物理机器或 VM；下载失败不回退为缓存验证。
core 校验值是本地锁定值，镜像与归档摘要验证不等于发布者签名验证。
当前默认采用锁文件中的官方固定版本 URL，不再请求 latest；长度/摘要漂移会停止。

可先取得并单独保存可校验的 MoonBit 归档，再供 prepare 使用：

~~~bash
python3 scripts/toolchain_archives.py download --directory target/moonbit-archive-new
python3 scripts/toolchain_archives.py verify --directory target/moonbit-archive-new
python3 scripts/fresh-install.py prepare --workdir target/roadmap-fresh-new \
  --archive-dir target/moonbit-archive-new
~~~

本地模式只读取 sha256/<锁定摘要>.tar.gz；缺失、损坏、超长或静态符号链接即失败，
MoonBit 归档不转回网络或 latest；其余镜像/工具/registry 仍需网络。verify 是只读。请将目录和锁文件独立备份到维护者受控存储，
不要只保留会被忽略/清理的 target 副本。这里不自动上传、不保证上游永久保留、不验证发布者签名，
也不是 Rust/镜像/registry 的完整离线分发。外部长期托管及再分发许可需要另外安排。
