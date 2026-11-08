# 回执：S3-03pre（sema）

- **状态**：`DONE`
- **P1-1 容器中介引用环**：`fieldRefClass` 将 `List/Set/Map` 判为 GC；`fieldClassRefs` 穿透容器/数组/元组参与环 DFS；`class N { List<N> xs; }` → `Policy=gc, RefCycle=true`。
- **逃逸分类接口**：`Strategy.Escape` 由 `n/a` 填充为：
  - `none`：ARC + 栈候选且无 deinit/self 捕获/环；
  - `return`：ARC 但不可栈；
  - `other`：GC。
  供 E4/E5 消费；`xnull policy` 直接可见。
- **测试**：`impl/internal/sema/policy_escape_test.go`；`TestPolicyTable` 期望同步为填充值。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
- **证据**：`evidence/S3-03pre/`。
- **边界**：栈分配发射在 E4；GC 根/安全点/栈槽位在 E5。
