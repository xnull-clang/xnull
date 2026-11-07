# CEO1-RD3 首轮：代码生成域盘点（impl/internal/codegen，不含 ffi）

> **角色**：CEO1-RD3-代码生成（一司）｜必签 E4
> **依据**：董事会判决 v1.6.0 第 2.1 条（RD3 职责：C 代码生成/多文件；写入域 `codegen/**`）、第 5 条（首轮只读，48h 交）；CEO1《派工-首轮-2026-11-07》卡 3
> **基线**：main `dfcf033`；go1.27.3 darwin/amd64；cc = clang
> **只读声明**：未改任何生产代码、规范、台账、缺陷表；未 commit；未派工；未写他人文件。探针源码与产物均在 `$TMPDIR/opencode/rd3/`，可随时删除。
> **本文件性质**：只读盘点 + 缺陷初判 + 建议卡；**不是门禁结论、不是派工单、不是缺陷登记**（登记归 CEO3）。

---

## 0. 结论（先给可判定的）

1. **基线是绿的，但绿得没有意义**：`go test ./internal/codegen -count=1` 9 个测试函数全过，覆盖率 **72.4%**（已达 Stage 2 的 70% 线）。但本轮实测出 **5 条 P0 级生成错误全部在这层绿网之下**，其中 3 条是**静默输出错误值**（不报错、不崩溃、单测看不见）。
2. **最严重的一条**：插值字符串 `$"value={total}"` 编译路径输出 `value=`，解释路径输出 `value=7`。根因是 `plainText()` 只拼 `StrPart.Text`，直接丢掉 `StrPart.Expr`（`codegen.go:1798-1805`）。全程无任何诊断。
3. **defer/errdefer 的出口模型与规范 §10.3 不符**：嵌套块 `return` 不执行外层 defer；`break` / `continue` 不执行本块 defer。三条都有实测复现，解释路径正确、编译路径错。
4. **编译器会崩**：`print()` → `panic: index out of range`（`codegen.go:766`）。`print(1, 2)` → 静默忽略第二实参。两者都直接违反 NEG-01「编译器不崩溃、不静默接受」。
5. **codegen 有 99 处 `fmt.Errorf("codegen：…")`，只有 4 个真诊断码**（全在 `multifile.go`）。按 `impl/docs/m4-codegen-design.md:29` 的设计，codegen 失败应视为内部错误、不面向用户；现在的实际行为是把内部错误当用户诊断吐出去（无 `文件:行:列`、无诊断码），BND-14 / NEG-01 无法判过。
6. **质量门被悄悄放松**：设计文档要求 `-std=c11 -O2 -Wall -Werror`（§5.2），实现只用 `-O2`（`build.go:44`）。我按设计参数复跑 hello，**clang 报 20+ 个 `-Wunused-function`**——prelude 无条件发射全部助手函数。`-Werror` 现在根本打不开，这就是它被去掉的原因（推测，未取证）。
7. **测试缺口 12 条**（§4.3），全部是「双路径一致性」和「负向/崩溃」两类；现有 9 个测试函数里**没有一个**断言插值、`str(Bool)`、`Result<Bool,*>`、Set 字符串成员、`print()` 空实参、相对路径入口。
8. **功能矩阵对照**（判决 v1.0.0 §4.3，13 项）：4 项已修（break / 多文件 / `.x` / 单文件 build），3 项仍 ❌ 且属本域（闭包、泛型、区间 for-in、`main(args)`、XDK），1 项新增口径问题（并发不在本域）。逐项见 §5。
9. **前 3 张建议卡**（§6）：E4-01 插值静默丢弃、E4-02 defer/errdefer 出口模型、E4-03 崩溃/静默接受清零 + 诊断化。三张都 ≤2 人日，验收命令可复制。

---

## 1. 职责边界

| 项 | 内容 |
|---|---|
| 我做 | C 代码生成、多文件编译单元、生成侧所有权/生命周期、与 `impl/runtime` ABI 的对接 |
| 我不做 | `sema` 类型检查（RD2）、`xfront` 解析（RD1）、`codegen/ffi/**`（二司 RD3）、运行时 C 语义（二司 RD2）、派工与排期 |
| 本轮只读 | 全部文件；唯一写入 = 本文件 |
| 写权状态 | `wt/c1-rd3`（`pod/c1-rd3`，基线 `dfcf033`）已建但**未解禁**（`evidence/S0-28/` 缺失）→ 本轮及解禁前不得写生产代码 |

---

## 2. 生成器结构

### 2.1 三个入口（对外 API 面）

| 入口 | 位置 | 职责 | 调用方 |
|---|---|---|---|
| `LoadUnits(entryPath)` | `multifile.go:32` | 从入口解析 `import` 闭包 → 合并为单一 `CompilationUnit` | `Build`、`cli` 的 `--interp` 路径（`cli.go:228`） |
| `EmitC(u)` | `codegen.go:141` | `CompilationUnit` → 单文件 C 文本 | `Build`、测试 |
| `Build(srcPath, outPath, runtimeDir, stderr)` | `build.go:15` | LoadUnits → sema → EmitC → 写 `<out>.c` → `cc` → 可执行 | `cli.go:209`、`cli.go:312` |

只有这 3 个符号跨包可见；其余全是包内实现。**没有 `--emit c` 的库内支持**（CLI 侧也没有，见 `cli.go` 命令表）。

### 2.2 文件职责与规模

| 文件 | 行数 | 职责 |
|---|---:|---|
| `codegen.go` | 1812 | prelude（17 个 C 助手函数，恒量发射）、`EmitC` 三段式装配、`scope`/defer 帧、语句发射（if/while/for-in/defer/throw）、表达式发射（str/int/cond/callArgs）、`print`、`Result`、字符串字面量与转义 |
| `types.go` | 167 | 代码生成期轻量类型推断 `exprType`（只服务 print 分派 / 成员返回值） |
| `containers.go` | 331 | 容器按需实例化：`xn_arr_<e>` / `xn_set_<e>` / `xn_map_<k>_<v>` 结构 + 静态助手（new/push/get/set/remove/clear/free/add/has/put/getOr） |
| `containers_expr.go` | 351 | 容器在表达式层的收/放：字面量、成员语句、成员值、下标读写 |
| `classes.go` | 274 | 类：结构体 + `rt_type` 描述符 + deinit + 构造器 + 字段初值 |
| `classes_expr.go` | 177 | 类在表达式层：接收者解析（局部/self/字段链）、`new`、成员读写、方法调用 |
| `strmethods.go` | 96 | String 成员（length/indexOf/startsWith/endsWith/substring/trim/toUpper/toLower） |
| `multifile.go` | 151 | import 闭包加载、环检测、包一致检查、去重合并、4 个诊断码 |
| `build.go` | 56 | 端到端构建 + `cc` 驱动 |
| **小计** | **3415** | 测试 341 行（9 个 `Test` 函数），生产:测试 ≈ 10:1 |

### 2.3 发射路径图

**单文件**：`xfront.ParseUnit` → `sema.Analyze` → `EmitC`

`EmitC` 是**三遍式**，顺序不可交换（`codegen.go:141-313`）：

```
第 1 遍  收集 Result 实例化名（collectResult）
第 1.5 遍 收集类（collectClass → 字段类型触发容器实例化注册）
第 1.7 遍 顶层函数签名表 fnRet（重名即报「重载未支持」）
第 2 遍  试生成全部函数体/方法体（产物丢弃）——唯一目的是把 Result/容器实例化补齐
         ↓ g.tmp = 0
第 3 遍  正式生成顶层函数体
装配     prelude → Result typedef → xn_fatal_oob → 类前向声明 → 容器结构
         → 顶层函数原型 → 类结构/deinit/rt_type/构造器/方法原型/方法体
         → xn_result_error_copy_rt → 顶层函数体 → C 入口垫片
```

设计文档 §1.2 规划的是 7 个文件（`emit_stmt.go` / `emit_expr.go` / `emit_type.go` / `emit_defer.go` / `emit_rc.go` / `mangle.go`），实际是 **6 个按语言特性切的文件**（codegen/classes/containers/strmethods/types/multifile）。**`mangle.go` 整块缺失**（见 N-09），`emit_defer.go` 的静态展开也没实现（见 N-02/N-03）。

**输出顺序不变量**（`classes.go:97-99` 有明确注释，S1-06 修复的产物）：前向声明 → 容器结构 → 顶层函数原型 → 类完整定义。这个不变量现在有测试守（`multifile_test.go:123`）。

**多文件**：`LoadUnits` 后序合并（依赖在前、入口最后），不引入独立编译单元——**多文件是"合并成一个 C 文件"**，不是多 TU。因此 C 侧符号只要不重名就行；重名直接报错（`codegen.go:163`）。

**容器**：按元素 C 类型**逐实例化**（`mangle`：int64_t→i、int→b、rt_string*→s、类→`o_<Name>`），无运行期注册表。所有实例化在装配阶段按**字符串排序**输出，保证 DET-01。

**类**：单类、无继承、无协议、无泛型；ARC 对象 = `rt_header` + 内联字段；deinit 按字段类别（String/容器/类引用）逐个 release；方法一律 `static` 静态绑定，`self` 为首参。

**入口垫片**：`int main(void) { int64_t xn_r = xn_main(); rt_quarantine_flush(); return (int)xn_r; }`（`codegen.go:310`）——**没有 argv 透传**，即已登记的 P1-1。

### 2.4 值表示与所有权纪律（实际实现，非设计）

| XNull | C 表示 | 所有权 |
|---|---|---|
| `Int` | `int64_t` | 值 |
| `Bool` | `int` | 值（`print` 走 `xn_print_bool`） |
| `String` | `rt_string *` | 单一所有权；`strExpr` 产出必为 +1；`xn_concat` 接管两侧 |
| `Result<Int,String>` | `typedef struct { int ok; int64_t v; rt_string *err; }` | **无 deinit**，`err` 从不释放（N-14） |
| `Result<Bool,String>` | 同上但 `v` 为 `int` | **类型名写死在 `xn_Result_Int_String`**（N-06） |
| 容器 | `typedef struct { size_t len, cap; T *data; }` 等 | 局部 free 于块退出；String/类元素入容器 retain |
| 类实例 | `xn_Cls_X *`（ARC） | new/方法返回 = +1；字段读 / 容器元素 = 借用 |
| 闭包 / 泛型 / 元组 / `Float` / `Char` / `null` | — | 显式报「未支持」 |

### 2.5 与设计文档 `impl/docs/m4-codegen-design.md` 的偏离（可直接转整改项）

| # | 设计要求 | 实现现状 | 判定 |
|---|---|---|---|
| D-1 | §4.3 单出口 `goto xn_exit_fn` + 静态展开 defer | 无 goto、无出口标签；**每个 return/break/continue 就地内联清理，且只看当前 scope** | 偏离，造成 N-02/N-03 |
| D-2 | §2.5 命名映射 `mangle.go`，冲突追加 `_x` | 无任何 mangle；字段/局部名原样落地 | 缺失，造成 N-09 |
| D-3 | §5.2 `-std=c11 -O2 -Wall -Werror` | 只有 `-O2` | 门放松，N-17 |
| D-4 | §5.2 CC 探测 `CC`→cc→clang→gcc、libxrt.a 缓存、`target/gen/<unit>.c` | 硬编码 `cc`；每次现编 4 个 `.c`；`.c` 写在 `outPath+".c"` | 偏离，N-18 |
| D-5 | §6 新运行时 API `rt_string_concat`/`rt_str_from_*`/`rt_array_*` | 全部改为 prelude 内联 `xn_*`，未进 `rt.h` | 偏离（可接受，但需在 runtime-contract 补记，否则双份字符串实现漂移） |
| D-6 | §2.4 `Result` = `tag + union`，`deinit` 只释放 tag 所指一侧 | `ok + v + err` 三字段，无 deinit | 偏离，N-14 |
| D-7 | §3.3 传参 retain、返回 retain、临时释放 | 传参不 retain（借用）、临时释放基本没做 | 偏离，N-14 |

---

## 3. 已知缺陷

### 3.1 已登记（`收件箱/CEO/缺陷登记表-v1.0.0.md`）与本域的关系

| 缺陷ID | 与本域关系 | 本轮复测 |
|---|---|---|
| P0-3 多文件前向声明 | 已于 `3ea90b3` 关闭 | ✅ 复跑通过（`TestMultiFileExampleCompileMatchesInterp`）；顺序不变量现存于 `classes.go:97-99` |
| P1-1 `main(args)` | **本域** | ✅ 仍存在：`xnull run p9.x` → `cc: too few arguments to function call … xn_p_args was not specified` |
| P1-6 闭包/泛型/XDK/区间 for-in | **本域**（4 项中 3 项） | ✅ 仍存在：闭包无发射路径；泛型无单态化；`for i in 0..<3` → `codegen：for-in 源 *xfront.Binary 不是容器`；XDK 见 §5 |
| P0-1 / P0-5 break | 解释器侧 | 编译路径 break 语义正确，但**带 defer 时错**（N-03） |

### 3.2 新发现（本轮实测，均未在缺陷登记表）

> 每条给：现象 / 实测输出 / 根因 / 建议严重级。复现源码见 §9，命令模板见 §8。
> 严重级为 RD3 初判，最终由 CEO1/CEO3 定。

#### N-01　插值字符串静默丢弃全部插值表达式　【P0·静默错值】

| 项 | 内容 |
|---|---|
| 现象 | `$"value={total}"` 编译路径输出 `value=`；解释路径 `value=7` |
| 实测 | `p1.x`：编译 `value=` ／ 解释 `value=7`（§8 命令 3） |
| 根因 | `plainText(n)`（`codegen.go:1798-1805`）只写 `StrPart.Text`；parser 对插值段构造的是 `StrPart{Expr: …}`，`Text` 为空 → 整段消失。`strExpr` 的字面量分支（`codegen.go:1313-1316`）和类字段初值（`classes.go:245`）都走 `plainText` |
| 影响 | 所有 `$"…{}"` 字符串。**不报错、不崩溃、退出码 0**。当前 9 个示例无一使用插值 → 测试全绿 |
| 严重级建议 | P0（静默错误输出；S1 §1.4.4/§7.8 直接违反） |

#### N-02　嵌套块 `return` 不执行外层 `defer`　【P0·语义违反】

| 项 | 内容 |
|---|---|
| 现象 | 函数级 `defer` + `if { return }` → 编译路径不打印 defer |
| 实测 | `p2.x`：编译 `1` ／ 解释 `outer-defer` + `1` |
| 根因 | `scope.newChild()`（`codegen.go:560-566`）**不继承 `defers`**；`emitReturn`（`codegen.go:1129/1144/1157/1176/1193/1203/1212/1226/1242`）只调用本 scope 的 `emitCleanup`。外层 defer 帧在 return 路径上完全不可见 |
| 影响 | S1 §10.3「return 触发全部 defer，LIFO」。带 defer 的任何早返回函数都会漏清理（含 String/类引用 → 泄漏） |
| 严重级建议 | P0 |

#### N-03　`break` / `continue` 跳过本块 `defer`　【P0·语义违反】

| 项 | 内容 |
|---|---|
| 现象 | 循环体内 `defer` + `break`：defer 只执行了 `break` 之前的迭代次数 |
| 实测 | `p3.x`：编译 `loop-defer`×1 + `after` ／ 解释 `loop-defer`×2 + `after`；`p20.x`（continue）：编译无输出 ／ 解释 `d`×3 |
| 根因 | `BreakStmt`/`ContinueStmt` 直接发射 `"break;"` / `"continue;"`（`codegen.go:653-657`），不经 `emitCleanup`；块退出清理只在 `emitBlock` 末尾线性追加（`codegen.go:614-623`） |
| 影响 | S1 §10.3 + §6.7。与已关闭的 P0-1（解释器吞 break）同族，但方向相反：编译器这边是 break 之后不清理 |
| 严重级建议 | P0（与 N-02 同一张卡修） |

#### N-04　`print()` 空实参 → 编译器 panic　【P0·崩溃】

| 项 | 内容 |
|---|---|
| 现象 | `xnull run p15.x` → `panic: runtime error: index out of range [0] with length 0` |
| 实测 | 栈顶 `codegen.(*scope).emitExprStmt … codegen.go:766` |
| 根因 | `emitExprStmt` 无 arity 检查直接 `call.Args[0]`；sema 也没拦（拦了就不会到这里） |
| 影响 | NEG-01 / BND-14「编译器不得崩溃」。用户输入一句 `print()` 即得 Go 栈回溯 |
| 严重级建议 | P0 |

#### N-05　`print(1, 2)` 静默忽略多余实参　【P0·静默接受】

| 项 | 内容 |
|---|---|
| 现象 | 编译路径打印 `1`，退出码 0，无诊断 |
| 实测 | `p16.x` |
| 根因 | 同 N-04；只取 `Args[0]` |
| 严重级建议 | P0（与 N-04 同卡） |

#### N-06　`Result<Bool, String>` 发射错误类型名 → C 编译失败　【P1】

| 项 | 内容 |
|---|---|
| 现象 | `cc: unknown type name 'xn_Result_Int_String'; did you mean 'xn_Result_Bool_String'?` |
| 实测 | `p17.x`（编译失败）／ 解释 `true` |
| 根因 | `genFunc` 把 `xn_ret` 声明写死为 `xn_Result_Int_String`（`codegen.go:519`、`526-528`），而 `hasResult` 对 Int/Bool 都为真（`codegen.go:502`）；`resultName` 明明已算出 `xn_Result_Bool_String`（`codegen.go:346`） |
| 影响 | 所有返回 `Result<Bool,String>` 的函数。`result-try.x` 只用 Int → 测不到 |
| 严重级建议 | P1 |

#### N-07　`Set<String>.has()` → codegen 内部错误　【P1·双路径不一致】

| 项 | 内容 |
|---|---|
| 现象 | `codegen：Int 表达式 *xfront.StrLitExpr 未支持（M4.1 范围）` |
| 实测 | `p6.x`（编译失败）／ 解释 `true` |
| 根因 | `containerMemberValue` 对 Set/Array 的 `has` 一律 `s.intExpr(args[0])`（`containers_expr.go:293-299`），不按元素类型分派；`add` 分支（`:274-284`）反而正确用了 `elemValue` |
| 影响 | S1 §9 `Set.has`；解释器已支持 → 用户切编译路径即挂 |
| 严重级建议 | P1 |

#### N-08　类字段 `Set<T> = []` 生成错误签名 → C 编译失败　【P1】

| 项 | 内容 |
|---|---|
| 现象 | `cc: too many arguments to function call, expected 0, have 1`（`xn_set_s_new(0)`） |
| 实测 | `p8.x`（编译失败）／ 解释 `0` |
| 根因 | `classCtorInit` 对 `f.isArr` 一律发 `<ctype>_new(0)`（`classes.go:259-265`），但 `xn_set_*_new` 是无参的（`containers.go:213`） |
| 严重级建议 | P1 |

#### N-09　无标识符 mangle：字段撞 `rt_header.hdr`、局部撞 C 关键字　【P1】

| 项 | 内容 |
|---|---|
| 现象 | ① 类字段名 `hdr` → `duplicate member 'hdr'`；② 局部名 `int` → `int64_t int = 3;` 语法错误 |
| 实测 | `p14.x`：`prog.c:127:13: error: duplicate member 'hdr'` / `prog.c:151:9: cannot combine with previous 'type-name' declaration specifier` |
| 根因 | 结构体恒有 `rt_header hdr`（`classes.go:118`），字段名原样输出（`classes.go:120`）；局部声明原样输出（`codegen.go:1013`）。设计 §2.5 要求 `mangle.go` + 冲突加 `_x`，该文件不存在 |
| 影响 | 任何与 C 关键字 / `rt_header` 成员 / 生成符号（`xn_*`、`xn_tN`、`self`、`o`）重名的用户标识符 → C 层报错，且报错位置在生成文件里，用户看不到自己源码的位置 |
| 严重级建议 | P1 |

#### N-10　`./main.x` 相对路径入口报「无法读取入口文件」　【P1】

| 项 | 内容 |
|---|---|
| 现象 | `xnull run ./main.x` → `./main.x:1:1: error[RES-106]: 无法读取入口文件 main.x`（文件就在当前目录） |
| 实测 | `p-sub`：`cd sub && XNULL_RUNTIME=… xnull run ./main.x` |
| 根因 | `LoadUnits` 用**原始** `path` 做 state/units 的 key（`multifile.go:43,73`），入口查表却用 `filepath.Clean(entryPath)`（`multifile.go:94`）。依赖侧 key 走 `filepath.Join` 已被 Clean，入口侧没有 → `./main.x` ≠ `main.x` → `entry == nil` |
| 影响 | 最常见的调用形态之一。绝对路径、`main.x`、`../x/main.x` 正常，只有带 `./` 前缀挂 |
| 严重级建议 | P1（一行修，但属"用户第一步就踩"） |

#### N-11　`xn_arr_*_remove` 释放整个数组的元素　【P1·所有权】

| 项 | 内容 |
|---|---|
| 现象 | 生成代码里删一个元素 = 遍历释放**全部**元素 |
| 证据 | `p4bin.c:153-160`（§8 命令 5）：`for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }` 在 `remove` 里，随后才做位移 |
| 根因 | `emitArrHelpers` 的 `%[7]s` 传了 `relElemLoop(elem)`（`containers.go:197-198`），`%[7]s` 在 `remove` 模板里（`containers.go:179-185`）。此处应只释放被删的那个槽位（`dropOld` 语义） |
| 为何现在没炸 | 因为 N-14（字符串临时从不释放）让每个元素多欠一个引用，`release` 一次没归零。**修了泄漏就会立刻变成提前释放/悬垂指针**——这是一颗定时炸弹，两件事必须同批修 |
| 附带 | `remove` 内 `for (size_t i = …)` 与参数 `i` 同名遮蔽（同文件 `:155`），`-Wshadow` 会报 |
| 严重级建议 | P1（升 P0 的条件：N-14 先修） |

#### N-12　codegen 错误不走诊断通道　【P1·系统性】

| 项 | 内容 |
|---|---|
| 现象 | 用户看到的错误形如 `xnull: 代码生成失败：codegen：…（M4.4a 范围）`——无 `文件:行:列`、无诊断码 |
| 证据 | `grep -c 'fmt.Errorf("codegen：' *.go` = **99**；真诊断码只有 RES-106/108/109/110 四个（`multifile.go:24-27`） |
| 设计冲突 | `m4-codegen-design.md:29`：「诊断全部由前端/sema 产生…codegen 失败视为编译器内部错误（BUG 段位）」 |
| 影响 | ① NEG-01 / BND-14 要求「所有禁止构造给出带源位置的诊断」，codegen 侧做不到；② 上表 N-06/07/08/09/10/13 全都以"内部错误"形态暴露，用户无法定位到自己的源码行 |
| 严重级建议 | P1（一张卡：可达的 `fmt.Errorf` 逐条判定 → 归为诊断 或 归为 BUG 并加断言） |

#### N-13　缺 `main` 时编译路径落到 cc 报错，解释路径有诊断　【P1·双路径不一致】

| 项 | 内容 |
|---|---|
| 现象 | 编译：`cc: call to undeclared function 'xn_main'` + `xnull: C 编译失败：exit status 1`；解释：`xnull: 找不到入口 main（缺失入口）` |
| 实测 | `p18.x` |
| 根因 | `EmitC` 无条件发射入口垫片（`codegen.go:300-311`），不校验 `main` 是否存在 |
| 影响 | ENTRY-01「缺失入口被拒绝」现以"内部错误 + C 编译器输出"形态出现 |
| 严重级建议 | P1 |

#### N-14　字符串临时/实参系统性泄漏　【P2·内存】

| 项 | 内容 |
|---|---|
| 现象 | `f("x")`、`"a" + "b"`、字符串比较、插值（若修好）产生的临时串**从不释放** |
| 根因 | `callArgs` 把 `strExpr` 产生的声明塞进 `s.pending`（`codegen.go:1684-1690`），不登记 defer；`emitPrint` 是唯一显式 `rt_release` 的路径（`codegen.go:836`）。`strExpr` 的 Ident 分支自己 retain（`:1391-1398`）后也没有对应释放点 |
| 影响 | 长跑程序无界增长；N-11 因此"看起来没坏"。S3 §2/§7 计数纪律不成立 |
| 备注 | `emitLocalDecl` 的 `String s`（无初值）分支（`codegen.go:966-968`）也漏了 defer，与有初值分支不一致 |
| 严重级建议 | P2（必须有泄漏检测用例才算可验，建议先落 `rt` 侧计数回声） |

#### N-15　`str(Bool)` 静默错值、`print(容器)` 不支持　【P2·静默错值 + 缺口】

| 项 | 内容 |
|---|---|
| 现象 | `print(str(true))` 编译 `1` ／ 解释 `true`；`print([1,2])` 编译报「print 实参类型 xn_arr_i 未支持」／ 解释 `[1, 2]` |
| 实测 | `p7.x`、`p11.x` |
| 根因 | `strExpr` 的 `str()` 分支只走 `s.intExpr`（`codegen.go:1335-1342`）→ Bool 走 intExpr 得 `1`；`exprType` 对 `str(x)` 无条件返回 `rt_string *`（`types.go:155-156`），把 Bool 的错误掩盖到运行期 |
| 影响 | S1 §1.4.4 明确「`Bool` 格式化为 `true`/`false`」 |
| 严重级建议 | P2（Silent wrong value，跟 N-01 同卡修最省事） |

#### N-16　类返回值的 retain 用文本包含启发式　【P2·脆弱】

| 项 | 内容 |
|---|---|
| 现象 | 用 `strings.Contains(expr, d.name)` 判断返回表达式是否引用某个受 defer 保护的临时 |
| 位置 | `codegen.go:1171-1175` |
| 风险 | defer 保护 `xn_t1` 与 `xn_t10` 同时存在时，`xn_t10` 的返回会误命中 `xn_t1` → 多 retain → 泄漏；反向漏命中 → 提前终结（复活 fatal） |
| 建议 | 改为结构化：让 `classCallExpr` 返回其依赖的临时集合，不做字符串匹配 |
| 严重级建议 | P2 |

#### N-17　发射的 C 过不了 `-Wall -Werror`　【P2·质量门】

| 项 | 内容 |
|---|---|
| 现象 | 按设计参数复跑 hello：`error: unused function 'xn_print_int'` 等 20+ 条 |
| 实测 | §8 命令 4 |
| 根因 | prelude 无条件发射全部助手（`codegen.go:34-137`，17 个函数 = hello.c 的 `static` 共 22 条），未按使用情况裁剪；另有 `if (((i == 2)))` 的多余括号（`-Wparentheses-equality`） |
| 影响 | 设计 §5.2 的质量门形同不存在；`build.go:44` 只用 `-O2` |
| 严重级建议 | P2（建议：prelude 拆成按需片段 + 条件表达式去掉多余括号，再开 `-Wall -Werror`） |

#### N-18　`Build` 偏离设计 §5.2（CC 探测/缓存/产物路径/`--emit c`）　【P2】

| 项 | 内容 |
|---|---|
| 位置 | `build.go:39-53` |
| 偏离 | ① 硬编码 `cc`，无 `CC` 环境变量与 fallback；② 每次现编 4 个运行时 `.c`，无 `libxrt.a` 缓存；③ `.c` 写在 `outPath + ".c"`（不是 `target/gen/`）；④ `Build` 无 `--emit c` 只生成模式 |
| 备注 | ③ 与已登记 P1-3（产物不落 `target/`）同族，但落点不同：P1-3 记的是 CLI `out`，这里记的是 `codegen` 自己补的 `.c` 后缀 |
| 严重级建议 | P2 |

#### N-19　`mapTypes` 只认单字符 mangle，`Map<K,类>` 类型还原丢失　【P2·潜在】

| 项 | 内容 |
|---|---|
| 位置 | `containers_expr.go:144-165` |
| 现象 | `xn_map_s_o_Node` → `k = unMangle('s')` 正确，`v = unMangle('e')` = `""`；`containerElem` 对同一名字走 `LastIndex("_")` 得 `"Node"`，也不认 `o_` 前缀 → 返回 false |
| 为何现在没炸 | `Map<String,Node>` 的值只用于 `put` / `length` 时，`elemValue("")` 落到 `intExpr`，`new Node()` / 变量名恰好能"蒙对"类型；一旦 `for-in`、下标、`getOr` 走 `containerElem` 就断 |
| 实测 | `p19.x` 通过（蒙对）；`Map` 直接 `for-in` 本就被规范禁止（S1 §6.7），但代码会发 `m.data` → C 报错而不是诊断 |
| 严重级建议 | P2 |

#### N-20　死代码 / 死分支（覆盖率为 0 的实证）

| 位置 | 说明 |
|---|---|
| `codegen.go:906-916` `isStrShape` | 无调用者，递归分支永不执行 |
| `classes.go:223-230` `cZeroValue` | 无调用者 |
| `codegen.go:1635` `retBase` | 恒等函数，只有 1 处调用 |
| `codegen.go:1385-1390` `strExpr` 的 `mem.Name == "error"` 分支 | 在外层 `case *xfront.Call` 里，`r.error` 是 `Member` 不是 `Call` → 不可达 |
| `containers_expr.go:170,202` `out` / `_ = out` | 死变量 |

附带：`print(r.error)` 因此**整条路径没实现**（`exprType` 在 `types.go:51-58` 先报「接收者类型不可判定」，`strExpr` 的专门分支进不去）。但按解释器口径 `r.error` 是裸成员访问、本应被 sema 拒绝（`p5.x` 实测解释器报「Result 成员是方法」）。→ **sema 漏了，codegen 也漏了**，两侧都该拒；归属 RD2，这里只记现象。

#### N-21　容器成员面缺口（对 BLD-01）

| 容器 | 未实现 | 位置 |
|---|---|---|
| `List`/`T[]` | `insert` | `containers_expr.go:181-182` |
| `Set` | `remove`、`clear`、`get`/下标读 | `containers_expr.go:204-214` |
| `Map` | `get`（缺键返回 `null`）、`keys`、`values` | `types.go:127-131`、`containers_expr.go:318-323` |
| 通用 | 对 Set 的 `a[i] = v` 会发 `xn_set_*_set`（未生成该助手）→ C 未定义符号；`indexRead` 同理 | `containers_expr.go:305-351` |

#### N-22　`for-in` 期间修改容器：双路径不一致（口径未定）　【待裁决】

| 项 | 内容 |
|---|---|
| 实测 | `p22.x`：编译输出 `1 2 3`（边遍历边看到 `push` 进去的 `3`）／ 解释输出 `1 2`（快照） |
| 根因 | `emitForIn` 每轮重读 `acc.len`（`codegen.go:805-811`），不取长度快照 |
| 规范 | S1 §6.7 只说「循环变量可重新赋值，但不会写回容器」，**没有规定遍历期间修改容器的语义** |
| 处置 | 不判缺陷，列 D-1 待董事会/PM 定口径；定了之后两侧往同一口径收 |

---

## 4. 测试覆盖表

### 4.1 现有用例（9 个 `Test` 函数，341 行）

| 测试 | 文件:行 | 覆盖什么 | 缺口 |
|---|---|---|---|
| `TestExamplesCompileMatchesInterp` | `codegen_test.go:74` | 9 个示例双路径逐字节 + 退出码 | 只跑现成示例；示例本身不使用插值/`str(Bool)`/`Result<Bool>`/Set<String>/break-defer |
| `TestCompileDeferSemantics` | `codegen_test.go:99` | 块退出 LIFO（正常下落，无早返回） | 恰好绕开 N-02/N-03 |
| `TestLoadUnitsOrderDeterministic` | `multifile_test.go:33` | 依赖在前 + 去重 | 不测入口路径形态 |
| `TestLoadUnitsCycle` | `multifile_test.go:57` | RES-108 | 只断言码，不断言行列 |
| `TestLoadUnitsMissing` | `multifile_test.go:72` | RES-106 | 同上；未覆盖 `./x` 形态（N-10） |
| `TestMultiFileCrossFileTypeClash` | `multifile_test.go:86` | RES-102（借道 sema） | — |
| `TestMultiFileFnOverloadExplicit` | `multifile_test.go:105` | 重名顶层函数显式报错 | — |
| `TestMultiFileExampleCompileMatchesInterp` | `multifile_test.go:123` | `examples/multi` 双路径 | 只有 1 个多文件示例 |
| `TestXdkSeedUnitCompiles` | `xdk_seed_test.go:16` | `impl/lib/xdk/text.x` 能生成 C | **只断言能生成，不断言能跑**；且该文件在 `codegen.Build` 里根本加载不到（§5 XDK 行） |

### 4.2 覆盖率（实测）

```
go test ./internal/codegen -count=1 -cover   →   72.4% of statements
```

已过 Stage 2 的 70% 线（PM 口径 `CEO1PM-首轮.md` §4.3），**但这是"示例驱动"的覆盖率**：9 个示例跑出来的路径多、分支少。逐函数低覆盖清单（`go tool cover -func`）：

| 函数 | 覆盖率 | 说明 |
|---|---:|---|
| `Build` | **0.0%** | 端到端构建路径在本包内零覆盖（`cli` 另包，不计入） |
| `borrowStr` | **0.0%** | 「借用的 String 表达式」（`print(obj.field)` / `print(list.get(0))`）在主测试里从未走到；我手测 `p21.x` 是通过的，说明**能跑但没测** |
| `isStrShape` / `cZeroValue` / `retBase` / `strings0` | 0.0% | 死代码（N-20） |
| `exprType` | 56.0% | 类型推断一半分支没测（Result/String 成员/Map 分支） |
| `containerMemberStmt` | 31.9% | Set/Map 写操作基本没测 |
| `valExpr` | 33.3% | 容器字面量的失败分支没测 |
| `containerElem` | 43.8% | Set/Map/类元素解析分支没测 |
| `indexRead` | 53.3% | 非容器/Map 报错分支没测 |

### 4.3 测试缺口（12 条，按可验证性排序）

> 每条给「要测什么 / 建议用例名 / 断言形态」。全部要求**双路径**（编译 stdout+退出码 == 解释 stdout+退出码）。

| ID | 缺什么 | 建议用例名 | 断言 |
|---|---|---|---|
| T-01 | 插值字符串：静态段、单插值、多插值、嵌套括号、`{{` 字面量、左→右求值顺序 | `TestInterpStringCompileMatchesInterp` | 双路径逐字节；副作用顺序用计数变量断言 |
| T-02 | `str()` 全类型分派：Int/Bool/String | `TestStrDispatchCompileMatchesInterp` | `str(true)` 必须是 `true`（现测为 `1`，N-15） |
| T-03 | defer 出口矩阵：嵌套块 return / break / continue / try 传播 / 函数自然下落 | `TestDeferExitPathsCompileMatchesInterp` | 5 个场景双路径；现测 N-02/N-03 三点全红 |
| T-04 | `print` 负向：`print()`、`print(1,2)`、`print(未知类型)` | `TestPrintArityRejected` | 必须是**带行列的诊断**，进程不得 panic（现测 panic，N-04/N-05） |
| T-05 | `Result<Bool,String>` 全链路：Ok/Err/try/isOk/value/unwrapOr | `TestResultBoolCompileMatchesInterp` | 双路径（现测 C 编译失败，N-06） |
| T-06 | 容器成员矩阵 × 元素类型（Int/Bool/String/类）：List 全成员、Set 全成员、Map 全成员 | `TestContainerMembersCompileMatchesInterp` | 4 元素类型 × 3 容器 × 成员表，逐格一条（现测 Set<String>.has 失败，N-07） |
| T-07 | 容器元素为引用时 remove/set/clear 的引用计数正确性 | `TestContainerRefElemRefcount` | 需运行时暴露计数回声；现无手段验（N-11/N-14） |
| T-08 | 标识符冲突：类字段 `hdr`、局部 `int`/`for`/`data`/`self`、类名与 C 关键字 | `TestIdentMangleNoCClash` | 生成 C 必须 cc 通过；或有明确诊断（现测 C 报错，N-09） |
| T-09 | 多文件入口路径形态：`main.x`、`./main.x`、`../d/main.x`、绝对路径 | `TestLoadUnitsEntryPathForms` | 4 种形态等价（现测 `./` 挂，N-10） |
| T-10 | 入口负向：缺 `main`、两个 `main`、`main` 带参、`main` 返回 void | `TestEntryPointDiagnostics` | 双路径同码同位置（现测编译落 cc，N-13；带参 = P1-1） |
| T-11 | 生成 C 的可确定性 + 严格编译 | `TestEmitCDeterministicAndStrict` | 两次 `EmitC` 同 sha（已手工验过 ✓）+ `-Wall -Werror` 零告警（现测 20+ 告警，N-17） |
| T-12 | 未支持构造一律「显式拒绝」而非 panic/静默：Float/Char/null/闭包/泛型/元组/Map for-in/Set 下标写 | `TestUnsupportedConstructsRejected` | 每条断言诊断码+行列；**禁止** `panic` 与退出码 0 |

### 4.4 假绿风险点（这轮最需要 CEO1 注意的）

1. **示例驱动**：`TestExamplesCompileMatchesInterp` 是唯一的语义守门员，而 9 个示例是**为了能通过而挑的语言面**。示例不用的构造 = 无测试。N-01/N-06/N-07/N-15 全部由此漏出。
2. **`TestCompileDeferSemantics` 的形态刚好正确**：它的 defer 全部是"块正常下落"，正好不触发 N-02/N-03。这条测试给人"§10.3 已验"的错觉。
3. **`print(1,2)` 静默 = 断言写不了**：没人想到去测 arity，因为"编译器不该崩"被当成默认。
4. **`-Werror` 缺席**：`build.go:44` 只留 `-O2`，等于把 C 层 20+ 条告警全部关掉；`go test` 也从不以 `-Werror` 编 C，所以"生成的 C 质量"这一维度**零证据**。
5. **覆盖率 72.4% 已达标**：数字会让人认为 codegen 可以进 Stage 2 分母，但按 PM §4.3 的"PASS 需正例+负例+边界"，本域一条都没满足。

---

## 5. 与判决 v1.0.0 §4.3 功能矩阵逐项对照

> 判决原文 13 行；下表按本域重新实测（基线 `dfcf033`）。

| 能力 | 判决原判 | 本轮实测 | 结论 |
|---|---|---|---|
| 基础/函数/递归 | ✅/✅ | ✅ 双路径一致（`hello`/`lexer-seed`/`parser-seed`） | 维持通过 |
| 类/字段/方法/容器 | ✅/✅ | ✅ 双路径一致（`classes`/`containers`/`objlist`/`ast-seed`） | 维持通过 |
| Result/try/defer | ✅/✅ | ⚠️ `Result<Int,String>` ✅；**`Result<Bool,*>` C 编译失败（N-06）**；**defer 早返回/break/continue 错（N-02/N-03）** | **降级为不通过**（原判仅覆盖示例形态） |
| 单文件 build | ✅ | ✅ `xnull run`/`build` 可用；`.c` 落点与缓存偏离设计（N-18） | 功能通过，工程纪律待整改 |
| FFI 发射 | ✅（合同面） | 不在本域（`codegen/ffi/**` 归二司），未复测 | 不表态 |
| 闭包 | ❌/✅ | ❌ 无任何发射路径；`exprType` 无函数类型 | 维持未通过 |
| 泛型 | ❌/❌ | ❌ 无单态化；`typeName` 只做末段名匹配 | 维持未实现 |
| XDK List/Map 调用 | ❌/✅ | ❌ **双路径同为 RES-101**（`import xdk.text` + `text.repeatText(...)` 两侧都报未定义名）；且 `LoadUnits` 直接跳过 `xdk.*`（`multifile.go:76-78`），即使 sema 放行也没有实现体 | 维持未通过，且**比判决口径更差**：不是"编译不支持"，是"两条路径都不支持" |
| 区间 for-in | ❌/✅ | ❌ `for i in 0..<3` → `codegen：for-in 源 *xfront.Binary 不是容器`（`codegen.go:782`） | 维持未通过 |
| `main(args)` | ❌/✅ | ❌ `cc: too few arguments … xn_p_args`（已登记 P1-1） | 维持未通过 |
| break | ✅/❌ | ✅ 无 defer 时正确（P0-1 已关闭）；❌ 带 defer 时错（N-03） | **有条件通过**：建议在矩阵加脚注「循环体内含 defer 时不成立」 |
| 并发/任务 | ❌/❌ | 不在本域 | 不表态 |
| `.x` 扩展名 | ❌ | ✅ 已整改（S1-22） | 已闭合 |

**矩阵口径问题（本域发现，交 PM/董事会）**：M4 行的「通过」都是在 9 个示例的语言面上通过的，而不在锚点（ERR-01/BLD-01/ENTRY-01/DET-01/NEG-01）面上。建议给 §4.3 每行加「覆盖到哪个锚点」列，否则「Result/try/defer ✅」这种结论会被错误地当门证据。

---

## 6. 前 3 张建议卡

> 模板依 `派工-首轮-2026-11-07.md` 卡 5 口径；单卡 ≤2 人日；主责唯一；每卡验收命令可复制。
> 三张都排在其他卡之前：E4-01/E4-02 是**静默错值/语义违反**，E4-03 是**崩溃**，属质量红线不可拖。

### 卡 1　E4-01　插值字符串正确发射（P0）

| 项 | 内容 |
|---|---|
| 主责 | CEO1-RD3 |
| 必签 | E4（原主责）+ QA2（双路径独立复跑） |
| 输入 | `codegen.go:1313-1316`（`strExpr` 字面量分支）、`codegen.go:1798-1805`（`plainText`）、`classes.go:245`（字段初值同源）、`impl/runtime/rt.h`（`rt_string_from_c`/`rt_release`） |
| 输出 | ① `StrSampler`：把 `StrLitExpr.Parts` 按序展开为「静态段 `rt_string_from_c` + 插值段 `xn_str_*`」→ `xn_concat` 链；② `str()` 按静态类型分派（`strExpr` 现有 `s.intExpr` 改为 `exprType` 驱动，补 `xn_str_bool`/`xn_str_str`）；③ 求值顺序严格左→右（每段先落临时再 concat） |
| 不做什么 | 不改 `sema`（插值合法性归 RD2）；不实现 `toString()` 自定义类型、`Double`/`Float`/元组/枚举格式化（S1 §1.4.4 有，但属后续切片，本期显式拒绝并给诊断） |
| 验收 | `go test ./internal/codegen -run 'TestInterpStringCompileMatchesInterp|TestStrDispatchCompileMatchesInterp' -count=1` 全绿；新增 T-01/T-02 用例；示例新增 `examples/interp.x` 并接入 `TestExamplesCompileMatchesInterp` |
| 当前红证据 | `p1.x` 编译 `value=` / 解释 `value=7`；`p7.x` 编译 `1` / 解释 `true` |
| 依赖 | 无（可立即开工；需 worktree 解禁） |
| 预估 | 1.5 人日（Sampler 1d + 测试 0.5d） |
| 证据路径 | `evidence/S1-interp-str/` |

### 卡 2　E4-02　defer/errdefer 出口模型统一（P0）

| 项 | 内容 |
|---|---|
| 主责 | CEO1-RD3 |
| 必签 | E4 + QA1（条款追溯 §10.3）+ QA2（双路径） |
| 输入 | `codegen.go:542-625`（`scope`/`newChild`/`emitCleanup`/`emitBlock`）、`codegen.go:1123-1247`（`emitReturn`）、`codegen.go:653-657`（break/continue）；设计文档 §4.3（单出口 `goto`） |
| 输出 | 二选一并写明理由：① 按设计 §4.3 落「块级出口标签 + `goto`」，`scope` 维护 defer 栈链（`parent *scope`），return/break/continue 统一 `goto` 到最近出口；② 保持内联展开，但 `scope` 链式回溯全部祖先 defer。**推荐 ①**：内联展开在「N 个 return × M 个 defer」下产物是 O(N×M)，且 continue 在循环里会每轮膨胀 |
| 不做什么 | 不动 `throw`（§10.4 不展开，现实现正确）；不动解释器 |
| 验收 | `go test ./internal/codegen -run 'TestDeferExitPathsCompileMatchesInterp|TestCompileDeferSemantics|TestExamplesCompileMatchesInterp' -count=1`；T-03 的 5 个场景全部双路径一致；`defer-cleanup.x` 输出不变（回归锚） |
| 当前红证据 | `p2.x` 编译 `1` / 解释 `outer-defer,1`；`p3.x`；`p20.x` |
| 依赖 | 与 E4-01 可并行（不同文件区：`strExpr` vs `scope`） |
| 预估 | 2 人日（标签化 1.5d + 回归 0.5d） |
| 证据路径 | `evidence/S1-defer-exit/` |

### 卡 3　E4-03　崩溃与静默接受清零 + codegen 错误诊断化（P0/P1）

| 项 | 内容 |
|---|---|
| 主责 | CEO1-RD3 |
| 必签 | E4 + QA1（NEG-01 负例集） |
| 输入 | `codegen.go:766`（`print` arity）、`grep -n 'fmt.Errorf("codegen：' `（99 处）、`multifile.go:24-27`（现有 4 个诊断码）、`impl/internal/diag` |
| 输出 | ① 入口层加「生成前置校验」：`print` arity、`Result` 成员形态、容器成员存在性、入口 `main` 存在性与签名——一律在 `EmitC` 之前以 `diag.Diagnostic`（带 `文件:行:列`）返回；② 99 处 `fmt.Errorf` 逐条判定：**可达** → 转诊断（与 RD2 商定码段）；**不可达**（sema 已保证）→ 改为 `panic` 断言或注释标明不变量，禁止再以用户可见文本出现；③ 补 `Set.has` 按元素类型分派、`Result` 返回类型名按 `resultName` 实算、类字段容器初值按 `ctype` 实参（顺带修 N-06/N-07/N-08） |
| 不做什么 | 不改 sema 的诊断段位；不为 `Float`/闭包/泛型伪造诊断码（保持「未支持」显式拒绝，等各自切片） |
| 验收 | `go test ./internal/codegen -run 'TestPrintArityRejected|TestUnsupportedConstructsRejected|TestEntryPointDiagnostics|TestResultBoolCompileMatchesInterp|TestContainerMembersCompileMatchesInterp' -count=1` 全绿；**且** `go test ./internal/codegen -count=1` 期间不得出现任何 `panic:` 行（可用 `-run` 全量 + `grep -c panic` 断言） |
| 当前红证据 | `p15.x` panic / `p16.x` 静默 / `p17.x` C 失败 / `p6.x` / `p8.x` / `p18.x` |
| 依赖 | 建议在 E4-01/E4-02 之后或并行（不共享文件：本卡集中在入口校验与 `containers_expr.go`/`classes.go`） |
| 预估 | 2 人日 |
| 证据路径 | `evidence/S1-codegen-neg/` |

**后续卡（不进前三，请 PJ 排期）**：`xn_arr_*_remove` 只释放被删元素（N-11，须与 N-14 泄漏同批）｜`mangle.go`（N-09）｜`LoadUnits` 入口 key 归一（N-10，0.2 人日，可搭车）｜`-Wall -Werror` + prelude 裁剪（N-17）｜`Build` 工程化（N-18）。

---

## 7. 待决策项（一次列全，我不自行定）

| ID | 事项 | 我的建议 | 决策人 |
|---|---|---|---|
| D-1 | `for-in` 遍历期间修改容器：快照还是实时（N-22，双路径已不一致） | 取快照（解释器现状 + 更易推理）；写进 S1 §6.7 | 董事会 + PM |
| D-2 | codegen 侧诊断码段位怎么分（CME-xxx？还是复用 sema 码） | 新增 `CMG-0xx` 段，语义为「语言面未支持」；与 `diagnostics.tsv`（v1.1.0 D2）一起登记 | 董事会 + CTO-2 |
| D-3 | `Result<Bool,*>`、`Result<String,*>` 等实例是否都属本期（现只 Int/Bool + String 错误） | 本期只补 Bool 修正；`Result<String,String>` 单开卡 | CEO1 |
| D-4 | `print(容器)` / 容器格式化是否进 Stage 1（解释器已有，编译器没有） | 进 | PM + CEO1 |
| D-5 | 判决 §4.3 矩阵「Result/try/defer ✅」是否降级（本轮实测三项有缺口） | 降为「部分：仅覆盖示例形态」 | 董事会 |
| D-6 | `str()`/插值的 `Double`/`Float`/元组/枚举/`toString()` 格式化归属 | 单开「格式化面」卡，本期显式拒绝 | PM |

---

## 8. 复核命令（全部可复制、可复算）

```bash
cd /Users/vjs/Desktop/XNull-Lang

# 0. 建探针工具（只写 $TMPDIR，不碰仓库）
export X=$TMPDIR/opencode/xnull
export R=/Users/vjs/Desktop/XNull-Lang/impl/runtime
mkdir -p $TMPDIR/opencode/rd3 && cd $TMPDIR/opencode/rd3
(cd /Users/vjs/Desktop/XNull-Lang/impl && go build -o "$X" ./cmd/xnull)

# 1. 基线全绿 + 覆盖率（本文件 72.4% 的来源）
cd /Users/vjs/Desktop/XNull-Lang/impl
go test ./internal/codegen/ -count=1 -cover -timeout 600s
go test ./internal/codegen/ -count=1 -coverprofile=$TMPDIR/opencode/rd3/cover.out -timeout 600s >/dev/null
go tool cover -func=$TMPDIR/opencode/rd3/cover.out | sort -k3 -n | head -25   # Build/borrowStr = 0.0%

# 2. 规模与错误面（3415 行 / 341 行 / 99 处）
cd /Users/vjs/Desktop/XNull-Lang/impl/internal/codegen
wc -l build.go classes.go classes_expr.go codegen.go containers.go containers_expr.go multifile.go strmethods.go types.go | tail -1
wc -l codegen_test.go multifile_test.go xdk_seed_test.go | tail -1
grep -c 'fmt.Errorf("codegen：' *.go | awk -F: '{s+=$2} END {print s}'
grep -n 'code[A-Z][A-Za-z]* *=' multifile.go

# 3. 缺陷复现模板（源码见 §9；编译路径 vs 解释路径）
cd /Users/vjs/Desktop/XNull-Lang
for f in p1 p2 p3 p6 p7 p15 p16 p17 p18 p20 p22; do
  echo "##### $f 编译"; "$X" run "$TMPDIR/opencode/rd3/$f.x" 2>&1 | head -4
  echo "----- $f 解释"; "$X" run --interp "$TMPDIR/opencode/rd3/$f.x" 2>&1 | head -4
done

# 4. -Wall -Werror 质量门（N-17）
"$X" build examples/hello.x -o "$TMPDIR/opencode/rd3/hello" >/dev/null 2>&1
cc -std=c11 -Wall -Wextra -Werror -I $R -O2 -o "$TMPDIR/opencode/rd3/hello_s" \
   "$TMPDIR/opencode/rd3/hello.c" $R/rt.c $R/rt_gc.c $R/rt_policy.c $R/rt_weak.c 2>&1 | head -8

# 5. xn_arr_*_remove 释放全数组（N-11）
"$X" build "$TMPDIR/opencode/rd3/p4.x" -o "$TMPDIR/opencode/rd3/p4bin" >/dev/null 2>&1
grep -n "xn_arr_s_remove" -A 8 "$TMPDIR/opencode/rd3/p4bin.c"

# 6. 确定性（DET-01，当前 PASS，作回归基线）
"$X" build examples/hello.x -o "$TMPDIR/opencode/rd3/h1" >/dev/null 2>&1
"$X" build examples/hello.x -o "$TMPDIR/opencode/rd3/h2" >/dev/null 2>&1
shasum "$TMPDIR/opencode/rd3/h1.c" "$TMPDIR/opencode/rd3/h2.c" | awk '{print $1}'   # 两行必须相同

# 7. 相对路径入口（N-10）
mkdir -p "$TMPDIR/opencode/rd3/sub" && cd "$TMPDIR/opencode/rd3/sub"
XNULL_RUNTIME=$R "$X" run ./main.x    # error[RES-106]: 无法读取入口文件 main.x

# 8. 只读自查（本会话唯一新增 = 本文件）
cd /Users/vjs/Desktop/XNull-Lang
git -c core.quotePath=false status --short --untracked-files=all -- impl/ | grep -v '^??' ; echo "(空即未改生产代码)"
```

---

## 9. 附录：探针源码（写到 `$TMPDIR/opencode/rd3/`，不进仓库）

<details><summary>p1.x　插值（N-01）</summary>

```x
static Int main() {
    Int total = 7;
    print($"value={total}")
    return 0
}
```
</details>

<details><summary>p2.x　嵌套 return 丢外层 defer（N-02）</summary>

```x
static Int f(Bool b) {
    defer print("outer-defer")
    if b {
        return 1
    }
    return 0
}
static Int main() {
    print(f(true))
    return 0
}
```
</details>

<details><summary>p3.x　break 丢 defer（N-03）／ p20.x　continue 丢 defer</summary>

```x
static Int main() {
    Int i = 0
    while i < 3 {
        defer print("loop-defer")
        i = i + 1
        if i == 2 {
            break
        }
    }
    print("after")
    return 0
}
```

```x
static Int main() {
    Int i = 0
    while i < 3 {
        defer print("d")
        i = i + 1
        continue
    }
    return 0
}
```
</details>

<details><summary>p4.x　List&lt;String&gt;.remove（N-11 生成代码取证）</summary>

```x
static Int main() {
    List<String> xs = ["a", "b", "c"]
    xs.remove(1)
    print(xs.length())
    print(xs.get(0))
    print(xs.get(1))
    return 0
}
```
</details>

<details><summary>p6.x　Set&lt;String&gt;.has（N-07）</summary>

```x
static Int main() {
    Set<String> s = ["x", "y"]
    print(s.has("x"))
    return 0
}
```
</details>

<details><summary>p7.x　str(Bool)（N-15）／ p11.x　print(容器)</summary>

```x
static Int main() {
    print(str(true))
    print(str(42))
    return 0
}
```

```x
static Int main() {
    Int[] xs = [1, 2]
    print(xs)
    return 0
}
```
</details>

<details><summary>p8.x　类字段 Set = []（N-08）</summary>

```x
class Box {
    Set<String> tags = [];
    Int n = 0;
}
static Int main() {
    Box b = new Box();
    print(b.n);
    return 0
}
```
</details>

<details><summary>p14.x　标识符撞名（N-09）</summary>

```x
class Wrap {
    Int hdr = 1;
    Int len = 2;
}
static Int main() {
    Int int = 3
    Int data = 4
    Wrap w = new Wrap();
    print(int + data + w.hdr + w.len)
    return 0
}
```
</details>

<details><summary>p15.x　print() 崩溃（N-04）／ p16.x　print(1,2) 静默（N-05）</summary>

```x
static Int main() {
    print()
    return 0
}
```

```x
static Int main() {
    print(1, 2)
    return 0
}
```
</details>

<details><summary>p17.x　Result&lt;Bool,String&gt;（N-06）</summary>

```x
static Result<Bool, String> ok(Bool b) {
    return Ok(b)
}
static Int main() {
    Result<Bool, String> r = ok(true)
    print(r.isOk())
    return 0
}
```
</details>

<details><summary>p18.x　缺 main（N-13）</summary>

```x
static Int helper() { return 1 }
static Int notmain() {
    print(helper())
    return 0
}
```
</details>

<details><summary>p22.x　for-in 期间 push（N-22，双路径不一致）</summary>

```x
static Int main() {
    List<Int> xs = [1, 2]
    for v in xs {
        if v == 1 {
            xs.push(3)
        }
        print(v)
    }
    return 0
}
```
</details>

<details><summary>sub/{main.x,helper.x}　相对路径入口（N-10）</summary>

```x
// sub/main.x
import helper
static Int main() {
    print(twice(3))
    return 0
}
```

```x
// sub/helper.x
static Int twice(Int n) { return n * 2 }
```
</details>

---

## 10. 声明

- 本文件是**只读盘点的技术产出**，不是门禁结论、不是任务卡、不是缺陷登记、不是排期；§3.2 的严重级为 RD3 初判，登记与定级归 CEO3/CEO1。
- 所有「实测」均可在 §8 命令下原样重跑；所有「仍存在」的判定都以本轮输出为准，不引用他人回执。
- 本轮**没有**修改 `impl/**`、规范母本、台账、缺陷表、他人文件；`git status -- impl/` 无新增改动（可自查，§8 命令 8）。
- 未复测：`codegen/ffi/**`（二司域）、`sema` 内部逻辑（只记录它在该放行的地方放行/该拒绝的地方没拒绝，归 RD2 复核）。
