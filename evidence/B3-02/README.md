# B3-02 证据：基础表达式/语句

## 结论

- `impl/lib/b3/xnullc.x` 已扩展：Int/Bool/String/Char/Float/Double、算术/比较/逻辑（C `&&`/`||` 短路）、复合赋值 `+=`/`-=`、`print`/`str`、字符串拼接与插值、local decl、`if/else`、`while`、`for-in`（`List<Int>`）、`switch`、`return`。
- 6 个 EXPR/STMT fixture 的 C 文本与 Go `--emit-c` **逐字节一致**（`green.out`、`hashes.out`）。
- 双路径：Go 原生构建产物 vs xnullc 生成的 C（同一 cc/运行时）stdout/退出码一致。
- 先红：空 stub xnullc → `PASS=0 FAIL=6`（`red.out`）。

## 覆盖

| 层 | 文件 | 覆盖点 |
| --- | --- | --- |
| EXPR | `fixtures/expr/int_ops.x` | Int 算术/一元/比较/逻辑/`%`/`/` |
| EXPR | `fixtures/expr/scalars.x` | Char/Float/Double/Bool/String、`str`、字符串拼接 |
| EXPR | `fixtures/expr/interp.x` | 字符串插值链 |
| STMT | `fixtures/stmt/if_while.x` | `if/else`、`while`、`+=` |
| STMT | `fixtures/stmt/switch.x` | `switch` 降级为 `do/if/else if/else` |
| STMT | `fixtures/stmt/for_in.x` | `List<Int>` 字面量 + `for-in` + 容器 prelude |

## Oracle 不支持的构造（负例）

`ternary`、`do-while`、`incdec`、`*=`/`/=` 在当前 Go `--emit-c` 直接失败（M4.1 范围），
已加入 `tests/b3/negative.tsv`（`neg/*.x`）。这些构造无法产生黄金 C，B3-02 不以“能编译”替代文本差分；
待 Go oracle 扩展后再对拍。

## 测试

```bash
bash tests/b3/xnullc-expr-stmt.sh
# PASS expr/int_ops.x ... PASS stmt/switch.x
# xnullc-expr-stmt 汇总：PASS=6 FAIL=0

XNULL_BIN=/tmp/xnull-b3 bash tests/b3/run.sh
# emit-diff 9/9、dual-path 9/9、negative 7/7、skeleton 2/2、expr-stmt 6/6
```

`xnull check impl/lib/b3/xnullc.x` 通过（`check.out`）。

## 边界

- 只改 `impl/lib/b3/xnullc.x`、`tests/b3/`。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
- xnullc 仍以解释器执行（`xnull run --interp`），编译自身留后续卡。
