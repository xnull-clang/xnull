# `Stdio`

| 项 | 值 |
| --- | --- |
| 类型 | `class Stdio` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`Writer` |

---

## 1. 定位

标准输入/输出/错误的访问入口；返回 Reader/Writer 协议。

不做：终端 UI、ANSI（`terminal`）、文件重定向。

---

## 2. 设计逻辑

- 静态类；无实例状态。
- `stdin/stdout/stderr` 返回内部标准流对象。
- 标准流不 close；`isOpen` 恒 true；`close` no-op。
- `isTerminal` 判断 TTY；不保证所有平台。

---

## 3. 表示与不变量

无实例字段；内部标准流对象由实现持有。

---

## 4. 生命周期

标准流进程级；不 close。

---

## 5. 构造契约

静态类，不公开构造。

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `stdin` | 标准输入 | 无 | `Reader` | 无 |
| `stdout` | 标准输出 | 无 | `Writer` | 无 |
| `stderr` | 标准错误 | 无 | `Writer` | 无 |
| `isTerminalIn` | 输入是否 TTY | 无 | `Bool` | 无 |
| `isTerminalOut` | 输出是否 TTY | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 进程标准流；
- TTY 判断；
- 协议返回。

---

## 9. 需要的支撑

- 语言：class、Bool、Reader、Writer；
- 运行时：stdin/stdout/stderr、isatty；
- 接口：`Reader`、`Writer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Writer`。

---

## 11. 所有权与并发

标准流进程级；不 close；写入需外部同步。

---

## 12. 示例与反例

正确：`Stdio.stdout().writeAll(ctx, data)`。  
反例：close 标准输出；多任务并发写期望顺序；把 stderr 当业务输出。

---

## 13. 测试/场景义务

stdin/stdout/stderr 非 null；isTerminal；write/read；不 close。

---

## 14. XNull 伪代码

```xnull
class Stdio {
    static Reader stdin() {
        return StdinReader.instance()
    }

    static Writer stdout() {
        return StdoutWriter.instance()
    }

    static Writer stderr() {
        return StderrWriter.instance()
    }

    static Bool isTerminalIn() {
        return stdinIsTerminalRaw() != 0
    }

    static Bool isTerminalOut() {
        return stdoutIsTerminalRaw() != 0
    }
}
```

> `StdinReader/StdoutWriter/StderrWriter` 是 io 包内部标准流实现；不 close 标准流。
