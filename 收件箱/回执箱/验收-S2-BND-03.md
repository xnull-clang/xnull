# 验收：S2-BND-03（派发模型）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（类静态派发、协议 vtable 动态派发、构造/`deinit`/`super` 静态派发全部成立）
> **复验点**：main `47fedb8`（`47fedb8ad1659925af04a677a9e82b861c2dffcd`）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/BND-03/`、`evidence/S2-QA/probes/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 类类型接收者静态派发 | **PASS**：`Base b = new Derived(); b.f()` → `1` |
| 协议类型接收者动态派发（vtable） | **PASS**：`P p = new B(); p.f()` → `2` |
| 协议接收者只能调用协议方法 | **PASS**：`TY-211` + 位置 |
| 类接收者调用派生类独有方法被拒绝 | **PASS（编译路径）**：codegen rc=1；`check` rc=0 的前端缺口见 §四-2 |
| 内存策略不影响 vtable | **PASS（结构性）**：`vptr` 只由协议实现关系决定 |
| 构造器 / `deinit` / `super` 静态派发与顺序 | **PASS**：双路径一致 |
| `S2-BND03-D01` 双路径一致 | **PASS**：A01–A04、M01 0 mismatch |

**判定：PASS。** 派发行为与规范 §5.6–§5.7 一致；台账 BND-03 可从「未实现」登记为 PASS。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-BND03-A01` 类继承静态派发 | `1\n1\n` | `1\n1\n`，rc=0 | `1\n1\n`，rc=0 | **PASS** |
| `S2-BND03-A02` 协议变量动态派发 | `2\n1\n` | `2\n1\n`，rc=0 | `2\n1\n`，rc=0 | **PASS** |
| `S2-BND03-A03` 不同布局/策略下结果一致 | `7\n7\n` | `7\n7\n`，rc=0 | `7\n7\n`，rc=0 | **PASS** |
| `S2-BND03-A04` 构造器 + `super()` + `self.f()` | `B\nD\n1\n3\n` | `B\nD\n1\n3\n`，rc=0 | `B\nD\n1\n3\n`，rc=0 | **PASS** |
| `S2-BND03-M01a` 派生→父类 deinit 链（显式 `super.deinit()`） | `B\nD\n1\ndD\ndB\nafter\n` | 同左，rc=0 | 同左，rc=0 | **PASS** |
| `S2-BND03-M01b` 单类 deinit 次数 | `dD\nafter\n` | 同左，rc=0 | 同左，rc=0 | **PASS** |

A01 语义：`B b = new D()` 后 `b.f()` 按静态类型 `B` 选择 `B.f`，输出 `1`；`D d` 继承同一实现，输出 `1`。
A02 语义：`P` 接收者通过 vtable 选择运行时实现，`B`→`2`、`A`→`1`。
A04/M01 语义：构造顺序 `B`→`D`，`self.f()` 静态到 `B.f`（`1`），`d.g()=1+2=3`；deinit 派生 `dD` 后由显式 `super.deinit()` 输出 `dB`，不重复自动调用父类。

### 2.2 官方用例

| 用例 | 断言 | 结果 |
|---|---|---|
| `internal/interp/s2_dispatch_test.go:TestS2DispatchModel` | 协议动态、类继承静态、类接收者拒绝派生独有方法、协议接收者拒绝协议外方法 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2BND03NullableProtocolAndDeinit` | 可空协议字段 + deinit 链 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2BND11VtableOnlyProtocolSlots` | vtable 只含协议槽，普通方法不进入 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2ProtocolVtableLayout` | 协议实现类载荷起始处有 vtable 指针 | **PASS** |

### 2.3 补充探针（`evidence/S2-QA/probes/`）

| 探针 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `bnd03_class_receiver_proto_method.x`：类接收者调用协议方法 | 静态 `1`；协议接收者 `1` | 双路径 `1\n1\n`，rc=0 | **PASS** |
| `bnd03_super_static.x`：`super.f()` | `2` | 双路径 `2`，rc=0 | **PASS** |
| `bnd03_neg_class_derived.x`：`Base b = new Derived(); b.g()` | 拒绝 | `check` rc=0；`run` compiled rc=1（`codegen：类 Base 没有成员 g`）；interp rc=1 | 见 §四 |

---

## 三、vtable 与内存策略

- vtable 存在性只由协议实现关系决定：
  `impl/internal/codegen/classes.go:252`：
  `ci.vptr = len(d.Protocols) > 0 || (ci.base != nil && ci.base.vptr)`
- vtable 指针槽只在 `vptr` 为真时发射：`impl/internal/codegen/classes.go:432`。
- 协议接收者调用走 `__vtable[slot]`：`impl/internal/codegen/protocol.go:315`；类接收者方法按静态类型直接绑定（`classes_expr.go:200`–`207`）。
- 当前 codegen 所有类对象均 `rt_arc_new`（`classes.go:8`），没有 GC 分配路径；因此「ARC vs GC 不影响 vtable」没有运行期双策略对照，只有上述结构性证据。

---

## 四、边界与缺口（不改变本锚点判定）

1. **A03 夹具未真正构造 ARC/GC 对照**：`difftest/s2/bnd03/a03_policy.x` 实际是「无协议类 `Val` + 有协议类 `Ref`」，输出 `7/7`。它验证了「布局不同不影响方法结果」，但没有 GC 策略路径。codegen 目前全部 ARC；若门禁要求 ARC/GC 双策略运行期证据，A03 需在 GC 分配落地后补夹具重跑。
2. **sema 静态成员解析缺口（归 DISP-01/BND-14）**：`Base b = new Derived(); b.g()` 在 `xnull check` 下 rc=0，只在 codegen/解释路径拒绝。整体编译仍失败，且未进入 vtable；但「只在前端 check 通过」属成员解析/诊断位置缺口，不是 BND-03 的派发行为失败。证据：`evidence/S2-QA/probes/bnd03_neg_class_derived/`。
3. **协议接收者拒绝协议外方法**：`TY-211` + `file:line:col`，三路径一致，无缺口。

---

## 五、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/interp -run 'TestS2DispatchModel' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2BND03NullableProtocolAndDeinit\|TestS2BND11VtableOnlyProtocolSlots\|TestS2ProtocolVtableLayout' -count=1` | **PASS** |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 13（golden 18）。与本锚点无关，但阻断 GATE-01。 |

---

## 六、证据

- `evidence/S2-QA/BND-03/A01/`–`A04/`、`M01a/`、`M01b/`（含 `cmd.txt`、`interp.*`、`compiled.*`、`check.*`、`sha.txt`）
- `evidence/S2-QA/probes/bnd03_class_receiver_proto_method/`、`bnd03_super_static/`、`bnd03_neg_class_derived/`
- `evidence/S2-QA/qa-a-interp.log`、`qa-a-codegen.log`、`qa-a-fulltest.log`、`qa-a-vet.log`
- `evidence/S2-QA/matrix.tsv`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §5.6–§5.7、§6.4、§15.3、§16 BND-03
