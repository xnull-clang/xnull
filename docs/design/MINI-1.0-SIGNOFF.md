# mini 1.0 批准包（2026-11-22）

## 1. 结论

**账本可签；签字不等于已发布。**

- 批准前 Signed closed：0；批准后：**51**（41 Strict + 10 Optimized）
- 63 行 = **41 Strict evidenced + 10 Optimized proposed + 3 Deferred candidate + 9 Out-of-scope / deferred**
- Strict candidate：0；Optimized candidate：0
- API manifest：**160 symbols / 14 packages**
- C1 证据：`core-evidence@a48a50f4:docs/design/t0/C1-U0-U5-EVIDENCE.md`
- U3：`PASS with substitute artifact；official 0.3.0 blocked（xn-s4 卡死，已停）`
- U5：`agent proxy PASS；human pending`
- R4 Reviewer：**已批准（无独立复核人）**
- AUDIT 8 个 `Verified=yes`：**已由 owner 批准**（见 §6）
- 1.0 发布：**已从 `release/1.0` 发布**；tag `mini-1.0.0`，commit `1c6f00ff`，tarball `5964d6da…`；main 已合并（merge `813e52ce`），未 push；另一任务重组在 `stash@{0}`

> 本包已批准并生成 1.0.0 tag；不代表已 push，也不代表官方 0.3.0 已升级、真人 U5 已通过，或 3 个 Deferred 已 closed。

### 1.1 批准记录

- 批准记录：owner 授权（AI 填写），日期 **2026-11-22**。
- A/B/D/E/F：按表接受；C：1.0 不含，post-1.0 方向 A，会议 **2026-11-23（代拟，待确认）**；G1：选 **B（接受 substitute artifact，官方 0.3.0 留 post-1.0）**；G2：**owner waiver：1.0 不阻塞；真人 trial post-1.0（未通过）**。
- P1=B / P10=B 生效；签后需同步 R8/W10（从 4 平台降为 2 平台）和 W12（中文文档成本）。
- 本签署只表示接受证据；1.0 已在 `release/1.0` 发布，但 **main 已合并（`813e52ce`），未 push**；U5 与官方 0.3.0 仍未关闭。

### 1.2 发布记录

- 分支 `release/1.0`；commit `1c6f00ff`；annotated tag `mini-1.0.0`。
- `src/toolchain/release.sh` 两次 sha256 一致：`5964d6dade77971e8aa60bc2c03ddbaae4c2bfc6db35b54af694ea44dafd0d6b`。
- 解包 → `src/mini/build.sh` → `mini 1.0.0`；`doctor` PASS；hello 输出 `hello, XNull / 1 + 2 = 3`。
- main 已合并（merge `813e52ce`），未 push；另一任务的重组在 `stash@{0}`，pop 时需处理 T0 文档冲突。
- 发布物：`dist/xnull-1.0.0.tar.gz`（source-only，含 `mini.c` seed，不含宿主二进制）。

---

## 2. 签字表 A：41 个 Strict evidenced

签字 = 接受该行证据；日期写 YYYY-MM-DD。

| 包 | Item | 证据（提交 + 场景 + 命令） | 签字 | 日期 |
| --- | --- | --- | --- | --- |
| errors | 复杂接收者表达式推断 | `fecca2cb` + `r4/inference.x` + `r4_evidence.sh` | 已批准 | 2026-11-22 |
| errors | 错误码命名空间工具 | `fecca2cb` + `error-codes.tsv` + `check_error_codes.py` + `error_codes.sh` | 已批准 | 2026-11-22 |
| errors | `DetailedError` 聚合 | `fecca2cb` + `r4/errors_detail.x` | 已批准 | 2026-11-22 |
| errors | `tryWith*` | `fecca2cb` + `r4/errors_detail.x` | 已批准 | 2026-11-22 |
| runtime | `dumpTasks` / `stats` | `62052241` + `ref/u2_task_dump.x` + `r4/runtime_stats.x` + `r4_evidence.sh` | 已批准 | 2026-11-22 |
| runtime | `RuntimeInfo` | `62052241` + `r4/runtime_info.x` | 已批准 | 2026-11-22 |
| runtime | `assert` / fatal 边界 | `build_rt.sh` + `test_std.c` / `test_abi*.c` | 已批准 | 2026-11-22 |
| text | `StringBuilder` | `fecca2cb` + `r4/text_builder.x` | 已批准 | 2026-11-22 |
| text | Unicode（UTF-8↔UTF-16、码点） | `xdk.sh` + `xdk_text.x` / `xdk_text_full.x` | 已批准 | 2026-11-22 |
| text | 转义 | `fecca2cb` + `r4/escape.x` | 已批准 | 2026-11-22 |
| text | 数字格式化 | `xdk.sh` + `xdk_text.x` / `xdk_text_full.x` | 已批准 | 2026-11-22 |
| text | Regex POSIX ERE 子集 | `xdk.sh` + `xdk_text.x` / `xdk_text_full.x` | 已批准 | 2026-11-22 |
| text | `Format` 全量 | `xdk.sh` + `xdk_text.x` / `xdk_text_full.x` | 已批准 | 2026-11-22 |
| collections | `Map.entries` 任意 K/V | `xdk.sh` + `xdk_collections.x` / `xdk_containers.x` / `xdk_members.x` | 已批准 | 2026-11-22 |
| collections | `groupBy` | `xdk.sh` + `xdk_collections.x` / `xdk_containers.x` / `xdk_members.x` | 已批准 | 2026-11-22 |
| collections | `OrderedMap` / `BTreeMap` | `xdk.sh` + `xdk_collections.x` / `xdk_containers.x` / `xdk_members.x` | 已批准 | 2026-11-22 |
| time | 可取消 `sleep` | `62052241` + `r4/time_sleep_cancel.x` | 已批准 | 2026-11-22 |
| time | 全量 layout 解析/格式化 | `62052241` + `r4/time_layout_parse.x` | 已批准 | 2026-11-22 |
| time | `Stopwatch` | `62052241` + `r4/time_stopwatch.x` | 已批准 | 2026-11-22 |
| io | EOF checked | `xdk.sh` + `xdk_io.x` | 已批准 | 2026-11-22 |
| io | Buffered/Chain/Tee/Limit/LineReader | `xdk.sh` + `xdk_io.x` | 已批准 | 2026-11-22 |
| io | stdio | `xdk.sh` + `xdk_io.x` | 已批准 | 2026-11-22 |
| fs | File/Dir/Path | `xdk.sh` + `xdk_fs.x` | 已批准 | 2026-11-22 |
| fs | `Result` 面 | `xdk.sh` + `xdk_fs.x` | 已批准 | 2026-11-22 |
| fs | Metadata/walk/glob/Temp/Atomic/权限/链接 | `xdk.sh` + `xdk_fs.x` | 已批准 | 2026-11-22 |
| sys | File/Dir/Process | `xdk.sh` + `xdk_sys.x` / `xdk_sys_full.x` | 已批准 | 2026-11-22 |
| sys | stdio 管道 | `xdk.sh` + `xdk_sys.x` / `xdk_sys_full.x` | 已批准 | 2026-11-22 |
| sys | 信号 | `xdk.sh` + `xdk_sys.x` / `xdk_sys_full.x` | 已批准 | 2026-11-22 |
| sys | 环境枚举 | `xdk.sh` + `xdk_sys.x` / `xdk_sys_full.x` **+ `resources.sh`** | 已批准 | 2026-11-22 |
| sys | 进程组 | `xdk.sh` + `xdk_sys.x` / `xdk_sys_full.x` **+ `resources.sh`** | 已批准 | 2026-11-22 |
| sys | 内嵌资源读取子集 | `xdk.sh` + `xdk_sys.x` / `xdk_sys_full.x` **+ `resources.sh`** | 已批准 | 2026-11-22 |
| log | `Field` / `Sink` | `dd399cfb` + `check_layers 0/0` + `xdk.sh` / `xdk_core.sh` | 已批准 | 2026-11-22 |
| log | Console sink | `dd399cfb` + `xdk_log.x` | 已批准 | 2026-11-22 |
| log | 时间戳/单调时钟字段 | `10515423` + `r4/log_timestamp.x` | 已批准 | 2026-11-22 |
| log | Memory sink | `dd399cfb` + `xdk_log.x`；File sink 已移 T1 | 已批准 | 2026-11-22 |
| config | `ConfigSource`/`FileSource`/overlay | `dd399cfb` + `check_layers 0/0` + `xdk.sh` / `xdk_core.sh` | 已批准 | 2026-11-22 |
| config | 类型化 getter | `10515423` + `r4/config_typed.x` | 已批准 | 2026-11-22 |
| config | 最小键校验（setChecked） | `10515423` + `r4/config_checked.x` | 已批准 | 2026-11-22 |
| cli | `OptionSpec`/`Command`/子命令 | `dd399cfb` + `check_layers 0/0` + `xdk.sh` / `xdk_core.sh` | 已批准 | 2026-11-22 |
| cli | help 渲染 | `dd399cfb` + `xdk_cli.x` | 已批准 | 2026-11-22 |
| bytes | `ByteBuffer` | `f254ab33` + `xdk_bytes_extra.x` / `xdk_bytes_strict.x` / `test_std.c` | 已批准 | 2026-11-22 |

---

## 3. 签字表 B：10 个 Optimized proposed

签字 = 接受“保留 1.0 承诺、不改公共语义、adapter/shim + 测试 + I/D/B/M”这一提案；不是 signed closed。

| Item | Shim | 测试 | Retained / Lost | I / D / B / M | 签字 |
| --- | --- | --- | --- | --- | --- |
| runtime stdio | 复用 `xdk.io` Reader/Writer | `r4/stdio.x`；`76871532` | 保留最小 stdio；丢失 runtime 级流 | runtime/io；io/runtime；none；use xdk.io | 已批准 |
| meta BuildInfo | `BuildInfo` / `buildInfo()` | `r4/meta_buildinfo.x`；`10515423` | 保留 version/platform；丢失 runtime 探测/包元数据 | meta；log/cli；none；read aggregate | 已批准 |
| meta 能力矩阵 | `capabilities.tsv` + `api-manifest.tsv` | `check_layers.py` + `gen_api_manifest.py`；`10515423` | 保留所有权/清单；丢失 runtime 探测/per-platform flags | meta/sys；all packages；none；build-time read | 已批准 |
| meta 构建元数据 | `targetArch` / `buildMode` / `compiler*` | `r4/meta_buildinfo.x`；`10515423` | 保留 version/platform；丢失可复现时间戳/build number | meta；meta/diagnostics；none；none | 已批准 |
| bytes NUL | `nulIndex` / `hasNul` / `nulPrefix` / `withNulTerminator` / `withoutTrailingNul` | `r4/bytes_nul.x`；`10515423` | 保留 Bytes/ByteReader；丢失 CString/裸指针 | bytes；bytes users；none；replace manual scan | 已批准 |
| time 日历加减 | `addDays` / `addMonths` / `addYears` | `r4/time_calendar.x` / `r4/time_calendar_edges.x`；`62052241` | 保留 Duration/DateTime；丢失 DST/TimeZone/locale | time；time users；subset；document UTC | 已批准 |
| log 过滤/脱敏/采样 | `Filter` / `Redactor` / `Sampler` | `r4/log_pipeline.x`；`76871532` | 保留 Logger；丢失策略引擎 | log；log users；none；hooks | 已批准 |
| cli 补全 | `completionBash(Command)` | `r4/cli_completion.x`；`10515423` | 保留 parse/help；丢失原生 shell 补全 | cli；cli users；none；generated list | 已批准 |
| cli 短选项/重复策略 | `Command.parse` expansion | `r4/cli_completion.x`；`10515423` | 保留 parse；丢失 POSIX 边缘 | cli；cli users；subset；documented rule | 已批准 |
| cli env/config 默认值 | 固定优先级链 | `r4/cli_defaults.x`；`10515423` | 保留 parse；丢失复杂来源 | cli；cli users；subset；fixed chain | 已批准 |

---

## 4. 签字表 C：3 个 Deferred candidate

签字 = 选择方向并定会议日期；未签前不是第三态，C1-6 保持 RED。

| Item | A / B / C | 推荐 | 1.0 失去什么 | 会议日期 | 签字 |
| --- | --- | --- | --- | --- | --- |
| math random | A T1 `xdk.random`；B OS RNG adapter；C 不提供 | 1.0 不含；post-1.0 A | 1.0 无随机数 | 2026-11-23（代拟） | 已批准：1.0 不含；post-1.0 方向 A |
| time `TimeZone` | A 固定偏移子集；B IANA tzdata；C 不提供 | 1.0 不含；post-1.0 A（固定偏移） | 1.0 无 DST/历史规则 | 2026-11-23（代拟） | 已批准：1.0 不含；post-1.0 方向 A |
| config codec | A JSON codec；B external adapter；C 不提供 | 1.0 不含；post-1.0 A | 1.0 无标准 JSON/TOML | 2026-11-23（代拟） | 已批准：1.0 不含；post-1.0 方向 A |

---

## 5. 签字表 D：9 个 Out-of-scope / deferred

签字 = 确认 package API 不进 1.0；不是删除语言内建，也不是 signed closed。

| Item | Spec 条款 | Package API | 签字 |
| --- | --- | --- | --- |
| tasks select/race | `12-tasks.md:26/75` 非目标 | 不进 1.0；后续可评估真实包 | 已批准 |
| tasks `Context` 值 | `12-tasks.md:26/75` 非目标 | 不进 1.0；语义残差已记录 | 已批准 |
| tasks 取消作用域 | `12-tasks.md:26/75` 非目标 | 不进 1.0；语义残差已记录 | 已批准 |
| sync `RwLock` | `13-sync.md:26/76-77` 非目标 | 不进 1.0 | 已批准 |
| sync `Semaphore` | `13-sync.md:26/76-77` 非目标 | 不进 1.0 | 已批准 |
| sync `WaitGroup` | `13-sync.md:26/76-77` 非目标 | 不进 1.0 | 已批准 |
| sync `Once` | `13-sync.md:26/76-77` 非目标 | 不进 1.0 | 已批准 |
| sync `Barrier` | `13-sync.md:26/76-77` 非目标 | 不进 1.0 | 已批准 |
| sync select | `13-sync.md:26/76-77` 非目标 | 不进 1.0 | 已批准 |

---

## 6. 签字表 E：R4 / AUDIT / API manifest

| 项 | 当前状态 | Reviewer | 日期 |
| --- | --- | --- | --- |
| xdk.text | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.collections | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.io | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.fs | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.sys | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.log | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.config | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| xdk.cli | AUDIT `Verified=yes`；已批准 2026-11-22 | 已批准 | 2026-11-22 |
| API manifest | 160 symbols / 14 packages；`core-evidence@a48a50f4` | 已批准 | 2026-11-22 |

> 8 个 `Verified=yes` 已由已批准接受；无独立 Reviewer，按规则由用户本人签。API manifest 已落盘。

---

## 7. 决策表 F：P1–P8 / P10

| P | A / B / C | 推荐 | 影响 | 签字 |
| --- | --- | --- | --- | --- |
| P1 平台 | A macOS only；B macOS + Linux x86_64；C macOS arm64/x86_64 + Linux x86_64/aarch64 | B | 平台矩阵与发布物 | 已批准 |
| P2 IDE | A 只语法/index；B 只读 LSP；C LSP+调试+formatter | A | 1.0 不含 LSP/调试 | 已批准 |
| P3 project | A 单文件；B project build；C project+package | B（U1 要求） | 多文件构建；A 与 U1 冲突 | 已批准 |
| P4 版本 | A mini1.0/XDK0.1；B 全部1.0；C language3.4/compiler1.0/XDK1.0/ABI1 | C | 版本口径 | 已批准 |
| P5 兼容 | A 不承诺；B 源码1.x+ABI1.x；C 源码+ABI+二进制 | B | 升级承诺 | 已批准 |
| P6 并发 | A 当前语义；B 取消/关闭明确、不承诺公平；C 公平/优先级 | B | 并发契约 | 已批准 |
| P7 性能 | A 无预算；B 只运行时间；C 编译+运行+内存 | C | U4/R9 预算 | 已批准 |
| P8 安全 | A 无；B FFI/路径/资源/日志脱敏；C 完整威胁模型 | B | 1.0 安全面 | 已批准 |
| P10 中文文档 | A 仅英文；B 中文入库+英文翻译；C 完整双语 | B | W12 成本/发布物 | 已批准 |

---

## 8. 决策表 G：U3 / U5

### G1. U3 官方 0.3.0

现状：`PASS with substitute artifact；official 0.3.0 blocked（xn-s4 卡死，已停）`。

| 选项 | 内容 | 代价/影响 | 签字 |
| --- | --- | --- | --- |
| A | 修复官方 0.3.0 bootstrap（xn-s4）后重跑升级 | 保留“官方 0.3.0 升级”承诺；时间不确定 | ☐ |
| B | 接受源码重建基线作为替代 artifact | 可推进 1.0；失去“官方 0.3.0 包升级”承诺 | 已批准：选 B |

### G2. U5 真人 trial

现状：`agent proxy PASS；human pending`。代理记录不等于真人通过。

步骤：

1. 干净机器 + 发布物 + 文档；不给源码。
2. 构建 `ref/project` 三文件工程并运行。
3. 记录首次输出：期望 `alpha=2 / 6`。
4. 修改 count 后重跑；期望 `alpha=3 / 6`。
5. 记录所有文档缺口与卡点；2 小时上限。

记录模板：

```text
tester:
date:
machine:
release:
commands:
output:
blockers:
doc gaps:
result: pass / block
```

批准：owner waiver（1.0 不阻塞；post-1.0 真人 trial） 日期：2026-11-22

---

## 9. 批准后做什么

批准 ≠ main 已合并；发布已在 `release/1.0` 完成。按顺序：

- [x] merge `release/1.0` 到 main（merge `813e52ce`）
- [x] 更新 release notes / known issues
- [x] tag `mini-1.0.0`（最终门禁全绿后）
- [x] 最终复跑 R0–R10、`ref.sh`、`xdk.sh`、`xdk_core.sh`、`check_layers`
- [ ] 归档签字包与证据链接

---

## 10. 现在不能宣称什么

- 不能宣称 **已 push**；main 已合并，tag 仍在本地。
- 不能宣称 **官方 0.3.0 已升级**（xn-s4 卡死，已停）。
- 不能宣称 **真人 U5 已通过**（只有 agent proxy）。
- 不能宣称 3 个 **Deferred 已 closed**；10 个 Optimized 是 owner 批准，不是独立复核。
- AUDIT 8 个 `Verified=yes` 是 owner 批准，不是独立 Reviewer 签；不能冒充独立复核。
- 不能把 `PASS with substitute artifact` 当作官方包升级。
