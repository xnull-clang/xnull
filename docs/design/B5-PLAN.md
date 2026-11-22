# B5 core 15 包实施计划

| 项 | 值 |
| --- | --- |
| 状态 | Draft for B5 owner acceptance；B5 未 GO、未开工 |
| 基线 | 分支 `b5-plan` @ `d419b208`（C7 merge `d01943ba` / 源 `c0ab6d2a`） |
| 范围 | 仅 L1–L3 的 15 个 core 包；不包含 B4/B6–B10 实现 |
| 计数 | 15 包 / 186 类型 |
| 权威 | [`DEBT-REGISTER.md`](DEBT-REGISTER.md)、[`EXECUTION-PLAN.md`](EXECUTION-PLAN.md)、[`PACKAGE-MAP.md`](PACKAGE-MAP.md)、[`PLAN.md`](PLAN.md) |
| 合同 | [`core/`](core/README.md) 的逐类型合同；C7 已整合，B5 只实现/验证 |
| 范围不变量 | UI/桌面/显示/音频/输入/电源/剪贴板/通知/托盘/文件对话框不在 XDK 范围 |

本计划只整理 B5 目标、债务、工作包、并行车道与入口/出口；不实现代码、不修改 core 类型合同、不修改债表/执行计划/README。

---

## 1. B5 目标与边界

### 1.1 目标

B5 把 L1–L3 的 15 个 core 包从“有 2.x 合同/设计”推进到“2.x 实现 + 验证”：

| 组 | 包 | 类型 |
| --- | --- | ---: |
| foundation | `xdk.errors`、`xdk.meta`、`xdk.bytes`、`xdk.text`、`xdk.collections`、`xdk.math`、`xdk.time` | 80 |
| io/fs/sys | `xdk.io`、`xdk.fs`、`xdk.sys` | 42 |
| log/config/cli | `xdk.log`、`xdk.config`、`xdk.cli` | 39 |
| execution | `xdk.runtime`、`xdk.execution` | 25 |
| **合计** | **15 包** | **186** |

C7 已整合的合同覆盖其中 11 包 / 147 类型：`runtime`、`collections`、`log`、`cli`、`sys`、`time`、`meta`、`errors`、`config`、`io`、`fs`。B5 另外实现 4 包 / 39 类型：`bytes`、`text`、`math`、`execution`。

### 1.2 B5 必须交付

1. 15 包 / 186 类型按逐类型合同实现，包级 `Verified`。
2. C7：11 包 1.x 已实现面完成实现/验证，不再只是合同整合。
3. API-SURFACE 按逐类型合同重生成（至少 core；utils 归 B6 对照）。
4. `TimeZone` 固定偏移面：`FixedOffset`、`toZone`、`offsetSeconds`。
5. execution/sync 的 X1-05–X1-13 逐条关闭：实现或 owner waiver，不能拿 X 当关闭。
6. `xdk2` 场景 + `xdk`/`xdk_core` 1.x 回归 + 文档/空白门禁全绿。
7. 15 包 B5 出口证据：逐包场景、门禁输出、commit、债表状态更新。

### 1.3 明确不做

- 不实现 B4 的 8 个纯包（`functional/graph/stats/net.uri/net.mime/tensor/linalg/geo`）。
- 不实现 B6–B10 的 data/encoding/network/platform/services/solutions 包。
- 不新增包、类型或公开 API；15 包 / 186 类型计数冻结。
- 不修改 C7 已整合合同；实现发现合同缺口时，先走独立合同修正，再实现。
- 不把 UI/桌面能力重新登记为包、类型、字段、任务或债务。

### 1.4 现状证据

- [`core/STATUS.md`](core/STATUS.md)：1.x mini 状态为 errors/runtime/meta/bytes/math/time/log/config/cli `Verified（mini）`，text/collections/io/fs/sys `Partial（mini）`；execution 的 tasks/sync 是 1.x 内建部分。`Verified（mini）` **不是** 2.x `Verified`，B5 必须重跑 2.x 场景。
- `t0/01`–`t0/16`：1.x 实现事实；C7 已把这些能力写入 2.x 类型合同，B5 以合同为实现依据，不以 t0 反向覆盖合同。
- [`PACKAGE-MAP.md`](PACKAGE-MAP.md) L1–L3：15 包 / 186 类型；[`PLAN.md`](PLAN.md) 规定 B5 在 B4 之后、B6 之前。

---

## 2. B5 债务清单

> 只抽取 B5 直接相关项，不复制 [`DEBT-REGISTER.md`](DEBT-REGISTER.md) 全文。B5 债 = 12 条具体债 + 1 条批次伞项（NEXT-21）。状态均为“待 owner 接受”；B5 未 GO。

| ID | 来源 | 债务 | B5 关闭证据 | 状态 |
| --- | --- | --- | --- | --- |
| B5-D01 | NEXT-01 / C7 | 1.x 已实现 API 合同已整合，待实现/验证 | 11 个 C7 包逐包场景 + `xdk2` + 1.x 回归 + commit | 待 owner 接受 |
| B5-D02 | NEXT-02 / S7/U1 | `API-SURFACE.md`（及 utils 对照）仍是旧广度稿 | 从类型合同重生成 core API 面；旧名不进实现；`check_doc_naming`/links 绿；commit | 待 owner 接受 |
| B5-D03 | X1-02 | 1.x UTC-only；2.x `TimeZone` 固定偏移未实现 | `FixedOffset`/`toZone`/`offsetSeconds` 合同 + 场景 + 回归 + commit | 待 owner 接受 |
| B5-D04 | X1-05 | 1.x tasks `select`/`race` 是规范非目标 | `Select`/`Future`/`Promise` 实现或 owner waiver；场景 + commit | 待 owner 接受 |
| B5-D05 | X1-06 | 1.x `Context` 值语义是规范非目标 | Context 值/传播/等待合同 + 场景 + commit | 待 owner 接受 |
| B5-D06 | X1-07 | 1.x 取消作用域是规范非目标 | TaskGroup/Context 取消作用域 + 取消/超时场景 + commit | 待 owner 接受 |
| B5-D07 | X1-08 | 1.x `RwLock` 是规范非目标 | `RwLock` 并发场景 + commit | 待 owner 接受 |
| B5-D08 | X1-09 | 1.x `Semaphore` 是规范非目标 | `Semaphore` 许可/取消场景 + commit | 待 owner 接受 |
| B5-D09 | X1-10 | 1.x `WaitGroup` 是规范非目标 | `WaitGroup` 完成/取消场景 + commit | 待 owner 接受 |
| B5-D10 | X1-11 | 1.x `Once` 是规范非目标 | `Once` 并发只执行一次场景 + commit | 待 owner 接受 |
| B5-D11 | X1-12 | 1.x `Barrier` 是规范非目标 | `Barrier` 实现或 owner waiver；场景 + commit | 待 owner 接受 |
| B5-D12 | X1-13 | 1.x sync `select` 是规范非目标 | sync select 语义 + 取消/超时场景 + commit | 待 owner 接受 |
| B5-UMB | NEXT-21 | B5 core 15 包 / 186 类型未开工 | 15 包 Verified + C7 + 全门禁 + commit | 待 owner 接受 |

### 2.1 不直接进入 B5 的 U/P/X

| 项 | 归属 | 与 B5 的关系 |
| --- | --- | --- |
| U5–U11（crypto/compress/metrics） | B6/B9 | 不阻塞 B5；B5 只引用其稳定接口 |
| P6/P7/P9/P10（平台适配/错误/生命周期/相关类型） | B8（P10 兼 B4/B8） | 不阻塞 B5；B5 不实现平台包 |
| X1-01 random、X1-03 codec | B6 | 不阻塞 B5 |
| X1-04 真人 trial | QA | 不阻塞 B5 |
| N1 HTTP/2 | B7 | 不阻塞 B5 |
| X1–X5 solutions | B10 | 不阻塞 B5 |

B5 不因上述项未关闭而停；但 B5 不得声称它们完成。

---

## 3. 包分组与工作包

### 3.1 门禁记号

| 记号 | 内容 |
| --- | --- |
| `G0` | `src/mini/build.sh` PASS |
| `G1` | `src/mini/tests/xdk2.sh` + 包场景 `.x/.out` 已登记且 PASS |
| `G2` | `src/mini/tests/xdk.sh` + `src/mini/tests/xdk_core.sh` PASS（1.x 回归） |
| `G3` | `python3 src/toolchain/check_doc_naming.py docs/design` + `check_links.py docs/design` + `git diff --check` PASS |
| `G4` | B5 出口全门禁：`G0` + `G1` + `G2` + `src/runtime/build_rt.sh` + `G3` + 批末复盘 |

每个包出口 = `G0+G1+G2+G3`；B5 出口 = `G4`。

### 3.2 foundation（7 包 / 80 类型）

| WP | 包 / 类型 | 依赖 | 入口 | 出口 | 场景 | 门禁 | Owner | 并行/串行 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B5-F1 | `xdk.errors` / 16 | 无 | B5 GO；C7 errors 合同 | 16 类型 Verified；错误分类/报告/聚合/重试/sink/码表 | error taxonomy、report、group、retry、sink、code | G0–G3 | XDK-CORE | 串行第一 |
| B5-F2 | `xdk.meta` / 11 | 构建期/FFI | B5 GO；BuildInfo 合同 | 11 类型 Verified；BuildInfo/TargetInfo/Capability/Profile | buildinfo、capability、profile、target | G0–G3 | XDK-CORE / ARCH | 可与 F1 并行 |
| B5-F3 | `xdk.bytes` / 7 | F1 | F1 完成 | 7 类型 Verified；Bytes/BytesBuilder/BitSet/ByteBuffer/Reader/Writer | bytes、builder、bitset、bytebuffer、reader/writer | G0–G3 | XDK-CORE | F1 后并行 |
| B5-F4 | `xdk.text` / 11 | F1、F3 | F1/F3 完成 | 11 类型 Verified；Format/Regex/Match/Unicode/Escape/SB/Utf16 | format、regex、match、unicode、escape、stringbuilder | G0–G3 | XDK-CORE | F3 后串行 |
| B5-F5 | `xdk.collections` / 17 | F1 | F1 完成 | 17 类型 Verified；List/Map/Set/Pair/Entry/算法 | list、map、set、entry/pair、algorithms | G0–G3 | XDK-CORE | F1 后并行 |
| B5-F6 | `xdk.math` / 4 | F1、F4 | F1/F4 完成 | 4 类型 Verified；Int128/Decimal/Complex/RoundingMode | int128、decimal、complex、rounding | G0–G3 | XDK-CORE | F4 后串行 |
| B5-F7 | `xdk.time` / 14 | F1、X1 | F1/X1 完成 | 14 类型 Verified；Duration/DateTime/TimeZone/Stopwatch/Formatter/Parser | duration、datetime、timezone、stopwatch、layout、parse | G0–G3 | XDK-CORE | 可并行（依赖满足后） |

### 3.3 io/fs/sys（3 包 / 42 类型）

| WP | 包 / 类型 | 依赖 | 入口 | 出口 | 场景 | 门禁 | Owner | 并行/串行 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B5-S1 | `xdk.io` / 22 | F1、F3 | F1/F3 完成 | 22 类型 Verified；Reader/Writer/Buffered/Line/Chain/Tee/Limit/Counting/Peek/Stdio | read/write、buffered、line、chain、tee、limit、stdio、copy | G0–G3 | XDK-CORE | 串行先于 fs/sys |
| B5-S2 | `xdk.fs` / 12 | F1、F3、S1 | S1 完成 | 12 类型 Verified；Path/OpenOptions/File/Dir/Metadata/Permissions/Temp/Atomic/glob | path、open、metadata、permissions、temp、atomic、walk/glob | G0–G3 | XDK-CORE | 与 S3 并行 |
| B5-S3 | `xdk.sys` / 8 | F1、X1、S1 | S1/X1 完成 | 8 类型 Verified；Process/Env/Platform/Resource/Signal/SystemInfo | process、env、platform、resource、signal、stdio | G0–G3 | XDK-PLATFORM / RUNTIME | 与 S2 并行 |

### 3.4 log/config/cli（3 包 / 39 类型）

| WP | 包 / 类型 | 依赖 | 入口 | 出口 | 场景 | 门禁 | Owner | 并行/串行 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B5-L1 | `xdk.log` / 10 | F1、X1、F4、F7、S1 | 依赖完成 | 10 类型 Verified；Level/Field/Record/Sink/Formatter/Logger/Factory/Filter/Redactor/Sampler | level、field、sink、formatter、filter、redactor、sampler | G0–G3 | XDK-CORE | 与 L2 并行 |
| B5-L2 | `xdk.config` / 12 | F1、F2、F4、S2、S3 | 依赖完成 | 12 类型 Verified；Config/Source/Loader/Schema/Profile | source、overlay、typed、schema、profile | G0–G3 | XDK-CORE | 与 L1 并行 |
| B5-L3 | `xdk.cli` / 17 | F1、F3、F7、S1、S3、X2 | 依赖完成 | 17 类型 Verified；Args/OptionSpec/Parser/Help/Shell/CommandLine/CliRuntime | args、parser、help、shell、completionBash、defaults | G0–G3 | XDK-CORE / TOOLING | 必须串行最后 |

### 3.5 execution（2 包 / 25 类型）

| WP | 包 / 类型 | 依赖 | 入口 | 出口 | 场景 | 门禁 | Owner | 并行/串行 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B5-X1 | `xdk.runtime` / 8 | FFI/runtime | B5 GO；B3 prelude | 8 类型 Verified；RuntimeInfo/MemoryStats/TaskStats/Health/RuntimeStats | runtime info、stats、task、dump、health | G0–G3 | RUNTIME | 串行第一 |
| B5-X2 | `xdk.execution` / 17 | F1、X1 | F1/X1 完成 | 17 类型 Verified；Context/Task/TaskGroup/Mutex/Channel/Executor/Semaphore/RwLock/WaitGroup/Once/Pool/Future/Promise/Atomics | context、task、group、mutex、channel、executor、semaphore、rwlock、waitgroup、once、pool、future/promise、select/barrier | G0–G3 | RUNTIME / XDK-CORE | X1 后串行；核心切片先于 L3 |

### 3.6 工作包计数

- 包级工作包：**15**（F1–F7、S1–S3、L1–L3、X1–X2）。
- 集成检查点：**7**（W0 入口、W1 runtime/errors/meta、W2 bytes/collections/execution 核心、W3 text/math/time/execution 高级、W4 io/fs/sys、W5 log/config/cli、W6 B5 出口）。
- 共享文件门禁：**3**（`src/mini/main.x`/`mini.c`、`src/mini/tests/xdk2.sh`、`src/xdk/xdk2-packages.tsv`）。

---

## 4. 并行车道与集成顺序

### 4.1 依赖优先于四组标签

四组标签是**归属分组**，不是严格串行顺序。依赖图要求：

- `time`、`log`、`config`、`cli` 依赖 `runtime`；
- `cli` 依赖 `execution`；
- `fs`/`sys` 依赖 `io`。

因此 `runtime`/`execution` 不能在 `cli` 之后才做。落地顺序按 DAG，不按“execution 组最后”机械排序。

### 4.2 车道

| 车道 | 工作包 | 分支 / worktree（未来创建） | 写集 | 共享文件 |
| --- | --- | --- | --- | --- |
| R runtime/execution | X1–X2 | `b5-runtime` / `XNull-xdk2-b5-runtime` | `src/xdk/core/runtime/**`、`src/xdk/execution/**`、`src/runtime/**`、`src/ffi/runtime_raw.xfb` | 仅在缺原语时改 `src/mini/main.x`/`mini.c`，串行 |
| F foundation | F1–F7 | `b5-foundation` / `XNull-xdk2-b5-foundation` | `src/xdk/core/{errors,meta,bytes,text,collections,math,time}/**` | 不改共享测试/清单 |
| S io/fs/sys | S1–S3 | `b5-iofs` / `XNull-xdk2-b5-iofs` | `src/xdk/io/**`、`src/xdk/fs/**`、`src/xdk/core/sys/**` 或清单路径 | 不改共享测试/清单 |
| L log/config/cli | L1–L3 | `b5-app` / `XNull-xdk2-b5-app` | `src/xdk/log/**`、`src/xdk/config/**`、`src/xdk/cli/**` | 不改共享测试/清单 |
| I integration | 合并/门禁 | `b5-core` / `XNull-xdk2-b5-core` | `src/mini/tests/xdk2.sh`、`src/xdk/xdk2-packages.tsv`、`src/mini/main.x`/`mini.c` 合并 | 唯一 owner：QA/ARCH |

`b5-plan`（当前 docs worktree）只写本计划，不做实现。

### 4.3 集成顺序

1. **W0 入口**：B4 出口证据 + B5 owner 接受；创建 R/F/S/L/I 工作树；冻结 15/186 计数。
2. **W1 runtime + errors + meta**：R/X1、F/F1、F/F2 并行；合并到 I；跑 `G0–G3`。
3. **W2 bytes + collections + execution 核心**：F/F3、F/F5、R/X2 核心切片并行；合并；跑门禁。
4. **W3 text + math + time + execution 高级**：F/F4、F/F6、F/F7、R/X2 高级切片；按 F3→F4、F4→F6 串行；合并。
5. **W4 io/fs/sys**：S/S1 先落；S/S2 与 S/S3 并行；合并；跑 `G0–G3`。
6. **W5 log/config/cli**：L/L1 与 L/L2 并行；L/L3 最后（依赖 execution/time/io/sys）；合并；跑 `G0–G3`。
7. **W6 B5 出口**：API-SURFACE 重生成、C7 11 包验证、D01–D13 债表回写、`G4` 全门禁、批末复盘。

合并顺序：`R/F → I`、`S → I`、`L → I`；I 每次只合一条车道，合后跑全门禁，不为省时间跳过 1.x 回归。

### 4.4 共享文件规则

| 文件 | Owner | 规则 |
| --- | --- | --- |
| `src/mini/main.x` / `src/mini/bin/mini.c` | COMPILER / RUNTIME | 只有缺运行时/编译器原语时才改；R 车道提出，I 车道合并；合并后跑 B1/B3/B5 + 1.x 全回归 |
| `src/mini/tests/xdk2.sh` | QA | 只由 I/QA 追加场景；每个包场景合并后才登记；不并行编辑 |
| `src/xdk/xdk2-packages.tsv` | ARCH/QA | 75 包/698 类型冻结；B5 不新增包/类型；路径修正一次完成，不由包车道改 |
| `docs/design/core/**` | ARCH / 合同 owner | C7 合同冻结；B5 实现不改合同；发现缺口先独立合同修正，再实现 |
| `docs/design/B5-PLAN.md` | ARCH | 本计划只读；执行偏差先改计划并签字，不在 worktree 私自改 |

---

## 5. 债清零标准

### 5.1 通用标准

一条 B5 债关闭必须同时有：

1. **Owner 接受**：owner 在债表/计划中确认关闭标准；不接受就不算关闭。
2. **实现/验证**：源码、类型、合同一致；不是只写 ledger 或只冻结合同。
3. **场景/门禁**：`.x` + `.out` 场景登记；`G0–G3` 通过；1.x 回归不退化。
4. **Commit**：包/债对应提交，附命令与退出码。
5. **债表回写**：B5 实现批可更新 [`DEBT-REGISTER.md`](DEBT-REGISTER.md) 状态；本计划批不改。

明确禁止：

- 把“合同已整合/冻结”当成 C7 或 B5 完成；
- 把 `X` 标记当成 X1-05–X1-13 关闭；
- 用 `Partial`/“后续补”作为包出口；
- 用旧 `API-SURFACE.md` 或旧名作为实现依据；
- 为让场景变绿修改 `.out` 期望值。

### 5.2 债关闭矩阵

| 债 | Owner 接受 | 实现/验证 | 场景/门禁 | Commit |
| --- | --- | --- | --- | --- |
| B5-D01 C7 | ARCH + XDK-CORE | 11 包 147 类型实现/验证 | 11 包场景 + `xdk2` + 1.x | 逐包/批末 commit |
| B5-D02 API-SURFACE | ARCH | 从合同重生成 core API 面 | `check_doc_naming`/links + 旧名扫描 | docs commit |
| B5-D03 TimeZone | XDK-CORE | `FixedOffset`/`toZone`/`offsetSeconds` | 固定偏移/往返/边界场景 | time commit |
| B5-D04 select/race | RUNTIME | `Select`/`Future`/`Promise` 或 waiver | 选择/取消/超时场景 | execution commit |
| B5-D05 Context 值 | RUNTIME | Context 值/传播/等待 | 父子/重复 wait 场景 | execution commit |
| B5-D06 取消作用域 | RUNTIME | TaskGroup/Context 取消 | 取消传播/隔离场景 | execution commit |
| B5-D07 RwLock | RUNTIME | 读写锁 | 并发读/单写/取消 | execution commit |
| B5-D08 Semaphore | RUNTIME | 许可计数 | 许可/超时/取消 | execution commit |
| B5-D09 WaitGroup | RUNTIME | 等待计数 | 完成/取消/重复 wait | execution commit |
| B5-D10 Once | RUNTIME | 只执行一次 | 并发/异常传播 | execution commit |
| B5-D11 Barrier | RUNTIME | `Barrier` 或 waiver | 到达/释放/取消 | execution commit |
| B5-D12 sync select | RUNTIME | select 语义 | 多通道/取消/超时 | execution commit |
| B5-UMB 15/186 | XDK-CORE + RUNTIME | 15 包 Verified | `G4` + 批末复盘 | B5 出口 commit |

`waiver` 只能由 owner 明确签字并写入债表；waiver 不是“实现完成”，B5 出口不得把它算作 Verified。

---

## 6. B5 入口与出口

### 6.1 入口

**B5 未 GO、未开工。B4 完成前 B5 不 GO；B5 完成前 B6 不 GO。** 当前 B4 仍 NO-GO；B5 必须等 B4 出口：

1. B4 owner 接受 [`DEBT-REGISTER.md`](DEBT-REGISTER.md) 与 B4-01/B4-02 冻结决定。
2. B4 8 包（34 类型）实现/验证完成，B4 出口证据齐全。
3. B4 合并到 2.x 基线；`xdk2` + 1.x 回归绿。
4. B5 owner 接受本计划与 B5 债表；15/186 计数冻结。
5. B5 工作树/车道/共享文件 owner 就位。

以上任一未满足，B5 不 GO；不在 B4 未完成时写 B5 实现。

### 6.2 出口

B5 完成必须同时满足：

1. 15 包 / 186 类型全部 `Verified`；无 `Partial`、无 TODO 出口。
2. C7 11 包实现/验证完成，`xdk2` + 1.x 回归绿。
3. B5-D01–B5-D13 全部关闭：实现或 owner waiver，债表有 commit/场景/门禁。
4. `API-SURFACE.md` 从合同重生成；旧名不进入实现；core 对照通过。
5. `G4` 全门禁通过：build/xdk2/xdk/xdk_core/build_rt/docs/diff。
6. B5 出口报告写 `Verified`/`RED`；B6 入口单列 `GO/NO-GO`。
7. 批末复盘通过 `.agent/bin/check.py`。

**B5 完成后 B6 才能开**；B5 出口报告不得用“B5 合同已整合/包已开工”替代 Verified。

---

## 7. 风险 / BLOCKED

> 下列不是 B5 可关闭项；只在本批相关时引用，不冒充关闭。

| ID | 风险/阻塞 | 对 B5 的影响 | 处理 |
| --- | --- | --- | --- |
| B5-R01 | B4 未完成/未 GO | B5 不能开工 | 等 B4 出口；不借用 B4 worktree、不预写 B5 实现 |
| B5-R02 | BLK-02 `Deinit` 无源语法 | B5 core 不依赖该注解目标 | 不进入 B5 出口；若某 B5 包需要 Deinit，单条 BLOCKED |
| B5-R03 | BLK-03 `TypeUse` 无位置语法 | B5 core 不依赖 type-use 注解 | 不进入 B5 出口；需要时单条 BLOCKED |
| B5-R04 | BLK-04 跨包注解 FQN 受限 | 只有 B5 包使用跨包领域注解时才受影响 | 避免跨包注解；若使用则该项 BLOCKED，不宣称全部注解可用 |
| B5-R05 | BLK-01 U3 官方 0.3.0 缺 bootstrap | B5 1.x 回归用当前 1.x 基线，不依赖官方 0.3.0 | 保持 BLOCKED；不宣称官方 0.3.0 已升级 |
| B5-R06 | execution 合同把 `Select`/`Barrier`/`Context` 值/取消作用域/`TimeZone` 标 X | B5 债 D03/D04/D05/D06/D11 不能靠 X 关闭 | owner 先决定实现或 waiver；实现前先改合同，再写代码 |
| B5-R07 | 共享 `src/mini/main.x` / `mini.c` 改动 | 可能回归 B1/B3 | 只在 R/I 车道串行改；合后跑全回归 |
| B5-R08 | API-SURFACE 生成器缺失/旧名残留 | D02 不能关闭 | 生成器缺失则 BLOCKED + 证据；不手改旧名冒充生成 |
| B5-R09 | UI/桌面范围回潮 | 破坏 75/698 计数与范围不变量 | grep 只允许“不在范围/已移除”；不新增包/类型/字段/任务 |

---

## 8. 与 B4 的交叉规则

1. **只读 B4 状态**：B5 计划读取 [`DEBT-REGISTER.md`](DEBT-REGISTER.md) 的 B4 状态；不修改 B4 债表/合同/计划。
2. **B4 未完成不写 B5 实现**：B5 实现只在 B4 出口后开始；B4 未 GO 时 B5 只做计划/评审。
3. **不同 worktree/分支**：B4 与 B5 不共用实现 worktree；B4 工作树不合并 B5 代码，B5 工作树不 cherry-pick B4 半成品。
4. **写集不重叠**：B4 写 L4/L5/L6 纯包；B5 写 L1–L3 core；`src/mini/main.x`/测试清单只在各自集成车道串行触碰。
5. **合同依赖**：B4 若改动 core 合同（不应发生），B5 在 B4 合并后 rebase；不静默改合同迁就 B4。
6. **门禁独立**：B4 出口与 B5 出口各自跑全门禁；B4 的 PASS 不能替代 B5 的 `G4`。
7. **债表独立**：B4 关闭 B4-01/B4-02；B5 关闭 B5-D01–D13；互不代签。

---

## 9. 本计划批验收

本批只交付本文件：

- 只改 `docs/design/B5-PLAN.md`；不改 `DEBT-REGISTER.md`/`EXECUTION-PLAN.md`/`PLAN.md`/`README.md`/core 合同。
- `check_doc_naming` PASS；`check_links` PASS；`git diff --check` PASS。
- UI/桌面实际包/类型引用为 0；只允许范围声明。
- 提交一次到 `b5-plan`；不 merge `main`；不动 stash/release。

后续 B5 实现批的出口按 §6.2 执行；本文件不宣布 B5 GO。
