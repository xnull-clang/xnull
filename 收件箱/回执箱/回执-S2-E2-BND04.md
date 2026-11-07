# 回执：S2-E2-BND04（结构体值规则）

- **卡片**：BND-04 结构体值字段/递归/deinit/捕获 self/泛型实参
- **状态**：`DONE`
- **改动**：
  - `impl/internal/sema/typedecl.go`：`isValueTypeRef` 支持泛型结构体声明中的本声明类型参数；泛型结构体实例逐实参做值类型检查；新增 `checkValueInstantiation`。
  - `impl/internal/sema/ty.go`：顶层字段、参数/返回、局部声明位置调用泛型结构体实参校验。
  - 测试：`impl/internal/sema/s2_bnd04_test.go`（声明合法、`Pair<Int,Int>`、`Pair<String,Int>` 字段/局部拒绝、元组实参、`List<T>` 拒绝）。
- **红→绿**：`evidence/S2-BND04/before/sema.out` exit 1 → `after/sema.out` exit 0。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
- **边界**：复制语义/运行期布局不在本卡；泛型结构体实例化后的字段布局归 BND-11/E4。
