# XDK 2.x 计划总览

| 项 | 值 |
| --- | --- |
| 性质 | 执行总览；不复制逐类型合同，不替代架构/包/批次/债表 |
| 基线 | 分支 `xdk-2` @ `993833b8` |
| 目标 | 75 包 / 698 类型 |
| 1.x 基线 | 14 包 / 160 symbols |
| 范围不变量 | UI/桌面/显示/音频/输入/电源/剪贴板/通知/托盘/文件对话框不在 XDK 范围 |

---

## 1. 一页结论

| 问题 | 结论 |
| --- | --- |
| 现在在哪 | B0–B3 已完成并合并；B4 设计合同与 B4-01/B4-02 入口合同已冻结；B4 仍未 GO。 |
| 下一步 | owner 接受 [`DEBT-REGISTER.md`](DEBT-REGISTER.md) 与 B4-01/B4-02 冻结决定后，开 B4 的 8 个纯包。 |
| 什么没开 | B4 实现未开工；B5–B10 未开工；C7 正在 `debt-c7-core` 进行中，未合并前不算完成。 |

B4 当前状态是“**合同已冻结（待 owner 接受）**”，不是“B4 已完成”或“已 GO”。合同冻结不等于 owner 接受，也不等于包验收。

---

## 2. 当前基线

```text
branch: xdk-2
HEAD:   993833b8 docs(design): freeze B4-01/B4-02 contracts
2.x:    75 packages / 698 types
1.x:    14 packages / 160 symbols
UI:     removed from 2.x scope
```

关键提交：

| 批次 | 结果 | 提交 |
| --- | --- | --- |
| B0 方案落地 | 已完成；含 B0-fix | `0e0f7b5f` / `a2967e67` |
| B1 注解编译器 | 已合并 | merge `c4dbdf54` |
| B3 runtime prelude | 已完成；含 B3.2 | merge `cce533f5` / `876b9320` |
| B2 注解类型 | 已完成（B2.1–B2.3） | merge `48ec4bae` |
| B4 入口合同 | B4-01/B4-02 已冻结，待 owner 接受 | `993833b8` |

B0–B3 的详细证据在 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) §11.1–§11.4；不要在 PLAN 里复制门禁日志。

---

## 3. 层/包地图摘要

完整 75 行见 [`PACKAGE-MAP.md`](PACKAGE-MAP.md)。这里只给层汇总：

| 层 | 包 | 类型 | 内容 |
| --- | ---: | ---: | --- |
| L0 annotations | 1 | 14 | 注解元模型/注册表/处理器合同 |
| L1 runtime/execution | 2 | 25 | runtime、execution |
| L2 core foundation | 7 | 80 | errors/meta/bytes/text/collections/math/time |
| L3 core system | 6 | 81 | io/fs/sys/log/config/cli |
| L4 data/encoding | 12 | 76 | codec/crypto/compress/random/uuid/stats/functional/graph/reflect/toml/yaml/xml |
| L5 network/data | 9 | 125 | net/uri/mime/tls/http/websocket/net.service/jwt/sql |
| L6 platform/compute | 17 | 93 | os.* + gpu/tensor/linalg/geo/serial/device |
| L7 application services | 12 | 82 | validate/cache/queue/schedule/event/resilience/metrics/trace/audit/terminal/i18n/test |
| L8 solutions | 9 | 122 | api/db/ml/agent/numerics/jsonrpc/mcp/accel/embedded |
| **合计** | **75** | **698** | |

B4 是跨层批次，不额外增加包数：`functional`/`graph`/`stats` 来自 L4，`net.uri`/`net.mime` 来自 L5，`tensor`/`linalg`/`geo` 来自 L6，合计 8 包 / 34 类型。

---

## 4. 执行顺序

```text
B4 第一批纯包
  → B5 core 15 包
    → B6 data/encoding 12 包
      → B7 network 9 包
        → B8 platform 17 包
          → B9 application services 12 包
            → B10 solutions 9 包
```

| 批次 | 范围 | 入口/出口 |
| --- | --- | --- |
| B4 | functional/graph/stats/net.uri/net.mime/tensor/linalg/geo；8 包 / 34 类型 | owner 接受债表与 B4-01/B4-02 冻结决定；每包场景 + 2.x gate |
| B5 | core 15 包 / 186 类型 | B4 完成；C7 完整合同整合与 1.x 回归 |
| B6 | data/encoding 12 包 / 76 类型 | B5 完成；依赖闭包绿 |
| B7 | network 9 包 / 125 类型 | B6 完成；HTTP/1.1 先于 HTTP/2 |
| B8 | platform 17 包 / 93 类型 | B7 完成；P6/P7/P9 决策先冻结 |
| B9 | application services 12 包 / 82 类型 | B8 完成；依赖闭包绿 |
| B10 | solutions 9 包 / 122 类型 | B9 完成；X1–X5 先冻结 |

批次权威是 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) §4.3；本表只做摘要。

---

## 5. 债务与范围

### 5.1 B4 前置账本

[`DEBT-REGISTER.md`](DEBT-REGISTER.md) 是 B4 的前置账本，不是 B4 完成记录：

- 45 条 = 2 B4 阻塞 + 26 后续批次 + 13 1.x/post-1.0/owner accepted + 4 BLOCKED。
- B4-01/P11 与 B4-02/P8 的合同已冻结，状态为“合同已冻结（待 owner 接受）”。
- B4 入口公式：**owner 接受债表 + B4-01/B4-02 合同冻结 → GO**。合同冻结已完成，owner 接受未完成，所以 B4 不 GO。
- `SCOPE-01` 是“非债务/范围外”，不计入 45 条。

### 5.2 C7

C7 是 1.x 已实现 API 向 2.x core 完整合同的整合，当前在 `debt-c7-core` 进行中：

- 已完成的只是 B0 的 ledger 回写；不等于 C7 完成。
- 未合并前不得写成“已完成”，也不得据此宣布 B5 开工。
- 证据入口：[`DEBT-REGISTER.md`](DEBT-REGISTER.md) NEXT-01、[`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) §11.1。

### 5.3 UI/桌面

UI/桌面/显示/音频/输入/电源/剪贴板/通知/托盘/文件对话框是范围不变量，不是债务：

- 不实现、不排期、不立 3.x 议题。
- 不得重新出现在包表、API 面或 `xdk2-packages.tsv`。
- 证据：[`DEBT-REGISTER.md`](DEBT-REGISTER.md) §7 `SCOPE-01`、[`ARCHITECTURE.md`](ARCHITECTURE.md) D7。

---

## 6. 文档权威顺序

| 顺序 | 文档 | 覆盖什么 |
| ---: | --- | --- |
| 1 | 语言规范 S0–S9 | 语言语法/语义；最高优先级 |
| 2 | [`ARCHITECTURE.md`](ARCHITECTURE.md) + [`PACKAGE-MAP.md`](PACKAGE-MAP.md) | 分层、包边界、包/类型计数；“有什么” |
| 3 | [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) | 批次顺序、任务板、门禁；“什么时候做什么” |
| 4 | [`DEBT-REGISTER.md`](DEBT-REGISTER.md) | 债务分类、B4 入口、owner 接受状态；“欠什么/能否开工” |
| 5 | 各领域 README / 逐类型合同 | 逐类型签名、失败、取消、生命周期；“怎么用” |
| 6 | [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md) | 冲突决定、改名、缺失原语；必须回链，不复制第二份契约 |
| 7 | [`API-SURFACE.md`](API-SURFACE.md) 等广度稿 | 只作对照，不作实现依据 |
| 8 | [`LEGACY-1.0.md`](LEGACY-1.0.md) 与 `t0/` | 1.x 已发布事实；不参与 2.x 排期 |

覆盖规则：

- 架构/包边界冲突：`ARCHITECTURE`/`PACKAGE-MAP` 胜。
- 批次状态冲突：`EXECUTION-PLAN`/`DEBT-REGISTER` 胜；类型合同不写批次状态。
- 债务/B4 入口冲突：`DEBT-REGISTER` 胜。
- 类型签名冲突：类型合同在包内胜，但不得违反架构/包边界；冲突时先修合同，不改架构迁就实现。
- 1.x 历史：`t0`/`LEGACY-1.0` 只作事实，不反向覆盖 2.x 计划。
- 本 `PLAN.md` 与上述文档冲突时，上述权威文档胜，PLAN 随后同步。

---

## 7. 门禁

基础命令与证据格式见 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) §8。2.x 批次完整门禁：

```sh
src/mini/build.sh
src/mini/tests/xdk2.sh
src/mini/tests/xdk.sh
src/mini/tests/xdk_core.sh
src/runtime/build_rt.sh
python3 src/toolchain/check_doc_naming.py docs/design
python3 src/toolchain/check_links.py docs/design
git diff --check
# retro：批末复盘并通过 .agent/bin/check.py
```

规则：

- 门禁红不进入下一批；先修工具链/合并语义。
- 场景 `.out` 是规格，不改期望值迁就实现。
- 批末工作区干净；`Partial`/`TODO`/“下批再做”不是批次终态。
- B4 包验收必须同时有：类型合同、源码、`.x`+`.out` 场景、完整门禁、commit 证据。

---

## 8. 更新规则

1. 计划/顺序变化：先改 `PLAN.md` 与 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md)；涉及债表或 B4 入口再改 [`DEBT-REGISTER.md`](DEBT-REGISTER.md)。
2. 状态只写在这三份计划/账本里，不写进类型合同；类型合同只写合同，不写“已完成/未开工”。
3. 包/类型计数变化：同步 `PACKAGE-MAP.md`、`COVERAGE.md`、`README.md`，并在批次记录说明原因。
4. 1.x `t0`/`MINI-1.0` 历史不改；2.x 破坏性变化走 `DESIGN-CONSISTENCY.md`。
5. UI/桌面是范围不变量；不得把已移除能力重新登记成“未来包”、债务或计划项。
6. 合同冻结 ≠ owner 接受 ≠ 包验收 ≠ B4 GO；三者分开写。
