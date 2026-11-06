# 回执-M1-TUPLE-01（E2 / wt-e2-sema）

1. **结论**：TUPLE-01 台账验收要点 11/11 全绿；先红后绿，红/绿原始输出齐全。
2. **变更**：`sema/ty.go`（元组类型身份/字面量适配/`TY-106`/越界/成员/switch/插值/as）、`interp/interp.go`+`values.go`（元素赋值、`?.N`、`==/!=/===/!==`、元组值复制）。
3. **测试**：新增 `sema/tuple_test.go`（13 用例）、`interp/tuple_test.go`（3 用例）；未改现有测试期望、未删测试。
4. **验证**：`go test ./... -count=1` 全绿、`go vet ./...` exit 0；既有 9 示例双路径 9/9 stdout 一致、退出码一致。
5. **证据**：`evidence/M1-TUPLE-01/` 七件套（command/stdout/stderr/exit_code/artifact.sha256/sha/acceptance）+ `before/` 红输出 + `dualpath/` + `cli/`；台账状态留待 QA1/CEO1 独立验收。

## 逐项打勾（台账验收要点）

- [x] T1 类型身份
- [x] T2 字面量
- [x] T3 元素访问
- [x] T4 推断
- [x] T5 可赋值性
- [x] T6 相等与插值
- [x] T7 越界选择器被拒绝
- [x] T8 单元素/零元元组被拒绝
- [x] T9 解构被拒绝
- [x] T10 元组 switch 被拒绝
- [x] T11 元组 const 被拒绝

## 未测项

- 元组作为顶层函数返回类型/顶层字段：`xfront.parseTopType` 不支持，属语法域，未跨域修改。
- 可空元组声明 `(T1,T2)?`：parser 不接受 `)` 后 `?`；`?.N` 已在非空元组上测通，null 接收者未测。
- 元组进入容器/泛型实参/闭包捕获的专项用例，以及容器插入时的值复制。
- 编译路径（codegen）元组：现有 codegen 无元组实现，未新增元组示例；双路径仅回归既有 9 示例。
- 台账 `status.tsv` 仍为“部分”，按流程由 QA/CEO 更新，执行侧不手改。

## 声明

执行侧自检，不构成验收签署；未 push、未合并，未触碰其他锚点文件。
