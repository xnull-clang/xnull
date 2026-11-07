# M6-B0-05 sema 会签自检

- 卡片：M6-B0-05（sema 一处）
- 目标：`List.remove(index)` 的静态返回类型从 `void` 改为被删元素类型 `V`（`genericArg(k, "List<")`）。
- 变更文件：`impl/internal/sema/ty.go`；新增 `impl/internal/sema/list_remove_test.go`。
- 未改既有测试期望、未删测试。

## 用例

| 用例 | 期望 | 结果 |
|---|---|---|
| `List<Int>.remove(0)` → `Int` | 无诊断 | PASS |
| `List<String>.remove(1)` → `String` | 无诊断 | PASS |
| `xs.remove(0)` 作语句丢弃返回值 | 无诊断 | PASS |
| `List<Int>.remove(0)` → `String` | `TY-101` | PASS（负例） |

## 命令与结果

- 红：`go test ./internal/sema/ -run TestListRemoveReturnsElement -v -count=1` → exit 1，`void 不能赋给 Int`
- 绿：同命令 → PASS，exit 0
- `go test ./internal/sema/ -count=1` → PASS
- `go test ./internal/interp/ ./internal/codegen/ -count=1` → PASS
- `go test ./... -count=1 -timeout 600s` → 全部 PASS，exit 0
- `go vet ./...` → exit 0

## 边界

- 本卡只改 sema 静态返回类型。解释器当前 `List.remove` 仍返回 `vNull`、codegen 仍生成 `void` 调用；按卡面要求由 E3/E4 同批提交值返回，未在本 worktree 跨域修改。
- 在该同批落地前，`Int v = xs.remove(0)` 会通过 sema 但解释器路径得到 null；这是预期的批次中间态，不是 sema 缺陷。

## 证据

`evidence/M6-B0-05-sema/`（command.txt、stdout.txt、stderr.txt、exit_code.txt、artifact.sha256、sha.txt、acceptance.md）+ `before/` + `after/`。
