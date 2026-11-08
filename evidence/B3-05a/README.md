# B3-05a 证据：类/结构体基础

## 结论

- `impl/lib/b3/xnullc.x` 已支持：类/结构体布局、字段、构造/主构造、方法、`new` 与栈分配、member 访问、基础 ARC（retain/release、deinit hook、gc_scan）。
- 4 个对象锚点 C 与 Go `--emit-c` **逐字节一致**；双路径（Go 原生 vs xnullc C）stdout/退出码一致。
- 先红：空 stub xnullc `PASS=0 FAIL=4`（`red.out`）。

## 锚点

| 文件 | 覆盖 |
| --- | --- |
| `fixtures/obj/class_point.x` | 类布局、显式构造、方法、`new` 栈分配、`self->field`、静态派发 |
| `fixtures/obj/class_string.x` | String 字段、deinit hook、gc_scan、ARC retain/release、String 返回 |
| `fixtures/obj/class_primary.x` | 主构造 `class Vec(final Int x, final Int y)`、隐式字段、`_new_1` |
| `fixtures/obj/struct_point.x` | struct 值语义、复制、`.` 成员、`(&p)` 方法调用 |

## 实现要点

- 类：`xn_Cls_<Name>` 结构（`rt_header` + 字段）、deinit/gc_scan、`RT_TYPE_XN_*`、`new_init/new`、方法。
- 有引用字段：`xn_gc_new` + `xn_root_add(o)` + gc_scan；无引用字段：`rt_arc_new`。
- 主构造：字段按参数逆序布局，`_new_1/_new_1_init`，隐式字段在方法中映射为 `self->x`。
- struct：`xn_Struct_<Name>` 值结构、`_new` 返回 value、方法接收 `*self`，调用点 `(&p)`。
- 局部 `new`：无引用字段类走栈分配（memset + new_init + `&t`），有引用字段走堆。

## 测试

```bash
bash tests/b3/xnullc-obj.sh
# PASS obj/class_point.x class_primary.x class_string.x struct_point.x
# xnullc-obj 汇总：PASS=4 FAIL=0

XNULL_BIN=/tmp/xnull-b3 bash tests/b3/run.sh
# emit-diff 9/9、dual-path 9/9、negative 7/7、skeleton 2/2、expr-stmt 6/6、err 5/5、containers 5/5、obj 4/4
```

`hashes.out`：4 例 Go/XNull C SHA-256 全部相同；`xnull check` 通过。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
- 继承/super、协议 vtable、deinit 方法、singleton/factory/extension/enum 属 B3-05b/05c，未在本卡范围。
