# codegen 测试提速：前后耗时（S8-21 / S8-21b / S8-21c）

> 测量机：本机 macOS（darwin），12 逻辑核 / 6 物理核，Go 1.27.3；命令一律 `-count=1`、`-timeout 900s`。
> 前端统一 `XNULL_FRONTEND=go`（隔离测试基础设施差异，排除 B2-04 默认 auto 前端的干扰）。
> **注意**：这台机上常有其他会话并发跑全量（多次观测到另一个 `codegen.test` 占 300%+ CPU），
> 绝对值会成倍波动；下表同时标注当时是否有争用。

## 0. S8-21 收口（2026-11-08，main `274303a`）

| 执行方式 | 墙钟 | 结果 |
|---|---|---|
| 单进程串行 `go test ./internal/codegen` | **252.7s** | 全绿 |
| `xnull dev test --parallel 4 ./internal/codegen`（4 分片并发） | **117.2s** | 4 分片全绿 |

- 用例数 192（4 片 43/50/48/51），与改动前一致，无删减、无跳过；
- 提速 2.2×，达成 ≤170s 目标；
- 口径：`XNULL_FRONTEND=go`，`-count=1`，main `274303a`（含 E4 B2-04d）；
- 本机另有一次同为 4 分片的记录 142.70s、8 分片 137.56s（当时有其他会话并发跑 `codegen.test`，绝对值被放大）。

## 1. 最终结论（S8-21c：已回退 libxnrt 链接）

| 场景 | 耗时 | 结果 | 争用 |
|---|---|---|---|
| codegen 全量，单进程串行，**回退后**（直编 14 个 C 源） | 448.40s | 绿（192 例） | 有（另一 `codegen.test` 378% CPU） |
| codegen 全量，切片 `--shard 0/4 --parallel 4`，**回退后** | **142.70s** | 绿（43/50/48/51） | 有 |
| codegen 全量，切片 `--shard 0/8 --parallel 8`，**回退后** | **137.56s** | 绿（20/23/29/28/23/27/19/23） | 有 |
| 对照：链接 `libxnrt.a`（S8-21b），单进程串行 | 134.71s | 绿（仅 1 例预存在红） | 低 |
| 对照：改动前（用户口径） | 115s | 绿 | 未知 |

**目标 ≤170s**：切片并发 137.56s 达成（0/8/8），0/4/4 为 142.70s；单进程串行 448.40s 未达成。
**全绿**：达成（192 例，0 失败；此前唯一的 `TestTupleCodegenRuns` 红已由 E4 在 `274303a` 修复）。

## 2. S8-21c 回退内容

- `impl/internal/codegen/` 下 9 个测试文件恢复 `runtimeCSources` 直编运行时源，与 `699c625` 逐字节一致
  （`git diff 699c625 -- impl/internal/codegen/*_test.go` 为空）；
- 删除 `impl/internal/codegen/rtlib_test.go`（强制链接 `libxnrt.a` 的入口），测试不再引用 `runtimeLib`；
- 保留：
  - `xnull dev test --fast/--shard/--parallel/--merge`（稳定哈希切片、全片聚合、串行标记）；
  - `tests/b2/batch.sh` 批处理（PASS=101 FAIL=0 @ 4 片）；
  - `impl/runtime/build_rt.sh --lib` 的 SHA-256 内容缓存（脚本能力保留，当前无测试调用者）。

## 3. 为什么串行回退后 448s，而链接 `.a` 只要 135s

每次 `cc` 链接都要现编 14 个运行时 C 源（`-O2`），10 处用例各来一遍，累计约 300s；`.a` 把这部分摊掉。
两种方式的测试结果集合完全一致，`.a` 不改变语义，只是省编译。

回退是按计划执行的取舍：`.a` 让测试环境多一层"运行时构建产物"，与"测试直接编译源码"的既有约定不一致，
且 main 上的实测（283.9s）与本地 A/B（134.71s）方向相反、口径无法对齐。回退后改用切片并发达成本卡 ≤170s 的目标，风险更低。

## 4. `TestTupleCodegenRuns` 红灯已消失

S8-21b 期间的唯一红灯（`unknown type name 'xn_tup_int64_t_int64_t'`，`p.c:396`）属于**预存在缺陷**：
在 `699c625`（无 `.a`、直编源）上同样复现。E4 的 `274303a`（B2-04d）合入后该用例通过：

```
XNULL_FRONTEND=go go test ./internal/codegen -count=1 -run TestTupleCodegenRuns
ok  xnull.dev/xnull/internal/codegen  1.375s
```

## 5. auto 与 go 前端（为什么曾出现 609s / 686.9s / 905s）

| 用例 | `XNULL_FRONTEND=auto`（B2-04 默认） | `XNULL_FRONTEND=go` |
|---|---|---|
| `TestXDK07SemaSurface` | >301s（300s 超时失败，user 552s 忙等） | **1.77s** |
| `internal/cli` 全包 | 601s（10m 超时，`TestXDK07SemaSurface` 挂起 8m55s） | **108.47s 全绿** |

auto 前端走 XNull 前端（`xparser.x` interp）路径，单个用例可慢两个数量级。
**建议**：测试环境统一 `XNULL_FRONTEND=go`，需要验证 auto 的用例显式设置。

作废记录（当时机器上另有 6 个失控 `xnull run --interp xparser.x` 进程，各占 20–210% CPU 约 2 小时，
叠加多会话并发全量，load average 一度 40+）：

| 现象 | real | 真实原因 |
|---|---|---|
| 基线（改动前）跑 codegen | 930.59s（900s 超时被杀） | 失控进程 + 并发全量 |
| 改动后第 1 次 | 707.38s | 同上 |
| 改动后第 2 次 | 612.40s | 同上 |
| 改动后第 3 次 | 322.84s | 逐步清理中 |
| 默认前端（auto） | 183.51s | auto 前端 + 残余争用 |

## 6. libxnrt.a 的内容哈希缓存（保留，当前无调用者）

`impl/runtime/build_rt.sh --lib`：

- 缓存键 = 编译旗标版本串 + 11 个运行时 C 源内容，`shasum -a 256`；
- 缓存路径 `impl/runtime/.cache/libxnrt-<hash>.a`，命中 `cp` 回 `libxnrt.a` 后退出；
- 未命中才 `cc -c` 11 个源并 `ar rcs`，随后写缓存；
- `.cache/`、`libxnrt.a` 已 gitignore。

实测：冷 14.58s / 命中 **0.20s**。

## 7. B2 差分批处理

`run-l1.sh`、`run-l2.sh` 原共用 `/tmp/b2-go.tok` 等固定路径，并发即互相覆盖；改为每进程独立 `B2_TMP` 后：

```
B2_JOBS=4 bash tests/b2/batch.sh          # 或 --parallel 4
B2 批处理：PASS=101 FAIL=0 (JOBS=4)
```

## 8. 复现命令

```bash
# 隔离测（单包串行，用于横向对比）
cd impl && XNULL_FRONTEND=go go test ./internal/codegen -count=1 -timeout 900s

# 合并门禁口径：切片并发、全部 shard 聚合
XNULL_FRONTEND=go xnull dev test --shard 0/8 --parallel 8 codegen

# 包级并发
XNULL_FRONTEND=go go test -p 4 ./internal/...

# libxnrt 缓存冷/热（当前仅手工可用）
rm -rf impl/runtime/.cache && time sh impl/runtime/build_rt.sh --lib
time sh impl/runtime/build_rt.sh --lib

# B2 差分
bash tests/b2/batch.sh --parallel 4
```
