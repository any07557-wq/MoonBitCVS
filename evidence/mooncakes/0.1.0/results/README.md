# Mooncakes 0.1.0 发布验收证据

发布：2026-10-19；registry consumer 与证据收尾：2026-10-20（Asia/Shanghai）。
结论、实际命令、授权范围及已知限制见 [MOONCAKES_RELEASE.md](../../../../docs/MOONCAKES_RELEASE.md)。
机器结果见 [RELEASE.json](RELEASE.json)。

此处保存的是实跑报告，不包含登录凭据、工具链、完整 registry、构建目录或用户恢复现场：

- `project/`：冻结提交 `d5d8242` 的完整 237 项回归、环境报告与重复 smoke。
- `preflight-final.*`：最终预检；服务端接受 202 / CLI 255 的不一致如实保留。
- `publish-once.*`、`PUBLISH_INVOCATION.json`：唯一正式发布命令；服务端 200 / CLI 0。
- `registry-before.json`、`registry-after-*.json`：发布前 404、成功后的固定版本/摘要读回。
- `registry-index.json`：空 registry home 下载的新 index 中该版本记录。
- `consumer/`：固定 registry 依赖的导入源码、原始 update/check/test/run/whoami 日志。
- `publication-package*.log`、`packaging-checks.json`：被内容门禁拦下的空 ZIP / 次序漂移，以及精确重现结果。
- `capture_moon.py`：本轮认证命令的脱敏捕获与单次发布门禁实现，仅供审阅，**不要再次运行 publish**。
- `PRIVACY_REVIEW.json`：本轮新增附件的独立模式检查；不是完整 DLP 或作者身份/签名验证。
- `CLOSEOUT.json`：文档链接、未改发布源码与附件的最终检查；首次检查先于清单生成而失败，
  记录在 `closeout-first-attempt.log`，调整检查顺序后核对清单，不影响发布包。

冻结包、逐文件摘要和冻结时元数据在父目录，保持原字节；下载的 ZIP 与之相同，因此不重复存三份。
原始运行目录仍是 `target/reports/mooncakes-release.4J7nF4/`，这里独立保存必要证据，避免只依赖 ignored target。
源 TAR 摘要绑定 Git 导出；源码由本地提交保留，不在此再存一份完整源码。

在本目录核对附件：

~~~bash
sha256sum -c SHA256SUMS
sha256sum ../any07557-wq-moonvcs-0.1.0.zip
~~~

consumer 可复制到仓库外的新目录复现，不要复制 `_build`、`.mooncakes` 或 moon.work。
已有固定工具链和 C 编译器后，执行 `moon update`、`moon check --target native --deny-warn`、
`moon test --target native --deny-warn`、`moon run . --target native`。
两个测试不依赖完整 Host/插件。现有工具会对 main 包 `_test.mbt` 给出未来兼容性警告；
这不等于包运行错误，也没有以修改已发布内容来消除它。

包内 README 的“Not published yet”是冻结时历史措辞；本次未改版本或替换同版内容。
本地证据归档与独立提交不等于已推送、异地备份、新 GitHub CI 或新 rootfs 验收。
