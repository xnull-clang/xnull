# B3-06a-2 证据：fn2.x 多实例

## 结论

- `identity<T>` 的 `Int`/`String` 两实例：`xn_identity_i`、`xn_identity_s`；mangle 与实例顺序（调用顺序）与 Go oracle 一致。
- `String` 实例：参数/返回深替换为 `rt_string *`，返回参数时按 oracle 先 `rt_retain(param)` 再 `return param`。
- `tests/b3/fixtures/gen/fn2.x` C 逐字节一致，双路径一致。
- 先红 `PASS=0 FAIL=2`；绿 `PASS=2 FAIL=0`（fn + fn2）。

## 测试

```bash
bash tests/b3/xnullc-gen.sh
# PASS gen/fn.x
# PASS gen/fn2.x
# xnullc-gen 汇总：PASS=2 FAIL=0
```

`hashes.out` 两例 SHA-256 相同；`xnull check` 通过。

## 边界

- 只扩到 fn2.x 两实例；类泛型、多轮上限、嵌套实参未做。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
