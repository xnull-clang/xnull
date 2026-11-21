# mini 1.0 —— 发布计划（2026-11-21）

| 项 | 值 |
| --- | --- |
| 状态 | Draft for sign-off（C0/C1/U 未关闭、X 账本 0 signed closed、3 Deferred candidate 待会议） |
| 适用 | mini 1.0 发布列车：编译器 + C runtime + XDK + 工具链 + 发布物 |
| 权威 | P9 已由用户确认（2026-11-21）；P1–P8、P10 为建议或待签；本文件只管“1.0 范围、分层、门禁、顺序” |
| 不改变 | `docs/design/core/*` 的能力契约；`CORE-CLOSURE.md` 的批次范围 |
| 执行 | 严格按 `LOCAL_RULES.md` 第 5 号：批内不逐条验收/提交，批末一次门禁与提交 |
| 本次范围 | 只改本文件；不改代码、core 文档、`LOCAL_RULES`、测试；不提交 |

---

## 本次修改映射（2026-11-21）

| # | 修改要求 | 落点 |
| --- | --- | --- |
| 1 | 0.9.0 改为 Plan C；拆 `K Verified` / `1.0 Verified` | §1.2、§4 |
| 2 | 新增 C0 干净核心门禁，作为 0.9.0 exit gate；C0b 管 0.9.1–0.9.2 还债 | §5、§5.1 |
| 3 | 新增 C1 核心完整门禁，置于 0.9.4 | §6 |
| 4 | 新增 U0–U5 用户旅程门禁，置于 rc.1 前 | §7 |
| 5 | X disposition 表进附录，14 包逐项 | §15 |
| 6 | R1/R4/R0/R9/DET-01 写成可判定门禁 | §10 |
| 7 | P1–P10 给 A/B/C，含成本、风险、影响、失去什么 | §9 |
| 8 | W1–W13 并入 8 项方案 | §8 |
| 9 | 文档卫生：状态、清单、P9 同步、措辞 | 头部、§12、§13、§16 |
| 10 | 闭包账本三态 + 26 个 post 项重评 | §15.1–§15.3 |
| 11 | 兼容/影响政策（加法 API、deprecated、flag、adapter） | §15.4 |

---

## 0. 先回答：为什么现在只能算 0.9

上一版只覆盖了“分层与所有权”，它是 1.0 的必要条件，不是 1.0 本身。

| 1.0 维度 | 上一版是否覆盖 | 现状 |
| --- | --- | --- |
| 分层 / 所有权 / FFI 目录 | 覆盖 | 只完成设计，未落地门禁 |
| 语言与编译器正确性 | 未覆盖 | mini 0.3.0；仍有推断、诊断、FFI lowering 缺口 |
| C runtime 正确性与 ABI | 未覆盖 | ABI v1 已锁定；无 sanitizer / 跨平台 / 兼容性门禁 |
| XDK 公共面 | 未覆盖 | 实时状态见 `AUDIT.md`；`tasks`/`sync` 按 P9=B 降为 deprecated 命名空间，不计入 1.0 包 |
| 并发 / 取消 | 未覆盖 | 能力在编译器内建类型，包本身没有实现 |
| 诊断 / 可观测 | 未覆盖 | 错误码仅见 `SEM-001..005`；`dumpTasks`/`stats` 无公开入口 |
| 工具链 / 构建 | 未覆盖 | 无复现构建/跨平台门禁；project/package 按 P3 待签 |
| 打包 / 版本 | 未覆盖 | mini 0.3.0、XDK 0.1.0；`xdk/index.json` 缺失 |
| 质量工程 | 未覆盖 | 无 CI、无 ASan/UBSan/TSan、无 fuzz、无覆盖率 |
| 平台矩阵 | 未覆盖 | 仅 `__APPLE__` / `__linux__` 分支；无 Windows |
| 性能 | 未覆盖 | 只有本地 `m10_perf`；历史读数不作基线 |
| 文档 / 迁移 / 安全 | 未覆盖 | 无迁移指南、无安全策略；`docs/zh/` 被 gitignore |
| IDE / 编辑器 | 未覆盖 | VS Code 语法 + index、Web IDE；无 LSP/调试器 |

**结论：上一版是 `0.9.0` 的架构门（W1），不是 1.0 计划。** 本文件把它降为 W1，并补齐 C0/C1/U、W2–W13。

---

## 1. 1.0 的产品承诺

mini 1.0 不是“功能最多”，而是“可以依赖”。发布时必须能对用户说清以下 10 条：

1. **语言子集固定**：规范里标为 1.0 的语法/语义全部实现；未实现的明确列为 post-1.0。
2. **编译器可诊断**：用户输入错误只产生 `file:line:col + code + message`，不出现内部 `fatal`。
3. **C runtime ABI v1 稳定**：已锁定符号不破坏；变更走主版本。
4. **XDK 1.0 公共面稳定**：14 个 1.0 包 `1.0 Verified`；API 清单锁定；废弃有周期。
5. **构建可复现**：同一输入、同一工具链，两次构建产物字节一致。
6. **平台矩阵明确**：每个支持平台都有 CI 证据，而不是“应该能跑”。
7. **并发语义可依赖**：任务、取消、Channel、Mutex 有压力测试和竞态门禁。
8. **性能有预算**：编译时间、运行时间、内存三条线，超线即红。
9. **质量有证据**：sanitizer、fuzz、泄漏、压力、差分、负例全部进门禁。
10. **发布物完整**：版本号、安装/卸载、校验和、许可证、release notes、迁移指南。

### 1.1 “mini 1.0”指什么

本文件的 1.0 是**发布列车**，不是只指 `mini` 二进制：

```text
mini compiler  +  C runtime  +  XDK  +  xnull CLI  +  发布/安装物
```

版本号是否全部对齐到 1.0，见 §9 的 P4。

### 1.2 两个状态词（强制）

| 状态 | 定义 | 落盘位置 |
| --- | --- | --- |
| `K Verified` | K 能力面可运行、场景绿；允许存在已登记的 X | 包设计 `当前状态`、`AUDIT.md` 的 K 列、`src/xdk/PLAN.md` 矩阵、`xdk/lib/xdk/PLAN.md` 镜像 |
| `1.0 Verified` | 1.0 合同内 X 全部有唯一去向；API 清单签字；`AUDIT.md` 独立签字 | 包设计 `当前状态`、`AUDIT.md` 的 1.0 列、`src/xdk/PLAN.md` 矩阵、`xdk/lib/xdk/PLAN.md` 镜像 |

规则：

- 禁止混用；禁止把 `K Verified` 写成 `1.0 Verified`。
- `1.0 Verified` 不接受批次 agent 自签；必须有独立复核行。
- 0.9.0 只给 CORE-CLOSURE 5 包 `1.0 Verified`；其余 9 包保持 `K Verified`。
- 0.9.4 才要求 14 包全部 `1.0 Verified`。

**状态落盘交付项（0.9.0 前）**：

| 文件 | 必须落盘 | 截止 |
| --- | --- | --- |
| `docs/design/core/AUDIT.md` | 增加 `K`、`1.0`、`Evidence`、`Reviewer`、`Date` 列；`Gate` 只保留门禁结果；`Verified` 另起签字行 | 0.9.0 |
| `src/xdk/PLAN.md` | 增加 `K`、`1.0`、`Owner`、`Evidence` 列 | 0.9.0 |
| `xdk/lib/xdk/PLAN.md` | 与 `src/xdk/PLAN.md` 镜像 | 0.9.0 |
| `src/ffi/capabilities.tsv` | 每个能力有稳定 id；owner、符号、证据、状态列 | 0.9.0 |
| `src/ffi/api-manifest.tsv` | package、symbol、signature、stability、owner、status；76871532：160 symbols / 14 packages | 5 包子集 0.9.0；14 包 0.9.4（已落盘） |
| `docs/design/core/*.md` | `当前状态` 使用 `K Verified` / `1.0 Verified` 标签 | 5 包 0.9.0；14 包 0.9.4 |

- `Gate PASS` 只保留为门禁结果；`Verified` 必须另起签字行，不得用 `Gate PASS` 代替。
- `AUDIT.md` 目前只有 `Package/Design/Implementation/Gate/Blocker`，缺 `K/1.0/Evidence/Reviewer/Date`；这是 0.9.0 的交付项，不是“应该有”。

---

## 2. 1.0 非目标（建议/待签）

以下内容不阻塞 1.0；未经用户签字不得拉进来：

- Windows 原生支持（P1 待签，默认不纳入）；
- LSP / 调试器 / formatter（P2 待签，默认不纳入）；project manager（P3 待签；U1 要求至少 project build，不含包管理）；
- 反射、宏、运算符重载、继承；
- 实时/嵌入式/自定义分配器；
- 跨主版本的二进制兼容；
-  包（网络、HTTP、随机、时区数据库等）；
- 完整的 IDE 产品化。

范围外的东西进入 `POST-1.0.md`（届时新建），不进入 1.0 批次。

---

## 3. 发布门禁 R0–R10

每次释放候选必须全绿；任一红即停止发布链。

| # | 门禁 | 证据 | 阻塞 |
| --- | --- | --- | --- |
| R0 | 构建与复现 | `build_rt.sh --lib`、`selfhost.sh`、两次构建哈希一致（§10.3）；macOS 需 `-Wl,-no_uuid` 或剥离 `LC_UUID` | 是 |
| R1 | 分层与所有权 | `check_layers.py`（G1–G3，§10.1）、0.9.0 allowlist 非空且每条有 owner/remove_batch、1.0 allowlist 为空、三组镜像一致 | 是 |
| R2 | 语言一致性 | 规范正例/负例、诊断码、无内部 fatal | 是 |
| R3 | runtime 正确性/ABI | `test_abi*`、GC/ARC、task/sync stress、泄漏、sanitizer | 是 |
| R4 | XDK 公共面 | 14 包 `1.0 Verified`；`AUDIT.md` 独立签字；API 清单签字；无骨架包 | 是 |
| R5 | 并发/取消 | 竞态、取消、deadline、channel close、长时压力 | 是 |
| R6 | 质量工程 | ASan/UBSan/TSan/fuzz、负例；valgrind 限 Linux x86_64 | 是 |
| R7 | 工具链 | CLI 合同、退出码、JSON、doctor/clean/resources | 是 |
| R8 | 平台矩阵 | 由 P1 决定的平台清单，每平台完整门禁 | 是 |
| R9 | 性能 | 编译/运行/内存预算，参考机中位数（§10.4） | 是 |
| R10 | 发布卫生 | 文档、迁移、安全、校验和、安装/卸载、release notes | 是 |

---

## 4. 版本阶梯（Plan C）

每个阶段 = 一个或多个批次；批末一次门禁与提交。

| 版本 | 主题 | 覆盖 | 退出条件 |
| --- | --- | --- | --- |
| C0 | 0.9.0 exit gate（干净核心） | W1 B0–B1（C0 自身） | §5 的 8 条全绿；C0 不过，0.9.0 不算完成 |
| 0.9.0 | 干净核心 + 核心层收口 | W1 + CORE-CLOSURE + P9 doc-only | 14 包 `K Verified`；CORE-CLOSURE 5 包 `1.0 Verified`；P9 的 7 份文档同步完成；C0 全绿 |
| 0.9.1 | 正确性还债 | W1 B2–B6 | env/时钟/sleep/platform/dump/Context 单一语义；allowlist 缩减 |
| 0.9.2 | runtime 硬化 | W3 + W9 | sanitizer/泄漏/压力矩阵绿；DET-01 权威页 |
| C0b | 正确性还债门禁（0.9.1–0.9.2 exit） | 0.9.1 + 0.9.2 | env/platform/sleep 单一语义；DET-01 权威页；5 包 `1.0` 签字复核；C0b 不过，0.9.2 不算完成 |
| 0.9.3 | 编译器硬化 | W2 + W6 | 一致性套件、错误码、通用 FFI、无内部 fatal |
| 0.9.4 | XDK 锁定 + 核心完整 | W4 + W5 + C1 | 14 包 `1.0 Verified`；C1 全绿；X 表签字；API 清单签字 |
| 0.9.5 | 工具链/打包/平台 | W7 + W8 + W10 | CLI 合同、复现构建、安装/卸载、平台矩阵绿 |
| 0.9.6 | 文档/安全/性能 | W11 + W12 | 迁移/安全/基准/release notes 完成 |
| 1.0.0-rc.1 | 用户旅程锁定 | 全部 + U0–U5 | U0–U5 全绿；只修 bug；连续两轮全门禁绿；外部 dogfood |
| 1.0.0 | 发布 | 全部 | R0–R10 + C0/C1/U 全绿；发布清单签字 |

### 4.1 依赖图

```text
W1 分层/所有权
  └─> C0（0.9.0 exit gate，§5）
        └─> 0.9.0：14 包 K + CORE-CLOSURE 5 包 1.0 + P9 文档同步
              └─> 0.9.1：正确性还债
                    └─> 0.9.2：W3 runtime + W9 质量 + DET-01
                          └─> C0b：env/platform/sleep 单一语义 + DET-01 + 5 包复核（§5.1）
                                └─> 0.9.3：W2 编译器 + W6 诊断
                                      └─> 0.9.4：W4 XDK + W5 并发 + C1
                                            └─> 0.9.5：W7/W8/W10
                                                  └─> 0.9.6：W11/W12
                                                        └─> rc.1：U0–U5
                                                              └─> 1.0.0
```

### 4.2 状态词与阶梯的硬约束

- 0.9.0 不得要求 14 包 `1.0 Verified`；只要求 14 包 `K Verified` + 5 包 `1.0 Verified`。
- 0.9.4 不得接受 `K Verified` 冒充 `1.0 Verified`。
- W4=0.9.4、W6=0.9.3 与 0.9.0 不再冲突：runtime 的 `dumpTasks`/`stats` 在 0.9.3 交付，0.9.4 才锁定 runtime 的 `1.0 Verified`。
- rc.1 前必须过 U0–U5（§7）；U5 不过，1.0 不算站起来。

---

## 5. C0 干净核心门禁（0.9.0 exit gate）

C0 是 0.9.0 的 exit gate，不是前置阶段，也不是 W1 的子项。C0 不过，0.9.0 不算完成。

| # | 判定 | 证据 | 失败处理 |
| --- | --- | --- | --- |
| C0-1 | 每个能力在 `capabilities.tsv` 有稳定 id 和唯一 owner；没有 owner-less 能力 | `capabilities.tsv` + G1 | owner 缺失/重复，停止 |
| C0-2 | 骨架/内建状态用 `kind=skeleton|builtin|real` 标记；`tasks`/`sync` 按 P9=B 为 `builtin`；**只要求 `runtime` 的 K 公开符号**（diagnose/exit/nowMono/nowWall）逐项有实现；dumpTasks/stats/RuntimeInfo 等 X 符号不在 C0 要求；不得用行数判定 | `capabilities.tsv` 的 kind 列；P9 文档同步；K 符号清单 | 仍有 skeleton 冒充 Verified，停止 |
| C0-3 | 核心 5 包的 `1.0 Verified` 有独立签字和证据行；批次 agent 不自签 | `AUDIT.md` 签字行；签字人不是批次 agent | 自签视为未完成 |
| C0-4 | 清掉“绿但错”的测试（String 排序、`writeText=0` 这类已固化 bug）；**归 W1 B0–B1** | W1 B0–B1 交付：`AUDIT.md` 红点清单 + 测试期望 diff；旧期望值必须改对 | 保留错误期望，停止 |
| C0-5 | `check_layers.py` 已建；B1/0.9.0 的 allowlist 非空，且每条有 owner + remove_batch；1.0 为空 | §10.1 的三阶段结果 | 脚本未建、条目无 owner/batch、或 1.0 非空，R1 红 |
| C0-6 | 三组镜像一致：`src/xdk`↔`xdk/lib/xdk`、`src/ffi`↔`xdk/ffi`、`src/runtime`↔`xdk/runtime`（排除测试/产物）；`rt.c` 不漂移；**归 W1 B0–B1** | W1 B0–B1 修正 + G3 输出；`rt.c` 哈希一致 | 任一差异，停止 |
| C0-7 | 核心 5 包的 X 表逐项签字（0.9.0 exit 前） | §15 签字列 | 未签 = 未完成 |
| C0-8 | 没有已知红；核心 5 包无未关闭 X（残余只列 ） | CORE-CLOSURE 5 包无未关闭 X（残余只列 ）；`AUDIT.md` 无红点 | 有红点或残留，停止 |

**核心包**在本节指 CORE-CLOSURE 的 5 包：io、collections、text、fs、sys。其余 9 包的 X 由 §15 的表决定，不在 C0 强制清空。

### 5.1 C0b 正确性还债门禁（0.9.1–0.9.2）

C0b 不 gate 0.9.0；它是 0.9.1–0.9.2 的 gate。C0b 不过，0.9.2 不算完成。

| # | 判定 | 证据 | 失败处理 |
| --- | --- | --- | --- |
| C0b-1 | env/platform/sleep 无双语义（0.9.1） | 双实现清单为空；单一 owner 场景 | 有分叉，停止 |
| C0b-2 | DET-01 有权威条目 + 正反例（0.9.2 / W3） | `docs/design` 或 S3 的 DET-01 页；`test_rt.c` 正反例 | 只写“必须有”，不算 |
| C0b-3 | 核心 5 包的 `1.0 Verified` 在还债后复核签字（0.9.2；初签在 0.9.0，复核不替代初签） | `AUDIT.md` 复核行 | 复核不过，回到 0.9.1 |

---

## 6. C1 核心完整门禁（0.9.4）

| # | 判定 | 证据 |
| --- | --- | --- |
| C1-1 | 14 包 1.0 合同全部有实现、场景、证据 | 每包 API 清单行 + 场景文件 + C 测试 + 门禁命令 |
| C1-2 | X 账本逐项状态：`Strict evidenced` / `Strict candidate` / `Optimized proposed` / `Optimized candidate` / `Deferred candidate` / `Out-of-scope / deferred`；只有 `Signed Strict closed` / `Signed Optimized closed` 计入 1.0；candidate 必须有缺口/补证路径 | §15 账本；批次不得改标 |
| C1-3 | 三个参考程序可运行 | CLI/并发/FFI 三个参考程序 **PASS（76871532）**；CLI unblocked（dd399cfb）；见 §6.1/§6.2 |
| C1-4 | API 清单签字 | 14 包逐包符号、签名、稳定性 |
| C1-5 | 独立审计记录；`xdk.sh`/`xdk_core.sh` 只是证据之一 | `AUDIT.md` 签字行；不是包完整性证明 |
| C1-6 | 闭包账本：每条 X 有唯一状态；0 个未签项被当作 closed；`Strict candidate` / `Optimized candidate` / `Optimized proposed` / `Out-of-scope` 签字前不计入 1.0；签字条件 = 保留 1.0 承诺 + 不改公共语义 + adapter/shim + 测试 + I/D/B/M + 用户/独立复核人签字 | §15 ledger；缺一项即红 |

### 6.1 三个参考程序

| 程序 | 覆盖 | 验收 |
| --- | --- | --- |
| CLI 工具 | **unblocked：dd399cfb**；config `FileSource`、cli 子命令/help、log `Field`/`Sink`/`ConsoleSink`/`MemorySink`、time 格式化；**默认输出只用 ConsoleSink**，MemorySink 只用于断言；File sink 是 ，不得默认写日志文件 | 构建、运行、`--help`、配置文件读取、日志字段输出到 console/stderr |
| 并发处理器 | `Task`/`Channel`/`Mutex`、取消、背压 | 10k 任务、取消风暴、channel 背压、无竞态 |
| FFI/字节程序 | FFI 调用、`Bytes`/`ByteReader`/`ByteWriter`、错误码 | 构建、运行、负例错误码 |

### 6.2 C1 evidence（base 76871532；file @a48a50f4）

证据文件：`core-evidence@a48a50f4:docs/design/t0/C1-U0-U5-EVIDENCE.md`。

| 项 | 状态 | 证据 |
| --- | --- | --- |
| U0 干净安装 | PASS | `release.sh` 两次 tarball 哈希一致 `9395415a…f63`；安装/doctor/hello PASS |
| U1 多文件构建 | PASS | `76871532`：`ref/project` 三文件工程 build/run `alpha=2 / 6`；改 count 重跑 `alpha=3 / 6` |
| U2 失败定位 | PASS | `xdk.runtime.dumpTasks()` 输出 `live/spawned/settled/carrier`；`ref/u2_task_dump.x` PASS |
| U3 0.x 升级 | PASS with substitute artifact | `76871532`：mini-v0.3.0 源码重建；官方 0.3.0 bootstrap 缺失（`xn-s4` 不存在）；official 0.3.0 blocked（xn-s4 卡死，已停）；不是官方包升级 |
| U4 参考负载 | PASS | `76871532`：`m10_perf` 5 次，200M 中位数 0.651s（0.888x） |
| U5 非作者文档 | agent proxy PASS；human pending | `76871532` 代理记录；真人 U5 未执行 |
| R0 构建复现 | PASS | `76871532`：`build_rt.sh --lib` + `selfhost.sh` 两次，rt hash 两次一致；release tarball `9395415a…f63` |
| R9 性能 | PASS | `76871532`：200M 中位数 0.651s（0.888x）；编译 2.10s；RSS 0.59/41.42MiB |
| API manifest | PASS | `api-manifest.tsv` 160 symbols / 14 packages，逐符号签名/稳定性 |
| CLI 参考程序 | PASS / unblocked | `dd399cfb`；默认 ConsoleSink |
| 并发参考程序 | PASS | `76871532`：`ref/concurrent.x` 10k tasks、Channel 背压、Mutex、取消 |
| FFI/字节参考程序 | PASS | `76871532`：`ref/ffi_bytes.x` |

C1 不过，0.9.4 不算完成/不得锁定。

---

## 7. U0–U5 用户旅程门禁（rc.1 前）

U 门禁验证“用户能不能用”，不是“作者能不能跑”。

| # | 场景 | 验收 | 证据 |
| --- | --- | --- | --- |
| U0 | 干净机器安装 | 只从发布物安装；`doctor` 绿；运行 hello | 安装脚本 + 输出 |
| U1 | 多文件程序构建/运行 | 非单文件项目；构建、运行、增量重跑 | 项目目录 + CLI 输出 |
| U2 | 用错误码/诊断/任务转储定位失败 | 注入一个错误；只看错误码、诊断、`dumpTasks` 定位 | 诊断输出 + 任务转储 |
| U3 | 从 0.x 升级 | **PASS with substitute artifact；official 0.3.0 blocked（xn-s4 卡死，已停）**：mini-v0.3.0 源码重建；官方 0.3.0 bootstrap 缺失（`xn-s4` 不存在），不是官方包升级 | 76871532 + 替代 artifact |
| U4 | 参考负载性能 | 固定参考机、N=7、中位数 ≤ 预算（§10.4） | §10.4 的中位数报告 |
| U5 | 非作者只看文档完成 U1 | **agent proxy PASS；human U5 pending** | 76871532 代理记录 + 待真人 |

**“非作者”判定**：未参与该包/该批次开发；不能读源码；只能读 `docs`、`examples`、`--help`；由用户指定至少 1 人；失败项先修文档再重试。

**U3 措辞**：`PASS with substitute artifact`；official 0.3.0 blocked（xn-s4 卡死，已停）。官方 0.3.0 bootstrap 缺失，`xn-s4` 不存在；这是源码重建基线，不是官方包升级。保留给用户决定：补官方构建，或接受源码重建基线。不得标 `Signed Strict closed` / `Signed Optimized closed`。

**U5 措辞**：`agent proxy PASS；human U5 pending`。代理记录不等于真人通过；human U5 仍待执行。

U5 human 不过，1.0 不算站起来。

**依赖冲突提示**：U1 要求多文件构建，因此 **P3=A（单文件 only）与 U1 冲突**；P3 至少为 B（project build，不含包管理）。P3 待用户签字。

---

## 8. 工作流 W1–W13

### W1 · 分层、所有权、FFI 目录

1. **范围**：L3→L2→L1 单向；每个能力唯一 owner；不放新 API。
2. **产物**：`capabilities.tsv`（稳定 id + kind 列）、`layer-allowlist.tsv`、`check_layers.py`、14 包清单、X 表、C0-4 测试期望修正、C0-6 镜像修正。
3. **证据**：`python3 src/toolchain/check_layers.py` 退出 0；B1/0.9.0 allowlist 非空且每条有 owner + remove_batch；1.0 allowlist 为空；脚本未建则 R1 红。
4. **依赖**：无；阻塞所有后续 W 和 C0。
5. **顺序**：B0 盘点 → B1 门禁 + C0-4/C0-6 → B2–B6 还债；C0 在 B1 后、0.9.0 exit。
6. **失败/回退**：allowlist 只减不增；红门停止；新增 allowlist 必须带移除批次。
7. **风险/缓解**：编译器 `ffiSpecial` 特例；缓解是 W2 的通用 FFI lowering。
8. **明确不做**：不新增 API、不改包名、不做大重构。

**所有权矩阵（用户决策）**：

| 能力 | Owner | 备注 |
| --- | --- | --- |
| `exit` / `diagnose` | `xdk.runtime` | 已归位 |
| `sleep`（含可取消）/ 延迟 / timer / `nowMicros` | `xdk.time` | tasks 不得 import time |
| `env` | `xdk.sys` | 统一为快照语义 |
| `dumpTasks` / `stats` | `xdk.runtime` | 新增公开面 |
| `platform` | `xdk.runtime` | meta/sys 改为委托 |
| `Context` / 取消 | 语言内建（P9=B） | 1.0 由语言规范定义；`xdk.tasks` 降为 deprecated 命名空间 |
| `nowMono` / `nowWall` | `xdk.runtime` | `xdk.time` 只包装 |
| `hostname` / `pid` / `cwd` / `chdir` | `xdk.sys`（推定，B0 确认） | |
| stdio | `xdk.io`（推定，B0 确认） | |

**四道门禁**：

- G1 所有权：非 owner 不得调用 L2 符号；例外进 allowlist（带 owner + 移除批次）。
- G2 符号闭环：`.xfb` ↔ C 定义 ↔ 编译器硬编码 cName 三方一致。
- G3 镜像：三组镜像一致；排除清单显式列出测试与产物。
- G4 两端同测：C 测试 + X 场景 + base/full parity + 负例。

### W2 · 语言与编译器正确性

1. **范围**：1.0 语言子集、诊断、通用 FFI lowering、Int 32 位审计、推断；不含 formatter/project。
2. **产物**：一致性套件、错误码注册表、fuzz 语料、通用 FFI lowering、Int 审计清单。
3. **证据**：`check.sh`、`sema.sh`、一致性 runner；期望 0；红 = 规范/实现不一致。
4. **依赖**：W1 的 L2 契约；阻塞 W4。
5. **顺序**：B2.1 Int 审计 → B2.2 诊断码 → B2.3 FFI lowering → B2.4 fuzz。
6. **失败/回退**：编译器缺口不修场景；红门停止；不得用弱断言迁就。
7. **风险/缓解**：推断回归；用 golden + 双跑对比。
8. **明确不做**：formatter、project build、宏、反射。

### W3 · C runtime 正确性与 ABI

1. **范围**：ABI v1、GC/ARC、task/sync、泄漏、sanitizer；不新增 XDK API。
2. **产物**：ABI 符号清单、sanitizer 脚本、压力测试、泄漏门禁、DET-01 权威页。
3. **证据**：`build_rt.sh` + ASan/UBSan/TSan；valgrind 仅 Linux；期望 0；红 = 任一 sanitizer 报告。
4. **依赖**：W1 的 G2/G3；阻塞 W4。
5. **顺序**：B3.1 ABI 清单 → B3.2 sanitizer → B3.3 压力 → B3.4 平台分支审计 → B3.5 DET-01。
6. **失败/回退**：红门停止；抑制必须签字并写原因。
7. **风险/缓解**：macOS arm64 无 valgrind；按平台拆分；TSan 不可用则记录例外。
8. **明确不做**：Windows、实时/嵌入式、自定义分配器。

**DET-01 交付**：必须有一页权威条目（放在 `docs/design` 或链接 S3），包含判定表和正反例；只在 README 里出现不算。

### W4 · XDK 公共面

1. **范围**：14 包、API 清单、X disposition、deprecated 命名空间；不含 。
2. **产物**：`src/ffi/api-manifest.tsv`、14 包状态表、X 表、`xdk/index.json`、独立 AUDIT 记录。
3. **证据**：`xdk.sh` + `xdk_core.sh` + AUDIT 签字 + API 清单签字；期望 0。
4. **依赖**：W2/W3/W6；阻塞 W7/W8。
5. **顺序**：B4.1 API 清单 → B4.2 X 签字 → B4.3 场景/测试 → B4.4 锁定。
6. **失败/回退**：红门停止；不允许批次 agent 自签；不允许“只登记”。
7. **风险/缓解**：范围爆炸；用 X 表逐项签字；未签 = 未完成。
8. **明确不做**： 包、新能力、包改名。

**W4.1 1.0 包清单与 X 边界**

1.0 包清单（14 个，P9=B 后）：

```text
errors  runtime  meta  bytes  text  collections  math  time
io      fs       sys   log    config  cli
```

- `tasks`、`sync` 不在清单内：按 P9=B 登记为语言内建；`xdk.tasks`/`xdk.sync` 只保留 deprecated 命名空间。
- **1.0 合同内的 X**：1.0 包设计文档中所有 X 条目。按 §15 闭包账本状态为 `Strict evidenced` / `Strict candidate` / `Optimized proposed` / `Optimized candidate` / `Deferred candidate` / `Out-of-scope / deferred`；只有签字后的 `Signed Strict closed` / `Signed Optimized closed` 计入 1.0。
- 每个包的 `1.0 Verified` 由 `AUDIT.md` 独立签字 + API 清单签字确认；`00-overview.md` 的旧标签不自动继承。
- 包清单新增/删除必须走 P9 同类决策，不能在批次里顺手改。
- deprecated 命名空间：1.x 可 import，标 `deprecated`；移除版本默认 2.0，随 P5 确认；不计入 1.0 “可依赖 API”承诺。
- **P9 文档同步是 0.9.0 的 doc-only 批次**：CORE-CLOSURE 合并后立即做，7 个文件 checklist 见 §13.1；不得留到 0.9.4。

**R4 前置复核（骨架不算 Verified）**：

1. 包内每个公开符号必须有真实实现，不能只有注释、命名空间或编译器内建类型在代偿；
2. 只有内建类型支撑的包，按 P9=B 处理：登记为语言内建、从 XDK 包清单移除；`xdk.tasks`/`xdk.sync` 只保留 deprecated 命名空间；
3. 设计文档列出的 CAP 必须在包内有公开入口；只在 C 面或 raw 面有实现的不算；
4. `1.0 Verified` 必须同时有 API 清单、场景、测试和 `AUDIT.md` 独立签字；旧标签不自动继承；
5. 复核结果写入 `AUDIT.md`；R4 只认复核后的状态，不直接抄 `00-overview.md`。

**退出**：R4 绿；API 清单签字；无骨架包；P9=B 已落地；C1 全绿。

### W5 · 并发与取消

1. **范围**：`Context`/`Task`/`TaskGroup`/`Channel`/`Atomic*` 内建契约、取消、关闭、压力；不含新调度器。
2. **产物**：状态机文档、压力测试、TSan 用例、语言规范条目。
3. **证据**：`xdk_tasks.x`、`xdk_cancel.x`、`xdk_channel*.x` + 10k 任务压力；期望 0。
4. **依赖**：W3；阻塞 W4。
5. **顺序**：B5.1 规范 → B5.2 压力 → B5.3 TSan → B5.4 P9 文档同步。
6. **失败/回退**：红门停止；竞态不修不得锁定。
7. **风险/缓解**：竞态偶发；固定种子 + 长时压力 + TSan。
8. **明确不做**：公平性、优先级、实时性承诺。

**并发语义**：spawn/join/close/cancel/deadline/channel close 的状态机；取消传播与幂等关闭；关闭后调用必须失败或终止。`xdk.time` 可单向依赖内建 `Context` 句柄；`xdk.tasks` 不得 import `xdk.time`。

### W6 · 诊断与可观测

1. **范围**：错误码、诊断格式、`dumpTasks`/`stats`、fatal 边界；不做完整日志产品。
2. **产物**：错误码注册表、JSON 诊断测试、`xdk.runtime` 新面。
3. **证据**：`check.sh`/`sema.sh` + JSON 诊断断言；期望指定码；红 = 未注册码/内部 fatal。
4. **依赖**：W1/W3；阻塞 W4。
5. **顺序**：B6.1 注册表 → B6.2 runtime 面 → B6.3 fatal 边界。
6. **失败/回退**：红门停止；不得用自由文本替代错误码。
7. **风险/缓解**：诊断文案变动；以码为稳定面，文案可改。
8. **明确不做**：完整 stack trace、分布式追踪。

### W7 · 工具链与 CLI

1. **范围**：CLI 合同、复现构建、doctor；project/package 按 P3 待签（U1 要求至少 B）。
2. **产物**：CLI 合同测试、复现构建脚本、doctor 矩阵。
3. **证据**：`m8.sh` + 复现脚本两次构建哈希一致；macOS 链接加 `-Wl,-no_uuid` 或剥离 `LC_UUID`；期望 0。
4. **依赖**：W1/W3；阻塞 W8。
5. **顺序**：B7.1 合同 → B7.2 复现 → B7.3 doctor。
6. **失败/回退**：红门停止；缺命令明确报错，不回退第二引擎。
7. **风险/缓解**：cc 版本差异；固定版本 + `SOURCE_DATE_EPOCH` + 路径映射。
8. **明确不做**：包管理器；project 命令若 P3=A 则与 U1 冲突，必须先解决。

### W8 · 打包、安装、版本

1. **范围**：版本策略、tarball、校验和、安装/卸载/升级；不做包管理器。
2. **产物**：发布物、checksums、install/uninstall 测试、版本文件。
3. **证据**：安装 → doctor → 卸载三场景；期望 0。
4. **依赖**：W7；阻塞 R10。
5. **顺序**：B8.1 版本 → B8.2 打包 → B8.3 安装测试。
6. **失败/回退**：红门停止；安装失败不得发布。
7. **风险/缓解**：平台差异；每平台跑安装测试。
8. **明确不做**：依赖解析、lockfile、包仓库。

### W9 · 质量工程

1. **范围**：CI、sanitizer、fuzz、覆盖率、压力；不做产品功能。
2. **产物**：CI 配置、fuzz 语料、sanitizer 矩阵、报告。
3. **证据**：CI 矩阵全绿；夜间 sanitizer/fuzz 绿；红 = 任一。
4. **依赖**：W2/W3；阻塞 R6。
5. **顺序**：B9.1 CI → B9.2 sanitizer → B9.3 fuzz → B9.4 压力。
6. **失败/回退**：红门停止；flaky 用例必须定位，不得重跑掩盖。
7. **风险/缓解**：CI 成本/不稳定；分层（每次提交轻量，夜间重量）。
8. **明确不做**：100% 覆盖率、形式化验证。

### W10 · 平台矩阵

1. **范围**：P1 决定的平台；当前 R8/W10 默认 C（4 平台），与 P1=B（2 平台）冲突，P1 待签。
2. **产物**：runner 矩阵、平台测试、doctor 平台检查。
3. **证据**：每平台完整门禁；期望 0。
4. **依赖**：W3/W9。
5. **顺序**：B10.1 runner → B10.2 平台测试 → B10.3 文档。
6. **失败/回退**：平台红则从 1.0 矩阵移除，不得静默通过。
7. **风险/缓解**：runner 成本；夜间跑重矩阵。
8. **明确不做**：Windows、32 位平台。

### W11 · 性能

1. **范围**：编译/运行/内存预算、基准集、参考机；不做微优化承诺。
2. **产物**：基准脚本、基线 JSON、阈值脚本、release 报告。
3. **证据**：固定参考机、N≥5、中位数、归一化；超阈值红。
4. **依赖**：W9/W10。
5. **顺序**：B11.1 参考机 → B11.2 基线 → B11.3 阈值。
6. **失败/回退**：红门停止；单次读数不作为证据。
7. **风险/缓解**：噪声；校准负载 + 中位数 + 空闲机。
8. **明确不做**：实时性能、嵌入式性能。

### W12 · 文档、安全、迁移

1. **范围**：规范同步、迁移指南、安全策略、release notes、API reference；P10=B 时包含中英文档同步。
2. **产物**：迁移指南、安全策略、known issues、API reference、release notes。
3. **证据**：链接检查、示例编译、文档与 API 清单对比；期望 0。
4. **依赖**：W4。
5. **顺序**：B12.1 规范同步 → B12.2 迁移 → B12.3 安全 → B12.4 release notes。
6. **失败/回退**：文档与代码不一致则阻塞发布。
7. **风险/缓解**：文档漂移；API reference 从清单生成。
8. **明确不做**：完整多语言教程、视频。

**P10=B 成本**：中文原文入库、英文翻译同步、每批文档改动双语检查、CI 链接/术语检查；若 P10=A，则中文只本地，不发布，U5 的文档只保证英文。

### W13 · IDE/编辑器

1. **范围**：默认只保语法高亮 + XDK index；LSP/调试器/formatter 按 P2 不进 1.0。
2. **产物**：index 同步测试、语法测试。
3. **证据**：`ide/xdk/index.json` 与 `capabilities.tsv` 一致；期望 0。
4. **依赖**：W4。
5. **顺序**：P2 决定后，单批。
6. **失败/回退**：index 不一致则红。
7. **风险/缓解**：scope creep；单独决策。
8. **明确不做**：LSP、调试器、完整 IDE。

---

## 9. P1–P10：A/B/C

| P | 选项 | 成本 | 风险 | 对 1.0 承诺的影响 | 不做会失去 | 推荐/状态 |
| --- | --- | --- | --- | --- | --- | --- |
| P1 平台 | A: macOS only | 低 | 低 | 只承诺 macOS | Linux/服务器用户 | 否 |
| | B: macOS + Linux x86_64 | 中 | 中 | 覆盖主流开发/CI | arm64 Linux | **推荐；待用户签字** |
| | C: macOS arm64/x86_64 + Linux x86_64/aarch64 | 高 | 高 | 覆盖最广 | 无 | 当前 R8/W10 默认，待签 |
| P2 IDE | A: 只语法/index | 低 | 低 | 无 LSP/调试 | 编辑器体验 | **推荐；待签** |
| | B: 只读 LSP（补全/诊断） | 中 | 中 | 基础 LSP | 调试 | 可选 |
| | C: LSP+调试+formatter | 高 | 高 | 完整 IDE | 无 | post-1.0 |
| P3 project | A: 单文件 only | 低 | 低 | CLI 保持现状 | 多文件项目 | 与 U1 冲突，不成立 |
| | B: project build，无包管理 | 中 | 中 | 多文件构建 | 依赖管理 | **推荐；U1 要求；待用户签字** |
| | C: project+package manager | 高 | 高 | 完整工程 | 无 | post-1.0 |
| P4 版本 | A: mini 1.0，XDK 0.1 | 低 | 中 | 版本口径混乱 | 用户信任 | 否 |
| | B: 全部 1.0 | 中 | 中 | 清晰 | 无 | 可选 |
| | C: language 3.4 / compiler 1.0 / XDK 1.0 / ABI 1 | 中 | 低 | 最清晰 | 无 | **推荐；待签** |
| P5 兼容 | A: 不承诺 | 低 | 高 | 无兼容保证 | 用户升级信心 | 否 |
| | B: 源码 1.x + ABI 1.x | 中 | 低 | 可依赖 | 跨主版本二进制 | **推荐；待签** |
| | C: 源码+ABI+二进制 | 高 | 高 | 最强 | 无 | 不现实 |
| P6 并发 | A: 只保当前语义 | 低 | 中 | 取消/关闭不明确 | 并发可靠性 | 否 |
| | B: 明确取消/关闭，不承诺公平 | 中 | 低 | 可依赖 | 公平性 | **推荐；待签** |
| | C: 公平/优先级/抢占 | 高 | 高 | 实时级 | 无 | post-1.0 |
| P7 性能 | A: 无预算 | 低 | 高 | 无性能承诺 | 性能回归 | 否 |
| | B: 只运行时间 | 中 | 中 | 部分 | 编译/内存 | 可选 |
| | C: 编译+运行+内存 | 高 | 中 | 完整 | 无 | **推荐；待签** |
| P8 安全 | A: 无 | 低 | 高 | 无安全承诺 | 用户信任 | 否 |
| | B: FFI/路径/资源/日志脱敏 | 中 | 低 | 基础安全 | 完整威胁模型 | **推荐；待签** |
| | C: 完整威胁模型 + 审计 | 高 | 中 | 最强 | 无 | post-1.0 |
| P9 tasks/sync | A: 做真实包 | 高 | 高 | 包 API 完整 | 1.0 工期 | 否 |
| | B: 语言内建 + deprecated 命名空间 | 中 | 低 | 诚实，不假装包 | 包 API | **已定 B** |
| | C: 直接移除 | 低 | 中 | 破坏 import | 兼容性 | 否 |
| P10 中文文档 | A: 保持 gitignore，仅英文 | 低 | 中 | 英文为准 | 中文用户 | 可选 |
| | B: 中文入库 + 英文翻译 | 中 | 中 | 双语 | 维护成本 | **推荐；待用户签字** |
| | C: 完整双语发布 | 高 | 高 | 最强 | 无 | post-1.0 |

**冲突提示**：

- **P1=B vs R8/W10=C**：当前 R8/W10 仍写 4 平台；若 P1=B，R8/W10 必须降为 macOS arm64 + Linux x86_64。P1 未签前，R8/W10 标“由 P1 决定”。
- **P3=A vs U1**：U1 要求多文件构建，P3=A 不成立；P3 至少 B。
- **P10=B**：成本已写入 W12；若 P10=A，U5 的文档只保证英文。

---

## 10. 证据标准与门禁实现

一条命令、一份输出、一个退出码（`LOCAL_RULES` 第 3 号）。

| 门禁 | 命令（示例） |
| --- | --- |
| R0 | `./src/runtime/build_rt.sh --lib && ./src/mini/tests/selfhost.sh` + §10.3 两次构建 |
| R1 | `python3 src/toolchain/check_layers.py`（待建；W1 首批交付） |
| R2 | `src/mini/tests/check.sh && src/mini/tests/sema.sh` + 一致性套件 |
| R3 | `./src/runtime/build_rt.sh` + sanitizer 矩阵 |
| R4 | `src/mini/tests/xdk.sh && src/mini/tests/xdk_core.sh` + `AUDIT.md` 独立签字 + API 清单签字 |
| R5 | `src/mini/tests/xdk_tasks.x` / `xdk_cancel.x` / `xdk_channel*.x` + 压力 |
| R6 | CI 矩阵（ASan/UBSan/TSan/fuzz）；valgrind 仅 Linux x86_64 |
| R7 | `src/mini/tests/m8.sh` |
| R8 | 各平台完整门禁；平台清单由 P1 决定 |
| R9 | `src/mini/tests/m10_perf.sh` + §10.4 参考机报告 |
| R10 | 安装/卸载脚本 + 文档检查 |

### 10.1 R1 `check_layers.py` 设计

**输入**：

- `src/ffi/capabilities.tsv`：稳定 `id`、`kind`（`real|builtin|skeleton`）、能力、owner、L2 符号、L1 符号、C 测试、X 场景、parity、状态。
- `src/ffi/*.xfb`：cName 与声明。
- `src/xdk/**/*.x`：raw 调用与 import。
- `src/runtime/*.c`：`xdkc_*`/`xrt_*` 定义。
- `src/mini/main.x`：`ffiSpecial`/`ffiHardProto` 硬编码 cName。
- 三组镜像：`src/xdk`↔`xdk/lib/xdk`、`src/ffi`↔`xdk/ffi`、`src/runtime`↔`xdk/runtime`。

**G1 所有权**：raw 调用者包必须等于符号 owner；例外读 allowlist。

**G2 符号闭环**：

- `.xfb` cName → C 定义必须存在；
- C 导出 → `.xfb` 或 allowlist（internal）；
- `mini/main.x` 硬编码 cName → `.xfb` 必须存在。

**G3 镜像**：三组镜像逐文件哈希；排除清单显式列出 `test_*.c`、`libxnrt.a`、`.cache/`。

**输出**：退出 0/1；JSON 违规列表：

```json
{"gate":"G1","violations":[{"file":"src/xdk/...","line":42,"symbol":"envRaw","caller":"xdk.config","owner":"xdk.sys","rule":"non-owner"}]}
```

**allowlist 列**：`kind,symbol,caller,owner,reason,remove_batch`。

**dry run（两阶段）**：

- **B1 baseline**：allowlist **非空**；当前违规必须全部命中；删一条 allowlist 必须红，证明门禁真的会红。
- **0.9.0**：allowlist **非空**；每条必须有 `owner` + `remove_batch`，不允许无主条目。
- **1.0**：allowlist **为空**；每条要么修复为 owner 调用，要么转成 `internal` 的明确符号。
- “删一条必须红”只在 B1 baseline 做；0.9.0 验收的是“非空但每条有 owner/batch”，1.0 验收的是“空”。

**现状**：`check_layers` 已建，allowlist 0/0；B1/0.9.0 非空、1.0 空 的三阶段证据未完整记录。

### 10.2 R4 独立复核与证据行

- 签字人：用户指定的独立复核人，不能是批次 agent；没有独立人时由用户本人签。
- `AUDIT.md` 只收签字行，不收“已复核”散文。
- 每行格式：

```text
package | capability | public symbol | API manifest id | scenario file | C test | gate command | exit code / output hash | reviewer | date | status
```

- `xdk_core.sh` 是门禁，不是包完整性证明；只能作为证据之一。
- 任何 `1.0 Verified` 行必须有签字人和日期；自签视为未完成。
- `AUDIT.md` 必须新增 `K`、`1.0`、`Evidence`、`Reviewer`、`Date` 列；`Gate` 只保留门禁结果，`Verified` 另起签字行。
- `src/ffi/api-manifest.tsv` 是 1.0 API 清单的落盘文件：`package,symbol,signature,stability,owner,status`；76871532 已落盘 160 symbols / 14 packages。R4 仍缺独立 Reviewer 签字；核心 5 包的 `1.0 Verified` 依赖其 0.9.0 子集。

### 10.3 R0 复现构建 dry run

**R0 dry run（2026-11-21，HEAD 0adea13b，本机 macOS arm64）**：

| 步骤 | 结果 |
| --- | --- |
| `mini --emit-c main.x` 两次 | 字节一致；SHA-256 `152f4deceeda3e370c4437efb4ed77d4aa8b7bd69b990168a84758cf8e2ed3d2` |
| `cc` 链接两次（无 `-no_uuid`） | 大小一致 465080；字节不同；差异为 `LC_UUID`：`C13843F8-...` vs `206AE0EF-...` |
| `cc` 链接两次（`-Wl,-no_uuid`） | 字节一致；SHA-256 `dd2964976ecc784b463ec0ff6082baafce7cdfc3de8bea548ab705ff37b6aeff` |

**结论**：codegen 可复现；链接层 `LC_UUID` 是唯一差异。W7 必须在 macOS 加 `-Wl,-no_uuid` 或剥离 `LC_UUID`，R0 才绿。`build_rt.sh --lib` 两跑与 `selfhost.sh` 仍待 B0 记录。

固定变量：

1. 固定 `cc --version` 与路径；不同 cc 版本不比较哈希。
2. 固定 `LC_ALL=C`、`TZ=UTC`、`SOURCE_DATE_EPOCH`（取提交时间）、`umask`。
3. 两次构建到不同目录，加 `-ffile-prefix-map=$ROOT=.`；产物不得含工作目录绝对路径。
4. 输入排序：`find` 结果排序；资源表按路径排序；JSON 键排序。
5. 逐文件 SHA-256；差异必须定位到具体段。
6. `grep -R '__DATE__\|__TIME__'` 确认没有未消除的时间宏；有则修或显式允许。

### 10.4 R9 参考机与性能测量

**现状**：0.733s@200M 是历史本地读数；`AUDIT.md` 最新为 0.635s；曾因负载出现 1.29x。两者都不作基线。

**U4 数值预算（provisional；B11 只允许向下重定）**：

| 指标 | 参考机 | 预算 | 说明 |
| --- | --- | --- | --- |
| 200M LCG 运行中位数 | macOS arm64（M 系列，8C/16G） | ≤ 0.80s | 7 次，丢 2 次预热 |
| 200M LCG 运行中位数 | Linux x86_64（4 vCPU/8G） | ≤ 1.20s | 7 次，丢 2 次预热 |
| `mini --emit-c main.x` | macOS arm64 | ≤ 10s | 单次，冷启动 |
| 峰值 RSS | 两平台 | ≤ 512MB | `/usr/bin/time -l` 或等价 |

方案：

1. 参考机：一台 macOS arm64 + 一台 Linux x86_64；固定型号、电源模式、后台负载。
2. 每次测量前跑固定校准负载，记录校准时间。
3. 每点 N=7，丢 2 次预热，取中位数；同时记录 min/p95。
4. 以校准后的中位数设阈值；首次基线在参考机上重测；预算只允许下调。
5. 结果写入 release notes；单次读数不作为证据。

### 10.5 DET-01

- 必须在 `docs/design` 或 S3 有一页权威条目，包含判定表和正反例。
- 只在 README 或 `rt_policy.h` 注释里出现不算。
- W3 交付；C0b-2 检查；不在 C0 前检查。

### 10.6 R6 平台与 sanitizer 矩阵

| 平台 | ASan | UBSan | TSan | valgrind |
| --- | --- | --- | --- | --- |
| macOS arm64 | 是 | 是 | 是（若 runner 支持） | 否 |
| Linux x86_64 | 是 | 是 | 是 | 是 |
| Linux arm64 | 是 | 是 | 是 | 视可用性 |

- runner：GitHub Actions 托管或自建；macOS 分钟成本显著高于 Linux。
- 策略：每次提交跑轻量；夜间跑 sanitizer/fuzz/压力；发布前跑全矩阵。
- 若 macOS TSan 不可用，记录例外，由 Linux TSan 兜底；不得静默略过。

---

## 11. 执行规则与并行开发

- 批次 = 用户本次给出的条目；不自行增减（`LOCAL_RULES` 第 5 号）。
- 批内不逐条跑门禁、不逐条提交、不逐条更新文档。
- 批末顺序：完整门禁 → 更新矩阵/`PLAN.md`/状态 → 提交 → 汇报。
- 门禁红且批内无法修复 → 停止整条链，不跳批。
- 规范缺失 → 先写一页条款与后果，再实现（`LOCAL_RULES` 第 4 号）。
- 与其他开发并行：优先新文件/新 worktree；不修改对方在途文件；合并前重跑 R0–R1。
- 本计划不删除任何现有代码/文档；旧实现只登记、按批迁移。

---

## 12. 当前基线（2026-11-21）

> 本节是落盘时快照，只用于说明起点，不作为验收依据。包状态以 `docs/design/core/AUDIT.md` 为准；版本/行数/测试数量会变，不在门禁里比对。

- 工作树：落盘前干净；`docs/design/MINI-1.0.md` 本身待提交。
- 版本：mini 0.3.0；XDK 0.1.0；language 3.4.0；runtime ABI v1。
- 测试：16 个 C runtime 测试文件；mini 侧有 lex/parser/sema/codegen/flow/class/generics/ffi/xdk/m8/m10/selfhost/resources 等脚本。
- 性能：`m10_perf` 的 0.733s@200M 是历史本地读数；`AUDIT.md` 最新为 0.635s，且曾因机器负载出现 1.29x。1.0 以 §10.4 的中位数/归一化方法为准，不把单次读数写进计划。
- 已知缺口：
  - 无 CI；无 sanitizer/fuzz/覆盖率入口；
  - 仅 `__APPLE__` / `__linux__` 平台分支；
  - core 各包实时状态见 `docs/design/core/AUDIT.md`，本计划不复制快照；
  - `xdk.tasks` 14 行、`xdk.sync` 16 行（P9=B：降为 deprecated 命名空间，不计入 1.0 包）；
  - `xdk.runtime` 27 行，缺 `dumpTasks`/`stats`/`RuntimeInfo`；
  - `env` 两套语义；`xdk/runtime/rt.c` 镜像漂移；
  - `xdk/index.json` 缺失；
  - 错误码仅见 `SEM-001..005`，无注册表；
  - `docs/zh/` 被 gitignore。

---

## 13. 与既有计划的关系

- `docs/design/core/CORE-CLOSURE.md`：继续作为 core 能力收口批次；本计划只给它加 C0/C1 门禁，不改其范围。
- `src/xdk/PLAN.md`：包矩阵与能力进度继续维护；1.0 状态以本文件的 §1.2 和 R4 为准。
- `src/mini/PLAN.md` / `MILESTONES.md`：编译器队列与里程碑继续维护；1.0 版本阶梯以本文件为准。
- `docs/design/core/*`：能力契约仍有效；与 W1 所有权冲突时，所有权按本文件，行为按原设计。

### 13.1 P9=B 文档同步 checklist（0.9.0 doc-only 批次）

CORE-CLOSURE 合并后立即做，7 个文件，一个不能漏：

1. `docs/design/core/00-overview.md`：包矩阵/状态移除 tasks/sync，标语言内建。
2. `docs/design/core/12-tasks.md`：语言内建、包 deprecated、移除版本 2.0。
3. `docs/design/core/13-sync.md`：同上。
4. `src/xdk/PLAN.md`：包矩阵移除/标记。
5. `xdk/lib/xdk/PLAN.md`：镜像同步。
6. `docs/design/core/AUDIT.md`：Package status 行改为内建/deprecated。
7. `src/mini/PLAN.md`：XDK 状态同步。

门禁：`diff -qr src/xdk xdk/lib/xdk` + `xdk.sh` + 文档 grep（不得再把 tasks/sync 列为 1.0 包）。

---

## 14. 1.0 退出清单（逐条可判定）

- [ ] C0：§5 的 8 条全绿；C0 不过，0.9.0 不算完成。
- [ ] 0.9.0：14 包 `K Verified`；CORE-CLOSURE 5 包 `1.0 Verified`；P9 文档同步 7 文件完成。
- [ ] C0b：§5.1 的 3 条全绿；env/platform/sleep 单一语义、DET-01、5 包复核签字；C0b 不过，0.9.2 不算完成。
- [ ] R0：按 §10.3 两次构建哈希一致（macOS 加 `-Wl,-no_uuid` 或剥离 `LC_UUID`）；`selfhost.sh` 绿；`build_rt.sh --lib` 两跑已记录。
- [ ] R1：`check_layers.py` 已建；B1/0.9.0 allowlist 非空且每条有 owner/batch；1.0 allowlist 为空；三组镜像一致。
- [ ] R2：规范正/负例全绿；无未注册错误码；无内部 `fatal`。
- [ ] R3：ABI v1 测试绿；GC/ARC/task/sync 压力绿；无泄漏。
- [ ] 0.9.4 / C1：14 包 `1.0 Verified`；C1 全绿；X 表签字；API 清单签字。
- [ ] R4：14 包 `1.0 Verified`；`AUDIT.md` 独立签字；API 清单签字；无骨架包。
- [ ] R5：取消/deadline/channel close 压力与竞态绿。
- [ ] R6：ASan/UBSan/TSan/fuzz 有固定入口且绿；valgrind（Linux）绿。
- [ ] R7：CLI 合同、退出码、JSON、doctor/clean/resources 绿。
- [ ] R8：P1 决定的平台矩阵全部跑过完整门禁。
- [ ] R9：编译/运行/内存预算达标，参考机中位数达标。
- [ ] R10：安装/卸载/升级、校验和、许可证、迁移、安全策略、release notes 完成。
- [ ] U0–U5：rc.1 前全绿；U5 不过，1.0 不算站起来。
- [ ] 版本口径统一（P4）。
- [ ] 工作树干净，tag 与发布物一致。

---

## 15. 附录：X closure ledger（证据 / 提议 / 候选）

### 15.1 状态定义与计数

| 状态 | 定义 | 是否 closed | 计数 |
| --- | --- | --- | --- |
| `Strict evidenced` | 有实现、场景、门禁证据；R4 可直接审计；没有签字 | 否 | 41 |
| `Strict candidate` | 声明 strict，但缺源码/场景/命令输出；不可直接审计 | 否 | 0 |
| `Optimized proposed` | 有 adapter/shim、保留/丢失、测试、I/D/B/M；没有签字 | 否 | 10 |
| `Optimized candidate` | 有 adapter/shim，但缺测试命令/输出或逐项 retained/lost | 否 | 0 |
| `Deferred candidate` | strict + optimized 已尝试；有 residual/options/推荐；会议日期未定 | 否 | 3 |
| `Out-of-scope / deferred` | 设计文档明确列为非目标；package API 由用户签 | 否 | 9 |
| `Signed Strict closed` | `Strict evidenced` + 用户/独立复核人签字 | 是 | 0 |
| `Signed Optimized closed` | `Optimized proposed` + 保留 1.0 承诺 + 不改公共语义 + 测试 + I/D/B/M + 签字 | 是 | 0 |
| **合计** | 54 个 14 包 X + 9 个 tasks/sync | | **63** |

> 只有 `Signed Strict closed` / `Signed Optimized closed` 计入 closed。`Strict evidenced`、`Strict candidate`、`Optimized proposed`、`Optimized candidate`、`Deferred candidate`、`Out-of-scope / deferred` 都不是 closed。

### 15.2 逐项账本（63 行，一行一条）

| # | 包 / 项 | 状态 | Package API | Strict 证据 | Optimized 提案（保留/丢失） | Impact | Dependents | Breakage | Migration | Options/推荐 | Meeting/签字 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | errors / 复杂接收者表达式推断 | Strict evidenced | — | fecca2cb + r4/inference.x / r4_evidence.sh | — | none | package users | none | none | — | unsigned |
| 2 | errors / 错误码命名空间工具 | Strict evidenced | — | fecca2cb + error-codes.tsv / check_error_codes.py / error_codes.sh | — | none | package users | none | none | — | unsigned |
| 3 | runtime / dumpTasks / stats | Strict evidenced | — | 62052241 + ref/u2_task_dump.x + r4/runtime_stats.x / r4_evidence.sh | — | none | package users | none | none | — | unsigned |
| 4 | runtime / RuntimeInfo | Strict evidenced | — | 62052241 + r4/runtime_info.x | — | none | package users | none | none | — | unsigned |
| 5 | runtime / assert / fatal 边界 | Strict evidenced | — | build_rt.sh（test_std.c/test_abi*.c） | — | none | package users | none | none | — | unsigned |
| 6 | text / StringBuilder | Strict evidenced | — | fecca2cb + r4/text_builder.x | — | none | package users | none | none | — | unsigned |
| 7 | text / Unicode（UTF-8↔UTF-16、码点） | Strict evidenced | — | xdk.sh（xdk_text.x/xdk_text_full.x） | — | none | package users | none | none | — | unsigned |
| 8 | text / 转义 | Strict evidenced | — | fecca2cb + r4/escape.x | — | none | package users | none | none | — | unsigned |
| 9 | text / 数字格式化 | Strict evidenced | — | xdk.sh（xdk_text.x/xdk_text_full.x） | — | none | package users | none | none | — | unsigned |
| 10 | text / Regex POSIX ERE 子集 | Strict evidenced | — | xdk.sh（xdk_text.x/xdk_text_full.x） | — | none | package users | none | none | — | unsigned |
| 11 | text / Format 全量 | Strict evidenced | — | xdk.sh（xdk_text.x/xdk_text_full.x） | — | none | package users | none | none | — | unsigned |
| 12 | collections / Map.entries 任意 K/V | Strict evidenced | — | xdk.sh（xdk_collections.x/xdk_containers.x/xdk_members.x） | — | none | package users | none | none | — | unsigned |
| 13 | collections / groupBy | Strict evidenced | — | xdk.sh（xdk_collections.x/xdk_containers.x/xdk_members.x） | — | none | package users | none | none | — | unsigned |
| 14 | collections / OrderedMap/BTreeMap | Strict evidenced | — | xdk.sh（xdk_collections.x/xdk_containers.x/xdk_members.x） | — | none | package users | none | none | — | unsigned |
| 15 | time / 可取消 sleep | Strict evidenced | — | 62052241 + r4/time_sleep_cancel.x | — | none | package users | none | none | — | unsigned |
| 16 | time / 全量 layout 解析/格式化 | Strict evidenced | — | 62052241 + r4/time_layout_parse.x | — | none | package users | none | none | — | unsigned |
| 17 | io / EOF checked | Strict evidenced | — | xdk.sh（xdk_io.x） | — | none | package users | none | none | — | unsigned |
| 18 | io / Buffered/Chain/Tee/Limit/LineReader | Strict evidenced | — | xdk.sh（xdk_io.x） | — | none | package users | none | none | — | unsigned |
| 19 | io / stdio | Strict evidenced | — | xdk.sh（xdk_io.x） | — | none | package users | none | none | — | unsigned |
| 20 | fs / File/Dir/Path | Strict evidenced | — | xdk.sh（xdk_fs.x） | — | none | package users | none | none | — | unsigned |
| 21 | fs / Result 面 | Strict evidenced | — | xdk.sh（xdk_fs.x） | — | none | package users | none | none | — | unsigned |
| 22 | fs / Metadata/walk/glob/Temp/Atomic/权限/链接 | Strict evidenced | — | xdk.sh（xdk_fs.x） | — | none | package users | none | none | — | unsigned |
| 23 | sys / File/Dir/Process | Strict evidenced | — | xdk.sh（xdk_sys.x/xdk_sys_full.x） | — | none | package users | none | none | — | unsigned |
| 24 | sys / stdio 管道 | Strict evidenced | — | xdk.sh（xdk_sys.x/xdk_sys_full.x） | — | none | package users | none | none | — | unsigned |
| 25 | sys / 信号 | Strict evidenced | — | xdk.sh（xdk_sys.x/xdk_sys_full.x） | — | none | package users | none | none | — | unsigned |
| 26 | sys / 环境枚举 | Strict evidenced | — | xdk.sh（xdk_sys.x/xdk_sys_full.x） | — | none | package users | none | none | — | unsigned |
| 27 | sys / 进程组 | Strict evidenced | — | xdk.sh（xdk_sys.x/xdk_sys_full.x） | — | none | package users | none | none | — | unsigned |
| 28 | sys / 内嵌资源读取子集 | Strict evidenced | — | xdk.sh（xdk_sys.x/xdk_sys_full.x）+ resources.sh | — | none | package users | none | none | — | unsigned |
| 29 | log / Field/Sink | Strict evidenced | — | dd399cfb（Field/Sink/ConsoleSink/MemorySink）+ check_layers 0/0 + xdk.sh/xdk_core.sh PASS | — | none | package users | none | none | — | unsigned |
| 30 | log / Console sink | Strict evidenced | — | dd399cfb（ConsoleSink）+ xdk_log.x | — | none | package users | none | none | — | unsigned |
| 31 | log / 时间戳/单调时钟字段 | Strict evidenced | — | 10515423 + r4/log_timestamp.x | — | none | package users | none | none | — | unsigned |
| 32 | config / ConfigSource/FileSource/overlay | Strict evidenced | — | dd399cfb（ConfigSource/MapSource/FileSource/overlay）+ check_layers 0/0 + xdk.sh/xdk_core.sh PASS | — | none | package users | none | none | — | unsigned |
| 33 | config / 类型化 getter | Strict evidenced | — | 10515423 + r4/config_typed.x | — | none | package users | none | none | — | unsigned |
| 34 | cli / OptionSpec/Command/子命令 | Strict evidenced | — | dd399cfb（OptionSpec/Command/子命令）+ check_layers 0/0 + xdk.sh/xdk_core.sh PASS | — | none | package users | none | none | — | unsigned |
| 35 | cli / help 渲染 | Strict evidenced | — | dd399cfb（Command.help）+ xdk_cli.x | — | none | package users | none | none | — | unsigned |
| 36 | time / Stopwatch | Strict evidenced | — | 62052241 + r4/time_stopwatch.x | — | none | package users | none | none | — | unsigned |
| 37 | errors / DetailedError 聚合 | Strict evidenced | — | fecca2cb + r4/errors_detail.x | — | none | package users | none | none | — | unsigned |
| 38 | errors / tryWith* | Strict evidenced | — | fecca2cb + r4/errors_detail.x | — | errors API | errors users | none | helper alias | — | unsigned |
| 39 | runtime / stdio 流 | Optimized proposed | — | 新 runtime 流原语（0.9.3 后） | adapter 复用 xdk.io Reader/Writer；证据 76871532 + r4/stdio.x | runtime/io | io/runtime | none | use xdk.io streams | retained/lost 见提案；unsigned | unsigned |
| 40 | meta / BuildInfo | Optimized proposed | — | 动态构建信息 | 只读 version/platform/compiler；证据 10515423 + r4/meta_buildinfo.x | meta | log/cli | none | none | retained/lost 见提案；unsigned | unsigned |
| 41 | meta / 能力矩阵 | Optimized proposed | — | 运行时探测 | 构建期表 capabilities.tsv；证据 10515423 + check_layers.py / gen_api_manifest.py | meta/sys | meta/sys | none | none | retained/lost 见提案；unsigned | unsigned |
| 42 | meta / 构建元数据 | Optimized proposed | — | 完整构建元数据 | 只读常量；证据 10515423 + r4/meta_buildinfo.x | meta | meta | none | none | retained/lost 见提案；unsigned | unsigned |
| 43 | bytes / ByteBuffer | Strict evidenced | — | f254ab33（ByteBuffer）+ xdk_bytes_extra.x/xdk_bytes_strict.x/test_std.c | — | bytes | bytes users | none | use Bytes/ByteWriter | — | unsigned |
| 44 | bytes / NUL 边界工具 | Optimized proposed | — | 原生 NUL 边界原语 | 薄包装 Bytes/ByteReader；证据 10515423 + r4/bytes_nul.x | bytes | bytes users | none | use ByteReader | retained/lost 见提案；unsigned | unsigned |
| 45 | time / 日历加减边界 | Optimized proposed | — | 完整 civil 运算 | 基础 add/sub；证据 62052241 + r4/time_calendar.x / r4/time_calendar_edges.x | time | time users | subset | document edge limits | retained/lost 见提案；unsigned | unsigned |
| 46 | log / Memory sink | Strict evidenced | — | dd399cfb（MemorySink）+ xdk_log.x；File sink 已移  | — | log | log users | no File sink | Console/Memory sink | — | unsigned |
| 47 | log / 过滤/脱敏/采样 | Optimized proposed | — | 完整策略引擎 | predicate / 脱敏 hook / 确定性 sampler；证据 76871532 + r4/log_pipeline.x | log | log users | none | hooks | retained/lost 见提案；unsigned | unsigned |
| 48 | config / 最小键校验（setChecked） | Strict evidenced | — | 10515423 + r4/config_checked.x | — | config | config users | none | minimal checks | — | unsigned |
| 49 | cli / 补全 | Optimized proposed | — | shell 专用补全 | 从 OptionSpec 生成；证据 10515423 + r4/cli_completion.x | cli | cli users | none | generated | retained/lost 见提案；unsigned | unsigned |
| 50 | cli / 短选项合并/重复策略 | Optimized proposed | — | POSIX 全解析 | 文档化合并/重复规则；证据 10515423 + r4/cli_completion.x | cli | cli users | subset | documented rule | retained/lost 见提案；unsigned | unsigned |
| 51 | cli / 环境/配置文件默认值 | Optimized proposed | — | 完整优先级 | 固定优先级链；证据 10515423 + r4/cli_defaults.x | cli | cli users | subset | fixed chain | retained/lost 见提案；unsigned | unsigned |
| 52 | math / random | Deferred candidate | — | 无 T0-K 原语；T1 xdk.random 未定稿 | OS RNG adapter（getrandom/arc4random） | math | math users | none | none | A T1 包（推荐）/ B OS adapter / C 不提供 | date TBD; signer: user |
| 53 | time / TimeZone | Deferred candidate | — | IANA tzdata 加载/更新未设计 | 固定偏移子集 toZone(offset) | time | time users | no DST | none | A 固定偏移（推荐 1.0）/ B IANA / C 不提供 | date TBD; signer: user |
| 54 | config / codec | Deferred candidate | — | codec 注入/格式未定稿 | 外部 adapter String -> Map | config | config users | no standard codec | external adapter | A JSON codec（推荐）/ B external / C 不提供 | date TBD; signer: user |
| 55 | tasks / select/race | Out-of-scope / deferred | Deferred candidate | 12-tasks.md:26/75（非目标） | — | package API | tasks users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 56 | tasks / Context 值 | Out-of-scope / deferred | Deferred candidate | 12-tasks.md:26/75（非目标） | — | package API | tasks users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 57 | tasks / 取消作用域 | Out-of-scope / deferred | Deferred candidate | 12-tasks.md:26/75（非目标） | — | package API | tasks users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 58 | sync / RwLock | Out-of-scope / deferred | Deferred candidate | 13-sync.md:26/76-77（非目标） | — | package API | sync users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 59 | sync / Semaphore | Out-of-scope / deferred | Deferred candidate | 13-sync.md:26/76-77（非目标） | — | package API | sync users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 60 | sync / WaitGroup | Out-of-scope / deferred | Deferred candidate | 13-sync.md:26/76-77（非目标） | — | package API | sync users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 61 | sync / Once | Out-of-scope / deferred | Deferred candidate | 13-sync.md:26/76-77（非目标） | — | package API | sync users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 62 | sync / Barrier | Out-of-scope / deferred | Deferred candidate | 13-sync.md:26/76-77（非目标） | — | package API | sync users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |
| 63 | sync / select | Out-of-scope / deferred | Deferred candidate | 13-sync.md:26/76-77（非目标） | — | package API | sync users | none (non-goal) | deprecated namespace | package API 由用户签；A later / B out-of-scope | user sign; W5/0.9.4 |### 15.3 兼容/影响政策

任何闭包不得破坏他人：

- **加法 API**：新增符号，不改既有签名/语义；
- **deprecated 命名空间**：1.x 可 import，标 `deprecated`，2.0 移除（随 P5）；
- **feature flag**：默认关闭的新行为必须有开关；
- **adapter**：优先复用既有实现，不复制第二套。

每次尝试必须写 Impact / Dependents / Breakage / Migration；`Strict evidenced` 行指向真实文件/命令，`Strict candidate` / `Optimized candidate` / `Deferred candidate` / `Out-of-scope` 行必须写明缺口和补证路径。`Deferred candidate` 不得由批次 agent 标注，只能作为会议输入。`Signed Optimized closed` 只有保留 1.0 承诺、不改公共语义、有 adapter/shim 与测试证据、I/D/B/M 完整、用户/独立复核人签字才算绿；`Optimized candidate` 补不齐测试/retained-lost 不得升 proposed。

---
## 16. 自检（本次修改后）

### 16.1 文件级验收

| 检查 | 结果 |
| --- | --- |
| 0.9.0 不再与 W4=0.9.4、W6=0.9.3 矛盾 | 条目已落盘；状态见 §16.2 |
| C0/C0b/C1/U 都在文件里且逐条可判定 | 条目已落盘；状态见 §16.2 |
| X 账本在文件里，逐项有证据态/提议态/候选态 | 0 signed closed；41 strict evidenced；0 strict candidate；10 optimized proposed；0 optimized candidate；3 deferred candidate；9 out-of-scope/deferred；26 个输入 post 项已重评 |
| 没有裸“post-1.0”项 | 条目已落盘；26 个输入 post 项全部有状态；0 项 signed closed；状态见 §16.2 |
| 只改 `docs/design/MINI-1.0.md` | 条目已落盘；状态见 §16.2 |
| P1/P10 标记待签，P9 保持已定 B | 条目已落盘；状态见 §16.2 |
| P1=B 与 R8/W10=C 的冲突显式写出 | 条目已落盘；状态见 §16.2 |
| P10=B 的中英文档成本写入 W12 | 条目已落盘；状态见 §16.2 |
| U1 与 P3=A 的冲突显式写出 | 条目已落盘；状态见 §16.2 |

> R4-EVIDENCE §7：**0 signed closed / 41 strict evidenced / 0 strict candidate / 10 optimized proposed / 0 optimized candidate / 3 deferred candidate / 9 out-of-scope/deferred**。

### 16.2 门禁实际状态

| 门禁 | 状态 | 证据/原因 |
| --- | --- | --- |
| C0 | RED | `check_layers` 已 PASS、allowlist 0/0、镜像干净；但 0 signed closed，AUDIT Reviewer 未签（8 个 `Verified=yes` 未签），核心 5 包 X 未签 |
| C0b | NOT RUN | 0.9.1/0.9.2 未开始；env/platform/sleep 单一语义、DET-01 未验 |
| C1 | RED | 0 signed closed；10 optimized proposed / 3 deferred / 9 out-of-scope unsigned；R4 Reviewer 待签；U3 官方 0.3.0 blocked；U5 human pending |
| U0–U5 | MIXED | U0 PASS；U1 PASS；U2 PASS；U3 PASS with substitute artifact / official 0.3.0 blocked；U4 PASS；U5 agent proxy PASS / human pending |
| R0 | PASS | `76871532`：`build_rt.sh --lib` + `selfhost.sh` 两次，rt hash 一致；release tarball `9395415a…f63` |
| R1 | RED | `check_layers` 已 PASS；B1/0.9.0 非空、1.0 空 的三阶段证据未完整记录 |
| R4 | RED | 独立 Reviewer 未签；API manifest 160/14 已落盘；AUDIT 8 个 `Verified=yes` 未签，不计 signed closed |
| R9 | PASS | `76871532`：200M 中位数 0.651s（0.888x）；编译 2.10s；RSS 0.59/41.42MiB |

---

## 17. 仍未解决的决定

1. **P1 平台矩阵**：B（2 平台）还是 C（4 平台）；当前 R8/W10 写 C，推荐 B，待用户签字。
2. **P2 IDE/工具**：A（只语法/index）、B（只读 LSP）、C（LSP+调试+formatter）；推荐 A，待签。
3. **P3 project**：U1 要求多文件构建，P3 至少 B；若坚持 A，U1 必须改；待签。
4. **P4 版本口径**：A/B/C；推荐 C（language 3.4 / compiler 1.0 / XDK 1.0 / ABI 1），待签。
5. **P5 兼容承诺**：A/B/C；推荐 B（源码 1.x + ABI 1.x），待签。
6. **P6 并发保证**：A/B/C；推荐 B（明确取消/关闭，不承诺公平），待签。
7. **P7 性能预算**：A/B/C；推荐 C（编译+运行+内存），待签；U4 数值见 §10.4。
8. **P8 安全范围**：A/B/C；推荐 B（FFI/路径/资源/日志脱敏），待签。
9. **P10 中文文档**：B（入库）还是 A（仅英文）；B 的成本已写入 W12；待签。
10. **X 表**：§15 逐项签字；未签 = 未完成，不是默认关闭；post 共 26 项（14 包 17 + 账本 9），逐项签。
11. **R4 独立复核人**：需要用户指定；没有独立人时由用户本人签。
12. **R1 脚本交付**：`check_layers` 已建，allowlist 0/0；B1/0.9.0 非空、1.0 空 的三阶段证据未完整记录。
13. **R0/R9/DET-01**：R0 `76871532` 已跑 `build_rt.sh --lib` + `selfhost.sh` 两次，rt hash 一致；R9 200M 中位数 0.651s（0.888x）；DET-01 权威页未落。
14. **P0-2/P0-8 计数**：`fecca2cb` 使 `DetailedError`/`tryWith*` 转 `Strict evidenced`；`10515423` 使 `config setChecked` 转 `Strict evidenced`；NUL 为 `Optimized proposed`；`MemorySink` 保持 `Strict evidenced`。14 包 post 项 17，加账本 9 项，输入 post 总数 26。
15. **闭包账本计数**：0 signed closed；41 `Strict evidenced`；0 `Strict candidate`；10 `Optimized proposed`；0 `Optimized candidate`；3 `Deferred candidate`；9 `Out-of-scope / deferred`。Deferred candidate = math random、time TimeZone、config codec；每项已有 strict/optimized 尝试、residual、impact、A/B/C，签字人为用户，会议日期待定。
16. **Deferred candidate 会议输入**：3 项必须在会议中逐项决定；批次 agent 不得自行改标；签字后才算 closed。
17. **U3 替代 artifact**：`PASS with substitute artifact；official 0.3.0 blocked（xn-s4 卡死，已停）`；官方 0.3.0 bootstrap 缺失，`xn-s4` 不存在。需用户决定：补官方构建，或接受源码重建基线；不得标 signed closed。
18. **U5 真人**：agent proxy PASS，human U5 pending；代理记录不等于真人通过。
19. **R4 Reviewer**：仍待签；API manifest 160/14 已落盘；AUDIT 8 个 `Verified=yes` 未签，0 signed closed。
