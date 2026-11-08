# B3-06a-1 证据：泛型函数微切片（fn.x）

## 结论

- `identity<T>(T)` 唯一实例 `T=Int` 已实现：实例发现、`_i` mangle、参数/返回深替换；
  原型在 init 前、定义在 main 后（与 Go oracle 顺序一致）。
- `tests/b3/fixtures/gen/fn.x` C 与 Go `--emit-c` 逐字节一致，双路径（Go 原生 vs xnullc C）一致。
- 先红：空 stub `PASS=0 FAIL=1`；绿：`PASS=1 FAIL=0`。

## 测试

```bash
bash tests/b3/xnullc-gen.sh
# PASS gen/fn.x
# xnullc-gen 汇总：PASS=1 FAIL=0
```

`hashes.out` 的 Go/XNull SHA-256 相同；`xnull check` 通过。

## 边界

- 只实现 `fn.x`；类泛型、多实例/排序/上限、嵌套实参不在本切片。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
