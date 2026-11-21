# 1.x Legacy 基线

| 项 | 值 |
| --- | --- |
| 目的 | 把 1.x 已发布/已验收文档从 2.x 设计目标中分离，避免“用旧档实现新树” |
| 范围 | `docs/design/t0/` 22 篇 + 3 篇根级发布文档 |
| 状态 | 1.x 已发布；只作兼容、回归、迁移依据 |
| 2.x 权威 | [`ARCHITECTURE.md`](ARCHITECTURE.md) + [`PACKAGE-MAP.md`](PACKAGE-MAP.md) + 逐类型合同 |
| 当前仓库 | `main` = `305b5c08`；tag `mini-1.0.0`；`release/1.0` = `1c6f00ff` |

---

## 1. 25 篇旧档

### 1.1 `t0/` 22 篇

| # | 文件 | 作用 |
| --- | --- | --- |
| 1 | [`t0/00-overview.md`](t0/00-overview.md) | T0 总览、权威顺序、类级设计标准 |
| 2 | [`t0/01-errors.md`](t0/01-errors.md) | errors 包 |
| 3 | [`t0/02-runtime.md`](t0/02-runtime.md) | runtime 包 |
| 4 | [`t0/03-meta.md`](t0/03-meta.md) | meta 包 |
| 5 | [`t0/04-bytes.md`](t0/04-bytes.md) | bytes 包 |
| 6 | [`t0/05-text.md`](t0/05-text.md) | text 包 |
| 7 | [`t0/06-collections.md`](t0/06-collections.md) | collections 包 |
| 8 | [`t0/07-math.md`](t0/07-math.md) | math 包 |
| 9 | [`t0/08-time.md`](t0/08-time.md) | time 包 |
| 10 | [`t0/09-io.md`](t0/09-io.md) | io 包 |
| 11 | [`t0/10-fs.md`](t0/10-fs.md) | fs 包 |
| 12 | [`t0/11-sys.md`](t0/11-sys.md) | sys 包 |
| 13 | [`t0/12-tasks.md`](t0/12-tasks.md) | tasks 内建（1.x 兼容名） |
| 14 | [`t0/13-sync.md`](t0/13-sync.md) | sync 内建（1.x 兼容名） |
| 15 | [`t0/14-log.md`](t0/14-log.md) | log 包 |
| 16 | [`t0/15-config.md`](t0/15-config.md) | config 包 |
| 17 | [`t0/16-cli.md`](t0/16-cli.md) | cli 包 |
| 18 | [`t0/AUDIT.md`](t0/AUDIT.md) | 1.x 能力审计 |
| 19 | [`t0/C1-U0-U5-EVIDENCE.md`](t0/C1-U0-U5-EVIDENCE.md) | C1/U0–U5 证据 |
| 20 | [`t0/CORE-CLOSURE.md`](t0/CORE-CLOSURE.md) | core 收口记录 |
| 21 | [`t0/MIGRATION-0.x-to-1.0.md`](t0/MIGRATION-0.x-to-1.0.md) | 0.x → 1.0 迁移 |
| 22 | [`t0/R4-EVIDENCE.md`](t0/R4-EVIDENCE.md) | R4 证据 |

### 1.2 根级 3 篇

| # | 文件 | 作用 |
| --- | --- | --- |
| 23 | [`MINI-1.0.md`](MINI-1.0.md) | 1.0 预签账本 |
| 24 | [`MINI-1.0-SIGNOFF.md`](MINI-1.0-SIGNOFF.md) | owner 批准、U3/U5/P 决策、发布记录 |
| 25 | [`RELEASE-NOTES-1.0.0.md`](RELEASE-NOTES-1.0.0.md) | 1.0.0 发布说明与已知问题 |

---

## 2. 1.x 事实

| 项 | 值 |
| --- | --- |
| 版本 | mini 1.0.0 / XDK 1.0.0 |
| 公开包 | 14：`errors/runtime/meta/bytes/text/collections/math/time/io/fs/sys/log/config/cli` |
| 内建 | `xdk.tasks`、`xdk.sync`（不是 1.0 公共包） |
| API manifest | 160 symbols / 14 packages |
| 包状态 | 8 个严格 `Verified=yes`；14/14 Gate PASS |
| 门禁 | `xdk.sh`、`xdk_core.sh`、`ref.sh`、`r4_evidence.sh`、`check_layers`、`build_rt.sh`、`selfhost.sh` |
| 发布物 | `dist/xnull-1.0.0.tar.gz`；sha256 `5964d6da…`；source-only |
| 标签 | annotated `mini-1.0.0` |
| 分支 | `release/1.0`；`main` 已合并并 push |

### 2.1 明确未完成

- **U3**：官方 0.3.0 升级路径 blocked（`xn-s4` 卡死）；1.0 使用 substitute artifact，状态 `PASS with substitute artifact`，不是官方路径通过。
- **U5**：真人 trial 未通过；owner waiver，agent proxy 不是真人 PASS；转 post-1.0。
- **P（random / TimeZone / codec）**：1.0 不包含；post-1.0 方向 A；不得用空壳 API 冒充支持。

这些是发布记录的一部分，不改写、不删除、不把“未完成”写成“完成”。

---

## 3. 使用规则

### 3.1 可以做什么

- 用 `t0` + `src/xdk` 作为 1.x 行为/兼容/回归依据；
- 用 `api-manifest.tsv` 核对 1.x 公共符号；
- 用 `MINI-1.0-SIGNOFF.md` 查 U3/U5/P 的 owner 决策；
- 在 2.x 改动涉及 core 时，跑 1.x 门禁做回归。

### 3.2 不可以做什么

- 不把 `t0` 当 2.x 实现顺序或 2.x 类型合同；
- 不用 2.x 设计反向覆盖 1.x 已发布语义；
- 不删除/改名 `t0` 旧档；
- 不把 U3/U5/P 的未完成写成完成；
- 不在 1.x 分支引入 2.x 破坏性 API。

### 3.3 2.x 迁移规则

- 同名换义必须先登记 [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)，并给出 1.x → 2.x 适配器；
- 2.0 可以破坏，但必须有迁移表、deprecated 周期或明确“无适配”的 owner 决策；
- 1.x 的 14 个公开包名保留；2.x 新增 `xdk.execution`、`xdk.annotations`、`xdk.codec` 等能力包；
- 1.x 的 `xdk.tasks`/`xdk.sync` 在 2.x 不新增公共面，只保留兼容映射到 `xdk.execution`。

---

## 4. 1.x → 2.x 包映射

| 1.x | 2.x | 说明 |
| --- | --- | --- |
| `xdk.errors` | `xdk.errors` | 同名，2.x 扩展 |
| `xdk.runtime` | `xdk.runtime` | 同名，补 `RuntimeMonitor` |
| `xdk.meta` | `xdk.meta` | 同名，补 build/target/profile |
| `xdk.bytes` | `xdk.bytes` | 同名，补 `alloc/empty` |
| `xdk.text` | `xdk.text` | 同名，补 Regex/Format |
| `xdk.collections` | `xdk.collections` | 同名，泛型 `Pair`/`Entry` |
| `xdk.math` | `xdk.math` | 同名，补 Decimal/Int128/Complex |
| `xdk.time` | `xdk.time` | 同名，补 TimeZone/Timer |
| `xdk.io` | `xdk.io` | 同名，Reader/Writer 2.x protocol |
| `xdk.fs` | `xdk.fs` | 同名，OpenOptions |
| `xdk.sys` | `xdk.sys` | 同名，进程组/stdio |
| `xdk.log` | `xdk.log` | 同名，Filter/Redactor/Sampler |
| `xdk.config` | `xdk.config` | 同名，ConfigSource Context |
| `xdk.cli` | `xdk.cli` | 同名，短选项/补全 |
| `xdk.tasks` / `xdk.sync` | `xdk.execution` | 2.x 合并；1.x 兼容名 |

---

## 5. 当前发布状态备注

`MINI-1.0-SIGNOFF.md` 与 `RELEASE-NOTES-1.0.0.md` 是发布当时的记录，其中“main 未 push”是历史状态。当前仓库状态以本节为准：

- `main` = `305b5c08`，已 push 到 `origin/main`；
- tag `mini-1.0.0` 已 push；
- `release/1.0` = `1c6f00ff`；
- 另一任务的设计重组仍在 `stash@{0}`，未 drop、未 pop。

历史文档不因当前状态回改；状态差异在这里统一说明。
