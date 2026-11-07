# 验收：S2-BND-09（私有字段与规范名）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 已含 `4b463a7`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-09/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `private name` / `_name` 两种声明映射同一字段 | **PASS** |
| `private _name` 拒绝 | **PASS**：`TY-207` + 位置 |
| `public` / `protected` + `_name` 拒绝 | **PASS**：`TY-207` + 位置 |
| `_` / `__x` / `_1` 基名拒绝 | **PASS**：`TY-207` + 位置 |
| 类内只能裸写 `_name`；`self._name` 拒绝 | **PASS**：`TY-207` + 位置 |
| 裸 `name` 引用私有字段拒绝 | **PASS**：`TY-207` + 位置 |
| 外部 `name` / `_name` 都拒绝 | **PASS**：`TY-207` + 位置 |
| 局部变量 / 参数使用 `_name` 拒绝 | **PASS**：`TY-207` + 位置 |
| 字段基名继承链唯一（含 private 父字段） | **PASS**：`TY-203` + 位置 |
| 同一类 `x` / `_x` 基名冲突 | **PASS**：`TY-203` + 位置 |
| protected 子类访问合法；外部 protected 拒绝 | **PASS**：子类 `self.x` rc=0；外部 `TY-209` |
| 跨包私有字段外部访问拒绝 | **PASS**：`TY-207` + 位置 |
| 跨包继承链基名唯一 | **PASS**：`TY-203` + 位置 |
| `super._name` 不能绕过父类私有可见性 | **PASS**：`TY-207` + 位置，三路径 rc=1 |

**判定：PASS。** `4b463a7` 补上了 `super._name` 的私有可见性检查；BND-09 的声明/类内/外部/继承链/跨包规则全部成立。台账 BND-09 可登记为 PASS。

---

## 二、正例

### 2.1 A01：类内合法路径

夹具：`evidence/S2-QA/QA-BND0914b/BND-09/A01/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `11\n1\n`，rc=0 | **PASS** |
| `run`（编译） | `11\n1\n`，rc=0 | **PASS** |

覆盖：`protected Int x` 由子类 `self.x` 访问；`private Int limit` 类内裸写 `_limit`；`Int _retries` 类内裸写 `_retries`。

### 2.2 补充正例：`private final` 构造器赋值

`private final Int id; C(Int id) { _id = id }` → `check` rc=0，双路径输出 `7`。**PASS**。

---

## 三、负例（`xnull check`，期望 rc≠0）

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01a` `private Int _name` | `TY-207`：`private` 与 `_` 前缀不能同时使用 | **PASS** |
| `R01b` `public Int _name` | `TY-207`：`public`/`protected` 与 `_name` 同时出现 | **PASS** |
| `R01c` `protected Int _name` | `TY-207`：同上 | **PASS** |
| `R01d` `Int _` | `TY-207`：私有字段名 `_` 非法 | **PASS** |
| `R01e` `Int __x` | `TY-207`：私有字段名 `__x` 非法 | **PASS** |
| `R01f` `Int _1` | `TY-207`：私有字段名 `_1` 非法 | **PASS** |
| `R02a` `self._name` | `TY-207`：类内只能裸写 `_name` | **PASS** |
| `R02b` 裸 `name` | `TY-207`：类内只能写 `_name` | **PASS** |
| `R02c` 外部 `w.name` | `TY-207`：外部访问私有字段 | **PASS** |
| `R02d` 外部 `w._name` | `TY-207`：外部访问私有字段 | **PASS** |
| `R02e` 局部变量 `_name` | `TY-207`：与私有字段规范名冲突 | **PASS** |
| `R02f` 参数 `_name` | `TY-207`：与私有字段规范名冲突 | **PASS** |
| `R02g` 父 `Int x` + 子 `Int _x` | `TY-203`：字段基名 `x` 已声明 | **PASS** |
| `R02h` 同类 `Int x` + `Int _x` | `TY-203`：基名在同一类重复 | **PASS** |
| `R02i` 父 `private Int x` + 子 `Int x` | `TY-203`：字段隐藏被拒绝 | **PASS** |
| `R02j` `super._x` 读父类私有字段 | `TY-207`：`super._x` 不能访问父类私有字段；check/interp/compiled 均 rc=1 | **PASS** |

### 3.1 X01 跨包

| 用例 | 实测 | 判定 |
|---|---|---|
| `X01a-name` 导入包后 `c.x`（private） | `TY-207` + 位置 | **PASS** |
| `X01a-underscore` 导入包后 `c._y`（private） | `TY-207` + 位置 | **PASS** |
| `X01b` 跨包继承 `Int x` + 子类 `Int _x` | `TY-203` + 位置 | **PASS** |

---

## 四、官方用例

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/sema/s2_bnd0914b_test.go:TestS2BND0914b` | **PASS** | `super._x` → `TY-207`；final 二次写 → `TY-224`；extension 目标 → `TY-225` |
| `internal/sema/s2_bnd09_test.go:TestS2BND09FieldRules` | **PASS** | 基名冲突 / 外部私有 / protected |
| `internal/sema/typedecl_test.go:TestPrivateFieldRules` | **PASS** | `private _name`、`public/protected _name`、`_`/`__x`/`_1`、`self._name`、裸 `name`、外部两名、局部冲突 |

---

## 五、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND0914b\|TestS2BND09FieldRules\|TestS2BND14NegativeMatrix\|TestPrivateFieldRules\|TestS2Ext' -count=1` | **PASS** |
| `go test ./internal/sema -count=1` | **PASS** |
| `go vet ./internal/sema` | exit 0 |

---

## 六、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-09/A01/`、`R01a/`–`R02j/`、`X01a-name/`、`X01a-underscore/`、`X01b/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-09/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/sema-targeted.log`、`sema-full.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §7.3–§7.4、§16 BND-09
