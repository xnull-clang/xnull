# B3-06b-2 证据：元组相等 + 插值

## 结论

- 元组 `==`/`!=`/`===`/`!==`：oracle 形式先复制左右元组到临时，再逐元素比较；
  `==`/`!=` 的 String 元素用 `xn_str_eq`，`===`/`!==` 用指针相等；`!=`/`!==` 整体取反。
- 元组插值 `$"{t}"`：临时复制元组，`"(" + f0 + ", " + f1 + ")"` 的 concat 链，String 元素 `rt_retain`。
- `tuple/basic.x` 与 `tuple/eq_interp.x` C 与 Go `--emit-c` 逐字节一致；先红 `PASS=0`、绿 `PASS=2`。

## 测试

```bash
bash tests/b3/xnullc-tuple.sh
# PASS tuple/basic.x
# PASS tuple/eq_interp.x
# xnullc-tuple 汇总：PASS=2 FAIL=0
```

`hashes.out` 两例 SHA-256 相同；回归 obj/obj2/obj3/containers/err/expr-stmt/gen 全绿。

## 边界

- 只做 `(Int, String)` 元组的相等/插值；嵌套/参数/返回值/容器元素下一刀。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
