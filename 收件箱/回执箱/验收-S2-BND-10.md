# 验收：S2-BND-10（内存策略 → 运行时行为）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `c4361f6`（含 E5 `bbeca42` BND-10、E4 `a34a392` BND-10b；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/BND-10/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 判定表决定分配：引用环类 → GC | **PASS**：`rt_gc_new(&RT_TYPE_XN_Node)`；环退出时回收 |
| 非环纯值类保持 ARC | **PASS**：`rt_arc_new(&RT_TYPE_XN_Plain)` |
| stack 候选类保持 ARC（栈优化未启用时身份不变） | **PASS**：`TestBND10bArcStackCandidate` |
| 数据枚举项 → GC + 全局根 | **PASS**：`rt_gc_new(&RT_TYPE_XN_ENUM_Status)` + `rt_gc_root_add` |
| 单例实例 → GC + 全局根 | **PASS**：`rt_gc_new(&RT_TYPE_XN_SINGLE_AppInfo)` + `rt_gc_root_add` |
| 混合图 15.6：GC 持 ARC，deinit 时字段有效，sweep 释放一次 | **PASS**：CLI `node-deinit helper` ×2、`helper-deinit` ×2 |
| 源码 `@arc` / `@gc` 拒绝 | **PASS**：`TY-201` + 位置 |
| 策略/槽位/构建确定性 | **PASS**：`TestPolicyDeterministic` |
| BND-10b 三类全局根 / stack 候选回归 | **PASS**：`TestBND10b*` 三例 |

**判定：PASS。** 策略已从 sema 传到 codegen：环类走 GC、非环类 ARC、数据枚举/单例走 GC 并登记全局根；混合图 deinit/释放顺序正确。台账 BND-10 可登记为 PASS。

---

## 二、策略 → 分配

| 用例 | 生成 C 分配 | 运行结果 | 判定 |
|---|---|---|---|
| `direct_cycle`（`Node { Node next }` 环） | `rt_gc_new(&RT_TYPE_XN_Node)` | `main\nnode-deinit\nnode-deinit\n` | **PASS** |
| `plain`（`Plain { Int x }` 非环） | `rt_arc_new(&RT_TYPE_XN_Plain)` | `1\n` | **PASS** |
| `dataenum_root`（`enum Status { Ready(0) }`） | `rt_gc_new(&RT_TYPE_XN_ENUM_Status)` + `rt_gc_root_add(xn_enum_Status_Ready)` | `0\n` | **PASS** |
| `singleton_root`（`singleton AppInfo`） | `rt_gc_new(&RT_TYPE_XN_SINGLE_AppInfo)` + `rt_gc_root_add(xn_single_AppInfo)` | `3\n` | **PASS** |

策略判定：`direct_cycle` 的 `Node` 为 `policy=gc, refCycle=true, rule=6`；`plain` 为 ARC。

---

## 三、混合图（15.6）

夹具：`BND-10/mixed/source.x`（环 `Node` + `Helper`）

```text
main
node-deinit helper
helper-deinit
node-deinit helper
helper-deinit
```

- `Node.deinit` 执行时 `Helper` 字段仍有效（`node-deinit helper`）。
- `Helper` 由 sweep 释放，执行一次 `helper-deinit`，无重复释放/悬挂。
- 运行时 `test_gc.c` 六套件覆盖不变量 2/3/5/6。

---

## 四、BND-10b 回归

| 用例 | 断言 | 结果 |
|---|---|---|
| `TestBND10bDataEnumGlobalRoot` | 数据枚举 `rt_gc_new` + `rt_gc_root_add`；运行 `0` | **PASS** |
| `TestBND10bSingletonGlobalRoot` | 单例 `rt_gc_new` + `rt_gc_root_add`；运行 `3` | **PASS** |
| `TestBND10bArcStackCandidate` | stack 候选 `Plain` 保持 `rt_arc_new`，不走 GC；运行 `1` | **PASS** |

---

## 五、边界与残余风险

1. **stack 分配未启用**：stack-eligible 类仍按 ARC 分配（§2.7 许可优化，语义不变），`TestBND10bArcStackCandidate` 明确断言。
2. **容器元素为 GC 类型**：显式拒绝（容器级扫描/释放归 B2）；容器中介的引用环当前策略判 ARC，但 codegen 拒绝容器字段赋值，无执行期泄漏路径。
3. **一次 transient fatal（未复现）**：合并窗口内首次复跑 `mixed` 曾出现一次 `复活检测：对已终结对象 retain`；在 `c4361f6` 复验二进制上 `mixed` 连续 100 次 CLI 运行 0 失败，`TestBND10GCMixedARCFieldValid` PASS。见 `BND-10/mixed/stability.log`；建议后续加入重复运行门禁持续观察。

---

## 六、官方用例

| 用例 | 结果 |
|---|---|
| `internal/codegen/mem_bnd10_test.go:TestBND10GCCycleCollected` | **PASS** |
| `TestBND10GCMixedARCFieldValid` | **PASS** |
| `TestBND10PolicyAllocationKinds` | **PASS** |
| `TestBND10ValueOnlyStaysARC` | **PASS** |
| `TestBND10bDataEnumGlobalRoot` | **PASS** |
| `TestBND10bSingletonGlobalRoot` | **PASS** |
| `TestBND10bArcStackCandidate` | **PASS** |
| `internal/sema/policy_test.go:TestPolicyTable/TestPolicyDeterministic/TestPolicyInternalAnnos` | **PASS** |
| `impl/runtime` 六套件（rt/gc/hard/abi/std/res） | **PASS** |

---

## 七、回归

| 项 | 结果 |
|---|---|
| `sh impl/runtime/build_rt.sh` | **PASS** |
| `go test ./internal/codegen -run 'TestS2MEM\|TestBND10' -count=1` | **PASS** |
| `go test ./internal/sema -run 'TestPolicy' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp -count=1` | **PASS** |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

---

## 八、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/BND-10/direct_cycle/`（含 `alloc.txt`、`policy.json`）、`plain/`、`mixed/`、`dataenum_root/`、`singleton_root/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/BND-10/matrix.tsv`、`mixed/stability.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-E5b/runtime-build.log`、`codegen-mem.log`、`sema-policy.log`、`sema-interp-full.log`、`vet.log`
- 断言依据：S2 §2.7、§15.1、§15.6、§15.8；S3 §8/§15.6；`impl/docs/runtime-contract.md` P-09；§16 BND-10
