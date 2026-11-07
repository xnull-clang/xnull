# 集成复核 P1：pod/c2-rd1 → main@9f5f66c

> 证据目录：`evidence/INTEG-c2-rd1/`
> 被测树：main `9f5f66c`（`impl/` 工作区干净，0 个改动文件）
> 分支：`pod/c2-rd1` @ `0f227e4`（已含于 main，非仅候选）
> 只读复核：未改代码、未改测试、未 commit。

## 结论

**FAIL**（3 项中 1/2 项全通过，第 3 项的一个子项不达标）

| # | 复核项 | 结论 |
|---|---|---|
| 1 | `git merge-base --is-ancestor 0f227e4 9f5f66c` | **PASS**（exit 0） |
| 2 | `go vet ./...` / `go test ./... -count=1 -timeout 300s` / `bash impl/runtime/build_rt.sh` | **PASS**（均 exit 0） |
| 3a | BLD-01 `Map.get` / `getOr` 缺失键行为 | **PASS** |
| 3b | BLD-01 `List.remove` / `insert` 返回值与边界 | **PASS** |
| 3c | BLD-01 赋值保持种类 | **FAIL** |
| **总判定** | | **FAIL** |

## 失败命令与原始输出

命令（工作目录 `$TMPDIR/bldprobe`，二进制由 main `9f5f66c` 干净树 `go build ./cmd/xnull` 产出）：

```
xnull run --interp a_assign.x
```

`a_assign.x`：

```x
static Int main() {
    List<Int> xs = [1]
    xs = [2]
    print(xs is List)
    print(xs.length())
    return 0
}
```

原始输出（`evidence/INTEG-c2-rd1/probe.txt` 第 5–10 行）：

```
false
1
exit=0
```

同一条判据更严重的表现（合法程序直接失败）：

```
xnull run --interp e_set.x
```

```x
static Int main() {
    Set<Int> s = [1]
    s = [2]
    print(s is Set)
    s.add(3)
    print(s.length())
    return 0
}
```

原始输出：

```
false
xnull: 该类型没有成员方法 add：Array
exit=1
```

## 判定依据

- 声明初始化会按声明类型定向（`values.go:541 coerceByDecl`），但**赋值路径没有**：`interp.go:1048 assignTo` 的 `IdentExpr` 分支直接 `sc.assign(t.Name, v)`，不做定向。
- 结果：`List<Int> xs = [1]; xs = [2]` 之后运行值种类是 `Array`，`xs is List` 为 `false`。
- List 侧因 `values.go:289` 有「按 List 专有方法就地提升」的补丁，`push/insert/...` 会把种类补回来；**Set 侧没有该补丁**，`add` 直接报错，合法程序不可运行。
- 卡内测试 `TestListAssignmentKeepsList`（`values_test.go:294`）先调用 `xs.push(3)` 再断言 `xs is List`，恰好被上述提升逻辑掩盖，未直接验证「赋值后种类」。
- 该限制在 `evidence/M1-BLD-01/impl-notes.md`「白名单限制」中已披露，属卡内已知近似，不是本次合入新引入的回归。

## 是否建议回退

**不建议回退整条集成。** 理由：门禁三项全绿、无测试回归；缺陷是卡内既有且已书面披露的近似，回退整条合并的代价大于前向修复。

**建议动作**：BLD-01 维持台账「部分」，不得关闭；开一张修复卡在 `assignTo` 按目标声明类型定向（List/Set 同路径），并补两条直接断言用例：

1. `List<Int> xs=[1]; xs=[2]; print(xs is List)` → `true`；
2. `Set<Int> s=[1]; s=[2]; s.add(3)` → 正常执行，`length()==2`。

## 附加观察（不影响本判定，供修复卡参考）

- `Map<Bool,Int>` / `Map<Char,Int>` 当前是**运行期**错误（exit 1），S1 §9.5 要求「其他键类型是编译错误」。属 sema 泛型实参校验缺口，不是本卡引入。
- `Map` 重新赋值保持种类（`h_map_assign.x`：`true` / `2`），因为 Map 字面量本身求值为 `vMap`，不经过 Array 降级；同一问题只影响 List/Set。

## 证据清单

| 文件 | 内容 |
|---|---|
| `ancestor.txt` | is-ancestor 结果与 exit |
| `go-vet.txt` | `go vet ./...`，exit 0 |
| `go-test-all.txt` | 全仓 `go test ./... -count=1 -timeout 300s`，exit 0（cli 70.2s / codegen 115.0s / ffi 43.0s / interp 3.5s / sema 7.0s） |
| `build-rt.txt` | `build_rt.sh`，exit 0（rt/gc/hard/abi/std/资源表全通过） |
| `bld01-tests.txt` | BLD-01 五个用例 -v 全 PASS |
| `probe.txt` | 11 个独立探针原始输出（含失败两项） |
| `probe/*.x` | 探针源码 |
| `sha256.txt` | 二进制与全部证据 SHA-256 |
