# B3-06c 证据：可选值（PARTIAL）

## 结论

- 已实现 `Int?`/`Bool?`/`String?`：`xn_opt_i/xn_opt_b/xn_opt_s` 包装、`null` → `{0,0}`、自动包装 `{1, v}`、打印 `if (x.has) ... else xn_print_null()`。
- `tests/b3/fixtures/type/opt.x` C 与 Go `--emit-c` 逐字节一致；先红 PASS=0、绿 PASS=1。

## 未完成

- Any/Object 装箱/拆箱、`is/as/as?` 类型描述符判断尚未实现；对应 TYPE 锚点未纳入本提交。

## 测试

```bash
bash tests/b3/xnullc-type.sh
# PASS tests/b3/fixtures/type/opt.x
# xnullc-type 汇总：PASS=1 FAIL=0
```

回归：obj/obj2/obj3/containers/err/expr-stmt/gen/tuple 全绿。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`；未改 Go codegen/oracle、未改 `xparser.x` 语义。
