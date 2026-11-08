# B3-06a-3 证据：class.x 泛型类实例

## 结论

- `Box<T>` 的 `Box<Int>` 实例：`xn_Cls_Box_i` 结构/RT_TYPE/new_init/new/methods 全部 `_i` 后缀；
  字段/参数/方法返回深替换为 `int64_t`；typedef 双段与原型位置同 Go oracle。
- 泛型类实例局部走堆（`_new` + 单 root + 末尾 release），不套用非泛型类的栈优化。
- `tests/b3/fixtures/gen/class.x` C 逐字节一致，双路径一致。
- 先红 `PASS=0 FAIL=3`；绿 `PASS=3 FAIL=0`（fn/fn2/class）。

## 测试

```bash
bash tests/b3/xnullc-gen.sh
# PASS gen/class.x
# PASS gen/fn.x
# PASS gen/fn2.x
# xnullc-gen 汇总：PASS=3 FAIL=0
```

`hashes.out` 三例 SHA-256 相同；`xnull check` 通过。

## B3-06a 收口

函数单实例（fn）、多实例（fn2）、类实例（class）三例全绿。

## 边界

- 只做 class.x 的 `Box<Int>`；多轮上限/嵌套实参/类泛型多实例未做。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
