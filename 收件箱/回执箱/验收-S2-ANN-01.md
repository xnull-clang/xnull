# 验收：S2-ANN-01（注解）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（常量/参数/类型值/new/位置全过；无运行期对象；`@Override`/`@arc`/`@gc` 规则成立）
> **复验点**：main `10941d7`（含 E2 `fc602b7`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/ANN-01/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| A01 编译期字段/参数/方法/构造器/deinit/枚举项注解 | **PASS**：双路径 rc=0 |
| A01 注解参数按字段顺序绑定；省略尾部用初值 | **PASS**：`@Marker` / `@Marker("cls",2)` 均通过 |
| A02 `@Override` 对协议实现 | **PASS**：双路径 `true` |
| 注解字段初始化式必须常量 | **PASS**：`TY-223` + 位置 |
| 注解参数过多 / 类型不匹配 | **PASS**：`TY-223` + 位置 |
| 注解不能作类型 / 不能 `new` | **PASS**：`TY-223` + 位置 |
| 未知注解（类型/枚举项/参数） | **PASS**：`TY-223` + 位置 |
| 同一目标重复注解 | **PASS**：`TY-223` + 位置 |
| 非法目标（`@Override` 字段、`@ReadOnly` 方法） | **PASS**：`TY-223` + 位置 |
| 注解字段必须 final / 常量类型 | **PASS**：`SYN-101` / `TY-223` + 位置 |
| `@Override` 不能标记父类方法 | **PASS**：`TY-203` + `TY-208` + 位置 |
| 源码 `@arc` / `@gc` 拒绝 | **PASS**：`TY-201` + `TY-223` + 位置 |
| 无运行期对象 / 无运行期元数据 | **PASS**：codegen 官方用例 |

**判定：PASS。** `fc602b7` 覆盖的常量、参数、类型值、`new` 与位置诊断全部成立；注解声明/使用在编译期完成，不生成运行期对象。台账 ANN-01 可登记为 PASS。

---

## 二、正例（双路径）

| 用例 | 覆盖 | 解释 | 编译 | 判定 |
|---|---|---|---|---|
| `A01a` 注解类/字段/方法/参数/枚举项 + 参数绑定 | `@Marker("cls",2)`、`@Marker`、`@Marker("m",3)`、`@Marker("p",5)`、枚举项 `@Marker("e",4)` | `x\n7\n`，rc=0 | `x\n7\n`，rc=0 | **PASS** |
| `A01b` 构造器 / `deinit` 注解 | `@A C()`、`@A void deinit()` | rc=0 | rc=0 | **PASS** |
| `A02` `@Override` 对协议方法 | `class C implements P { @Override Bool go() }` | `true`，rc=0 | `true`，rc=0 | **PASS** |

A01a 源码：`evidence/S2-QA/QA-EXTANN2/ANN-01/A01a/source.x`。
A01b 源码：`A01b/source.x`。
A02 源码：`A02/source.x`。

---

## 三、负例（`xnull check`，期望 rc≠0）

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01a_override_field` `@Override` 字段 | `TY-223`: `@Override` 只能用于方法 | **PASS** |
| `R01b_readonly_method` `@ReadOnly` 方法 | `TY-223`: `@ReadOnly` 只能用于字段 | **PASS** |
| `R01c_unknown` 未知注解 | `TY-223`: 未知注解 `@Nope` | **PASS** |
| `R01d_duplicate` 重复注解 | `TY-223`: 同一目标重复使用注解 | **PASS** |
| `R01e_nonfinal` 注解字段非 final | `SYN-101`: 注解体只能声明 `final` 字段 | **PASS** |
| `R02a_type` 注解作类型 | `TY-223`: 注解不是类型 | **PASS** |
| `R02b_new` `new` 注解 | `TY-223`: 不能用于类型位置 / 不能 new | **PASS** |
| `R03a_override_parent` `@Override` 父类方法 | `TY-203` 子类覆写 + `TY-208` `@Override` 不能标记父类方法 | **PASS** |
| `R03b_arc` 源码 `@arc` | `TY-201`: 源码不得使用 `@arc`（+ `TY-223`） | **PASS** |
| `R03c_gc` 源码 `@gc` | `TY-201`: 源码不得使用 `@gc`（+ `TY-223`） | **PASS** |
| `R04a_const` 字段初始化式非编译期常量 | `TY-223`: 必须是编译期常量 | **PASS** |
| `R04b_toomany` 参数过多 | `TY-223`: 注解参数过多 | **PASS** |
| `R04c_type` 参数类型不匹配 | `TY-223`: 参数类型不匹配字段 | **PASS** |
| `R04d_enum_unknown` 枚举项未知注解 | `TY-223`: 未知注解 | **PASS** |
| `R04e_param_unknown` 参数未知注解 | `TY-223`: 未知注解 | **PASS** |
| `R04f_fieldtype` 注解字段非常量类型 | `TY-223`: 字段类型 `Int[]` 不是编译期常量类型 | **PASS** |

所有诊断带 `file:line:col`。

---

## 四、无运行期对象

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/codegen/s2_object_test.go:TestS2ANN01NoRuntimeOverhead` | **PASS** | 注解字段/参数值不进入产物；`@Override` 不进产物 |
| `internal/codegen/s2_object_test.go:TestS2ANN01UnknownAnnotationNeutral` | **PASS** | 注解不影响代码生成 |

---

## 五、边界（不属于 ANN-01 台账门）

**`@ReadOnly` 外部写未强制**：`P01_readonly_external` 中 `@ReadOnly Int x` 被外部 `c.x = 3` 写入，`check` rc=0，双路径输出 `2\n3\n`。按 §12.3，`@ReadOnly` 是强制注解；但 ANN-01 台账门只列「编译期字段/参数、目标限制、无运行期对象、`@Override`、`@arc/@gc`」，未列 `@ReadOnly` 写保护，故本回执按边界记录，归 FIELD-01 / BND-01 的字段只读面。若董事会将 `@ReadOnly` 写保护纳入 ANN-01，则该项应判 FAIL。

---

## 六、官方用例

| 用例 | 结果 |
|---|---|
| `internal/sema/s2_ann_test.go:TestS2ANN01` | **PASS** |
| `internal/sema/s2_ann_b_test.go:TestS2ANNbRules` | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2ANN01NoRuntimeOverhead` | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2ANN01UnknownAnnotationNeutral` | **PASS** |

---

## 七、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2ANN01\|TestS2ANNbRules' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2ANN01' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp -count=1` | **PASS** |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

---

## 八、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/ANN-01/A01a/`、`A01b/`、`A02/`、`R01a/`–`R04f/`、`P01_readonly_external/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/ANN-01/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/sema-ann-ext.log`、`codegen-ann-ext.log`、`sema-interp-full.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §12.1–§12.4、§16 ANN-01
