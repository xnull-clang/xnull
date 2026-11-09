# B3-09 K-06 剩余 diff 函数/机制聚类（E4 → E2 施工单）

> 输入基线：`/tmp/b3-base2b/results.tsv`（PASS0=108、DIFF=33、FAIL=2、K07-LIMIT=0）。
> oracle：`/tmp/xnull-b3-base2`；AST：`/tmp/xnast-b3-base2`；xnullc：`main@2d8ab2f` 的
> `impl/lib/b3/xnullc.x`（文件最后改动 `60b7cdc`，K-06-01 parser-seed）。
> 本文只读分析，未修改 xnullc / Go oracle / 测试。
>
> 统计口径：逐文件生成 Go C 与 xnullc C，按 C 函数边界切分；`chg` = 统一 `xn_tN→xn_t#`
> 并去前导缩进后的 `+/-` 行数，`raw` = 未归一化的 `+/-` 行数，`content` = 基线
> `results.tsv` 的 content 列（含 unified diff 上下文，故不能与 `chg` 直接相加）。
> 函数级行号均指 `impl/lib/b3/xnullc.x`；C 证据行号指本次生成的 `/tmp/b3-k06-after/*.c`。

## 0. 结论摘要

1. **xparser / xlex / xnfmt 的大头不是 codegen，是 xnast 的 64 层 AST 序列化截断**。
   `xnast --ast` 在深层表达式上输出 `(depth-limit)`，xnullc 把截断节点降级成 `0`、
   `0(0)`、`rt_string_from_c("")`。`xparser` 受影响函数占其 `chg` 的 **63%**，
   `xlex` 23%，`xnfmt` 29%。前端 `frontbridge.go:73` 本来就检测 `(depth-limit)` 并回退
   Go oracle；B3-09 直接调 `xnast --ast`，绕过了这个门禁。**先加门禁，不要在 xnullc
   里追这些幻影 diff。**
2. 真正的 xnullc 规则前两名：**表达式物化策略**（return / 实参 / 成员接收者 / Opt-Result
   调用绑定，约 1800 `chg`，7 文件）和 **通用 `List<T>` 代码生成**（数组字面量 +
   按元素类型分派 helper，约 1000 `chg`，5 文件）。
3. coll_basic / coll_nonnull 和 f2 不是“文本差”，是**语义错**：`OrderedMap.put` 被发成
   `xn_map_s_i_put(om, "", 20)`、`PriorityQueue.push` 被发成 `xn_arr_i_push(pq, 3)`、
   `connectAsync` 直接 `return xn_ret;` 未赋值。必须先按通用规则修，不能只对文本。
4. f2 / coll 的剩余 diff 集中在“泛型用户类 + 容器类同名方法 + Lambda/函数指针字段 +
   Bytes 字段所有权”，与 K-06 的 temp/root 不是同一类问题；不要用 K-06 的 root 计数
   口径去验收。
5. 所有修法都应落在共享 emit 分支；coll / f2 / bundle_app 只作为验收夹具，不做文件特判。

## 1. 8 文件总览

| 文件 | content | chg | raw | depth-limit 影响函数占比 | 首因 |
|---|---:|---:|---:|---:|---|
| `impl/lib/b2/xparser.x` | 6710 | 4268 | 33490 | 63%（12 函数） | depth-limit + List<T> + 物化 |
| `impl/xnfmt/xnfmt.x` | 1838 | 905 | 5440 | 29%（2 函数） | String 方法 + List<String> + depth |
| `impl/lib/b2/xlex.x` | 1783 | 1157 | 4059 | 23%（2 函数） | ArrayLit + 返回物化 + depth |
| `tests/s6/xdk07/collections_basic.x` | 947 | 456 | 653 | 0 | 泛型类方法分派 + Lambda + Opt 绑定 |
| `tests/s6/xdk07/collections_nonnull.x` | 925 | 441 | 632 | 0 | 同上（少 pop 相关行） |
| `examples/parser-seed.x` | 304 | 152 | 818 | 0 | 返回/实参物化 + String 方法 |
| `difftest/anchors/cases/pkg/f2.x` | 272 | 98 | 526 | 0 | Result 返回 + 参数遮蔽 + Bytes 字段 |
| `tests/b3/fixtures/bundle/app.x` | 97 | 81 | 97 | 0 | 容器 typedef/helper 双注册表 |

`chg` 合计约 7718 行（归一化），但 `content` 合计 12876 行；差距来自统一 diff 的
上下文/文件头，以及 xparser/xnfmt/xlex 大量 root_add 行在归一化后仍然保留。

---

## 2. 逐文件

### 2.1 `impl/lib/b2/xparser.x`（content 6710）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_Cls_Parser_parsePrimary` | 633 | 2521 | RetMat（16 处 `return call` 落临时）+ DepthLimit（9 节点）+ List<T> |
| `xn_Cls_Parser_parseTypeDecl` | 603 | 2713 | DepthLimit（55 节点，`0 + 0` 链）+ ArrayLit（8 个 `= 0`） |
| `xn_Cls_Parser_parseTop` | 298 | 974 | DepthLimit（6 节点）+ ArrayLit + `void` 标识符 |
| `xn_Cls_Parser_parseMember` | 230 | 420 | ArrayLit + DepthLimit（8 节点）+ TempPolicy |
| `xn_Cls_Lexer_scanString` | 197 | 1277 | DepthLimit（33 节点）+ ArrayLit + TempPolicy |
| （6）`xn_Cls_Lexer_scanToken` | 184 | 326 | RetMat（12 处 `return scanString`） |

**证据 1：`List<String>` 字面量退化成 `= 0` + int helper**

```c
/* Go xparser.go.c:15768-15777, 15800 */
xn_arr_s *xn_t2775 = xn_arr_s_new(0);
xn_root_add(xn_t2775);
xn_arr_s * tps = xn_t2775;
...
xn_arr_s_push(tps, xn_t2782);

/* xnullc xparser.xn.c:14789-14798, 14809 */
xn_arr_s * tps = 0;
xn_root_add(tps);
...
xn_arr_i_push(tps, xn_Cls_Parser_next(self)->text);   /* tps 是 xn_arr_s*，这里发成 int push */
```

**证据 2：depth-limit 截断后整条字符串拼接变成 `0 + 0`**

```c
/* xparser.xn.c:15093 */
xn_arr_i_push(sigs, (((((((((((0 + 0) + ms) + 0) + xn_q(xn_t2631)) + 0) + xn_B(vd)) + 0)
  + xn_Cls_Parser_retv(self, vd, xn_t2632)) + 0) + xn_SL(ps)) + 0));
```

**证据 3：返回调用被强行落临时并 4 次 root_add**

```c
/* xnullc xparser.xn.c:21328-21339 */
xn_Cls_E * xn_t3794 = xn_Cls_Parser_mk(self, xn_t3793, t->line, t->col);
xn_root_add(xn_t3794);
xn_root_add(xn_t3794);
xn_root_add(xn_t3794);
...
return xn_t3794;

/* Go xparser.go.c:23229 */
return xn_Cls_Parser_mk(self, xn_t4224, t->line, t->col);
```

**判断：多独立机制。** 首因是输入截断（非 codegen）；扣掉 depth 后仍有 3 条通用规则：
List<T> 代码生成、返回/实参物化、C 关键字标识符（`int void = 0;`，parseTop）。

---

### 2.2 `impl/xnfmt/xnfmt.x`（content 1838）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_Cls_Fmt_format` | 181 | 845 | StrMethod（replace/trim）+ List<String> 分派 + ExprStrLit + root_hold |
| `xn_Cls_Fmt_keywordNoEnd` | 124 | 276 | DepthLimit（长 `||` 链被截断，部分字面量变 `xn_str_int(0)`） |
| `xn_Cls_Fmt_matchOp` | 64 | 302 | DepthLimit（长 `||` 链） |
| `xn_Cls_Fmt_markAngles` | 28 | 166 | TempPolicy（arg 临时）+ IntField（Bool 字段 `int64_t`） |
| `xn_Cls_Fmt_markUnary` | 28 | 162 | 同上 |
| （6）`xn_Cls_Fmt_sortImports` | 26 | 64 | ListDisp（`xn_arr_s_get/set` → `xn_arr_i_*`）+ 实参物化 |

**证据 1：String 成员方法未覆盖，直接发成 C 结构体方法调用**

```c
/* xnullc xnfmt.xn.c:743, 767, 793, 801 */
rt_string *xn_t69 = xn_p_src.replace(xn_t67, xn_t68);
rt_string *xn_t75 = xn_p_src.trim();
xn_arr_i_clear(self->outLines);      /* lines/header/imports 都是 List<String> */
rt_string *xn_t80 = rt_retain(0);    /* self.pkg = "" 走 expr(), 不是 emitStr() */
```

**证据 2：depth-limit 把关键字字面量改成 `xn_str_int(0)`**

```c
/* Go xnfmt.go.c:4677 */
rt_string *xn_t618 = rt_string_from_c("return");
/* xnullc xnfmt.xn.c:4416 */
rt_string *xn_t594 = xn_str_int(0);
```

**证据 3：`List<String>` 清空/取元素全用 int helper**

```c
/* Go xnfmt.go.c: format 内 */
xn_arr_s_clear(self->outLines);
rt_string *lt = rt_retain(xn_arr_s_get(self->lines, i));
/* xnullc xnfmt.xn.c:793, 892 */
xn_arr_i_clear(self->outLines);
rt_string *lt = xn_arr_i_get(self->lines, i);
```

**判断：多机制。** 核心是 String 通路（方法表 + literal 走 emitStr）和 List<T> 分派；
`keywordNoEnd`/`matchOp` 属 depth-limit，不修 xnullc 也应先被门禁挡住。

---

### 2.3 `impl/lib/b2/xlex.x`（content 1783）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_Cls_Lexer_scanString` | 197 | 1277 | DepthLimit（33 节点，`0(0)`/`0.adv()`/`0 = 0`）+ ArrayLit + TempPolicy |
| `xn_Cls_Lexer_scanToken` | 184 | 326 | RetMat（12 处 `return scanString`） |
| `xn_Cls_Lexer_matchOp` | 164 | 348 | ArrayLit（52 项 `List<String>`）+ ListDisp |
| `xn_Cls_Lexer_isKeyword` | 129 | 143 | ArrayLit（关键字数组） |
| `xn_Cls_Lexer_next` | 48 | 112 | RetMat / TempPolicy |
| （6）`xn_dumpTok` | 48 | 68 | root_hold/release 顺序 |

**证据 1：深嵌套循环里 `self`/`expr` 被截断成 `0`**

```c
/* xnullc xlex.xn.c:3806-3837 */
rt_string *xn_t862 = 0(0);
...
0.adv();
if (((!(0())))) {
    0 = 0;
```

**证据 2：返回 `scanString` 被落临时，Go 直接 return**

```c
/* xnullc xlex.xn.c:2090-2105 */
xn_Cls_Tok * xn_t633 = xn_Cls_Lexer_scanString(self, l, c, 0, 1, 0);
xn_root_add(xn_t633);
xn_root_add(xn_t633);
xn_root_add(xn_t633);
...
return xn_t633;

/* Go xlex.go.c:2289 */
return xn_Cls_Lexer_scanString(self, l, c, 0, 1, 0);
```

**证据 3：`matchOp` 的 52 项数组字面量整段消失**

```c
/* xnullc xlex.xn.c:2411-2419 */
xn_arr_s * ops = 0;
xn_root_add(ops);
...
rt_string *s = xn_arr_i_get(ops, i);
```

**判断：多机制。** 最大两块是 ArrayLit（matchOp/isKeyword）和返回物化（scanToken/next）；
`scanString` 的 197 行以 depth-limit 为主。

---

### 2.4 `tests/s6/xdk07/collections_basic.x`（content 947）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_main` | 67 | 71 | NameHijack + ListDisp + Lambda + OptDup + ARC 局部 release 缺失 |
| `xn_Cls_OrderedMap_i_valuesArray` | 14 | 22 | ArrayLit（`res = 0`）+ RetMat |
| `xn_Cls_PriorityQueue_i_pop` | 11 | 25 | GenericRet（V 未替换）+ OptDup + RetMat |
| `xn_Cls_OrderedMap_i_get` | 11 | 21 | GenericRet（`V?` → `int64_t`）+ RetMat |
| `xn_Cls_BTreeMap_i_get` | 11 | 21 | 同上 |
| （6）`xn_Cls_BTreeMap_i_keysArray` | 10 | 22 | LocalDecl 的 ArrayLit 分支误用于 Call 初值，`keysArray()` 调用被丢掉 |

**证据 1：用户类的 `put`/`push` 被方法名硬编码劫持**

```c
/* Go coll_basic.go.c:1564, 1600 */
xn_Cls_OrderedMap_i_put(om, 2, 20);
xn_Cls_PriorityQueue_i_push(pq, 3);

/* xnullc coll_basic.xn.c:1613, 1655 */
xn_map_s_i_put(om, xn_t2, 20);   /* key 还变成空串 */
xn_arr_i_push(pq, 3);            /* pq 是 xn_Cls_PriorityQueue_i* */
```

**证据 2：Lambda 实参丢失 + 返回数组调用被丢**

```c
/* Go coll_basic.go.c:1588, 1597 */
xn_arr_i * ks = xn_Cls_BTreeMap_i_keysArray(bt);
xn_Cls_PriorityQueue_i * pq = xn_Cls_PriorityQueue_i_new(xn_fn_lit_1);

/* xnullc coll_basic.xn.c:1648, 1652 */
xn_arr_i *xn_t7 = xn_arr_i_new(0);
xn_arr_i * ks = xn_t7;
xn_Cls_PriorityQueue_i * pq = xn_Cls_PriorityQueue_i_new(0);
```

**证据 3：Opt 返回值用作 `.has/.v` 时重复调用（会连续 pop 两次）**

```c
/* Go coll_basic.go.c:1606-1607 */
xn_opt_i xn_t4 = xn_Cls_PriorityQueue_i_pop(pq);
if (xn_t4.has) { xn_print_int(xn_t4.v); } else { xn_print_null(); }

/* xnullc coll_basic.xn.c:1669 */
if (xn_Cls_PriorityQueue_i_pop(pq).has) { xn_print_int(xn_Cls_PriorityQueue_i_pop(pq).v); } else { xn_print_null(); }
```

**判断：多独立机制（约 7 条），但全部围绕泛型用户类。** 不是 root/temp 编号问题；
其中 `put/push/less` 是语义错，`ks` 是调用被丢，不能只当文本 diff。

---

### 2.5 `tests/s6/xdk07/collections_nonnull.x`（content 925）

与 2.4 同构，`chg` 441；差异只在 `xn_main` 少 15 行（没有 `pop` 三连），以及
`OrderedMap.get` 不存在（用 `getOr`）。机制表同上。

**单条最小证据（`put` 劫持同样存在）**

```c
/* Go coll_nonnull.go.c:1561 */
xn_Cls_OrderedMap_i_put(om, 2, 20);
/* xnullc coll_nonnull.xn.c:1609-1611 */
rt_string *xn_t2 = rt_string_from_c("");
xn_map_s_i_put(om, xn_t2, 20);
```

**判断：与 coll_basic 同一组通用规则，修一处两边同时收敛；不要按文件分别修。**

---

### 2.6 `examples/parser-seed.x`（content 304）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_Cls_Parser_parsePrimary` | 31 | 105 | RetMat（5 处 `return mkXxx(...)`） |
| `xn_dump` | 24 | 184 | TempPolicy（`arr_o_Node_get()` 作实参被强行落临时） |
| `xn_Cls_Parser_curKind` | 12 | 92 | StrMethod（`toLower`）+ 求值顺序（`indexOf` 先实参后 receiver） |
| `xn_Cls_Parser_curText` | 10 | 160 | 同上 |
| `xn_Cls_Parser_parseUnary` | 9 | 69 | RetMat |
| （6）`xn_main` | 2 | 34 | ExprStrLit（`p.src = "1 + 2"` → `rt_retain(0)`） |

**证据 1：返回类对象落临时 + 4 次 root_add**

```c
/* xnullc parser_seed.xn.c:1176-1182 */
xn_Cls_Node * xn_t216 = xn_mkInt(xn_t215);
xn_root_add(xn_t216);
xn_root_add(xn_t216);
xn_root_add(xn_t216);
xn_root_add(xn_t216);
return xn_t216;

/* Go parser_seed.go.c:1186 */
return xn_mkInt(xn_t210);
```

**证据 2：String receiver/实参求值顺序相反**

```c
/* Go parser_seed.go.c:721-722 */
rt_string *xn_t145 = rt_string_from_c("0123456789");
rt_string *xn_t146 = rt_retain(c);
if (((xn_str_indexof(xn_t145, xn_t146) >= 0))) { ... }

/* xnullc parser_seed.xn.c:741-744 */
rt_string *xn_t153 = c.toLower();                 /* 先算实参, 且方法未 lower */
rt_string *xn_t154 = rt_string_from_c("abcdefghijklmnopqrstuvwxyz");
if (((xn_str_indexof(xn_t154, xn_t153) >= 0))) { ... }
```

**证据 3：String 字段赋值丢字面量**

```c
/* xnullc parser_seed.xn.c:2022 */
rt_string *xn_t121 = rt_retain(0);   /* Go: p->src = rt_retain(rt_string_from_c("1 + 2")) */
```

**判断：2–3 条通用规则，无文件特有机制。** 返回/实参物化 + String 方法/字面量通路；
K-06-01（`60b7cdc`）只修了局部求值顺序，没有把规则上移。

---

### 2.7 `difftest/anchors/cases/pkg/f2.x`（content 272）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_Cls_Response_header` | 7 | 17 | RetMat（`return map_get(...)` 落临时） |
| `xn_Cls_Request_new_init` | 5 | 21 | FieldOwn（Bytes 字段赋值缺 retain/release） |
| `xn_postAsync` | 5 | 9 | ResultReturn（普通 Call 未赋 `xn_ret`）+ ArgRetain |
| `xn_Cls_Socket_connect` | 4 | 50 | Shadow（参数 `host/port` 被解析成 `self->host/self->port`；raw 差主要是编号） |
| `xn_Cls_Socket_connectAsync` | 5 | 9 | ResultReturn + ArgRetain + Context root 差异 |
| （6）`xn_Cls_Response_body` | 5 | 9 | RetMat |

**证据 1：参数名与字段同名时，xnullc 优先解析成字段**

```c
/* Go f2.go.c:902 */
if (((!(xn_isValidAddress(xn_t61, xn_p_port))))) { ... }

/* xnullc f2.xn.c:902 */
if (((!(xn_isValidAddress(xn_t57, self->port))))) { ... }
```

**证据 2：Result 函数 `return self.connect(...)` 完全没有给 `xn_ret` 赋值**

```c
/* Go f2.go.c:956-960 */
rt_string *xn_t68 = rt_retain(xn_p_host);
xn_root_add(xn_t68);
xn_root_add(xn_t68);
xn_ret = xn_Cls_Socket_connect(self, xn_t68, xn_p_port);

/* xnullc f2.xn.c:951-959 */
size_t xn_t63 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_context);
xn_root_add(xn_p_host);
#line 85 ...
    {
xn_root_restore(xn_t63);
    }
return xn_ret;      /* 未初始化 */
```

**证据 3：Bytes 字段赋值缺 retain/release，deinit 也漏 release**

```c
/* Go f2.go.c:1296-1300, 1333 */
xrt_bytes_obj *xn_t90 = rt_retain(xn_p_body);
xn_root_add(xn_t90);
rt_release(o->body);
o->body = xn_t90;
...
rt_release(o->body);

/* xnullc f2.xn.c:1324 */
o->body = xn_p_body;
```

**判断：多独立机制，集中在类/async 语义。** ResultReturn 是正确性 bug，优先修；
Shadow 和 FieldOwn 是通用的名字解析/字段所有权规则，不应只改 net.x。

---

### 2.8 `tests/b3/fixtures/bundle/app.x`（content 97）

| 函数 | chg | raw | 机制 |
|---|---:|---:|---|
| `xn_arr_u16_insert` | 13 | 13 | 整个 helper 只在 Go 侧 |
| `xn_arr_u16_join` | 10 | 10 | 同上 |
| `xn_arr_u16_remove` | 9 | 9 | 同上 |
| `xn_arr_u16_deinit` | 9 | 9 | 同上 |
| `xn_arr_u16_push` | 8 | 8 | 同上 |
| （prelude） | 13 | 13 | 缺 `xn_arr_i` typedef；`xn_arr_u16` typedef 有、helper 无 |

**证据：同一翻译单元两个 List 元素类型时，typedef 与 helper 各取了一半**

```c
/* Go bundle_app.go.c:398-400 */
typedef struct { ... int64_t *data; } xn_arr_i;
typedef struct { ... uint16_t *data; } xn_arr_u16;
/* Go bundle_app.go.c:499 */
static void xn_arr_u16_deinit(void *p) { ... }

/* xnullc bundle_app.xn.c:398 */
typedef struct { ... uint16_t *data; } xn_arr_u16;   /* 只有 u16 typedef */
/* xnullc 只有 xn_arr_i_* helper（见 420-495），没有 u16 helper */
```

**判断：单一通用规则。** `cbKey` 只能表达一个容器类型；typedef 来自
`containerTypedef(cbKey)`/`C_ARR`，helper 来自另一个选择。需要按 `C_ARR` 全量生成
每个元素类型的一套 typedef + helper。

---

## A. 全局聚类表（机制 × 文件数 × content 行合计 × 代表函数）

> `content 行合计` 是多标签求和：同一文件命中多条机制会重复计入，因此不可横向相加。
> `可归因 chg` 是本批 8 文件里能明确落到该机制的归一化 `+/-` 行数（估算，depth 与
> 物化有重叠时按函数首因归属）。

| # | 机制 | 文件数 | content 行合计（多标签） | 可归因 chg | 代表函数 |
|---|---|---:|---:|---:|---|
| M1 | 表达式物化策略：return / 实参 / 成员接收者 / Opt-Result 绑定 | 7 | 12779 | ≈1800 | `Parser.parsePrimary`、`Lexer.scanToken`、`Parser.dump`、`Response_header`、`PriorityQueue.pop` |
| M2 | 通用 `List<T>` 代码生成：ArrayLit + 按元素类型分派 helper | 5 | 12203 | ≈1000 | `Parser.parseTypeDecl`、`Lexer.matchOp`、`Fmt.new_init`、`Fmt.sortImports`、`coll main` |
| M3 | AST depth-limit 截断（输入门禁，不是 xnullc 规则） | 3 | 10331 | ≈2750 | `Parser.parseTypeDecl/parseTop`、`Lexer.scanString`、`Fmt.keywordNoEnd/matchOp` |
| M4 | ExprStmt 按方法名硬编码 `push/put/clear/set` | 2 | 1872 | 52 | `coll main`、`BTreeMap.put` |
| M5 | String 成员方法表不全 + `indexOf` 求值顺序 | 2 | 2142 | ≈110 | `Fmt.format`、`Parser.curKind/curText` |
| M6 | Lambda / 函数指针字段调用 | 2 | 1872 | ≈14 | `coll main`（`PriorityQueue` 构造器、`self->less`） |
| M7 | 泛型类类型参数替换只认 `T`（`V`/其它名未替换） | 2 | 1872 | ≈27 | `OrderedMap.get`、`BTreeMap.get`、`valuesArray/keysArray` |
| M8 | `expr()` 无 StrLitExpr 分支，调用点未走 `emitStr` | 3 | 8852 | ≈15 | `Fmt.format`（`self.pkg=""`）、`parser-seed main`、`Parser.parseTop`（`m.vis="public"`） |
| M9 | 类字段所有权：Bytes/对象字段 retain/release + deinit | 1 | 272 | 12 | `Request_new_init`、`Response_new_init/deinit` |
| M10 | 参数/局部与字段同名时的名字解析顺序 | 1 | 272 | 8 | `Socket.connect/bind`、`Listener.bind` |
| M11 | LocalDecl root 钩子双写/漏写；方法 self/参数 root 条件 | 7 | 12779 | ≈130 | `coll main`、`Parser.parseTypeDecl`、`Fmt.markUnary` |
| M12 | Bool/Int 字段 C 类型（Go 用 `int64_t` + cast） | 2 | 2110 | 52 | `Tok.gen/ternary/unary/postfix`、`Socket._closed` |
| M13 | `main(String[] args)` 入口未发 argv | 2 | 8493 | 12 | `xparser main`、`xlex main` |
| M14 | 容器 typedef/helper 双注册表（多元素类型） | 1 | 97 | 81 | `bundle_app` 的 `xn_arr_i` / `xn_arr_u16` |
| M15 | FFI 出参/返回值所有权（`rt_release`、out 参数 cast） | 1 | 1838 | ≈60 | `xnfmt.main` 的 `readFileText/writeFileText/pathExists` |
| M16 | C 关键字标识符未 mangle | 1 | 6710 | 4 | `Parser.parseTop` 的 `int void = 0;` |
| M17 | 表达式括号/cast 形式（逻辑括号、`(int64_t)((int)(0))`） | 4 | ≈9000 | ≈40 | `Lexer.scanString`、`Fmt.markUnary`、`f2.isValidAddress` |

**按 content 覆盖排序：M1（12779）> M2（12203）> M3（10331）> M8（8852）> M13（8493）> M12（2110）> M5（2142）> M4/M6/M7（1872）。**

**按可归因 chg 排序（扣掉 depth 后）：M1（1800）> M2（1000）> M11（130）> M5（110）> M14（81）> M15（60）> M4（52）> M12（52）。**

---

## B. 修一条规则覆盖最多的前 3 名

### B.1 第一名：表达式物化策略统一（M1，7 文件，≈1800 chg）

**不是“root 次数”问题，而是“该不该落临时”的策略不一致。** 三类站点：

1. **return 普通 Call 被强行落临时**（xparser/xlex/parser_seed/coll/f2）：
   `xnullc.x:2635-2640` 的 ReturnStmt 兜底无条件
   `cType + t = expr(v); return t;`。Go 对 `return f(...)` 直接 `return f(...);`。
   修法：`v.nm == "Call"`（且不是 Ok/Err/需要 retain 的特殊类型）时直接
   `sc.ret = expr(v)`；只有需要类型转换/元组/Opt literal 时才落临时。
2. **Result 函数 `return f(...)` 没赋 `xn_ret`**（f2 全部 async）：
   `xnullc.x:2567` 的 `if v.nm != "Call" ... e.add("xn_ret = ...")` 把普通 Call 排除了。
   修法：`v.nm == "Call"` 且不是 Ok/Err 时 `e.add("xn_ret = " + expr(v) + ";")`。
3. **成员访问的接收者该落临时但没落**（parseStmt/isTypeStart）：
   `expr` 的 Member 分支（`xnullc.x:1412-1444`）直接 `expr(mx)+"->"`；当 `mx` 是
   Call/Index 且返回 GC 类时，Go 会先落临时并 root_add。修法：Member 的 `X` 为
   Call/Index 且 `exprType(X)` 是 GC 类型时，`e.nt()` 落临时 + `rootStr`，再取字段。
4. **对象数组 `get` 被无条件落临时**（markUnary/dump 多出的 5 行）：
   `xnullc.x:1567-1582` 的 `mn == "get"` + `isObjArr` 分支无条件建临时。Go 只有在
   需要稳定接收者/实参所有权时才落。修法：直接返回 `arr_o_get(...)`，把“需要落临时”
   的条件上移到父节点（Member/Index/调用实参的所有权判断）。
5. **Opt/Result 返回值作 `.has/.v` 时重复求值**（coll main）：
   `expr` 对 `Member` 的 `.has/.v` 直接内联两次 Call；Go 在 `emitExpr` 里对
   `Opt/Result` 接收者先落 `xn_opt_i t = call();` 再读。修法：`Member` 的 X 是
   Call 且 `exprType(X)` 为 `Opt/Result`/元组时，落临时并复用。

**验收点**：`f2` 的 `connectAsync/readAsync/writeAsync/bindAsync` 必须出现
`xn_ret = ...;`；`Parser.parsePrimary`/`Lexer.scanToken` 的 `return xn_tN` 变
`return f(...)`；`PriorityQueue.pop` 不再调用两次。

### B.2 第二名：通用 `List<T>` 代码生成（M2，5 文件，≈1000 chg）

一条规则要同时覆盖四个入口，缺一不可：

1. **类型判定**：`isArr`（`xnullc.x:491`）目前只认 `List<Int>`/`Int[]`。扩为
   “所有 `List<T>`（除 U16/obj/tuple 专用）”；`cType`（`:464-466`）的硬编码
   `List<Int>` 提前返回要移到通用分支之后，保证 `List<String>`、`List<Tok>` 走
   `arrNameC(elem)`。
2. **局部声明 ArrayLit**：`xnullc.x:2206-2218` 的 `isArr` 分支改为按
   `arrNameC(cType(elem))` 生成 `_new(n)` + 对应 `_push`；并**先判断 `init.nm ==
   "ArrayLit"`**，否则 `List<Int> ks = bt.keysArray()` 会被当成空数组（coll
   `keysArray` 被丢的直接原因）。
3. **字段初始化**：`xnullc.x:3267-3275` 的 `isArr(ft) || isObjArr(ft)` 覆盖
   `List<String>` 字段；当前 `Fmt.lines/header/imports` 全变 `0`。
4. **方法分派**：`expr` 的 `get`（`:1567`）、`length`（`:1563`）、`ExprStmt` 的
   `push/clear/set`（`:2461-2494`）、`Index` 赋值（`:2414`）都要按 `List<T>` 元素类型
   选 helper；`insert/remove` 目前完全没有表达式路径（`BTreeMap.put` 的
   `self->keys.insert` 会原样漏出）。
5. **`ExprStmt` 去方法名硬编码**：`push/put/clear/set` 四个分支必须先判断
   `exprType(mx)` 是内建容器；否则交回普通 Call（`xn_Cls_*_put/push`）。这一条同时
   修 M4 的 coll 语义错。

**验收点**：`coll_basic` 的 `om.put(2,20)` 变 `xn_Cls_OrderedMap_i_put(om,2,20)`，
`pq.push(3)` 变 `xn_Cls_PriorityQueue_i_push(pq,3)`，`ks` 保留 `keysArray()` 调用；
`Fmt.new_init` 的 `o->lines/header/imports` 变 `xn_arr_s_new(0)`；
`Parser.parseTypeDecl` 的 `tps` 变 `xn_arr_s_new(0)` + `xn_arr_s_push`。

### B.3 第三名：String 通路一条规则（M5+M8，3 文件，content 8852/2142）

1. **补 String 成员表**：`xnullc.x:1539-1562` 目前只有 `length/substring/indexOf/
   indexOfByte`。需要补 `replace`（Go `xn_str_replace`）、`trim`（`xn_str_trim`）、
   `startsWith/endsWith`（`xn_str_startswith/endswith`）、`toUpper/toLower`
   （`xn_str_upper/lower`）、`split`（`xn_str_split`）、`charAt`（已有类型但无发射）。
   不补就会漏出 `xn_p_src.replace(...)`/`lt.trim()` 这类非法 C。
2. **`indexOf` 求值顺序**：`xnullc.x:1556-1562` 先算 `a0 = emitStr(arg)` 再算
   `rb = expr(mx)`；Go 先 receiver 后实参。改成先 `rb` 再 `a0`（parser-seed
   curKind/curText 的先后差异）。
3. **StrLitExpr 进 `expr` 必须走 `emitStr`**：`expr` 末尾 `:1661` 的 `return "0"`
   兜底前加 `if x.nm == "StrLitExpr" { return emitStr(x,e,sc) }`；同时修
   `AssignStmt` 的 Member String 分支（`:2435-2441` 用 `v0` 而不是 `emitStr(val0)`），
   以及所有 `expr(StrLit)` 调用点（`m.vis="public"`、`self.pkg=""`、`p.src="1+2"`）。
   否则 `rt_retain(0)` / `rt_string_from_c("")` 会继续污染 map key、字段初值。

**验收点**：`Fmt.format` 不再出现 `.replace/.trim`，`self.pkg` 恢复
`rt_string_from_c("")`；`parser-seed curKind/curText` 的 receiver/实参顺序与 Go 一致；
`p.src` 恢复字面量。

---

## C. E2 建议顺序（先修什么 / 预计下降）

> 顺序按“先消除不可修幻影 → 再修一条通用规则拿最大面积 → 再修语义正确性”。
> 预计值是相对当前 `content` 的估算（用本文件 `content/chg` 比折算），不是承诺；
> 每步都必须跑全量 shard 聚合，不看单文件。

| 步 | 规则 / 首个验收函数 | 触及文件 | 预计 content 下降 |
|---|---|---|---:|
| P0 | **depth-limit 门禁**：`tests/b3/xnullc_all.py` 在 `xnast --ast` 结果含 `(depth-limit)` 时标 `K07-LIMIT`/`FRONTEND-FALLBACK`，不计 DIFF；或把 `xfront` dump 深度提到 ≥96 并验证反序列化 | xparser/xlex/xnfmt | 重分类 ≈5000（不是真实 codegen 收益） |
| P1 | **通用 List<T> + ExprStmt 去方法名硬编码**；验收 `coll_basic.xn_main`、`Fmt.new_init`、`Parser.parseTypeDecl`、`Lexer.matchOp` | coll_basic/coll_nonnull/xnfmt/xparser/xlex | coll 947→≈500、925→≈480；xparser −900；xlex −400；xnfmt −200 |
| P2 | **返回/物化策略统一**（含 Result 普通 Call 赋值）；验收 `f2.connectAsync/postAsync`、`Parser.parsePrimary`、`Lexer.scanToken`、`parser-seed parsePrimary/dump` | f2/xparser/xlex/parser_seed/coll | f2 272→≈120；xparser −600；xlex −300；parser_seed 304→≈150；coll −80 each |
| P3 | **泛型类三连**：Lambda/函数指针字段、`V` 参数替换、Opt `.has/.v` 绑定；验收 `coll main`/`BTreeMap.get`/`PriorityQueue.siftDown` | coll_basic/coll_nonnull | coll 再 −200 each（→≈250–280） |
| P4 | **String 通路**（方法表 + indexOf 顺序 + StrLit 走 emitStr）；验收 `Fmt.format`、`parser-seed curKind/curText/main` | xnfmt/parser_seed/xparser | xnfmt −250；parser_seed −60；xparser −50 |
| P5 | **f2 字段/遮蔽**：参数名优先于字段、Bytes 字段 retain/release + deinit、Bool 字段 `int64_t` | f2 | f2 ≈120→≈40 |
| P6 | **容器双注册表**：按 `C_ARR` 全量生成 typedef + helper；验收 `bundle_app` | bundle_app | 97→0 |
| P7 | **root 钩子收尾**：LocalDecl 统一出口、方法 self/参数 root 条件 | 全部 | 残余 −100~200 |

**为什么 P0 必须在最前**：xparser/xlex/xnfmt 的 diff 里有 `0(0)`、`0.adv()`、
`0 + 0` 这类输入截断产物。E2 若先按 K-06 修 root/temp，会把 xnullc 规则往错误方向
拽；这三个文件在门禁修正前不应作为 K-06 的“下降指标”。

**为什么 P1 先验收 coll 而不是 xparser**：coll 的失败是确定性的（`put/push/keysArray`
/signature），一条 List<T> 规则的对错立刻可见；xparser 混着 depth 和物化，反馈信号差。

**不要按文件硬编码**：P1/P2/P4 的修改点都在 `isArr/cType/LocalDecl/expr/ExprStmt/
ReturnStmt` 共享分支；coll/f2/bundle 只用于验收，禁止加 `if path==...` 或类名白名单。

---

## D. 与已完成 C.1–C.9 规则的关系

### D.1 已成立、不要重做的部分

- **C.3/C.4 作用域链 + 块尾/return 清理**：8 个文件的 `xn_root_restore` 总数与
  `while(1)` 数已一致（实测：xparser 1637/19、xlex 487/2、xnfmt 325/1、coll 87/1、
  parser-seed 108/1、f2 68/0、bundle 227/1，Go 与 xnullc 同值）。说明 C.3–C.6 的
  骨架在这些文件生效，剩余差异不是“少一层 restore”或“while 没降级”。
- **C.5 break/continue**、**C.6 switch/for 顺序**：本批 8 文件没有出现
  break/continue restore 或 case 求值顺序的独立 hunk。
- **C.7 入口收口**：函数/方法入口的 `size_t mark = xn_root_mark();` 与
  `xn_root_restore(mark)` 已对齐；剩余 root 差异在“哪些值该 root”，不在“帧有没有建”。

### D.2 遗留特判（C.1–C.9 没覆盖的旧分支）

1. `isArr` 只认 `List<Int>`/`Int[]`（`:491`）+ `cType` 硬编码提前返回（`:464-466`）。
2. `ExprStmt` 按方法名直接发容器 helper（`:2461-2494`），劫持用户类 `put/push/set/clear`。
3. LocalDecl 每个类型分支各自调 `finishLocalRoot`（`:2126、:2132、:2167、:2178、
   :2191、:2203、:2214、:2228、:2245、:2251、:2306、:2323、:2334、:2342、:2347`），
   与 C.2 的 `rootTempDecls` 双写；`List<String>` 分支反而没有钩子（parseTypeDecl 的
   `annos` 少 root）。
4. `expr` 缺 StrLitExpr/ArrayLit/Lambda 分支，末尾 `return "0"`（`:1661`）静默降级。
5. 类字段初始化/deinit 手写只认 String/isArr/isObjArr（`:3168-3173`、`:3267-3275`），
   Bytes 字段直接漏。
6. `main(void)` 写死（`:5216`），`xn_main()` 不传 argv（`:5221`）。
7. 方法 self root 用 `ref`（classPolicy）而不是 Go 的 `isGCRootC`（`:3376`），
   coll 的方法多出 `xn_root_add(self)`。
8. 泛型实例替换硬编码 `SUB_FROM=["T"]`（`:4001、:4138、:5240`），`V`/其它参数名
   不替换（`BTreeMap_i_get` 返回 `int64_t` 而不是 `xn_opt_i`）。

### D.3 未泛化的新机制（C.1–C.9 设计里没有）

1. **通用 `List<T>` 一等公民**：ArrayLit + 元素类型分派 + 字段/局部/索引/方法全路径
   （M2）。C.1–C.9 只处理了“容器是 GC 根”，没处理“元素类型决定 helper”。
2. **表达式物化策略**（M1）：Go 的 `emitExpr` 在 return/实参/接收者三处有不同规则；
   xnullc 目前是“兜底一律落临时 + 某些分支一律落临时”，需要按站点对齐。
3. **String 成员完整表 + 求值顺序**（M5）：C.1–C.9 没有 String 方法表。
4. **Lambda / 函数指针字段**（M6）：需要新增 lambda 顶层函数发射（`xn_fn_lit_N`）
   和字段调用分派（`self->less(...)`）。
5. **泛型类型参数替换**（M7）：`substKey` 只做精确 `T` 匹配；需要按类声明的
   `TypePars` 逐个替换，并支持 `T?`/`List<T>`/`Map<K,V>` 复合键。
6. **Bytes/对象字段所有权与 deinit**（M9）：C.3 的 defer 只覆盖局部 String/容器；
   字段赋值和 deinit 是另一套手写逻辑。
7. **容器 typedef/helper 双注册表**（M14）：`cbKey` 单值无法表达同一 TU 多元素类型。
8. **AST depth-limit 门禁**（M3）：这是输入管线的新机制，不属于 K-06 codegen。

### D.4 与 K-06-01（`60b7cdc` parser-seed）的关系

`60b7cdc` 把 parser-seed 的局部求值顺序/临时号从 1319 降到 239，但没有把规则上移：
本次 parser-seed 仍有 304 content，`parsePrimary/parseUnary` 的返回物化、
`dump` 的实参物化、`curKind/curText` 的 String 方法/顺序都还在。它属于
“**遗留局部修法**”：可以保留其测试价值，但 E2 应按 B.1/B.3 的通用规则重做，
不要继续在 parser-seed 内部加分支。

---

## 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang
mkdir -p /tmp/b3-k06-after && cd /tmp/b3-k06-after
# Go C
/tmp/xnull-b3-base2 build --emit-c impl/lib/b2/xparser.x > xparser.go.c
# AST/bundle/projection
/tmp/xnast-b3-base2 --ast impl/lib/b2/xparser.x > xparser.ast.txt
/tmp/xnull-b3-base2 --emit-ast-bundle impl/lib/b2/xparser.x > xparser.bundle.json
python3 tests/b3/xfb-projection.py impl/lib/b2 > xparser.proj.txt
# xnullc C（大文件走 --ast-file/--bundle-file，避免 argv 超限）
/tmp/xnull-b3-base2 run --interp impl/lib/b3/xnullc.x -- \
  impl/lib/b2/xparser.x --ast-file xparser.ast.txt \
  --project "$(cat xparser.proj.txt)" --bundle-file xparser.bundle.json > xparser.xn.c
```

只读声明：本文件由 E4 分析会话生成，未修改 xnullc、Go oracle、测试或 fixtures；
所有结论以 `/tmp/b3-base2b/results.tsv` 与上述生成物为准。
