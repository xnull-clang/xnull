# B3-09 K-06 内容差异聚类（只读）

> 数据源：`tests/b3/xnullc-all.sh` 全量结果（`evidence/B3-09-harness/out/results.tsv`）
> 59 个有 diff 文件。逐文件重新生成 **归一化 content diff**（`xn_tN→xn_t#`、
> 去前导缩进）后按下述规则聚类。只读分析，未改 xnullc。

## 1. 聚类口径

- 多标签：一个文件可同时命中多个机制（例如 xlex.x 同时有 void/typedef/root/defer）。
- 计数为“命中文件数”；影响值为该文件 `content` diff 行数求和；排序值 =
  文件数 × 影响值（多标签会重复计入，用于判断“修一条规则覆盖面”）。
- “纯缩进”在 content 归一化后为 0；本次 **没有** 纯缩进文件。缩进差异只作为
  while 降级/块层级的伴随现象出现（raw diff 大于 content diff）。

## 2. 聚类结果（59 文件，多标签）

| 类 | 文件数 | content 行合计 | 文件数×行数 | 说明 |
|---|---:|---:|---:|---|
| root 次数 | 40 | 18040 | **721600** | `xn_root_add/hold/restore` 数量或位置不同 |
| defer | 31 | 18265 | **566215** | `rt_release` 块拆分/顺序/合并 |
| 其它:typedef | 14 | 14244 | **199416** | K-02/K-03/K-05/结构 typedef |
| while 降级 | 12 | 14997 | 179964 | 条件有临时未降级 `while(1)` |
| 其它:void | 11 | 14681 | 161491 | `void` 返回类型 |
| 其它:空参数 | 15 | 9429 | 141435 | `()` vs `(void)` 的构造/无参函数形式 |
| 其它:非 ASCII | 8 | 12790 | 102320 | 中文字符串丢失 |
| 其它:String 索引 | 4 | 9155 | 36620 | `substring/length` 临时位置 |
| blockHeld | 4 | 8499 | 33996 | 跨作用域赋值 hold/release 缺失 |
| 其它:Result 零值 | 8 | 441 | 3528 | `NULL` vs `0`（指针错误槽） |
| 其它:私有字段 | 2 | 848 | 1696 | `_a` vs `a` |
| 编号/缩进 | 1 | 11 | 11 | 纯编号差（归一化后无 content diff） |
| 其它:表达式/编号 | 4 | 57 | 228 | 无法归入上述的表达式求值差 |

### 独占首因（每文件只取一个主因）

`root次数 40、空参数 7、其它表达式 4、defer 3、Result零值 2、私有字段 1、
非ASCII 1、编号 1`。

### 排序结论

- **总体前 3**（含非 K-06）：`root 次数`、`defer`、`其它:typedef`。
- **K-06 内前 3**：`root 次数`、`defer`、`while 降级`。
- 修一条规则覆盖最多：先把 `rootTempDecls` 的**分层次数**统一（root 次数），
  再把 defer 的**独立块/LIFO**统一，第三是 while 条件临时降级。

## 3. 每类最小复现 + Go 关键输出 + 规则

复现文件均为最小 `.x`；输出由 `xnull build --emit-c` 实测摘录。

### 3.1 root 次数（40 文件）

复现 `root.x`：

```x
static Int main() {
    String s = ""
    if true {
        s = "a" + str(1)
    }
    print(s)
    return 0
}
```

Go 关键段：

```c
if (1) {
    size_t xn_t3 = xn_root_mark();
    rt_string *xn_t4 = rt_string_from_c("a");
    xn_root_add(xn_t4);
    xn_root_add(xn_t4);          // 同一临时两次
    rt_string *xn_t5 = xn_str_int(1);
    xn_root_add(xn_t5);
    xn_root_add(xn_t5);
    rt_string *xn_t6 = xn_concat(xn_t4, xn_t5);
    xn_root_add(xn_t6);
    xn_root_add(xn_t6);
    xn_root_release(s); rt_release(s);
    s = xn_t6; xn_root_hold(s);
}
```

规则：

- `rootTempDecls`（`codegen.go:5603`）在 `emitStmt`（`:2126`）与 `emitReturn`
  （`:3612`）各执行；嵌套语句会被每层祖先语句的 `emitStmt` 再次后处理 →
  **同一临时重复 root_add 次数 = 语句嵌套层数 + 1（GC 局部再 +1 声明 root）**。
- 详见 `handoff/B3-root-emission.md` §2.1。

### 3.2 while 降级（12 文件）

复现 `while.x`：

```x
class C { String s = "x"
    String get() { return self.s } }
static Int main() {
    C c = new C()
    Int i = 0
    while c.get() == "x" {
        i = i + 1
        if i > 1 { break }
    }
    return 0
}
```

Go 关键段：

```c
while (1) {
    rt_string *xn_t2 = xn_Cls_C_get(c);
    xn_root_add(xn_t2);
    rt_string *xn_t3 = rt_string_from_c("x");
    xn_root_add(xn_t3);
    if (!((xn_str_eq(xn_t2, xn_t3)))) { break; }
    size_t xn_t4 = xn_root_mark();
    ...
}
```

规则：`emitWhile`（`codegen.go:2169`）若条件求值产生 `s.pending`，降级
`while(1){ 前置; if(!(cond)) break; 体; safepoint }`；前置/条件/体/ safepoint
均 +4 缩进。无前置语句才输出普通 `while(cond)`。

### 3.3 defer（31 文件）

复现 `defer.x`：

```x
static Int main() {
    String a = "a"
    String b = "b"
    print(a + b)
    return 0
}
```

Go 关键段：

```c
int64_t xn_t7 = 0;
    {
rt_release(b);
    }
    {
rt_release(a);
    }
    {
xn_root_restore(xn_t1);
    }
return xn_t7;
```

规则：`emitBlock`（`:2084`）按 `s.defers` 逆序（LIFO）输出，每个 defer
独立 `{}`，不合并；`String` 局部声明在 `emitLocalDecl` 注册 release defer。
`blockHeld` 的 `xn_root_release` 在该序列之前（`:2106`）。

### 3.4 blockHeld（4 文件）

复现 `blockheld.x`：

```x
static Int main() {
    String s = ""
    Int i = 0
    while i < 2 {
        s = "v" + str(i)
        i = i + 1
    }
    print(s)
    return 0
}
```

Go 关键段：

```c
// 循环体内（跨作用域赋值）
xn_root_release(s);
rt_release(s);
s = xn_t6;
xn_root_hold(s);
// 函数体块退出
xn_root_release(s);     // 位于 return 之后，仍输出
```

规则：`promoteRoot`（`:5576`）判定目标在祖先作用域 → `release 旧 + hold 新`，
并在目标声明作用域的 `blockHeld` 里登记；`emitBlock`（`:2106`）退出时输出
`xn_root_release`（可能落在 return 之后）。

### 3.5 编号/缩进（1 文件，纯编号）

复现 `num.x`：

```x
class C { String s = "x"
    String get() { return self.s } }
static String twice(C c) { return c.get() + c.get() }
static Int main() { C c = new C(); print(twice(c)); return 0 }
```

Go 关键段：

```c
rt_string *xn_t2 = xn_Cls_C_get(c);
rt_string *xn_t3 = xn_Cls_C_get(c);
rt_string *xn_t4 = xn_concat(xn_t2, xn_t3);
```

规则：`nextTmp`（`:2024`）先 `++` 后命名，**从不复用编号**；表达式左→右、
先实参后结果；两遍发射只重置一次（第二遍从 1 开始）。缩进为 4 空格/层。

### 3.6 其它：void/typedef/空参数/私有字段/Result 零值/非 ASCII

- **void**：`genFuncNamed`（`:1870`）以 `fn.Void` 覆盖 `retC="void"`；xlex/parser-seed
  类文件仍生成 `int64_t`。
- **容器/函数指针/Result typedef**：见 `handoff/B3-typedef-void-spec.md` K-02/03/05。
- **空参数形式**：Go 分站点：
  - 隐式无参类构造器：`new(void)`（`classes.go:466/709`）；
  - 显式零参构造器：`new()`（`ctorParamDecls` 空 join，`classes.go:450+`）；
  - `struct` 构造器：`Struct_new(void)`（`struct.go:150`）。
  xnullc 目前统一成一种形式，故 15 个文件首条 diff 是 `()`/`(void)` 互换。
- **私有字段**：Go 字段 C 名带前缀 `_a`（`classes.go` 字段布局），xnullc 丢了 `_`。
- **Result 零值**：`resultZeroC`（`codegen.go:1515`）指针类型用 `NULL`，整数/枚举用
  `0`；`Ok/Err` 构造时错误槽/值槽必须按成员类型选 `NULL`/`0`，不能统一 `0`。
- **非 ASCII**：字符串字面量必须按 UTF-8 原样进入 `rt_string_from_c`；xnullc 的
  `q`/字符串扫描只保留 ASCII，导致中文丢失。

## 4. 与 regexMatchAt 已实现规则的关系

`xn_regexMatchAt` 已单独收敛的 5 条规则仍只在“该函数路径”成立，尚未泛化：

| 规则 | regexMatchAt 现状 | 仍需泛化到 |
|---|---|---|
| root 分层次数 | 已修正该函数 | `emitStmt`/`emitReturn`/`rootTempDecls` 全语句 |
| while(1) 降级 | 已修正该函数 | `emitWhile` 对所有有 `pending` 的条件 |
| 每个 defer 独立块 + LIFO | 已修正该函数 | `emitBlock`/`emitCleanup` 对所有作用域 |
| blockHeld 尾释放（return 后） | 已修正该函数 | `promoteRoot` + 所有跨作用域赋值 |
| 编号不复用 | 已修正该函数 | `nextTmp`/表达式求值全路径 |

其它函数（xlex、ast-seed、classes、collections、bundle_text 等）仍按旧规则发射，
所以聚类仍显示这些类。修法应是**把 regexMatchAt 的局部规则上移为通用发射器规则**，
而不是逐函数特殊处理。

## 5. 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang
XNULL_BIN=/tmp/xnull-orc XNAST_BIN=/tmp/xnast-orc \
  wt/e4-codegen/tests/b3/xnullc-all.sh --shard 1/1 --parallel 8
# 结果：wt/e4-codegen/evidence/B3-09-harness/out/results.tsv
```

最小复现：本文 §3 的 5 个 `.x` 片段；Go 输出用 `xnull build --emit-c` 生成。
