# 验收：S2-MEM-02（混合引用图）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `c4361f6`（含 E5 `9e90d4e` MEM-01/02、`bbeca42` BND-10、E4 `a34a392` BND-10b；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-02/`、`.../QA-E5b/runtime-build.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| ARC ↔ GC 互引不悬挂/不泄漏 | **PASS**：`test_gc.c` 不变量 2/3/6 |
| 弱引用目标终结前清除、终结后读不到 | **PASS**：`test_hard.c` |
| 弱引用不阻止 GC 回收；槽位可复用 | **PASS**：`test_hard.c` |
| 引用环由 GC 回收（直接自环 / 两对象环） | **PASS**：CLI 双路径 + `test_gc.c` 不变量 5 |
| 全 ARC 环被避免（直接类字段） | **PASS**：策略 `policy=gc, refCycle=true` |
| 混合图 15.6 六条不变量 | **PASS**：`test_gc.c` + `TestBND10GCMixedARCFieldValid` |
| 容器中介的引用环 | **边界**：策略仍判 ARC，但 codegen 对容器字段赋值显式拒绝（B2），无执行期泄漏路径 |

**判定：PASS。** MEM-02 的运行时混合图不变量与弱引用/环回收均成立。  
**边界**：`class Node { List<Node> next; }` 的 `refCycle=false, policy=arc`；`a.next = [a]` 在 codegen 报「容器字段赋值需要引用语义容器（B2 范围）」，程序不可执行，因此当前无实际泄漏；容器级环检测归 B2 引用语义容器。

---

## 二、ARC ↔ GC 与混合图

### 2.1 直接自环

夹具：`MEM-02/direct_cycle/source.x`（`Node { Node next }` + `deinit`）

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `main`，rc=0 | **PASS** |
| `run`（编译） | `main\nnode-deinit\nnode-deinit\n`，rc=0 | **PASS** |
| 策略 | `policy=gc, refCycle=true, rule=6` | **PASS** |

### 2.2 两对象环

夹具：`MEM-02/two_cycle/source.x`（`A{b} / B{a}`）

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `main`，rc=0 | **PASS** |
| `run`（编译） | `main\ndB\ndA\n`，rc=0 | **PASS** |
| 策略 | `A`、`B` 均 `policy=gc, refCycle=true` | **PASS** |

### 2.3 混合图（GC 持 ARC / ARC 持 GC）

夹具：`MEM-02/mixed/source.x`（环 `Node` + `Helper`）

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `main`，rc=0 | **PASS** |
| `run`（编译） | `main\nnode-deinit helper\nhelper-deinit\nnode-deinit helper\nhelper-deinit\n`，rc=0 | **PASS** |

`node-deinit` 时 `Helper` 字段仍有效；`helper-deinit` 各执行一次，无重复释放。

---

## 三、弱引用（运行时）

`runtime-build.log` 中 `test_hard.c`：

```text
ok  resurrection detection terminates (fatal handler)
ok  weak slot detached after target death
ok  weak slots (invariant 4, cleared before deinit, reusable)
hard-semantics tests passed
```

覆盖：弱清除先于 deinit；终结后 `rt_weak_get` 返回 NULL；弱槽不阻止 GC 回收；槽位复用。

---

## 四、全 ARC 环

| 场景 | 策略/行为 | 判定 |
|---|---|---|
| 直接类字段环 | `policy=gc, refCycle=true` | **PASS** |
| 两对象类字段环 | 双方 `policy=gc` | **PASS** |
| 容器字段环 `List<Node>` | `policy=arc, refCycle=false`；codegen 拒绝容器字段赋值（B2） | **边界** |

容器级环检测未进入 sema 的 `classRefCycle`（只走直接类字段）；当前由 codegen 显式拒绝容器字段赋值阻断执行。若 B2 开放容器引用赋值，需要先补容器级环检测。

---

## 五、官方用例

| 用例 | 结果 |
|---|---|
| `impl/runtime/test_gc.c`（六套件） | **PASS** |
| `impl/runtime/test_hard.c`（弱引用/复活） | **PASS** |
| `internal/codegen/mem_bnd10_test.go:TestBND10GCMixedARCFieldValid` | **PASS** |
| `TestS2MEM02CycleClassIsGCByPolicy` | **PASS** |

---

## 六、回归

| 项 | 结果 |
|---|---|
| `sh impl/runtime/build_rt.sh` | **PASS**（rt/gc/hard/abi/std/res） |
| `go test ./internal/codegen -run 'TestS2MEM\|TestBND10' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp -count=1` | **PASS** |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

---

## 七、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-02/direct_cycle/`、`two_cycle/`、`mixed/`、`container_boundary/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-02/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/MEM-02/runtime-build.log`
- 断言依据：S2 §15.6、§15.8；S3 §14/§15/§16；§16 MEM-02
