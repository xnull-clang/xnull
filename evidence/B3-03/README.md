# B3-03 证据：Result/try/defer

## 结论

- `impl/lib/b3/xnullc.x` 已支持：Result 实例化、`Ok`/`Err`、`isOk/isErr/value/error/unwrapOr`、`try` 传播、`defer`/`errdefer` 内联（LIFO、错误路径守卫）、`throw`。
- 4 个 CLEAN/ERR 锚点的 C 与 Go `--emit-c` **逐字节一致**，双路径（Go 原生 vs xnullc C）stdout/退出码一致。
- 先红：空 stub xnullc `PASS=0 FAIL=4`（`red.out`）。

## 锚点

| 类别 | 文件 | 覆盖点 |
| --- | --- | --- |
| CLEAN | `fixtures/err/clean_defer.x` | 函数级 `defer` LIFO 清理 |
| CLEAN | `fixtures/err/errdefer.x` | `defer` + `errdefer`；Ok 路径与 early-return 错误路径 |
| ERR | `fixtures/err/result_try.x` | Result 实例化、`Ok`/`Err`、`try`、`isOk/isErr/value/error/unwrapOr` |
| ERR | `fixtures/err/throw.x` | `throw` → `xn_throw` |

## 测试

```bash
bash tests/b3/xnullc-err.sh
# PASS err/clean_defer.x / errdefer.x / result_try.x / throw.x
# xnullc-err 汇总：PASS=4 FAIL=0

XNULL_BIN=/tmp/xnull-b3 bash tests/b3/run.sh
# emit-diff 9/9、dual-path 9/9、negative 7/7、skeleton 2/2、expr-stmt 6/6、err 4/4
```

- `hashes.out`：4 例 Go/XNull C SHA-256 全部相同。
- `xnull check impl/lib/b3/xnullc.x` 通过（`check.out`）。

## 实现要点

- 动态 prelude：按 Result 类型插入 `typedef struct { int ok; ... }` 与顶层函数原型，再拼固定 prelude。
- 顶层函数（含参数 `xn_p_*`、Result 返回 `xn_ret`）按声明顺序发射。
- `try`：Result 临时 + `if (!t.ok) { xn_ret = t; restore; cleanup; return xn_ret; }` + `v = t.v`。
- `defer`/`errdefer`：注册时分配临时编号，函数/块退出按 LIFO 内联；`errdefer` 包 `if (!xn_ret.ok)`。
- 仅使用 oracle 支持的 `Result<Int, String>`；未改 Go codegen。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
