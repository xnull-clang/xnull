# 回执：S6-XDK-07 collections sema

- **状态**：`DONE`（sema）
- **根因**：类方法调用已按继承链/泛型替换解析，但 `PriorityQueue.less` 是**函数类型字段**，被当成“未登记方法”落到 `TY-229`；`self.less(a,b)` 未识别。
- **修复**：`inferCall` 先识别函数类型字段调用（`self.<field>` 经类字段表、外部接收者经 `findClassField`），按声明参数检查并返回声明返回类型；普通类方法仍走 `findClassMethod`。`RingBuffer.isFull/isEmpty`、`OrderedMap.indexOf/get`、`BTreeMap.lowerBound/get`、`PriorityQueue.swap/sift*` 均按源码签名通过。
- **测试**：`s6_xdk07_test.go` 覆盖 4 容器成员 + `less` 字段调用 + 实参类型负例；另用 main 的 `collections.x` + `import xdk.collections` 探针 `xnull check` 通过（`evidence/S6-XDK07/collections-main.*`）。
- **验证**：红→绿 `evidence/S6-XDK07/`；sema/xfront/interp/codegen/cli 全绿。
- **边界**：只改 sema；未动 collections 源码/codegen/runtime。若编译路径仍有发射缺口，归 E4。
