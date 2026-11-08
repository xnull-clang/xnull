# B3 text 剩余 91 行逐函数诊断

> 对照对象：`wt/e2-sema` 的 `xnullc` @ `9313c48`（`B3-08c-20 text 逐函数根收紧`）。
> Go 侧：`xnull build --emit-c tests/b3/fixtures/bundle_text/app.x`（Go oracle 冻结 `main@d02b3d2`）。
> 语料实际源码：`impl/lib/xdk/text.x`（bundle 投影）；fixture 入口 `tests/b3/fixtures/bundle_text/app.x`。
> 行号为该函数在 Go C / xnullc C 内的相对行；函数清单见文末复现脚本。
> 本文只做诊断，未改 xnullc。

## 0. 结论与行数分布

按函数边界逐行 diff（`diff -u <fn>.go.c <fn>.xnullc.c`）复现出与 E2 一致的 91 行：

| 函数 | 变更行 | 主因 |
|---|---:|---|
| `parseFloat` | 42 | `ch` 的 defer 块缺 4 处 / 多 1 处；root_add 层数多处 ±1；break 多恢复一层；一对逻辑括号 |
| `Regex.compile` | 17 | `ch` 的 defer 块缺 4 处 / 多 1 处；逻辑括号 1 对 |
| `utf16ToUtf8` | 14 | `res` 的 `rt_release` 缺 3 处；分支正常落出缺 1 个 `root_restore`；多 1 行 `root_add` |
| `utf8ToUtf16` | 12 | 3 个 else-if 分支落出缺 `root_restore`（各 4 行） |
| `Regex.isMatch` | 6 | `rt_retain`/`substring` 临时 root_add 多 4 行、if 体内少 2 行 |
| 合计 | 91 | |

两条通用规则先给出，后面每函数只给站点差异。

### 0.1 defer 队列（解释 E2 上次 349→403 的原因）

Go 的清理顺序由 **作用域链** 决定，不是一张全局列表：

1. 每个块进入时先登记 `root_restore(<mark>)`，随后每条 `String`/`Bytes` 局部声明在**当前块**追加 `rt_release(name)`。
2. **块正常落出**（`emitBlock`，`codegen.go:2084`）：只输出本块 defer，逆序（LIFO）；
   每项独立 `{ ... }`，不合并。`return` 已接管时跳过（`if !s.returned`）。
3. **return**（`emitCleanup`，`codegen.go:2032`）：从最内层作用域向外逐层走，
   每层内仍按 LIFO；顺序是：
   `最内 if 块 root_restore → 循环块 rt_release(局部) → 循环块 root_restore → 外层 if 块 root_restore → 函数 root_restore`。
4. **break/continue**（`emitRootRestores`，`codegen.go:2064`）：只恢复被跳出块的根帧，
   **不执行 rt_release**。
5. **函数末尾正常落出**：只执行函数作用域 defer；循环体内的局部 release 已在循环体块尾执行，
   不得在函数尾重放。

xnullc 目前把局部 release 记在一张全局/跨层 defer 表里，导致：
- 循环体正常落出时漏 `rt_release(ch)`；
- return 时漏 `rt_release(ch)`；
- 函数末尾反而把循环局部的 `rt_release(ch)` 重放（parseFloat 2 次、compile 1 次）。

上次“在 early return 后直接插 release”会变差，是因为没有同时修块尾/函数尾，
同一 release 被全局表在函数尾再放一次，且插入位置绕过了作用域顺序。
正确做法：把 release 挂到**声明所在块**的 defer 队列，统一由
`emitBlock`（块尾）、`emitCleanup`（return）、`emitRootRestores`（break/continue）三处消费。

### 0.2 root_add 层数（逐语句扫描的叠加）

Go 的 `rootTempDecls`（`codegen.go:5603`）在 `emitStmt`（`:2126`）包装层对**整棵语句子树**
逐行扫描 GC 类型 `x = ...` 声明，并在该声明行后追加一行无缩进 `xn_root_add(x);`。
因此同一个临时会被它自己所在语句、以及每层祖先语句各追加一次，缩进由各层后续
`reindent` 决定。局部声明的 `emitStmtInner` 还会额外追加一次自己的根。

对本文件的操作口径（不要套公式，按站点改）：

- **函数体顶层**的 `String *xn_tN = ...`：Go 1 行（return 表达式临时为 2 行）；
  xnullc 多为 2 行 → 删 1 行。
- **一级 while 体内**：两边一致（不增删）。
- **二级嵌套（while 内再 if/while）**：xnullc 少 1 行，缺的是**8 空格缩进**那一行
  （Go 形如 `0 / 8 / 12 / 12`，xnullc 只有 `0 / 12 / 12`）。
- **return 值临时**（如 `xn_t353`）：Go 2 行，保持。

## 1. parseFloat（42 行）

源码：`impl/lib/xdk/text.x:122-178`，Go C 函数 `xn_parseFloat`。

### 1.1 early Err return 缺 `rt_release(ch)`（2 处，6 行）

Go（`非法字符`，text.x:136）：

```c
xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t132)};
    { xn_root_restore(xn_t131); }
    { rt_release(ch); }          /* ← xnullc 缺这一块 */
    { xn_root_restore(xn_t120); }
    { xn_root_restore(xn_t110); }
return xn_ret;
```

xnullc：`t131` 后直接 `t120`，缺 `rt_release(ch)`。

- 插入点：`{ xn_root_restore(xn_t131); }` 之后、`{ xn_root_restore(xn_t120); }` 之前。
- 形状：独立块；`{`/`}` 与相邻 restore 块同缩进（16 空格），块内 `rt_release(ch);` 为 12 空格。
- 同样一处：`非法小数`（text.x:148），锚点 `xn_root_restore(xn_t144)` →
  `rt_release(ch)` → `xn_root_restore(xn_t136)` → `xn_root_restore(xn_t135)` →
  `xn_root_restore(xn_t110)`。
- 顺序依据：`ch` 声明在 while 块，return 时先执行内层 if 的 root_restore，
  再执行 while 块的 `[rt_release(ch), root_restore(t136)]`（LIFO）。

### 1.2 循环体正常落出缺 `rt_release(ch)`（2 处，6 行）

Go（外层 while，text.x:139）：

```c
i = (i + 1);
    { rt_release(ch); }        /* ← 缺 */
    { xn_root_restore(xn_t120); }
xn_gc_safepoint();
```

内层 while（text.x:152）同理：`i = (i + 1);` 后先 `{ rt_release(ch); }`，
再 `{ xn_root_restore(xn_t136); }`。

- 插入点：`i = (i + 1);`（各循环体最后一条语句）之后、对应 `root_restore` 块之前。
- 形状：`{`/`}` 与该循环体块尾 restore 同缩进（外层 8、内层 16），
  块内 `rt_release(ch);` 分别 8 / 16 空格。
- 只有正常落出才发；`break` 路径不发（见 1.3）。

### 1.3 break 多恢复一层 + 循环后缺恢复（1 + 4 行）

Go（内层 while 的 `break`，text.x:146）：

```c
xn_root_restore(xn_t142);
xn_root_restore(xn_t136);
break;
```

xnullc 多了一行 `xn_root_restore(xn_t135);`（把外层 if 块提前恢复）。

- 删除：`break;` 前紧邻的 `xn_root_restore(xn_t135);`。
- `break` 只恢复被跳出的循环块（t136）与其内嵌 if 块（t142），不恢复 t135。

内层 while 关闭后（text.x:153-154），Go 还有：

```c
    xn_gc_safepoint();
    }
    { xn_root_restore(xn_t135); }   /* ← xnullc 缺 */
}
```

- 插入点：内层 `while` 的 `}` 之后、外层 `if (i < n)` 的 `}` 之前。
- 形状：独立块，`{`/`}` 8 空格，块内 `xn_root_restore(xn_t135);` 8 空格。
- 这属于外层 `if` 块正常落出的 cleanup，不是循环体 cleanup。

### 1.4 函数尾多 `rt_release(ch)`（4 行）

Go 函数尾：

```c
xn_ret = (xn_Result_Double_Error){1, v, 0};
    { xn_root_restore(xn_t110); }
return xn_ret;
```

xnullc：

```c
xn_ret = ...;
    { rt_release(ch); rt_release(ch); }   /* ← 整块删除 */
    { xn_root_restore(xn_t110); }
```

- 删除整个 `{ rt_release(ch); rt_release(ch); }` 块。
- 原因见 0.1 第 5 条：两个 while 体内的 `ch` release 已在各自块尾/return 路径消费，
  函数尾不得重放。

### 1.5 root_add 层数（约 18 行）

| 站点 | Go | xnullc | 动作 |
|---|---:|---:|---|
| 函数体 `xn_t133`/`xn_t134`（text.x:141 条件） | 1 | 2 | 删 1 行 0 空格 |
| 外层 while `ch`、`xn_t122`（132-133） | 3 / 2 | 3 / 2 | 不动 |
| 内层 while `ch`（145） | 4（0/8/12/12） | 3（0/12/12） | 在第一个 add 后插 1 行 **8 空格** |
| 内层 `xn_t138/139/140/141/143/145` | 3（0/8/12） | 2（0/12） | 同上，各插 1 行 **8 空格** |
| 函数体 `xn_t148/149/150/151`（156-157） | 1 | 2 | 各删 1 行 0 空格 |
| 嵌套 `xn_t157/158/161/163/165`（159-165） | 3 | 2 | 各插 1 行 **8 空格** |

注意 `xn_t163` 还有“少 1 行 8 空格 + 多 1 行 12 空格”的移位：先按上表补 8 空格，
再删掉最后多出的 12 空格外层重复行（以 Go 段 `0/8/12` 为准）。

### 1.6 逻辑括号（2 行）

Go（text.x:156 指数判定）：

```c
if ((((i < n)) && ((xn_str_eq(t148,t149) || xn_str_eq(t150,t151))))) {
```

xnullc：

```c
if ((((i < n)) && (xn_str_eq(t148,t149) || xn_str_eq(t150,t151)))) {
```

- 右操作数 `(A || B)` 作为 `&&` 的操作数时，Go 在它外面**再加一对括号**。
- 规则：`cond` 递归生成 `&&`/`||` 时，若某个操作数本身是 `&&`/`||`，
  该操作数包成 `"(" + 已带括号的表达式 + ")"`；普通比较/原子操作数不变。

## 2. Regex.compile（17 行）

源码：`impl/lib/xdk/text.x:271-283`，Go C `xn_Cls_Regex_compile`。

### 2.1 `ch` 的 defer 块（4 缺 + 1 多 = 15 行）

Go 有三处 early Err return（text.x:273/276/279）：

```c
xn_ret = (xn_Result_Regex_Error){0, NULL, xn_textErr(...)};
    { xn_root_restore(xn_t339); }   /* 276 行站点是 t347，279 行是 t351 */
    { rt_release(ch); }             /* ← xnullc 每处都缺 */
    { xn_root_restore(xn_t325); }
    { xn_root_restore(xn_t324); }
return xn_ret;
```

- 插入点：内层 if 的 `root_restore` 块之后、循环块 `root_restore(xn_t325)` 之前。
- 形状/缩进：与相邻块一致（`{`/`}` 16 空格，`rt_release(ch);` 12 空格）。

循环体正常落出（text.x:281）：

```c
i = (i + 1);
    { rt_release(ch); }        /* ← 缺 */
    { xn_root_restore(xn_t325); }
xn_gc_safepoint();
```

- 插入点：`i = (i + 1);` 后、`root_restore(t325)` 前，形状同上。

函数尾（text.x:283）：

```c
xn_ret = (xn_Result_Regex_Error){1, xn_Cls_Regex_new(xn_t353), 0};
    { xn_root_restore(xn_t324); }     /* Go 无 release */
return xn_ret;
```

xnullc 多一个 `{ rt_release(ch); }` 块 → 删除（与 parseFloat 1.4 同因）。

### 2.2 逻辑括号（2 行）

Go（text.x:276）：

```c
if (((((A || B) || C))) && ((i == 0)))) {
```

xnullc 左侧 `||` 链少一对括号：

```c
if ((((A || B) || C)) && ((i == 0)))) {
```

- 左操作数是 `&&` 的 `||` 子表达式 → 外面再加一对括号。
- 右操作数 `((i == 0))` 两边一致，不动。

## 3. utf16ToUtf8（14 行）

源码：`impl/lib/xdk/text.x:225-259`，Go C `xn_utf16ToUtf8`。

### 3.1 `res` 的 return 清理缺 `rt_release`（3 处，9 行）

三个 early Err return（text.x:241、243、251）：

```c
xn_ret = (xn_Result_Bytes_Error){0, NULL, xn_textErr(...)};
    { xn_root_restore(xn_t200); }    /* 各站点内层 mark */
    { rt_release(res); }             /* ← xnullc 缺 */
    { xn_root_restore(xn_t199); }    /* 循环块 */
    { xn_root_restore(xn_t196); }    /* 函数块 */
return xn_ret;
```

- 插入点：内层 if 的 root_restore 之后、循环块 `root_restore(xn_t199)` 之前。
- 块形状：独立 `{ ... }`；`rt_release(res);` 缩进与相邻 `xn_root_restore` 行一致
  （Go 段为 36 空格层，直接照抄相邻块即可）。
- `res` 是 `Bytes` 局部，声明在函数块；return 走作用域链时在循环块层释放。

### 3.2 else-if 分支落出缺 `root_restore`（4 行）

第三个分支（text.x:240-245）：

```c
i = (i + 2);
    { xn_root_restore(xn_t204); }   /* ← xnullc 缺 */
} else if (u >= 0xDC00 && u <= 0xDFFF) {
```

- 插入点：分支最后一条语句 `i = (i + 2);` 之后、`} else if` 之前。
- 形状：4 行独立块（`{` / `    xn_root_restore(xn_t204);` / `}` + 空行），
  缩进比分支内语句多 4。
- 语义：then 分支正常落出时恢复该分支块的根帧（`emitBlock` 的块尾 cleanup），
  不能等到下一个 else 分支。

### 3.3 root_add 多 1 行（1 行）

text.x:226 `Bytes res = Bytes.fromString("")` 的中间临时：

```c
rt_string *xn_t197 = rt_string_from_c("");
xn_root_add(xn_t197);
/* xnullc 多一行 xn_root_add(xn_t197); */
xrt_bytes_obj *xn_t198 = xrt_bytes_from_string(...);
```

- 删除重复的第 2 行 `xn_root_add(xn_t197);`（保留紧邻 decl 的第一行）。

## 4. utf8ToUtf16（12 行）

源码：`impl/lib/xdk/text.x:185-222`，Go C `xn_utf8ToUtf16`。

三个 else-if 分支（2 字节 `:196`、3 字节 `:203`、4 字节 `:216`）在正常落出、
进入下一个 `else` 前各缺一个分支块 root_restore：

```c
i = i + 2;
    { xn_root_restore(xn_t177); }   /* ← 缺 */
} else if (c >= 0xE0 && c < 0xF0) {

i = i + 3;
    { xn_root_restore(xn_t183); }   /* ← 缺 */
} else if (c >= 0xF0 && c < 0xF8) {

i = i + 4;
    { xn_root_restore(xn_t189); }   /* ← 缺 */
} else {
```

- 插入点：各分支最后一条 `i = i + N;` 之后、`} else` 之前。
- 形状：4 行独立块；`{`/`}` 比分支内语句多 4 空格，`xn_root_restore` 行内缩进与相邻
  `xrt_bytes`/`xn_arr_u16_push` 同级（直接照抄 Go 段）。
- 三个 mark 分别对应分支块的 `size_t mark = xn_root_mark();`（t177/t183/t189）。
- 没有 `rt_release(res)` 差异：`res` 在函数块，分支落出不释放。

## 5. Regex.isMatch（6 行）

源码：`impl/lib/xdk/text.x:285-295`，Go C `xn_Cls_Regex_isMatch`。

### 5.1 函数体临时多 1 行（4 行）

Go：

```c
rt_string *xn_t355 = rt_retain(self->pattern);
xn_root_add(xn_t355);
rt_string *xn_t356 = rt_retain(self->pattern);
xn_root_add(xn_t356);
rt_string *xn_t357 = xn_str_substr(xn_t356, 0, 1);
xn_root_add(xn_t357);
rt_string *xn_t358 = rt_string_from_c("^");
xn_root_add(xn_t358);
```

xnullc 每个临时后各多一行 `xn_root_add`（共 4 行）。

- 删除：`xn_t355/356/357/358` 后第二行重复的 `xn_root_add(...)`，各保留 1 行。
- 其中 t355/t356 是 `rt_retain(self->pattern)` 的接收者 retain 结果；
  retain 本身不额外加根。

### 5.2 if 体内临时少 1 行（2 行）

Go（text.x:289 的 `if self.pattern.length() > 0 && ...` 体内）：

```c
rt_string *xn_t360 = rt_retain(self->pattern);
xn_root_add(xn_t360);
        xn_root_add(xn_t360);
        xn_root_add(xn_t360);
rt_string *xn_t361 = rt_retain(xn_p_text);
xn_root_add(xn_t361);
        xn_root_add(xn_t361);
        xn_root_add(xn_t361);
```

xnullc 只有 `0/8` 两行，缺第二个 **8 空格** 行。

- 插入：`xn_t360`、`xn_t361` 各自的 8 空格 `xn_root_add(...)` 后再补一行同缩进。
- 与 1.5 的“二级嵌套少 1 行 8 空格”同因。

## 6. 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang
# Go C
/tmp/xnull-orc build --emit-c tests/b3/fixtures/bundle_text/app.x > /tmp/text.go.c
# xnullc C（commit 9313c48）
git -C wt/e4-codegen show 9313c48:impl/lib/b3/xnullc.x > /tmp/xnullc-9313c48.x
/tmp/xnull-orc run --interp /tmp/xnullc-9313c48.x -- \
  tests/b3/fixtures/bundle_text/app.x <ast> <projection> '<bundle.json>' > /tmp/text.xn.c
```

按函数截取（起点正则）后 `diff -u`：

- `xn_parseFloat(rt_string`
- `xn_Cls_Regex_compile(rt_string \* xn_p_pattern) {`
- `xn_utf16ToUtf8(xn_arr_u16`
- `xn_utf8ToUtf16(xrt_bytes_obj`
- `xn_Cls_Regex_isMatch(xn_Cls_Regex \*self`

行数核对：`42 + 17 + 14 + 12 + 6 = 91`。
