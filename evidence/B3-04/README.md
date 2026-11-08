# B3-04 证据：容器

## 结论

- `impl/lib/b3/xnullc.x` 已支持数组/List/Set/Map：字面量、结构/助手 prelude、成员与下标、所有权 root 管理。
- 5 个容器用例 C 与 Go `--emit-c` **逐字节一致**；双路径（Go 原生 vs xnullc C）stdout/退出码一致，含越界 panic。
- 先红：空 stub xnullc `PASS=0 FAIL=5`（`red.out`）。

## 用例

| 文件 | 覆盖 |
| --- | --- |
| `fixtures/container/array.x` | `Int[]` 字面量、`a[i]` 读/写、长度 |
| `fixtures/container/list.x` | `List<Int>`：`remove/get/push/clear/length` |
| `fixtures/container/mapset.x` | `Map<String,Int>`（`get`）+ `Set<Int>`（`add/length`） |
| `fixtures/container/containers.x` | examples/containers 全量：数组、List、Map（`getOr/put/has`）、Set、函数参数、`for-in` |
| `fixtures/container/oob.x` | 越界下标 → `xn_fatal_oob`，双路径退出码 134 |

## 实现要点

- prelude 三档：`PRELUDE_ARR`（数组/List<Int>）、`PRELUDE_MAPSET`（Map+Set）、`PRELUDE_CONT`（全量，含 `getOr`），按 AST 使用面选择。
- 类型：`Int[]`/`List<Int>` → `xn_arr_i *`；`Map<String,Int>` → `xn_map_s_i *`；`Set<Int>` → `xn_set_i *`。
- 字面量：数组/List 直接 `xn_arr_i_new/push`；Set 先数组再 `xn_set_i_add` 转换；Map 逐键 `xn_map_s_i_put`（字符串键先 emitStr 并 root）。
- 成员：`length`（Set 走 `a->len`）、`get/getOr/put/has/add/remove/clear/push`；下标读写走 `xn_arr_i_get/set`。
- 所有权：容器本地双重 `xn_root_add` + `xn_gc_safepoint()`；函数指针参数在入口 `xn_root_add`。

## 测试

```bash
bash tests/b3/xnullc-containers.sh
# PASS container/array.x containers.x list.x mapset.x oob.x
# xnullc-containers 汇总：PASS=5 FAIL=0

XNULL_BIN=/tmp/xnull-b3 bash tests/b3/run.sh
# emit-diff 9/9、dual-path 9/9、negative 7/7、skeleton 2/2、expr-stmt 6/6、err 5/5、containers 5/5
```

`hashes.out`：5 例 Go/XNull C SHA-256 全部相同；`xnull check impl/lib/b3/xnullc.x` 通过。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
- 当前覆盖 `Int[]`/`List<Int>`/`Set<Int>`/`Map<String,Int>`；其它元素类型组合待后续卡。
