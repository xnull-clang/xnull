# B4b 大文件：native xparser 段错误修复（12/12 AST 逐字节一致）

- 卡片：B4b（native xparser 大文件阻塞项）
- 日期：2026-11-11
- 分支：`pod/e4-codegen`（已 `git merge main`）
- 基线：main `1c0e42d` + B4b-02
- 改动：`impl/lib/b2/xparser.x`、本文件、`evidence/B4b-xparser-largefile/`
- 结论：**PASS**。native xparser `--file` 对 `xlex.x`、`xparser.x`、`xnfmt.x` 与 `xnast --ast --dump-depth 100000` **逐字节一致**；9 示例 AST 9/9、完整验收 9/9。

## 1. 复现

```bash
cd wt/e4-codegen
XNULLC_BIN=/tmp/xn-s4 tests/b4/xnull-build.sh bootstrap-xparser -o /tmp/xparser-native
/tmp/xparser-native --file impl/lib/b2/xlex.x > /tmp/a.ast
# 修复前：rc=139（SIGSEGV），stdout 0 字节，stderr 0 字节
```

`head -n 320 impl/lib/b2/xlex.x` 同样 rc=139（非单调：300 行过、320 行崩，典型堆/GC 问题）。

调试环境说明：本机 ASAN 运行时与 libsystem_pthread 不兼容（最小 `cc -fsanitize=address` 程序即 `EXC_BAD_INSTRUCTION`），改用 `-fsanitize=undefined` 拿到精确栈。

## 2. 根因

### 2.1 主因：native codegen 对 GC 类局部变量重新赋值不补根（UAF）

`xn_Cls_Parser_parsePostfix` 的循环里 `e = ne`、`xn_Cls_Parser_parseBin` 的循环里 `l = be`，二者都是 **GC 类对象**。native xnullc 对 String 局部赋值会发 `xn_root_release/rt_release/.../xn_root_hold`，但对 GC 类类型只发裸赋值：

```c
e = ne;          // 无 xn_root_hold
xn_root_restore(mark);  // 本轮块内临时根被撤销
xn_gc_safepoint();      // 下一轮循环前 GC：ne 已不可达 → sweep
```

下一轮循环再读 `e.d`/`l.d` 即 use-after-free；内存被复用后 `e->d == NULL`，`xn_concat(a, NULL)` 在 `a->len` 处段错误。

证据（`evidence/B4b-xparser-largefile/ubsan-stack.txt`）：

```
xn_concat a.out.c:121: member access within null pointer of type 'rt_string'
#0 xn_concat
#1 xn_Cls_Parser_parsePostfix
#2 xn_Cls_Parser_parseUnary
#3.. xn_Cls_Parser_parseBin ×12
...
```

在 `xn_concat` 注入判空后得到 `a=0x... b=0x0`，返回地址经 `atos` 定位到 `parsePostfix` 中 `(Call ... + e.d + ...)` 的第二次拼接，第二个实参来自 `rt_retain(e->d)`。

### 2.2 放大因素：TP 重解析 + render

`parseUnit` 原本把 `parseTop` 产出的规范 S 表达式再喂给 `TP` 建树、`render` 递归重排。大文件下这是 O(n²) 拼接，并让每个 AST 节点的 `String` 局部根泄漏（`xn_root_hold` 在函数返回时不撤销），根表线性扫描成为主要开销。实测 `xlex.x` 修复段错误后仍需 **101s**。

`parseTop` 的输出本身就是与 oracle 相同的规范格式（引号内空格由 `TP.val` 的引号分支保留，渲染不改变），因此可直接输出。

### 2.3 `\u0000` / `\0` 解码缺口

native xnullc 把源文件里的 `"\u0000"` 编译为 `rt_string_from_c("")`（C 字面量中的 NUL 被 `strlen` 截断），xparser 原实现又只识别 `\n\t\r\\\"\'\0`，遇到 `\u0000` 会产出 `u0000`，比 oracle 多 1 字节（oracle 输出转义文本 `\x00`）。

## 3. 修复（只改 `impl/lib/b2/xparser.x`）

| 位置 | 改动 |
|---|---|
| `parseBin`（:1798） | `l` 改存 `List<E> lh`，每轮 `lh.set(0, be)`；容器生根，跨 `xn_gc_safepoint` 不再被回收 |
| `parsePostfix`（:1834） | 同上，`e` 改存 `List<E> eh`，所有 `e = ne` 改 `eh.set(0, ne)` |
| `parseUnit`（:1149） | 直接返回 `"(xnast v1 " + body + ")"`，移除 `TP` 建树 + `render`（输出已验证逐字节不变） |
| `Lexer.scanChar`（:441） | 支持 `'\0'` → `val = 0`（自身解析与 oracle 一致） |
| `Lexer.scanString`（:563） | `\0` 与 `\u0000` 用 `str('\0')` 构造真实 NUL；其余 `\u` 保持原行为 |
| `q`（:596） | NUL 输出为 `\x00`，与 Go `%q` 一致 |

未改 `xnullc.x`、未改 Go oracle。codegen 的根赋值缺口仍属 E4；本卡用容器生根绕过。

## 4. 验证

### 4.1 三个大文件（`evidence/B4b-xparser-largefile/byte-compare.txt`）

| 文件 | rc | 字节数 | sha256 | 结果 |
|---|---|---|---|---|
| `impl/lib/b2/xlex.x` | 0 | 240916 | `2c783fe3…` | IDENTICAL |
| `impl/lib/b2/xparser.x` | 0 | 1007946 | `4fd480c3…` | IDENTICAL |
| `impl/xnfmt/xnfmt.x` | 0 | 272310 | `a6001762…` | IDENTICAL |

耗时：xlex 5s、xparser 88s、xnfmt 7s（修复前 xlex 需 101s 且 xparser/xnfmt 不可用）。

### 4.2 AST 全量（`evidence/B4b-xparser-largefile/ast-check.log`）

```
XPARSER_BIN=/tmp/xparser-fix5 XNULLC_BIN=/tmp/xn-s4 tests/b4/xnull-build.sh ast-check
PASS 9 示例 + impl/lib/b2/xparser.x + impl/lib/b2/xlex.x + impl/xnfmt/xnfmt.x
AST 一致性：PASS=12 DIFF=0
```

### 4.3 9 示例完整验收（`evidence/B4b-xparser-largefile/examples.log`）

```
B4b-01 examples：PASS=9 FAIL=0
```

C sha256 与 B4b-01 完全一致（hello `3362e71c…`、containers `55f9d388…`、result-try `a7834e09…`）。

### 4.4 自举与 C 一致性

```bash
XPARSER_BIN=/tmp/xparser-fix3 XNULLC_BIN=/tmp/xn-s4 \
  tests/b4/xnull-build.sh bootstrap-xparser -o /tmp/xparser-self
shasum /tmp/e4b4b-self/xparser.c /tmp/xparser-fix3.c
# 两者均为 2c7be3b82ad74a0580e90d498bfc98281978106b（C-IDENTICAL）
/tmp/xparser-self --file impl/lib/b2/xlex.x | cmp - /tmp/xlex.oracle   # IDENTICAL
```

### 4.5 回归

- `--diags`：`parser_neg` 三个负例 code/line/col 与 oracle 一致。
- 字符串参数模式（非 `--file`）：9 示例 + `parser_cases/*.x` AST 与 oracle 一致。
- `tests/b2/native-diff.sh` 的 L2/L3 路径未受 `--file` 改动影响。

## 5. 复现（修复后）

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/e4-codegen
XNULLC_BIN=/tmp/xn-s4 tests/b4/xnull-build.sh bootstrap-xparser -o /tmp/xparser-fix
XPARSER_BIN=/tmp/xparser-fix tests/b4/xnull-build.sh ast-check   # 12/12
XPARSER_BIN=/tmp/xparser-fix tests/b4/xnull-build.sh examples    # 9/9
```

## 6. 遗留 / 后续

1. **E4 codegen**：GC 类局部变量赋值应统一补 `xn_root_hold`（或等价赋值后根帧），当前只在 String 分支处理；这是本次 UAF 的根因，xparser 只是绕过。
2. **E4 codegen**：全局 `List<String> X = [...]` 初始化器被发射成空列表（尝试把词法常量表提到顶层时发现），大文件词法常量仍每次重建。
3. **E2/词法**：`\uXXXX`（非零码点）、`\xHH` 仍未解码；当前只覆盖目标文件用到的 `\u0000`/`\0`。
4. 性能：xparser.x（1MB AST）88s，主要耗时在生成代码的根表线性扫描；根赋值修复后应显著下降，可再评估。
