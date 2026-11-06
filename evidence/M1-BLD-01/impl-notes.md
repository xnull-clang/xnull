# M1-BLD-01 实现说明（interp 容器成员契约）

## 修复项

| 缺口 | 修复 | 位置 |
|---|---|---|
| `Map.get` 缺失键 fatal | 返回 `null`（`V?`，§9.5） | `values.go` `callValueMethod` Map 分支 |
| `Map` 键类型过宽 | `canonKey` 仅接受 `Int`/`String`；`Bool`/`Char` 报 `runtimeErr`（§9.5；简单枚举运行时未落地，暂以 Int 编码承接） | `values.go` `canonKey` |
| `List.remove` 返回 `null` | 返回被删元素（§9.4） | `values.go` List 分支 |
| `List.insert` 越界钳制 | `idx < 0 || idx > length` → `fatal`（exit 134）；`idx == length` 仍合法（§9.4） | `values.go` List 分支 |
| `List` 赋值退化为 `Array` | 见下方“白名单限制” | `values.go` `callValueMethod` |

## 白名单限制（必须让验收方知道）

- `List<Int> xs = [1]; xs = [2]` 的赋值发生在 `interp.go` 的 `assignTo`；本卡白名单**不允许改 `interp.go`**（E3 的 TUPLE 卡占用）。
- 采用的最小修复：运行时值为 `vArr`、按 `List` 专有方法（`push/insert/set/get/remove/clear`）使用时，**就地提升**为 `vList`，之后 `xs is List` 为 true。
- 副作用：绕过 sema 的非法程序 `Int[] a = [1]; a.push(2)` 也会被提升（当前 sema 不拒绝数组上的 List 方法）。正常源码路径由 sema 的类型检查约束；**建议后续卡**在 `assignTo` 按声明类型定向，彻底消除此近似。
- `T[]` 自身的 `length/join` 不受影响（不触发提升）。

## 红→绿证据

- 红：`evidence/M1-BLD-01/impl-red-tests.txt`（5 组用例均 FAIL，exit=1）
- 绿：`evidence/M1-BLD-01/impl-green-tests.txt`（5 组用例 PASS，interp 包 61.2% 覆盖）
- 全仓：`evidence/M1-BLD-01/impl-fullrepo-tests.txt`（`go test ./...` exit=0）
- 端到端：`evidence/M1-BLD-01/impl-e2e.txt`（`xnull run --interp`，含 134/1 退出码）
- 哈希/范围：`evidence/M1-BLD-01/impl-sha.txt`

## 未改

`interp.go`、`objects.go`、`sema/**`、`codegen/**`、`runtime/**`、现有测试期望均未改。
