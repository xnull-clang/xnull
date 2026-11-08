# B2-04d 证据：原生差分器

## 结论

- 新增 `tests/b2/native-diff.sh`：原生 `xlex`/`xparser` ↔ `xnast` oracle，三层比较。
- 当前原生差异**非 0**：记录运行 `L1 34/7、L2 0/42、L3 6/37，PASS=40 FAIL=86`（L1 因原生 UB 在 33–36 间波动）。
- 因此**默认仍为 `go`**；`auto` 不启用，直到本门禁差异为 0。
- 差分器只作门禁，不接入生产路径。

## 原生二进制构建（本机验证）

```bash
cd <main>/impl
go run ./cmd/xnull build <worktree>/impl/lib/b2/xlex.x    -o /tmp/native-xlex
go run ./cmd/xnull build <worktree>/impl/lib/b2/xparser.x -o /tmp/native-xparser
```

## 复跑

```bash
XNULL_NATIVE_XLEX=/tmp/native-xlex \
XNULL_NATIVE_XPARSER=/tmp/native-xparser \
XNAST_BIN=/tmp/xnast \
bash tests/b2/native-diff.sh

# Go 门禁入口（默认跳过；显式开启后当前应 FAIL）
XNULL_B2_NATIVE_DIFF=1 XNULL_NATIVE_XLEX=/tmp/native-xlex \
XNULL_NATIVE_XPARSER=/tmp/native-xparser \
go test ./internal/frontbridge -run TestNativeDifferentialGate -count=1 -v
```

## 差异清单

`native-diff.tsv` 列：`层<TAB>文件<TAB>首个差异字节<TAB>want 片段<TAB>got 片段`；原生崩溃时 got 前缀 `[exit N]`。
`native-diff.out` 为完整 stdout（与本次 TSV 同一次运行）；`go-gate-red.out` 为另一次 Go 门禁失败输出（计数会波动）。

## 观察到的原生缺陷（供 E4/codegen 修）

- `examples/hello.x`：`Ret (NamedType (Qual "main"))`、`Name ""`、字符串变 `IdentExpr ")"`。
- 多个文件原生 xparser 段错误/abort（exit 139/134），输出为空或截断。
- 原生 xlex 对部分文件同样崩溃；正常文件在**保留文件末尾换行**时 token 与 oracle 一致。
  门禁脚本用 `cat + x` 技巧保留原始尾换行，避免误报 EOF Kind 0/1。
- L1 结果存在轻微非确定性（同一二进制重复运行 PASS 33–36），与原生 UB 一致；L2 稳定 0/42。

## 边界

- 未改 `xparser.x`/`xlex.x` 语义；未改 `internal/xfront`。
- 只新增 `tests/b2/native-diff.sh`、`impl/internal/frontbridge/native_diff_test.go`、证据与 handoff 说明。
