# XDK 2.x 执行计划（Coding-Ready）

| 项 | 值 |
| --- | --- |
| 状态 | Active；P0 架构基线 `81fddb7b`；B0–B4 已完成/合并；C7 合同已整合待 B5；B5–B10 未开工 |
| 目标 | 把 2.x 从“设计完成”推进到“第一个 XDK 包可编码、可验收” |
| 基线 | `main` = 1.x 已发布；2.x 在 `xdk-2` 分支/worktree |
| 规则 | `LOCAL_RULES.md` 第 1–6 号；批内不停、批末一次门禁/提交/汇报 |
| 范围 | 非 UI 的 75 包 / 698 类型；UI/desktop 不在本计划 |
| 不在本计划 | 直接改 `main` 的 1.x；让实现 agent 自行发明 API；逐文件/逐条停 |

---

## 0. 一句话

**先把“能开工”的 5 件事做完，再开第一个包。**

不是先写 75 个包，也不是先写 `xdk.annotations` 14 个类；先让编译器能解析注解、测试能跑 2.x、包目录/清单能落地、1.x 回归有基线、任务板有 owner。这 5 件事构成 **CR-0（Coding Ready）**。

---

## 1. 当前开工阻塞

| # | 阻塞 | 证据 | 解除条件 | Owner |
| --- | --- | --- | --- | --- |
| G1 | 2.x 代码放哪没定 | `main` 是 1.x；`src/xdk` 是 1.x 源码 | 建 `xdk-2` 长分支 + worktree；`main` 保持 1.x | ARCH |
| G2 | 没有 2.x 测试入口 | `src/mini/tests/xdk.sh` 只测 1.x；无 `xdk2.sh` | 新增 `src/mini/tests/xdk2/` + `xdk2.sh` | QA |
| G3 | 没有 2.x 包清单/脚手架 | 75 包只在设计文档；`src/xdk` 无对应目录 | `src/xdk/xdk2-packages.tsv` + 首批包目录 | ARCH/QA |
| G4 | 编译器不解析注解 | `src/mini/main.x` 无 `AnnotationDecl`/`AnnotationUse`；`@` 只是 punct | B1：parser/AST/语义/诊断 | COMPILER |
| G5 | 运行时前置缺失 | 无 `RuntimeMonitor`、`Context` 截止/等待、泛型 `Pair` 等 | B3：runtime prelude | RUNTIME |
| G6 | P0.5 同名类型未改名 | `Histogram`/`Timer`/`Redactor` 等仍在类型文件里 | 8 组改名 + 引用替换 | ARCH |
| G7 | 1.x 已实现 API 未回写 2.x core 文档 | C7：`RuntimeStats/stats`、log Filter 等 | core 文档同步批次 | ARCH |
| G8 | 没有可执行任务板 | 只有 ARCHITECTURE/PACKAGE-MAP | 本文件 §5 工作包板 | ARCH |

> 历史快照：G1–G8 已由 B0–B4 解除；G4 已由 B1（注解 parser/AST/语义/诊断）关闭，G5 已由 B3 关闭。保留此表用于追溯，不再作为当前阻塞。

> G1–G8 不要求一次全清；**CR-0 只要求 G1–G5 + G8**。G6/G7 可与 B1/B3 并行，但必须在对应包实现前完成。

---

## 2. CR-0：Coding-Ready 门禁

CR-0 全绿 = 可以开始写第一个 XDK 包。

| # | 条件 | 证据/命令 | 门禁 |
| --- | --- | --- | --- |
| CR-0.1 | 架构基线已提交 | `git log --oneline \| grep 81fddb7b` | 已满足 |
| CR-0.2 | `xdk-2` 分支/worktree 建好 | `git worktree list` 显示 `XNull-xdk2` | B0.1 |
| CR-0.3 | 2.x 测试入口可跑 | `src/mini/tests/xdk2.sh` 退出 0，至少 1 个 smoke 场景 | B0.2 |
| CR-0.4 | 2.x 包清单存在 | `src/xdk/xdk2-packages.tsv` 75 行；首批目录存在 | B0.3 |
| CR-0.5 | 注解语法可解析 | `@annotation` 声明 + `@Name(...)` 使用 AST 可 dump | B1.1 |
| CR-0.6 | 注解诊断有稳定码 | `AN0001`–`AN0011` 至少覆盖未知/错目标/重复/错参数 | B1.2 |
| CR-0.7 | 1.x 回归有基线 | `xdk.sh` + `xdk_core.sh` 在 `xdk-2` 起点绿 | B0.4 |
| CR-0.8 | 任务板有 owner/scope | 本文件 §5 前 4 个批次全部有 owner | B0.5 |

> CR-0 不要求 `xdk.annotations` 14 类型、处理器调度、RuntimeMonitor 全部完成；那些是 CR-0 之后的 **B2/B3**。但 B3 必须与 B1 并行排期，否则 B4 的包会被运行时前置卡住。

---

## 3. 分支、目录与批次策略

### 3.1 分支

```text
main            1.x 已发布；只接受 1.x 修复；不承接 2.x 破坏性改动
release/1.0     1.0.0 发布线；只读/归档
xdk-2           2.x 长分支；所有 2.x 代码/文档/测试
```

工作区：

```text
/Users/vjs/Desktop/XNull-Lang                 main，保持干净
/Users/vjs/Desktop/XNull-xdk2                 xdk-2 worktree，主开发区
/Users/vjs/Desktop/XNull-xdk2-compiler        B1/B2 编译器 worktree（可选）
/Users/vjs/Desktop/XNull-xdk2-runtime         B3 运行时 worktree（可选）
```

规则：

- `main` 不合并 2.x，直到 2.0 发布前才做总合并。
- 每个并行 worktree 只改自己的文件域；合并到 `xdk-2` 用 `--no-ff`，批末一次。
- 1.x 的 `docs/design/t0` 不改；2.x 设计只改 `docs/design` 新树。

### 3.2 源码布局

**不建 `src/xdk2` 第二套源码。** 2.x 仍用 `src/xdk`，在 `xdk-2` 分支上演进；1.x 由 `main`/`release/1.0` 保存。

2.x 沿用现有 `src/xdk` 目录，不强制把 1.x 目录整体搬迁；包名与目录的映射写入 `xdk2-packages.tsv`。

```text
src/xdk/
  annotations/          xdk.annotations（新增）
  execution/            xdk.execution（新增；1.x tasks/sync 兼容映射）
  core/
    errors/ runtime/ meta/ bytes/ text/ collections/ math/ time/
  io/ fs/ sys/ log/ config/ cli/          （沿用现有目录）
  codec/ crypto/ compress/ random/ uuid/ stats/
  functional/ graph/ reflect/             （新增）
  net/ net/uri net/mime net/tls net/http net/websocket/
  os/ gpu/ tensor/ linalg/ geo/ serial/ device/
  validate/ cache/ queue/ schedule/ event/ resilience/
  metrics/ trace/ audit/ terminal/ i18n/ test/
  api/ db/ ml/ agent/ numerics/ jsonrpc/ mcp/ accel/ embedded/
```

首批只建实际要写的目录，不一次建 75 个空目录；`core/` 下的包继续留在 `core/`，不为了目录对称而搬迁。

### 3.3 测试布局

```text
src/mini/tests/xdk2/
  annotations/          B1/B2 注解正/负例
  prelude/              B3 runtime prelude
  functional/ graph/ stats/   B4 纯包
  ...
src/mini/tests/xdk2.sh  2.x 总门禁（可先跑 smoke，再逐步加）
```

测试规则：

- 每个场景 = `.x` + 精确 `.out`；场景红了先修实现，不改期望值。
- 每个包场景在 `xdk2.sh` 中登记；未登记不算验收。
- 1.x 的 `xdk.sh`/`xdk_core.sh` 仍跑，作为回归；2.x 改动不得打穿 1.x 公开行为。

### 3.4 批次

- 一个批次 = 用户给的一组工作包；批内不逐条门禁/提交/汇报。
- 批末一次：`src/mini/build.sh` + `xdk.sh` + `xdk_core.sh` + `xdk2.sh` + `check_doc_naming.py` + link check。
- 跨包批次按包各提交一次，仍在同一次收尾内。
- 只有红门修不了、规范缺失、破坏性操作、用户叫停才停。

---

## 4. 开工顺序

### 4.1 总顺序

```text
B0 方案落地（分支/测试/清单/诊断码/基线）
  → B1 注解编译器最小闭环（parser/AST/语义/诊断）
    → B2 xdk.annotations 14 类型 + 只读注册表
      → B3 runtime prelude（RuntimeMonitor/Context/Pair/isFinite/Bytes.alloc/errors）
        → B4 第一批纯 XDK 包（functional/graph/stats/uri/mime/tensor/linalg/geo）
          → B5 core 15 包 2.x 化
            → B6 data/encoding（codec/random/crypto/compress/formats）
              → B7 network（TCP/UDP/DNS/TLS/HTTP/WS/JWT/SQL/net.service）
                → B8 platform（os.*/gpu/serial/device）
                  → B9 application services（validate/cache/queue/...）
                    → B10 solutions（api/db/ml/agent/mcp/...）
```

### 4.2 并行关系

```text
B0.1 分支/worktree
  ├─ B0.2 测试入口 ─┐
  ├─ B0.3 包清单   ─┤
  ├─ B0.4 1.x 基线 ─┼─→ CR-0
  └─ B1.0 诊断码冻结 ┘

B1 编译器注解 ──→ B2 注解类型
B3 runtime prelude ──→ B4 纯包
B1/B2 与 B3 可在不同 worktree 并行；B4 要等 B2 + B3。
B5 之后按层串行；同层内按依赖列排序，不按目录顺序。
```

### 4.3 批次表

| 批次 | 内容 | 出口 | 可并行 |
| --- | --- | --- | --- |
| B0 | 分支/worktree、`xdk2.sh`、包清单、1.x 基线、诊断码冻结 | CR-0 | B0.2/B0.3/B0.4 可并行 |
| B1 | 注解 lexer/parser/AST、类型解析、目标/保留/重复、常量求值、诊断 | `AN0001`–`AN0014` 正/负例绿 | 与 B3 并行 |
| B2 | `xdk.annotations` 14 类型、`AnnotationRegistry`、运行时只读查询 | 14 类型 + 注册表场景绿 | 串行 B1 |
| B3 | `RuntimeMonitor`、`Context` 截止/等待、泛型 `Pair`/`Entry`、`isFinite`、`Bytes.alloc`、errors helpers、`List.copy` | prelude 场景 + 1.x 回归绿 | 与 B1 并行；`main.x` 冲突按 §4.4 rebase 解决 |
| B4 | `functional`、`graph`、`stats`、`net.uri`、`net.mime`、`tensor`、`linalg`、`geo` | 每包场景 + 2.x gate 绿 | 包间可并行 |
| B5 | core 15 包 2.x 化（foundation → io/fs/sys → log/config/cli → execution） | core 15 包 Verified | 子批串行 |
| B6 | data/encoding 12 包 | 依赖闭包绿 | 子批并行 |
| B7 | network 9 包 | 端到端网络场景绿 | 传输→协议串行 |
| B8 | platform 17 包 | 模型/只读/控制面分级绿 | os 与 device 可并行 |
| B9 | application services 12 包 | 依赖闭包绿 | 包间可并行 |
| B10 | solutions 9 包 | 逐组端到端绿 | 组间可并行 |

### 4.4 冲突处理（不是隔离）

冲突不是“换一条线绕开”或“标延期”就结束，必须按下面闭环：

1. 写清冲突文件/函数/语义，指定 owner。
2. 指定合并顺序（谁先落、谁 rebase）。
3. 合并时保留双方语义，补冲突测试（两边的场景都要跑）。
4. 处理完仍达不到严格要求，才标 `BLOCKED`，附证据和下一步；标记后继续该批其他条目，不整批停。
5. 不允许把“冲突已隔离”当作完成。

`src/mini/main.x` 是 B1/B3 的真实共享文件：

- B1 先落注解 AST/parser/Checker。
- B3 从 B1 的新 HEAD rebase，保留泛型 `Pair`、`List.copy`、`Bytes.alloc` 等编译支持；冲突逐段解，不丢任一侧。
- 合并后跑 `xdk2.sh`（注解 + prelude 全部场景）+ 1.x 回归。
- B3.2 `Context` deadline/wait 在 rebase 后继续做；它不是延期关闭项。

---

## 5. 工作包板（首批）

> 这是给实现 agent 的任务板，不是按文件列清单。每个工作包一个 owner 角色、一个文件域、一个出口；批内不逐条停。

### B0：方案落地

| ID | 工作包 | Owner | 依赖 | 文件域 | 产物 | 出口 |
| --- | --- | --- | --- | --- | --- | --- |
| B0.1 | 建 `xdk-2` 分支/worktree | ARCH | 无 | `.git`、worktree | `git worktree list` 可见 | `XNull-xdk2` 干净，HEAD 包含 `81fddb7b` |
| B0.2 | 2.x 测试入口 | QA | B0.1 | `src/mini/tests/xdk2.sh`、`xdk2/` | smoke 场景 + 门禁 | `xdk2.sh` 退出 0 |
| B0.3 | 包清单/首批脚手架 | ARCH/QA | B0.1 | `src/xdk/xdk2-packages.tsv`、`src/xdk/annotations/`、`src/xdk/execution/` | 75 行清单（包名/层/类型数/源码路径/状态）+ 首批目录 | 清单计数=75/698；路径映射无缺失；首批目录存在 |
| B0.4 | 1.x 基线 | QA | B0.1 | 无代码 | 门禁日志/commit | `xdk.sh`+`xdk_core.sh` 绿 |
| B0.5 | 注解诊断码冻结 | ARCH | 无 | `ANNOTATION-PLAN.md` | `AN0001`–`AN0020` | 文档签字，无待定 |
| B0.6 | P0.5 类型改名 | ARCH | B0.1 | `docs/design/utils/**`、`solutions/**`、`network/net/tls/**` | 8 组改名 + 引用 | `check_doc_naming`/links 绿 |
| B0.7 | 1.x core 文档回写 | ARCH | B0.1 | `docs/design/core/**` | C7 ledger 同步 | PASS（ledger）；C7 合同整合已合并（`d01943ba`）；B5 负责实现/验证 |

### B1：注解编译器最小闭环

| ID | 工作包 | Owner | 依赖 | 文件域 | 产物 | 出口 |
| --- | --- | --- | --- | --- | --- | --- |
| B1.1 | 注解 AST/parser | COMPILER | B0.5 | `src/mini/main.x`：`AstNode`、`Parser.parseTop`/`parseClassDecl`/`parseEnum`/`parseProtocol`/`parseFunc`/`parseBlock`/`parseExpr` | `AnnotationDecl`/`AnnotationUse`/`AnnotationArg` AST | `@annotation` + `@Name(...)` dump 正确 |
| B1.2 | 注解类型解析 | COMPILER | B1.1 | `Mono`/新 `AnnotationChecker` | 包/导入解析、未知注解 `AN0001` | 未知/同名/未导入用例 |
| B1.3 | 目标/保留/重复 | COMPILER | B1.2 | `AnnotationChecker` | 11 目标表、3 保留、`@Repeatable` 保序 | `AN0002`/`AN0003`/`AN0011` 用例 |
| B1.4 | 常量求值/默认值 | COMPILER | B1.2 | `AnnotationChecker`/常量求值器 | 标量/枚举/数组/嵌套/类型引用；尾部默认值 | `AN0004`–`AN0008` 用例 |
| B1.5 | 内建强制 | COMPILER | B1.2 | `AnnotationChecker`/类型检查 | `@ReadOnly`/`@Override`/`@Deprecated`/`@SuppressWarnings` | `AN0012`–`AN0015` 用例 |
| B1.6 | 注解测试门禁 | QA | B1.1–B1.5 | `src/mini/tests/xdk2/annotations/`、`xdk2.sh` | `.x`+`.out` 正/负例 | `xdk2.sh` 注解段绿 |

> 词法不需要大改：`src/mini/main.x:9831` 的 `lex()` 已把 `@` 产出为 `punct`；第一刀在 `Parser`/`AstNode`/语义检查。

### B2：`xdk.annotations` 14 类型

| ID | 工作包 | Owner | 依赖 | 文件域 | 产物 | 出口 |
| --- | --- | --- | --- | --- | --- | --- |
| B2.1 | 14 类型源 | XDK-CORE | B1.5 | `src/xdk/annotations/Annotations.x` | Value/Protocol/Registry/Diagnostic/Enum | 类型可编译、构造/查询场景绿 |
| B2.2 | 只读注册表 | XDK-CORE | B2.1 | `src/xdk/annotations/` | `AnnotationRegistry` 静态表读取 | 目标/名称/重复项查询场景绿 |
| B2.3 | 编译器元数据发射 | COMPILER | B2.2 | `src/mini/main.x` | `Runtime` 注解静态表（版本/排序） | 生成表可被 B2.2 读 |
| B2.4 | 注解门禁 | QA | B2.1–B2.3 | `xdk2/annotations/` | 端到端场景 | `xdk2.sh` 绿 |

### B3：Runtime prelude

| ID | 工作包 | Owner | 依赖 | 文件域 | 产物 | 出口 |
| --- | --- | --- | --- | --- | --- | --- |
| B3.1 | `RuntimeMonitor` + raw | RUNTIME | B0.1 | `src/runtime/`、`src/ffi/runtime_raw.xfb`、`src/xdk/core/runtime/Runtime.x` | enter/exit/wait/notify | 并发/关闭场景绿 |
| B3.2 | `Context` 截止/等待 | RUNTIME/COMPILER | B3.1 + B1 合并 | `src/mini/main.x` 内建、`src/xdk/execution/` | deadline/cancel/wait | 已合并 `876b9320`；取消/超时/重复 wait 场景绿 |
| B3.3 | 泛型 `Pair`/`Entry` | XDK-CORE | B0.1 | `src/xdk/core/collections/Collections.x` | `Pair<A,B>`、`Entry<K,V>` | 1.x 兼容 + 2.x 场景 |
| B3.4 | `isFinite/isNaN`、`Bytes.alloc/empty`、errors helpers、`List.copy` | XDK-CORE | B0.1 | `src/xdk/core/math`、`core/bytes`、`core/errors`、`core/collections` | 顶层函数/构造 | prelude 场景绿 |
| B3.5 | prelude 门禁 | QA | B3.1–B3.4 | `xdk2/prelude/` | 场景 | `xdk2.sh` 绿 + 1.x 回归绿 |

### B4：第一批纯 XDK 包

| ID | 包 | Owner | 依赖 | 出口 |
| --- | --- | --- | --- | --- |
| B4.1 | `xdk.functional` | XDK-CORE | B3 | 场景绿 |
| B4.2 | `xdk.graph` | XDK-CORE | B3 | 场景绿 |
| B4.3 | `xdk.stats` | XDK-CORE | B3 | 场景绿；`BucketHistogram` 命名已执行 |
| B4.4 | `xdk.net.uri` | XDK-NET | B3 | 解析/编码场景绿 |
| B4.5 | `xdk.net.mime` | XDK-NET | B3 | MediaType 场景绿 |
| B4.6 | `xdk.tensor` | XDK-PLATFORM | B3 | CPU 张量场景绿 |
| B4.7 | `xdk.linalg` | XDK-PLATFORM | B3/B4.6 | LU/QR/SVD 场景绿 |
| B4.8 | `xdk.geo` | XDK-PLATFORM | B3 | 距离/投影场景绿 |

---

## 6. 每个工作包的完成定义（DoD）

一个包/工作包只有同时满足以下条件才算完成：

1. **契约**：对应类型 `.md` 已更新，签名/失败/取消/生命周期无“待定”。
2. **源码**：`src/xdk/<pkg>/` 存在，package 声明正确，公共类型齐全。
3. **场景**：`src/mini/tests/xdk2/<pkg>/` 有 `.x` + 精确 `.out`；至少覆盖成功、失败、边界、取消/关闭（适用时）。
4. **门禁**：`src/mini/build.sh`、`xdk2.sh`、`xdk.sh`、`xdk_core.sh`、`check_doc_naming.py`、link check 全绿。
5. **证据**：批末汇报附命令、退出码、场景输出、commit hash。
6. **干净**：worktree 无未提交文件；没有 `Partial`/`Blocked`/`TODO`/“下批再做”作为批末状态。
7. **不回归**：1.x 公开行为不变；破坏性 2.x 变化有 `DESIGN-CONSISTENCY.md` 记录。

---

## 7. 首批派工模板

> 这些是给实现 agent 的提示词骨架；不要由编排者自己写代码。

### 7.1 B0 方案落地 agent

```text
读 LOCAL_RULES.md 第 5/6 号、docs/design/ARCHITECTURE.md、PACKAGE-MAP.md、EXECUTION-PLAN.md。
本批 = B0：建 xdk-2 worktree、xdk2.sh、xdk2-packages.tsv、首批包目录、1.x 基线、诊断码冻结。
不写 XDK 包实现，不改 src/mini 的注解语义。
批内不跑门禁、不提交、不汇报；批末跑 build + xdk.sh + xdk_core.sh + xdk2.sh + check_doc_naming + link check，提交一次。
出口 = CR-0 的 CR-0.2–CR-0.8 全部绿；红门修不了才停。
```

### 7.2 B1 编译器注解 agent

```text
读 LOCAL_RULES.md 第 5/6 号、ANNOTATION-PLAN.md、ARCHITECTURE.md §8。
本批 = B1：Parser/AST/类型解析/目标/保留/重复/常量/内建/诊断。
文件域 = src/mini/main.x + src/mini/tests/xdk2/annotations/。不要写 xdk.annotations 14 类型，不要写处理器调度。
词法已把 @ 产出为 punct；从 Parser.parseTop 和 AstNode 开始。
批末一次 build + xdk2.sh + xdk.sh + xdk_core.sh，提交一次。
出口 = AN0001–AN0015 正/负例绿；不改变 1.x 语法行为。
```

### 7.3 B3 runtime prelude agent

```text
读 LOCAL_RULES.md 第 5/6 号、ARCHITECTURE.md §11、PACKAGE-MAP.md L1。
本批 = B3：RuntimeMonitor、Pair/Entry、isFinite/isNaN、Bytes.alloc/empty、errors helpers、List.copy；B3.2 Context deadline/wait 在 B1 合并后 rebase 继续，不是延期关闭项。
文件域 = src/runtime/、src/ffi/runtime_raw.xfb、src/xdk/core/runtime/、collections/、math/、bytes/、errors/、execution/。`src/mini/main.x` 是共享文件：按 EXECUTION-PLAN §4.4 与 B1 合并，保留双方语义，不丢泛型/List.copy/Bytes/注解任何一侧。
不要写 codec/net/platform。
批末一次 build + xdk2.sh + xdk.sh + xdk_core.sh，提交一次。
出口 = prelude 场景绿 + 1.x 回归绿 + main.x 冲突清单已交给 integration owner。
```

### 7.4 独立 review agent

```text
只审不写。检查：是否按 EXECUTION-PLAN 的 DoD、是否改了 1.x 公开行为、是否把未实现写成完成、是否有 TODO/Partial、是否 0 broken links、门禁输出是否可复现。
输出：PASS / RED + 具体文件/行/证据。
```

---

## 8. 门禁与证据

### 8.1 批末固定命令

```sh
src/mini/build.sh
src/mini/tests/xdk.sh
src/mini/tests/xdk_core.sh
src/mini/tests/xdk2.sh
python3 src/toolchain/check_doc_naming.py docs/design
# link check（B0.2 落地为脚本）
python3 src/toolchain/check_links.py docs/design
```

### 8.2 证据格式

```text
batch: B0
commit: <hash>
gate:
  build: PASS
  xdk.sh: PASS
  xdk_core.sh: PASS
  xdk2.sh: PASS
  check_doc_naming: PASS
  check_links: PASS
scenarios:
  <path>.x -> <path>.out (diff 0)
worktree: clean
```

### 8.3 禁止

- 用“文档完成”代替场景绿；
- 用 `Partial`/`Blocked`/`TODO` 作为批末状态；
- 改 `.out` 迁就实现；
- 删断言/换弱断言；
- 批内逐条提交/汇报；
- 在 `main` 上写 2.x。

---

## 9. 停止条件

只有以下情况允许停：

1. 批末门禁红，且批内无法修复；
2. 规范确实缺失，必须用户签字（`LOCAL_RULES` 第 4 号）；
3. 破坏性/不可逆操作；
4. 用户当场叫停或改变批次边界。

其他情况一律继续下一条，直到该批出口。

---

## 10. 第一轮实际安排

### 第一轮（B0）

| 动作 | Owner | 产出 |
| --- | --- | --- |
| 建 `xdk-2` worktree | ARCH | `XNull-xdk2` |
| 写 `xdk2.sh` + smoke 场景 | QA | 2.x 门禁入口 |
| 写 `xdk2-packages.tsv` + 首批目录 | ARCH/QA | 包清单/脚手架 |
| 跑 1.x 基线 | QA | 基线日志 |
| 冻结诊断码 | ARCH | `AN0001`–`AN0020` |
| 类型改名 + 1.x core 回写 | ARCH | P0.5/C7 |

**B0 出口 = CR-0。CR-0 之前不写 `xdk.annotations`、不写 `functional/graph/stats`、不写 `codec/net`。**

### 第二轮（B1 + B3 并行）

| Lane | Owner | 范围 |
| --- | --- | --- |
| Compiler | COMPILER | 注解 parser/AST/语义/诊断 |
| Runtime | RUNTIME | RuntimeMonitor/Context/Pair/math/bytes/errors |

### 第三轮（B2 + B4）

| Lane | Owner | 范围 |
| --- | --- | --- |
| Annotations | XDK-CORE | 14 类型 + 注册表 |
| Pure packages | XDK-CORE/XDK-NET/XDK-PLATFORM | functional/graph/stats/uri/mime/tensor/linalg/geo |

> 第三轮结束，2.x 才算“真正开始有 XDK 包”，而不是只有编译器/运行时前置。

---

## 11. 任务板状态

| 批次 | 状态 | 备注 |
| --- | --- | --- |
| P0 架构基线 | 已完成 | commit `81fddb7b` |
| B0 方案落地 | 已完成 | 见 §11.1；CR-0.2–CR-0.8 绿 |
| B1 注解编译器 | 已合并 | merge `c4dbdf54`；22 负例 + warning + AST 场景绿 |
| B2 注解类型 | 已完成（B2.1–B2.3） | merge `48ec4bae`；16 场景绿；B2.3 Registry 已生成 |
| B3 runtime prelude | 已完成（B3.1–B3.5） | merge `cce533f5` + B3.2 merge `876b9320`；prelude 12 场景绿 |
| C7 core 合同整合 | 合同已整合（待 B5 实现/验证） | merge `d01943ba`（源 `c0ab6d2a`）；B5 前不标完成 |
| B4 第一批纯包 | 已完成 | 8 包/34 类型；`xdk2.sh` 27 scenarios、`xdk2_extra.sh`、`xdk_core.sh`、full `xdk.sh` 142s PASS（§11.5） |
| B5 core 2.x | 未开工 | 等 B4 |
| B6–B10 | 未开工 | 按层推进 |

---

### 11.1 B0 执行证据（2026-11-22）

```text
branch: xdk-2
base: b95e4f76（包含 81fddb7b）
worktree: /Users/vjs/.local/share/opencode/worktree/0778d3/xdk-2
```

B0.1–B0.7：

| 项 | 结果 | 证据 |
| --- | --- | --- |
| B0.1 分支/worktree | PASS | `git switch -c xdk-2`；HEAD `b95e4f76` |
| B0.2 2.x 测试入口 | PASS | `src/mini/tests/xdk2.sh` + `xdk2/smoke/smoke.x/.out`；输出 `xdk2: PASS (1 scenario(s))` |
| B0.3 包清单 | PASS | `src/xdk/xdk2-packages.tsv` 75 包 / 698 类型；`annotations/`、`execution/` 首批目录存在 |
| B0.4 1.x 基线 | PASS | `src/mini/build.sh`、`xdk.sh`、`xdk_core.sh` 均 exit 0 |
| B0.5 诊断码 | PASS | `ANNOTATION-PLAN.md` §9 冻结 `AN0001`–`AN0020` |
| B0.6 P0.5 改名 | PASS | 10 个文件/9 组类型改名；链接与命名门禁绿 |
| B0.7 C7 回写 | PASS（ledger）；合同整合见 NEXT-01 | 10 个 core README 的 ledger 已升级为类型合同（C7）；B5 仍负责实现/验证，不宣称 B5 完成 |

B0.6 改名清单：

```text
stats/Histogram.md -> stats/BucketHistogram.md
metrics/Timer.md -> metrics/MetricTimer.md
audit/Redactor.md -> audit/AuditRedactor.md
net-service/ReconnectPolicy.md -> net-service/ServiceReconnectPolicy.md
net-service/ServiceState.md -> net-service/NetServiceState.md
numerics/Signal.md -> numerics/SignalBuffer.md
agent/Exporter.md -> agent/PipelineExporter.md
db/Batch.md -> db/DbBatch.md；ml/Batch.md -> ml/MlBatch.md
net/tls/PrivateKey.md -> net/tls/TlsPrivateKey.md
```

B0.7 回写文件：`core/{runtime,collections,log,cli,sys,time,meta,errors,config,io,fs}/README.md`。这里的 PASS 是 **ledger 完成**；C7 的 1.x → 2.x 类型合同整合已合并（merge `d01943ba`，源 `c0ab6d2a`；NEXT-01：合同已整合），B5 仍负责实现与 xdk2 + 1.x 回归，不在 B0 宣称 B5 完成。

批末门禁（本记录随后提交）：

```text
src/mini/build.sh                 PASS
src/mini/tests/xdk.sh             PASS
src/mini/tests/xdk_core.sh        PASS
src/mini/tests/xdk2.sh            PASS
python3 src/toolchain/check_doc_naming.py docs/design   PASS
python3 src/toolchain/check_links.py docs/design        PASS
```

**B0 时点缺口（历史记录）**：B1 注解编译器、B2 注解类型、B3 runtime prelude 未开工；B1/B3 已在 §11.2 合并，B3.2 已在 §11.3 合并。

### 11.2 Integration batch：B1 + B3

```text
B1 merge: c4dbdf54
B3 merge: cce533f5
integration commit: HEAD at 2026-11-22 (the commit containing this record)
worktree: /Users/vjs/.local/share/opencode/worktree/0778d3/xdk-2
```

冲突：`src/mini/main.x` 与 `src/mini/bin/mini.c` 为共享文件；本次 `ort` 自动合并，无冲突文件。合并后确认双方语义同时存在：

- B1：`AnnotationDecl` / `AnnotationUse` / 注解 parser/Checker；22 个负例、warning、AST 场景；
- B3：`findGenericClass`、泛型 `Pair`/`Entry`、`Bytes.alloc`、`List.copy`、runtime monitor；
- 没有回退任一侧，也没有修改期望值迁就实现。

门禁：

```text
src/mini/build.sh            PASS
src/mini/tests/xdk2.sh       PASS（11 scenario(s)；22 negative；warning；AST）
src/mini/tests/xdk.sh        PASS
src/mini/tests/xdk_core.sh   PASS
src/runtime/build_rt.sh      PASS（无参全量 C 套件）
check_doc_naming             PASS
check_links                  PASS
```

B3.2 `Context` deadline/wait 在本批仍 **OPEN**；随后在 §11.3 合并完成。B1/B3 在本批只标“已合并”。

### 11.3 B3.2 integration：Context deadline/wait

```text
B3.2 merge: 876b9320（--no-ff，B3 branch tip 8a76b7bb）
base: c2974f2c
worktree: /Users/vjs/.local/share/opencode/worktree/0778d3/xdk-2
```

合并：`git merge-tree` 预演无冲突，`git merge --no-ff b3-runtime` 由 `ort` 自动合并；未丢 `Context`、注解或泛型任一侧。

B3.2 场景 `src/mini/tests/xdk2/prelude/context_deadline.x/.out` 覆盖：

- `Context.withCancel` / `withDeadline` / `withTimeout` / `wait`；
- 父取消传播到子，子取消不反向影响父；
- 相对超时与绝对截止到期取消；
- 已过期截止/零超时立即取消，`wait` 不阻塞；
- 重复 `wait` / 重复 `cancel` 幂等；
- 另一任务取消唤醒主线程 `wait`。

门禁：

```text
src/mini/build.sh            PASS
src/mini/tests/xdk2.sh       PASS（12 scenario(s)；22 negative；warning；AST；context_deadline）
src/mini/tests/xdk.sh        PASS
src/mini/tests/xdk_core.sh   PASS
src/runtime/build_rt.sh      PASS（无参全量 C 套件）
check_doc_naming             PASS
check_links                  PASS
```

B3 最终状态：**已完成（B3.1–B3.5）**。B2 在本批之后由 §11.4 合并完成；本批不开始 B2.3/B4。

### 11.4 B2 integration：`xdk.annotations` 14 类型与 Registry

```text
B2 merge: 48ec4bae（--no-ff，B2 branch tip 1abcb8da）
base: 248fccb0
worktree: /Users/vjs/.local/share/opencode/worktree/0778d3/xdk-2
```

合并：`merge-tree` 预演无冲突；`ort` 自动合并，无冲突文件。B1 注解、B3 `Context`/泛型、B2 Registry/14 类型三侧同时保留。

验证：

- `import xdk.annotations` 直接可用；`annotations_types_*` 测试无 `annotations` 符号链接；
- `xdkAnnotationRegistry()` / `xdkAnnotationRegistryVersion()` 是编译期生成入口，查询只读静态表；
- `annotations_types_runtime_registry.x/.out` 通过；
- B2-fix 四项通过：无 `xdk.collections` 依赖、`Float` 作为 `Double` 别名、枚举不可为 null、`targetKey(Annotation)` 为 `annotation:` 分支。

门禁：

```text
src/mini/build.sh            PASS
src/mini/tests/xdk2.sh       PASS（16 scenario(s)；22 negative；warning；AST；registry）
src/mini/tests/xdk.sh        PASS
src/mini/tests/xdk_core.sh   PASS
src/runtime/build_rt.sh      PASS（无参全量 C 套件）
check_doc_naming             PASS
check_links                  PASS
```

B2 最终状态：**已完成（B2.1–B2.3）**，B2.3 Registry 由编译器生成只读表。

S3 注解三块已关闭，B4 已完成：

- `Deinit`：`20f82bf5`；`deinit` 声明、`@Target(Deinit)`、注册表 `owner#deinit()` 与 GC 钩子已落地；`deinit.sh` 12 cases PASS。
- `TypeUse`：`ab7e2a47`；`@Foo Type` 支持字段/参数/返回/局部类型，消歧与注册表已落地；`typeuse.sh` 3 正例 + 6 负例 PASS。
- 跨包注解 use 预解析：`11298b82`；注册表 `typeName` 使用全限定名，`cross_package.sh` 输出 `true/true/true`，双导入歧义 `AN0001`。
- 11 个注解目标现在都有至少一个合法挂载点。
- 仍保留：`@pkg.a.Marker` 源码点号路径尚未解析；跨包注解通过导入 + 简单名或声明包解析。

B4 已完成。

### 11.5 B4 完成：8 包 / 34 类型

- 债表：[`DEBT-REGISTER.md`](DEBT-REGISTER.md)
- B4 包：`functional`、`graph`、`stats`、`net.uri`、`net.mime`、`tensor`、`linalg`、`geo`，合计 8 包 / 34 类型。
- 验收证据：
  - `xdk2.sh` 27 scenarios PASS；`xdk2_extra.sh` PASS；`xdk_core.sh` PASS。
  - 完整 `xdk.sh` exit 0，142s，最后 `mini xdk: PASS`。
  - tensor：`src/mini/tests/xdk2/tensor/tensor.x/.out`、`tensor_panic.sh` 6/6 PASS。
  - `check_b4_contracts.py`、`check_b4_status.py` PASS。
- B4-01/P11 与 B4-02/P8 已关闭；C7 合同已整合待 B5，B5–B10 未开工。
- 债表计数：45 条 = 0 B4 阻塞 + 26 后续批次 + 13 1.x/post-1.0/owner accepted + 1 BLOCKED + 5 已关闭（S3 3 + B4 2）。
- 已知残余不影响 B4 合同：functional 嵌套 inline lambda 链、graph `describe()` 文本、linalg Int64 `>2^53`/大矩阵 panic 未单列。

## 12. 一句话收口

**先 B0 把“开工条件”做实，再 B1/B3 并行，B2/B4 出第一批可验收包；不要从 75 包同时铺开，也不要在 `main` 上写 2.x。**

B4 已完成（8 包 / 34 类型 + full `xdk.sh`）；入口与关闭证据见 §11.5。下一步 B5 仍需 owner 对剩余运行时分项做实现/waiver 决定；C7 实现/验证归 B5。
