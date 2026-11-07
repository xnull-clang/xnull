# 回执：S2-E2-EXTb / ANNb

## 卡1：EXT-01 补口

- **状态**：`DONE`
- 同包 `singleton`、数据 `enum` 扩展放行。
- 跨包 extension Target（导入路径末段同名）→ `TY-225`，带 file:line:col。
- 证据：`evidence/S2-EXTANNb/ext/`。

## 卡2：ANN-01 补口

- **状态**：`DONE`
- 注解字段初始化式必须编译期常量；参数个数/类型/常量校验。
- 注解不能作类型/值、不能 `new`（`TY-223`）。
- 枚举项与顶层函数参数上的未知注解拒绝。
- 证据：`evidence/S2-EXTANNb/ann/`。

## 共同验证

`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
