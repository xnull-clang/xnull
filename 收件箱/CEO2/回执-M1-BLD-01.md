# 回执 M1-BLD-01（S1 内置类型）

> 卡：M1-BLD-01　主责：CEO2-RD2　会签：CEO2-QA1
> 基线：`main` = `2c00cf5`（已非快进合入 `pod/c2-rd2`）　被测 commit：`349c3b2`
> 分支：`pod/c2-rd2`（**未 push、未合 main**）　日期：2026-11-07

## 一、五行

1. **改了什么**：`impl/internal/interp/values.go`（String ASCII 大小写、`new` 负数 fatal、`List.insert` 越界 panic、`List.remove` 返回元素、`Map.get` 缺失键返回 null、Map 惰性排序快照使 put 均摊 O(1)、Set 哈希索引+插入序墓碑使 add/has/remove 平均 O(1)）；`interp.go`（`Value.Set`、scope 记录声明类型 → 赋值不退化为数组、for-in 走 Set.elements）；`sema/ty.go`（`List.remove` 返回元素、`Map.get` 类型 `V?`、Map 键类型 `TY-106`）。
2. **怎么验**：`sh evidence/M1-BLD-01/red/run-red.sh` → **28/28 绿**（T+1 红基线 11 红已清零）；`go vet ./...` exit 0；`go test ./... -count=1 -timeout 300s` **10 包全绿**；`TestExamplesCompileMatchesInterp` **9/9 双路径 PASS**；`impl/runtime/build_rt.sh` 六套件回归 6/6。
3. **sha**：被测 `349c3b2`（merge main `2c00cf5`）；实现 `03a73d5`；红基线 `96644b3`；分支 `pod/c2-rd2`，未 push。
4. **产物**：`evidence/M1-BLD-01/` 七件套（`command/stdout/stderr/exit_code/sha/artifact.sha256/acceptance.md`）+ `green/` 原始输出 + `red/`（fixtures、cases.tsv、run-red.sh、逐例 `.out/.err/.exit/.time`）。
5. **未测项**：Set 元素类型静态限制（§9.6）未加检查；`new T[count]` 的 T 为数组类型/OOM 未测；复杂度为墙钟预算且 `Map.keys/values` 惰性排序有 log 因子偏离（待 PM/QA 裁决）；§9.9 null 接收者 panic 未改；编译路径未建 20 条逐项矩阵；枚举键未测；台账状态未改（等 L1/L2）。

## 二、检查表（台账验收要点逐项，20/20）

| # | 要点 | 用例 | 判定 |
|---:|---|---|---|
| 1 | String 成员签名（10 个成员） | c01 | ✅ |
| 2 | String 边界（substring 钳制、indexOf -1、split 空段、replace 空 from、trim 仅 ASCII、UTF-8 字节长度） | c02 | ✅ |
| 3 | String 大小写只转 ASCII | c03 | ✅ |
| 4 | T[] 成员（下标读写/length/join） | c04 | ✅ |
| 5 | T[] 读/写越界 panic | c05、c06 | ✅ |
| 6 | new T[count] 零值与长度 0 | c07 | ✅ |
| 7 | new T[count] 负数 panic（134） | c08 | ✅ |
| 8 | List 成员签名 + 下标等价 | c09 | ✅ |
| 9 | List.insert 越界 panic | c10、c11 | ✅ |
| 10 | List.remove 返回被删元素 | c12 | ✅ |
| 11 | List get/set/remove 越界 panic | c13–c15 | ✅ |
| 12 | Map 成员签名（9 个成员） | c16 | ✅ |
| 13 | Map.get 缺失键返回 null | c17 | ✅ |
| 14 | Map.getOr 缺失键返回 fallback | c18 | ✅ |
| 15 | Map 键类型限制（Bool 键编译错误 TY-106） | c19 | ✅ |
| 16 | Map 重复键覆盖 / 整数键 / keys 顺序确定 | c20、c21 | ✅ |
| 17 | Set 成员 + 字面量去重 + for-in | c22 | ✅ |
| 18 | Set.at 越界 panic | c23、c24 | ✅ |
| 19 | 赋值保持容器种类（List/Set） | c25、c26 | ✅ |
| 20 | 复杂度 §9.8（Set 增删查、Map put 平均 O(1)） | c27、c28 | ✅ |

## 三、未测项与风险（详）

1. Set 元素类型限制（§9.6 同 §9.5）未加静态检查，`Set<Bool>` 仍被接受。
2. `new T[count]`：T 为数组类型应编译期拒绝、OOM 应 panic，均无用例。
3. 复杂度：墙钟预算（c27 800ms / c28 3000ms），非操作计数；`Map.keys/values` 结构修改后首次读取 `O(n log n)`，对 §9.8「O(n)」有 log 因子偏离，**申报裁决**。
4. §9.9 null 接收者非 `?.` 调用：仍为 runtimeErr(1)，未改（不属本锚点台账要点）。
5. 编译路径：9 示例双路径通过（含 containers.x），未对 20 条逐项建编译路径断言。
6. 枚举键：`Map<SomeEnum,V>` 未测。
7. 台账状态未动；等 CEO2-QA1 L1、CEO1 L2 后由台账维护方更新。

## 四、跨域与合并说明

- 实现面为 `interp/**` 与 `sema/**`（BLD-01 本身所在域），按 v1.7.1「8 锚点并行、跨域支援不排队」执行；未改 `runtime/**` 之外的他人锚点文件。
- `git merge main`（`2c00cf5`）非快进；唯一冲突 `impl/internal/sema/ty.go`，已双保留（`checkMapKey` + `checkResultType`），并删除与 main 重名的本地 `splitTypeArgs`。
- 合并后复跑：28/28、vet 0、全量 10 包绿、9/9 双路径、C 六套件 6/6。

## 五、证据索引

- 七件套：`evidence/M1-BLD-01/{command.txt,stdout.txt,stderr.txt,exit_code.txt,sha.txt,artifact.sha256,acceptance.md}`
- 原始输出：`evidence/M1-BLD-01/green/{run-red-28.txt,go-vet.txt,go-test-all.txt,dualpath-9.txt,build_rt.txt}`
- 用例与脚本：`evidence/M1-BLD-01/red/{cases.tsv,fixtures/,run-red.sh,results/}`
- 红基线（11 红）：commit `96644b3` 的 `evidence/M1-BLD-01/red/results/`
