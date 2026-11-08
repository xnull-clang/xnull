# B3-05b 证据：协议/继承/deinit

## 结论

- `impl/lib/b3/xnullc.x` 已支持：协议 vtable 布局/填充、协议变量动态派发、单继承字段扁平化/base new_init 链、继承方法解析与转换、deinit 方法/hook/release、super 调用、类型描述符。
- 5 个对象锚点 C 与 Go `--emit-c` **逐字节一致**；双路径（Go 原生 vs xnullc C）stdout/退出码一致。
- 先红：空 stub xnullc `PASS=0 FAIL=5`（`red.out`）。

## 锚点

| 文件 | 覆盖 |
| --- | --- |
| `fixtures/obj2/proto.x` | 协议 vtable 槽、`implements`、vtable 填充、类型描述符 |
| `fixtures/obj2/dispatch.x` | 协议变量上转 + vtable 动态派发 `((T (*)(void*))...->__vtable[i])(s)` |
| `fixtures/obj2/inherit.x` | 单继承字段扁平化、base new_init 链、继承方法解析/转换 |
| `fixtures/obj2/deinit.x` | `void deinit()`、hook 调用、ARC 释放、局部堆分配 |
| `fixtures/obj2/super_deinit.x` | deinit 覆写 + `super.deinit()` 调用 |

## 实现要点

- 协议：类结构 `void **__vtable` 槽；`xn_vt_<Cls>[slots+2]`；new 设置 `o->__vtable`；`xn_init_vtables` 按协议方法序填槽。
- 动态派发：`((<ret> (*)(void *))((xn_vt_obj *)(x))->__vtable[i])(x)`。
- 继承：派生结构按祖先→自身扁平化字段；new_init 先调 base；方法解析沿基类链，调用点把 `self` 转为声明类。
- deinit：hook 先调 `xn_Cls_X_deinit(o)` 再释放字段；有 deinit/协议/引用字段的局部走堆并登记 `rt_release`。
- super：`xn_Cls_<Base>_<m>(((xn_Cls_<Base> *)self))`。

## 测试

```bash
bash tests/b3/xnullc-obj2.sh
# PASS obj2/deinit.x dispatch.x inherit.x proto.x super_deinit.x
# xnullc-obj2 汇总：PASS=5 FAIL=0

XNULL_BIN=/tmp/xnull-b3 bash tests/b3/run.sh
# emit-diff 9/9、dual-path 9/9、negative 7/7、skeleton 2/2、expr-stmt 6/6、err 5/5、containers 5/5、obj 4/4、obj2 5/5
```

`hashes.out`：5 例 Go/XNull C SHA-256 全部相同；`xnull check` 通过。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
- 多协议/is/as?/singleton/factory/extension/enum 属 B3-05c 或后续。
