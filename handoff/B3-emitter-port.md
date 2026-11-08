# B3 emitter 作用域清理移植图（xnullc → Go oracle）

> 目标：让 `wt/e2-sema/impl/lib/b3/xnullc.x` 的 defer / root_restore / 局部 release 子系统
> 变成 Go oracle `impl/internal/codegen/codegen.go` 的逐语句等价实现，使
> `tests/b3/fixtures/bundle_text/app.x` 的 C 输出与 Go 逐字节一致。
>
> 基线：
> - Go oracle：`main@d02b3d2`，本文行号取自当前工作区 `impl/internal/codegen/codegen.go` / `classes.go`。
> - xnullc：`wt/e2-sema@9313c48:impl/lib/b3/xnullc.x`（`git log` 最后一次改动，工作区干净）。
> - 差分现状：`/tmp/xnull-orc build --emit-c tests/b3/fixtures/bundle_text/app.x` 对
>   `xnullc` 解释执行产物为 **349 行 unified diff**（2026-11-09 复现）。
> - 逐函数剩余差异见 `wt/e4-codegen/handoff/B3-text-rest-diff.md`（91 行，其中 4 行是
>   `&&`/`||` 括号，见本文附录 E）。
>
> 本文只读分析，不改 xnullc、不改 Go oracle。E2 按 B/C 施工。

## 0. 一句话结论

xnullc 现在的根清理是 **一张函数级全局表 + 用缩进猜块**：
`sc.strLocals` / `sc.releases` 在函数尾统一释放，`sc.blockRoots` 在 return/break 时
从内到外全部恢复，`sc.blockDefers` 只在 if 分支被保存/恢复。Go 的模型是
**每块一个 scope，每块自己的 defers 队列，块尾自己消费；return 沿 parent 链消费；
break/continue 只恢复被跳出块，不执行 release**。必须整体换掉，不能补丁式插入
`rt_release`。

---

# A. Go 侧精确语义（可直接翻译）

## A.1 `scope` 字段（`codegen.go:1931-1963`）

`deferItem`（`:1931-1935`）：

| 字段 | 含义 |
|---|---|
| `errdefer bool` | 只有 return/try 的失败路径才执行 |
| `lines []string` | 已带相对缩进的 C 语句；用户 `defer` 行带 8 空格，局部 release / root_restore 行不带前导空格 |
| `name string` | 被 release 保护的引用名；仅用于“return 类调用表达式时先 retain 抵消” |

`scope`（`:1937-1963`）与本任务相关的字段：

| 字段 | 语义 |
|---|---|
| `parent *scope` | 父块；return/try 沿它向外执行 defer |
| `defers []deferItem` | **本块**注册的清理，LIFO；普通 defer、errdefer、局部 release、块根 restore 全在同一队列 |
| `blockHeld []string` | 本作用域持有的长期根（跨作用域赋值用 hold 登记），块退出释放 |
| `rootMark string` | 本块进入时的根栈标记变量名；空 = 本块不登记 |
| `rootDeclared bool` | 本块是否真的输出了 `size_t mark = xn_root_mark();`；break/return 只恢复已声明帧 |
| `rootPrelude []string` | 根帧建立后、块体前的登记语句（GC 参数 / self / 构造对象 o） |
| `kind string` | `"loop"` / `"switch"`；break/continue 的停止条件 |
| `returned bool` | 本块末句已经生成 return；**只影响本块** emitBlock 的块尾清理 |
| `hasResult bool` | 返回类型是 `xn_Result_*`；errdefer 的 `xn_ret.ok` 判定前提 |
| `retC string` | C 返回类型 |
| `locals map[string]string` | 名字 → C 类型（newChild 时复制） |
| `own map[string]bool` | 本块直接声明的变量（promoteRoot 找 owner 用） |
| `isCtor bool` | 构造器体（Go 当前实际未置 true，见 D.5） |
| `taskBody/lockBody` | 任务/Mutex 回调特殊返回通道；text.x 不涉及 |

`newChild` 不复制：`defers`、`blockHeld`、`rootMark`（重新分配）、`rootDeclared`、
`rootPrelude`、`kind`、`returned`。

## A.2 `newChild` 与临时号规则（`codegen.go:2003-2013`、`:2015-2027`）

```
newChild(parent):
    child.parent       = parent
    child.g            = parent.g
    child.retC         = parent.retC
    child.hasResult    = parent.hasResult
    child.params       = parent.params        // 共享
    child.locals       = copy(parent.locals)
    child.alias        = copy(parent.alias)
    child.own          = {}
    child.self         = parent.self
    child.staticRefs   = parent.staticRefs
    child.staticTypes  = parent.staticTypes
    child.superT       = parent.superT
    child.isCtor       = parent.isCtor
    child.rootMark     = g.nextTmp()          // ← 无条件占号
    // defers/blockHeld/rootPrelude/kind/returned 全为空/false
```

关键：

1. **每创建一个子块作用域就立刻分配一个 `xn_tN`，即使块内没有任何语句。**
   空 `if`、空 `while` 体也占号；漏占/多占会让整文件后续临时号全部平移。
2. `newChild` 的分配时机就是下列语句的执行时机，顺序不能变：
   - if：先求条件（条件里的临时已分配），再 `thenSc = newChild()`，再 `elseSc = newChild()`；
     `else-if` 的 `elseSc` 也占号，但**不声明**（见 A.7）。
   - while：先求条件；条件有前置语句时先产生前置临时，再 `bodySc = newChild()`。
   - for-in：先 `bodySc = newChild()` 并发射循环体，**之后**才 `idx = s.tmp()`（`:2555`、`:2568`）。
   - switch：先求值匹配值和**全部** case 表达式，再按源码顺序为每个 case/default `newChild()`。
   - try：**不创建新 scope**，不占 rootMark；只有 Result 临时。
3. 函数/方法/构造器入口的 rootMark 也在入口处 `nextTmp()`（`codegen.go:1897`、
   `classes.go:940`、`:732`），随后 emitBlock 输出声明。

## A.3 `emitBlock`（`codegen.go:2084-2122`）

Go 原始形态（相对缩进）：

```
emitBlock(stmts):
    out = []
    if rootMark != "":
        rootDeclared = true
        out += "size_t <rootMark> = xn_root_mark();"
        out += rootPrelude            // 清空 rootPrelude
        defers += DF(lines=["xn_root_restore(<rootMark>);"])
    for st in stmts:
        out += lineDirective(st)      // #line 在语句前
        out += emitStmt(st)
    for v in blockHeld:               // 无条件，甚至在 return 之后
        out += "xn_root_release(<v>);"
    if !returned:
        for d in reverse(defers):
            if d.errdefer: continue   // 块正常落出不触发 errdefer
            out += "    {"
            out += reindent(d.lines, "    ")
            out += "    }"
```

最终输出（xnullc 直接按绝对缩进发射时用这个口径）。设本块语句基准缩进为 `I`：

| 内容 | 缩进 |
|---|---:|
| `size_t <mark> = xn_root_mark();` | `I` |
| `rootPrelude` 每行 | `I` |
| 块内语句 | `I` |
| `blockHeld` 的 `xn_root_release(v);` | `I` |
| defer 的 `{` / `}` | `I + 4` |
| `DF.lines` 行（局部 release / root_restore，0 前缀） | `I + 4` |
| `DF.lines` 行（用户 defer，已带 8 空格前缀） | `I + 12` |

即：**block 退出时 brace 比语句深 4；局部 release / root_restore 与 brace 同缩进；
用户 defer 体比 brace 深 8。** 这不是排版偏好，是 Go 文本逐字节要求（实测见
`clean_block_defer.x`：`            {` 后跟 `                    rt_string *xn_t5 ...`）。

顺序硬约束：

1. 根 restore 是在**块进入时** append 到 defers 的第一个元素；所以块尾 LIFO 时
   它一定**最后**执行（局部 release / 用户 defer 先执行）。
2. `blockHeld` 在所有 defers **之前**输出，且不受 `returned` 影响（return 之后
   的 `xn_root_release` 是不可达文本，但必须存在）。
3. `returned == true` 时整个 defer 段跳过；但 root restore 已经在 return 路径的
   `emitCleanup` 里执行过。
4. 空块：mark 行 + root restore 块照发。

## A.4 `emitCleanup`（`codegen.go:2032-2053`）

```
emitCleanup(s, condErr, indent):
    for sc = s; sc != nil; sc = sc.parent:
        for d in reverse(sc.defers):
            if d.errdefer:
                if !s.hasResult || !condErr: continue
                out += indent + "if (!xn_ret.ok) {"
                out += d.lines
                out += indent + "}"
            else:
                out += indent + "{"
                out += d.lines
                out += indent + "}"
```

要点：

- 从**当前块**一路到函数根，每层内部 LIFO；先子块后父块。
- `errdefer` 用**起始 scope 的 `hasResult`** 判断（祖先继承同一函数返回值类型）。
- 普通块退出调用时 `condErr=false`，errdefer 全部跳过；return/try 调用 `condErr=true`。
- `emitReturnInner` 传 `indent="    "`；调用方再把整段 return 语句缩进到当前块。
  设 return 所在块语句缩进为 `I`，则 cleanup 的 `{`/`if` 在 `I+4`，`d.lines` 的最终缩进为
  **`I + 行首空格`**（局部 release/root_restore 0 → `I`，比 brace 少 4；用户 defer 8 → `I+8`，
  比 brace 多 4）。原因：Go 的 emitCleanup 不对 d.lines 做 `reindent`，brace 的 4 空格是
  `indent` 参数，而 d.lines 保留注册时的前缀。
- `try` 传 `indent=""`，随后 `reindent(..., "        ")`；最终 `{` 在 `I+8`，
  行在 `I+8+行首空格`（见 A.10）。
- **cleanup 不输出 blockHeld release**。blockHeld 只在 emitBlock 块尾输出。

## A.5 `emitRootRestores`（`codegen.go:2064-2081`）

```
emitRootRestores(s, kind):        // kind = "break" | "continue"
    out = []
    for sc = s; sc != nil; sc = sc.parent:
        if sc.rootMark != "" && sc.rootDeclared:
            out += "xn_root_restore(<sc.rootMark>);"
        if kind == "continue":
            if sc.kind == "loop": break
            continue
        else: // break
            if sc.kind != "": break      // loop 或 switch 都停
    return out
```

- 只输出**裸 restore**，不输出 release，不输出 `{}`。
- `break` 停在最近的 `loop` 或 `switch`（含该层，先 restore 再停）。
- `continue` 停在最近的 `loop`（含该层）；遇到 switch 只 restore 它的 case 帧后继续向外。
- 只恢复 `rootDeclared==true` 的帧；`else-if` 那种“占号但未声明”的 scope 不恢复。
- 输出行缩进 = break/continue 语句所在块的语句缩进 `I`。

## A.6 局部声明的 release 注册（`emitLocalDecl`，`codegen.go:2729-3087`）

注册到**声明所在的当前 scope**（不是函数 scope，不是全局表），在声明时立即 append：

| 类型 | 注册点 | 内容 |
|---|---|---|
| `String` | `:3060` | `rt_release(name);` |
| `Bytes` | `:2877` | `rt_release(name);` |
| 协议 `xn_proto_*` | `:2819` | `rt_release((void *)name);` |
| 类（非 GC / ARC） | `:2951`、`:2957`、`:2966`、`:2977`、`:2989`、`:2779` | `rt_release(name);` |
| `handle` | `:2868` | `rt_release(name);` |
| Task/Context 句柄（拥有型初值） | `:2921` | `rt_release(name);` |
| Text / StringBuilder / 容器 / GC 类 / Any | 不注册 | 由 root_restore 管 |
| 局部 GC 根登记 | `emitStmtInner:2145-2153` | 声明后 `xn_root_add(name);` + `xn_gc_safepoint();`（deinit 内不 safepoint） |

append 顺序 = 源码声明顺序。块进入时 root restore 已在队列底；之后每条声明 append。
块尾 LIFO 得到：**后声明的先 release，最后 root_restore**。

`deferItem.name`（Go）：类/协议/handle/bytes 等 release 注册时带变量名，供“返回类调用
表达式”时先 `rt_retain` 抵消本层 release（`codegen.go:3824-3828`）；String 普通声明
（`:3060`）不带 name。xnullc 的 `addNamedRelease` 对应此字段。

例：`String ch` 在 while 体内声明，release 属于 while-body scope：
- 正常落出：`{ rt_release(ch); }` 然后 `{ xn_root_restore(whileMark); }`。
- 体内 return：先内层 if 的 restore，再 `{ rt_release(ch); }`，再 while 的 restore。
- 循环外函数尾**不得**再重放 `rt_release(ch)`。

## A.7 if / while / for / switch 的子 scope 与拼接

### A.7.1 `emitIf`（`codegen.go:3983-4018`）

```
cond = cond(n.Cond)                  // 条件临时分配在此
thenSc = s.newChild()                // 占号
thenBody = thenSc.emitBlock(n.Then.Stmts)
out = "if (<cond>) {" + reindent(thenBody, "    ") + "}"
if n.Else != nil:
    out += " else {"
    if n.Else is Block:
        elseSc = s.newChild(); elseBody = elseSc.emitBlock(...)
        out += reindent(elseBody,"    ")
    else:
        elseSc = s.newChild()        // 占号，但不 emitBlock → rootDeclared=false
        out += reindent(elseSc.emitStmt(n.Else), "    ")
    out += "}"
return indentAll(out)                // 整体再缩进 4
```

- 不要为整个 if 额外发 root restore；then/else 各自的 emitBlock 已经负责。
- `else-if` 的 `elseSc` **只占号不声明**；内层 if 自己再 `newChild()`。
- xnullc 直接发射时，else-if 的 `emitStmt` 仍沿用现有 `e.ind+8` 临时缩进设置
  （`xnullc.x:2482-2492`），只替换 scope/清理，不要改缩进公式。
- 父块 `returned` 不受子块影响。

### A.7.2 `emitWhile`（`codegen.go:2169-2206`）

普通形态：

```
cond = s.cond(n.Cond)
bodySc = s.newChild(); bodySc.kind = "loop"
body = bodySc.emitBlock(n.Body.Stmts)      // 内含 mark、块尾 release/restore
out = "while (<cond>) {" + reindent(body,"    ")
if !inDeinit: out += "    xn_gc_safepoint();"
out += "}"
```

条件降级形态（条件求值产生前置语句）：

```
pre = s.pending; s.pending = nil
bodySc = s.newChild(); bodySc.kind = "loop"
body = bodySc.emitBlock(...)
out = "while (1) {"
out += reindent(pre, "        ")
out += "        if (!(<cond>)) { break; }"
out += reindent(body, "        ")
if !inDeinit: out += "        xn_gc_safepoint();"
out += "}"
```

- mark 在 pre 和条件检查**之后**；pre 的 root_add 属于外层 statement 层，不在 body mark 之下。
- 循环体每轮 mark/restore；`continue` 回到 while 顶部重新求值。
- 旧 xnullc 的 `blockRoots.push`、手写 `xn_root_restore`、`loopDepth/loopIndent` 全部删除。

### A.7.3 `emitForIn`（`codegen.go:2541-2578`）

```
bodySc = s.newChild(); bodySc.kind = "loop"
bodySc.locals = copy(s.locals) + { n.Var: elemC }
body = bodySc.emitBlock(n.Body.Stmts)   // 先发射体
idx = s.tmp()                            // 再分配下标；顺序不可换
out = "for (size_t <idx> = 0; <idx> < <acc>->len; <idx>++) {"
out += "    <elemC> <n.Var> = <acc>->data[<idx>];"
out += reindent(body,"    ")
if !inDeinit: out += "    xn_gc_safepoint();"
out += "}"
```

xnullc 当前在 `:2590-2591` 先分配 `bodyRoot` 和 `loop`，再发射体，导致体临时号整体错位；
必须改成“先 newChild + emitBlock，后 e.nt() 分配下标”。

### A.7.4 `emitSwitch`（`codegen.go:2456-2538`）

```
vt = exprType(n.Value)
求值匹配值 valExpr（字符串临时/整型表达式）
for c in n.Cases: 求值 c.Expr 条件（所有 case 先算完，case 临时保留）
out = "do {"
for i,c in n.Cases:
    caseSc = s.newChild(); caseSc.kind = "switch"
    body = caseSc.emitBlock(c.Stmts)
    out += (i==0 ? "if" : "else if") + " (<cond_i>) {" + reindent(body) + "}"
if n.Default: defaultSc = s.newChild(); defaultSc.kind="switch"; emitBlock
out += "} while (0);"
释放 case 字符串临时 rt_release(...)   // 不是 root release
释放匹配值临时（字符串）
```

- 每个 case/default 都 newChild 占号并声明 mark，即使空 case。
- `break` 在 case 体内走 A.5，只恢复到该 case 帧（kind=switch）。
- case 条件临时在 do 块外，块尾不归 case scope 管。

## A.8 root_add 的两个来源（决定逐字节计数）

Go 的 root_add 不是表达式发射器逐点手写的，而是两层叠加：

1. **局部声明**：`emitStmtInner` 的 LocalDeclStmt 分支（`codegen.go:2145-2153`）在
   `emitLocalDecl` 返回后，对 `isGCRootC` 类型追加一行 `xn_root_add(name);`，再追加
   `xn_gc_safepoint();`（deinit 内不追加）。这一行是“显式 1 层”。
2. **`rootTempDecls` 后处理**（`codegen.go:5603-5641`）：
   - 在 `emitStmt`（`:2137`）对**整条语句输出**逐行扫描；
   - 在 `emitReturn`（`:3617`）又对 return 输出扫描一次（所以 return 表达式比普通语句多一层）；
   - 每遇到形如 `rt_string *x = ...;` / `xrt_bytes_obj *x = ...;` /
     `xrt_text *x = ...;` / `xrt_sb *x = ...;` / `xn_arr_* x = ...;` /
     `xn_set_*` / `xn_map_*` / `xn_Cls_*` 且含 `" = "` 的行，就在该行后追加
     `xn_root_add(x);`；
   - 若该行本身包含 `xn_root_add(` 或 `xn_root_hold(` 则跳过；
   - 临时名从 `"="` 左侧最后一个 token 取，去掉 `*` 和 `;`；带 `(` 的名字跳过。

**嵌套层数**：内层 `emitStmt` 先加一遍；外层语句（if/while/return）再各自扫描整段
文本加一遍，所以同一临时在深层会出现 0/8/12/12 多个 add。这不是 bug，不要 dedup。
xnullc 的 `doubleRoot`、`rootedTemps`、`extraTmpCount`、`regexMatchAt` 特判全部是
对这个机制的近似，必须删掉，改成同一个 `rootTempDecls` 后处理，并按语句缩进
`e.ind` 追加新行（见 B.2）。注意：外层 wrapper 必须扫描**包含内层块在内的整段
语句文本**，不能只扫描本层新增行，否则层数会少。

## A.9 函数/方法/构造器入口（`genFuncNamed` 1870-1927；`genMethod` classes.go:896-987；ctor classes.go:730-793）

```
sc = new root scope
sc.rootMark = g.nextTmp()
sc.rootPrelude = []
if 方法 self 是 GC 根: rootPrelude += "xn_root_add(self);"
if 构造器对象 o 是 GC 根: rootPrelude += "xn_root_add(o);"
for p in params:
    if param C 类型 isGCRootC: rootPrelude += "xn_root_add(xn_p_<p>);"
body = sc.emitBlock(fn.Body.Stmts)     // 在 body 开头输出 mark + prelude
// 不再在 body 之后追加 cleanup / release / root_restore
if hasResult && !sc.returned:
    xn_zero = {0}; xn_ret = xn_zero; return xn_ret;
```

**函数尾 fallback 差异（必须区分）**：

- 顶层函数 `genFuncNamed`（`:1919-1924`）：只有 `hasResult && !returned` 时补
  `{0}` 零值 + `return xn_ret;`；非 Result 函数**没有**任何 fallback return。
- 方法 `genMethod`（`classes.go:974-984`）：`hasResult && !returned` 同上；否则若
  `retC != "void" && !hasResult`，**无条件**补一行 fallback（即使所有路径已 return）：
  - opt/struct/tuple：`return (<retC>){0}; /* sema 保证不可达 */`
  - 其他：`return (<retC>)0; /* sema 保证不可达（函数体全路径 return） */`
  实测 `Regex.isMatch` 末尾有 `return (int)0; /* sema ... */`。
- 工厂方法走 `genFuncNamed`（`factory.go:122`），按顶层函数规则，无 fallback。
- 构造器 init 是 void，无 fallback。

- 方法的 self 只有在 GC 类时才 prelude；ARC 类 self 不 root。
- 构造器初始化函数返回 `void`；`o` 与 GC 参数 prelude，body 后无 tail restore（由
  emitBlock 块尾承担）。
- 顶层函数无 self；GC 参数按声明顺序 prelude。
- 旧 xnullc 在 emitFunc/方法/工厂/枚举/单例尾部手写的 `root_restore` + `releases` +
  `strLocals` + `return` 全部删除。

## A.10 return / try 的清理拼接

普通 return（`emitReturnInner` 开头即分派）：

```
emitReturn:
    lines = emitReturnInner
    return rootTempDecls(lines)       // 内层扫描
```

`emitReturnInner` 的每个分支在求值完返回表达式后、`return` 之前：

```
out += emitCleanup(s, true, "    ")   // 全部 scope，errdefer 看 xn_ret.ok
s.returned = true
out += "return <value>;"
```

- Result 返回：必须先 `xn_ret = <resultExpr>;`，再 cleanup，再 `return xn_ret;`
  （`codegen.go:3857-3868`）。Ok/Err/变量/调用同一纪律。
- String 标识符返回：先 `rt_retain(name);`，再 cleanup（会 release 本层引用），再 return。
- 类 new 返回：对象临时，cleanup 后 return；类调用返回时若有本层 defer 保护了
  表达式引用的对象，先按 `d.name` 补 `rt_retain`（`:3824-3828`）。
- 构造器：Go 实际 `isCtor` 未置 true，`return;` 走 `retC=="void"` 分支：
  `emitCleanup(true,"    ")` + `return;`（`codegen.go:3682-3689`）。不要生成
  `return o;` 或 `return xn_ret;`。
- **`s.returned` 只设当前 scope**；外层块仍会在自己的块尾输出清理（不可达文本，但
  必须输出）。

try 传播（`emitTryInto`，`codegen.go:3092-3194`）：

```
resultC tmp = call;
if (!tmp.ok) {
    xn_ret = tmp;                       // 或跨 Result 类型逐字段
    emitCleanup(s, true, "") 后整体再缩进 8
    return xn_ret;
}
// 不创建新 scope；不设 s.returned；后续语句和块尾清理照常输出
```

最终 try 的 cleanup `{` 在语句缩进 `I+8`，行在 `I+8+行首空格`（text.x 无 try，
但 `err/result_try.x` 必须保持）。

## A.11 实测缩进样张（必须逐字对齐）

`err/errdefer.x` 函数级 Ok return（`I=0`）：

```c
    if (!xn_ret.ok) {                 /* brace 4 */
        rt_string *xn_t3 = ...;       /* 8 */
xn_root_add(xn_t3);                   /* 0（外层 wrapper 层） */
xn_root_add(xn_t3);                   /* 0（return 内层 wrapper 层） */
        xn_root_add(xn_t3);           /* 8（defer 注册时的层 + 前缀） */
        xn_print_str(xn_t3);
        rt_release(xn_t3);
    }
    {
        rt_string *xn_t2 = ...;
xn_root_add(xn_t2);                   /* 0 */
xn_root_add(xn_t2);                   /* 0 */
        xn_root_add(xn_t2);           /* 8 */
        xn_print_str(xn_t2);
        rt_release(xn_t2);
    }
    {
xn_root_restore(xn_t1);               /* 0，比 brace 少 4 */
    }
```

`err/clean_block_defer.x` if 块正常落出（`I=8`）：

```c
            {                         /* 12 */
                    rt_string *xn_t5 = ...;   /* 20 */
xn_root_add(xn_t5);                   /* 0（外层 If 语句 wrapper） */
                    xn_root_add(xn_t5);       /* 20 */
                    xn_print_str(xn_t5);
                    rt_release(xn_t5);
            }                         /* 12 */
            {
            xn_root_restore(xn_t3);   /* 12，与 brace 同缩进 */
            }                         /* 12 */
```

两条记忆规则：
- **块尾**：brace `I+4`，局部/root_restore `I+4`，用户 defer `I+12`。
- **return**：brace `I+4`，局部/root_restore `I`，用户 defer `I+8`。
- **try**：brace `I+8`，局部/root_restore `I+8`，用户 defer `I+16`。

---

# B. xnullc 映射

## B.1 新增/修改的 SC 字段（XNull 语法）

```xnull
class DF {
    String text = ""              // 旧字段保留，迁移期兼容
    String temp = ""              // 旧字段保留，迁移期兼容
    Bool err = false
    String name = ""              // 保护的引用名（return 类调用 retain 抵消，Go :3824）
    List<String> lines = []       // 新：每行原样，用户 defer 行已带 8 空格
}

class SC {
    // —— 作用域链（新增）——
    SC parent
    Bool hasParent = false
    List<String> own = []         // 本块直接声明的名字（promoteRoot）
    String rootMark = ""
    Bool rootDeclared = false
    List<String> rootPrelude = []
    List<DF> defers = []          // 统一队列：defer/errdefer/release/root_restore
    List<String> blockHeld = []
    String kind = ""              // "loop" / "switch"
    Bool returned = false
    Bool hasResult = false
    Bool isCtor = false

    // —— 既有字段保留（函数级上下文）——
    List<String> names = []
    List<String> types = []
    List<String> params = []
    List<String> paramTypes = []
    List<String> escaped = []
    List<String> fnNames = []
    List<String> fnRets = []
    List<String> resultTypes = []
    String curFn = ""
    String ret = ""
    String selfName = "self"
    String curClass = ""
    Bool selfPtr = false
    Bool staticMeth = false
    String retKind = "Int"

    // def() 追加：names/types + own
    void def(String n, String t) {
        self.names.push(n); self.types.push(t); self.own.push(n)
    }
}
```

删除的旧字段（迁移完成后必须 grep 到 0）：

`errdefers`、`blockDefers`、`releases`、`blockRoots`、`blockInds`、`rootedTemps`、
`extraTmpName`、`extraTmpCount`、`doubleRoot`、`held`、`loopDepth`、`loopIndent`、
`inRet`；`EM.terminated` 也不再需要（用各 scope 的 `returned`）。

## B.2 新增函数签名与核心实现（XNull 语法）

```xnull
// —— 作用域创建 ——
static List<String> copyStrs(List<String> src) {
    List<String> out = []
    Int i = 0
    while i < src.length() { out.push(src.get(i)); i = i + 1 }
    return out
}

static SC newChild(SC parent, EM e) {
    SC s = new SC()
    s.parent = parent
    s.hasParent = true
    // 函数级上下文
    s.curFn = parent.curFn
    s.retKind = parent.retKind
    s.selfName = parent.selfName
    s.curClass = parent.curClass
    s.selfPtr = parent.selfPtr
    s.staticMeth = parent.staticMeth
    s.hasResult = parent.hasResult
    s.isCtor = parent.isCtor
    s.params = parent.params
    s.paramTypes = parent.paramTypes
    s.fnNames = parent.fnNames
    s.fnRets = parent.fnRets
    s.resultTypes = parent.resultTypes
    s.escaped = parent.escaped
    s.names = copyStrs(parent.names)
    s.types = copyStrs(parent.types)
    // 本块状态
    s.own = []
    s.defers = []
    s.blockHeld = []
    s.rootPrelude = []
    s.returned = false
    s.rootDeclared = false
    s.kind = ""
    s.rootMark = e.nt()          // 无条件占号
    return s
}

// —— defer 注册 ——
static void addDefer(SC s, List<String> lines, Bool err) {
    DF d = new DF()
    d.lines = lines
    d.err = err
    s.defers.push(d)
}

static void addRelease(SC s, String code) { addDefer(s, [code], false) }

// 需要参与 return 类调用 retain 抵消的 release（Go deferItem.name）
static void addNamedRelease(SC s, String name, String code) {
    DF d = new DF(); d.lines = [code]; d.err = false; d.name = name
    s.defers.push(d)
}

// —— 块尾 / return 共用：braceInd 与 lineInd 分开传 ——
// 块尾：braceInd = I+4，lineInd = I+4
// return：braceInd = I+4，lineInd = I     （Go 不对 d.lines 做 reindent）
// try：  braceInd = I+8，lineInd = I+8   （Go reindent 8 作用于 brace 和 d.lines）
static void emitDeferItem(DF d, EM e, Int braceInd, Int lineInd, Bool guarded) {
    if guarded { e.addAt(braceInd, "if (!xn_ret.ok) {") }
    else { e.addAt(braceInd, "{") }
    Int i = 0
    while i < d.lines.length() {
        e.addAt(lineInd, d.lines.get(i))  // d.lines 自带前缀（0 或 8）
        i = i + 1
    }
    e.addAt(braceInd, "}")
}

// —— 块尾，只消费本 scope 的 defers（跳过 errdefer）——
static void emitBlockExit(SC s, EM e, Int ind) {
    Int hi = 0
    while hi < s.blockHeld.length() {
        e.addAt(ind, "xn_root_release(" + s.blockHeld.get(hi) + ");")
        hi = hi + 1
    }
    if s.returned { return }
    Int i = s.defers.length() - 1
    while i >= 0 {
        DF d = s.defers.get(i)
        if !d.err { emitDeferItem(d, e, ind + 4, ind + 4, false) }
        i = i - 1
    }
}

// —— return / try：沿 parent 链（必须处理到根 scope）——
// return 调用：braceBase = e.ind+4, lineBase = e.ind
// try    调用：braceBase = e.ind+8, lineBase = e.ind+8
static void emitCleanup(SC s, EM e, Int braceBase, Int lineBase, Bool condErr) {
    SC sc = s
    Bool stop = false
    while !stop {
        Int i = sc.defers.length() - 1
        while i >= 0 {
            DF d = sc.defers.get(i)
            if d.err {
                if s.hasResult && condErr { emitDeferItem(d, e, braceBase, lineBase, true) }
            } else {
                emitDeferItem(d, e, braceBase, lineBase, false)
            }
            i = i - 1
        }
        if sc.hasParent { sc = sc.parent } else { stop = true }
    }
}

// —— break / continue ——
static List<String> rootRestoresOf(SC s, String kind) {
    List<String> out = []
    SC sc = s
    Bool stop = false
    while !stop {
        if sc.rootMark != "" && sc.rootDeclared {
            out.push("xn_root_restore(" + sc.rootMark + ");")
        }
        if kind == "continue" {
            if sc.kind == "loop" { stop = true }
        } else {
            if sc.kind != "" { stop = true }
        }
        if !stop {
            if sc.hasParent { sc = sc.parent } else { stop = true }
        }
    }
    return out
}

// —— 局部 GC 根类型判定（与 Go isGCRootC 对齐）——
static Bool isGCRootType(String ty) {
    if ty == "String" || ty == "Bytes" || ty == "Text" || ty == "StringBuilder" { return true }
    if ty == "Any" { return true }
    if isProtoType(ty) { return true }
    if isArr(ty) || isSet(ty) || isMap(ty) || isTupList(ty) || isU16List(ty) || isObjArr(ty) { return true }
    if isDataEnum(ty) { return true }
    if isClass(ty) { return classPolicy(ty) == "gc" }
    return false
}

// —— 局部声明出口统一钩子：Go emitStmtInner:2145-2153 ——
static void finishLocalRoot(SC sc, String nm, String ty, EM e) {
    if isGCRootType(ty) {
        e.addAt(e.ind, "xn_root_add(" + nm + ");")
        if sc.curFn != "deinit" { e.addAt(e.ind, "xn_gc_safepoint();") }
    }
}

// —— 表达式临时 root 后处理；start 为语句在 e.ls 的起点 ——
static void rootTempDecls(SC sc, EM e, Int start, Int ind) {
    List<String> res = []
    Int i = start
    while i < e.ls.length() {
        String ln = e.ls.get(i)
        res.push(ln)
        String t = ln.trim()
        Bool skip = t.indexOf("xn_root_add(") >= 0 || t.indexOf("xn_root_hold(") >= 0
        if !skip && t.indexOf(" = ") >= 0 && gcDeclLine(t) {
            String nm = declNameOf(t)
            if nm != "" && nm.indexOf("(") < 0 {
                res.push(sp(ind) + "xn_root_add(" + nm + ");")
            }
        }
        i = i + 1
    }
    while e.ls.length() > start { e.ls.remove(e.ls.length() - 1) }
    i = 0
    while i < res.length() { e.ls.push(res.get(i)); i = i + 1 }
}

// —— 跨作用域赋值（Go promoteRoot）——
static SC promoteOwner(SC s, String name) {
    SC owner = s
    while owner.hasParent && !inNames(owner.own, name) {
        owner = owner.parent
    }
    return owner
}

static List<String> promoteRoot(SC s, String name) {
    SC owner = promoteOwner(s, name)
    if owner == s { return [] }                 // 同作用域：调用方发 root_add
    if inNames(owner.blockHeld, name) { return ["xn_root_hold(" + name + ");"] }
    owner.blockHeld.push(name)
    return ["xn_root_hold(" + name + ");"]
}
```

`emitBlock` 的新签名与骨架：

```xnull
static void emitBlock(SC s, N blk, EM e, Int ind) {
    if blk.nm != "Block" { return }
    if s.rootMark != "" {
        s.rootDeclared = true
        e.addAt(ind, "size_t " + s.rootMark + " = xn_root_mark();")
        Int pi = 0
        while pi < s.rootPrelude.length() {
            e.addAt(ind, s.rootPrelude.get(pi)); pi = pi + 1
        }
        s.rootPrelude = []
        addDefer(s, ["xn_root_restore(" + s.rootMark + ");"], false)
    }
    N stmts = fld(blk, "Stmts")
    Int i = 0
    while i < stmts.el.length() {
        Int save = e.ind
        e.ind = ind
        emitStmt(s, stmts.el.get(i), e)
        e.ind = save
        i = i + 1
    }
    emitBlockExit(s, e, ind)
}
```

`emitStmt` 的新骨架（删除 regexMatchAt 特判）：

```xnull
static void emitStmt(SC s, N st, EM e) {
    Int start = e.ls.length()
    emitStmtInner(s, st, e)
    rootTempDecls(s, e, start, e.ind)
}
```

`emitStmtInner` 的 ReturnStmt 分支：在 `e.terminated=false` 的位置改成
`Int rStart = e.ls.length()`，生成完 `xn_ret = ...`/临时声明后：
`emitCleanup(s, e, e.ind + 4, e.ind, true)`；`s.returned = true`；追加 `return ...;`；
最后 `rootTempDecls(s, e, rStart, e.ind)`（形成 Go 的内外两层）。

`emitTryInto` 的 cleanup 调用改成 `emitCleanup(s, e, e.ind + 8, e.ind + 8, true)`，并删除手写
`xn_root_restore(sc.root)` 与 `emitEarlyRet`。

## B.3 126 处站点逐条动作

行号对应 `wt/e2-sema/evidence/B3-08c-25/root-emission-sites.md`（即
`xnullc@9313c48`）。动作定义：

- **删**：不再手写，由 `rootTempDecls` 或局部 GC 钩子统一补。
- **替**：改由 `defers` / `emitBlockExit` / `emitCleanup` / `rootRestoresOf` /
  `promoteRoot` 承载。
- **移**：逻辑保留，移到 rootPrelude / 新函数。
- **留**：不属于作用域清理的临时释放/字段赋值，原样保留。

### rootStr（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L1044 | 删 | 表达式临时 root_add 交给 `rootTempDecls` |
| L1045 | 删 | `doubleRoot` 特判一并删除 |

### argExpr（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L1051 | 删 | Call 参数临时 root_add 交给后处理 |
| L1052 | 删 | `regexMatchAt`/`inRet` 特判删除 |

### expr（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L1141 | 留 | `xn_box_str` 后释放源串，属表达式所有权 |
| L1374 | 删 | `get()` 返回对象临时 root_add 交给后处理 |

### emitPrint（4）

| 行 | 动作 | 说明 |
|---|---|---|
| L1593 | 删 | `extraRoots` 参数与循环一并删除 |
| L1595 | 留 | 打印后释放字符串临时 |
| L1612 | 留 | 枚举名临时释放 |
| L1620 | 留 | 数据枚举名临时释放 |

### emitDeferBody（9）

| 行 | 动作 | 说明 |
|---|---|---|
| L1641 | 删 | 消息临时 root_add 交给 defer 体语句的 `emitStmt` |
| L1642 | 删 | 同上 |
| L1643 | 删 | 同上 |
| L1645 | 留 | 消息临时释放，改由 `DF.lines` 携带 |
| L1648 | 删 | mode1 的 root_add |
| L1649 | 删 | 同上 |
| L1650 | 删 | 同上 |
| L1651 | 删 | 同上 |
| L1653 | 留 | mode1 的消息释放，改由 `DF.lines` 携带 |

整个 `emitDeferBody` 由 `emitDeferItem` + `DF.lines` 取代。

### emitBlockDefers（3）

| 行 | 动作 | 说明 |
|---|---|---|
| L1664 | 删 | root_add 交给 defer 体语句 |
| L1665 | 删 | 同上 |
| L1667 | 留 | 该 release 作为 `DF.lines` 的一项，由 `emitBlockExit` 输出 |

`emitBlockDefers` 函数删除。

### emitEarlyRet（3）

| 行 | 动作 | 说明 |
|---|---|---|
| L1691 | 删 | `emitCleanup` 沿 parent 链恢复，不再遍历 `blockRoots` |
| L1699 | 删 | 局部 release 由 defers 承载 |
| L1704 | 删 | 函数根 restore 由 defers 承载 |

`emitEarlyRet` 函数删除。

### emitStmt（4）

| 行 | 动作 | 说明 |
|---|---|---|
| L1758 | 替 | `isAdd` 识别保留，写进新 `rootTempDecls` |
| L1766 | 替 | 追加逻辑保留，去掉 `pendEc`/`extraCountOf` |
| L1772 | 替 | `xn_root_hold(` 跳过保留 |
| L1781 | 替 | 末尾追加保留，改为逐行扫描后立即追加，不延迟 |

整个 regexMatchAt 分支（L1745-1748）删除。

### emitStmtInner（71）

| 行 | 动作 | 说明 |
|---|---|---|
| L1809 | 替 | break/continue 改调 `rootRestoresOf(sc, kind)` |
| L1837 | 删 | try 的 `xn_root_restore(sc.root)`；`emitCleanup` 已含 |
| L1854 | 删 | Bytes 字面量中间临时 root_add |
| L1855 | 留 | `rt_release(bs)`（源串所有权） |
| L1857 | 删 | Bytes 局部 root_add；由局部钩子补一次 |
| L1858 | 删 | 同上 |
| L1900 | 删 | String 局部 root_add；局部钩子补 |
| L1901 | 删 | 同上 |
| L1902 | 删 | `regexMatchAt` 第三次 add 特判 |
| L1904 | 删 | String 局部 root_add |
| L1905 | 删 | 同上 |
| L1916 | 删 | U16 列表临时 root_add |
| L1920 | 删 | U16 列表局部 root_add |
| L1921 | 删 | 同上 |
| L1932 | 删 | 对象数组临时 root_add |
| L1936 | 删 | 对象数组局部 root_add |
| L1937 | 删 | 同上 |
| L1947 | 删 | 元组数组临时 root_add |
| L1951 | 删 | 元组数组局部 root_add |
| L1952 | 删 | 同上 |
| L1965 | 删 | Int 列表局部 root_add |
| L1966 | 删 | 同上 |
| L1975 | 删 | Set 中转数组 root_add |
| L1980 | 删 | Set 临时 root_add |
| L1983 | 删 | Set 局部 root_add |
| L1984 | 删 | 同上 |
| L1994 | 删 | Map 临时 root_add |
| L2003 | 删 | Map 局部 root_add |
| L2004 | 删 | 同上 |
| L2011 | 删 | Any 局部 root_add |
| L2067 | 删 | 协议局部 root_add |
| L2069 | 替 | `sc.releases.push` → `addNamedRelease(sc, nm, code)` |
| L2085 | 删 | 栈类局部 root_add |
| L2096 | 删 | GC 类局部 root_add |
| L2098 | 删 | GC 类第二次 root_add |
| L2100 | 替 | ARC 类 `releases.push` → `addNamedRelease(sc, nm, code)` |
| L2107 | 删 | 类借用局部 root_add |
| L2108 | 替 | ARC 类 `releases.push` → `addNamedRelease(sc, nm, code)` |
| L2112 | 删 | 类局部 root_add |
| L2113 | 替 | 删 root_add；`xn_gc_safepoint()` 移入局部 GC 钩子 |
| L2114 | 替 | ARC 类 `releases.push` → `addNamedRelease(sc, nm, code)` |
| L2156 | 留 | 协议字段赋值先释放旧值 |
| L2167 | 删 | 类字段赋值临时 root_add 交给后处理 |
| L2168 | 留 | 字段旧值释放 |
| L2192 | 替 | String 赋值改 `promoteRoot`：同作用域不 `xn_root_release`，改 `xn_root_add` |
| L2193 | 留 | 旧串引用释放 |
| L2195 | 替 | 跨作用域才 `xn_root_hold`，并记 owner.blockHeld |
| L2204 | 留 | 成员 String 赋值旧值释放 |
| L2307 | 删 | Err 消息临时 root_add ×2 |
| L2320 | 删 | Err 消息嵌套层 root_add |
| L2324 | 删 | Err 消息 root_add |
| L2325 | 删 | 同上 |
| L2343 | 删 | return 的 `blockRoots` 循环；`emitCleanup` 接管 |
| L2352 | 删 | class early return 的 `strLocals` 循环；defers 接管 |
| L2358 | 删 | return 的函数根 restore；`emitCleanup` 接管 |
| L2378 | 删 | `new` 参数 String 临时 root_add |
| L2379 | 删 | early 分支重复 add |
| L2390 | 删 | `new` 结果临时 root_add |
| L2391 | 删 | 同上 |
| L2392 | 删 | 同上 |
| L2394 | 删 | 非 early 分支重复 add |
| L2395 | 删 | 同上 |
| L2431 | 删 | String return 临时 root_add |
| L2432 | 删 | early 重复 add |
| L2475 | 替 | if-then 块尾 restore → `emitBlockExit(thenSc,...)` |
| L2514 | 替 | if-else 块尾 restore → `emitBlockExit(elseSc,...)` |
| L2558 | 替 | while 降级体块尾 → `emitBlockExit(bodySc,...)` |
| L2580 | 替 | while 普通体块尾 → `emitBlockExit(bodySc,...)` |
| L2604 | 替 | for 体块尾 → `emitBlockExit(bodySc,...)` |
| L2637 | 替 | switch case 块尾 → `emitBlockExit(caseSc,...)` |
| L2662 | 替 | switch default 块尾 → `emitBlockExit(defaultSc,...)` |

### emitFunc（5）

| 行 | 动作 | 说明 |
|---|---|---|
| L2897 | 移 | GC 参数 root_add 移入 `rootPrelude`，由 emitBlock 输出 |
| L2916 | 替 | `regexMatchAt` strLocals 逆序释放 → defers |
| L2924 | 替 | 普通 strLocals 顺序释放 → defers（且改为逆序） |
| L2930 | 替 | 函数根 restore → emitBlock 块尾 |
| L2936 | 删 | `held` 的 post-return release hack；用 blockHeld |

emitFunc 尾部的 `emitCleanup`、`releases` 循环、`strLocals` 循环、root restore、
`return` 全删；只保留 `if hasResult && !sc.returned` 的零值返回。
另：`:2933-2934` 的 `return sc.ret;` 是顶层函数无条件 fallback，必须删除
（Go `genFuncNamed` 对非 Result 函数无 fallback；方法 fallback 见 A.9）。

### emitClassSection（10）

| 行 | 动作 | 说明 |
|---|---|---|
| L3129 | 替 | 方法根 restore → emitBlock 块尾 |
| L3154 | 留 | 字段初值旧串释放 |
| L3178 | 移 | 构造对象 o 的 root_add → rootPrelude |
| L3187 | 移 | 构造器 GC 参数 root_add → rootPrelude |
| L3206 | 替 | 构造器根 restore → emitBlock 块尾 |
| L3262 | 移 | 方法 self root_add → rootPrelude |
| L3268 | 移 | 方法 GC 参数 root_add → rootPrelude |
| L3282 | 替 | 方法 strLocals 释放 → defers |
| L3287 | 替 | 方法根 restore → emitBlock 块尾 |
| L3293 | 删 | String 返回值的 post-return `xn_root_release` hack |

### emitStructMethods（1）

| 行 | 动作 | 说明 |
|---|---|---|
| L3401 | 替 | 结构体方法根 restore → emitBlock 块尾 |

### emitExtensionMethods（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L3443 | 移 | self root_add → rootPrelude（仅 GC 目标） |
| L3446 | 替 | 根 restore → emitBlock 块尾 |

### emitFactoryMethods（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L3490 | 移 | 参数 root_add → rootPrelude |
| L3495 | 替 | 根 restore → emitBlock 块尾 |

### emitDataEnum（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L3543 | 移 | 构造对象 o root_add → rootPrelude |
| L3559 | 替 | 根 restore → emitBlock 块尾 |

### emitDataEnumMethods（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L3604 | 移 | self root_add → rootPrelude |
| L3607 | 替 | 根 restore → emitBlock 块尾 |

### emitSingletonSection（2）

| 行 | 动作 | 说明 |
|---|---|---|
| L3701 | 移 | self root_add → rootPrelude（按 `classPolicy=="gc"` 判定，不用 `hasRefFields`） |
| L3704 | 替 | 根 restore → emitBlock 块尾 |

## B.4 旧路径删除清单（grep 必须为 0）

```
errdefers
blockDefers
.sc.releases
blockRoots
blockInds
rootedTemps
extraTmpName
extraTmpCount
doubleRoot
sc.held
loopDepth
loopIndent
inRet
terminated
String root
emitDeferBody
emitBlockDefers
emitEarlyRet
extraCountOf
bumpExtra
rootStr
```

`emitStmt` 的 `early` 参数、`emitStmtInner` 的 `early` 参数、`emitBlock` 的
`early` 参数全部删除；所有 return 自己发 cleanup，不再有 early/top-level 两套。
`argExpr` 保留函数本身（参数求值），但删除两处特判。

---

# C. 一次性迁移顺序

> 所有步骤在 `wt/e2-sema` 工作区完成。每步先 `go build`/解释执行 xnullc 自身，
> 再跑 fixture 对比。除注明“输出会变”的步骤外，其余 fixture 应逐字节不变。

## C.0 基线与命令

```bash
cd /Users/vjs/Desktop/XNull-Lang
(cd impl && go build -o /tmp/xnull-orc ./cmd/xnull && go build -o /tmp/xnast-orc ./cmd/xnast)

# Go C
/tmp/xnull-orc build --emit-c tests/b3/fixtures/bundle_text/app.x > /tmp/text.go.c

# xnullc C
/tmp/xnull-orc --emit-ast-bundle tests/b3/fixtures/bundle_text/app.x > /tmp/text.bundle.json
/tmp/xnull-orc run --interp \
  wt/e2-sema/impl/lib/b3/xnullc.x -- \
  tests/b3/fixtures/bundle_text/app.x \
  "$(/tmp/xnast-orc --ast tests/b3/fixtures/bundle_text/app.x)" \
  "$(python3 tests/b3/xfb-projection.py tests/b3/fixtures)" \
  "$(cat /tmp/text.bundle.json)" > /tmp/text.xn.c

diff -u /tmp/text.go.c /tmp/text.xn.c | wc -l    # 基线 349
```

基线保存：`cp /tmp/text.xn.c /tmp/text.xn.baseline.c`。

## C.1 步骤 1：只加新机制（零输出变化）

1. `SC` 加 B.1 字段；`DF` 加 `lines`。
2. 加 `copyStrs` / `newChild` / `addDefer` / `addRelease` / `emitDeferItem` /
   `emitBlockExit` / `emitCleanup2`（先命名 `emitCleanup2`）/ `rootRestoresOf` /
   `rootTempDecls` / `isGCRootType` / `promoteRoot`；暂不调用。
3. `inNames` 已存在（`:2700`），复用。

**预期不变**：全部 49 个 `tests/b3/fixtures/**/*.x` 源文件的 C 输出逐字节不变；
`diff /tmp/text.go.c /tmp/text.xn.c` 仍为 349。只允许编译产物多出未使用函数。

## C.2 步骤 2：引入 rootTempDecls（只改 root_add 行）

1. 在 `emitStmtInner` 的 LocalDeclStmt 出口加局部 GC 钩子（所有分支 return 前调用
   `finishLocalRoot(sc, nm, ty, e)`：`isGCRootType(ty)` 时 `xn_root_add(nm);` +
   非 deinit `xn_gc_safepoint();`）。
2. `emitStmt` 改调新 `rootTempDecls`；ReturnStmt 内部再加一次内层
   `rootTempDecls`（Go 的 `emitReturn` 层）。
3. 删除 `rootStr`、`argExpr` 两处特判、`emitPrint` 的 `extraRoots`、`emitStr` 内
   所有手写 root_add、`emitReturn` 内所有手写 root_add、局部声明分支内的
   B.3 标注“删”的 root_add。保留 B.3 标注“留”的 `rt_release`。
4. 删除 `doubleRoot`/`rootedTemps`/`extraTmpName`/`extraTmpCount`/`inRet` 及
   regexMatchAt 的 `emitStmt` 特判；`emitStmtInner` 里 `inRet` 的保存/置位/恢复
   （L2442-2445）一并删除。

**预期不变**：所有临时号、`#line`、函数签名、release/restore 行不变；
**只允许 root_add 行的数量/缩进变化**。验收点：
- `bundle_text` 的 `ch`、`xn_t138/t140/t143/t145/t148~t151/t157/t158/t161/t163/t165`
  层数变为 Go 的 0/8/12/12 等（见 B3-text-rest-diff §1.5）；
- `Regex.isMatch` 的 `t355~t358` 从 2 行变 1 行，`t360/t361` 从 0/8 变 0/8/8；
- `utf16ToUtf8` 的 `xn_t197` 从 2 行变 1 行；
- `bundle/app.x`、`err/result_try.x` 的 root_add 行数只减不增（若增加说明钩子重复）。

## C.3 步骤 3：建 scope 链 + 块尾消费点（输出会变，锁定块尾）

3a. 顶层函数与类方法/构造器入口改为 root scope（`emitFunc` 与
`emitClassSection` 的 method/ctor 段；`bundle_text` 含 Regex 方法，必须先换）：

```xnull
SC root = new SC()
root.rootMark = e.nt()
root.curFn = ...
root.retKind = ...
root.hasResult = isResult(retKind)
root.rootPrelude = [...]
emitBlock(root, body, e, 0)
```

**迁移期兼容**：暂时保留入口尾部旧的 `emitCleanup`/`releases`/`strLocals`/
root restore/`return`，并把 `root.root` 设为 `root.rootMark`（旧 `emitEarlyRet`
仍引用 `sc.root`）。`newChild` 迁移期把 `child.releases`/`child.strLocals` 指向
parent 的同一 List（共享），否则旧 early-return 路径看不到祖先 release。这些旧路径
在步骤 4 统一删除；步骤 3 结束只要求能编译、能跑通 `bundle_text`，不要求 diff 收敛。

3b. if/while/for/switch 全部改为 `newChild(parent, e)` + `bodySc.emitBlock(...)`；
块尾 restore 由 `emitBlockExit` 输出。else-if 只 `newChild` 不 `emitBlock`。

3c. 局部 release 注册改为 `addRelease(sc, code)`（类/协议/handle/bytes 等需要
return retain 抵消的用 `addNamedRelease(sc, name, code)`）；同时**双写**旧的
`sc.releases`/`sc.strLocals`（迁移期兼容旧 return 路径），步骤 4 再删旧列表。
`sc.releases.push` 与 `sc.strLocals.push` 直接替换为“addRelease/addNamedRelease +
旧列表 push”。

**预期会变**（步骤 3 + 4 完成后；只允许这些函数/位置变）：

| fixture / 函数 | 预期新增/删除 |
|---|---|
| `bundle_text` `parseFloat` | while 体正常落出新增 `{ rt_release(ch); }`；函数尾删除重复 `rt_release(ch)` |
| `bundle_text` `Regex.compile` | 三个 early Err return 新增 `{ rt_release(ch); }`；循环落出新增；函数尾删除 |
| `bundle_text` `utf16ToUtf8` | early return 新增 `{ rt_release(res); }`；函数尾顺序改为逆序 |
| `bundle_text` `utf8ToUtf16` | 三个 else-if 分支新增分支块 `root_restore` |
| `bundle_text` `Regex.isMatch` | if 体内临时层的 restore 位置不变；不再有函数尾 release |

**预期不变**：临时号、所有 `#line`、所有非清理语句、未列出 fixture 的全部文本。
此步 return/break 仍走旧路径，parseFloat break 多恢复一层等问题允许暂时存在。

编译门：xnullc 能解释执行 `bundle_text` 并输出完整 C；不得有重复函数定义/未声明变量。

## C.4 步骤 4：return/try 消费点（输出只变 return 路径）

1. 删除 `emitEarlyRet`；所有 `ReturnStmt`（含 `early` 两套分支）统一：
   `emitCleanup(sc, e, e.ind + 4, e.ind, true)` → `sc.returned = true` → `return ...;`。
2. `try` 的 cleanup 改 `emitCleanup(sc, e, e.ind + 8, e.ind + 8, true)`，删除手写 root restore。
3. 删除入口尾部的旧 `emitCleanup`、`releases`/`strLocals` 循环、root restore、
   无条件 `return`；删除 `sc.releases`/`sc.strLocals` 双写。
   - **顶层函数**：只保留 `if hasResult && !root.returned` 的零值返回；非 Result
     函数不加 fallback（Go `genFuncNamed` 无 fallback）。
   - **方法**：保留 Go `genMethod` 的 fallback——`retC != void && !hasResult` 时
     无条件输出 `return (<retC>)0; /* sema 保证不可达（函数体全路径 return） */`
     （opt/struct/tuple 用 `{0}` 形式）。这是 Go 文本的一部分，不能当“死代码”删掉。
4. 构造器 ReturnStmt 特判：`emitCleanup(...)` + `return;`（D.5）。

**预期会变**：所有 early Err return 的清理块按作用域链重排：
`parseFloat` 两处 Err、`Regex.compile` 三处、`utf16ToUtf8` 三处、`utf8ToUtf16`
多处；`err/result_try.x` 的 try 清理恢复为“子块 → 函数块”顺序。
**预期不变**：块尾行（步骤 3 已定）、break/continue 行、root_add 行。

## C.5 步骤 5：break/continue 消费点

1. `BreakStmt`/`ContinueStmt` 改为 `rootRestoresOf(sc, kind)` + `break;`/`continue;`。
2. 删除 `blockRoots`/`blockInds` 与 `blockRoots.push/remove`。

**预期会变**：`parseFloat` 内层 while 的 `break` 从
`t142 → t136 → t135` 变为 `t142 → t136`（不再恢复外层 if 的 t135）；
`stmt/if_while.x`、`stmt/for_in.x`、`stmt/switch.x` 的 break/continue 行。
**预期不变**：所有 return 清理、块尾清理、root_add、非 break/continue 语句。

## C.6 步骤 6：switch/for 的创建顺序与 else-if 细节

1. `emitSwitch`：先求匹配值与全部 case 表达式，再逐个 `newChild`；case 体用
   `emitBlock`；default 同样。
2. `emitForIn`：先 `bodySc = newChild` + `emitBlock`，后 `idx = e.nt()`。
3. `emitIf` 的 else-if：`elseSc = newChild`，只 `emitStmt(elseSc, n.Else)`，不
   `emitBlock`。

**预期不变**：`bundle_text`（无 switch/for-in）逐字节不变；`stmt/switch.x`、
`stmt/for_in.x` 只允许 case/循环体的 mark 号与顺序变化，以及随之平移的临时号；
`gen/*` 的 if/else-if 输出不变。

## C.7 步骤 7：入口点收口

按 B.3 的 emitStructMethods / emitExtensionMethods / emitFactoryMethods /
emitDataEnum / emitDataEnumMethods / emitSingletonSection 动作，把其余入口改成
root scope + rootPrelude + emitBlock，删除尾部手写清理（类方法/构造器已在 3a 完成）。
方法入口保留 `genMethod` 的 fallback return（见 A.9），工厂方法不保留。

**预期不变**：`bundle_text`（只有顶层函数和 Regex 方法）在步骤 3-6 后应已逐字节
一致；`obj/*`、`obj2/*`、`obj3/*`、`gen/*` 只允许入口/出口清理行变化，
方法体中间文本不变。

## C.8 步骤 8：删旧路径（零输出变化）

删除 B.4 字段/函数/参数；grep 确认 0 引用；再跑一次全量，输出必须与步骤 7 完全一致。
`emitDeferBody`/`emitBlockDefers` 删除后，用户 `defer` 的通用捕获改为：

```xnull
// DeferStmt 分支
Bool err = txt(fld(st, "Errdefer")) == "true"
EM de = new EM()
de.tmp = e.tmp                  // 共享翻译单元临时号
de.path = e.path
// 逐条 emitStmt(sc, deferredStmt, de)，此时 de.ind = 0
// 捕获 de.ls，给每行加 8 空格前缀，存入 DF.lines
// 注意：Go 的 defer 体不发射 #line；捕获时置 SKIP_LINE=true 或直接跳过 #line 行
e.tmp = de.tmp
addDefer(sc, prefixedLines, err)
```

## C.9 步骤 9：全量回归与四函数

1. 全量 fixture：`tests/b3/fixtures/**/*.x` 按 `last-green.tsv` 口径逐个跑 Go C /
   xnullc C / `diff`；要求 `bundle_text` 为 0，其余不得回归（与步骤 0 基线比）。
2. 四函数专项（text.x 的 `regexAtomMatch`、`regexMatchAt`、`repeatText`、
   `repeatJoined` 都在 `bundle_text` 里）：

```bash
for fn in xn_regexAtomMatch xn_regexMatchAt xn_repeatText xn_repeatJoined; do
  for side in go xn; do
    awk -v n="$fn" '$0 ~ ("[ *]" n "\\(") && /\{$/ {p=1} p{print} p && /^}$/{exit}' \
      /tmp/text.$side.c > /tmp/$fn.$side.c
  done
  diff -u /tmp/$fn.go.c /tmp/$fn.xn.c
done
```

若全文件 diff 已为 0，这四个 diff 必然为 0；保留该检查用于定位回归。
3. 预期最终：`diff -u /tmp/text.go.c /tmp/text.xn.c` 输出为空（0 行）。
   若还剩 4 行，只可能是附录 E 的逻辑括号，按 E 修。

---

# D. 风险点

## D.1 Result early return

- `xn_ret` 必须在 cleanup **之前**赋值；Ok/Err/变量/调用/`try` 全部如此。
- cleanup 里的 errdefer 用 `xn_ret.ok` 判定；普通 return Ok 时 errdefer 不执行，
  但普通 defer/局部 release/root_restore 照常执行。
- `emitCleanup` 的 `hasResult` 取起始 scope；子 scope 必须继承，不能默认 false。

## D.2 errdefer

- 普通 defer 与 errdefer 必须在**同一个 defers 列表**里按注册顺序交错；不能像现在
  这样先输出全部 errdefers 再输出 defers。
- 块正常落出：errdefer 全部跳过。
- return/try：逆序遇到 errdefer 才输出 `if (!xn_ret.ok) { ... }`；非 Result 函数
  的 errdefer 永不输出（`!s.hasResult`）。
- `DF.err` 是唯一标志；不要另建列表。

## D.3 blockHeld

- 只有跨作用域赋值才 `xn_root_hold`；owner 是**声明该变量的 scope**，用 `own` 链查找。
- 同一 owner 同一变量多次赋值只记一次 `blockHeld`，但每次赋值都发 `xn_root_hold`。
- owner 块退出时在**所有 defers 之前**输出 `xn_root_release`；return 路径不输出，
  return 之后的不可达文本仍要输出（emitBlockExit 无条件先发 blockHeld）。
- 漏掉 `own` 会导致把 hold 记到当前循环体，造成每轮释放/计数错误；
  用 `names` 判断（包含祖先）会永远命中当前 scope，必须用 `own`。

## D.4 GC 参数 / self / 构造对象 rootPrelude

- 顺序：先 self（方法）或 o（构造器），再按参数声明顺序；全部在 mark 之后、
  第一条 `#line`/语句之前。
- 只对 `isGCRootC` 类型登记；ARC 类 self/参数不登记。
- `rootPrelude` 只由 emitBlock 输出一次并清空；不要在每个子块重复。
- 构造器 `o` 的 root_add 属于 rootPrelude，不是“函数体第一条语句”；漏掉会让
  `xn_root_add(o)` 跑到 `#line` 后面，整段 diff。

## D.5 构造器 return

- Go 的 `genMethod`/ctor 没有把 `isCtor` 置 true（`classes.go:730`），所以构造器体
  里的 `return;` 走 `retC=="void"` 分支：`emitCleanup(true,"    ")` + `return;`
  （`codegen.go:3682-3689`）。
- xnullc 构造器初始化函数也返回 `void`；不要生成 `return o;` 或 `return xn_ret;`。
- 如果 E2 给 `SC` 加了 `isCtor`，必须与 Go 实际行为一致：要么不置 true，要么在
  ReturnStmt 里走 void 分支。不要照抄 `codegen.go:3621-3628` 的 `return o;` 死代码。

## D.6 try 传播

- try **不创建 scope**，不占 rootMark；cleanup 从当前 scope 沿 parent 链执行。
- try 的 `if (!t.ok)` 体缩进：`{` 在 `I`，`xn_ret` 在 `I+4`，cleanup 的 `{` 在
  `I+8`，cleanup 行在 `I+8+行首空格`，`return` 在 `I+4`，`}` 在 `I`。
- try 传播**不设** `returned`；块尾仍会在后面输出一次清理（不可达文本，但 Go 有）。
- 跨 Result 类型（`Result<T>` → `Result<U>`）先置零再转移 err，不能整结构体赋值。

## D.7 其他高风险点

1. **空块占号**：`newChild` 必须无条件 `e.nt()`；不要因为 `Stmts.length()==0` 跳过。
2. **else-if 不声明**：`elseSc` 占号但不 `emitBlock`；若误调 emitBlock，会多一行
   mark 并把后续临时号全部打乱。
3. **returned 不传播**：只在当前 scope 置 true；外层块继续输出块尾清理（死代码）。
   旧 `terminated` 的全局抑制必须删掉。
4. **rootTempDecls 不 dedup**：同一临时在多层 wrapper 出现多次是规范；保留
   `doubleRoot`/`rootedTemps` 会少行，去重会多删。
5. **局部 release 的 scope**：String/Bytes/ARC 类/协议/句柄/Task 的 release 必须挂
   声明所在块；挂函数级会导致循环体漏释放、return 漏释放、函数尾重放。
6. **break/continue 不执行 release**：只 restore 根帧；不要为“对称”补 `rt_release`。
7. **switch**：case 条件先全部求值；每个 case/default 都占号并声明 mark；case 内
   break 停在 kind=switch 的帧，不再恢复外层 loop。
8. **while 降级**：mark 在 pre 和 `if (!cond) break;` 之后；pre 的 root_add 不属于
   body mark。
9. **for-in 分配顺序**：先 newChild/emitBlock，后 `idx = e.nt()`；反了会让循环体
   临时号整体后移。
10. **用户 defer 捕获**：必须在 `e.tmp` 共享的临时 EM 中发射，行首统一加 8 空格；
    不能只支持字符串字面量，也不能在块尾重新 `expr` 求值（会重复副作用/新临时号）。
11. **入口 rootMark 的分配点**：顶层函数/方法在入口最先分配；构造器在字段初值临时
    之后分配（Go `classCtorInit` 先于 `sc.rootMark`）；工厂/枚举/单例沿用现有
    `ce.nt()` 位置。不要为了“统一”把 rootMark 提前或推后，否则整文件临时号平移。

---

# E. 附录：同批必修的 4 行逻辑括号（否则无法归零）

不属于作用域清理，但 `B3-text-rest-diff.md` 的 91 行里含 4 行；只做 A-D 仍会剩 4 行。
位置：`xnullc.x` `expr` 的 `&&`/`||` 分支（L1195-1205）。

规则（来自 `B3-text-rest-diff.md` §1.6/§2.2）：当 `&&`/`||` 的操作数本身也是
`&&`/`||` 时，该操作数要在已有的外层括号上**再加一对**：

```xnull
if !IN_PAREN && !NO_OP_WRAP && lb.nm == "Binary" {
    String lop = unq(txt(fld(lb, "Op")))
    if lop == "&&" || lop == "||" { lv = "(" + lv + ")" }
}
if !IN_PAREN && !NO_OP_WRAP && rb.nm == "Binary" {
    String rop = unq(txt(fld(rb, "Op")))
    if rop == "&&" || rop == "||" { rv = "(" + rv + ")" }
}
```

期望修复：
- `parseFloat` text.x:156 `if ((((i < n)) && ((xn_str_eq(t148,t149) || xn_str_eq(t150,t151)))))`
- `Regex.compile` text.x:276 左侧 `||` 链外再包一对。

# F. 复现与验收清单

```bash
# 1) 基线
diff -u /tmp/text.go.c /tmp/text.xn.c | wc -l        # 349

# 2) 固定函数段对比
for fn in xn_parseFloat xn_utf16ToUtf8 xn_utf8ToUtf16; do
  for side in go xn; do
    awk -v n="$fn" '$0 ~ ("[ *]" n "\\(") && /\{$/ {p=1} p{print} p && /^}$/{exit}' \
      /tmp/text.$side.c > /tmp/$fn.$side.c
  done
  diff -u /tmp/$fn.go.c /tmp/$fn.xn.c
done

# 3) 终验
diff -u /tmp/text.go.c /tmp/text.xn.c    # 必须为空
```

验收硬指标：

1. `bundle_text` 全文件 diff = 0。
2. `regexAtomMatch` / `regexMatchAt` / `repeatText` / `repeatJoined` 四段 diff = 0。
3. `tests/b3/fixtures/err/{clean_defer,clean_block_defer,errdefer,result_try}.x`
   的 defer/errdefer/return 文本与 Go 一致。
4. `tests/b3/fixtures/stmt/{if_while,for_in,switch}.x` 的 break/continue 恢复层数
   与 Go 一致（不多恢复一层）。
5. `tests/b3/fixtures/obj*`、`gen/*` 的类方法/构造器入口 prelude 与尾部清理一致。
6. grep B.4 清单为 0；`xnullc` 自解释执行无未定义符号。

## 施工注意事项

- 本文所有 xnullc 行号以 `9313c48` 为准；E2 改动后行号会漂移，按函数名 + 行号片段定位。
- 不要改 Go oracle；任何“Go 看起来奇怪”的输出（重复 root_add、brace 比 body 深、
  return 后不可达清理）都是冻结行为，照抄。
- 每完成 C.1/C.2 先提交一次中间版本（单卡 30 分钟规则）；C.3-C.6 可作为一个
  逻辑提交，但内部按 3a→3b→3c→4→5→6 顺序编译。
