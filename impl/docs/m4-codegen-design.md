# M4 前置设计：XNull → C 代码生成架构（impl/docs/m4-codegen-design.md）

> 编制：运行时侧（C 侧）　日期：2026-11-06
> 性质：M4.1–M4.3 的实现设计输入。**M4 正式实现由编译器侧承担**，本文档 + `impl/docs/runtime-contract.md` 是运行时侧与编译器侧的协调界面。
> 对齐依据：`impl/runtime/README.md`（M3 冻结契约）、`impl/runtime/rt.h`（值模型与生命周期合同）、
> `impl/internal/sema/policy.go`（Strategy 冻结结构）、S1 §10（错误处理）、S2 §15（策略判定）、S3（内存管理）、S8（工程配置）。

## 0. 目标与完成定义（对齐实施计划）

- M4.1 代码生成：XNull → C，替代解释执行的正式路径；
- M4.2 `xnull build` 端到端：一个完整程序 → C → 编译 → 可执行 → 运行；
- M4.3 解释器降级为调试模式（`--interp`），正式路径走编译；
- **验收**：examples 三示例经编译路径运行，输出与解释器**逐字节一致**；DET-01 确定性在编译路径同样成立（同一源程序 + 同一编译器版本 → 逐字节相同的 C 输出与相同运行结果）。

## 1. 总体架构

### 1.1 管线

```
.x 源文件
  → xfront（解析，已有）
  → sema（名称解析/确定赋值/类型检查/策略判定，已有）
  → codegen（新增包 internal/codegen）→ 每编译单元一个 <unit>.c
  → cc 驱动（cc -std=c11 -O2 -Wall）+ 运行时静态库（rt*.c 预编译缓存）
  → target/<name> 可执行
```

- codegen 只消费 **sema 产物**（类型已检查、策略已判定、确定赋值已通过），不做语义再判定；
- 诊断全部由前端/sema 产生，codegen 不新增诊断码段位（v1）；codegen 失败视为编译器内部错误（BUG 段位，v1 不触发）；
- 解释器与 codegen 共享 xfront AST 与 sema 结果，保证 `--interp` 与编译路径语义同源。

### 1.2 模块划分（internal/codegen）

| 文件 | 职责 |
| --- | --- |
| `codegen.go` | 入口：单元级生成，管线组装 |
| `emit_stmt.go` | 语句 → C 语句映射 |
| `emit_expr.go` | 表达式 → C 表达式映射 + 临时变量提升 |
| `emit_type.go` | XNull 类型 → C 类型映射（标量/堆指针/struct 值/Result/元组/可选） |
| `emit_defer.go` | defer/errdefer 帧与块出口展开 |
| `emit_rc.go` | ARC 插入（retain/release/deinit 生成）与 escape 分类回填 |
| `mangle.go` | 命名映射（XNull 名 → C 标识符，确定性、可逆注释） |

## 2. 值表示（与 rt.h / Strategy 判定对齐）

### 2.1 标量

| XNull | C 表示 | 备注 |
| --- | --- | --- |
| `Int` | `int64_t` | S1 §2 整数语义 |
| `Double` | `double` | |
| `Bool` | `bool` | |
| `Char` | `uint32_t` | Unicode 标量值（§1.3 `\u{…}`） |
| 枚举（简单） | `int32_t` 常量 | 行 3：内联、无分配；switch 直映射 C switch |

### 2.2 堆引用（行 2/4/9：ARC 与 GC）

引用类型（String、类实例、数组/List/Map/Set、闭包、数据枚举项）统一表示为 `rt_object*` 指针，
头部即 rt.h 的 `rt_header`（种类/描述符/原子计数/终结标志/弱槽），载荷按类型布局：

- **ARC 类**（判定行 9）与 **GC 类**（行 5/6、数据枚举行 4）：分配时按 Strategy 选择 `rt_alloc_arc` / `rt_alloc_gc` 路径；`rt_policy_input.escape` 由 codegen 回填（对象级逃逸分类 none/return/other，§15.2——**这是 M2.5.2 预留字段在 M4.1 的兑现点**）；
- **String**：直接使用 `rt_string`（rt.h 已有；`len` 权威、NUL 仅为 FFI 便利）；
- **闭包**：`rt_closure` = 头 + 函数指针 + 捕获结构体（捕获引用字段按 ARC 计数；struct 值捕获按行 8 复制）；
- **容器**：`rt_array<T>`（头 + 长度 + 元素数组；元素为引用类型时每个槽位是一个强引用，deinit/scan 逐槽处理）、List/Map/Set 以 rt_array + 哈希结构组合实现（M4.1 只需支撑示例与台账已 PASS 面）。

### 2.3 值类型（行 8：struct 栈候选）

- struct 值 → 内联 C `struct xn_s_<Name>`，栈分配或字段内联，复制 = 逐字段浅复制（值语义 §15.2）；
- 仅当 escape 分类为 none 才栈分配；return/other 归 ARC 堆分配（保守正确优先，优化挂后置切片）；
- struct 字段类型递归展开；含引用字段的 struct 由编译器生成 `deinit` 与 `scan` 钩子，注册进 `rt_type` 描述符。

### 2.4 复合

- `Result<T,E>` → `struct xn_result_<T>_<E> { int tag; /*0=ok,1=err*/ union { T ok; E err; } }`；
  T/E 为引用类型时 union 成员是强引用——**ok/err 两态互斥由 tag 保证，deinit 只释放 tag 所指一侧**；
- 元组 → `struct xn_tuple_n { T0 _0; T1 _1; ... }`（值语义，`.0/.1` 直映射字段）；
- `T?`（引用类型）→ 裸指针 + `NULL` 即 none；`T?`（值类型）→ `struct { bool present; T val; }`；
- 函数类型 → 闭包堆对象。

### 2.5 命名映射（mangle）

- 顶层函数：`xn_<单元名>_<函数名>`；类型：`xn_t_<Name>`；类型成员函数：`xn_t_<Name>_<method>`；
- 局部临时：`xn_tmp<N>`；块出口标签：`xn_exit_<N>`；函数统一返回出口：`xn_ret`；
- 与 C 关键字/XNull 保留名冲突时追加 `_x`；映射为纯函数（DET-01：同一声明 → 同一 C 名）。

## 3. 语句/表达式映射策略

### 3.1 语句直映射

| XNull | C 形态 |
| --- | --- |
| 块 `{ ... }` | `{ ... }` 作用域块；含 defer 时加块出口展开（§5） |
| `if` / `else if` | `if (...) { ... } else if ...`（条件为 C 表达式；无括号差异仅语法层） |
| `while` / `do-while` | `while (...)` / `do { } while (...)` |
| `for-in` 区间 | `for (int64_t i = lo; i < hi; i++)`（含步长） |
| `for-in` 容器 | String/数组/List 展开为索引循环；Map/Set 用迭代器临时（v1：`xn_iter<N>` 状态机内联展开，不引入运行时迭代器 API） |
| `switch` | 简单枚举/整数主值 → C `switch`；含字符串/元组/数据枚举绑定 → if-else 链 + tag 分派；穷尽性已由 sema 保证 |
| `return` | 先执行 defer 帧展开（§5）→ `goto xn_ret`（函数有 Result/引用返回时经返回槽） |
| `break` / `continue` / `label` / `goto` | 直映射；跨 defer 块的跳转同样过块出口 |
| 局部声明 | 声明 + 初始化；引用类型初始化即持有（§4.2） |

### 3.2 表达式：临时变量提升

原则：**副作用与生命周期需要语句位次的子表达式提升为临时**。

- 触发提升：字符串拼接、插值串、容器字面量、闭包字面量、`new`、`try`、函数调用（返回引用类型需持有）、短路求值中含调用的分支；
- 提升形态：`int64_t xn_tmp1 = ...;`（标量）/ `rt_string *xn_tmp2 = ...;`（引用，声明即持有点）；
- 求值顺序严格左→右（S1 §7.2 与解释器一致；这是与解释器逐字节一致的前提之一）；
- 短路：`&&`/`||`/`??` 直映射 C 短路；`??` 对可选值类型展开为 `xn_tmp.present ? xn_tmp.val : default`；
- 字符串拼接 `a + b` → `rt_string_concat(a, b)`（新运行时 API，见 §6）；插值串 → 逐段 `str()` 转换 + concat 链，静态段一次构造；
- `str(x)` → 按静态类型分派：Int→`rt_str_from_int`、Double→`rt_str_from_double`、Bool→`rt_str_from_bool`、String→retain、容器→`rt_str_from_container`（复用解释器 `formatContainer` 的逐字节输出格式）。

### 3.3 引用计数插入规则（ARC 面）

1. 局部声明初始化：源引用 retain（+1）；
2. 赋值：新值 retain → 旧值 release（顺序：先持新后放旧，防自赋值悬挂）；
3. 传参：实参 retain（被调方拥有自己的引用）；
4. 返回：返回值 retain 移交调用方；
5. 作用域退出（块出口/函数出口）：局部引用变量逆序 release；
6. 字段访问不转移所有权（`obj.f` 读为借用）；
7. 编译器生成 `deinit`：字段逆序 release；struct 值字段递归调其 deinit；
8. GC 字段不 retain/release，由 scan 钩子枚举（rt.h scan 合同）。

优化（CSE 掉冗余 retain/release）不进 v1；确定性优先。

## 4. 错误传播与 defer/errdefer 的 C 层方案（S1 §10）

### 4.1 函数上下文

每个返回 `Result` 或含 defer 的函数生成函数级上下文（栈变量，非堆）：

```c
/* 编译器生成，非运行时 API */
xn_result_Int_String xn_ret_slot;   /* 统一返回槽 */
int xn_err_active = 0;              /* 错误传播中标志（errdefer 触发条件） */
```

### 4.2 try 展开（§10.2）

`Int v = try double(n)` 展开为：

```c
xn_result_Int_String xn_tmp1 = xn_double(n);
if (xn_tmp1.tag == 1) {            /* err */
    xn_err_active = 1;
    xn_ret_slot = xn_tmp1;         /* err 值移交（所有权转移，不 retain） */
    goto xn_exit_fn;               /* 先展开 defer 帧（LIFO），再 goto xn_ret */
}
int64_t v = xn_tmp1.ok;
```

错误路径**单出口**（`xn_exit_fn`）保证：errdefer 判定一次、defer LIFO 一次、所有权移交一次。

### 4.3 defer 帧的块级展开（推荐方案）

编译期已知每个块的 defer 个数，**静态展开、不用运行时栈**：

- 每个含 defer 的块生成唯一出口标签 `xn_exit_<N>`；块内一切提前退出（return、try 传播、break/continue 出块）先 `goto xn_exit_<N>`；
- 出口处按 LIFO 顺序内联各清理体（清理体已由规范限制为无 return/throw 的语句，§10.3，sema 侧校验）；
- `defer` 条目无条件执行；`errdefer` 条目包一层 `if (xn_err_active) { ... }`；
- 函数出口 `xn_ret`：展开函数级 defer 帧（最外层块）→ `return xn_ret_slot;`；
- defer 体内声明的临时变量提升到块首（C 的声明位置约束）。

示例（defer-cleanup.x 的 work()）：

```c
static int32_t xn_work(void) {
    int32_t xn_ret_val = 0;
    /* block: function body — defer: cleanup2, cleanup1 */
    xn_print_str(rt_string_from_c("A"));
    { /* if true 块：defer: inner cleanup */
        xn_print_str(rt_string_from_c("B"));
        xn_print_str(rt_string_from_c("C"));
        xn_exit_1:
        xn_print_str(rt_string_from_c("inner cleanup"));   /* LIFO #3 */
    }
    xn_print_str(rt_string_from_c("D"));
    xn_ret_val = 0;
    goto xn_exit_fn;
    xn_exit_fn:
    xn_print_str(rt_string_from_c("cleanup 2"));           /* LIFO #2 */
    xn_print_str(rt_string_from_c("cleanup 1"));           /* LIFO #1 */
    return xn_ret_val;
}
```

（实际生成中 if 块 false 分支要绕过 `xn_exit_1` 标签直达块后——编译器负责标签可达性；标签仅作锚点，控制流由 goto 补全。）

### 4.4 throw fatal 与终结链交互（S1 §10.3–10.4、S3 §14/§15）

- `throw fatal` → `rt_fatal("...")`（rt.h 已有；宿主处理器可接管，默认 abort）——不进入 Result 通道，defer 帧不展开（进程终止语义）；
- 复活检测、终结链 panic 等 S3 硬语义同样走 `rt_fatal`（M3.4 已落地），编译器不拦截；
- errdefer 与 throw fatal 无交互（fatal 不算"错误返回"，语义按 S1 §10.4：进程终止优先）。

## 5. `xnull build` CLI 设计（S8 工程纪律）

### 5.1 命令面

```
xnull build [file.x | 工程目录]     # 默认 .；产出 target/<name>
xnull run   [file.x | 工程目录]     # build + 执行（M4.3 起为编译路径）
xnull build --emit c                # 只产出 C 源到 target/gen/，不编译（调试/审计用）
xnull run --interp [file.x]        # 强制解释器（M4.3 起为调试模式）
```

- 现有 `test` / `lock` / `fmt` 子命令不变；`--emit ast` 等既有调试旗标不变；
- 单文件模式（examples 场景）：一个 .x 直接编译；工程模式按 S8 目录纪律（src/main/...）。

### 5.2 构建缓存与工具链

- 产物：`target/gen/<unit>.c` → `target/obj/<unit>.o` → `target/<name>`；
- 运行时库：`impl/runtime/rt*.c` 首次编译为 `target/obj/libxrt.a` 缓存（内容哈希键控，runtime 源变更即重编）；
- cc 探测顺序：`CC` 环境变量 → `cc` → `clang` → `gcc`；旗标 `-std=c11 -O2 -Wall`（与 M3 验收基线一致）；
- 禁网、禁环境读取（S8 §5 纪律对构建工具链同样适用）；`xnull.lock` 与退出码 0/1/2/130 合同不变（S8 §5.1）；
- 确定性（DET-01）：codegen 输出按声明排序、临时变量编号按遍历顺序——同一源程序两次 build 的 C 产物逐字节一致（测试断言项）。

### 5.3 诊断与兼容

- 诊断格式/段位不变（前端产生）；`--interp` 保留为调试路径（M4.3），解释器与编译器输出逐字节一致由三示例 + 台账可执行用例锚定。

## 6. 对运行时的新增 API 需求（提案 → runtime-contract.md，编译器侧评审）

rt.h 现有合同（retain/release/rt_string/fatal/weak/policy）**不动**；M4.1 需要 codegen 消费面的增补：

| 提案 API | 用途 | 备注 |
| --- | --- | --- |
| `rt_string_concat(a, b)` | `+` 拼接 | 新串持 1，调用方规则按 §3.3 |
| `rt_str_from_int / _double / _bool` | `str()` 分派 | 输出格式与解释器 `formatValue` 逐字节一致 |
| `rt_str_from_container` | 容器 print/str | `[1, 2]` / `{k: v}` 等格式锚定解释器 |
| `rt_array_new(elem_type, len)` / `rt_array_get / set` | 数组 | 元素类型描述符进 rt_type |
| `rt_closure_new(fn, captures)` | 闭包 | 捕获结构由 codegen 布局 |
| `rt_print(str)` | `print()` | stdout + `\n`；实现即 `fwrite` + 换行 |
| `rt_result_*` 辅助（视实现取舍） | Result 构造可全在 codegen 内联 | v1 倾向内联，不进运行时 |

**字符串与容器堆表示是 M3.4 收口时已声明的 M4.1 消费面**（runtime/README 子切片表），此表即其落地清单。新增 API 一律走 runtime-contract.md 评审后进 rt.h，codegen 不绕过运行时自管堆内存。

## 7. 三示例的预期 C 输出形态

### 7.1 hello.x → hello.c（骨架）

```c
#include "xrt.h"   /* rt.h + codegen 便利层的单元一 umbrella（提案名） */

static int32_t xn_main(void) {
    rt_string *xn_tmp1 = rt_string_from_c("hello, XNull");
    rt_print(xn_tmp1); rt_release(xn_tmp1);
    rt_string *xn_tmp2 = rt_string_concat(rt_string_from_c("1 + 2 = "),
                                          rt_str_from_int(3));
    rt_print(xn_tmp2); rt_release(xn_tmp2);
    return 0;
}
int main(void) { return xn_main(); }   /* 入口垫片：Int main() 退出码直通 */
```

### 7.2 result-try.x → 关键形态

- `double`/`run` 返回 `xn_result_Int_String`（tag + union：`int64_t ok` / `rt_string *err`）；
- `try double(n)` → §4.2 五行展开；err 字符串所有权随 slot 移交；
- `ok.isOk()` → `xn_result_tag(...) == 0`；`unwrapOr(0)` → `tag ? xn_tmp.err : 0` 形态的条件表达式（err 串在 `bad` 作用域结束时 release）；
- `"negative: " + str(n)` → concat 链 + `rt_str_from_int`。

### 7.3 defer-cleanup.x → 关键形态

- §4.3 静态 LIFO 展开：work() 四个清理体按 `inner cleanup → cleanup 2 → cleanup 1` 排布；
- run() 的 errdefer：

```c
static xn_result_Int_String xn_run(int64_t n) {
    xn_result_Int_String xn_ret_slot; int xn_err_active = 0;
    /* defer: "defer: run exits"；errdefer: "errdefer: error path" */
    xn_result_Int_String xn_tmp1 = xn_maybe(n);
    if (xn_tmp1.tag == 1) { xn_err_active = 1; xn_ret_slot = xn_tmp1; goto xn_exit_fn; }
    ...
    xn_exit_fn:
    if (xn_err_active) { rt_print(rt_string_from_c("errdefer: error path")); }
    rt_print(rt_string_from_c("defer: run exits"));
    return xn_ret_slot;
}
```

- 三示例的逐字节输出比对是 M4 完成定义的第一验收组。

## 8. 实现切片建议（供编译器侧排期参考）

| 切片 | 内容 | 验收 |
| --- | --- | --- |
| M4.1a | codegen 骨架 + 标量/String/print + hello.x 编译路径 | hello 输出与解释器逐字节一致 |
| M4.1b | ARC 插入 + struct 值 + Result/try/defer/errdefer | result-try、defer-cleanup 逐字节一致；-O2 -Werror 零缺陷 |
| M4.1c | escape 分类回填 rt_policy_input.escape + 容器面 | policy CLI 输出含 escape 字段且两次一致 |
| M4.2 | build CLI + 缓存 + libxrt + 入口垫片 | 端到端可执行；退出码合同；C 产物确定性断言 |
| M4.3 | --interp 降级 + 正式路径切换 | 默认 run/build 走编译；文档与 usage 更新 |

## 9. 风险与开放点（经变更单报编译器侧 / 项目侧）

1. **标签出口展开的正确性**：块出口标签在 C 里的可达性（如 §4.3 注）需要 codegen 生成"绕行 goto"——实现时以解释器输出为金标准逐用例锚定；
2. **容器/Map/Set 完整面**：v1 只支撑台账已 PASS 面与三示例；`Map` 迭代顺序的确定性（DET-01）要求 codegen 与解释器同一排序键（canonKey 语义平移）；
3. **panic 与 unwind 边界**：C 无异常；S1 §10 若未来引入可恢复 throw（非 Result），需要 setjmp/longjmp 方案另立设计——v1 不做；
4. **runtime-contract.md 的维护权**：M3 冻结部分变更须编译器侧发起；M4 提案部分（§6）变更由运行时侧发起、编译器侧消费评审。
