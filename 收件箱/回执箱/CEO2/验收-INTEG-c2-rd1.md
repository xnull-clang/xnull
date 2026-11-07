# 回执 验收-INTEG-c2-rd1（集成复核 P1）

> 卡：INTEG-c2-rd1　复核人：CEO2-QA1-运行时
> 被测树：`main` = **`9f5f66c`**（`impl/` 工作区干净，0 改动）
> 被复核分支：`pod/c2-rd1` @ **`0f227e4`**（已含于 main）
> 日期：2026-11-07　性质：只读复核（未改代码/测试/期望，未 commit，未派工）
> 证据：`evidence/INTEG-c2-rd1/`
>
> **状态提示：§一 总判定（FAIL）针对 `9f5f66c`；`8a50e84` 追加复核见 §七（PASS）；`f63fcba` 集成最终复核见 §八（PASS，以该节为准）。**

## 一、结论

**FAIL**

| # | 复核项 | 结论 |
|---|---|---|
| 1 | `git merge-base --is-ancestor 0f227e4 9f5f66c` | **PASS** |
| 2 | `go vet ./...` / `go test ./... -count=1 -timeout 300s` / `bash impl/runtime/build_rt.sh` | **PASS** |
| 3a | BLD-01 `Map.get` / `getOr` 缺失键行为 | **PASS** |
| 3b | BLD-01 `List.remove` / `insert` 返回值与越界 | **PASS** |
| 3c | BLD-01 赋值保持种类 | **FAIL** |
| **总判定** | | **FAIL** |

## 二、命令与原始输出

### 2.1 祖先检查（PASS）

```
$ git merge-base --is-ancestor 0f227e4 9f5f66c
$ echo $?
0
```

（`evidence/INTEG-c2-rd1/ancestor.txt`）

### 2.2 三项门禁（PASS）

```
$ cd impl && go vet ./...
vet exit=0

$ cd impl && go test ./... -count=1 -timeout 300s
ok  xnull.dev/xnull/internal/cli            70.180s
ok  xnull.dev/xnull/internal/codegen       115.040s
ok  xnull.dev/xnull/internal/codegen/ffi    42.968s
ok  xnull.dev/xnull/internal/devtool         6.485s
ok  xnull.dev/xnull/internal/diag            2.702s
ok  xnull.dev/xnull/internal/interp          3.456s
ok  xnull.dev/xnull/internal/sema            6.986s
ok  xnull.dev/xnull/internal/xfront          4.651s
ok  xnull.dev/xnull/internal/xpd             7.440s
go-test exit=0

$ bash impl/runtime/build_rt.sh
rt tests passed
gc tests passed (invariants 2/3/5/6)
hard-semantics tests passed
abi 测试通过
std 测试通过
资源表测试通过
build_rt exit=0
```

### 2.3 失败项（FAIL）

二进制由被测树干净构建：`go build -o $TMPDIR/xnull ./cmd/xnull`（`impl/`）。

```
$ xnull run --interp a_assign.x
false
1
exit=0
```

```x
// a_assign.x
static Int main() {
    List<Int> xs = [1]
    xs = [2]
    print(xs is List)
    print(xs.length())
    return 0
}
```

期望：`true` / `1`（赋值后仍为 List）。实际：`false`。

同一根因下，合法程序直接报错：

```
$ xnull run --interp e_set.x
false
xnull: 该类型没有成员方法 add：Array
exit=1
```

```x
// e_set.x
static Int main() {
    Set<Int> s = [1]
    s = [2]
    print(s is Set)
    s.add(3)
    print(s.length())
    return 0
}
```

期望：`true` / `2`。实际：`false` 后 `add` 不可用，exit 1。

## 三、判定依据

1. `interp.go:1048 assignTo` 的 `IdentExpr` 分支直接 `sc.assign(name, v)`，不按目标声明类型定向；定向只在声明初始化走 `coerceByDecl`（`interp.go:415`、`values.go:541`）。因此 `xs = [2]` 把运行值写成 `vArr`。
2. List 侧有补丁：`values.go:289` 在调用 List 专有方法时就地提升为 `vList`。Set 侧无对应补丁，故 `add` 直接失败。
3. 卡内用例 `TestListAssignmentKeepsList`（`values_test.go:294`）先 `xs.push(3)` 再断言 `is List`，被上述提升逻辑救回，**没有直接断言赋值后的种类**；测试设计掩盖了缺口（测试本身不假，结论口径偏松）。
4. `evidence/M1-BLD-01/impl-notes.md`「白名单限制」已书面披露该近似，属卡内已知缺陷，不是本次合入新引入的回归。

## 四、是否建议回退

**不建议回退整条集成。**

- 三项门禁全绿，全仓测试无回归；缺陷局限于解释器容器赋值路径，不涉及内存安全/崩溃。
- 回退会把已合入的 P-09/P-10 之外的 B0 阶段对齐工作一起打回，代价大于前向修复。
- 修复已在兄弟分支存在：`pod/c2-rd2`（`interp.go:156` 增加 `types map[string]xfront.TypeRef` 声明类型表，未合 main）。本轮用该工作树构建只读复测，两个探针均转为期望值：

```
=== c2-rd2 工作树：a_assign ===
true
1
=== c2-rd2 工作树：e_set ===
true
2
```

**建议动作**：BLD-01 维持「部分」，不得关闭/标 PASS；由修复卡（c2-rd2 或后续）合入后在 main 复跑本回执的 2.3 两条命令，再签关闭。

## 五、边界与未测项

1. **codegen 路径未验**：同一组容器探针在 codegen 路径不可执行（`xs = [2]` 报 `Int 表达式 *xfront.ArrayLit 未支持（M4.1 范围）`）。BLD-01 台账本就锚定 `internal/interp/values_test.go`，本复核不据此判负，但双路径一致性不能声称已覆盖。
2. **Map 键类型诊断层级**：main 上 `Map<Bool,Int>` / `Map<Char,Int>` 是运行期错误（exit 1），S1 §9.5 要求编译错误；属 sema 泛型实参校验缺口（c2-rd2 已以 TY-106/TY-107 处理，未合 main），不计入本卡判定。
3. 未跑性能/复杂度基准，未跑端到端示例矩阵（不在本卡范围）。
4. 未改任何测试期望、未改台账。

## 六、证据清单与 SHA-256

| 文件 | 说明 |
|---|---|
| `evidence/INTEG-c2-rd1/ancestor.txt` | 祖先检查 |
| `evidence/INTEG-c2-rd1/go-vet.txt` | vet 输出 |
| `evidence/INTEG-c2-rd1/go-test-all.txt` | 全仓测试输出 |
| `evidence/INTEG-c2-rd1/build-rt.txt` | 运行时套件输出 |
| `evidence/INTEG-c2-rd1/bld01-tests.txt` | BLD-01 五用例 `-v` 全 PASS（暴露第 3 条口径偏松） |
| `evidence/INTEG-c2-rd1/probe.txt` | 11 个独立探针原始输出 |
| `evidence/INTEG-c2-rd1/probe/*.x` | 探针源码 |
| `evidence/INTEG-c2-rd1/summary.md` | 复核摘要 |
| `evidence/INTEG-c2-rd1/sha256.txt` | 二进制与全部证据哈希 |

关键哈希（完整清单见 `sha256.txt`）：

```
d2e87dbbec8513ea4d5090364a4f78214ba761d74dbdee3365db2eeb24705ecb  xnull（被测树构建产物）
64195ffe2511e6e38887d49f867012dc6379c4ad284254b0912c3cf192b4fa23  probe.txt
37d601a29a781f72c6e142186748f19b8ac6fecbfb224c9c1d83969bc7074b07  go-test-all.txt
54062b862f23db05d817c959bea24f76b4a0a2f34a3c27ad0d79e8a0cf56db9b  build-rt.txt
```

---

## 七、追加复核 @8a50e84（2026-11-07）

> 触发：`pod/c2-rd2` 已合入 main（`8a50e84`），原 §一 第 3c 项「赋值保持种类」应复验。
> 取树：`git archive 8a50e84 | tar -x` 到临时干净树（非工作区）；只读，未改代码/测试。
> 被测：`8a50e844fa45e6b8c1ab0ae8acdadc02920def50`（`merge(pod/c2-rd2): SYNCED eaf3c41`）
> 二进制：该树 `go build ./cmd/xnull`，SHA-256 `302619a815e6a07ad65c728e1c527a8042478794969d99c22d799c5bec4d0784`
> 证据：`evidence/INTEG-c2-rd1/rerun-8a50e84/`

### 7.1 结论

**PASS**

| # | 复核项 | 结论 |
|---|---|---|
| 1 | `List<Int> xs=[1]; xs=[2]; xs is List` → `true` | **PASS** |
| 2 | `Set<Int> s=[1]; s=[2]; s.add(3)` → 可用，`length()==2` | **PASS** |
| 3 | BLD 矩阵 28 例（含 c25 `assign_list`、c26 `assign_set`） | **PASS**（28/28 GREEN） |
| 4 | BLD Go 用例（List/Map/Set + get/getOr/remove/insert/赋值保持） | **PASS**（全 PASS） |
| 5 | `go vet ./...` / `go test ./... -count=1 -timeout 300s` / `build_rt.sh` | **PASS**（均 exit 0） |

原 §一 的 FAIL 由本节证据取代；原「不建议回退」的判断不变。

### 7.2 原始输出

```
$ xnull-8a50e84 run --interp a_assign.x
true
1
exit=0

$ xnull-8a50e84 run --interp e_set.x
true
2
exit=0
```

BLD 矩阵（`sh evidence/M1-BLD-01/red/run-red.sh`）：

```
GREEN c25_assign_list           exit=0       54ms
GREEN c26_assign_set            exit=0       51ms
TOTAL=28 RED=0 GREEN=28
```

直接判据（c25/c26 的 fixture 与输出，已复制到证据目录）：

```x
// c25_assign_list.x
List<Int> xs = [1]
xs = [2, 3]
xs.push(4)
print(xs.length())      // 3
```

```x
// c26_assign_set.x
Set<Int> s = [1]
s = [2, 3]
s.add(4)
print(s.length())       // 3
```

门禁：

```
$ cd clean-8a50e84/impl && go vet ./...
vet exit=0

$ go test ./... -count=1 -timeout 300s
ok  internal/cli 27.069s / codegen 37.851s / ffi 19.657s / devtool 2.501s
ok  internal/diag 4.025s / interp 4.662s / sema 5.520s / xfront 6.185s / xpd 7.034s
go-test exit=0

$ bash impl/runtime/build_rt.sh
rt/gc/hard/abi/std/资源表 全通过
build_rt exit=0
```

### 7.3 顺带关闭的原观察项

原 §五 第 2 条（`Map<Bool,Int>` / `Map<Char,Int>` 是运行期错误，规范要求编译错误）已修复：现在编译期报 `error[TY-107]`，exit 1，示例如下（`probes.txt`）：

```
k_boolkey.x:2:5: error[TY-107]: Map 键类型 Bool 不被支持（§9.5：只允许 String、整数类型和简单枚举）
```

### 7.4 边界

1. 本次只复验 `--interp` 路径；codegen 容器路径仍属 M4.x 未覆盖，未在本次范围重验。
2. 未改台账状态；BLD-01 是否关闭仍以 L1/L2 门禁与 CEO2 结论为准。
3. 未回退、未改任何代码或测试期望。

### 7.5 证据清单（本节）

| 文件 | 说明 |
|---|---|
| `rerun-8a50e84/env.txt` | 被测 sha、取树方式、二进制哈希、命令集 |
| `rerun-8a50e84/probes.txt` | 11 个探针原始输出（含 List/Set 赋值两条） |
| `rerun-8a50e84/red-28-summary.txt` / `.tsv` | BLD 28 例矩阵逐例判定 |
| `rerun-8a50e84/c25_assign_list.x` / `.out` | 赋值保持 List（直接用例） |
| `rerun-8a50e84/c26_assign_set.x` / `.out` | 赋值保持 Set（直接用例） |
| `rerun-8a50e84/bld-go-tests.txt` | BLD Go 用例 `-v` |
| `rerun-8a50e84/go-vet.txt` / `go-test-all.txt` / `build-rt.txt` | 门禁原始输出 |
| `rerun-8a50e84/sha256.txt` | 本节全部证据哈希 |

---

## 八、集成最终复核 @f63fcba（2026-11-07）

> 触发：最终集成复核，main = `f63fcba`。
> 取树：`git archive f63fcba | tar -x` 到临时干净树（非工作区）；只读，未改代码/测试。
> 被测：`f63fcba52a763eb6176c2fabe7aedd80352f72a2`（`merge(pod/e3-interp): SYNCED 37cbe18`）
> 二进制：该树 `go build ./cmd/xnull`，SHA-256 `6b6cab4874265f46e64d3ede17813efeb6c4df80dc56abdae5019580b75576b5`
> 证据：`evidence/INTEG-final-c2rd1/`

### 8.1 结论

**PASS**

| # | 复核项 | 结论 |
|---|---|---|
| 1 | BLD 赋值保持种类：List/Set 重赋值后 `push` / `add` 可用 | **PASS** |
| 2 | `Map.get` / `getOr` 缺失键、重复键、整数键 | **PASS** |
| 3 | `List.remove` 返回元素 / `insert` 0..length / 越界 fatal | **PASS** |
| 4 | BLD 矩阵 `run-red.sh` | **PASS**（28/28 GREEN） |
| 5 | `go test ./internal/interp/ -count=1` | **PASS**（ok 4.363s） |

### 8.2 原始输出

```
$ xnull-f63fcba run --interp a_assign.x
true
1
exit=0

$ xnull-f63fcba run --interp e_set.x
true
2
exit=0

$ xnull-f63fcba run --interp d_assign_push.x
true
2
exit=0
```

List 边界（`m_list_edge.x`）：

```
$ xnull-f63fcba run --interp m_list_edge.x
2        # remove(1) 返回被删元素
2        # 删除后 length
9        # insert(0,9) 后 get(0)
8        # insert(length,8) 后 get(length-1)
4        # 最终 length
exit=0

$ xnull-f63fcba run --interp f_bounds.x
xnull: fatal: List.insert 下标越界：len=2, idx=3（§9.4 合法范围 0..length）
exit=134

$ xnull-f63fcba run --interp g_bounds_neg.x
xnull: fatal: List.remove 下标越界
exit=134
```

Map 行为（`b_map.x` / `n_map_edge.x`）：

```
$ xnull-f63fcba run --interp b_map.x
true     # get 缺失键 == null
7        # get 缺失键 ?? 7
9        # getOr 缺失键 fallback
1        # get 存在键
1        # getOr 存在键
false    # has 缺失键
false    # remove 缺失键
true     # remove 存在键
0        # 最终 length
exit=0

$ xnull-f63fcba run --interp n_map_edge.x
b        # 重复键后者覆盖
missing  # get 缺失键 ?? 默认
fallback # getOr 缺失键
true     # has
true     # remove
0        # length
exit=0
```

BLD 矩阵：

```
$ sh evidence/M1-BLD-01/red/run-red.sh
GREEN c25_assign_list           exit=0
GREEN c26_assign_set            exit=0
TOTAL=28 RED=0 GREEN=28
run-red exit=0
```

解释器测试：

```
$ go test ./internal/interp/ -count=1
ok  xnull.dev/xnull/internal/interp  4.363s
interp-test exit=0
```

### 8.3 判定与处置

- §一（`9f5f66c`）的 3c FAIL 在 `8a50e84` 修复、`f63fcba` 保持；本节为最终结论。
- **不回退**；BLD-01 可按 L1/L2 门禁流程推进关闭，最终状态以门禁签署为准。
- 未改台账、未改任何代码或测试期望。

### 8.4 边界

1. 本次按指令只验 `--interp`；codegen 容器路径仍属 M4.x 未覆盖，不在本次范围。
2. `Map<Bool/Char,*>` 编译期 `TY-107` 行为顺带确认，非本节判据。
3. 全部探针与矩阵均在 `git archive` 干净树执行，不依赖工作区未提交状态。

### 8.5 证据清单（本节）

| 文件 | 说明 |
|---|---|
| `evidence/INTEG-final-c2rd1/env.txt` | 被测 sha、取树方式、二进制哈希、命令集 |
| `evidence/INTEG-final-c2rd1/probes.txt` | 13 个探针原始输出 |
| `evidence/INTEG-final-c2rd1/red-28.txt` | 28 例矩阵完整输出（含逐例 GREEN 行与汇总） |
| `evidence/INTEG-final-c2rd1/red-28-summary.tsv` | 逐例判定表 |
| `evidence/INTEG-final-c2rd1/c25_assign_list.x` / `.out` | List 重赋值后仍可 push（length=3） |
| `evidence/INTEG-final-c2rd1/c26_assign_set.x` / `.out` | Set 重赋值后仍可 add（length=3） |
| `evidence/INTEG-final-c2rd1/interp-test.txt` | `go test ./internal/interp/` 原始输出 |
| `evidence/INTEG-final-c2rd1/sha256.txt` | 本节全部证据哈希 |
