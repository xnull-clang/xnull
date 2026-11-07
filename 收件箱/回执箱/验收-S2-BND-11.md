# 验收：S2-BND-11（值 / 身份 / ABI）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（结构体值复制、类身份、vtable 槽位、sret 值语义全部成立）
> **复验点**：main `47fedb8`（`47fedb8ad1659925af04a677a9e82b861c2dffcd`）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/BND-11/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 结构体按值复制（赋值） | **PASS**：`1 / 10 / 3 / 12` 双路径一致 |
| 结构体按值复制（传参 / 返回 / 嵌套字段） | **PASS**：codegen 官方用例 |
| 类对象身份不被优化改变（`===` / `==` / `!==`） | **PASS**：`true / false / true` 双路径一致 |
| vtable 只含协议方法槽位 | **PASS**：普通方法未进入 vtable |
| 地址 + sret ABI 不暴露共享身份 | **PASS**：返回/传参后副本独立 |
| `S2-BND11-D01` 双路径一致 | **PASS**：0 mismatch |

**判定：PASS。** 四项发布门槛均有可执行证据；台账 BND-11 可从「未实现」登记为 PASS。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-BND11-A01` struct 赋值复制独立 | `1\n10\n3\n12\n` | `1\n10\n3\n12\n`，rc=0 | `1\n10\n3\n12\n`，rc=0 | **PASS** |
| `S2-BND11-A02` class 身份保持 | `true\nfalse\ntrue\n` | `true\nfalse\ntrue\n`，rc=0 | `true\nfalse\ntrue\n`，rc=0 | **PASS** |

A01 语义：`Point b = a` 后写 `b.x = 10`，`a.x` 仍为 `1`，`a.sum()=3`、`b.sum()=12`。
A02 语义：`C b = a` 与 `a === b` 为 `true`；`C c = new C()` 与 `a === c` 为 `false`；`a == b` 为 `true`。

### 2.2 vtable / ABI（codegen 官方用例）

| 用例 | 断言 | 结果 |
|---|---|---|
| `internal/codegen/s2_object_test.go:TestS2BND11VtableOnlyProtocolSlots` | 生成 C 中存在 `xn_vt_C[0] = (void *)&xn_Cls_C_f;`；普通方法 `g` 不在 vtable | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2BND11StructSretCopy` | `make()` 返回、`pass()` 传参后修改副本，原值不变 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2BND11ClassIdentity` | `==` / `===` / `!==` 与对象身份一致 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2ProtocolVtableLayout` | 协议实现类载荷起始处有 `void **__vtable;` | **PASS** |

布局实现位置：`impl/internal/codegen/struct.go:3`（struct 为无头 C 结构体，赋值/传参/返回即整值复制）、`impl/internal/codegen/protocol.go:184`–`221`（协议类型与 vtable 定义/填充）、`impl/internal/codegen/classes.go:432`（vtable 指针槽）。

### 2.3 双路径

A01/A02 的 `interp.out` 与 `compiled.out` 逐字节相同，rc 均为 0，`D01` 0 mismatch。

---

## 三、边界（不影响本锚点判定）

1. **优化路径未启用**：当前 codegen 的类对象一律 `rt_arc_new`（`impl/internal/codegen/classes.go:8`），无栈优化 / GC 分配；因此「类身份不因优化改变」没有可对照的优化形态，按现有唯一路径验证为保持身份。GC 运行期形态归 MEM-02 / BND-10。
2. **ABI 探针是行为级**：`sret` 用例验证「返回后副本独立」，未使用独立 C harness 读取地址；语义结果与「不暴露共享身份」一致。
3. **M01 的 C 侧探针**：以生成 C 的静态断言 + 运行结果替代独立 C 探针，覆盖「vtable 只含协议槽」与「sret 不共享身份」两项。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS2StructValueCopy\|TestS2BND11ClassIdentity\|TestS2BND11StructSretCopy\|TestS2BND11VtableOnlyProtocolSlots\|TestS2ProtocolVtableLayout' -count=1` | **PASS** |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 13（golden 18）。与本锚点无关，但阻断 GATE-01。 |

---

## 五、证据

- `evidence/S2-QA/BND-11/A01/`、`A02/`（含 `cmd.txt`、`interp.*`、`compiled.*`、`check.*`、`sha.txt`）
- `evidence/S2-QA/qa-a-codegen.log`
- `evidence/S2-QA/qa-a-fulltest.log`、`qa-a-vet.log`
- `evidence/S2-QA/matrix.tsv`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §3.3、§3.6、§5.7、§15.3、§16 BND-11
