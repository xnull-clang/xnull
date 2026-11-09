# B3-09 最终证据（2026-11-10）

- 产品提交：`974c5e1`（xnullc P7-48..55）
- 判定时 main：`0721022`（含门禁 900s/long-case 修复 `77a8a47`）
- 范围：`收件箱/门/B3-09范围-v1.0.2.md`

## 1. 全量门禁

`results.tsv` / `run.log`：

```text
文件 241；excluded=2；entries=239
PASS0=141；DIFF=0；FAIL=0；NEG-PASS=98；EXCLUDED=2
exit=0
```

xparser 单独复核：`xparser.txt`

```text
go_lines=29553  xn_lines=29553  cmp=SAME
sha256=a88a3e074729a6630a62914831913e7aa0d14b715aebe4a7d60d836780aa0bb9
```

## 2. 9 示例双路径 + 确定性

`examples.log`：

```text
PASS ast-seed.x / classes.x / containers.x / defer-cleanup.x / hello.x
PASS lexer-seed.x / objlist.x / parser-seed.x / result-try.x
xnullc-examples 汇总：PASS=9 FAIL=0
```

每个示例同时做两次 xnullc 生成（`xn.c` vs `xn2.c`）字节一致，再做 Go C /
xnullc C 各自 cc 编译运行、stdout/exit 比对。

## 3. 全量测试

- `fulltest.log`：`PKG_EXIT=0`（除 codegen 外的全部包，`go test -p 4`）。
- `codegen-shard.log`：`CG_EXIT=0`（`xnull dev test --parallel 4 ./internal/codegen`，
  4/4 分片绿）。

## 4. 关键文件状态

| 文件 | 状态 |
|---|---|
| `impl/lib/b2/xparser.x` | 0（29553 行，SHA 同上） |
| `impl/lib/b2/xlex.x` | 0 |
| `impl/xnfmt/xnfmt.x` | 0 |
| `collections_basic/nonnull.x` | 0 |
| `examples/parser-seed.x` + corpus | 0 |
| `difftest/.../f2.x` | 0 |
| `tests/s6/xdk05/sync_basic.x` + corpus | 0 |

## 5. 备注

- 2 个 `t00_sanity_text` 夹具按 v1.0.1 排除（`writeFileText` 无绑定）。
- 负例矩阵按 v1.0.2 由共享前端/sema 判定，xnullc 不参与源码 sema。
- xparser 生成慢，门禁 `run()` 超时 900s，并在 shard 内串行执行。
