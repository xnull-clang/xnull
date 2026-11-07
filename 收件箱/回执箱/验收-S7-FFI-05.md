# 验收：S7-FFI-05（回调 trampoline）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `33a228a`（含 S7-03 `9b70a54` 回调声明 + typed trampoline）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-05/`
> **依据**：S7 §5.1–§5.3、FFI-05；S7-03 回执/验收计划
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 回调声明（`.xfb callback`） | **PASS**：登记 2 个回调；生成 `xn_tramp_<Cb>_args/closure` |
| typed trampoline 生成 | **PASS**：`new/destroy/invoke/adapt` 符号齐全 |
| env 根生命周期 | **PASS**：`alive=1`，invoke 输出 `log st=0 r=7 n=1`、`notify st=0 n=9` |
| destroy 注销根 | **PASS**：`destroyed alive=0` |
| 注销后调用 | **PASS**：进程终止（fatal），无 `destroyed-missed` |
| 回调 panic/非 0 状态 | **PASS**：进程终止，无 `panic-missed` |
| 回调参数校验 | **PASS**：`Bytes` 参数/`layout` 返回 → `FFI-112`；重名 → `FFI-111` |

**判定：PASS。** 回调声明、trampoline 发射、env 根登记/注销、注销后调用与 panic 端到端全部成立；`build_rt.sh` 的 `test_abi_link` callback env 同步绿。

---

## 二、实测

```text
$ go test ./internal/codegen/ffi -run 'TestS703|TestTrampoline' -count=1 -v
PASS TestTrampolineGenerated
PASS TestS703CallbackTrampolineEndToEnd
PASS TestS703CallbackValidation

$ sh impl/runtime/build_rt.sh
abi link tests passed (xrt.h only, init order, weak gate, handle/callback)
xnull runtime fatal: trampoline：已注销的 env 被调用（S7 §5.2 合同违规）
exit 0
```

E2E 输出：

```text
log st=0 r=7 n=1 alive=1
notify st=0 n=9
destroyed alive=0
```

`destroyed` / `panic` 子模式均进程终止，未出现 `*-missed`。

---

## 三、边界

| 项 | 说明 |
|---|---|
| 回调边界类型 | 仅标量/Void；`Bytes`/`layout` 显式 `FFI-112` |
| 回调 panic | 非 0 状态由 trampoline 转 fatal（无任务隔离） |
| 闭包 codegen | 捕获外部变量的闭包仍属后续语言面 |

---

## 四、证据

- `evidence/S7-QA/FFI-05/matrix.tsv`
- `ffi-s703.log`（TrampolineGenerated / CallbackTrampolineEndToEnd / CallbackValidation）
- `runtime-build.log`（callback env / 注销后调用 fatal）
- `source-contract.txt`（s703 E2E 合同）
- `收件箱/回执箱/回执-S7-03.md`
