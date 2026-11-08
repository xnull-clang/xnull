# B3 root 发射规范（Go codegen 现行行为）

> 只描述现行 Go 实现（B3-00 冻结 oracle），供 E2 对齐 C 文本。不是新规范。
> 代码位置：`impl/internal/codegen/codegen.go`（root prelude、`emitBlock`、
> `emitStmt`、`emitAssign`、`emitReturn`、`rootTempDecls`、`promoteRoot`）。
> 运行时语义：`xn_root_add/hold` 按对象去重计数；`xn_root_release` 递减；
> `xn_root_restore(mark)` 弹出标记之后的全部根并逐个 release。

## 1. 三种操作的角色

| 操作 | 语义 | 何时出现 |
|---|---|---|
| `xn_root_add(obj)` | `hold` 一次 + 压入当前深度（可被 `restore` 弹出） | 局部声明、表达式临时、同作用域赋值 |
| `xn_root_hold(obj)` | 仅增加持有计数，不压栈（块退出不自动释放） | 跨作用域赋值的新值；静态字段替换 |
| `xn_root_release(obj)` | 计数递减/移除根 | 跨作用域赋值前释放旧值；声明作用域退出释放 hold 根 |
| `xn_root_restore(mark)` | 弹栈直到 mark，逐个 release | 块退出、return、break/continue、任务体出口 |

## 2. 函数入口

1. 函数/方法/构造器作用域创建时先分配函数根帧号（`sc.rootMark = nextTmp()`），
   在函数体第一行输出 `size_t xn_tN = xn_root_mark();`。
2. **GC 参数**按形参声明顺序输出 `xn_root_add(xn_p_x);`（`rootPrelude`），
   紧跟在函数根帧之后；非 GC 参数不登记。
3. 方法/构造器的 `self` 也按 GC 类型登记：`xn_root_add(self);`（在 prelude）。
4. 函数根帧的释放由 return 路径或函数体块退出时的 `xn_root_restore` 完成。

## 3. 块与根帧

- 每个子块（if/else/while/for-in/switch case/try/普通块）由 `newChild()` 创建时
  **立即分配**一个根帧号；块开始输出 `size_t xn_tN = xn_root_mark();`。
- 块正常退出：先输出本块 `blockHeld` 的 `xn_root_release`，再按注册逆序执行
  defer（每个 defer 包在 `{}` 中），其中包含本块的 `xn_root_restore`。
- 空块也占一个根帧号，但不产生任何 root 操作（只有 mark 未使用）。
- `break`/`continue`：`emitRootRestores` 从当前作用域向外，逐个输出已声明根帧的
  `xn_root_restore`，到最近 loop（continue）或 loop/switch（break）为止。
- `return`：`emitCleanup` 从最内层向最外层执行全部 defer，根帧 restore 按
  defer 注册逆序出现；因此嵌套 return 先恢复子块、再恢复函数根帧。

## 4. 局部声明

- GC 类型局部（`String/Bytes/Text/SB/容器/GC 类/Any/协议`）在声明行后输出
  `xn_root_add(var);`，随后 `xn_gc_safepoint();`（非 deinit 体）。
- 表达式临时：`rootTempDecls` 扫描语句的临时声明行，在声明后插入
  `xn_root_add(tmp);`。注意：该后处理在 `emitStmt` 与 `emitReturn` 多层调用，
  **同一临时可能出现多次 `xn_root_add`**（例如 text.x 中同一条 Err 临时可见
  2–3 次）；这是幂等计数，块退出时由同一根栈条目数一对一 release。
- 局部声明本身不带 `root_release`；由块退出 `root_restore` 统一释放。
- 非 GC 局部（Int/Bool/Float/枚举/结构体值）无 root 操作。

## 5. 赋值

分两类，取决于目标变量**声明在哪个作用域**（`promoteRoot`）：

### 5.1 同作用域赋值（目标在本块声明）

```c
target = value;          // 类引用另有 rt_release/retain 规则
xn_root_add(target);     // 旧值的根仍保留到块退出
```

- 旧值的 `xn_root_add` 不会被撤销（“旧值保留登记到块退出”），因此同一变量
  多次赋值会积累多个根条目；块退出 `root_restore` 全部弹出。

### 5.2 跨作用域赋值（目标在祖先块声明）

```c
xn_root_release(target); // 释放旧值的根（在覆盖前）
target = value;
xn_root_hold(target);    // 新值用 hold，块退出不弹
```

- 新值登记到**目标声明作用域**的 `blockHeld` 列表；该作用域退出时输出
  `xn_root_release(target);`（若 return 已生成，该行可能落在 `return` 之后，
  属不可达文本，但保序输出）。
- 循环体内反复给外层变量赋值：每轮 release 旧、hold 新，根计数保持 1，
  不会随迭代累积；这也是该规则的主要动机。
- `Result` 局部赋值只做结构体赋值，不额外 root（见 §8）。

## 6. String 临时

- 字符串字面量：`rt_string *t = rt_string_from_c("...");` + `xn_root_add(t);`
- 标识符拼接/成员读取：先 `rt_string *t = rt_retain(x);` + root；
- 二元 `+`：先求左右（各自临时与 root），最后
  `rt_string *t = xn_concat(L,R);` + root（`xn_concat` 接管两侧所有权）。
- 插值串：静态片段与表达式交替，每个片段一个临时 + root，累积拼接临时 + root。
- 方法返回值（`substring/indexOf/trim/...`）：返回临时 + root。
- 所有字符串临时由所在块退出 `root_restore` 释放；循环体每轮重新登记/释放。

## 7. if/else、循环

- `if`：条件临时与 root 在 **then 块根帧之前**；then 块 mark 后是 then 体；
  else 块 mark 在 then 体之后。
- `while`：条件临时先于循环体根帧；
  若条件产生前置语句（降级 `while(1)`），前置语句在循环内、块根帧之后。
- `for-in`：**先创建循环体作用域并发射体**，再分配循环下标临时；因此体临时/
  根帧号可能小于下标号；根操作顺序按代码文本（体在内层 mark 下，下标在外部）。
- `switch`：先求匹配值/各 case 条件（root 在 do 块外），再为每个 case/default
  创建根帧并发射体；case 临时在体前释放（`rt_release`，不是 root release）。

## 8. return、Ok/Err、方法尾

- return 表达式先求值（临时 root 已插入），随后：
  - 标量/Float：返回槽临时；
  - String：`rt_retain` 后返回，清理仍执行；
  - Result：`xn_ret = <Ok/Err 结构>`；**Result 结构本身与其 GC 载荷不额外
    root_add**（载荷仅靠表达式临时根活到 return 前的 restore）；
  - 类 new：对象临时，清理执行；
- 清理序列（defer + root_restore）在 `return` 语句**之前**；嵌套块先恢复子块，
  再恢复函数根帧。
- `Ok(x)`/`Err(x)` 只是构造 Result 结构体；不产生 root 操作。
- 方法尾：与函数一致；跨作用域赋值的 `blockHeld` 释放在方法声明作用域退出处
  输出（可能位于 return 之后）。

## 9. text.x 典型函数（生成代码实证）

### 9.1 `Format.build()`（方法 + while + 跨作用域 String 赋值）

```c
size_t xn_t316 = xn_root_mark();   // 方法根帧
xn_root_add(self);
rt_string *res = rt_retain(self->text);
xn_root_add(res); xn_root_add(res);  // 声明 + rootTempDecls 重复
...
while (xn_str_length(res) < self->width) {
    size_t xn_t319 = xn_root_mark(); // 循环体根帧
    rt_string *xn_t320 = rt_retain(unit); xn_root_add(...);
    rt_string *xn_t321 = rt_retain(res);  xn_root_add(...);
    rt_string *xn_t322 = xn_concat(t320,t321); xn_root_add(...);
    xn_root_release(res); rt_release(res);
    res = xn_t322;
    xn_root_hold(res);              // 跨作用域赋值：hold 新值
    { xn_root_restore(xn_t319); }   // 每轮释放临时
}
...
rt_retain(res);
{ rt_release(unit); } { rt_release(res); }
{ xn_root_restore(xn_t316); }
return res;
xn_root_release(res);               // blockHeld 释放（return 后不可达文本）
```

### 9.2 `parseInt(String s)`（参数 + Err 分支 + 嵌套 return）

```c
xn_Result_Int_Error xn_ret;
size_t xn_t87 = xn_root_mark();
xn_root_add(xn_p_s);                // GC 参数
...
if (n == 0) {
    size_t xn_t88 = xn_root_mark();
    rt_string *xn_t89 = rt_string_from_c("parseInt: 空串");
    xn_root_add(xn_t89);            // 可能重复 2–3 次
    xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t89)};
    { xn_root_restore(xn_t88); }    // 先子块
    { xn_root_restore(xn_t87); }    // 再函数根帧
    return xn_ret;
}
```

### 9.3 `utf8ToUtf16(Bytes b)` / `parseFloat`

- `Bytes b` 为 GC 参数 → 函数 prelude `xn_root_add(xn_p_b)`；
- `List<UInt16> res = []` → 声明后 `xn_root_add(res)`；
- while 条件/体各自根帧；`b.get(i)` 返回标量，无 root；
- `res.push(...)` 不新增 root；
- `Err(...)` 分支与 parseInt 同型：消息临时 root → 子块 restore → 函数 restore → return；
- 嵌套循环（parseFloat 的小数/指数段）每层一个根帧，inner restore 先于 outer。

## 10. E2 对齐检查表

1. 函数根帧 + GC 参数 prelude 的顺序与号。
2. 每个子块都占号并输出 mark；空块也占号。
3. GC 局部：声明行后 root_add（可重复）；临时声明行后 root_add。
4. 同作用域赋值：仅追加 root_add（旧根不撤销）。
5. 跨作用域赋值：release 旧 → 赋值 → hold 新；目标声明作用域退出 release。
6. String：字面量/retain/concat 各自临时，先操作数后结果。
7. return：表达式临时 → 清理（defer/restore，内→外）→ 返回；`xn_ret` 无 root。
8. break/continue：从内向外 restore 到最近 loop/switch。
9. 循环体：每轮 mark/restore，临时 root 不跨迭代累积。
10. 重复 `xn_root_add` 是常见现象，按出现次数逐字对齐，不要“去重优化”。
