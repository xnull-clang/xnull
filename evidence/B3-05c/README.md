# B3-05c 证据：单例/工厂/扩展/枚举

## 结论

- `impl/lib/b3/xnullc.x` 已支持：singleton、factory、extension、简单枚举、数据枚举 + switch。
- 5 个对象锚点 C 与 Go `--emit-c` **逐字节一致**；双路径（Go 原生 vs xnullc C）stdout/退出码一致。
- 先红：空 stub xnullc `PASS=0 FAIL=5`（`red.out`）。
- **B3-05 整体收口**：obj 4/4 + obj2 5/5 + obj3 5/5 = 14 个对象锚点全绿。

## 锚点

| 文件 | 覆盖 |
| --- | --- |
| `fixtures/obj3/singleton.x` | `xn_Single_*` 布局/init/instance 访问/方法/`xn_init_singletons` |
| `fixtures/obj3/factory.x` | `xn_Factory_*` 静态工厂方法、new 返回 ARC |
| `fixtures/obj3/extension.x` | `xn_Cls_*_ext_*_N` 扩展方法、原型/放置 |
| `fixtures/obj3/enum_simple.x` | `xn_Enum_*` typedef/name 函数/成员/switch |
| `fixtures/obj3/enum_data.x` | 数据枚举结构/new/全局项/`xn_init_enums`/字段/方法/相等 |

## 测试

```bash
bash tests/b3/xnullc-obj3.sh
# PASS obj3/enum_data.x enum_simple.x extension.x factory.x singleton.x
# xnullc-obj3 汇总：PASS=5 FAIL=0

XNULL_BIN=/tmp/xnull-b3 bash tests/b3/run.sh
# emit-diff 9/9、dual-path 9/9、negative 7/7、skeleton 2/2、expr-stmt 6/6、err 5/5、containers 5/5、obj 4/4、obj2 5/5、obj3 5/5
```

`hashes.out`：5 例 Go/XNull C SHA-256 全部相同；`xnull check` 通过。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
