# 验收：S4-KIND-01（错误分类）

> **验收人**：QA1（独立质量线）
> **结论：PASS（sema/解释路径；编译路径 `ErrorKind` 归 E4 边界）**
> **复验点**：main `9161cd1`（含 S4-01/S4-02/S4-03/S4-05；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `ErrorKind` 枚举项与附录 A 一致（14 项） | **PASS**：`InvalidArgument..Internal`，sema/interp 两处表一致 |
| `Error` 协议含 `kind()/describe()` | **PASS**：`xdk.errors` 注册 |
| 实现检查：缺 `describe()` 拒绝 | **PASS**：`TY-208` + 位置 |
| 未知 `ErrorKind` 枚举项拒绝 | **PASS**：`TY-206` |
| `kind()` 生命周期内稳定 | **PASS**：同一错误值两次 `kind()` 均 `Io`，相等比较 `true` |
| `describe()` 单行输出 | **PASS**：`io` |
| 编译路径 | **边界**：`codegen：类型 ErrorKind 未支持（M4.1 范围）` |

**判定：PASS（KIND-01 的 sema/解释门）。** 14 个分类、`Error` 协议、实现检查与 `kind` 稳定性全部成立；编译路径 `xdk.errors/ErrorKind` 属 E4 M4.1 边界，按 S4-01/S4-02 的 sema/interp 范围不计入本轮失败。

---

## 二、ErrorKind 枚举项

sema `registerXdkErrors` 与 interp `registerBuiltinXDKErrors` 均为：

```text
InvalidArgument, NotFound, AlreadyExists, PermissionDenied,
Io, Network, Timeout, Cancelled, Busy, Unavailable,
DataCorrupted, Unsupported, OutOfMemory, Internal
```

与 S4 §3.1 / 附录 A 的 14 项逐项一致。证据：`KIND-01/kind-items.txt`。

---

## 三、Error 协议与实现检查

| 用例 | 实测 | 判定 |
|---|---|---|
| `class E implements Error` 完整实现 | `check` rc=0 | **PASS** |
| 缺 `describe()` | `TY-208`：未实现协议 `Error` 的方法 `describe` | **PASS** |
| `ErrorKind.Nope` | `TY-206` + 位置 | **PASS** |
| `report`/`kind`/`describe` 解释执行 | `Io\nIo\ntrue\nio\n`，rc=0 | **PASS** |

`kind()` 稳定性：同一 `E` 实例连续两次 `kind()` 均返回 `Io`，`e.kind() == ErrorKind.Io` 为 `true`。

---

## 四、编译路径边界

`kind.x`（`e.kind()` + `describe()`）编译路径：

```text
xnull: 代码生成失败：codegen：类型 ErrorKind 未支持（M4.1 范围）
```

按任务范围（S4-01 `ErrorKind/Error` 协议、S4-02 sema/interp）记为 E4 边界；若董事会要求 KIND-01 双路径，则该项应另判 FAIL。

---

## 五、官方用例

| 用例 | 结果 |
|---|---|
| `internal/sema/s4_01_test.go:TestS4ErrorsProtocol` | **PASS** |
| `internal/interp/s4_02_test.go:TestS4BuiltinXDKErrors` | **PASS** |
| `internal/interp/s4_02_test.go:TestS4ObservationMembers` | **PASS** |

---

## 六、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/sema-s4.log`、`interp-s4.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/KIND-01/`（`source.x`、`interp.out`、`compiled.err`、`kind-items.txt`）
- 断言依据：S4 §2.2/§3.1/§10、附录 A
