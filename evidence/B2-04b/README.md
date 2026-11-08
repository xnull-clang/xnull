# B2-04b 证据：前端性能与默认回退 go

## 结论

- **默认模式改为 `go`**：未设置 `XNULL_FRONTEND` 即为 Go oracle；`xnull` 仅显式开启，`auto` 也需显式。
- **auto 生产路径禁用进程内解释器**：只用外部原生 `xparser` 二进制（`XNULL_NATIVE_XPARSER` 或缓存），没有则直接回退 Go。
- **AST 内容缓存**：`sha256(格式版本 + parser SHA-256 + 源码 SHA-256)` → 进程内 LRU（256）+ 磁盘缓存。
- **批处理**：`frontbridge.ParseBatch`（≤4 并发）；`codegen.LoadUnits` 对同一文件的直接 import 预取批解析。
- **元组防丢**：反序列化后校验 `TupleTypeRef` 数量与 dump 一致，不一致视为传输失败（auto 回退 Go）；新增元组回归测试。

## 前后数据（同一台机器）

### 微基准（8 个语料文件 × 30 次）

| 版本 | go ns/op | auto ns/op | auto/go |
| --- | ---: | ---: | ---: |
| B2-04（HEAD 335f77b） | 2.699 ms | 5.506 ms | **2.04x** |
| B2-04b | 2.408 ms | 2.612 ms | **1.08x** |

原始输出：`bench-before.out`、`bench-after.out`。

### 全量 `go test ./internal/codegen -count=1`

- 默认（go）：`ok … 68.9s`（`codegen-default.out`），绿。
- 显式 `XNULL_FRONTEND=auto`（本工作树无原生二进制 → Go 回退）：`ok … 62.6s`（`codegen-auto.out`），绿。
- 两者均 ≤170s。但本工作树无法用 `xnull build` 生成原生 xparser（codegen 尚不支持该源码），
  因此“真实 auto/native 路径 ≤170s”门禁无法验证；按规则**默认保持 go**。

> 报告中的 609s 来自解释器路径；该路径现已从默认/auto 生产路径移除。

## 测试

- `frontbridge-test.out`：反序列化往返、元组回归、auto 不调用进程内解释器、原生路径、自动构建缓存、LRU/磁盘缓存、批处理。
- `diff.out`：全语料三层差分 `PASS=83`（显式 `XNULL_FRONTEND=xnull` + 自举二进制）。
- `go-test-p4.out`：`go test -p 4`（排除未跟踪 `impl/Tests/`）；仅剩既有 `devtool` 台账 golden 红（基线 HEAD 同红，SSOT 不手改）。
- 测试硬规则：本工作树无 `xnull dev test --shard` 实现，包级按 `go test -p 4` 执行；用例级差分由 `TestB2Differential` 覆盖。

## 复跑

```bash
cd impl
go test -p 4 ./...                                   # 默认 go
XNULL_FRONTEND=auto XNULL_NATIVE_XPARSER=<bin> \
  go test ./internal/codegen -count=1                # 原生路径
XNULL_B2_DIFF=1 XNULL_SELFHOST_BIN=<xnull> \
  go test ./internal/frontbridge -run TestB2Differential -count=1
go test ./internal/frontbridge -run '^$' -bench BenchmarkParseUnitCorpus -benchtime=30x
```
