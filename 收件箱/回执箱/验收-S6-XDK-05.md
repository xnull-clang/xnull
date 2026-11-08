# 验收：S6-XDK-05（sync）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 E3 解释器同步原语 `f22f4a0` 与 E4 codegen 同步原语 `189b532`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK05/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `Mutex<struct>` / `AtomicRef<Int>` → `TY-228` | **PASS**：`TestS5SyncTypeRules` |
| `withLock` 作用域化 | **PASS**：sema + 双路径 E2E |
| `Channel.send/receive` 返回 `Result` | **PASS**：双路径 E2E |
| `AtomicInt/AtomicBool` load/store/compareExchange | **PASS**：双路径 E2E |
| 解释路径 | **PASS**：`0/7/6/true` |
| 编译路径 | **PASS**：`0/7/6/true` |
| 运行时 C 原语 | **PASS**：`sync tests passed (channel/mutex/atomic/cancel)` |
| `Channel` 关闭终态 | **PASS**：`ch.close()` 后流程正常 |

**判定：PASS。** E3/E4 同步原语落地后，`Mutex/Channel/Atomic` 的 sema、解释与编译路径全部通过；D01 双路径输出逐字节一致。

---

## 二、双路径 E2E

夹具：`tests/s6/xdk05/sync_basic.x`

```x
Mutex<Int> m = Mutex<Int>(0)
m.withLock((Int x) -> { print(x); return Ok() })
Channel<Int> ch = Channel<Int>(1)
ch.send(7); ch.receive(); ch.close()
AtomicInt a = AtomicInt(0)
a.store(5); a.compareExchange(5, 6); print(a.load())
AtomicBool b = AtomicBool(false); b.store(true); print(b.load())
```

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `0\n7\n6\ntrue\n`，rc=0 | **PASS** |
| `run`（编译） | `0\n7\n6\ntrue\n`，rc=0 | **PASS** |

`cli-xdk05.log`：

```text
--- PASS: TestXDK05SemaSurface
--- PASS: TestXDK05InterpE2E
--- PASS: TestXDK05CompiledE2E
```

上一轮的两个 `SKIP`（`未定义的函数：Mutex` / `类型 Mutex 未支持`）已消失。

---

## 三、sema 与运行时

- `sema-xdk05.log`：`TestXDK05SyncConstructors`、`TestS5SyncTypeRules`、`TestS5ChannelAndMutexFlow` 全 PASS。
- `runtime-xdk05.log`：`sync tests passed (channel/mutex/atomic/cancel)`；`task tests`、`sysasync`、资源 API 同步回归均 PASS。

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK05/interp.out`、`compiled.out`、`interp.exit`、`compiled.exit`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK05/cli-xdk05.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK05/sema-xdk05.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK05/runtime-xdk05.log`
- 断言依据：S6 §7/§10 XDK-05；`tests/s6/xdk05/sync_basic.expect`
