# 验收：S6-XDK-06（runtime）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 E5 XDK-06 runtime `5c88e82`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK016/XDK-06/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `diagnose` 单行、无控制字符 | **PASS**：stderr `diag-line` |
| `dumpTasks` 单行 | **PASS**：interp `tasks: live=0`；compiled `tasks: live=0 spawned=0 settled=0 carrier=0` |
| `nowMono` 单调 | **PASS**：连续两次 `b >= a` 为 `true` |
| `env` 快照 / 缺失返回 null | **PASS**：`env("PATH") != null`；缺失变量 `== null` |
| `exit` 立即终止、跳过 `defer`、退出码原样 | **PASS**：双路径 rc=3，`defer-should-not-run` 未输出 |
| 解释器桥接 | **PASS**：`TestS6XDK06RuntimeBuiltins` |
| 编译路径资源符号 / 链接 | **PASS**：compiled 程序正常链接运行 |

**判定：PASS。** XDK-06 的六个 runtime API 在解释/编译双路径行为一致；`dumpTasks` 单行、`exit` 跳过 defer、env 快照与 nowMono 单调均成立。

---

## 二、双路径实测

夹具：`evidence/QA-XDK016/XDK-06/source.x`

```x
import xdk.runtime
static Int main() {
    diagnose("diag-line")
    dumpTasks()
    Int a = nowMono()
    Int b = nowMono()
    print(b >= a)
    String? e = env("PATH")
    print(e != null)
    String? missing = env("XNULL_NO_SUCH_ENV_QA")
    print(missing == null)
    defer { print("defer-should-not-run") }
    exit(3)
    return 0
}
```

| 路径 | stdout | stderr | rc |
|---|---|---|---|
| `run --interp` | `true\ntrue\ntrue\n` | `diag-line\ntasks: live=0\n` | 3 |
| `run`（编译） | `true\ntrue\ntrue\n` | `diag-line\ntasks: live=0 spawned=0 settled=0 carrier=0\n` | 3 |

`defer-should-not-run` 两路径均未出现；`exit` 退出码原样为 3。

---

## 三、官方用例

| 用例 | 结果 |
|---|---|
| `internal/codegen/s6_02_test.go:TestS6_02RuntimeSurface` | **PASS** |
| `TestS6_02ExitSkipsDefer` | **PASS** |
| `TestS6_02DumpTasksCounts` | **PASS** |
| `internal/interp/s6_xdk06_test.go:TestS6XDK06RuntimeBuiltins` | **PASS** |
| `TestS6XDK06ExitSkipsDefer` | **PASS** |
| `TestS6XDK06EnvSnapshot` | **PASS** |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK016/XDK-06/source.x`、`interp.*`、`compiled.*`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK016/XDK-06/codegen-xdk06.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK016/XDK-06/interp-xdk06.log`
- 断言依据：S6 §5/§10 XDK-06
