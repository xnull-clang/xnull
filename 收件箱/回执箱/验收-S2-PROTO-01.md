# 验收：S2-PROTO-01（协议）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `b18e6da`（含 E3 `f9a9231` 强持有 deinit 时序；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-PROTO-01b/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 实现检查覆盖父协议（A01） | **PASS**：双路径 `1\n2\n` |
| 协议到父协议 / 类到协议上转（A01） | **PASS** |
| 协议变量只调协议方法（正例） | **PASS**：`p.f()` 双路径 |
| 协议变量调非协议方法（负例） | **PASS**：`TY-211` + 位置 |
| 协议强持有：返回值（A02-hold-return） | **PASS**：双路径 `7\nafter\ndC\n` |
| 协议强持有：字段（A02-hold-field） | **PASS**：双路径 `7\nafter\ndC\n` |
| 协议强持有：A02 组合（返回/字段/块赋值/deinit） | **PASS**：双路径 `7\n7\ndC\n7\ndC\ndC\ndC\n` |
| `is` 类→协议 / 协议→类（A05a/A05b） | **PASS**：双路径 `true` |
| `as?` 协议→类（A05c） | **PASS**：双路径 `true` |
| 类→协议变量上转后动态派发（A05d） | **PASS**：双路径 `1` |
| 协议字段 / 方法体（R01） | **PASS**：`SYN-101` + 位置 |
| 泛型协议 / 关联类型 / 泛型方法 / `where`（R02） | **PASS**：`SYN-101` + 位置 |
| 父协议方法未实现（R03） | **PASS**：`TY-208` + 位置 |
| 缺方法 / 签名不符（R04/R05） | **PASS**：`TY-208` + 位置 |
| D01 A01/A02 双路径一致 | **PASS**：0 mismatch |

**判定：PASS。** `f9a9231` 修复了解释路径的协议强持有：返回值不再在 `make()` 返回时提前 `deinit`，字段强持有也在结束时正确释放；A02 与两个隔离用例的解释/编译输出逐字节一致。台账 PROTO-01 可登记为 PASS。

---

## 二、逐项实测

### 2.1 A01：实现检查含父协议 + 上转

夹具：`evidence/S2-QA/QA-PROTO-01b/A01/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `1\n2\n`，rc=0 | **PASS** |
| `run`（编译） | `1\n2\n`，rc=0 | **PASS** |

`class C implements Child` 同时实现 `Base.base` 与 `Child.child`；`Child p = c`、`Base b = p` 上转后调用正确。

### 2.2 A02：协议强持有（修复项）

夹具：`evidence/S2-QA/QA-PROTO-01b/A02/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `7\n7\ndC\n7\ndC\ndC\ndC\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |
| D01 | stdout 逐字节一致 | **PASS** |

隔离 1：返回值强持有

```x
protocol P { Int f(); }
class C implements P { Int f(){ return 7 } void deinit(){ print("dC") } }
static P make() { C c = new C(); return c }
static Int main() { P p = make(); print(p.f()); print("after"); return 0 }
```

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `7\nafter\ndC\n` | **PASS** |
| `run`（编译） | `7\nafter\ndC\n` | **PASS** |

隔离 2：字段强持有

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `7\nafter\ndC\n` | **PASS** |
| `run`（编译） | `7\nafter\ndC\n` | **PASS** |

对照上一轮失败点：`make()` 返回时不再立即 `deinit`；A02 的 `dC` 次数/顺序从 interp 3 次/错序变为与 compiled 一致的 4 次/正确顺序。

### 2.3 A02neg：只调协议方法（负例）

夹具：`A02neg/source.x`，`P p = new C(); p.g()`：

```text
A02neg/source.x:8:12: error[TY-211]: 协议变量只能调用协议声明的方法（§4.4）：`g` 不在协议合同中
```

`check` rc=1。**PASS**。

### 2.4 is / as 双路径

| 用例 | 期望 | 解释 | 编译 | 判定 |
|---|---|---|---|---|
| `A05a` `c is P` | `true` | `true` | `true` | **PASS** |
| `A05b` `p is C` | `true` | `true` | `true` | **PASS** |
| `A05c` `p as? C` | `true` | `true` | `true` | **PASS** |
| `A05d` `P p = c; p.f()` | `1` | `1` | `1` | **PASS** |

### 2.5 负例

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01a` 协议字段 | `SYN-101`: 协议不能声明字段 | **PASS** |
| `R01b` 协议方法体 | `SYN-101`: 协议方法不能有方法体 | **PASS** |
| `R02a` 泛型协议 `P<T>` | `SYN-101` + 位置 | **PASS** |
| `R02b` 关联类型 `associatedtype T` | `SYN-101` + 位置 | **PASS** |
| `R02c` 泛型协议方法 `T get<T>()` | `SYN-101` + 位置 | **PASS** |
| `R02d` `where T: Any` | `SYN-101` + 位置 | **PASS** |
| `R03` 父协议方法未实现 | `TY-208`: 类 `C` 未实现协议 `Base` 的方法 `base` | **PASS** |
| `R04` 缺方法 | `TY-208` | **PASS** |
| `R05` 返回类型不符 | `TY-208` | **PASS** |

---

## 三、官方用例

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/interp/s2_proto_hold_test.go:TestS2ProtocolStrongHold` | **PASS** | ReturnValue / FieldHold / A02Alignment 三子项 |
| `internal/interp/s2_enum_isas_test.go:TestS2ClassProtocolIsAs` | **PASS** | is/as |
| `internal/interp/s2_enum_isas_test.go:TestS2AsFailure` | **PASS** | as 失败 |
| `internal/sema/s2_proto_test.go:TestS2PROTO01` | **PASS** | 实现检查 / 协议变量限制 / 协议字段 GC 判定 |
| `internal/sema/typedecl_test.go:TestProtocolRules` | **PASS** | 协议形式限制 |
| `internal/codegen/s2_object_test.go:TestS2PROTO01StrongHold` | **PASS** | 编译路径强持有 |
| `internal/codegen/s2_object_test.go:TestS2PROTO01OnlyProtocolMethods` | **PASS** | EmitC 兜底 |
| `internal/codegen/s2_object_test.go:TestS2PROTO01ParentProtocolImpl` | **PASS** | vtable 发射兜底 |

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/interp -run 'TestS2ProtocolStrongHold\|TestS2ClassProtocolIsAs\|TestS2AsFailure' -count=1` | **PASS** |
| `go test ./internal/sema -run 'TestS2PROTO01\|TestProtocolRules' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2PROTO01\|TestS2ProtocolVtableLayout\|TestS2BND11VtableOnlyProtocolSlots' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp -count=1` | **PASS** |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

---

## 五、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-PROTO-01b/A01/`、`A02/`、`A02-hold-return/`、`A02-hold-field/`、`A02neg/`、`A05a/`–`A05d/`、`R01a/`–`R05/`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-PROTO-01b/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-PROTO-01b/interp-proto.log`、`sema-proto.log`、`codegen-proto.log`、`sema-interp-full.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §4.1–§4.5、§15.1、§15.4、§16 PROTO-01
