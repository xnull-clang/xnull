# M1-ENTRY-01 独立验收报告（CEO3-QA2）

> **被测**：`592e7f775c97419a669b69171c600f1818998f54`（2026-11-07 03:31，`feat(entry): ENTRY-01 入口签名、退出码、初始化顺序与缺失/重复入口`）
> **基线**：父提交 `81ec33d`（已确认是 `main` 祖先）；`git rev-list --count 592e7f7 ^main` = 1
> **工作树**：`wt/e4-codegen`（`pod/e4-codegen`；HEAD `4d9ff0c` 只含 docs/evidence，代码取 `592e7f7` 归档）
> **环境**：macOS 26.5.2 / x86_64，go1.27.3，Apple clang 17.0.0
> **方法**：`git archive 592e7f7` → 临时目录副本 → `go build ./cmd/xnull` → 44 个独立用例 × 双路径 → 全量测试
> **边界**：未改生产代码、未 commit、未派工；`wt/e4-codegen` 与仓库工作区 `git status` 干净；所有产物在 `$TMPDIR/opencode/entry-qa`
> **日期**：2026-11-07

---

## 0. 结论

# **FAIL**

台账要点「入口与启动 / 两种签名 / 退出码 / 初始化顺序 / 缺失重复入口」中，**签名合法性与初始化失败语义不成立**，并有 1 处相对父提交的行为回归。E4 自检的「6/6 全绿」是其自选用例集的口径，未覆盖 §11.2 的全部约束。

| 判定依据 | 事实 | 证据 |
|---|---|---|
| **F-01** §11.3「初始化阶段 panic 时进程终止，入口不会被调用」在编译路径不成立 | `Int a = 1/0`：interp rc=134 且未运行 main；compiled **打印 `MAIN-SHOULD-NOT-RUN` 且 rc=0** | 用例 c3、c7b、c7c；见 §3.3 |
| **F-02** §11.2「入口必须是公开的」未强制 | `private static Int main()` / `protected static Int main()` 双路径均 rc=0 正常执行 | 用例 e10、e12 |
| **F-03** §11.2「入口不能是泛型函数」未强制 | `static Int main<Int>()` 双路径均 rc=0 正常执行 | 用例 e11 |
| **F-04** §11.2「其他 `main` 重载是普通函数」被违反，且为**回归** | `main()` + `main(Int)`：父提交 interp 输出 `entry` rc=0；本提交报「重复入口」rc=1 | 用例 e3；父/子对照 §4.2 |
| **F-05** 初始化语义在解释路径不成立（既有缺陷，非本卡引入） | `Int b = a + 1; Int a = 5` → interp「未定义的名称：a」；`b = read()` → interp「未定义的函数：read」。编译路径分别得到 `a=5 b=1`、`read a=1`，符合 §4.3 | 用例 c2、c5、c6 |

**通过面**：四种入口形态（void/Int × 无参/`String[]`）双路径一致；退出码映射 0/1/42/255/256→0/300→44/-1→255 双路径一致；顶层字段按声明顺序初始化（c1/c10）；缺失入口、同签名重复入口、非 `static`、返回 `String`/`Bool`、参数 `Int`/`String`/双参均被拒绝；`args` 长度与元素正确；全量 `go vet` + `go test ./...` 全绿；10 个示例双路径一致。

---

## 1. 验收要点 → 自写检查表

依据：台账 `XNull一致性用例台账-v1.0.0.md:31`（ENTRY-01 行）+ S1 §4.3、§10.4、§11.2、§11.3、§11.4。台账原文只写「两种 `main` 签名」，按 §11.2 展开为返回形态 × 参数形态，并把「非法签名」纳入（派工要求）。

| 编号 | 检查项 | 判据（条款） | 用例 | 结果 |
|---|---|---|---|---|
| C-01 | `void main()` 可运行、退出码 0 | §11.2 | a1 | PASS（双路径） |
| C-02 | `Int main()` 返回值即退出码 | §11.2 | a2 | PASS（双路径） |
| C-03 | `void main(String[] args)` 可运行 | §11.2 | a3 | PASS（双路径） |
| C-04 | `Int main(String[] args)` 可运行 | §11.2 | a4 | PASS（双路径） |
| C-05 | `final` 可选：加/不加 `final` 的 `String[]` 入口行为一致 | §11.2 | a3/a4/a5 | PASS（双路径） |
| C-06 | 退出码 0/1/42/255 直通；256→0、300→44、-1→255（平台截断） | §11.2 | b0…b_neg1 | PASS（双路径一致） |
| C-07 | 顶层字段按声明顺序先于入口初始化 | §4.3/§11.3 | c1/c10 | PASS（双路径） |
| C-08 | 初始化式可读未初始化字段（得零值，不报错） | §4.3 | c2 | **FAIL**（interp） |
| C-09 | 初始化式可调用函数；函数看到当前已完成状态 | §4.3 | c5/c6 | **FAIL**（interp） |
| C-10 | 初始化阶段 fatal → 终止进程、不调用入口 | §11.3/§10.4 | c3/c7b/c7c/c7e | **FAIL**（compiled） |
| C-11 | 缺失入口被拒绝（编译错误，不落 cc） | §11.4 | e1 | PASS（双路径） |
| C-12 | 同签名重复入口被拒绝 | §11.4 | e2 | PASS（双路径） |
| C-13 | 非匹配 `main` 重载是普通函数，不构成重复入口 | §11.2 | e3 | **FAIL**（双路径；父提交 interp 通过） |
| C-14 | 非 `static` 入口被拒绝 | §11.2 | e4 | PASS（双路径） |
| C-15 | 返回 `String`/`Bool` 被拒绝 | §11.2 | e5/e6 | PASS（双路径） |
| C-16 | 参数 `Int`/`String`/双参被拒绝 | §11.2 | e7/e8/e9 | PASS（双路径） |
| C-17 | 非公开入口（`private`/`protected`）被拒绝 | §11.2 | e10/e12 | **FAIL**（双路径） |
| C-18 | 泛型入口被拒绝 | §11.2 | e11 | **FAIL**（双路径） |
| C-19 | `args` 为运行时新数组，元素为参数、不含程序名 | §11.2 | d0/d2 | PASS（双路径；数量与内容一致） |
| C-20 | 非 `void` 入口缺 `return` 被拒绝 | §6.1 | e14 | PASS（双路径，DA-103） |
| C-21 | 既有示例双路径一致 | M1 门禁 | 9 示例 + multi | PASS（10/10） |
| C-22 | interp / cli / codegen 全量测试 | 回归 | `go test ./...` | PASS（全绿） |

---

## 2. 四形态与退出码（实测）

命令形态：`xnull run <case> --interp` 与 `xnull run <case>`。

| 用例 | 源码形态 | interp rc / out | compiled rc / out | 一致 |
|---|---|---|---|---|
| a1 | `static void main()` | 0 / `v0` | 0 / `v0` | 是 |
| a2 | `static Int main()` return 7 | 7 / `i0` | 7 / `i0` | 是 |
| a3 | `static void main(final String[] args)` | 0 / `va 0` | 0 / `va 0` | 是 |
| a4 | `static Int main(final String[] args)` return 5，传 2 参 | 5 / `ia 2` | 5 / `ia 2` | 是 |
| b0 | `return 0` | 0 | 0 | 是 |
| b1 | `return 1` | 1 | 1 | 是 |
| b42 | `return 42` | 42 | 42 | 是 |
| b255 | `return 255` | 255 | 255 | 是 |
| b256 | `return 256` | 0（截断） | 0（截断） | 是 |
| b300 | `return 300` | 44（截断） | 44（截断） | 是 |
| b_neg1 | `return -1` | 255 | 255 | 是 |

`args` 语义（d0/d2/ddash）：

| 运行 | interp | compiled |
|---|---|---|
| 无附加参数 | `n=0` | `n=0` |
| `alpha beta` | `n=2`，`alpha`、`beta` | 同左 |
| `-x beta` | `n=1`（`-x` 被 CLI 当标志丢弃） | 同左 |

注：`-x` 被丢弃属 CLI 参数消歧策略。§11.2 只说「元素是参数字符串」，未规定短横线参数是否透传；本轮**记为观察项，不作为失败依据**。

---

## 3. 初始化顺序

### 3.1 声明顺序 PASS

c1：`a = mark(1)`、`b = mark(a+1)` → 双路径 `init 1 / init 2 / main 2`。
c10：三段依赖链 `m10 / m20 / m30 / main 10,20,30,s` → 双路径一致。

### 3.2 前向引用与初始化调用函数（interp FAIL）

| 用例 | interp | compiled |
|---|---|---|
| c2 `Int b = a + 1` 在 `Int a = 5` 之前 | rc=1 `xnull: 未定义的名称：a` | rc=0 `a=5 b=1` |
| c5 `Int b = read()`，`read` 声明在字段之后 | rc=1 `xnull: 未定义的函数：read` | rc=0 `read a=1 / main b=2` |
| c6 `read()` 读尚未初始化的 `c` | rc=1 `xnull: 未定义的函数：read` | rc=0 `read c=0 / main c=9` |

§4.3 明确「初始化式读取尚未初始化的字段时，读到零值，不报错」「初始化式可以调用函数」；§3.3 声明顺序不影响可见性。**编译路径符合，解释路径不符合**，构成双路径分歧。
归因：父提交 `81ec33d` 上 interp 同样报错（compiled 当时不支持顶层字段），**属既有缺陷，非本卡引入**；但落在 ENTRY-01「初始化顺序正确」验收面内，需明确归属。

### 3.3 初始化 fatal（compiled FAIL，双路径分歧）

| 用例 | interp | compiled |
|---|---|---|
| c3 `Int a = 1 / 0` | rc=134，`fatal: 除零`，main 未运行 | **rc=0，打印 `MAIN-SHOULD-NOT-RUN`**；clang 告警 `division by zero is undefined [-Wdivision-by-zero]` |
| c7b `Int d = 0; Int a = 10/d;`（main 打印 a） | rc=134 | **rc=0，`a=0`** |
| c7c 同上 + main 打印 | rc=134 | **rc=0，`MAIN-SHOULD-NOT-RUN`** |
| c7e `String s="x"; Int d=s.length()-1; Int a=10/d`（运行期除零） | rc=134 | rc=255，main 未运行（**都终止，但退出码不同**） |

§11.3：「初始化阶段 panic 时，进程终止，入口不会被调用」；§10.4：除零属隐式 fatal。编译路径对可常量折叠的除零直接产出 0 并继续执行入口，**直接违反条款**；运行期除零虽终止，但退出码与解释路径不一致（134 vs 255）。
归因：`xn_init_globals()` 与顶层字段 C 生成是本提交新增（父提交对顶层字段直接报「暂未支持」），**属本卡新面**。

---

## 4. 入口拒绝矩阵

### 4.1 子提交实测（interp / compiled）

| 用例 | 期望（§11.2/§11.4） | interp | compiled | 判定 |
|---|---|---|---|---|
| e1 无 `main` | 拒绝 rc=1 | `找不到入口 main（缺失入口，§11.4）` | 同左 | PASS |
| e2 两个同签名 `main` | 拒绝 rc=1 | `重复入口 main（§11.4）` | 同左 | PASS |
| e3 `main()` + `main(Int)` | **允许**：非匹配重载是普通函数 | `重复入口 main` rc=1 | 同左 | **FAIL** |
| e4 `Int main()`（非 static） | 拒绝 | 签名不符 rc=1 | 同左 | PASS |
| e5 `static String main()` | 拒绝 | 签名不符 rc=1 | 同左 | PASS |
| e6 `static Bool main()` | 拒绝 | 签名不符 rc=1 | 同左 | PASS |
| e7 `static Int main(Int x)` | 拒绝 | 参数只能是 String[] rc=1 | 同左 | PASS |
| e8 `main(String[] a, Int b)` | 拒绝 | 同左 | 同左 | PASS |
| e9 `main(String a)` | 拒绝 | 同左 | 同左 | PASS |
| e10 `private static Int main()` | 拒绝（入口必须公开） | **rc=0 执行** | **rc=0 执行** | **FAIL** |
| e12 `protected static Int main()` | 拒绝 | **rc=0 执行，返回 3** | **rc=0 执行，返回 3** | **FAIL** |
| e13 `public static Int main()` | 允许 | rc=3 `pub` | rc=3 `pub` | PASS |
| e11 `static Int main<Int>()` | 拒绝（不能是泛型） | **rc=0 执行** | **rc=0 执行** | **FAIL** |
| e14 非 void 入口缺 return | 拒绝 | DA-103 rc=1 | DA-103 rc=1 | PASS |

### 4.2 e3 的父子对照（回归证据）

| 版本 | interp | compiled |
|---|---|---|
| 父 `81ec33d` | rc=0，输出 `entry`（重载被当普通函数） | rc=1「顶层函数 `main` 重载未支持」（既有 codegen 限制） |
| 子 `592e7f7` | rc=1「重复入口 main」 | rc=1「重复入口 main」 |

即：本提交把「同名函数一律算重复入口」，**收窄了解释器既有合法行为**。§11.2 的原文是「一个程序只能有一个**匹配签名**的入口；其他 `main` 重载是普通函数」，校验应当只对匹配签名的候选计数，而不是对 `Name == "main"` 计数。
`checkEntry`/`entryDeclOf` 的实现（`impl/internal/interp/interp.go` 的 `checkEntry`、`impl/internal/codegen/codegen.go:396-430`）均以「main 数量 > 1」直接拒绝。

---

## 5. 双路径与全量

### 5.1 既有示例（592e7f7）

9 个 `examples/*.x` + `examples/multi/main.x`：stdout 逐字节一致、退出码均 0 → **10/10 OK**。

### 5.2 独立用例双路径分歧汇总

| 分歧 | 用例 | interp | compiled |
|---|---|---|---|
| 初始化 fatal 是否终止 | c3/c7b/c7c | 终止（134），main 不运行 | 不终止（0），main 运行 |
| fatal 退出码 | c7e | 134 | 255 |
| 前向引用零值 | c2 | 报错 | `a=5 b=1` |
| 初始化调用函数 | c5/c6 | 报错 | 正常 |
| `str(Bool)` | c8/c9 | `true`/`false` | `1`/`0` |

`str(Bool)` 分歧在本提交之前即存在（父提交 c9 同样 `s=true` vs `s=1`），归 `BLD-01`/codegen 相邻面，**不作为本卡失败依据**，但应登记。

### 5.3 全量测试（592e7f7，干净归档副本）

```
go vet ./...                       → rc=0
go test ./... -count=1             → 全部 ok
  interp 10.155s · cli 93.927s · codegen 112.973s · codegen/ffi 41.204s
  devtool 12.261s · diag 11.189s · sema 13.748s · xfront 13.987s · xpd 14.885s
```

全绿不代表验收通过：本报告的 F-01—F-05 均未被现有测试覆盖（E4 自述「未测项 1：入口 visible 未覆盖」只列了其中一项）。

---

## 6. 缺陷清单

| # | 缺陷 | 条款 | 引入 | 严重度 | 证据 |
|---|---|---|---|---|---|
| D-01 | 初始化阶段除零在编译路径不终止，入口被调用（常量折叠为 0） | §11.3 / §10.4 | **本卡新面** | P1（阻断本卡） | c3/c7b/c7c |
| D-02 | `private` / `protected` 入口未被拒绝 | §11.2 | 既有，校验未覆盖 | P1（阻断本卡） | e10/e12 |
| D-03 | 泛型入口未被拒绝 | §11.2 | 既有，校验未覆盖 | P1（阻断本卡） | e11 |
| D-04 | 非匹配 `main` 重载被误判为重复入口；相对父提交为行为回归 | §11.2 | **本卡引入** | P1（阻断本卡） | e3 + §4.2 对照 |
| D-05 | 解释路径：初始化式前向引用/调用函数报「未定义」；双路径分歧 | §4.3 | 既有（父提交同） | P1（归属待裁） | c2/c5/c6 |
| D-06 | 初始化 fatal 退出码双路径不一致（134 vs 255） | §10.4 | 本卡新面（编译侧） | P2 | c7e |
| D-07 | `str(Bool)` 双路径输出不一致（`true` vs `1`） | §9.2 / BLD-01 | 既有 | P2 | c8/c9 |

复现：`$TMPDIR/opencode/entry-qa/run.sh`、`run2.sh`；父版本对照二进制在 `$TMPDIR/opencode/entry-qa/parent/xnull`。

---

## 7. 未覆盖 / 无法构造（如实登记）

| 项 | 原因 |
|---|---|
| 工程清单指定入口文件/入口包（§11.4 清单模式） | 工程配置规范未落地，`xnull.project` 解析不在本卡 |
| 非默认包 `main` 不作为入口（§11.2 末段） | 多包编译未支持（PKG-01 范围） |
| 默认参数 / 可变参数入口 | 语法层无该构造（`Param` 无默认值/可变字段） |
| `args` 修改不影响进程原始参数 | 进程参数在入口后不可观测，无黑盒判据 |
| 多文件重复入口（跨文件两个 `main`） | `LoadUnits` 需 import 关系，跨包暂不支持；单文件重复已覆盖 |
| 单例/静态字段初始化顺序（S2） | 不在 S1 ENTRY-01 |
| 顶层字段 `deinit` / 全局析构不保证 | §11.3 明确不保证，无判据 |

---

## 8. 放行条件（复验判据）

1. **D-01**：`Int a = 1/0`（常量与运行期两种形态）在编译路径必须终止、main 不产生任何 stdout；常量除零若前移到 sema 编译错误也应视为通过。
2. **D-02/D-03**：`private`/`protected`/泛型入口双路径返回非 0 且诊断点名 §11.2。
3. **D-04**：`main()` + `main(Int)` 双路径行为与父提交解释路径一致（入口为匹配签名者，重载为普通函数）；若 codegen 暂不支持重载，至少不得报「重复入口」。
4. **D-05**：明确归属。若归 ENTRY-01，则 c2/c5/c6 解释路径须符合 §4.3；若移出，需在台账 ENTRY-01 行注明移交锚点，避免「初始化顺序」验收口径悬空。
5. 复验时以干净归档副本重跑本报告 §2—§4 全部用例，并附 commit sha 与命令。

D-06/D-07 不阻断本卡，但需登记并在对应锚点闭环。

---

## 附录 A　用例与命令

```bash
T=$TMPDIR/opencode/entry-qa
git -C wt/e4-codegen archive 592e7f7 | tar -x -C $T/src
cd $T/src/impl && go build -o $T/xnull ./cmd/xnull
export XNULL_RUNTIME=$T/src/impl/runtime
bash $T/run.sh    # A/B/C/D/E 共 31 用例 × 双路径
bash $T/run2.sh   # 初始化 fatal / Bool 打印补充用例
```

**关键用例源码**

```x
// c3_init_fatal.x
Int a = 1 / 0
static Int main() { print("MAIN-SHOULD-NOT-RUN") return 0 }

// c7e_runtime_divzero.x（运行期除零）
String s = "x"
Int d = s.length() - 1
Int a = 10 / d
static Int main() { print("MAIN-SHOULD-NOT-RUN a=" + str(a)) return 0 }

// c2_forward_zero.x
Int b = a + 1
Int a = 5
static Int main() { print("a=" + str(a) + " b=" + str(b)) return 0 }

// e3_dup_overload.x（§11.2 允许）
static Int main() { print("entry") return 0 }
static Int main(Int x) { return x + 1 }

// e10_private_main.x / e12_protected_main.x
private static Int main() { return 0 }
protected static Int main() { return 3 }

// e11_generic_main.x
static Int main<Int>() { return 0 }
```

**父版本对照**

```bash
git -C wt/e4-codegen archive 81ec33d | tar -x -C $T/parent/src
cd $T/parent/src/impl && go build -o $T/parent/xnull ./cmd/xnull
XNULL_RUNTIME=$T/parent/src/impl/runtime $T/parent/xnull run $T/cases/e3_dup_overload.x --interp
# → rc=0，输出 entry
```
