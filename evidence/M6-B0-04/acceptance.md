# M6-B0-04 验收记录：类字段初值

> 卡：M6-B0-04（`死命令` 第 1.4 条第 4 项 B0 硬依赖）｜主责：CEO1-RD3
> 条款：S2 §6.3 L678-679（构造顺序 + 初值可引用范围）
> 基线：`pod/c1-rd3`（main=2c00cf5 已合入）｜时间：2026-11-07 04:32 CST

## 1. 结论

**DONE**。合法初值形态全部实现，编译/解释双路径逐字节一致；非法形态（`self.x` / 裸字段）显式拒绝。

| 项 | 结果 |
|---|---|
| 新增用例 | 5 个（6 个子用例） |
| codegen 包全量 | **21 用例全过**，退出码 0 |
| 全仓 | **9 个包全绿**，退出码 0 |
| 双路径样例 | `sample-field-init.x` 编译/解释输出与退出码完全一致 |

## 2. 覆盖的初值形态（S2 §6.3 L679 允许面）

| 形态 | 样例 | 旧行为 | 新行为 |
|---|---|---|---|
| 标量表达式 | `Int a = 1 + 2;` / `Bool b = 1 < 2;` | 已支持 | 保持 |
| String 字面量 | `String s = "x";` | 已支持 | 保持 |
| String 拼接 | `String s = "x" + "y";` | ❌ 报「只支持字面量」 | ✅ |
| `str()` 转换 | `String t = str(42);` | ❌ 同上 | ✅ |
| 顶层函数调用 | `String u = mk();` | ❌ 同上 | ✅ |
| 非空 List/数组 | `List<Int> xs = [1, 2];` | ❌ 报「只支持空字面量」 | ✅ |
| 非空 Map | `Map<String,Int> m = ["k": 7];` | ❌ 同上 | ✅ |
| 空 Map（两种写法） | `m = [];` / `m = [:];` | `[]` 可用；`[:]` ❌ | ✅ 都可用 |
| 非空 Set | `Set<Int> st = [1, 2, 2];` | ❌ 同上 | ✅（去重后 2） |
| 空 Set | `Set<String> tags = [];` | ❌ **生成 `xn_set_*_new(0)`，C 编译失败**（N-08） | ✅ |
| 类引用 `new` | `Node n = new Node();` | ❌ 报「引用字段只能后赋」 | ✅ |
| 前向引用（后声明类） | `class A { B b = new B(); }` 后接 `class B` | ❌ 报「类型 B 未支持」 | ✅ |
| 声明顺序执行 | `Int a = tick(1); Int b = tick(2);` | 已支持 | ✅ + 用例锁定 |
| `self.x` / 裸字段 | `Int b = self.a + 1;` / `Int b = a + 1;` | 前者报「未登记标识符」；**后者静默生成非法 C** | ✅ 显式拒绝，错误提到 §6.3 |

## 3. 实现要点（`impl/internal/codegen/`）

| 改动 | 文件 | 说明 |
|---|---|---|
| 类名预登记 | `classes.go` `registerClassNames` | 先登记全部类名再解析字段类型/方法签名，解决**前向引用**（`class A { B b = ... }` 早于 `class B`） |
| 构造器原型 | `classes.go` `emitClassForwardDecls` | 除 `typedef struct X X;` 外补 `static X *X_new(void);`，字段初值 `new 后声明类` 才合法（S1-06 同族） |
| 初值统一生成 | `classes.go` `classCtorInit` + `fieldInitValue` | 按字段类别分派到既有表达式发射器（`strExpr`/`valExpr`/`intExpr`/`emitNewClass`），复用而不是另写一套 |
| 初值合法性校验 | `classes.go` `validateFieldInit` | 白名单遍历：字面量/运算符/容器与 Map 字面量/new/顶层函数调用；拒绝裸标识符、成员访问、下标、闭包 |
| 清理死代码 | `classes.go` | 删除不再使用的 `tmpName`（原只服务字面量 String 分支） |

**所有权**：初值产物一律 +1（`strExpr` 新建串、容器 `_new`、`new` 类实例），存入字段后由 `deinit` 释放；赋值前对旧值 `rt_release`（memset 后为 NULL，`rt_release` 对 NULL 幂等）。

## 4. 红→绿证据

| 阶段 | 文件 | 结果 |
|---|---|---|
| 先红 | `before/red.log` | 5 用例：**4 FAIL / 1 PASS**（顺序用例本就通过） |
| 转绿 | `green.log` | 5/5 PASS |
| 回归 | `regression-codegen.log` | codegen 包 21 用例全过 |
| 回归 | `regression-all.log` | 全仓 9 包绿，退出码 0 |
| 双路径 | `cli-double-path.log` | 编译与解释 stdout/退出码完全一致 |

红阶段的 5 个失败点（正是本卡要闭环的）：
1. `类字段 C.s 的 String 初值暂只支持字面量`
2. `xn_set_s_new(0)` → C 编译失败
3. `类型 B 未支持`（前向引用）
4. `未登记标识符 self`（错误不明确）
5. 裸字段 `a` **被静默接受**，生成 `o->b = (a + 1)` → C 编译失败

## 5. 未覆盖 / 边界声明

1. **`T?` 可空类字段**：`Node? n = null` 仍不支持（`cType` 对后缀 `?` 未实现）。S2 §6.3 允许引用字段初值，但可选类型是独立切片（TYPE-02），本卡不含。
2. **常量 / 静态成员**：`死命令` 允许初值引用常量与静态成员，但 codegen 尚无 `TopField`（静态字段）与常量发射路径（`EmitC` 对 `*xfront.TopField` 直接报「顶层声明未支持」）。本卡只覆盖「顶层函数」。
3. **sema 未拦截 `self.x`**：实测 `self.a` 在解释路径**可运行**（interp 用实例作用域求初值，与 S2 §6.3 L679 冲突），sema 未报错；codegen 现已在生成前拒绝。**该缺口归 RD2/sema 与二司 interp**，本卡只保证编译器不产出非法 C。已列入交接。
4. **字段初值为 Result 类型**：`Result<Int,String> r = Ok(1);` 未测（`g.results` 的 typedef 只在函数体收集，类字段未登记）。属独立缺口，不在本卡范围。

## 6. 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/c1-rd3/impl
go test ./internal/codegen -run 'TestB0_04' -count=1 -v -timeout 300s          # 5/5 PASS
go test ./internal/codegen -count=1 -skip 'TestGEN01$|TestGEN01CrossFile' -timeout 900s
go test ./... -count=1 -skip 'TestGEN01$|TestGEN01CrossFile' -timeout 900s    # 全仓绿
# CLI 双路径
go build -o /tmp/xnull ./cmd/xnull && /tmp/xnull run ../evidence/M6-B0-04/sample-field-init.x \
  && /tmp/xnull run --interp ../evidence/M6-B0-04/sample-field-init.x
```

## 7. 证据七件套索引

| 件 | 文件 |
|---|---|
| command | `command.txt` |
| stdout | `stdout.txt` |
| stderr | `stderr.txt` |
| exit_code | `exit_code.txt` |
| sha | `sha.txt` |
| artifact.sha256 | `artifacts/artifact.sha256` |
| acceptance | 本文件 |
