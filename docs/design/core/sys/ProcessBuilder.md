# `ProcessBuilder`

| 项 | 值 |
| --- | --- |
| 类型 | `class ProcessBuilder` |
| 包 | `xdk.sys` |
| 稳定性 | `stable` |
| 依赖 | `Process`、`ProcessResult` |

---

## 1. 定位

子进程构造器：命令/参数/cwd/env/错误合并；spawn/run/runResult。

不做：PTY、stdio 管道（X）、进程组、shell 解释。

---

## 2. 设计逻辑

- 可变 builder；spawn 后不再修改。
- `command` 是程序；`args` 不含 argv[0]。
- `inheritEnv` 默认 true；`env` 覆盖/追加。
- `redirectErrorStream` 把 stderr 合并到 stdout。
- `spawn` 返回句柄；`run` 等完返回 status；`runResult` 捕获输出。
- Context 取消 → kill + Cancelled。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_command` | `String` | 程序 |
| `_args` | `List<String>` | 参数 |
| `_cwd` | `String?` | 工作目录 |
| `_env` | `Map<String,String>` | 覆盖 |
| `_inheritEnv` | `Bool` | 继承 |
| `_redirectErrorStream` | `Bool` | 合并 stderr |

不变量：command 非空；args 无 null。

---

## 4. 生命周期

可变构建期；spawn 后不修改；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ProcessBuilder(String command)` | command | 非空 | 空 → panic |
| `ProcessBuilder.of(String command)` | command | 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `arg` | 追加参数 | `String value` | `ProcessBuilder` | null → panic |
| `args` | 替换参数 | `List<String> values` | `ProcessBuilder` | 非法 → panic |
| `cwd` | 工作目录 | `String path` | `ProcessBuilder` | 无 |
| `env` | 设置变量 | `String name, String value` | `ProcessBuilder` | null → panic |
| `envAll` | 批量设置 | `Map<String,String> values` | `ProcessBuilder` | null → panic |
| `inheritEnv` | 继承环境 | `Bool value` | `ProcessBuilder` | 无 |
| `redirectErrorStream` | 合并 stderr | `Bool value` | `ProcessBuilder` | 无 |
| `spawn` | 启动 | `Context` | `Result<Process, Error>` | `Unavailable`/`Io`/`Cancelled` |
| `run` | 运行等待 | `Context` | `Result<Int, Error>` | 同上 |
| `runResult` | 捕获结果 | `Context` | `Result<ProcessResult, Error>` | 同上 |

---

## 8. 使用的技术

- fork/exec；
- 参数数组；
- 环境合并；
- 输出捕获；
- 取消。

---

## 9. 需要的支撑

- 语言：class、String、List、Map、Bool、Result、Context；
- 运行时/OS：spawn/wait/pipe；
- 接口：`Process`、`ProcessResult`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Process`、`ProcessResult`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

可变 builder；spawn 后不修改；非线程安全。

---

## 12. 示例与反例

正确：`ProcessBuilder.of("ls").arg("-l").runResult(ctx)`。  
反例：command 含空格期望 shell；args 含 null；spawn 后修改 builder。

---

## 13. 测试/场景义务

参数/cwd/env；继承/覆盖；stderr 合并；取消；spawn/run/runResult；失败。

---

## 14. XNull 伪代码

```xnull
class ProcessBuilder {
    String _command
    List<String> _args = []
    String? _cwd = null
    Map<String, String> _env = [:]
    Bool _inheritEnv = true
    Bool _redirectErrorStream = false

    ProcessBuilder(String command) {
        if command == "" { throw "ProcessBuilder: empty command" }
        _command = command
    }

    static ProcessBuilder of(String command) {
        return new ProcessBuilder(command)
    }

    ProcessBuilder arg(String value) {
        if value == null { throw "ProcessBuilder.arg: null" }
        _args.push(value)
        return self
    }

    ProcessBuilder args(List<String> values) {
        _args = []
        Int index = 0
        while index < values.length() {
            self.arg(values.get(index))
            index = index + 1
        }
        return self
    }

    ProcessBuilder cwd(String path) { _cwd = path; return self }

    ProcessBuilder env(String name, String value) {
        if name == null || value == null { throw "ProcessBuilder.env: null" }
        _env.put(name, value)
        return self
    }

    ProcessBuilder envAll(Map<String, String> values) {
        List<String> keys = values.keys()
        Int index = 0
        while index < keys.length() {
            self.env(keys.get(index), values.getOr(keys.get(index), ""))
            index = index + 1
        }
        return self
    }

    ProcessBuilder inheritEnv(Bool value) { _inheritEnv = value; return self }
    ProcessBuilder redirectErrorStream(Bool value) { _redirectErrorStream = value; return self }

    Result<Process, Error> spawn(Context context) {
        if context == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null context"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
        }
        Result<ProcessHandle, Error> handle = spawnRaw(
            _command, _args, _cwd, _env, _inheritEnv, _redirectErrorStream)
        if handle.isErr() { return Err(handle.error()) }
        return Ok(new Process(handle.value()))
    }

    Result<Int, Error> run(Context context) {
        Result<Process, Error> spawned = self.spawn(context)
        if spawned.isErr() { return Err(spawned.error()) }
        Process process = spawned.value()
        Result<Int, Error> status = process.wait(context)
        Result<Unit, Error> closed = process.close()
        if status.isErr() { return Err(status.error()) }
        if closed.isErr() { return Err(closed.error()) }
        return status
    }

    Result<ProcessResult, Error> runResult(Context context) {
        Long started = nowMono()
        Result<Int, Error> status = self.run(context)
        if status.isErr() { return Err(status.error()) }
        return Ok(new ProcessResult(status.value(), "", "", nowMono() - started, null))
    }
}
```

> `ProcessHandle`、`spawnRaw` 是 OS/运行时进程原语；`runResult` 的真实实现还需捕获 stdout/stderr。
