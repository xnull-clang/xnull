# B2-04e 证据：解释器前端 + 磁盘缓存验收

## 结论

- 默认模式改为**解释器前端（xnull 管线 + 磁盘缓存）**；无 runner 或失败时回退 Go，显式 `XNULL_FRONTEND=xnull` 才报 B2-001。
- `auto` 也允许进程内解释器；缓存命中直接反序列化，不启动任何 runner。
- 原生 xparser 暂缓：不自动发现、不自动构建；仅显式 `XNULL_NATIVE_XPARSER` 才使用。
- 全量 `internal/codegen`（xnull 管线）冷/热均绿且 ≤170s。

## 耗时（`internal/codegen -count=1`）

| 场景 | 耗时 | 结果 |
| --- | ---: | --- |
| xnull 冷缓存 | **88.2s** | 绿 |
| xnull 热缓存 | **76.5s** | 绿 |
| 默认模式（本工作树无 runner → Go 回退） | 102.8s | 绿 |
| 全量 `go test -p 4` | — | 仅既有 `devtool` 台账 golden 红 |

> 本工作树 `internal/interp` 缺 `Bytes`，进程内解释器不可用；上表 xnull 冷/热使用
> `XNULL_SELFHOST_BIN=/tmp/xnull-b2`（外部解释器）执行同一 `xparser.x`。
> 合并主线后默认走进程内解释器，无需外部二进制。

复跑：

```bash
cd impl
rm -rf /tmp/fbc-e && mkdir -p /tmp/fbc-e
XNULL_FRONTEND=xnull XNULL_SELFHOST_BIN=/tmp/xnull-b2 \
  XNULL_FRONTBRIDGE_CACHE=/tmp/fbc-e go test ./internal/codegen -count=1   # 冷
XNULL_FRONTEND=xnull XNULL_SELFHOST_BIN=/tmp/xnull-b2 \
  XNULL_FRONTBRIDGE_CACHE=/tmp/fbc-e go test ./internal/codegen -count=1   # 热
```

## B2 三层

- `b2-l1.out`：`PASS=40 FAIL=0`。
- `b2-l2.out`：`PASS=42 FAIL=0`（parser_cases + 全语料 + 负例）。
- 原生差分仍非 0（B2-04d），不阻塞本卡。

## 缓存与 runner

- 缓存键：`sha256(格式版本 + parser SHA-256 + 源码 SHA-256)`；进程内 LRU + 磁盘。
- 冷缓存 31 个唯一源码落盘；热缓存全部命中。
- `TestASTCacheMemoryAndDisk` 验证：同一源码第二次不调用 runner；清空内存后仍命中磁盘。
- `TestAutoTriesInterpreterWhenNoNative` 验证 auto 允许进程内解释器并在不可用时回退 Go。

## 测试

| 文件 | 说明 |
| --- | --- |
| `codegen-xnull-cold.out/.time` | xnull 冷缓存全量 |
| `codegen-xnull-warm.out/.time` | xnull 热缓存全量 |
| `codegen-default.out/.time` | 默认模式全量 |
| `b2-l1.out` / `b2-l2.out` | B2 L1/L2 |
| `frontbridge-test.out` | frontbridge 单测（含缓存/回退/原生显式路径） |
| `go-test-p4.out` | `go test -p 4`（排除未跟踪 `impl/Tests/`） |

## 边界

- 未改 `xparser.x`/`xlex.x` 语义，未改 `internal/xfront`。
- 只改 `impl/internal/frontbridge/`、handoff 说明与证据。
