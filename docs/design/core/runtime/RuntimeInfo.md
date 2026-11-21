# `RuntimeInfo`

### 1. 定位

当前运行时/进程/构建环境的只读快照。用于启动横幅、诊断、CLI `--version`、健康信息。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_languageVersion` | `String` | final | `major.minor.patch` |
| `_xdkVersion` | `String` | final | `major.minor.patch` |
| `_targetPlatform` | `String` | final | 构建目标平台 |
| `_architecture` | `String` | final | `arm64`/`x86_64` 等 |
| `_buildMode` | `String` | final | `debug`/`release` |
| `_pid` | `Int` | final | 进程 ID |
| `_hostname` | `String` | final | 主机名；不可用时空串 |
| `_cwd` | `String` | final | 启动时工作目录 |
| `_startTimeMono` | `Long` | final | 启动单调毫秒 |

不变量：版本非空三段式；pid > 0；startTimeMono ≥0；hostname/cwd 可为空串；不可变；可共享。

### 3. 使用的技术

- 不可变快照；
- 字符串拼接；
- 单调时钟差值；
- 运行时进程信息读取。

### 4. 需要的支撑

- 语言：class、final 字段、String、Int、Long；
- 运行时：`nowMono`、进程 ID、主机名、工作目录、启动时间；
- 接口：无。

### 5. 依赖的特性/接口/类

无其他 XDK 类；只依赖语言原语和运行时服务。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `languageVersion` | 语言版本 | 无 | `String` | 无 |
| `xdkVersion` | XDK 版本 | 无 | `String` | 无 |
| `targetPlatform` | 构建目标 | 无 | `String` | 无 |
| `architecture` | 架构 | 无 | `String` | 无 |
| `buildMode` | 构建模式 | 无 | `String` | 无 |
| `pid` | 进程 ID | 无 | `Int` | 无 |
| `hostname` | 主机名 | 无 | `String` | 无 |
| `cwd` | 启动目录 | 无 | `String` | 无 |
| `startTimeMono` | 启动时间 | 无 | `Long` | 无 |
| `uptimeMillis` | 已运行毫秒 | 无 | `Long` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制快照 | 无 | `RuntimeInfo` | 无 |

### 7. XNull 伪代码

```xnull
class RuntimeInfo {
    final String _languageVersion
    final String _xdkVersion
    final String _targetPlatform
    final String _architecture
    final String _buildMode
    final Int _pid
    final String _hostname
    final String _cwd
    final Long _startTimeMono

    RuntimeInfo(String languageVersion, String xdkVersion,
                String targetPlatform, String architecture,
                String buildMode, Int pid, String hostname,
                String cwd, Long startTimeMono) {
        _languageVersion = languageVersion
        _xdkVersion = xdkVersion
        _targetPlatform = targetPlatform
        _architecture = architecture
        _buildMode = buildMode
        _pid = pid
        _hostname = hostname
        _cwd = cwd
        _startTimeMono = startTimeMono
    }

    String languageVersion() { return _languageVersion }
    String xdkVersion() { return _xdkVersion }
    String targetPlatform() { return _targetPlatform }
    String architecture() { return _architecture }
    String buildMode() { return _buildMode }
    Int pid() { return _pid }
    String hostname() { return _hostname }
    String cwd() { return _cwd }
    Long startTimeMono() { return _startTimeMono }

    Long uptimeMillis() {
        Long current = nowMono()
        if current < _startTimeMono {
            return 0
        }
        return current - _startTimeMono
    }

    String describe() {
        return "xdk " + _xdkVersion
            + " lang " + _languageVersion
            + " " + _targetPlatform + "/" + _architecture
            + " pid=" + str(_pid)
            + " mode=" + _buildMode
    }

    RuntimeInfo copy() {
        return new RuntimeInfo(
            _languageVersion,
            _xdkVersion,
            _targetPlatform,
            _architecture,
            _buildMode,
            _pid,
            _hostname,
            _cwd,
            _startTimeMono
        )
    }
}
```

---
