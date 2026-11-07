# BND-13 复验摘要（扩展 extension）

- 任务给定 main：`7f0d6e1`
- 当前 `.git/refs/heads/main`：`7c5ab69a01756d30081684352a9b86a43fc7d099`（reflog：7f0d6e1 → a4abe73 → 7c5ab69；e4b57d4 已在主线）
- binary：`/tmp/xnull-s2-7c5ab69`，sha256 `f9d1fe6d1c71d8bd61409595cfb41fe6d62afabe58048cf49baf5063e1c918dd`
- 结果：**FAIL**

## 通过（codegen 面）

- class/struct/singleton/数据 enum 扩展：compiled 分别 `L:x`、`6`、`4`、`true/false`
- 扩展不进 vtable：官方 `TestS2BND13ExtensionNotInVtable` PASS
- 协议实现违规：`TY-208`
- static/字段/构造器/private/protected 方法修饰符：parser `SYN-101`
- 重复/已有/继承同签名、泛型目标、预定义类型、deinit：codegen 拒绝（`run` 阶段）

## 失败

1. 解释路径未支持扩展方法：A01–A05 全部 rc=1（`该类型没有成员方法`）。
2. `check` 未实现 extension 语义：重复/已有/继承同签名、泛型目标、预定义类型、deinit 均 rc=0；只有 `run` 到 codegen 才拒绝，且无位置。
3. 跨包扩展：`check` rc=0，compiled rc=0 输出 `x`（§11.4 应拒绝）。
4. 扩展访问 private 成员：`check` rc=0，compiled rc=0 输出 `1`（§11.3 应拒绝）。
5. 合法重载（`f()` + `f(Int)`）：`check` rc=0，compiled codegen 误拒（§11.1 允许重载）。
