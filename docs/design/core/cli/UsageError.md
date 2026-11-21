# `UsageError`

| 项 | 值 |
| --- | --- |
| 类型 | `class UsageError implements Error` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`ErrorKind`、`ExitCode` |

---

## 1. 定位

命令行用户输入错误：消息、出错选项 token、命令路径、是否建议显示 usage、退出码。

不做：打印、进程退出、帮助渲染、IO 错误、业务错误。

---

## 2. 设计逻辑

- 不可变；`with*` 返回新实例。
- `kind()` 固定 `InvalidArgument`；`describe()` 单行。
- `_optionToken` 保存带前导 `-`/`--` 的 token，例如 `"--output"`、`"-X"`，不保存裸名字。
- `_commandPath` 例如 `"app build"`；只用于描述。
- `showUsage` 是给应用的提示，不由 `UsageError` 自己打印。
- `exitCode()` 固定 `ExitCode.Usage`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_message` | `String` | 非空、单行 |
| `_optionToken` | `String?` | 合法选项 token 或 null |
| `_commandPath` | `String?` | 单行路径或 null |
| `_showUsage` | `Bool` | 是否建议显示 usage |

不变量：message 非空无换行；optionToken 若存在则 `isOptionToken`；commandPath 无换行；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `UsageError(String message)` | message | 非空、单行 | 非法 → panic |

派生方法对非法 optionToken/commandPath panic。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 错误分类 | 无 | `ErrorKind` | 无 |
| `describe` | 单行诊断 | 无 | `String` | 无 |
| `message` | 用户消息 | 无 | `String` | 无 |
| `optionToken` | 出错选项 | 无 | `String?` | 无 |
| `commandPath` | 命令路径 | 无 | `String?` | 无 |
| `showUsage` | 是否建议 usage | 无 | `Bool` | 无 |
| `exitCode` | 退出码 | 无 | `ExitCode` | 无 |
| `withOption` | 派生选项 | `String optionToken` | `UsageError` | 非法 → panic |
| `withCommandPath` | 派生路径 | `String commandPath` | `UsageError` | null/换行 → panic |
| `withShowUsage` | 派生提示 | `Bool value` | `UsageError` | 无 |

说明：

- `describe` 形如 `"app build: missing value for --output"`；消息未包含选项 token 时才追加 `" (option --output)"`。
- `showUsage` 不改变 `describe`；它只供应用决定是否追加帮助文本。

---

## 8. 使用的技术

- 不可变错误；
- Error 协议实现；
- 单行校验；
- 退出码枚举。

---

## 9. 需要的支撑

- 语言：class、protocol、String、Bool；
- 运行时：无；
- 接口：`Error`、`ErrorKind`、`ExitCode`、`isOptionToken`。

---

## 10. 依赖的特性/接口/类

`Error`、`ErrorKind`、`ExitCode`、`isOptionToken`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new UsageError("unknown option").withOption("--bad").withCommandPath("app")`。  
反例：在 `describe` 里写多行；直接打印 stderr；用 `UsageError` 表示 IO 失败。

---

## 13. 测试/场景义务

message 空/多行；optionToken 合法/非法；commandPath；showUsage；describe 顺序；exitCode；Error 协议。

---

## 14. XNull 伪代码

```xnull
class UsageError implements Error {
    final String _message
    final String? _optionToken
    final String? _commandPath
    final Bool _showUsage

    UsageError(String message) {
        if message == null || message == "" {
            throw "UsageError: empty message"
        }
        if message.indexOf("\n") >= 0 {
            throw "UsageError: multiline message"
        }
        _message = message
        _optionToken = null
        _commandPath = null
        _showUsage = true
    }

    private UsageError(String message, String? optionToken, String? commandPath, Bool showUsage) {
        if message == null || message == "" {
            throw "UsageError: empty message"
        }
        if message.indexOf("\n") >= 0 {
            throw "UsageError: multiline message"
        }
        if optionToken != null && !isOptionToken(optionToken) {
            throw "UsageError: invalid option token"
        }
        if commandPath != null && commandPath.indexOf("\n") >= 0 {
            throw "UsageError: multiline command path"
        }
        _message = message
        _optionToken = optionToken
        _commandPath = commandPath
        _showUsage = showUsage
    }

    ErrorKind kind() { return ErrorKind.InvalidArgument }

    String describe() {
        String result = _message
        if _optionToken != null {
            String optionToken = _optionToken as String
            if result.indexOf(optionToken) < 0 {
                result = result + " (option " + optionToken + ")"
            }
        }
        if _commandPath != null && _commandPath != "" {
            result = _commandPath + ": " + result
        }
        return result
    }

    String message() { return _message }
    String? optionToken() { return _optionToken }
    String? commandPath() { return _commandPath }
    Bool showUsage() { return _showUsage }
    ExitCode exitCode() { return ExitCode.Usage }

    UsageError withOption(String optionToken) {
        return new UsageError(_message, optionToken, _commandPath, _showUsage)
    }

    UsageError withCommandPath(String commandPath) {
        if commandPath == null { throw "UsageError.withCommandPath: null" }
        return new UsageError(_message, _optionToken, commandPath, _showUsage)
    }

    UsageError withShowUsage(Bool value) {
        return new UsageError(_message, _optionToken, _commandPath, value)
    }
}
```
