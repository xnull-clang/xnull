# T0 核心层收口契约（2026-11-21）

目的：把 T0 核心层从“每个包各自绿”变成“作为一个整体可用”。
本文件是收口批次的唯一范围来源；不以文件数、包数或“下批再做”为终点。

## 1. 完成定义

以下四项同时成立才算收口：

1. `docs/design/t0/{05-text,06-collections,09-io,10-fs,11-sys}.md`
   的 `当前状态` 全部为 `Verified`；
2. `src/mini/tests/xdk.sh` PASS；
3. `src/mini/tests/xdk_core.sh` PASS（端到端核心程序，见 §3）；
4. 工作树干净，每个批次一次提交。

## 2. 禁止的终态

收口批次只有两个终态：`Verified` 或 `RED`。

- 不允许以 `Partial`、`Blocked`、“登记为 T0-X”、“下批再做”、“先跳过”收尾；
- 不允许输出“待办/冻结/后续”清单代替实现；
- 发现缺口就地补：缺 API 补 API，缺比较器补比较器，缺规范补一页再实现；
- 只有会改变产品方向的决策才允许停下来问，命名/签名/错误语义按既有约定推导。

`RED` 表示批次失败，整条收口链停止，不允许跳过该包继续下一个。

## 3. 端到端验收程序

`src/mini/tests/xdk_core.x` 导入全部核心包，模拟一个真实小程序：

```text
文本 trim/contains/parse → List/Map → checked 数学 → 错误 → 配置
→ 日志 → Bytes/IO → 文件读写 → 系统存在性
```

`src/mini/tests/xdk_core.out` 是**规格**，不是当前行为的快照。
禁止为了让测试变绿而删断言、改期望值或换等价弱断言；只有 API 合法变更
（例如 `writeText` 从 `Int` 改为 `Result<Long,Error>`）才同步更新程序和期望值，
并在对应设计文档中写明。

### 3.1 起始红点（2026-11-21）

`xdk_core.sh` 初始为红，暴露了单包门禁掩盖的问题：

1. `xdk.bytes` 与 `xdk.text` 都导出顶层 `isEmpty`，mini 无重载，两个包不能同时导入。
   处理：bytes 侧改名 `isEmptyBytes`（已随本契约落地），同步测试与 `04-bytes.md`。
2. `List<String>` 的 `sortBy(names, (a,b) -> a < b)` 不排序；
   `xdk_collections_algo.x` 的期望值把 `b,a,c` 这个错误顺序固化了。
   处理：给 String 提供可用的比较/排序面，修正旧期望值，禁止保留“绿但错”。
3. `writeText` 返回 `0`，而 `10-fs.md` 规定返回字节数。
   处理：按文档返回字节数；`fs` 的 T0-X 再按设计改为 `Result<Long,Error>`。

## 4. 批次顺序

| # | 批次 | 范围 | 验收 |
| --- | --- | --- | --- |
| 0 | core-integration | 修 §3.1 红点，直到 `xdk_core.sh` 绿 | `xdk.sh` + `xdk_core.sh` |
| 1 | io | `09-io.md` 的全部 T0-X 条目 | 包 `Verified` + 两道门禁 |
| 2 | collections | `06-collections.md` 的全部 T0-X 条目（含编译器/运行时） | 同上 |
| 3 | text | `05-text.md` 的全部 T0-X 条目（Unicode、Regex、Format） | 同上 |
| 4 | fs | `10-fs.md` 的全部 T0-X 条目（Result 面、File/Dir/Path、atomic/temp/walk/glob） | 同上 |
| 5 | sys | `11-sys.md` 的全部 T0-X 条目（Result 面、File/Dir/Process、信号/管道/环境枚举） | 同上 |

依赖顺序固定；不得因为“风险大/工程大”改道、缩范围或拆出“先跳过”的子项。
`collections` 改编译器，必须串行；其余包可在后续并行化，但不在首轮收口链里混批。

## 5. 批内与批末

批内：只改代码、场景、必要文档；不跑门禁、不提交、不汇报、不列待办。

批末只做一次：

1. `src/mini/build.sh`（改编译器时必需）；
2. `src/mini/tests/xdk.sh` 与 `src/mini/tests/xdk_core.sh`；
3. 更新该包设计文档、`AUDIT.md`、`src/xdk/PLAN.md` 与 `xdk/lib` 镜像；
4. 扩展 `xdk_core.x` 覆盖该包新面并更新 `xdk_core.out`；
5. 提交一次；
6. 汇报一次。
