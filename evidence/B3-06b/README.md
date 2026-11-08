# B3-06b 证据：元组基础

## 结论（PARTIAL）

- 已实现元组结构体登记、字面量、成员访问、成员赋值：
  - `(Int, Int)` → `xn_tup_int64_t_int64_t`，typedef 位置/空行与 oracle 一致；
  - 局部 `T t = (T){.f0=..., .f1=...}`；`t.0` 读 `(t).f0`、赋值 `t.f0 = ...`；
  - String 元素先 `emitStr` 临时 + root。
- `tests/b3/fixtures/tuple/basic.x` C 逐字节一致；先红 PASS=0、绿 PASS=1。

## 未完成

- 元组相等/恒等（`==`/`!=`/`===`/`!==`）与插值（`$"{t}"`）尚未实现；
  Go oracle 会先复制元组到临时、逐元素比较/格式化，并混用 `xn_str_eq` 与指针相等。
- 嵌套元组、元组作为参数/返回值/容器元素未覆盖。

## 测试

```bash
bash tests/b3/xnullc-tuple.sh
# PASS tests/b3/fixtures/tuple/basic.x
# xnullc-tuple 汇总：PASS=1 FAIL=0
```

回归：obj/obj2/obj3/containers/err/expr-stmt/gen 全部保持绿。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`；未改 Go codegen/oracle、未改 `xparser.x` 语义。
