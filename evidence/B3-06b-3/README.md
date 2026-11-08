# B3-06b-3 证据：嵌套/参数/返回/容器

## 结论

- 嵌套元组 `(Int,(Int,Int))`：内外 typedef 按内层先、外层后发射；`(t.1).0` 访问。
- 元组作参数/返回值：参数类型 `xn_tup_*`；返回元组字面量按 oracle 在 restore 块之后 `return (T){...};`。
- 元组作 List 元素：`List<(Int,Int)>` → `xn_arr_t_int64_t_int64_t`，专用 prelude/`get` 助手。
- 5 个元组 fixture C 与 Go `--emit-c` 逐字节一致；先红 `PASS=0`、绿 `PASS=5`。

## 测试

```bash
bash tests/b3/xnullc-tuple.sh
# PASS basic / eq_interp / in_list / nested / param_ret
# xnullc-tuple 汇总：PASS=5 FAIL=0
```

`hashes.out` 五例 SHA-256 相同；回归 obj/obj2/obj3/containers/err/expr-stmt/gen 全绿。

## 边界

- `List<tuple>` 已覆盖；`Map<String,(Int,Int)>` 元素尚未覆盖（下一刀）。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
