# codegen 测试提速：前后耗时（S8-21 / S8-21b）

> 测量机：本机 macOS（darwin），Go 1.27.3，`-count=1`，`-timeout 900s`。所有数据均为同一工作树的实测 `real` 值。
> 口径：`XNULL_FRONTEND=go`（隔离 libxnrt 效果），代码提交见各行标注。

## 1. 结论

| 指标 | 改动前 | 改动后 | 倍数 |
|---|---|---|---|
| codegen 全量（单进程串行，go 前端） | 286.20s（`699c625`，直编 14 个 C 源） | **134.71s**（当前，链接 `libxnrt.a`） | 2.1× |
| codegen 全量（切片并发 `--shard 0/4 --parallel 4`） | — | **78.17s**（192 例，四片 43/50/48/51） | 3.7× vs 基线 |
| `internal/cli` 全包（go 前端） | — | **108.47s 全绿**（auto 前端同包 601s 超时红） | — |
| `build_rt.sh --lib` 构建运行时静态库 | 每个测试进程重编 11 个 C 源（7–10s/进程） | 冷构建 14.58s，缓存命中 **0.20s** | — |
| 单测（`TestBuildSampleHelloWithLinkArgs`） | 13.42s（冷，含构建 lib） | 11.31s（暖，缓存命中） | — |

目标 ≤170s：**单进程 134.71s 已达标**；切片并发 78.17s（有别的会话同时跑全量时为 124.82s，仍达标）。
全绿：**未达成**，唯一红灯是改动前就存在的 `TestTupleCodegenRuns`（见 §4），非本次改动引入。

## 2. libxnrt.a 缓存（S8-21b）

`impl/runtime/build_rt.sh --lib`：

- 缓存键 = 编译旗标版本串 + 11 个运行时 C 源内容，`shasum -a 256` 取整；
- 缓存路径 `impl/runtime/.cache/libxnrt-<hash>.a`，命中 `cp` 回 `libxnrt.a` 后直接退出；
- 未命中才 `cc -c` 11 个源并 `ar rcs`，随后写入缓存；
- `.cache/`、`libxnrt.a` 已 gitignore，不入库。

实测：

```
冷（rm -rf .cache）：libxnrt.a 已构建并缓存  real 14.58s
热（缓存命中）：      libxnrt.a 命中缓存      real 0.20s
```

`impl/internal/codegen/rtlib_test.go` 的 `runtimeLib(t)` 用 `sync.Once` 在测试进程内触发一次
`sh build_rt.sh --lib`，9 处测试的运行时源清单改为链接该 `.a`。

## 3. 为什么之前看到 609s / 686.9s / 905s（作废数据）

这些数字不是 `.a` 变慢，是两个叠加因素：**B2-04 默认 auto 前端** + **机器争用**。

### 3.1 前端选择是主因（auto vs go）

| 用例 | `XNULL_FRONTEND=auto`（B2-04 默认） | `XNULL_FRONTEND=go` |
|---|---|---|
| `TestXDK07SemaSurface` | >301s（300s 超时失败，user 552s，忙等） | **1.77s** |
| `internal/cli` 全包 | 601s（10m 超时，`TestXDK07SemaSurface` 挂起 8m55s） | 见 §7 |

auto 前端走 XNull 前端（`xparser.x` interp）路径，单例耗时是 Go 前端的百倍量级；codegen 全量因此从约 135s 涨到 600s+。

### 3.2 机器争用（放大项）

1. 6 个失控进程 `xnull run --interp ../impl/lib/b2/xparser.x ...`（B2 脚本无超时，goto/while 用例挂起），
   各占 20–210% CPU，已持续约 2 小时；
2. 同时还有别的会话在同一台机上跑 codegen 全量（`/tmp/b204b-base/impl`），load average 一度 40+。

`kill -9` 全部清理后，同一工作树同一命令从 905.8s（超时被杀）降到 134.71s。

作废记录（保留说明来源，不再作为依据）：

| 现象 | real | 真实原因 |
|---|---|---|
| 基线（改动前）跑 codegen | 930.59s（900s 超时被杀） | 6 个失控进程 + 并发全量 |
| 改动后第 1 次 | 707.38s | 同上 |
| 改动后第 2 次 | 612.40s | 同上 |
| 改动后第 3 次 | 322.84s | 逐步清理中 |
| 默认前端（auto） | 183.51s | auto 前端 + 残余争用 |

## 4. 唯一红灯：`TestTupleCodegenRuns`（预存在，非本次改动）

```
--- FAIL: TestTupleCodegenRuns (0.11s)
    tuple_test.go:93: cc 失败：exit status 1
        .../p.c:396:57: error: unknown type name 'xn_tup_int64_t_int64_t'
          396 | typedef struct { rt_header hdr; size_t len; size_t cap; xn_tup_int64_t_int64_t *data; } xn_arr_t_int64_t_int64_t;
```

- 在 `699c625`（没有 `.a`，仍直编 14 个 C 源）上单跑该用例：**同样失败、同样报错** → 预存在缺陷，与 libxnrt 无关。
- 生成顺序问题：`impl/internal/codegen/codegen.go:742` 先发容器 typedef（`xn_arr_*`），
  `impl/internal/codegen/codegen.go:755` 才发元组结构体（`xn_tup_*`）；数组元素为元组时，容器 typedef 先引用了尚未定义的类型。
- 修复方向（E4 域，本次不改生产代码）：把元组结构体发射提到容器 typedef 之前，
  并确认元组在 `prewarmTypeContainers` 阶段已登记（否则提前发射得到空集）。
- 归属：`codegen` 生产代码属 E4；本回执只出诊断与定位，patch 需 E4 落。

## 5. B2 差分批处理

`tests/b2/run-l1.sh`、`run-l2.sh` 原先共用 `/tmp/b2-go.tok` 等固定路径，并发即互相覆盖；
改为每进程独立 `B2_TMP`（`mkdir -p`）后：

```
B2_JOBS=4 bash tests/b2/batch.sh
B2 批处理：PASS=101 FAIL=0 (JOBS=4)
```

串行 L1 单跑 41 例全 PASS，与批处理一致。

## 6. `internal/cli` 全包：auto 与 go 的对照

```
XNULL_FRONTEND=go   go test -p 4 ./internal/cli -count=1   → ok  108.474s（全绿）
（B2-04 默认 auto）  同一命令                                → panic: test timed out after 10m0s
                                                              running tests: TestXDK07SemaSurface (8m55s)
```

`TestXDK07SemaSurface` 单跑：auto >301s（user 552s 忙等），go 1.77s。

**建议**：测试环境统一 `XNULL_FRONTEND=go`；需要验证 auto 前端的用例显式设置该变量，
否则整套测试会被前端解释执行拖垮（数百倍量级）。

## 7. 复现命令

```bash
# 隔离测 libxnrt 效果（单包串行）
cd impl && XNULL_FRONTEND=go go test ./internal/codegen -count=1 -timeout 900s

# 切片并发（合并门禁口径：0/n 跑完全部 shard 并聚合）
XNULL_FRONTEND=go xnull dev test --shard 0/4 --parallel 4 codegen

# 缓存冷/热
rm -rf impl/runtime/.cache && time sh impl/runtime/build_rt.sh --lib
time sh impl/runtime/build_rt.sh --lib

# B2 差分
B2_JOBS=4 bash tests/b2/batch.sh
```
