# 验收：S2-BND-13（扩展限制）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（class/struct/singleton/数据 enum 扩展全过；跨包扩展已拒绝）
> **复验点**：main `10941d7`（含 E2 `7d92ecc`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/BND-13/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| A01 同包非泛型 class 扩展 | **PASS**：双路径 `L:x` |
| A01 同包非泛型 struct 扩展 | **PASS**：双路径 `6` |
| A01 同包非泛型 singleton 扩展 | **PASS**：双路径 `4` |
| A01 同包非泛型数据 enum 扩展 | **PASS**：双路径 `true/false` |
| A01 合法重载（同名不同元数/类型） | **PASS**：双路径 `1/2/5` |
| A02 扩展不进入 vtable；静态派发不变 | **PASS**：`c.g()=2`、`p.f()=1` |
| R01 重复 / 同签名 / 已有 / 继承 / 覆写 | **PASS**：`TY-225` / `TY-203` + 位置 |
| R02 以扩展实现协议 | **PASS**：`TY-208` + 位置 |
| R03 泛型 / 预定义 / 简单枚举目标 | **PASS**：`TY-225` + 位置 |
| R03 跨包目标 | **PASS**：`TY-225` + 位置 |
| R04 private/protected 成员访问 | **PASS**：`TY-225` + 位置 |

**判定：PASS。** `7d92ecc` 补上了 singleton/数据 enum 目标放行与跨包扩展拒绝；BND-13 的目标集合、冲突、协议、可见性、不进入 vtable 全部成立。台账 BND-13 可登记为 PASS。

---

## 二、A01 同包非泛型目标（双路径）

| 用例 | 期望 | 解释 | 编译 | 判定 |
|---|---|---|---|---|
| `A01_class` class 扩展 | `L:x` | `L:x`，rc=0 | `L:x`，rc=0 | **PASS** |
| `A01_struct` struct 扩展 | `6` | `6`，rc=0 | `6`，rc=0 | **PASS** |
| `A01_singleton` singleton 扩展 | `4` | `4`，rc=0 | `4`，rc=0 | **PASS** |
| `A01_dataenum` 数据 enum 扩展 | `true\nfalse\n` | `true\nfalse\n`，rc=0 | 同左，rc=0 | **PASS** |
| `A01_overloads` 合法重载 | `1\n2\n5\n` | `1\n2\n5\n`，rc=0 | 同左，rc=0 | **PASS** |

规范依据：§11.1「目标类型必须是同包声明的非泛型 `class`、`struct`、`singleton` 或数据 `enum`。」

---

## 三、A02 不进入 vtable

夹具：`A02_vtable/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `2\n1\n`，rc=0 | **PASS** |
| `run`（编译） | `2\n1\n`，rc=0 | **PASS** |
| codegen 静态断言 | vtable 初始化区无 `_ext_`；只含协议槽 | **PASS** |

---

## 四、负例

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01a_dup_ext` 重复 extension | `TY-225`: 同一类型 `C` 存在重复 extension | **PASS** |
| `R01b_same_existing` 与目标方法同签名 | `TY-225`: 与已有/继承/其他扩展同签名 | **PASS** |
| `R01c_same_inherited` 与继承方法同签名 | `TY-225`: 同上 | **PASS** |
| `R01d_subclass_override` 子类覆写扩展 | `TY-203`: 子类方法 `f` 覆写了扩展方法 | **PASS** |
| `R02_protocol_impl` 以扩展实现协议 | `TY-208`: 类 `C` 未实现协议 `P` 的方法 `f` | **PASS** |
| `R03a_generic` `extension Box<Int>` | `TY-225`: Target 不能写泛型实参 | **PASS** |
| `R03c_predef` `extension Int` | `TY-225`: 不能扩展预定义类型 | **PASS** |
| `R03d_simple_enum` 简单枚举目标 | `TY-225`: Target 必须是同包非泛型 class/struct/singleton/数据 enum（得到 enum） | **PASS** |
| **`R03b_crosspkg` 跨包 `Device`** | `TY-225`: extension 不能跨包扩展 `Device`（§11.4） | **PASS** |
| `R04a_private` 扩展读 private | `TY-225`: 只能访问目标公开成员 | **PASS** |
| `R04b_protected` 扩展读 protected | `TY-225`: 只能访问目标公开成员 | **PASS** |

---

## 五、官方用例

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/sema/s2_ext_b_test.go:TestS2EXTbTargets` | **PASS** | singleton/数据 enum 允许；跨包拒绝 |
| `internal/sema/s2_ext_test.go:TestS2EXT01` | **PASS** | class 目标 + 冲突/可见性负例 |
| `internal/codegen/s2_object_test.go:TestS2BND13ExtensionClass` | **PASS** | class 扩展静态派发 |
| `internal/codegen/s2_object_test.go:TestS2BND13ExtensionStructSingleton` | **PASS** | struct/singleton 扩展 |
| `internal/codegen/s2_object_test.go:TestS2BND13ExtensionNotInVtable` | **PASS** | 不进入 vtable |
| `internal/codegen/s2_object_test.go:TestS2EXT01ExtensionOverloads` | **PASS** | 合法重载 |

---

## 六、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2EXT01\|TestS2EXTbTargets' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2BND13\|TestS2EXT01' -count=1` | **PASS** |
| `go test ./internal/interp -run 'TestS2ExtensionMethods' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp -count=1` | **PASS** |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

---

## 七、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/BND-13/A01_class/`、`A01_struct/`、`A01_singleton/`、`A01_dataenum/`、`A01_overloads/`、`A02_vtable/`、`R01a/`–`R01d/`、`R02_protocol_impl/`、`R03a/`–`R03d/`、`R04a/`–`R04b/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/BND-13/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-EXTANN2/sema-ann-ext.log`、`codegen-ann-ext.log`、`interp-ext.log`、`sema-interp-full.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §11.1–§11.4、§16 BND-13
