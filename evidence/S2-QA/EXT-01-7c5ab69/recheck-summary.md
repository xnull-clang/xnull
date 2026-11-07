# EXT-01 复验摘要（扩展）

- 任务给定 main：`7f0d6e1`
- 当前 `.git/refs/heads/main`：`7c5ab69a01756d30081684352a9b86a43fc7d099`
- binary：`/tmp/xnull-s2-7c5ab69`
- 结果：**FAIL**（与 BND-13 同源；复用 `difftest/s2/bnd13` 夹具）

## 通过

- codegen 正例：class/struct/singleton/数据 enum 扩展
- 扩展不进 vtable（官方测试）
- 协议实现违规 `TY-208`
- parser 拒绝 static/字段/构造器/private/protected 方法修饰符

## 失败

- 解释路径全部正例 `该类型没有成员方法`
- `check` 未注册 extension：重复/同签名/泛型/预定义类型/deinit 均 rc=0
- 跨包扩展被接受并运行
- 扩展访问 private 成员被接受并运行
- 合法重载被 codegen 误拒
