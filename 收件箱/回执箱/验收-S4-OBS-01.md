# 验收：S4-OBS-01（观测：report）

> **验收人**：QA1（独立质量线）
> **结论：PASS（按裁定修正用例后）**
> **复验点**：main `28e4f19`（含 E4 `82f6a7d` S4-02 report 发射）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-obs1b`，sha256 `074c5cb0a8bb6f34ca682fcd8715851d3060019485be3d83207d23a0be102dce`
> **证据**：`evidence/S4-QA/OBS-01b/`
> **依据**：S4 §2.1、§4.1–§4.3、OBS-01；本轮裁定（report -> void；`[Kind] describe` 以 compiled 为准；mapErr 顶层函数属 E2 缺口）
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `report(Err)` 失败单行 `[Kind] describe` | **PASS**：compiled `[Io] disk` |
| `report(Ok)` 成功零输出 | **PASS**：stdout `true`，stderr 无 Ok 行 |
| `report` 签名 `-> void` | **PASS**：`Result r = report(x)` 报 `TY-101`（正确拒绝；链式期望已删除） |
| 诊断通道无堆分配 | **PASS**：`xn_report_line` 栈缓冲 + `write(2)`，无 malloc |
| 敏感信息 | **PASS（责任边界）**：只输出 kind+describe，不打印栈/argv/env；describe 内容由错误类型设计者负责；换行折叠为单行 |
| 诊断格式 `[Kind] describe` | **PASS（compiled 为准）**：compiled `[Io] disk`；interp `Io: disk` 待 E3 对齐 |
| `mapErr` 顶层转换函数 | **BOUNDARY（E2 缺口）**：ERR-207，按裁定由 E2 修，不阻塞本项 report 判定 |
| 结构体错误 + ErrorKind | **PASS**：`TestS4_02StructErrorAndErrorKind` |

**判定：PASS。** 按裁定删除“report 链式返回原 Result”的错误期望后，report 的单行输出、成功零输出、void 签名、无堆分配与敏感信息责任边界均成立；compiled 诊断格式为 `[Kind] describe`。

---

## 二、修正说明

1. **report 返回 void**：S4 §2.1 明确 `<E: Error>(Result<T,E>) -> void`；删除 `Result again = report(bad)` 用例。该写法现按 `TY-101` 正确拒绝（保留为负例 `report_chain_obsolete.x`）。
2. **诊断格式**：以 compiled `[Kind] describe` 为准；interp 当前 `Kind: describe` 为待改项（E3），不作为 OBS-01 失败。
3. **mapErr 顶层转换函数**：`ERR-207` 是 sema 缺口，E2 修；本项只验 report 观测合同，不将其计入 OBS-01 失败。

---

## 三、逐项实测

### 3.1 report 语句（compiled）

```text
$ xnull run report_void.x
stdout: true
stderr: [Io] disk      # 单行；Ok 分支零输出
```

### 3.2 report 签名（void）

```text
$ xnull check report_chain_obsolete.x
error[TY-101]: 变量 again 的初始化式类型 void 不能赋给 Result<Int,E>
```

### 3.3 无堆分配

`impl/internal/codegen/codegen.go:148-177`：`xn_report_write` 使用 `write(STDERR_FILENO,...)`；`xn_report_line` 使用栈缓冲，控制字符折叠；无 `malloc`。

### 3.4 敏感信息/单行折叠

`describe() { return "user=alice\npassword=secret" }` → compiled stderr：

```text
[Io] user=alice password=secret
```

单行，且不附带栈/argv/env；凭据是否进入 `describe()` 由错误类型设计者负责（§4.3）。

---

## 四、残余项（不改变本项 PASS）

| 项 | 状态 | 归属 |
|---|---|---|
| interp 诊断格式 `Kind: describe` → `[Kind] describe` | 待改 | E3 |
| `mapErr` 顶层转换函数 ERR-207 | 待修 | E2 |
| E4 `TestS4_02WrapMapErrReport` / `ReportContract` 旧期望 | 已按裁定视为过期；以本文件用例为准 | E4/QA |

---

## 五、证据

- `evidence/S4-QA/OBS-01b/matrix.tsv`
- `report_void.x` / `report_void.compiled.{out,err}` / `report_void.interp.err`
- `report_sensitive.x` / `report_sensitive.compiled.err`
- `report_chain_obsolete.x` / `.err`（void 签名负例）
- `mapErr_topconv.x` / `.err`（E2 缺口）
- `struct-error-test.out`（结构体错误 + ErrorKind）
