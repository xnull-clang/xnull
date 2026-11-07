# 验收-INTEG-e2-sema（集成复核 P1）

> **复核人**：CEO1-QA2-回归　**对象**：pod/e2-sema，main `9f5f66c`，分支 tip `5cfc248`
> **方式**：`git archive 9f5f66c` 干净导出，只读复核；未改仓库代码/测试
> **日期**：2026-11-07

## 结论：FAIL

必需命令全绿，TUPLE 全绿；**B0-07a numeric 的 Int64 负向越界未被拦截**，5 个独立边界探针全部静默通过。

---

## 1. 必需检查

| 检查 | 命令 | 结果 |
|---|---|---|
| 祖先关系 | `git merge-base --is-ancestor 5cfc248 9f5f66c` | **TRUE**（exit 0） |
| 分支 tip | `git merge-base --is-ancestor pod/e2-sema 9f5f66c` | TRUE（exit 0） |
| 静态检查 | `cd impl && go vet ./...` | exit 0 |
| 全量测试 | `go test ./... -count=1 -timeout 300s` | exit 0；10 包全 ok（cli 73.7s / codegen 111.3s / ffi 45.4s / sema 10.3s / interp 12.4s / xfront 9.2s / xpd 8.5s / devtool 7.1s / diag 7.8s） |
| C 运行时 | `bash impl/runtime/build_rt.sh` | exit 0（hard-semantics/abi/std/资源表全通过） |

---

## 2. 重点复核

### 2.1 TUPLE 语义：PASS

| 项 | 命令 | 结果 |
|---|---|---|
| sema 元组 13 用例 | `go test ./internal/sema -run TestTuple -count=1 -v` | 13/13 PASS |
| interp 元组 9 用例 | `go test ./internal/interp -run TestTuple -count=1 -v` | 9/9 PASS |
| 独立运行时探针 | `go test ./internal/interp -run TestQA2TupleRuntimeProbe -v` | PASS：`==/!=/===/!==`、元素赋值后相等性、嵌套元组 |
| 独立 sema 探针 | 嵌套元组可赋值、元素类型不兼容 `TY-101`、元组比较 `TY-105`、错误类型元素赋值 `TY-101` | 4/4 PASS |

### 2.2 B0-07a numeric：既有用例 PASS，独立边界 FAIL

既有 3 个用例（`TestNumericVariant*`）全 PASS，覆盖正向上界与 Int32 负向越界；**未覆盖 Int64 负向越界**。

独立边界探针（`probe/probe-int64-negative-overflow.out`）：

| 用例 | 期望 | 实际 |
|---|---|---|
| `Int64 v = -9223372036854775809` | `TY-101` | **无诊断** ❌ |
| `Int64 v = -9223372036854775810` | `TY-101` | **无诊断** ❌ |
| `if (a > -9223372036854775809)` | `TY-105` | **无诊断** ❌ |
| `if (a >= -9223372036854775809)` | `TY-105` | **无诊断** ❌ |
| `if (a == -9223372036854775809)` | `TY-105` | **无诊断** ❌ |

对照通过项：`Int64 = 9223372036854775807` / `-9223372036854775808` 合法；`Int64 = 9223372036854775808` 报 `TY-101`；Int8/16/32、UInt8/32 上下界均正确。

**根因**：`impl/internal/sema/ty.go:778-781` 一元 `-` 对无符号字面量直接 `-int64(t.uintVal)`。`9223372036854775809`（2^63+1）转 `int64` 回绕为 `-9223372036854775807`，再取负得 `MaxInt64`，于是 `intLiteralFits` 判为可表示。

**引入提交**：`90be44e`（M6-B0-07a sema），非合并冲突引入。

---

## 3. 失败命令与原始输出

```bash
cd /tmp/integ-e2/impl   # git archive 9f5f66c
go test ./internal/sema -run TestQA2Int64NegativeOverflowProbe -count=1 -v
```

```
=== RUN   TestQA2Int64NegativeOverflowProbe
=== RUN   TestQA2Int64NegativeOverflowProbe/assign-min-1
    qa2_probe2_test.go:16: diags=[]
    qa2_probe2_test.go:18: 越界字面量被静默接受：期望 TY-101/TY-105，实际无诊断
=== RUN   TestQA2Int64NegativeOverflowProbe/assign-min-2
    qa2_probe2_test.go:16: diags=[]
    qa2_probe2_test.go:18: 越界字面量被静默接受：期望 TY-101/TY-105，实际无诊断
=== RUN   TestQA2Int64NegativeOverflowProbe/cmp-gt-min-1
    qa2_probe2_test.go:16: diags=[]
    qa2_probe2_test.go:18: 越界字面量被静默接受：期望 TY-101/TY-105，实际无诊断
=== RUN   TestQA2Int64NegativeOverflowProbe/cmp-ge-min-1
    qa2_probe2_test.go:16: diags=[]
    qa2_probe2_test.go:18: 越界字面量被静默接受：期望 TY-101/TY-105，实际无诊断
=== RUN   TestQA2Int64NegativeOverflowProbe/cmp-eq-min-1
    qa2_probe2_test.go:16: diags=[]
    qa2_probe2_test.go:18: 越界字面量被静默接受：期望 TY-101/TY-105，实际无诊断
--- FAIL: TestQA2Int64NegativeOverflowProbe (0.00s)
    --- FAIL: TestQA2Int64NegativeOverflowProbe/assign-min-1 (0.00s)
    --- FAIL: TestQA2Int64NegativeOverflowProbe/assign-min-2 (0.00s)
    --- FAIL: TestQA2Int64NegativeOverflowProbe/cmp-gt-min-1 (0.00s)
    --- FAIL: TestQA2Int64NegativeOverflowProbe/cmp-ge-min-1 (0.00s)
    --- FAIL: TestQA2Int64NegativeOverflowProbe/cmp-eq-min-1 (0.00s)
FAIL
FAIL	xnull.dev/xnull/internal/sema	0.873s
FAIL
```

---

## 4. 是否建议回退

**不建议整体回退 pod/e2-sema。** 理由与范围：

1. TUPLE 语义、全仓测试、C 运行时均全绿；整体回退会连带回滚已验证通过的 TUPLE/B0-05 等工作，回归面更大。
2. 该缺陷是**诊断漏报**（越界字面量静默接受），不崩溃、不改运行时数据；当前 codegen 尚不支持 Int32/Int64（卡面已声明边界），影响面限于 sema 诊断。
3. 建议**定点修复后复验**：一元 `-` 对 `uintVal > 1<<63` 的字面量标记越界（使 `intLiteralFits` 返回 false），并补 5 条边界用例（赋值 min-1/min-2 + 比较 3 例）。
4. 若门禁策略要求"FAIL 即回退"，**只回退 `90be44e`/`2c0c191`（B0-07a numeric）**，保留 TUPLE 与其余集成；代价是 p6 numeric 回到 `TY-101`，B0-07a 重新开卡。

---

## 5. 未跑 / 边界

1. 未跑 codegen 级 Int32/Int64（E4 域，卡面明确未支持）。
2. 未跑 B0-06 的 `p6_numeric.x` 端到端（该文件不在仓库，仅有 `evidence/M6-B0-07a/b0-06/` 输出留档）。
3. 未跑覆盖率、变异、性能（不属本次 P1 集成复核面）。
4. 未验证 UInt64 上界 `2^64-1` 与 `2^64` 解析边界（超出 B0-07a 卡面枚举，另列风险）。

---

## 6. 证据

`evidence/INTEG-e2-sema/`：

- `ancestor.out`（两条祖先检查）
- `vet.out`、`go-test.out`、`build-rt.out`
- `focus-sema.out`、`focus-interp-tuple.out`
- `probe/probe-sema.out`、`probe/probe-interp-tuple.out`、`probe/probe-int64-negative-overflow.out`
- `probe/qa2_probe_test.go`、`probe/qa2_probe2_test.go`、`probe/interp_probe_test.go`（独立探针源码）
- `command.txt`、`exit_code.txt`、`sha.txt`、`summary.md`

---

# 最终复核（main=f63fcba）

## 结论：PASS

> **复核树**：`git archive f63fcba`（只读）
> **e2-sema 集成**：`49cbb27`（merge pod/e2-sema，SYNCED `9848d06`）
> **修复提交**：`92ef021`（`fix(sema): Int64 负向越界禁止补码回绕`），`git merge-base --is-ancestor 92ef021 f63fcba` = exit 0
> **覆盖关系**：本次 PASS 覆盖前次在 `9f5f66c` 上的 FAIL；缺陷已修复并复验。

## 1. 全量门禁

| 命令 | 结果 |
|---|---|
| `cd impl && go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 300s` | exit 0；10 包全 ok（cli 36.7s / codegen 51.7s / ffi 27.9s / interp 6.1s / sema 7.5s / xfront 8.3s / xpd 9.4s / devtool 3.2s / diag 2.0s） |
| `bash impl/runtime/build_rt.sh` | exit 0（hard-semantics / abi / std / 资源表全通过） |

## 2. Int64 负向越界 5 探针（上轮失败项）

命令：`go test ./internal/sema -run TestQA2Int64NegativeOverflowProbe -count=1 -v`

| 探针 | 期望 | `f63fcba` 实际 |
|---|---|---|
| `Int64 v = -9223372036854775809` | `TY-101` | PASS |
| `Int64 v = -9223372036854775810` | `TY-101` | PASS |
| `if (a > -9223372036854775809)` | `TY-105` | PASS |
| `if (a >= -9223372036854775809)` | `TY-105` | PASS |
| `if (a == -9223372036854775809)` | `TY-105` | PASS |

**5/5 PASS**（`0.00s`，无诊断漏报）。**精确码复核 6/6 PASS**：3 个赋值场景均 `TY-101`、3 个比较场景均 `TY-105`，并含 `Int64 v = -18446744073709551615`（`probe/probe-int64-exact-codes.out`）。修复实现：`ty.go` 新增 `intBad` 标记；仅 `2^63` 映射 `MinInt64`，更大负量级禁止回绕；`-MinInt64` 同样标记不可表示。`numeric_variant_test.go` 已补 4 条边界用例。

其他 numeric 边界（独立探针）：Int8/16/32、UInt8/32 上下界、Int64 正向上界、字面量比较适配，全部 PASS。

## 3. TUPLE 回归

| 项 | 结果 |
|---|---|
| sema 元组用例 | 13/13 PASS |
| interp 元组用例 | 9/9 PASS |
| 独立运行时探针（==/!=/===/!==、元素赋值、嵌套） | PASS |
| 独立 sema 探针（嵌套赋值、错误元素类型、元组比较） | PASS |

## 4. 失败命令

无。上述所有命令 exit 0。

## 5. 残余风险 / 未跑

1. codegen 级 Int32/Int64 仍未支持（B0-07a 卡面已声明属 E4；本次只验 sema）。
2. `UInt64 > 2^64-1` 的解析边界未测（超出本卡枚举）。
3. 未跑覆盖率、变异、性能（不属本次集成复核面）。
4. `-9223372036854775810` 已在修复测试中覆盖；更大的负向字面量（如 `-18446744073709551615`）也已补入 `numeric_variant_test.go`，本次随全量测试通过。

## 6. 证据

`evidence/INTEG-final-e2/`：
- `ancestor.out`（`92ef021` / `5cfc248` / `49cbb27` 均在 `f63fcba`）
- `vet.out`、`go-test.out`、`build-rt.out`
- `focus-sema.out`、`focus-interp-tuple.out`
- `probe/probe-sema.out`（5 探针 + numeric 边界 + tuple）
- `probe/probe-interp-tuple.out`
- `probe/qa2_probe_test.go`、`probe/qa2_probe2_test.go`、`probe/interp_probe_test.go`
- `command.txt`、`exit_code.txt`、`sha.txt`、`summary.md`
