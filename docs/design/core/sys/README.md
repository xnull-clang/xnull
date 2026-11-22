# `xdk.sys` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sys` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.runtime`、`xdk.bytes`、`xdk.io` |
| 被依赖 | `cli`、`config`、`fs`、`log` |
| 稳定性 | 基础 `stable`；信号/资源/系统信息 `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.sys` 提供进程、环境、平台、信号、内嵌资源、系统信息：

- `ProcessBuilder`/`Process`/`ProcessResult`；
- `Env` 环境快照；
- `Platform` 平台标识；
- `Signal` 信号枚举；
- `Resource` 内嵌资源；
- `SystemInfo` CPU/内存/磁盘/主机快照。

不做：PTY、cgroup、容器信息、信号完整语义、网络；进程组/stdio 管道作为 1.x 兼容面保留。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 资源 close | Process 必须 close；幂等 |
| Context | spawn/wait 可阻塞；取消返回 Cancelled |
| Long 句柄/大小 | process id/size 用 Long；不截断 |
| 无全局 env 修改 | Env 是快照；不提供进程级 set |
| 平台差异 | 不支持 → `Unsupported`，不静默 |
| 信号 |  只基本 kill；完整 handler 为 X |
| 最小权限 | 不暴露裸句柄 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Signal` | enum | 信号 | [`Signal.md`](Signal.md) |
| `ProcessBuilder` | class | 进程构造/启动 | [`ProcessBuilder.md`](ProcessBuilder.md) |
| `Process` | class | 子进程句柄 | [`Process.md`](Process.md) |
| `ProcessResult` | class | 退出码/输出/耗时 | [`ProcessResult.md`](ProcessResult.md) |
| `Env` | class | 环境快照 | [`Env.md`](Env.md) |
| `Platform` | class | 平台标识 | [`Platform.md`](Platform.md) |
| `Resource` | class | 内嵌资源 | [`Resource.md`](Resource.md) |
| `SystemInfo` | class | CPU/内存/磁盘/主机 | [`SystemInfo.md`](SystemInfo.md) |

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `spawnProcess` | 启动 | `Context, String command` | `Result<Process, Error>` | `Unavailable`/`Io` |
| `spawnProcessPiped` | 启动管道进程 | `Context, String command` | `Result<Process, Error>` | 同上；无管道 → `Unsupported` |
| `runProcess` | 运行并等 | `Context, String command` | `Result<ProcessResult, Error>` | 同上 |
| `runProcessResult` | 运行并捕获 | `Context, String command` | `Result<ProcessResult, Error>` | 同上 |
| `envOrNull` | 环境变量 | `String name` | `String?` | 无 |
| `envOr` | 环境变量/兜底 | `String name, String fallback` | `String` | 无 |
| `envHas` | 是否存在 | `String name` | `Bool` | 无 |
| `envNames` | 升序变量名 | 无 | `List<String>` | 无 |
| `envAll` | 全量快照 | 无 | `Map<String,String>` | 无 |
| `platform` | 运行平台 | 无 | `String` | 无 |
| `arch` | 架构 | 无 | `String` | 无 |
| `hostname` | 主机名 | 无 | `String` | 无 |
| `pid` | 当前 pid | 无 | `Long` | 无 |
| `cwd` | 工作目录 | 无 | `String` | 无 |
| `chdir` | 切换目录 | `String path` | `Bool` | 无 |
| `homeDir` | home | 无 | `String` | 无 |
| `tempDir` | 临时目录 | 无 | `String` | 无 |
| `which` | 查找命令 | `String command` | `String?` | 无 |
| `commandExists` | 命令存在 | `String command` | `Bool` | 无 |
| `signalNumber` | 信号号 | `Signal signal` | `Int` | 无 |
| `signalNumberFromName` | 名称→信号号 | `String name` | `Int` | 未知 → -1 |
| `signal` | 发信号 | `Context, Process, Signal` | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `sendSignal` | 按 pid 发信号 | `Int targetPid, Signal signal` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Io` |
| `sendGroupSignal` | 按进程组发信号 | `Int processGroup, Signal signal` | `Result<Unit, Error>` | 同上 |
| `kill` | 终止 | `Context, Process` | `Result<Unit, Error>` | 同上 |
| `stdinReadLine` | 读 stdin 一行 | 无 | `String` | EOF → 空串 |
| `fileMtime` | 修改时间（兼容） | `String path` | `Long` | 失败 → -1 |
| `fileMtimeResult` | 修改时间 | `String path` | `Result<Long, Error>` | `NotFound`/`Io` |
| `resourceExists` | 资源存在 | `String path` | `Bool` | 无 |
| `resourceSize` | 资源大小 | `String path` | `Long?` | 无 |
| `resourceCount` | 资源总数 | 无 | `Int` | 无 |
| `readResource` | 读资源 | `Context, String path` | `Result<Bytes, Error>` | `NotFound`/`Cancelled` |
| `readResourceText` | 读资源文本 | `Context, String path` | `Result<String, Error>` | 同上 |
| `listResources` | 列资源 | `Context, String prefix` | `Result<List<String>, Error>` | `Cancelled` |

### 4.1 技术/支撑/依赖

- 技术：fork/exec、wait/kill、env 快照、statfs/sysinfo、内嵌资源表。
- 支撑：OS 进程/信号/环境/资源、`Context`、`Bytes`、`io`。
- 依赖：`errors`、`runtime`、`bytes`、`io`、`Process`、`ProcessResult`、`Env`、`Signal`、`Resource`、`SystemInfo`。

### 4.2 关键伪代码

```xnull
Result<ProcessResult, Error> runProcessResult(Context context, String command) {
    ProcessBuilder builder = ProcessBuilder.of(command)
    return builder.runResult(context)
}

String? envOrNull(String name) {
    Map<String, String> values = Env.snapshot().all()
    if values.has(name) { return values.getOr(name, null) }
    return null
}

Result<Bytes, Error> readResource(Context context, String path) {
    if context.isCancelled() {
        return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
    }
    if !resourceExists(path) {
        return Err(new BasicError(ErrorKind.NotFound, "resource missing"))
    }
    return readResourceRaw(context, path)
}
```

---

## 5. 场景

### S1：CLI 调外部命令

`runProcessResult`；状态/输出/错误；超时取消。

### S2：服务管理子进程

`ProcessBuilder` + `Process`；spawn/wait/kill/close；僵尸进程回收。

### S3：环境/平台诊断

`Env.snapshot`、`Platform`、`SystemInfo`；启动横幅。

### S4：内嵌资源

`Resource`/`readResourceText`；缺失 `NotFound`；不读 FS 回退。

### S5：监控采集

`SystemInfo` CPU/内存/磁盘；`Process` 采集。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| PTY/cgroup | X |
| 进程组 | 已纳入：`Process.groupId/sendGroupSignal`、顶层 `sendGroupSignal` |
| 信号 handler | X |
| 环境变量修改 | 不支持；只快照/传给子进程 |
| Windows 信号语义 | 受限；`Unsupported` |
| 资源写入 | 只读 |
| 进程 stdio 管道 | 已纳入：`spawnProcessPiped` 与 `Process` stdin/stdout/stderr；平台无管道 → `Unsupported` |
| 系统信息精度 | 快照；不承诺强一致 |
| 权限/用户 |  只读 |

## 9. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `Process.groupId` / `sendGroupSignal` | [`Process.md`](Process.md) 同名 | 子进程自成组；未知信号 `Unsupported` |
| `spawnProcessPiped` | 顶层同名 + [`ProcessBuilder.md`](ProcessBuilder.md) `spawnPiped` | 平台无管道 → `Unsupported` |
| `Process` stdio 方法 | `isPiped/writeStdin*/closeStdin/readStdout*/readStderr*` | 非管道 → `Unsupported`；返回副本；NUL 安全 |
| `Process.terminate` | `terminate()`；SIGTERM | 关闭后 `Unavailable` |
| `envNames` | 顶层 `envNames` + [`Env.md`](Env.md) `names()` | 升序名称，不含值 |
| `stdinReadLine` | 顶层同名 | EOF → 空串 |
| `fileMtime` / `fileMtimeResult` | 顶层同名；`fs.metadata.modifiedMillis` 是规范面 | `-1` 兼容/`Result` 分类 |
| `resourceCount` | 顶层同名 | 内嵌资源总数 |
| `readResource` / `readResourceText` / `listResources` | 见 §4；[`Resource.md`](Resource.md) | `NotFound`/`Cancelled`/`DataCorrupted` |
| `pid(): Int` | `pid(): Long` | 类型迁移 |
| `runProcessResult(String)` | `ProcessBuilder` argv-only | 不接受 shell 字符串 |

示例：

```xnull
Result<Process, Error> spawned = spawnProcessPiped(context, "cat")
Process process = spawned.value()
process.writeStdinText("hello\n")
process.closeStdin()
String output = process.readStdoutText().value()
Result<Unit, Error> term = process.terminate()
List<String> names = envNames()
Int count = resourceCount()
```

测试义务：进程组 SIGTERM → wait 143；stdio 往返/EOF/非管道 Unsupported；envNames 排序；stdinReadLine EOF；fileMtime -1/Result；resourceCount；pid/id 迁移；runProcessResult shell 字符串迁移。
