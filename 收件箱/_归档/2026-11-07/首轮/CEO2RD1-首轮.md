# CEO2-RD1 首轮盘点（只读）：解释器求值 / 控制流 / 闭包

> **角色**：CEO2-RD1-解释器　**依据**：董事会判决 v1.6.0 第 2 条（二司编制）、第 5 条（首轮只读）
> **日期**：2026-11-07　**基线**：主仓 `main` @ `dfcf033`（S1-22 改名后）
> **域**：`impl/internal/interp/**`（写入需 worktree，本卡只读）
> **方法**：读代码 + 全量 `go test` + 在临时目录（仓库外）用 `interp.Run` 直连与 `xnull run --interp` 两条路径跑探针；未改任何生产代码、未 commit、未派工。
> **边界**：二司名义域为 S3/S5/S7；解释器目前**只承载 S1/S2 求值语义**，S3/S5/S7 能力为零（见 §1.6），因此本报告结论集中在 S1/S2，S3/S5/S7 的验收面归 RD2/RD3。

---

## 0. 一句话结论

- 解释器基线**全绿**：`go vet ./internal/interp/` 通过；`go test ./... -count=1` 全仓通过；interp 包 **28 个测试、语句覆盖 60.0%**。
- 但测试绿≠语义对：本轮核实 **7 项 P0 静默错误**（闭包 `try` 穿透、闭包 `break` 穿出、元组/引用相等恒 false、`===`/`!==` 未实现、闭包值调用面缺失、`Map.get` 缺失键 fatal）。
- **S3/S5/S7 在解释器里不存在**：无 ARC/`deinit` 时序、无 task/并发、无 FFI/xdk；这不是缺陷，是边界，但必须让董事会知道“运行时司”的验收不能拿解释器凑。
- 前 3 张卡：**C1 闭包边界与一等函数调用**（P0）、**C2 相等/同一性/比较语义**（P0）、**C3 容器求值契约**（P1）。
- 另有一处治理风险：现有 `TestMap`/`TestSet` **把非规范返回值断言成预期**（`Map.remove`、`Set.add/remove` 返回 Bool），修改前需 PM 定口径，避免“改实现导致测试变红”还是“改测试放水”说不清。

---

## 1. 现状

### 1.1 规模与测试基线

| 文件 | 行数 | 职责 |
|---|---:|---|
| `impl/internal/interp/interp.go` | 1008 | 值模型、Run、语句/表达式求值、算术与相等、函数调用 |
| `impl/internal/interp/values.go` | 621 | 容器/元组/闭包/`is`/`as`/成员方法/格式化 |
| `impl/internal/interp/objects.go` | 197 | 类实例、字段/方法查找、构造与成员读写 |
| `impl/internal/interp/*_test.go` | 717 | `interp_test` / `values_test` / `hard_test`，共 28 个测试 |

- `go test ./internal/interp/ -count=1 -cover` → `coverage: 60.0% of statements`。
- `go test ./... -count=1` → 全仓 9 个包全 `ok`。
- 测试集中在：基础算术/控制、Result/try、defer/errdefer、确定性、容器 happy path、字符串方法、闭包 happy path、`is`/`as`、`main` 两形态；**负向与边界覆盖薄**（见 §3）。

### 1.2 求值现状

| 子域 | 已实现 | 代码点 | 备注 |
|---|---|---|---|
| 值模型 | `vNull/Bool/Int/Float/Char/Str/Result/Arr/List/Map/Set/Tuple/Closure/Obj` | `interp.go:29-59` | 所有整数类型共用 `int64` 的 `vInt`（`Int` 规范是 32 位） |
| 字面量 | Int/Float/Char/Bool/null/String/插值 | `interp.go:556-586` | Float 用 `strconv` 近 64 位，无 32 位 `Float` 区分 |
| 算术/位运算 | 五则运算、位运算（与/或/异或/移位）、大小比较 | `interp.go:703-779` | Float 除零被当成 fatal；Char 不参与顺序比较（规范要求支持） |
| 相等 | 仅标量；`Bool/Int/Float/Char/Str` | `interp.go:816-836` | 元组、数组/List/Map/Set、对象、闭包一律返回 false；`===`/`!==` 无分支 |
| 逻辑/三元/`??` | 短路与惰性已实现且有测试 | `interp.go:660-681`, `631-635` | 与 §7.3 一致 |
| 类型运算 | `is` / `as` / `as?` | `values.go:189-258` | 只认内建类型名；类/协议恒 false（`a is A` 实测 false） |
| 容器 | T[]、List、Map、Set 的读写与成员 | `values.go:94-178`, `262-481` | Map 键规范化为可排序字符串（DET-01）；`Map.get` 缺失键 fatal；`List.remove` 丢返回值；`List.insert` 越界钳制 |
| 对象 | class 实例、字段、单继承方法查找 | `objects.go:70-197` | 仅主构造器；显式构造器不执行；字段初始化作用域不含 `self` 字段名；static/enum/struct/protocol 校验缺失 |
| 格式化 | `format`/`formatContainer` | `interp.go:105-131`, `values.go:589-621` | Map/Set 按键排序；闭包打印 `<closure>`；对象打印 `<Cls>` |

### 1.3 控制流现状

- **信号模型**：`ctrlReturn` / `ctrlBreak` / `ctrlContinue` / `ctrlErr` / `fatal` / `runtimeErr` 用 panic/recover 承载（`interp.go:133-148`）。
- **块级 defer**：`execBlock` 维护 `ditem` 栈，LIFO；`return Err` 与 `try` 传播执行 `defer`+`errdefer`，`break/continue` 只执行 `defer`，`fatal` 不执行（`interp.go:330-360`）。测试覆盖较好。
- **循环**：`while`/`do-while`/`for-in`（区间与容器）由 `loopBody` 消化本层 `break/continue`（`interp.go:426-476`, `530-552`）；`do-while` 的 `continue` 正确跳到条件。
- **switch**：按源码顺序求值 case，命中即退出，无贯穿；`break`（无标签）被 case 捕获（`interp.go:477-498`）。
- **标签**：解释器用单一 `in.label` 字段传递“下一个循环的标签”，`LabeledStmt` 设置后恢复（`interp.go:188`, `509-516`）；**switch 不消费带标签的 break**，`outer: switch { case 1: break outer }` 报“break/continue 出现在循环或 switch 之外”（实测），而规范明确允许 `break label` 指向 `switch`（S1:936）。
- **goto**：解析层有节点，解释器直接 `runtimeErr`（`interp.go:517-518`）；属已文档化的未实现边界。
- **`try`/`errdefer`**：`try` 失败抛 `ctrlErr`，穿过块时按错误路径执行清理，`call`/`callMethod` 在函数边界把它转成 `Result`（`interp.go:302-303`, `objects.go:146-149`）。错误路径测试较全（`hard_test.go`）。
- **`throw`**：fatal，不执行 defer，退出码 134（`interp.go:211-223`, `413-415`），测试覆盖。
- 已实测正确但无测试的点：switch case 内 defer、循环体内 defer、带标签 break 的跨块 defer、`errdefer` + `return Result变量`、`Result<void,E>`、嵌套 `try`、降序区间零次。

### 1.4 闭包现状

- 创建：`evalLambda` 直接捕获当前 `*scope`（引用捕获，天然共享 cell，符合 S1:1146-1149）；循环体每轮新建 scope，闭包捕获每轮独立绑定（符合 S1:898）。
- 调用：`callClosure` 新建子作用域，支持块体/单表达式体，恢复 `ctrlReturn`（`values.go:547-585`）。
- 具名函数当值：`IdentExpr` 包装为 `clov{top}`，按参数个数分派（`interp.go:599-602`, `values.go:548-563`）。
- **调用点限制**：`evalCall` 只接受 `IdentExpr` 或 `Member` 作为被调用者（`interp.go:838-948`）：
  - `f(...)`（局部闭包变量）可用；
  - `h.f(...)`（闭包存字段）走对象方法分派 → “该类型没有成员方法 f”；
  - `fs[0](...)`、`((Int x) -> x+1)(1)` → “非常量可调用表达式”；
  - `null` 闭包调用 → “未定义的函数”而不是 panic。
- **错误边界**：`callClosure` **不捕获 `ctrlErr`**，`try` 失败会一路穿到外层普通函数边界，表现为“外层函数提前返回 Err / main 直接结束”（实测 `clo_try2` 无任何输出）。
- **控制转移边界**：`callClosure` **不拦截 `ctrlBreak/ctrlContinue`**，闭包里的 `break` 会穿出到外层循环并静默终止循环（实测 `clo_break` 无输出、退出码 0）。
- **遮蔽**：`evalCall` 先查 `in.funcs` 再查局部闭包，导致局部闭包变量无法遮蔽同名顶层函数（实测输出 `2` 而非 `101`，`interp.go:909-918`）。
- **未验证**：闭包作为返回值（解析层不支持函数类型作返回类型，`static Int(Int) make(...)` 直接 SYN 报错）、闭包入容器（sema 把 `fn[]` 与 `Int(Int)[]` 判成不兼容）、递归局部闭包（interp 可跑，sema 以 RES-101 拒绝）。

### 1.5 测试现状（按域）

| 域 | 已有 | 缺口 |
|---|---|---|
| 算术/控制 | 基础算术、短路、三元、`??`、switch 基本 | Float 特殊值、Char 顺序、`===`、整数宽度 |
| Result/错误 | Ok/Err/try 传播、defer/errdefer LIFO、throw | 闭包内 try、try 在 main、Result 相等、Result<void> 值语义 |
| 容器 | Array/List/Map/Set 的 happy path、越界读、Map 键排序 | `Map.get` 缺失键、`List.remove` 返回值、`List.insert` 越界、赋值保型、键类型限制 |
| 闭包 | 创建/传参/捕获/具名函数当值 | 错误边界、控制转移、字段/元素/立即调用、遮蔽、null 调用 |
| 对象 | 无（objects.go 零测试） | 构造、字段初始化、继承、`is`、static、显式构造器 |
| 控制流 | 标签嵌套循环、switch break、defer 块退出 | `break label`→switch、switch 内 continue、标签泄漏、异常路径的 defer 顺序 |

### 1.6 二司域边界（S3/S5/S7）

| 规范 | 解释器现状 | 结论 |
|---|---|---|
| S3 内存 | Go GC 托管；注释明确“不做 ARC 时序模拟”，`deinit` 解析但不调用（`objects.go:2-7`） | 解释器**不用于** S3 验收；S3 由 RD2 + `impl/runtime` 承担 |
| S5 并发 | 无 task/async/await/spawn 的 AST 或求值；无调度 | 解释器零覆盖；归 RD3 |
| S7 FFI | `extern ... from` 解析层拒绝；无 FFI 调用路径 | 解释器零覆盖；归 RD3 / codegen.ffi |
| S6 XDK | `StringBuilder()` 等内建在 sema 即 RES-101 | 解释器零覆盖；归 XDK/codegen |
| S1/S2 求值 | 本报告主体 | RD1 的实际工作面 |

---

## 2. 已核实偏差（按优先级）

> 证据类型：**I** = 直接 `interp.Run`（绕过 sema）；**C** = `xnull run <file> --interp`（含 sema，用户可见路径）。所有探针在仓库外临时目录执行，源文件未入库。

### 2.1 P0（静默错误；程序不报错但结果错）

| ID | 实测现象 | 规范期望 | 规范 | 代码点 |
|---|---|---|---|---|
| EV-01 | 闭包内 `try` 失败，错误穿出闭包并把 `main` 一并结束，`after-call` 不打印、退出码 0 | 错误只从闭包返回，调用方继续执行（闭包返回 `Result`） | S1:1154, 1473 | `values.go:547-585`（未捕获 `ctrlErr`） |
| EV-02 | 闭包内 `break` 静默终止外层 `for`，无任何输出、退出码 0 | 控制转移不得跨函数/lambda 边界，应报错 | S1:936（标签同函数）、§6.9 | `values.go:547-585`（未拦截 `ctrlBreak/continue`） |
| EV-03 | `(Int,Int) a=(1,2); b=(1,2); a==b` → `false` | 元组 `==`/`!=` 逐元素比较 | S1:492, 1634（TUPLE-01） | `interp.go:816-836`（无 `vTuple` 分支） |
| EV-04 | `Int[] b=a; a==b` → `false`（同一句柄也 false） | 引用类型 `==` 默认按对象身份 | S1:489-490, 1048 | `interp.go:816-836`（容器直接落空） |
| EV-05 | `a === b` 对所有类型 → `运算 === 的操作数类型不符` | `===`/`!==` 严格同一性：值类型比值、引用比引用、`null===null` 为 true | S1:490, 1023 | `interp.go:688-699`, `703-779`（无分支） |
| EV-06 | 闭包存字段 `h.f(1)` → “没有成员方法”；`fs[0](1)` / `((Int x)->x+1)(1)` → “非常量可调用表达式”；`null` 闭包 → “未定义的函数” | 闭包可存字段/容器、字面量可立即调用、调用 null 闭包是 panic | S1:1158-1162 | `interp.go:838-948`（分派白名单） |
| EV-07 | `Map<String,Int>.get("z")` → `fatal: Map.get 键不存在`（退出 134） | `get` 返回 `V?`，键不存在返回 `null`，不 panic | S1:1343 | `values.go:397-403` |

### 2.2 P1（规范明确、影响面次之）

| ID | 实测现象 | 规范期望 | 规范 | 代码点 |
|---|---|---|---|---|
| EV-08 | `List.remove(0)` 返回 `null` | 删除并**返回被删元素** | S1:1319 | `values.go:375-382` |
| EV-09 | `List.insert(5, 9)` 到长度 2 的列表 → 不 panic，长度变 3 | 越界 panic（合法位置 `0..length`） | S1:1316 | `values.go:347-359`（钳制） |
| EV-10 | `List<Int> xs=[1]; xs=[2]; xs.push(3)` → “Array 没有成员方法 push” | 目标类型 `List<Int>` 的赋值应得到 List | S1:1314-1320 | `interp.go:962-1001`（赋值不做目标类型定向）、`values.go:516-543`（只处理声明） |
| EV-11 | `print(1.0/0.0)` → `fatal: 除零`，退出 134 | IEEE 754：除零产生 ±Inf/NaN，不 panic；NaN `==` 恒 false | S1:379-380 | `interp.go:717-722` |
| EV-12 | `'a' < 'b'` → `运算 < 的类型不符：Char < Char` | Char 支持 `< <= > >=`，按码点 | S1:387 | `interp.go:745-755`（只处理 Str/Int/Float） |
| EV-13 | `outer: switch 1 { case 1: break outer }` → “break/continue 出现在循环或 switch 之外” | `break label` 可指向循环或 switch | S1:936 | `interp.go:477-498`（switch 只捕获空标签） |
| EV-14 | 方法 `f(Int a){return 7}` 以 `f()` 调用 → 打印 `7`（缺参补 null、多参忽略） | 参数个数必须匹配；无匹配是错误 | S1:1179（7.10）、S2:281 | `objects.go:160-167`；`interp.go:296-318` 同样补 null |
| EV-15 | 显式构造器类：无参 `A(){x=5}` 后 `a.x` → `0`（构造器体不执行）；带参 `A(Int v)` → “没有带参构造器” | 显式构造器必须执行；`new` 按重载解析 | S2:714-730, 281 | `objects.go:70-122`（只认 `Primary`） |
| EV-16 | 方法内 `return x`（x 为字段）→ “未定义的名称：x”；字段初始化 `Int y = x+1` 同样失败 | 实例字段可非限定访问（局部遮蔽字段时才需 `self`） | S2:639, 803, 629-641 | `objects.go:138-171`（作用域只放 `self`） |
| EV-17 | `A a=new A(); a is A` → `false`（`a is Any` → true） | 引用类型 `is` 检查动态类型或协议实现 | S1:1106-1107 | `values.go:206-258`（只认内建名） |
| EV-18 | `main` 中 `Int v = try f()` 且 f 返回 Err：无输出、退出码 0 | `try` 不能用于 main；应编译错误；至少不能静默吞错 | S1:1477 | `interp.go:302-303`（不检查函数返回类型） |

### 2.3 P2（口径/已知边界/跨司）

| ID | 现象 | 说明 | 处置 |
|---|---|---|---|
| EV-19 | `switch 1.5 { case 1.5: ... }` 命中；`switch` 一个 Result 静默落 default | 规范禁止 Float/Result/元组作 switch 值；sema 未拦，interp 也不兜底 | 建议 sema 补；interp 可加防御性 `runtimeErr` |
| EV-20 | `Ok(1)==Ok(1)` 在 interp 直连时返回 false | 规范禁止 Result `==`；sema 已能报 TY-105，属双保险 | 仅要求 interp 不静默（可选） |
| EV-21 | `new Int[-1]` → runtimeErr，退出码 1 | 规范：负数是 panic（应为 134） | `values.go:167-178` |
| EV-22 | `Map.remove`/`Set.add`/`Set.remove` 返回 Bool | 规范只描述动作、未定义返回值；现有测试把 Bool 当预期 | **PM 定口径**；若按规范改 void，须同步 QA 测试 |
| EV-23 | `Map<Bool,Int>`、`Map<Char,Int>` 可构造并工作 | 规范键类型只允许 String/整数/简单枚举 | sema 主责；interp `canonKey` 可拒 |
| EV-24 | static 方法 `A.make()` → “未定义的名称：A”；简单枚举 `Color.Red` → 未定义；struct 无运行时 | 对象运行时未覆盖 S2 §3/§6/§8 | 作为 RD1 backlog，需与 M4.4b 排期 |
| EV-25 | `goto` 不支持 | impl/README 已列为后续切片 | 已知边界，不重复立项 |
| EV-26 | 局部闭包递归：interp 可跑，sema 报 RES-101 | 作用域“从声明处开始”是否含自身初始化式，口径待 PM | 口径项 |
| EV-27 | 局部 `Int(Int) f = ...` 与顶层 `f` 同名，调用走顶层函数 | 局部应遮蔽顶层（§5.8 只写成员解析，顶层遮蔽未明写） | 口径项 + 实现修正 |
| EV-28 | `impl/README.md`「解释器范围」仍称“不支持对象/容器/元组/闭包”，实际已支持 | 文档过期，误导新人和验收 | 文档卡，RD1 可写（README 属 impl） |
| EV-29 | `Int` 在 interp 与 codegen 均映射 64 位；规范 `Int` 为 32 位 | 双路径一致但不符合 S1 §2.2；影响溢出回绕与移位上限 | 跨司口径（一司+二司+董事会），不单独立 RD1 卡 |

---

## 3. 测试缺口（建议 11 组，均可在 `impl/internal/interp` 落盘）

> 测试文件按 v1.6.0 属 QA 写入域（需分派）；RD1 提供用例与期望值，不直接改测试文件。

| ID | 建议用例 | 覆盖点 | 现状 | 规范 | 依赖 |
|---|---|---|---|---|---|
| T-01 | `TestFloatSpecialValues` | `1.0/0.0`→+Inf、`0.0/0.0`→NaN、NaN `==` false/`!=` true、NaN `<=` false、Float 打印最短往返 | 🔴 除零 fatal | S1:379-380, 266 | C2 |
| T-02 | `TestEqualityMatrix` | 元组 `==`/`!=`/`===` 逐元素；数组/List/Map/Set/对象同一句柄 `==` true；不同句柄 false；`null===null` true；Char 相等；Result `==` 拒绝 | 🔴 恒 false / runtimeErr | S1:485-493, 1048-1049 | C2 |
| T-03 | `TestClosureErrorBoundary` | 闭包返回 `Result` 时 `try` 失败→闭包返回 Err、调用方继续；闭包内 `defer/errdefer` 执行；非 Result 闭包用 `try` 报错；main 用 `try` 报错 | 🔴 穿透/静默 | S1:1154, 1473-1477 | C1 |
| T-04 | `TestClosureControlTransferRejected` | 闭包内 `break`/`continue`/`return` 边界：return 正常返回；break/continue 报错且不影响外层循环 | 🔴 静默穿出 | S1:936, §6.9 | C1 |
| T-05 | `TestClosureCallSites` | 闭包存字段/数组/Map/元组后可调用；字面量立即调用；闭包作为返回值（需先解 parser 依赖）；局部闭包遮蔽顶层函数；`null` 闭包调用 fatal 134 | 🔴 全部不支持/遮蔽失效 | S1:1158-1162 | C1 + 一司 parser |
| T-06 | `TestContainerMemberContract` | `Map.get` 缺失→null；`getOr`；`List.remove` 返回元素；`List.insert` 越界 fatal；`Set.add/remove`、`Map.remove` 返回值口径；Map 键类型拒绝 Bool/Char | 🔴 多处不符；现有 `TestMap`/`TestSet` 断言 Bool | S1:1316-1348, 1360-1372 | C3 + PM |
| T-07 | `TestListAssignmentKeepsKind` | `xs=[2]` 后仍可 `push/get`；`xs +=`?（不支持）；字段赋 List 保持 List；`List<Int>` 参数传入后容器方法可用 | 🔴 退化为 Array | S1:1314 | C3 |
| T-08 | `TestLabelMatrix` | `break label`→switch；`continue label` 目标非循环报错；switch 内 `continue` 作用于外层循环；case 内 `break` 不退出循环；标签不得泄漏到内层循环 | 🟡 部分绿；`break label`→switch 红 | S1:928-938 | C1/C3 之外的独立小卡 |
| T-09 | `TestObjectRuntimeEdges` | 方法内非限定字段、字段初始化引用字段、显式无参/带参构造器、`is` 类/协议、static 方法、简单枚举、`super` | 🔴 objects.go 零测试，且多数不支持 | S2:629-641, 714-730, §8 | 对象运行时卡（backlog） |
| T-10 | `TestGreenRegressions`（锚定已正确行为） | switch/循环/带标签 break 内 defer 顺序；`errdefer`+`return Result变量`；`Result<void,E>`；嵌套 `try`；降序区间零次；循环变量重赋值不写回；闭包共享 cell | 🟢 行为对、无测试 | S1:898, 1473-1510 | 无 |
| T-11 | `TestArityDiagnostics` | 方法/构造器/`Ok`/`Err`/`print`/`str` 参数个数不符必须报错；`Ok(1,2)` 不得静默取第一个 | 🔴 方法静默补 null | S1:1179, S2:281 | C1/C3 |

---

## 4. 前 3 张建议卡

> 卡号暂用 `CEO2-RD1-C*`，由 PJ 换正式卡号；worktree 未建前不得写生产代码（v1.6.0 §4.4 / S0-28）。测试文件由 QA 落盘；RD1 只改 `impl/internal/interp/*.go` 生产代码。

### 卡 C1（P0）闭包边界与一等函数调用

**为什么先做**
- EV-01/02/06 是“程序不报错但结果错”的静默错误，最容易被双路径验收漏掉（两边都错就一致）。
- 闭包是 S1 §7.7 的强制语义，现有测试只覆盖 happy path，缺口最大。

**范围（生产代码）**
- `values.go:547-585`：`callClosure`
  1. 捕获 `ctrlErr` → 以 `Err` 作为闭包返回值（错误只从闭包返回）；
  2. 拦截 `ctrlBreak/ctrlContinue` → `runtimeErr`（不得穿出）；
  3. 保留 `ctrlReturn` 恢复；`fatal/runtimeErr` 继续上抛。
- `interp.go:296-321`：`call` 捕获 `ctrlErr` 时检查 `fn.Ret` 是否为 `Result`；否则 `runtimeErr`（覆盖 EV-18，`main` 不再静默吞错）。
- `interp.go:838-948`：`evalCall`
  4. 允许任意可求值为闭包的被调用者：`Paren(Lambda)`、`Index`、`TupleMember`、闭包字段；
  5. `Member` 分支若接收者字段是闭包，优先按闭包调用，不落入对象方法分派；
  6. 局部闭包变量优先于同名顶层函数（遮蔽修正，EV-27 口径确认后执行）；
  7. `null` 闭包调用 → `fatal`（134）。
- `objects.go:138-172`：`callMethod` 的 `ctrlErr` 处理与 `call` 对齐（避免同一语义两套）。

**验收**
- T-03/T-04/T-05/T-11 全绿；关键探针：
  - `clo_try2`（闭包返回 Result、`try` 失败）→ 打印 `after-call` + `true`，退出 0；
  - `clo_break` → 非零退出且不静默终止外层循环；
  - `clo_field` / `clo_array` / `clo_immediate` → 输出 `2` / `2` / `2`；
  - `clo_shadow` → `101`。
- 既有 28 个 interp 测试全绿；`go vet ./...`、`go test ./... -count=1` 全绿；examples 既有输出不变。
- 不引入输出格式变化（DET-01）。

**风险/依赖**
- 闭包目标返回类型在运行期不可知（无静态类型）；“非 Result 闭包用 try”只能靠 sema 报错，interp 兜底为 `runtimeErr`。若 PM 要求更强，需要 AST 携带目标类型（与一司协同）。
- 闭包作为返回值测试被 parser 挡住（`static Int(Int) make()` 解析失败），C1 的“返回闭包”验收项需一司先修函数类型返回位置；不影响其余 6 项。

### 卡 C2（P0）相等 / 同一性 / 比较语义

**为什么做**
- TUPLE-01 台账状态是“部分”，元组 `==` 恒 false 直接违反 S1 §2.8；`===`/`!==` 在语法里已存在但运行期未实现，codegen 也生成非法 C（实测 `a === b` 编译失败）。
- 这是双路径最容易出现“解释器与编译器各错一半”的区域，必须先用 interp 钉住语义。

**范围（生产代码）**
- `interp.go:660-700`：`evalBinary` 增加 `===` / `!==` 分派。
- `interp.go:816-836`：`valuesEqual` 重写为：
  - 标量：现有语义；
  - `vTuple`：长度相同且逐元素 `==`；
  - `vArr/vList/vMap/vSet/vObj/vClosure`：按句柄/底层指针比较（`a == a` 为 true，不同对象 false）；
  - `vResult`：`runtimeErr`（防御 sema 漏网）；
  - `null`：`null===null` true，`==` 同现状。
- `interp.go:703-813`：`arith`
  - `vChar` 顺序比较（`< <= > >=`）；
  - Float 除零改为 Inf/NaN（删除 `fatal{"除零"}`）；
  - NaN 比较：`< > <= >=` 直接按 IEEE 真假，不能经 `floatCmp` 归零；
  - 可选防御：`~` 仅整数、一元 `-/+` 仅数值（sema 已拦，防直连 interp）。
- `interp.go:688-691`：`==`/`!=` 对元组/容器复用新 `valuesEqual`；`switch` 自动受益。
- `values.go:497-512`：`valueEqual`（Set 去重）与新的标量/元组语义对齐，避免 Set 与 `==` 两套规则。

**验收**
- T-01/T-02 全绿；探针：
  - `tupleeq` → `true`、`true`（`a===b` 逐元素同值）；
  - `arrid` → `true`、`true`；
  - `charcmp` → `true`；
  - `floatdiv` → `Inf` / `NaN`，NaN `==` false；
  - `a !== b` 各类型可用。
- 既有测试全绿；Map/Set 排序输出不变。

**风险/依赖**
- String 的 `===`：规范把 String 当引用类型（对象句柄），但 interp 用 Go string 值。需 PM/CTO 确认是“内容比较”还是“句柄比较”；在确认前建议 `===` 与 `==` 同义并标注 TODO，不阻塞其他类型。
- codegen 当前不支持元组类型、且 `===` 生成非法 C；C2 只能先签 interp 单路径，双路径验收需一司 RD3 同步（跨司协调由 CEO2 做）。
- `Any` 装箱同一性（S1:519）当前无法表达；本轮不纳入，登记为 backlog。

### 卡 C3（P1）容器求值契约对齐（Map/List）

**为什么做**
- EV-07/08/09/10 都是规范写死、且现有测试没有覆盖（或被错误断言固化）的成员契约；容器是 examples 与 xdk 的基础面，错误会扩散到双路径与 XDK 验收。

**范围（生产代码）**
- `values.go:397-403`：`Map.get` 缺失键返回 `null`（`V?`），不 fatal；`getOr` 不变。
- `values.go:375-382`：`List.remove` 返回被删元素。
- `values.go:347-359`：`List.insert` 越界（`<0` 或 `>len`）→ `fatal`，不再钳制。
- `interp.go:962-1001`：赋值时按目标当前容器种类定向
  - 目标当前值为 `vList` 且 RHS 为 `vArr` → 转为 `vList`；
  - 目标当前值为 `vSet` 且 RHS 为 `vArr` → 按 Set 去重语义转换；
  - 字段赋值可用 `FieldDecl.Type` 做同类定向（`objects.go` 已有声明类型）。
- `values.go:167-178`：`new T[n]` 负数 → `fatal`（134），与“分配失败是 panic”一致。
- `values.go:27-42`：`canonKey` 拒绝 Bool/Char（键类型只允许 String/整数/简单枚举），与 sema 修复并行。
- **口径项（需 PM 裁决后执行）**：`Map.remove` / `Set.add` / `Set.remove` 的 Bool 返回值是保留为扩展还是改 void；现有 `TestMap`/`TestSet` 断言 Bool，若改 void 必须同步测试。

**验收**
- T-06/T-07 全绿；探针：
  - `map_get` → `true`、`9`（不再 fatal）；
  - `list_remove` → `1`、`1`；
  - `list_insert_oob` → 134；
  - `list_reassign` → `2`（仍可 push）；
  - `newarr_neg` → 134；
  - `Map<Bool,Int>` → 报错。
- 既有容器测试全绿（口径项确认后再动 TestMap/TestSet）；DET-01 排序不变。

**风险/依赖**
- `Map.get` 变 nullable 后，`Int? v = m.get("z")` 与 `??` 组合需要 T-06 一并覆盖；当前 `typeMatches` 对 `T?` 的支持可用。
- 若 PM 选择保留 Bool 返回值，必须在 `impl/README` 写明“实现扩展”，并在台账标“部分”，不能默认算 PASS。
- List 赋值定向是“最小修复”；完整方案是把声明类型带进 scope（与 sema 的类型定向统一），留给后续卡，不在 C3 扩围。

---

## 5. 依赖与待确认（请 CEO2/PJ/PM 一次拍板）

| # | 事项 | 需要谁 | 影响 |
|---:|---|---|---|
| 1 | 测试文件写权分派（T-01..T-11 由 QA1/QA2 落盘，还是 RD1 在 worktree 内写测试交 QA 复验） | CEO2 / PJ | C1–C3 的验收方式 |
| 2 | RD1 worktree 未建（v1.6.0 §4.4 / S0-28） | E6 → CEO2 | 未建前 C1–C3 不能开工 |
| 3 | `Map.remove` / `Set.add` / `Set.remove` 返回值：按规范 void，还是保留 Bool 扩展 | PM | C3 是否改现有 `TestMap`/`TestSet` |
| 4 | String 的 `===`：内容还是句柄 | PM / CTO | C2 的 String 分支 |
| 5 | 局部闭包递归（EV-26）与局部遮蔽顶层函数（EV-27）口径 | PM | C1 的两条子项 |
| 6 | `Int` 宽度：interp/codegen 均 64 位 vs S1 32 位 | 董事会 / 一司 / 二司 | 跨司口径，不在 RD1 单卡解决 |
| 7 | codegen 侧同步（元组类型、`===`、容器契约） | CEO1-RD3 / CEO2 协调 | C2/C3 双路径验收 |
| 8 | parser 函数类型返回位置（`static Int(Int) make()`） | 一司 RD1 | C1 “返回闭包”验收项 |
| 9 | `impl/README` 解释器范围过期（EV-28） | RD1（文档） | 新人/验收误导 |

---

## 6. 复现方式与边界声明

```bash
# 基线
cd impl && go vet ./internal/interp/ && go test ./... -count=1

# 解释器测试与覆盖
go test ./internal/interp/ -count=1 -cover

# 用户可见路径（含 sema）
cd impl && go build -o /tmp/xnull ./cmd/xnull
XNULL_RUNTIME=impl/runtime /tmp/xnull run <file.x> --interp
```

- 探针均在仓库外临时目录生成（`probe` 小模块：`xnull.dev/xnull/probe` + `replace` 到 `impl`），未写入仓库、未修改任何生产代码。
- 本卡只读：已核对 `git status`，未新增/修改仓库文件（本报告除外），未 commit、未 push、未派工、未触碰他人域文件。
- 代码行号以基线 `dfcf033` 为准；若后续合并导致漂移，以符号名（`callClosure`/`valuesEqual`/`evalCall` 等）为准。

---

**CEO2RD1 READY 收件箱/CEO2/CEO2RD1-首轮.md**
