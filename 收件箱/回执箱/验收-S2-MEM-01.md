# 验收：S2-MEM-01（对象生命周期）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `c4361f6`（含 E5 `9e90d4e` MEM-01/02、`bbeca42` BND-10、E4 `a34a392` BND-10b；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-01/`、`.../QA-E5b/runtime-build.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| deinit 顺序：用户体先于字段释放（GC 清扫链） | **PASS**：`test_gc.c` 六套件 + deinit 内字段引用计数断言 |
| deinit 顺序：派生 → 父类链 | **PASS**：CLI 双路径 `main/dD/dB` |
| 父类 deinit 链（派生无自定义 deinit） | **PASS**：`main/base-deinit` |
| stack 提升：策略判定 | **PASS**：`ValueOnly stackEligible=true policy=arc`；`NeedsArc stackEligible=false` |
| struct 不进入 ARC/GC | **PASS**：struct 以 C 值类型发射，生成 C 无 `rt_arc_new`/`rt_gc_new`；双路径 `1` |
| 源码 `@arc` / `@gc` 拒绝 | **PASS**：`TY-201` + 位置 |
| 判定表 / 两次判定确定性 | **PASS**：`TestPolicyTable`、`TestPolicyDeterministic` |

**判定：PASS。** MEM-01 的生命周期门成立。  
**边界**：`stack` 分配本身未启用（§2.7 是“可以”的优化，不改变语义）；当前 stack-eligible 类仍按 ARC 分配，`BND-10b` 的 `TestBND10bArcStackCandidate` 明确断言这一点。

---

## 二、deinit 顺序

### 2.1 派生 → 父类（CLI 双路径）

夹具：`evidence/S2-QA/QA-E5b/MEM-01/deinit_derived/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `main\ndD\ndB\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

### 2.2 父类链（派生无自定义 deinit）

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `main\nbase-deinit\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

### 2.3 GC 清扫顺序（运行时）

`runtime-build.log` 中 `gc tests passed (invariants 2/3/5/6)`；`test_gc.c` 第 6 段断言 GC 对象 `deinit` 内 ARC 字段仍有效，清扫在 deinit 之后恰好 release 一次。

---

## 三、stack 提升（判定面）

`xnull policy` 对 `stack_policy/source.x`：

```json
ValueOnly: policy=arc, stackEligible=true,  rule=8
NeedsArc:  policy=arc, stackEligible=false, rule=7
```

有 `deinit` 的类不是 stack 候选；纯值类可作 stack 候选。当前 codegen 仍统一按 ARC 分配（stack 优化未启用），语义不变。**PASS（判定面）**。

---

## 四、struct 不进入 ARC/GC

夹具：`struct P { Int x = 1; } P p = new P()`：

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` / `interp` / `compiled` | rc=0，输出 `1` | **PASS** |
| 生成 C | `typedef struct xn_Struct_P`，无 `rt_arc_new`/`rt_gc_new` | **PASS** |

`alloc.txt` 仅含 `typedef struct xn_Struct_P`，无 ARC/GC 分配记录。

---

## 五、源码策略注解

| 用例 | 实测 | 判定 |
|---|---|---|
| `@arc class C` | `TY-201`: 源码不得使用 `@arc`（§15.1.2） | **PASS** |
| `@gc class C` | `TY-201`: 源码不得使用 `@gc`（§15.1.2） | **PASS** |

---

## 六、官方用例

| 用例 | 结果 |
|---|---|
| `internal/sema/policy_test.go:TestPolicyTable` | **PASS** |
| `TestPolicyDeterministic` | **PASS** |
| `TestPolicySelfCaptureScan` | **PASS** |
| `TestPolicyStructSelfCapture` | **PASS** |
| `TestPolicyInternalAnnos` | **PASS** |
| `internal/codegen/mem01_test.go:TestS2MEM01DeinitOrderBaseChain` | **PASS** |
| `TestS2MEM01StackPolicyClassification` | **PASS** |
| `TestS2MEM01StructNotInARCGC` | **PASS**（E4 struct 落地后已改为断言“无 ARC/GC 分配”） |

---

## 七、回归

| 项 | 结果 |
|---|---|
| `sh impl/runtime/build_rt.sh` | **PASS**（rt/gc/hard/abi/std/res 六套件） |
| `go test ./internal/codegen -run 'TestS2MEM\|TestBND10' -count=1` | **PASS** |
| `go test ./internal/sema -run 'TestPolicy' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp -count=1` | **PASS** |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

---

## 八、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-01/deinit_base/`、`deinit_derived/`、`stack_policy/`、`struct_no_arcgc/`、`arc_reject/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-01/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/runtime-build.log`、`codegen-mem.log`、`sema-policy.log`、`sema-interp-full.log`、`vet.log`
- 断言依据：S2 §6.4、§15.1、§15.4、S3 §8/§14/§15、§16 MEM-01
