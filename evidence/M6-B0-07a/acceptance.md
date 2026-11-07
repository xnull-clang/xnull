# M6-B0-07a sema 自检

- 卡片：M6-B0-07a（sema）
- 目标：按 S1 §2.6 支持整数字面量到 `Int32`/`Int64` 目标类型的适配；越界报错；比较同族同宽。
- 变更：`impl/internal/sema/ty.go`；新增 `impl/internal/sema/numeric_variant_test.go`。未改既有测试期望。

## 规则

1. `Int32`/`Int64`（及 S7 定宽 `Int8/16/32/64`、`UInt8/16/32/64`）纳入整数类型集合。
2. 整数字面量按目标宽度检查：`Int32` 范围 `[-2^31, 2^31-1]`，`Int64` 范围 `[-2^63, 2^63-1]`；越界 `TY-101`。
3. 一元 `-` 保留字面量值，`-2147483648` 可表示；`-2147483649` 拒绝。
4. 比较：整数字面量按另一侧整数类型适配后比较；仍要求同族同宽；不同宽度/不同数值类型（如 `Int32` vs `Int64`、`Int32` vs `Int`）报 `TY-105`。
5. 仅无后缀整数字面量（默认 `Int`）参与比较适配；`5L` 等显式后缀不隐式转换。
6. `Byte`/`Short`/`Int`/`Long` 等既有类型沿用历史行为，不扩大本卡语义面。

## 用例

| 用例 | 期望 | 结果 |
|---|---|---|
| `Int32 code = 0` / `Int64 got = 0` | 无诊断 | PASS |
| `code != 0 || got < 0` | 无诊断 | PASS |
| Int32 min/max、Int64 min/max 字面量 | 无诊断 | PASS |
| `Int32 = 2147483648` / `-2147483649` | `TY-101` | PASS |
| `Int64 = 9223372036854775808` | `TY-101` | PASS |
| `Int32 < 2147483648` | `TY-105` | PASS |
| `Int32` vs `Int64`、`Int32` vs `Int` | `TY-105` | PASS |
| `Int32 < 5L` | `TY-105` | PASS |

## 验证

- 红：`before/sema.out`，exit 1，原报错 `Int 不能赋给 Int32/Int64` + `TY-105 Int32/Int64 vs Int`。
- 绿：`after/sema-target.out` exit 0；`after/sema-all.out` exit 0。
- `go test ./... -count=1 -timeout 600s` → 全绿，exit 0；`go vet ./...` exit 0。
- B0-06 `p6_numeric.x`：解释路径 exit 0（输出 `0\n0`），`TY-101/TY-105` 清零。
- B0-06 `read_parse_write.x`：解释路径 `TY-101/TY-105` 计数 **0**；剩余 `RES-101`（Bytes/ffi 名称）属其他域。

## 边界

- `xnull build`（codegen 路径）编译 p6 仍报 `codegen：类型 Int32 未支持（M4.1 范围）`；按卡面本卡只负责 sema，codegen 值映射属 E4。
- 未支持 `Int32`/`Int64` 的算术结果类型推断之外的新语义；未改 `status.tsv`。

## 证据

`evidence/M6-B0-07a/`（七件套 + `before/` + `after/` + `b0-06/`）。
