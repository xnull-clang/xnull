# 验收：S4-BOUND-01（进程退出码）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `9161cd1`（含 S4-05 用例；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/BOUND-01/`

---

## 一、结论

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `Int main` 返回 7 | 7 | 7 | 7 | **PASS** |
| `Int main` 返回 0 | 0 | 0 | 0 | **PASS** |
| `void main` | 0 | 0，stdout `ok` | 0，stdout `ok` | **PASS** |
| `throw "boom"` | fatal 非零 | 134，stderr `xnull: fatal: boom` | 134 | **PASS** |
| 除零 fatal | 134 | 134，stderr `xnull: fatal: 除零` | 134 | **PASS** |

**判定：PASS。** 进程级退出码映射在解释/编译两路径均符合 S4 §10 BOUND-01：`Int main` 原样映射、`void main` 为 0、fatal 为 134（非零）。

---

## 二、实测

命令（每个用例独立进程）：

```bash
xnull run --interp <case>.x; echo $?
xnull run          <case>.x; echo $?
```

| 用例 | interp rc | compiled rc |
|---|---:|---:|
| `b01_7.x` | 7 | 7 |
| `b01_0.x` | 0 | 0 |
| `b01_void.x` | 0 | 0 |
| `b01_throw.x` | 134 | 134 |
| `b01_fatal.x` | 134 | 134 |

编译路径 `throw` 有一条 C 编译 warning（非 void 函数无返回），但进程退出码仍为 134，不影响 BOUND-01 判定。

---

## 三、官方用例

| 用例 | 结果 |
|---|---|
| `internal/interp/interp_test.go:TestExitCodeMapping` | **PASS**（7/0/134/134） |
| `internal/cli/cli_test.go:TestRunMainNoArgsExitCodeInterp` | **PASS**（7） |
| `internal/cli/cli_test.go:TestRunMainNoArgsExitCodeCompiled` | **PASS**（7） |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/BOUND-01/b01_7/`、`b01_0/`、`b01_void/`、`b01_throw/`、`b01_fatal/`（每条含 `source.x`、`interp.*`、`compiled.*`）
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/interp-s4.log`
- 断言依据：S4 §10 BOUND-01
