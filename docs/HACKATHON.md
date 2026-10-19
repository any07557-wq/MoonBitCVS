# 给评委的技术亮点摘要

展示主线：MoonBit Core、真实 Wasm 策略、显式权限、提交/接收门禁、按需历史。
它们有现有代码/测试/演示证据；后续安装复现、宽 Tree 剖析、暂存修复和恢复的实际状态见
[执行记录](ROADMAP_PROGRESS.md)，不将仍未完成的部分作完成宣称。
真实远端开放前仍需认证、ACL、TLS 和服务端 OS 权限分离。

MoonVCS 探索的不是“功能更多的 Git”，而是让受控策略、发布边界和按需历史在一个系统里真实协作。
MoonBit 实现 Blob/Tree/Commit、内容寻址、候选提交、Policy Engine、Lazy Store 和远端接收事务；
MoonBit 也编写 Secret Scanner、License Checker 与 Restricted Plugin，并实际编译为 Wasm Component。
Rust 只提供必要的 Wasmtime Host、绑定、能力过滤和执行预算。

本地提交与文件系统/stdio receive 入口分别运行固定版本/摘要的 required policies。
经这些入口的策略拒绝或运行失败不能更新 Ref；客户端“通过结果”不能授权接收发布。
同账户直接修改服务器文件不在这条入口保证内，独立进程不提供 OS 权限分离。
插件的数据来自显式授权交集，具有 fuel、epoch、线性内存和输出边界。
部分克隆从已校验的对象引用逐步发现旧历史，下载后再校验、缓存，Unknown 不盲目探测远端。

Lazy Fetch、Secret Scanning、Hook 和内容寻址都有既有实现。
本作品的价值是可运行、可测试的组合：MoonBit 核心 + MoonBit Wasm 策略 + 显式权限 + 发布约束 + Lazy Storage。
这仍是没有认证/TLS/OS 权限分离的原型，没有宣称速度、体积、工业安全或全球首创优势。

## 一页证据入口

- [三分钟讲稿与四个现场演示](../DEMO.md)
- [架构与语言职责](../ARCHITECTURE.md)
- [逐项宣传核验](CLAIMS.md)
- [实际测试、基准与剩余问题](../TESTING.md)
- [完整竞品差异与官方参考](COMPARISON.md)
- [阶段 8 实际交付记录](PHASE8_DELIVERY.md)

## MoonBit 价值的源码证据

| 价值 | 实际代码 |
|---|---|
| 强类型 VCS 模型与规范编码 | [model.mbt](../vcs/model.mbt)、[encoding.mbt](../vcs/encoding.mbt) |
| 提交与 required gate | [repository.mbt](../vcs/repository.mbt)、[policy_engine.mbt](../vcs/policy_engine.mbt) |
| 按需对象与远端发布 | [lazy_store.mbt](../vcs/lazy_store.mbt)、[receive.mbt](../vcs/receive.mbt) |
| Wasm 策略逻辑 | [Scanner](../plugins/secret-scanner/gen/interface/moonvcs/policy/evaluator/stub.mbt)、[License](../plugins/license-check/gen/interface/moonvcs/policy/evaluator/stub.mbt) |
| 可复用的强类型插件协议 | [WIT v1](../wit/policy.wit)，当前只验证 Wasmtime，跨宿主仍是潜力 |
