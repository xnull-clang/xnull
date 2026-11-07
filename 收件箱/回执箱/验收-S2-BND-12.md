# 验收：S2-BND-12（泛型与内存）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（黄金矩阵 R01–R03 + A01 全过）
> **复验点**：main `47fedb8`（含 E4 `ad44263` 泛型类单态化、E2 `9978a7d` 静态成员禁止类类型参数）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-47fedb8`，sha256 `46a22fee8a5523ef1a6061be2a4c73d3adb8c474762a930efa69850c56d14150`
> **证据**：`evidence/S2-QA/BND-12-47fedb8/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §13.3–§13.6、§16 BND-12；`收件箱/门/S2验收计划-QA.md` §2.3 BND-12

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| R01 泛型内 `new T()` | **PASS**：`GEN-104` @2:23 |
| R01 静态成员使用类类型参数 | **PASS**：`TY-214` @2:14（`9978a7d` 修复） |
| R02 泛型协议 | **PASS**：`SYN-101` @1:11 |
| R02 关联类型 | **PASS**：`SYN-101` @2:21 |
| R03 泛型 struct 非值字段类型实参 | **PASS**：`TY-204` @5:17 |
| R03 类型参数不出现在字段仍拒绝 | **PASS**：`TY-204` @5:17 |
| A01 泛型类单态化（补充正例） | **PASS**：解释/编译双路径 `7` |
| 残留类型参数、实例独立布局/方法名 | **PASS**：`TestS2BND12GenericClassBasic/Nested`；`Box<Int>`/`Box<String>` 生成独立 C 名与字段类型 |

**判定：PASS。** §13.4 的禁止面全部命中，泛型类单态化正例双路径一致。  
**注意**：PASS 仅覆盖本轮黄金矩阵（R01–R03 + A01）；泛型 struct 正例与类泛型方法仍为 E4 已声明边界，见 §三。

---

## 二、逐项实测

| ID | 模式 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| `S2-BND12-R01-newT` | check | 泛型内 `new T()` 拒绝 | rc=1；`2:23 error[GEN-104]` | PASS |
| `S2-BND12-R01-staticT` | check | `static T value` 拒绝 | rc=1；`2:14 error[TY-214]` | PASS |
| `S2-BND12-R02-generic-protocol` | check | 泛型协议拒绝 | rc=1；`1:11 error[SYN-101]` | PASS |
| `S2-BND12-R02-assoc` | check | 关联类型拒绝 | rc=1；`2:21 error[SYN-101]` | PASS |
| `S2-BND12-R03-struct-arg` | check | `Box<String>` 作 struct 字段拒绝 | rc=1；`5:17 error[TY-204]` | PASS |
| `S2-BND12-R03-struct-unused` | check | T 不出现在字段仍拒绝 | rc=1；`5:17 error[TY-204]` | PASS |
| `S2-BND12-A01` | interp | `Box<Int>(7).get()` → `7` | `7`，rc=0 | PASS |
| `S2-BND12-A01` | compiled | 同上 | `7`，rc=0 | PASS |
| `S2-BND12-CI` | gotest | `TestS2BND12*` PASS | `TestS2BND12StaticTypeParam`、`TestS2BND12GenericClassBasic/Nested` PASS | PASS |

补充确认：`Box<Int>` 与 `Box<String>` 同程序双实例输出 `7`/`x`，C 侧方法名分别为 `xn_Cls_Box_i_get` / `xn_Cls_Box_s_get`，字段类型分别为 `int64_t` / `rt_string *`，说明单态化发生在具体类型上，未残留 `T`。

---

## 三、边界与遗留风险（不改变本轮判定）

以下正例不在 BND-12 本轮黄金矩阵内，且 E4 回执已明示为“泛型结构体、泛型枚举（E2/后续卡）”边界；但属 §13.1/§13.4 覆盖缺口，建议 GATE-01 前补卡：

| 探针 | 结果 | 说明 |
|---|---|---|
| 泛型 struct 值实参正例 `Cell<Int>` | sema rc=0；codegen `类型 T 未支持` | `probes/generic_struct_int/`；泛型 struct 未单态化发射 |
| 类泛型方法 `U convert<U>(U)` | sema `RES-101 未定义的类型 U` | `probes/class_generic_method/`；方法级类型参数未登记 |
| 顶层泛型函数 `id<T>(T)` | 双路径 `3` | `probes/topfn_generic/`；泛型函数单态化可用 |

建议：E4 补“泛型 struct 发射 + 类泛型方法类型参数”卡；届时 BND-12 可扩为完整 §13 正例矩阵。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND12' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2BND12' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | **1 红**：`internal/devtool TestBuildLedgerRepoGoldenScale`（台账 PASS 13，golden 18）；与本锚点无关，阻断 GATE-01 |

---

## 五、证据

- `evidence/S2-QA/BND-12-47fedb8/matrix.tsv`
- `evidence/S2-QA/BND-12-47fedb8/S2-BND12-R01-{newT,staticT}/check/`
- `evidence/S2-QA/BND-12-47fedb8/S2-BND12-R02-{generic-protocol,assoc}/check/`
- `evidence/S2-QA/BND-12-47fedb8/S2-BND12-R03-{struct-arg,struct-unused}/check/`
- `evidence/S2-QA/BND-12-47fedb8/S2-BND12-A01/{interp,compiled}/`
- `evidence/S2-QA/BND-12-47fedb8/gotest-sema/`、`gotest-codegen/`、`probes/`、`regression/`
- 夹具：`difftest/s2/bnd12/`
