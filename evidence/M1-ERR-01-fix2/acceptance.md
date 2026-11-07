# ERR-01 QA FAIL 修复（B1 闭包 try / B2 清理体位置）

> 触发：`收件箱/回执箱/CEO1/验收-M1-ERR-01.md`（QA1，FAIL 2 项）
> 基线：`95e1f41`（merge main `7df123d`）　主责：CEO1-RD2　协办：E3（interp 闭包）

## 1) B1：闭包内 try 失败穿透外层函数

- 根因：`impl/internal/interp/values.go` `callClosure` 只恢复 `ctrlReturn`；`ctrlErr` 被原样上抛，穿到外层函数边界。
- 修复：在 `callClosure` 的 recover 中把 `ctrlErr` 转成 `Result` 的 `Err` 值返回（`&Value{K: vResult, R: sig.r}`），闭包内已注册的 `defer`/`errdefer` 由 `execBlock` 按错误路径执行。
- 复验：
  - QA 子用例「闭包 try 失败必须从闭包返回而不是穿透外层」由 FAIL → PASS。
  - 最小复现 `go run ./cmd/xnull run --interp /tmp/closure-try2.x` → exit 0，stdout **三行**：`closure-err:bad` / `after-call` / `outer-ok`（`after/closure-try2.out`）。

## 2) B2：清理体“单条局部声明”诊断位置 0:0

- 根因：`LocalDeclStmt.P` 是零位置，`checkCleanup` 用它报 `ERR-205`。
- 修复：改用局部声明 `Type` 节点的位置（`defer Int x = 1` 指向 `Int`）。
- 复验：`XNULL_RUNTIME=$PWD/runtime go run ./cmd/xnull build /tmp/cleanup-localdecl.x` → exit 1，stderr 为 **`/tmp/cleanup-localdecl.x:2:11: error[ERR-205]`**（`after/cleanup.err`），与 QA 期望 `2:11` 一致；QA sema 用例 `TestQAERR01` **全绿**。

## 3) QA interp 残留 1 条：期望顺序错误，不是实现缺陷

QA 用例「闭包 try 失败不触发外层 errdefer」当前仍 FAIL，实际输出：

```
closure-e
closure-d
handled
after-call
outer-d
outer-ok
```

期望写成 `... after-call, outer-ok, outer-d`。按 S1 §10.3，`f` 的 `defer print("outer-d")` 在 **`f` 返回时**执行，`main` 的 `outer-ok` 在 `f` 返回后才打印，因此 `outer-d` 必须在 `outer-ok` 之前；期望顺序与规范矛盾。实际输出中 **没有 `outer-e`**，即外层 `errdefer` 未被错误触发——B1 的语义目标已达成。本卡不修改 QA 用例；建议 QA 把期望改为 `closure-e/closure-d/handled/after-call/outer-d/outer-ok`。

## 4) 回归

| 项 | 结果 | 文件 |
|---|---|---|
| `go test ./internal/sema -count=1` | rc=0 | `after/sema-full.log` |
| `go test ./internal/interp -count=1` | rc=0 | `after/interp-full.log` |
| 9 示例双路径 | PASS | `after/codegen-examples.log` |
| `go test ./... -timeout 300s` | rc=0 | `after/go-all.log` |
| `go vet ./...` / `gofmt -l .` | rc=0 / 无输出 | `after/vet.log`、`after/gofmt.log` |

## 5) 边界

- B1 改动在 `impl/internal/interp/values.go`（E3 域），按本次指令协办；未改 `internal/interp` 其他逻辑。
- 未改 QA 测试文件（临时拷入复验后已删除，不入提交）。
- 编译路径的闭包 `try` 仍受 codegen 闭包支持面限制，不在本卡。
