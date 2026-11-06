# TYPE-01 假绿复核与修复（可选提升）

> 触发：`收件箱/CEO3/回执-M1-NEG-01.md` 第 5 条 P0
> 落位：`wt/c1-rd2`（`pod/c1-rd2`）　主责：CEO1-RD2
> 范围：`impl/internal/sema/ty.go`（`assignable` 可选提升顺序）+ 新增 `type01_optional_test.go`

## 根因

`assignable` 先按 `from.lit` 走字面量规则，`String` 字面量分支只接受 `to == "String"`，
导致 `String? s = "x"` 在到达可选提升分支前就返回 false（TY-101）。变量赋值 `s = a`
的 `from.lit == 0`，能走到旧的 `T → T?` 分支，所以出现“初始化失败、赋值通过”的假绿裂缝。

## 修复

在精确同型之后、字面量规则之前处理可选目标：

```go
if isOptional(to) {
    if from.lit == 4 { return true }          // null → T?
    if assignable(from, unwrapOpt(to)) { return true } // T → T?（含字面量/容器字面量）
}
```

即“能赋给 T 就能赋给 T?”，删除了原先只比较 `unwrapOpt(to) == from.key` 的窄分支。

## 结果

| 用例 | before | after |
|---|---|---|
| `String? s = "x"` | TY-101 | 通过 |
| `List<Int>? xs = [1]` / `Map<String,Int>? m = ["a": 1]` | TY-101 | 通过 |
| 变量赋值 `s = "x"` / `s = plain` | 通过 | 通过 |
| `String? = 5`、`Int? = "x"`、`Bool? = 1`、`Int = null`、`Double? = 1` | 拒绝 | 仍拒绝 |

原有 `ty_test.go` 期望未改；`go test ./internal/sema -count=1` rc=0。
证据：`before/test.log`、`after/test.log`、`stdout.txt`、`command.txt`、`applied.diff`、`artifact.sha256`。
