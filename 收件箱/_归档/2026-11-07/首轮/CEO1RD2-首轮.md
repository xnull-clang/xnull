# CEO1-RD2 首轮盘点：类型 / 对象 / 泛型（只读）

> **角色：CEO1-RD2-语义**（一司·编译器）　**依据：董事会判决 v1.6.0 第 2/5 条**
> **域：`impl/internal/sema/**`**　**日期：2026-11-07**
> **性质：只读盘点。未改生产代码、未 commit、未派工、未触碰他人文件。**
> **基线：`main` @ `dfcf033`；`git status --short impl` 为空。**
> **方法：通读 6 个生产文件 2,900 行 + 6 个测试文件 1,122 行；`go test -cover` 实测 75.7%；临时构建 `xnull` 到 `$TMPDIR`，用 40+ 个 `.x` 反例探针实测（探针全部在临时目录，未写入仓库）。**

---

## 0. 结论（先看这六条）

1. **三遍架构在，但没有一遍覆盖"方法体"的全部语义**：名称解析与确定赋值只遍历 `TopFunc`（`impl/internal/sema/sema.go:72-86`），class/struct/enum 的方法体与构造器体只进类型检查遍。方法内**未定义名、同层重复声明、可能未赋值读取、非 void 缺返回**全部静默通过（E10）。类型不匹配在方法体内是能查的（`aa1` 实测报 TY-101），所以缺口精确落在 RES/DA 两遍，不是"整段没做"。
2. **可赋值性缺 §2.6 的一半规则**：子类型、协议实现、引用根 `Object`、泛型方差全无（`impl/internal/sema/ty.go:117-170`）。后果是**误报合法程序**：`B → A`、`C → P`、`String → Object` 全部被拒（E01–E03）。`status.tsv:12` 把 TYPE-01 标 PASS，与实证不符；我不改状态，只登记。
3. **泛型只到"能解析、类型串能拼"**：类型参数不进名称空间；调用不做实参替换/推断，形参按字面 `T` 比较，合法调用被拒（E07）；泛型结构体声明被值字段检查误杀（E08）；型变 `out/in` 在解析层被丢弃（`impl/internal/xfront/types.go:207-227`），语义层已无从检查。GEN-01 标"未实现"（`status.tsv:14`）是准确的，但"泛型类能写"不等于"泛型可用"。
4. **类型位置合法性是最大空白**：未知类型名、未知 `is`/`as` 目标、泛型实参数量/`void`、XDK 符号出现在参数/返回/字段位置，全部静默（E09/E16）。拼写错误不会在编译期暴露。
5. **策略判定有 2 处输入错误**：`String`/`Text`/`Bytes`/`StringBuilder` 被当值字段（`impl/internal/sema/policy.go:85-88`），含 `String` 字段的类被判行 8 栈候选（应为行 9 ARC）；`static` 字段参与实例判定，`static Any` 把整个类推入 GC（E17）。`policy.go` 头注释已声明接口冻结供 M3.2 消费，必须在消费前修。
6. **测试面**：34 个测试函数、75.7% 语句覆盖；`methodRet`/`elemTypeOf`/`isTypeParam` 三个关键函数 **0% 覆盖**；DA-101 每处实际输出**两条**（`assign.go:97-101` 双遍），`expectCode` 只判"存在"掩盖了重复与 0 行号问题（E13/E14）。

---

## 1. 盘点基数

| 文件 | 生产行 | 测试行 | 职责 |
|---|---:|---:|---|
| `sema.go` | 300 | 169 | 入口、名称解析（M2-A）、三遍编排 |
| `assign.go` | 402 | 165 | 确定赋值与返回路径（M2-B） |
| `ty.go` | 924 | 156 | 类型检查（M2-C） |
| `typedecl.go` | 690 | 410 | 类型声明与对象规则（M2.5.1） |
| `policy.go` | 357 | 185 | 内存策略判定（M2.5.2） |
| `xdk.go` | 227 | 37 | XDK 包符号与导入诊断 |
| **合计** | **2,900** | **1,122** | 34 个测试函数，`go test -cover` = **75.7%** |

**三遍顺序**（`sema.go:56-90`）：导入 → 类型声明登记/检查 → 名称解析（仅顶层函数）→ 确定赋值（仅顶层函数）→ 类型检查（顶层函数 + 类/结构体方法体）。

---

## 2. 类型覆盖清单（S1 §2/§7）

> 状态口径：**覆盖** = 规则实现且有对应用例；**部分** = 骨架/单侧实现；**缺口** = 无实现或全部静默。

| # | 子项 | 规范锚点 | 实现位置 | 状态 | 证据 |
|---|---|---|---|---|---|
| T1 | 标量类型集（13 数值 + Bool/Char） | S1 §2.2 | `ty.go:37-40`、`typedecl.go:36-43` | 覆盖 | `ty_test.go:7` |
| T2 | 引用类型集 | S1 §2.3 | `ty.go:42-45`、`ty.go:94-107` | 部分 | 泛型类 `Box<Int>` 被 `isRefType` 判为非引用（`ty.go:103`），E05 |
| T3 | `T?` 归一（引用类型 `T?≡T`；`T??≡T?`） | S1 §2.4 | `ty.go:84-91` | 缺口 | `String? → String` 误报 TY-101（E04）；`Int??` 解析层拒绝（E15） |
| T4 | `null` 规则 | S1 §2.6 | `ty.go:132-137`、`ty.go:234-239` | 覆盖 | `ty_test.go:88`；错码 TY-103 与测试注释不一致属注释陈旧 |
| T5 | 字面量适配 + 表示性 | S1 §2.6/§2.10 | `ty.go:125-137` | 部分 | `Byte=300`、`Short=70000`、`UByte=-1` 全通过（E06，`ty.go:126` 自述推迟） |
| T6 | 容器字面量 → `List`/`Set` | S1 §2.6 | `ty.go:143-151` | 部分 | 单向数组字面量适配；嵌套 `List<List<Int>>` 空格写法通过、`>>` 写法解析失败（E15） |
| T7 | 闭包字面量 → 函数类型 | S1 §2.6 | `ty.go:152-159` | 部分 | 仅骨架放行，参数/返回未逐参检查（注释自述） |
| T8 | 元组类型身份 / 选择器 | S1 §2.11 | `ty.go:74-79`、`ty.go:573-582` | 部分 | `pair.5` 越界静默（E08b）；解构/相等/插值未做，与 TUPLE-01"部分"一致 |
| T9 | `Result<T,E>` 骨架 | S1 §10 | `ty.go:160-168`、`ty.go:505-511`、`ty.go:663-668`、`ty.go:796-813` | 部分 | 实参不深度检查；成员返回类型靠逗号 `Split`，嵌套泛型实参会拆错 |
| T10 | 运算符与条件 | S1 §7.2/§7.3/§6.1 | `ty.go:823-924`、`ty.go:412-417` | 覆盖 | `ty_test.go:116`；`??` 左侧合法性未查（E18） |
| T11 | `Any` 装箱 / 拆箱 / 引用根 | S1 §2.6 | `ty.go:117-170` | 缺口 | `Any → Object` 与 `String → Object` 均被拒（E03）；`Any` 拆箱只靠 `as` 得到同型串 |
| T12 | 子类型 / 协议实现 / 泛型方差 | S1 §2.6、S2 §2.5/§13.2 | 无 | **缺口** | `B→A`、`C→P` 误报（E01/E02） |
| T13 | 类型位置合法性 | S1 §2.9/§3 | 仅继承目标 `typedecl.go:521-532` | **缺口** | 未知类型 `Foo f`、`as Nope`、`is Nope` 静默（E09） |
| T14 | 泛型实参 arity / `void` / 未绑定 | S1 §8.3、S2 §13.3 | 无 | **缺口** | `Box<Int,String>`、`List<void>` 通过（E16） |
| T15 | `var` 推断 | S1 §2.7 | `ty.go:292-302` | 部分 | 基本推断有；`null`/空数组/空 Map/无目标闭包未按 §2.7 拒绝（未知类型一律放行） |
| T16 | `?.` 可空访问 | S1 §2.4 | `Member.NullSafe` 存在（`ast.go:132-137`），sema 未读 | 缺口 | `Int n = s?.length()` 通过（E12b）；结果类型未提升为 `T?` |
| T17 | 诊断定位与唯一性 | S1 §0.6、BND-14 | `ty.go:424`（`xfront.Pos{}`） | 缺口 | 复合赋值/自增类型错误输出 `0:0`（E14）；DA-101 每处两条（E13） |

---

## 3. 对象覆盖清单（S2）

| # | 子项 | 规范锚点 | 实现位置 | 状态 | 证据 |
|---|---|---|---|---|---|
| O1 | 类型声明登记 / 包内唯一 / 预定义冲突 | S2 §1.1 | `typedecl.go:90-159` | 覆盖 | `typedecl_test.go:403` |
| O2 | 修饰符位置与组合 | S2 §1.6 | `typedecl.go:192-200` | 部分 | 只查 `abstract`/`abstract final`；`final protocol`、`static class`、`final struct` 均通过（E19） |
| O3 | 单继承 / 父类种类 / final 父类 / 环 | S2 §2.5/§1.5 | `typedecl.go:264-279`、`typedecl.go:555-612` | 覆盖 | INH-01 PASS（`status.tsv:15`） |
| O4 | 字段隐藏 / 同签名方法 | S2 §2.5 | `typedecl.go:290-310`、`typedecl.go:543-553` | 部分 | 只看参数不看返回类型；同类内重复字段/同签名方法不查（E19b） |
| O5 | 字段可见性 | S2 §7.4 | `typedecl.go:203-227`、`ty.go:595-647` | 部分 | private 全覆盖；`protected`/`public` 方法外部访问、私有方法外部调用不查（E19c） |
| O6 | 字段初始化式类型 | S2 §6.1 | **无** | **缺口** | `class C { Int x = "s"; }`、struct 同型均通过（E11） |
| O7 | `deinit` 规则 | S2 §6.4 | `typedecl.go:311-333` | 覆盖 | 规则齐；方法体仍受 O13 影响 |
| O8 | 主构造器物化 | S2 §6.1、PCTOR-01 | `typedecl.go:245-254` | 部分 | 只做字段物化；`final` 恰好一次、`super` 顺序、与非主构造器混用未做 |
| O9 | 构造调用 arity / 实参类型 | S2 §6.3 | `ty.go:589-590` 返回未知 | **缺口** | `new C(1,2)` 通过（E12c） |
| O10 | 结构体值字段 / 递归值包含 / 捕获 self | S2 §3.1/§3.2/§1.5 | `typedecl.go:339-413` | 部分 | STRUCT-01 部分；泛型结构体 `struct Pair<A,B>` 被误判 TY-204（E08） |
| O11 | 协议形式 / 继承环 | S2 §4.1/§4.2 | `typedecl.go:416-433`、`typedecl.go:596-612` | 部分 | 字段/方法体/泛型由解析层拒绝；协议实现完整性 §4.3 未做，`P p = c` 误报（E02） |
| O12 | 枚举规则 | S2 §8 | `typedecl.go:436-501` | 部分 | 项名/值/形式/构造器数量已查；**项参数类型不查**（E19d）、switch 穷尽性未做（E19e） |
| O13 | 方法/构造器体语义 | S1 §3.3/§5.3/§6.1 | 仅 `typedecl.go:631-690` 类型推断 | **缺口** | 方法内未定义名/重复局部/未赋值读取/缺返回全静默（E10） |
| O14 | `abstract` 实例化 / `new` 协议或结构体 | S2 §2/§4 | 无 | 缺口 | `new A()`（abstract）、`new P()`（protocol）通过（E19f） |
| O15 | 成员存在性 / 方法 arity / 返回类型 | S1 §9.1、S2 §5 | `ty.go:671-678`、`ty.go:710-821` | 缺口 | `Int.value()`、`w.nope()`、`c.get(1,2)` 全静默（E16）；`methodRet` 0% 覆盖 |
| O16 | 内存策略判定 | S2 §15.1 | `policy.go:38-194` | 部分 | 行 5–9 骨架、排序确定性有；String 误归类、static 参与实例判定（E17） |
| O17 | XDK 导入诊断 | S1 §3.5、S6 | `xdk.go:90-227` | 部分 | 包/符号/别名有（PKG-01 部分）；类型位置检查只在局部声明（`sema.go:150`），参数/返回/字段不查（E20） |
| O18 | `switch` 值类型 / 穷尽性 / 分支类型 | S1 §6.8、S2 §8.5 | 无 | 缺口 | 枚举 switch 用 `case 1` 通过（E19e） |

---

## 4. 泛型覆盖清单（S1 §8、S2 §13）

| # | 子项 | 现状 | 位置 | 状态 |
|---|---|---|---|---|
| G1 | 泛型函数/类/结构体声明解析 | 解析可用（`static T identity<T>(T v)` 通过） | `xfront/unit.go:405-418`、`xfront/types.go:267/361` | 覆盖（仅解析） |
| G2 | 方法级泛型参数 | `MethodDecl` 无 `TypePars` 字段，方法泛型写不出来 | `xfront/types.go:27-36` | 缺口（跨域） |
| G3 | 类型参数进名称解析第 1 级 | `nscope` 不接收 `TypePars` | `sema.go:113-136` | 缺口（GEN-01） |
| G4 | 类型参数唯一性 / 与类参数重名 | 解析层对重复参数报 SYN-101（`x2`）；与类参数重名的规则无检查 | — | 部分 |
| G5 | 泛型实参 arity / `void` / 未绑定 | 全无 | — | 缺口 |
| G6 | 泛型调用替换与推断 | 无；形参按字面 `T` 比较 → 合法调用 TY-101 | `ty.go:680-701` | 缺口（误报） |
| G7 | 单态化 / 无限展开诊断 | 无 | — | 缺口（GEN-01） |
| G8 | 泛型类字段类型 / 成员返回 | `Box<Int>.get()` 返回未知，错误赋值也通过 | `ty.go:710-821` | 缺口（假绿） |
| G9 | 型变 `out`/`in` | 解析时丢弃，AST 不保留 | `xfront/types.go:207-227` | 缺口（跨域阻断） |
| G10 | 裸泛型 `Box ≡ Box<Any>` | `typeKey` 保留 `Box`，不与 `Box<Any>` 归一 | `ty.go:48-61` | 缺口 |
| G11 | 泛型静态字段 / `static T` | `class Box<T> { static T value; }` 通过（§6.5 禁止） | — | 缺口 |
| G12 | 泛型结构体值字段约束 | 声明期把类型参数一律判非值字段（误杀）；实例化点不查实参 | `typedecl.go:369-413` | 缺口（双向都错） |
| G13 | 策略层类型参数 | 仅 `isTypeParam` 保守归 GC，无测试 | `policy.go:134-145` | 部分（0% 覆盖） |

---

## 5. 实证反例（E01–E20）

> 探针均在 `$TMPDIR/probes/*.x`；`xnull policy` 单文件走的就是 `sema.AnalyzeWith`，与 `run`/`build` 共用同一语义入口（`internal/cli/cli.go:240,272`、`internal/codegen/build.go:28`）。

| ID | 现象 | 最小输入 | 实际 | 应为 | 根因 |
|---|---|---|---|---|---|
| E01 | 子类不可赋给父类 | `class B : A {}` + `A a = b` | TY-101 | 通过 | `assignable` 无子类型规则（`ty.go:117-170`） |
| E02 | 类不可赋给所实现协议 | `class C implements P` + `P p = c` | TY-101 | 通过 | 同上，无协议实现规则 |
| E03 | 引用根缺失 | `Object o = "x"`；`Object p = 1 as Any` | TY-101 ×2 | 通过（§2.6 引用根） | `refTypeNames` 判型，无 Object 根规则（`ty.go:42-45`） |
| E04 | `String?` 未归一 | `String? opt = null` + `String s = opt` | TY-101 | 通过（§2.4 同型） | `assignable` 只做 `T→T?`（`ty.go:139-141`） |
| E05 | 泛型类判空失败 | `class Box<T>` + `Box<Int> b = null` | TY-103 | 通过 | `isRefType` 见 `<` 即 false（`ty.go:103`） |
| E06 | 字面量表示性未查 | `Byte b = 300`；`Short s = 70000`；`UByte u = -1` | 全通过 | TY-101 | `ty.go:126` 只按"目标是否整数类型"接受 |
| E07 | 泛型调用误报 | `static T identity<T>(T v)` + `identity<Int>(1)` | 两条 TY-101 | 通过 | 调用层不替换 `T`（`ty.go:680-701`） |
| E08 | 泛型结构体声明误杀 | `struct Pair<A,B> { A first; B second; }` | 两条 TY-204 | 通过 | `isValueTypeRef` 把无参 `A` 当未知类型（`typedecl.go:373-396`） |
| E08b | 元组越界静默 | `var pair = (1,"a")` + `pair.5` | 无诊断 | TY-101（§2.11/附录 A） | `ty.go:573-582` 只取下标，不判越界 |
| E09 | 未知类型名静默 | `Foo f`；`1 as Nope`；`x is AlsoNope` | 全通过 | RES-101/TY-101 | 只查继承目标（`typedecl.go:521-532`） |
| E10 | 方法体三遍盲区 | 方法内 `if c { return 1 }` 无 else；`Int x=1; Int x=2`；`nope = 1` | 全通过 | DA-103 / RES-102 / RES-101 | `sema.go:72-86` 仅遍历 `TopFunc` |
| E11 | 字段初始化不查 | `class C { Int x = "s"; }`；struct 同型 | 通过 | TY-101 | `typedecl.go` 从不读 `FieldDecl.Init` |
| E12 | 成员调用 arity 不查 | `c.get(1,2)`；`"x".length(1)` | 通过 | TY-101 | `methodRet` 不收 arity（`ty.go:710-821`） |
| E12b | `new` arity 不查 | `C c = new C(1,2)` | 通过 | TY-101 | `infer(New)` 直接返回未知（`ty.go:589-590`） |
| E12c | `?.` 结果类型不提升 | `String? s` + `Int n = s?.length()` | 通过 | TY-101（结果 `Int?`） | `inferMember` 未读 `NullSafe`（`ty.go:595-647`） |
| E13 | DA-101 重复输出 | `Int x` + `print(str(x))` | 同一处两条 DA-101 | 一条 | `assign.go:97` 走一遍后 `:99` 又走 `blockExit`（`:130-133`） |
| E14 | 诊断位置 0:0 | `String s` + `s += "b"`；`Bool b` + `b++` | `0:0 TY-105` | 目标节点行列 | `checkOperand` 用 `xfront.Pos{}`（`ty.go:424`） |
| E15 | 解析层阻断泛型基础写法 | `List<List<Int>>`；`Int??` | SYN-102/SYN-108；SYN-109 | 通过 | `>` 未按两个 `>` 解析；`??` 后缀未归一（xfront 域） |
| E16 | 未知成员/泛型返回未知 | `Int x` + `x.value()`；`Box<Int>.get()` 赋给 `String` | 全通过 | TY-101 | `methodRet` 未知即放行（`ty.go:815-820`） |
| E17 | 策略判定输入错误 | `class Named { String name; }`；`class S { static Any p; Int x; }` | Named 行 8 栈候选；S 行 5 GC | Named 行 9 ARC；S 行 8（仅 `Int` 实例字段） | `policy.go:85-88`；`policy.go:154-170` 未排除 static |
| E18 | `??` 左侧规则未查 | `Int x = 1 ?? 2` | 通过 | TY-105（左侧须引用/`T?`） | `ty.go:892-894` 直接去 `?` |
| E19 | 修饰符/同类成员/可见性/枚举/abstract | `final protocol P`；`static class C`；`final struct S`；同类重复字段与同签名方法；`protected` 字段外部读；`enum S { Ready("x") }`；`new P()` | 全通过 | TY-201/TY-203/TY-206/TY-202 | `checkModifiers` 仅查 abstract（`typedecl.go:192-200`）；O4/O5/O12/O14 |
| E19g | static 方法经成员访问使用 `self` 未拒 | `class C { static Int f() { return self.x } Int x; }` | 通过 | TY-201（§1.6） | `inferMember` 的 `self` 分支不查 `cls.instance`（`ty.go:597-609`） |
| E20 | XDK 符号只在局部类型检查 | `class C { Regex r; }`；`static Regex f(Regex r)` | 无 RES-105 | RES-105 | `checkTypeXdkUse` 仅 `sema.go:150` 调用 |

### 5.1 关键反例源码（可直接复跑）

```x
// E01 / E02 / E03 —— 合法赋值被拒
class A { Int x = 0; }
class B : A { Int y = 0; }
protocol P { void go(); }
class C implements P { void go() { } }
static Int main() {
    B b = new B()
    A a = b            // TY-101（应通过）
    C c = new C()
    P p = c            // TY-101（应通过）
    Object o = "x"     // TY-101（应通过）
    Object q = 1 as Any// TY-101（应通过）
    return 0
}
```

```x
// E10 —— 方法体的三遍盲区
class M {
    Int noReturn(Bool c) {
        if c { return 1 }      // 缺 return：应 DA-103
    }
    Int dup() {
        Int x = 1
        Int x = 2              // 应 RES-102
        Int y
        return y               // 应 DA-101
    }
    Int undef() {
        nope = 1               // 应 RES-101
        return 0
    }
}
```

```x
// E17 —— 策略判定（当前输出）
class Named { String name; }              // 现：rule 8 stackEligible=true
class S { static Any p; Int x = 0; }      // 现：rule 5 gc
static Int main() { return 0 }
```

---

## 6. 测试缺口（10 条，按"假绿风险"排序）

> 判定口径：能复现、能断言、能进 `status.tsv` 或包内测试才算覆盖；"跑过没崩"不算。

| # | 缺口 | 现状证据 | 风险 | 建议锚点/文件 |
|---|---|---|---|---|
| G1 | **方法体语义零用例**：无方法内 RES-101/102、DA-101/103 用例 | `sema.go:72-86` 仅 `TopFunc`；`assign_test.go` 4 个用例全是顶层函数 | 最大的静默接受面，NEG-01/BND-14 无法签 | 新增 `typedecl_body_test.go`；CTRL-01 剩余项 |
| G2 | **`methodRet` 0% 覆盖**：`String`/`T[]`/`List`/`Map`/`Set`/`Result` 成员调用无任何 sema 用例 | `go tool cover`：`ty.go:710` 0.0% | §9.1 总表等于未验；arity/参数类型缺口（E12）无人发现 | 新增 `ty_member_test.go`，BND-01/BLD-01 输入面 |
| G3 | **`elemTypeOf` 0% 覆盖**：下标读写类型无测试（含 `Map<K,V>` 嵌套逗号） | `ty.go:429` 0.0% | 下标赋值类型错误可能漏报/误报；嵌套泛型解析会拆错 | `ty_index_test.go`，TUPLE/BLD 锚点 |
| G4 | **`isTypeParam` 0% 覆盖**：泛型类字段策略无测试 | `policy.go:134` 0.0% | 行 5 的"未单态化泛型"实际行为无证据 | `policy_generic_test.go`，MEM-01 |
| G5 | **诊断"存在"≠"正确"**：`expectCode` 只查前缀，不查条数与位置 | `sema_test.go:32-40`；DA-101 全部重复（E13）、TY-105 位置 `0:0`（E14） | 重复诊断、0 行号可穿过 CI，违反 BND-14 | 增加 `expectCodeOnce` / `expectPos`，先修 `assign.go:97-101`、`ty.go:424` |
| G6 | **字段初始化式无用例**：class/struct/enum 字段初始化类型不查 | `typedecl.go` 无 `FieldDecl.Init` 读取；`typedecl_test.go` 无对应用例 | 对象字段类型错误推迟到运行期/codegen | `typedecl_field_test.go` |
| G7 | **可赋值性"正向合法"用例缺失**：无子类、协议、Object 根、`String?` 归一用例 | `ty_test.go` 只测同型/字面量/null/Result | TYPE-01 标 PASS 但核心正向规则未测；误报无法被门禁发现 | `ty_assign_test.go`（先写红） |
| G8 | **泛型合法用例缺失**：无 `Box<Int>`/`identity<Int>` 通过用例，无 arity/void 负例 | `ty_test.go` 的"泛型"仅 `Result`/`try` 骨架；GEN-01 无文件（`status.tsv:14`） | 泛型误报（E07/E08）不会被任何测试捕获 | `ty_generic_test.go`（依赖 xfront 子卡） |
| G9 | **未知类型/未知成员负例缺失**：无 `Foo f`、`as Nope`、`x.value()` 用例 | NEG-01 未实现（`status.tsv` 无文件） | 拼写错误静默通过；能力缺口表易被读成"支持对象成员" | `ty_neg_test.go` |
| G10 | **策略判定只覆盖 11 个声明**：无 String/static/泛型实参用例 | `policy_test.go:27-103` | 行 8/9 误判直接影响 M3.2 消费 | `policy_fields_test.go` |

**次级（登记不单独立卡）**：`scanStmtSelf`/`scanExprSelf`/`fmtStrategyRow` 为未调用包装（0% 覆盖，可删）；`collectTopParam` 是空实现；`ty_test.go:96` 注释"TY-103 走 TY-101 通道"与代码不符（实际码 TY-103），注释陈旧。

---

## 7. 前 3 张建议卡（待 CEO1 派工、PJ 定编号）

> 说明：卡号为**建议**，最终以 PJ 的 `S<阶段>-<序号>` 为准；本报告不派工。
> 写入前提：`wt/c1-rd2` 已存在（`pod/c1-rd2` @ `dfcf033`，`git worktree list` 可查），但 `evidence/S0-28/` 未见；写权解禁以 CEO1 门禁结论为准，本报告不判定。
> WIP：三卡同属 RD2 单域，**必须串行**（卡 1 → 卡 2 → 卡 3），不并行改 `ty.go`。

### 卡 1（建议 `S1-2x`）可赋值性主干补齐：引用根 + 子类型 + 协议 + 泛型引用判定

| 项 | 内容 |
|---|---|
| 主责 | **CEO1-RD2** |
| 输入 | S1 §2.4/§2.6、S2 §2.5/§13.3；E01–E05、E18 |
| 范围 | 只改 `ty.go` 的 `assignable`/`isRefType` 与必要 helper：①`Object` 引用根（引用类型与 `Any` → `Object`）；②类继承链（复用 `typedecl.go:556-574` 的祖先收集）；③协议实现（`implements` + 父协议闭包）；④`isRefType` 对具体类/结构体泛型按声明种类判引用，不再"见 `<` 即 false"；⑤`??` 左侧必须引用/`T?`。**不做**型变（G9 跨域）、不做协议实现完整性 §4.3（另卡） |
| 非目标 | 泛型实参替换（候选 5/后续 GEN-01）、`String?` 归一若被判定属 TYPE-02 修复可一并纳入（E04） |
| 验收 | E01/E02/E03/E05 转绿；新增 `ty_assign_test.go` ≥12 例（含负例：值类型→Object、Any 未 `as`→具体类型仍拒）；现有 34 测试全绿；`go test -cover ./internal/sema` ≥ 80% |
| 依赖 | 无（`a.tc` 在 `analyzeTypes` 前已建好，`sema.go:60` 先于 `:88`）；不碰 xfront |
| 预估 | 1.5 人日 |
| 风险 | 子类型引入后可能暴露"类字段初始化未查"（卡 2）的连锁；协议实现需要 `c.types` 的 protocol 信息，注意别把 XDK 未导入符号误判为类 |

### 卡 2（建议 `S1-2x`）方法体语义遍接入 + 字段初始化 + DA 诊断质量

| 项 | 内容 |
|---|---|
| 主责 | **CEO1-RD2** |
| 输入 | S1 §3.3/§5.3/§6.1、S2 §6/§7.4；E10/E11/E13/E14 |
| 范围 | ①抽出通用"函数体三遍"helper，使 `MethodDecl`/`CtorDecl` 也走名称解析（字段进作用域）与确定赋值/返回路径；②class/struct/enum 的 `FieldDecl.Init` 做 `infer + assignable`；③`bodyNeverFallsThrough` 不再二次执行整棵语句树（`assign.go:97-101`），DA-101 每处恰好一条；④`checkOperand` 用目标节点位置（`ty.go:424`）；⑤修 `hintFor` 的 `Int?→Int` 误导（`ty.go:248-258`） |
| 非目标 | 不改写 `TopFunc` 现有诊断集合（除重复/位置）；不实现 PCTOR-01 的 `super` 顺序 |
| 验收 | E10/E11/E13/E14 转绿；新增方法体/构造器体用例 ≥15（含 E19g 的 `static self.x` 负例）；同一条 DA-101 只输出一次且行列正确；`go test ./internal/sema` 全绿 |
| 依赖 | 与卡 1 共享 `ty.go`，必须卡 1 合入后串行；不改 xfront |
| 预估 | 2.5 人日 |
| 风险 | 方法体进入 nscope 后，§7.4 裸私有名/`self` 规则与现有 `inferMember` 可能重复报错，需统一口径；构造器内 `final` 字段"恰好一次"留给 PCTOR-01，避免本卡膨胀 |

### 卡 3（建议 `S2-1x`）策略判定输入修正：String 归类、static 字段、泛型实参

| 项 | 内容 |
|---|---|
| 主责 | **CEO1-RD2**（必签 CEO2-RD2/运行时消费方） |
| 输入 | S2 §3.2/§7.1/§15.1；E17；`policy.go` 冻结接口注释（`:16-21`） |
| 范围 | ①`fieldRefClass` 把 `String`/`Text`/`Bytes`/`StringBuilder` 从 `"value"` 改为 `"ref"`（§3.2 明确排除 String 等为值字段）；②策略字段遍历排除 `static`（§7.1 类型级存储不占实例布局）；③泛型字段按声明种类（class/protocol/struct）归类，未单态化仍按行 5 归 GC；④补 `isTypeParam`/`fieldRefClass` 分支用例 |
| 非目标 | 不改逃逸分类（`Escape` 仍是 `n/a`，M4.1）；不引入 singleton（解析层未支持） |
| 验收 | `class Named { String name; }` → 行 9 ARC；`class S { static Any p; Int x; }` → 行 8（仅 `Int` 实例字段）且非 GC；`policy_test.go` 现有 11 个期望不回归；新增 `policy_fields_test.go` ≥8 例；`xnull policy` 输出确定性不变（DET-01） |
| 依赖 | 无；但被 M3.2 消费前必须完成（接口已冻结） |
| 预估 | 0.5–1 人日 |
| 风险 | 若 PM 认定"字段"包含 static（与 §7.1 冲突），本卡第 ② 项降级为待确认；String 归类依据 §3.2 价值字段清单，置信度高 |

**为什么是这三张**：先修"合法代码被拒"（卡 1，直接影响可用性与 TYPE-01 的门禁口径），再修"非法代码被静默接受"（卡 2，影响最大且不可绕过），最后修已冻结、即将被 M3.2 消费的策略输入（卡 3，成本最低、时间窗口最紧）。类型引用合法性（E09/E16）与 GEN-01 见下方候选，不挤进前三。

**候选卡（不排入前 3，登记备查）**：
- **候选 4**：类型引用合法性统一校验（未知类型名、`is/as` 目标、泛型实参 arity/`void`、XDK 符号在参数/返回/字段位置）。需 PM 先定新诊断码；预计 1.5 人日；与卡 1/2 同文件，需再串行。
- **候选 5**：GEN-01 最小可验收（泛型调用替换 + 单态化 + 无限展开）。被 xfront 的 method TypePars / variance / `>>` 解析三项阻断，建议先由一司 PM 与 RD1 定接口，再立卡。

---

## 8. 跨域依赖与待决（不自行决定，不派工）

| # | 事项 | 需谁定 | 影响 |
|---|---|---|---|
| B1 | `List<List<Int>>` 的 `>>` 被解析成比较/链式（E15） | CEO1-RD1（xfront） | 泛型嵌套是 §13.3 明写要求；候选 4/5 与 GEN-01 均受阻 |
| B2 | `Int??` 归一未在解析层完成（E15） | CEO1-RD1（xfront） | TYPE-02"`T??` 归一"无法签 |
| B3 | `MethodDecl` 无 `TypePars`，方法泛型不可写 | CEO1-RD1（xfront）+ PM | S2 §13.1/§13.2 整段无法验收（G2/G9） |
| B4 | `out`/`in` 型变在 `parseGenericPars` 被丢弃 | CEO1-RD1（xfront） | 型变规则（§13.2）在 AST 层已不可恢复 |
| B5 | 新诊断码段位分配（未知类型/arity/泛型实参） | 一司 PM + CEO1 | 候选 4 无法开工；不得复用既有码制造歧义 |
| B6 | TYPE-01/TYPE-02 标 PASS 与实证不符（E01–E06） | CEO1（门禁）/ QA | 建议先降为"部分"或补红用例，待修复后再签；我不改 `status.tsv` |
| B7 | static 字段是否参与 §15.1 判定 | 一司 PM / CTO | 决定卡 3 第 ② 项口径 |
| B8 | `evidence/S0-28/` 未见 vs 9 个 worktree 已存在 | CEO1 / 董事会 | 卡 1–3 的写权解禁依据 |

---

## 9. 复核命令（只读）

```bash
cd impl

# 1) 基线测试与覆盖率（约 18–25s）
go test ./internal/sema/ -count=1
go test -coverprofile=/tmp/sema.cover ./internal/sema/ && go tool cover -func=/tmp/sema.cover | sort -k3 -n | head

# 2) 反例实测（任选；需先构建临时二进制，不污染仓库）
go build -o /tmp/xnull ./cmd/xnull
/tmp/xnull policy /path/to/probe.x

# 3) 三遍覆盖面核对（应只见 TopFunc）
grep -n "TopFunc" internal/sema/sema.go

# 4) 0% 覆盖函数核对（应含 methodRet / elemTypeOf / isTypeParam）
go tool cover -func=/tmp/sema.cover | grep " 0.0%"

# 5) 策略误判核对
printf 'class Named { String name; }\nclass S { static Any p; Int x = 0; }\nstatic Int main() { return 0 }\n' > /tmp/p.x
/tmp/xnull policy /tmp/p.x   # Named 当前 rule=8 stack=true；S 当前 rule=5 gc

# 6) 本轮实测记录
#    go test ./internal/sema/            → ok 25.045s
#    go test -cover ./internal/sema/     → 75.7% of statements
#    探针 40+ 个（$TMPDIR/probes），结果见 §5
```

---

## 10. 本轮边界（自证未越权）

- 只读文件、只跑测试/构建临时二进制/写临时探针；**未编辑 `impl/**`**、未编辑 `xnull/**`、未改 `status.tsv`/台账/看板。
- 唯一写入：本文件 `收件箱/CEO1/CEO1RD2-首轮.md`。
- 未 commit、未 push、未派工、未建卡（§7 仅为建议，派工权在 CEO1/PJ）。
- 未使用 `wt/c1-rd2` 写任何内容；首轮按 v1.6.0 §5 只交盘点。
