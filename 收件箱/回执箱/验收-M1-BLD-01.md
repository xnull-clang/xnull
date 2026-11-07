# 验收：M1-BLD-01（内置类型，S1 §9）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（28/28；台账 20 项逐项通过）
> **复验点**：main `d620ea5`
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| 锚点用例（`cases.tsv`，28 例） | **28/28 GREEN** |
| 台账验收要点 | **20/20 PASS** |
| `go vet ./...` | exit 0 |
| 9 示例双路径 | 9/9 一致（DET 复验同批） |
| 全仓测试 | 唯一红点为 `internal/devtool` 台账 golden（与本锚点无关，见 §五） |

**判定：PASS。** 28 例覆盖 `String` / `T[]` / `List` / `Map` / `Set` 的成员签名、边界、缺失键、`new T[count]`、容器赋值与复杂度预算；本轮在 main `d620ea5` 上独立复跑全绿。

---

## 二、逐项检查表（台账 20 项）

| # | 要点 | 用例 | 期望 | 实测 |
|---:|---|---|---|---|
| 1 | `String` 成员签名 | c01 | 精确 stdout | GREEN |
| 2 | `String` 边界（substring 钳制、indexOf -1、split 空段、replace 空 from、trim ASCII、UTF-8 字节长度） | c02 | 精确 stdout | GREEN |
| 3 | `toUpper/toLower` 只转 ASCII（§9.2） | c03 | `é` 不变 | GREEN |
| 4 | `T[]` 成员（下标读写、length、join） | c04 | 精确 stdout | GREEN |
| 5 | `T[]` 读/写越界 panic | c05、c06 | exit 134 | GREEN |
| 6 | `new T[count]` 零值（Int/Bool/Float/String）与长度 0 | c07 | 精确 stdout | GREEN |
| 7 | `new T[count]` 负数 panic（§9.3） | c08 | exit 134 | GREEN |
| 8 | `List` 成员（push/insert/set/get/remove/clear/length）+ 下标等价 | c09 | 精确 stdout | GREEN |
| 9 | `List.insert` 越界 panic（0..length） | c10、c11 | exit 134 | GREEN |
| 10 | `List.remove` 返回被删元素（§9.4） | c12 | 输出被删元素 | GREEN |
| 11 | `List` get/set/remove 越界 panic | c13、c14、c15 | exit 134 | GREEN |
| 12 | `Map` 成员（put/get/getOr/has/remove/clear/length/keys/values） | c16 | 精确 stdout | GREEN |
| 13 | `Map.get` 缺失键返回 null、不 panic（V?） | c17 | exit 0 + `null` | GREEN |
| 14 | `Map.getOr` 缺失键返回 fallback；存在键返回原值 | c18 | 精确 stdout | GREEN |
| 15 | `Map` 键类型限制（Bool 键为编译错误） | c19 | 非 0 + `error[` | GREEN（`TY-107`） |
| 16 | `Map` 重复键后者覆盖；整数键可用、`keys()` 顺序确定 | c20、c21 | 精确 stdout | GREEN |
| 17 | `Set` 成员 + 字面量去重 + for-in（插入序） | c22 | 精确 stdout | GREEN |
| 18 | `Set.at` 越界 panic | c23、c24 | exit 134 | GREEN |
| 19 | 赋值保持容器种类（List/Set 不退化为数组） | c25、c26 | 精确 stdout | GREEN |
| 20 | 复杂度 §9.8（Set add/has/remove、Map put 平均 O(1)） | c27、c28 | 预算内（800ms / 3000ms） | GREEN（132ms / 358ms） |

---

## 三、复跑结果

```bash
cd /private/tmp/qa-m1-main
sh evidence/M1-BLD-01/red/run-red.sh
```

原样尾部输出：

```
GREEN c27_set_complexity         exit=0      132ms
GREEN c28_map_put_complexity     exit=0      358ms

TOTAL=28 RED=0 GREEN=28
```

被测 sha：`d620ea5`（`results/env.txt` 的 `git_sha` 一致）。

---

## 四、边界 / 已知口径

1. **复杂度口径**：c27/c28 用墙钟预算区分“每次 O(n)”与“均摊 O(1)”，非操作计数；`Map.keys/values` 为保证确定性输出采用惰性排序快照，结构修改后首次读取为 `O(n log n)`，对 §9.8 的“O(n)”有 log 因子偏离——沿用原验收申报，交 PM/QA 裁决。
2. `Set` 元素类型静态限制：本轮未新增 `Set<Bool>` 负例；运行期为 `Int`/`String` 限制。
3. `new T[count]` 的 `T` 为数组类型、OOM 分配失败未构造用例。
4. §9.9 null 接收者成员调用：当前走 runtimeErr（exit 1），不属台账 BLD-01 要点。
5. 编译路径容器成员矩阵：9 示例双路径通过，但未对 20 条逐条建编译路径断言。

---

## 五、回归

| 项 | 结果 |
|---|---|
| `go vet ./...` | exit 0 |
| 9 示例双路径 | 9/9 MATCH（`evidence/M1-DET-01-reverify-d620ea5/dualpath-9.txt`） |
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与 BLD-01 无关，需另修 golden 或回退状态。 |

---

## 六、证据

- 复验目录：`evidence/M1-BLD-01-reverify-d620ea5/`
  - `cases.tsv`：28 例期望（取自规范）
  - `results/summary.txt`、`results/summary.tsv`：逐例判定
  - `results/<id>.{out,err,exit,time}`：原始输出
  - `results/env.txt`：被测 sha、二进制 sha256、工具链
  - `sha.txt`、`command.txt`
- 用例表与执行器来源：`evidence/M1-BLD-01/red/`
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §9.1–§9.8
