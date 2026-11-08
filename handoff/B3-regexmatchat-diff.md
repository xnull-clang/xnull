# regexMatchAt：Go `--emit-c` vs xnullc 逐行差异

> 输入：`tests/b3/fixtures/bundle_text/app.x`（`text.x` 包）
> Go 侧：`xnull build --emit-c`；xnullc：`xnull run --interp impl/lib/b3/xnullc.x`
> 函数：`xn_regexMatchAt`（Go 第 2794 行起；xnullc 第 2749 行起）
> 结论先行：**不是字符串/Err 语义差异**，而是
> ①`rootTempDecls` 的分层次数不匹配；②带临时条件的 while 未降级为 `while(1)`；
> ③temp 编号复用了已释放号；④defers 的块拆分/LIFO 顺序；⑤blockHeld 尾释放缺失。

## 1. 关键 diff 段

### 1.1 root 次数：同一临时多/少一行

```diff
 rt_string *c = xn_str_substr(xn_p_pattern, xn_p_pi, 1);
 xn_root_add(c);
 xn_root_add(c);
+xn_root_add(c);                 // xnullc 多 1
 ...
 rt_string *xn_t225 = rt_retain(c);
 xn_root_add(xn_t225);
+xn_root_add(xn_t225);           // xnullc 多 1
 rt_string *xn_t226 = rt_string_from_c("$");
 xn_root_add(xn_t226);
+xn_root_add(xn_t226);           // xnullc 多 1
```

```diff
 rt_string *xn_t250 = rt_retain(xn_p_pattern);
 xn_root_add(xn_t250);
-        xn_root_add(xn_t250);
             xn_root_add(xn_t250);
 rt_string *xn_t251 = rt_retain(xn_p_text);
 xn_root_add(xn_t251);
-        xn_root_add(xn_t251);
             xn_root_add(xn_t251);
```

→ xnullc 在顶层临时上**多 1 次**，在嵌套 return 实参上**少 1 次**。

### 1.2 while 条件 temp：Go 降级 `while(1)`

```diff
-            while (1) {
-                rt_string *xn_t239 = rt_retain(c);
+        rt_string *xn_t239 = rt_retain(c);
 ...
-                if (!((((k < xn_str_length(xn_p_text))) && (xn_regexAtomMatch(xn_t239, xn_t240))))) { break; }
-                size_t xn_t241 = xn_root_mark();
-                #line 318 ...
-                count = (count + 1);
-                #line 319 ...
-                k = (k + 1);
-                    {
-                    xn_root_restore(xn_t241);
-                    }
+            while ((((k < xn_str_length(xn_p_text))) && xn_regexAtomMatch(xn_t239, xn_t240))) {
+            size_t xn_t241 = xn_root_mark();
 ...
```

→ xnullc 把条件临时放在循环外、直接 `while(cond)`；Go 在条件有前置语句时生成
`while(1){ 前置; if(!(cond)) break; 体 }`，前置/条件/体各多 4 空格缩进。

### 1.3 递归调用 temp 编号复用

```diff
-        rt_string *xn_t260 = rt_retain(xn_p_pattern);
-xn_root_add(xn_t260);
-        rt_string *xn_t261 = rt_retain(xn_p_text);
+        rt_string *xn_t261 = rt_retain(xn_p_pattern);
+        rt_string *xn_t262 = rt_retain(xn_p_text);
 ...
-        int xn_t262 = xn_regexMatchAt(xn_t260, (xn_p_pi + 1), xn_t261, (xn_p_ti + 1));
+        int xn_t260 = xn_regexMatchAt(xn_t261, (xn_p_pi + 1), xn_t262, (xn_p_ti + 1));
```

→ xnullc 复用了已释放的 `xn_t260` 作为**调用结果**；Go 编号单调递增，
结果号一定大于全部实参临时号。

### 1.4 函数尾 defers / blockHeld

```diff
     {
+rt_release(c);
 rt_release(next);
     }
     {
-rt_release(c);
-    }
-    {
 xn_root_restore(xn_t221);
     }
 
 return xn_t263;
-xn_root_release(next);
 }
```

→ Go：`next`、`c` 各自独立 `{}` 块，`next` 先释放（声明序逆序），最后 root_restore；
return 之后仍有 `xn_root_release(next)`（跨作用域赋值的 blockHeld 尾释放，虽不可达但保序输出）。
xnullc：把 `c`/`next` 合并到一个块且顺序反了，并缺少 `xn_root_release(next)`。

## 2. 精确规则（Go 现行）

### 2.1 `rootTempDecls` 的重复次数 = 语句嵌套层数（不是固定 +1）

- `emitStmt` 对**整条语句**做一次 `rootTempDecls`；嵌套语句先被子语句 emitStmt
  处理，再被每层祖先语句的 emitStmt 处理一次。
- GC 局部声明还额外有 `emitStmtInner` 的 `xn_root_add`。
- 因此本函数实测：
  | 位置 | Go root_add 次数 | 组成 |
  |---|---:|---|
  | 函数体顶层局部 `String c` | 2 | 局部声明 1 + 本语句 rootTempDecls 1 |
  | 顶层 `if` 条件临时 t225/t226 | 1 | if 语句 rootTempDecls 1 |
  | `if` 内 `while` 条件临时 t239/t240 | 2 | while 语句 1 + 外层 if 语句 1 |
  | `if→while→if` 内 return 实参 t250/t251 | 3 | return 1 + 内 if 1 + while 1 |
- xnullc 当前近似“固定 +1”，所以顶层/局部多 1、深层 return 少 1。
  对齐方法：按同一棵**语句嵌套树**逐层应用 rootTempDecls，而不是按临时类型统一加。

### 2.2 while 条件含临时

- 条件求值若产生 `s.pending`（字符串临时/方法返回临时），Go 降级：
  ```c
  while (1) {
      <条件前置语句>            // +4 缩进
      if (!(cond)) { break; }   // +4
      <循环体>                  // +4
      xn_gc_safepoint();        // +4
  }
  ```
- 前置临时在循环内每轮求值、每轮 root_add；循环体根帧在 `if(!cond)` 之后。
- 无前置语句时才输出普通 `while (cond)`。
- xnullc 必须按“条件是否有前置语句”决定降级，而不是统一普通 while。

### 2.3 缩进

- 4 空格/层；`while(1)` 降级会额外增加一层（前置、条件、体、safepoint 都 +4）。
- 每个 defer 独立 `{ ... }`，不合并；defer 顺序按注册逆序（LIFO）。
- xnullc 的 while 分支少一层缩进，且把多个 defer 合并为一个块。

### 2.4 temp 编号

- `xn_tN` 单元内单调递增，不复用已释放号；先实参（左→右）后结果。
- `return regexMatchAt(rt_retain(pattern), ..., rt_retain(text), ...)`：
  pattern 临时 → text 临时 → 调用结果；结果号最大。
- 根帧号也在同一序列中分配；xnullc 的“空闲号复用”必须取消。

### 2.5 defers / blockHeld 尾释放

- 每个 defer 独立块；逆注册序：本函数为 `next` 先、`c` 后（`next` 后声明）。
- 跨作用域赋值的变量（`next = ...` 在内层 if 中赋值、声明在函数体）：
  新值走 `xn_root_hold`，并在**声明作用域**（函数体）退出时输出
  `xn_root_release(next);`；该行位于 `return` 之后，仍须输出。
- 函数根帧 restore 在 defer 之后：`next`、`c` 释放块 → `xn_root_restore(t221)`。

### 2.6 String 索引/长度与 Err

- 本函数两者**无差异**：`xn_str_length(x)`、`xn_str_substr(s, start, 1)` 参数/顺序
  一致；差异仅是临时位置/root 次数/缩进。
- 本函数没有 `Err` 构造（返回 Bool）；`Err` 差异应去 `Regex.compile` 查，
  不归因到 `regexMatchAt`。

## 3. E2 修复清单（只针对本函数）

1. rootTempDecls 按语句嵌套层数执行；顶层临时 1、循环条件 2、深层 return 3。
2. while 条件有前置语句 → `while(1)` 降级 + 每层 +4 缩进 + `if(!(cond)) break;`。
3. temp 编号禁止复用；先实参后结果。
4. 每个 defer 独立 `{}`；按声明逆序释放（`next` 先、`c` 后）。
5. 函数体作用域退出补 `xn_root_release(<跨作用域赋值目标>)`（即使 return 之后）。
6. 校验 `xn_regexMatchAt` 的 105 行归一化 diff：预计 1.1–1.5 覆盖全部行。
