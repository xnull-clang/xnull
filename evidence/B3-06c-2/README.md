# B3-06c-2 证据：Any/Object 装箱 + is/as

## 结论

- Any 装箱：`42 as Any` → `xn_box_int((int64_t)(42))`、Bool → `xn_box_bool`、String → `xn_box_str`（先 emitStr + release）、类 → `xn_box_obj`。
- `is` → `xn_any_is(v, "Type")`；`as? Int/Bool` → `xn_any_get_int(..., 1)`；`as? String` → `xn_any_get_str`。
- `xn_Any`/`RT_TYPE_XN_ANY`/box/get 助手 prelude 按需启用。
- `type/is_as.x` 与 `type/opt.x` C 与 Go `--emit-c` 逐字节一致；先红 `PASS=0`、绿 `PASS=2`。

## 测试

```bash
bash tests/b3/xnullc-type.sh
# PASS type/is_as.x
# PASS type/opt.x
# xnullc-type 汇总：PASS=2 FAIL=0
```

回归：obj/obj2/obj3/containers/err/expr-stmt/gen/tuple 全绿。

## 边界

- 覆盖 Any 的 Int/Bool/String 装箱与 is/as?；Any 字段/对象拆箱到类的完整 GC 扫描留后续。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
