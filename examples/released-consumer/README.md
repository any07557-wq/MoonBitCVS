# 已发布 0.1.0 的独立消费夹具

这是外部 native 库使用示例，不导入当前仓库 `vcs/`，不安装完整 MoonVCS CLI 或插件。
两项测试和 `cmd/readme/main.mbt` 分别保持发布时 consumer 测试与 README 示例的原字节；
测试专用 import 放在非 main 根包，示例 main 单独放在 `cmd/readme/`。

不要在本目录运行验收后把已有缓存当作独立下载证明。请使用根目录脚本：

```bash
python3 scripts/verify-published-consumer.py --moon /actual/toolchain/bin/moon \
  --workdir /outside/checkout/new-acceptance-directory
```

父目录必须存在，本次目录必须不存在。细节、失败处理与报告见
[公开包消费验收](../../docs/PUBLISHED_CONSUMER.md)。
