# M1-BLD-01 红证据（T+1 检查点，2026-11-07）

> 锚点：S1 BLD-01 内置类型（`String` / `T[]` / `List` / `Map` / `Set` 成员签名、边界、
> `Map.get` / `getOr` 缺失键、`new T[count]`、复杂度 §9.8）
> 模式：**只读红证据**。本目录不修改 `impl/**`；xnull 构建到 `/tmp`，用 `run --interp` 执行夹具。
> 基线：`pod/c2-rd2` @ `81ec33d`（证据提交前的分支 HEAD 见 `results/env.txt`）

## 1. 怎么跑

```bash
cd wt/c2-rd2
sh evidence/M1-BLD-01/red/run-red.sh
```

- 构建：`cd impl && go build -o /tmp/xnull-bld01-bld01 ./cmd/xnull`
- 每例：`/tmp/xnull-bld01-bld01 run --interp fixtures/<id>.x`
- 原始输出：`results/<id>.out`（stdout）/ `.err`（stderr）/ `.exit`（退出码）/ `.time`（毫秒）
- 汇总：`results/summary.txt`（人读）、`results/summary.tsv`（机读）、`results/env.txt`（sha/工具链/二进制 sha256）
- 脚本固定 **exit 0**（报告模式）；红/绿看 `summary.txt` 的计数行。

## 2. 口径

- **期望值取自规范**（S1 §9.2—§9.8），不取自实现，也不复用实现断言；表在 `cases.tsv`。
- 退出码口径沿用仓库既有约定：运行期 panic（fatal）= **134**；运行期拒绝（runtimeErr）= **1**；
  编译期拒绝 = 非 0 且 stderr 含 `error[...]` 诊断码。
- 复杂度用**墙钟预算**区分「每次 O(n)」与「均摊 O(1)」：阈值取远高于实现成本、远低于线性成本的量级；
  精确渐进复杂度由 QA 独立复核，本证据只防回归。阈值与实测值都写进 `summary.tsv`。

## 3. 覆盖映射（台账验收要点 → 用例）

| 台账验收要点 | 用例 |
|---|---|
| `String` 成员签名 | c01 |
| `String` 边界（substring 钳制/IndexOf/split/trim/replace/UTF-8 长度） | c02 |
| `String` 大小写仅 ASCII（§9.2） | c03 |
| `T[]` 成员（下标读写/length/join） | c04 |
| `T[]` 边界（读/写越界 panic） | c05、c06 |
| `new T[count]` 零值、长度 0 | c07 |
| `new T[count]` 负数 panic | c08 |
| `List` 成员签名 + 下标等价 | c09 |
| `List.insert` 越界 panic | c10、c11 |
| `List.remove` 返回被删元素 | c12 |
| `List` get/set/remove 越界 panic | c13、c14、c15 |
| `Map` 成员签名 | c16 |
| `Map.get` 缺失键 → null | c17 |
| `Map.getOr` 缺失键 → fallback | c18 |
| `Map` 键类型限制（Bool 应编译错误） | c19 |
| `Map` 重复键覆盖 / 整数键 | c20、c21 |
| `Set` 成员 + 字面量去重 + for-in | c22 |
| `Set.at` 越界 panic | c23、c24 |
| 赋值保持容器种类（List / Set） | c25、c26 |
| 复杂度 §9.8（Set 增删查 / Map put） | c27、c28 |

## 4. 本轮红/绿基线

见 `results/summary.txt` 末尾 `TOTAL / RED / GREEN` 与逐条明细。
红条即 T+1 检查点的「失败测试 + 红输出」证据；实现完成后同一脚本应转为全绿（除跨域项，见回执）。
