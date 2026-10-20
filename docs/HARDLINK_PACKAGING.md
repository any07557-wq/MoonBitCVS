# 硬链接交付输入：修复与验收

## 问题与契约

旧证据筛选器把普通硬链接当作常规文件接受；GNU tar 会对同 inode 的成员使用
hardlink 编码，复现器却拒绝所有链接成员。摘要相同不能消除这个格式不兼容。

当前在预检中检查 `lstat().st_nlink == 1`：清单自身、清单内附件及打包器显式选择的
历史报告都必须满足。错误指出具体相对文件名，全部预检通过后才创建 `target/releases/`
及本轮包目录。不复制替换输入，不把 tar 改为解除链接，复现器仍拒绝链接成员。
内容相同而 inode 独立的常规文件继续允许；目录的链接计数不作文件规则检查。

这不覆盖源码硬链接，也不是对预检后恶意同账户修改的防护；打包期间不得并发修改输入。
本轮不改变已发布 Mooncakes 0.1.0 或不可变 `ec287d1` 工程包。

## 可重复的回归

```bash
python3 tests/submission_audit.py
```

套件 19 项，其中新增 5 项均调用真实 `package-submission.sh`、GNU tar 和 SHA-256，
使用临时目录内自建的源码/历史报告占位数据，不读取用户私有文件：

- 普通常规输入生成包，校验两个归档摘要并由真实复现解包器验证。
- 硬链接附件、清单和历史报告分别非零退出，错误含文件名，没有输出目录/半成品。
- 两个等内容、不同 inode、各自单链接的文件可以打包、校验、解包。

这些夹具验证打包与解包边界，不冒充完整 MoonVCS 源码的运行验收。
## 本机实际验收（2026-10-20）

`python3 tests/submission_audit.py`：19 项通过。随后实际调用根目录打包器，
从新包解到新目录，复用已安装的固定工具链/全局缓存、不复制工程构建产物：

```bash
bash scripts/package-submission.sh
python3 scripts/reproduce-submission.py \
  --package-dir target/releases/submission.AkD9Zq \
  --workdir /home/user/MoonBit_Program/target/reports/hardlink-fix.x81cL9/reproduction \
  --toolchain-dir /home/user/MoonBit_Program/.toolchains --moon /home/user/.moon/bin/moon
```

实际 07:00:06–07:07:01 UTC，environment/regression 均退出 0；完整去重 **250 项通过**
（native 86 + Rust 26 + Wasm 19 + Python 119），CLI 与双轮四场景演示通过。
重建后源码及两个输入归档摘要未变。命令/摘要摘要见
[HARDLINK_PACKAGING_VALIDATION.json](HARDLINK_PACKAGING_VALIDATION.json)，完整原始日志保留在上述 workdir。

这是本轮回归用临时验证包，不替换 `submission.QXtsyg` / `ec287d1` 最终工程交付。
该验证包在验收结果补写前生成；源码实现已测，不声称补写后的文档已重新统一冻结。
另行核对旧交付外层包及内部 `DELIVERY_SHA256SUMS` 全部通过。校验期间最初两次命令
使用了错误 cwd，出现文件找不到；在各清单所属目录重跑后通过，不把首次路径错误记为内容损坏。
没有新 rootfs、公开 GitHub CI、推送或 Mooncakes 重新发布。
