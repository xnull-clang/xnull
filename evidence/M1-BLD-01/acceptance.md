# M1-BLD-01 验收材料（S1 内置类型）

> 锚点：**BLD-01**（`String` / `T[]` / `List` / `Map` / `Set` 成员签名、边界、`Map.get` / `getOr` 缺失键、`new T[count]` 分配、复杂度 §9.8）
> 主责：CEO2-RD2　会签：CEO2-QA1　基线：`main` = `9f5f66c`（B0 门 + e2/c2-rd1/c3-rd1/c3-rd2；已合入 `pod/c2-rd2`）
> 被测 commit：**`9bc86b6`**（merge main 9f5f66c 后）　实现 commit：`03a73d5`　分支：`pod/c2-rd2`（未 push、未合 main）

## 1. 结论

| 项 | 结果 |
|---|---|
| 台账验收要点（逐项） | **20/20 通过** |
| 锚点用例（`red/run-red.sh`） | **28/28 绿**（红基线 11 条已全部转绿） |
| `go vet ./...` | exit 0（零输出） |
| `go test ./... -count=1 -timeout 300s` | **10 包全绿** |
| 9 示例双路径（解释 vs 编译） | **9/9 PASS**，stdout 逐字节 + 退出码一致 |
| C 运行时六套件（回归） | 6/6 PASS |
| 判定 | **PASS（待 CEO2-QA1 L1 + CEO1 L2）**；台账状态不改，等门禁 |

红证据基线（T+1 检查点）在 commit `96644b3` 的 `red/results/`：28 例中 11 红 17 绿；本轮同一脚本复跑为 28/28 绿。

## 2. 七件套

| 件 | 路径 | 说明 |
|---|---|---|
| command | `evidence/M1-BLD-01/command.txt` | 可复制命令（合并/红绿用例/vet/全量/双路径/C 回归） |
| stdout | `evidence/M1-BLD-01/stdout.txt` | 上述命令的关键原始输出 |
| stderr | `evidence/M1-BLD-01/stderr.txt` | 各命令 stderr 说明；逐例 stderr 在 `red/results/<id>.err` |
| exit_code | `evidence/M1-BLD-01/exit_code.txt` | 逐命令退出码 |
| sha | `evidence/M1-BLD-01/sha.txt` | 主线/分支/实现/合并/被测 commit |
| artifact.sha256 | `evidence/M1-BLD-01/artifact.sha256` | 改动源文件、用例表、脚本、xnull 二进制、关键输出哈希 |
| acceptance | 本文件 | 清单、结论、未测项 |
| 附：原始输出 | `evidence/M1-BLD-01/green/` | `run-red-28.txt`、`go-vet.txt`、`go-test-all.txt`、`dualpath-9.txt`、`build_rt.txt`、`red-run-summary.txt` |

## 3. 逐项检查表（台账验收要点）

| # | 要点 | 用例 | 期望 | 结果 |
|---:|---|---|---|---|
| 1 | `String` 成员签名（length/substring/indexOf/trim/split/replace/toUpper/toLower/startsWith/endsWith） | c01 | exit 0 + 精确 stdout | ✅ |
| 2 | `String` 边界（substring 负数/越界钳制、indexOf 未命中 -1、split 空分隔符与空段、replace 空 from、trim 仅 ASCII、UTF-8 字节长度） | c02 | 精确 stdout | ✅ |
| 3 | `String.toUpper/toLower` 只转 ASCII（§9.2） | c03 | `é` 不转成 `É` | ✅ |
| 4 | `T[]` 成员（下标读写、length、join） | c04 | 精确 stdout | ✅ |
| 5 | `T[]` 边界（读/写越界 panic） | c05、c06 | exit 134 | ✅ |
| 6 | `new T[count]` 零值初始化（Int/Bool/Float/String）与长度 0 | c07 | 精确 stdout | ✅ |
| 7 | `new T[count]` 负数 panic（§9.3） | c08 | exit 134 | ✅ |
| 8 | `List` 成员签名（push/insert/set/get/remove/clear/length）+ 下标等价 | c09 | 精确 stdout | ✅ |
| 9 | `List.insert` 越界 panic（0..length） | c10、c11 | exit 134 | ✅ |
| 10 | `List.remove` 返回被删元素（§9.4） | c12 | 输出被删元素 | ✅ |
| 11 | `List` get/set/remove 越界 panic | c13、c14、c15 | exit 134 | ✅ |
| 12 | `Map` 成员签名（put/get/getOr/has/remove/clear/length/keys/values） | c16 | 精确 stdout | ✅ |
| 13 | `Map.get` 缺失键返回 null、不 panic（V?） | c17 | exit 0 + `null` | ✅ |
| 14 | `Map.getOr` 缺失键返回 fallback；存在键返回原值 | c18 | 精确 stdout | ✅ |
| 15 | `Map` 键类型限制（Bool 键是编译错误，TY-106） | c19 | 非 0 + `error[` | ✅ |
| 16 | `Map` 重复键后者覆盖；整数键可用、keys() 顺序确定 | c20、c21 | 精确 stdout | ✅ |
| 17 | `Set` 成员签名 + 字面量去重 + for-in（插入序） | c22 | 精确 stdout | ✅ |
| 18 | `Set.at` 越界 panic | c23、c24 | exit 134 | ✅ |
| 19 | 赋值保持容器种类（List/Set 重新赋值不退化为数组） | c25、c26 | 精确 stdout | ✅ |
| 20 | 复杂度 §9.8（Set add/has/remove 平均 O(1)；Map put 平均 O(1)） | c27、c28 | 预算内（800ms / 3000ms） | ✅ |

## 4. 变更面

| 文件 | 变更 |
|---|---|
| `impl/internal/interp/values.go` | String ASCII 大小写；`new` 负数 fatal；List.insert 边界/remove 返回；Map.get 返回 null；Map 惰性排序快照（put O(1)）；Set 哈希索引 + 插入序墓碑（add/has/remove O(1)）；coerceByDecl 容器定向 |
| `impl/internal/interp/interp.go` | `Value.Set`；scope 声明类型（赋值保容器种类）；局部/顶层/参数 defineTyped；for-in 经 Set.elements() |
| `impl/internal/sema/ty.go` | `List.remove` 返回元素类型；`Map.get` → `V?`；Map 键类型检查 `TY-106`（§9.5） |

跨域说明：BLD-01 的实现面在 `interp/` 与 `sema/`（非 RD2 原 runtime 域），按 v1.7.1「8 锚点并行、不排队」直接落地。合并 `main 7df123d`（B0 门）时：`values.go` 的 List.insert/remove、Map.get 与 main 同类实现按语义取一份（保留更明确的 fatal 诊断）；`sema/ty.go` 自动合并后出现重复 `case "remove"`，已去重；`splitTypeArgs` 使用 main 版本。

**本轮合并（main 9f5f66c）**：3 文件冲突——`interp.go`（scope.assign：保留 BLD-01 的声明类型定向 + main 的元组值复制 `cloneTupleValue`）、`values.go`（`mapv.len` 与 main 的 Map 键限制注释/运行时键类型取合并；canonKey 采用 main 的 Int/String 限制）、`sema/ty.go`（诊断码撞号：main 用 TY-106 = 元组，BLD-01 的 MapKey 改 TY-107）。另修 `defineTyped` 未克隆元组导致 main 的 `TestTupleElementAssignmentAndEquality` 回归（已绿）。

**复跑**：`go test ./... -count=1 -timeout 300s` 首跑即全绿（37.9s/codegen），无超时；锚点矩阵 28/28、9/9 双路径、C 六套件 6/6。

## 5. 未测项 / 已知边界（如实申报）

1. **Set 元素类型静态限制**：§9.6 与 §9.5 同限制（String/整数/简单枚举），本轮只对 Map 键加了 `TY-106`；`Set<Bool>` 仍被接受（运行期也接受）。
2. **`new T[count]` 的静态面**：`T` 为数组类型应编译期拒绝、分配失败（OOM）应 panic —— 均未构造用例。
3. **复杂度口径**：c27/c28 用墙钟预算（800ms/3000ms）区分「每次 O(n)」与「均摊 O(1)」，非操作计数；`Map.keys/values` 为保证确定性输出采用惰性排序快照，结构修改后的首次读取为 `O(n log n)`，对 §9.8 的「O(n)」有 log 因子偏离，**申报由 PM/QA 裁决是否可接受**。
4. **§9.9 null 接收者**：非 `?.` 成员调用应 panic；当前仍走 runtimeErr（exit 1），未改（不属台账 BLD-01 要点）。
5. **编译路径容器成员矩阵**：9 示例双路径通过（含 `containers.x`），但未对 20 条要点逐条建编译路径断言。
6. **枚举键**：`Map<SomeEnum,V>` 的合法性未测；sema 对未知命名类型放行，实际支持取决于枚举声明。
7. **台账状态**：未改 `XNull一致性用例台账`（等 CEO2-QA1 L1 + CEO1 L2 后由台账维护方更新）。

## 6. 复现

```bash
cd wt/c2-rd2
git checkout 9bc86b6
sh evidence/M1-BLD-01/red/run-red.sh            # 28/28
cd impl && go vet ./... && go test ./... -count=1 -timeout 300s
cd impl && go test ./internal/codegen -run TestExamplesCompileMatchesInterp -count=1 -timeout 300s
cd impl/runtime && sh build_rt.sh               # C 六套件回归
```
