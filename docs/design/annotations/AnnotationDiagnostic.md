# `AnnotationDiagnostic`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationDiagnostic` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationDiagnosticSeverity`、`String` |

---

## 1. 定位

注解处理器的单条不可变诊断：严重级别、稳定诊断码、消息、元素名。

不做：不做日志记录、不做异常、不做退出码、不做诊断抑制、不做多语言本地化。

---

## 2. 设计逻辑

- 诊断由处理器或编译器产生；构建调度器收集后决定构建结果。
- `severity` 决定是否阻止构建；`code` 是机器可读稳定标识；`message` 是面向人的说明。
- `code` 与 `message` 分离：调用方/测试可以按码断言，不依赖消息文本。
- `elementName` 是可选的元素定位名；空串表示“无具体元素”（例如构建选项错误）。
- `elementName` 使用 `AnnotationElement.describe()` 或 `AnnotationInfo.targetName()` 的字符串形态；本类不解析。
- 诊断不可变；处理器不得在产生后修改级别或消息。
- `describe()` 是稳定诊断文本，但消息内容可随版本改进；测试应优先断言 `code`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_severity` | `AnnotationDiagnosticSeverity` | 级别，final，非 null |
| `_code` | `String` | 稳定码，final，去空白后非空 |
| `_message` | `String` | 消息，final，去空白后非空 |
| `_elementName` | `String` | 元素名，final，非 null；可为空 |

不变量：

- 级别固定为 `Error`/`Warning`/`Note`。
- `code` 是稳定 token，例如 `ANN001`；同一规则跨版本保持同码。
- `message` 非空；允许包含元素名，但不要依赖它做机器解析。
- `elementName` 为空表示无具体元素，不是 `null`。
- 构造后不可变；可跨任务共享。

---

## 4. 生命周期

由处理器/编译器在构建期创建；无 close；无资源；构建结束后随结果回收；不进入运行时注册表。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationDiagnostic(AnnotationDiagnosticSeverity severity, String code, String message, String elementName)` | 全部 | severity 是枚举成员（枚举不可为 null）；code/message 去空白后非空；elementName 非 null | null/空 code/空 message → panic |

说明：

- `code` 与 `message` 在构造时去除首尾空白；内部保存规范化值。
- `elementName` 也去除首尾空白；空串合法。
- 不校验 `code` 的字符集；编译器/工具链 lint 负责稳定性约定。
- 不把 `elementName` 拼进 `message`；二者保持独立字段。

---

## 6. 字段表

见 §3；字段私有、`final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `severity` | 诊断级别 | 无 | `AnnotationDiagnosticSeverity` | 无 |
| `code` | 稳定诊断码 | 无 | `String` | 无 |
| `message` | 诊断消息 | 无 | `String` | 无 |
| `elementName` | 元素定位名 | 无 | `String` | 无 |
| `describe` | 稳定诊断文本 | 无 | `String` | 无 |

说明：

- `describe()` 输出 `error ANN001: message [element]`；`elementName` 为空时省略方括号部分。
- 严重级别文本固定为小写 `error`/`warning`/`note`。
- 不提供 `withSeverity`/`withMessage` 等修改方法；需要新诊断时重新构造。
- 不提供 `equals`；测试按字段断言。

---

## 8. 使用的技术

- 不可变对象；
- 稳定诊断码；
- 级别枚举；
- 输入规范化；
- 稳定文本格式。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool（间接）、String.trim；
- 运行时：无；
- 接口：`AnnotationDiagnosticSeverity`。

---

## 10. 依赖的特性/接口/类

`AnnotationDiagnosticSeverity`、`String`、`String.trim`。

被 `AnnotationProcessingResult` 收集。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- 不持有元素/编译器句柄，只保存字符串。
- 相等：没有值相等实现；`==` 是引用身份。

---

## 12. 示例与反例

正确：

```xnull
AnnotationDiagnostic missing = new AnnotationDiagnostic(
    AnnotationDiagnosticSeverity.Error,
    "ANN001",
    "unknown annotation",
    "app.Device"
)
String text = missing.describe()
```

反例：用空 `code`；把完整消息塞进 `code`；用 `null` 表示无元素；用诊断级别替代日志级别；依赖 `message` 文本做机器判断；构造后修改级别；在运行时注册表里保存诊断。

---

## 13. 测试/场景义务

- 三种级别的 `describe()` 文本；
- `code`/`message` 去空白与空值拒绝；
- `elementName` 为空/非空；
- 诊断码跨版本稳定；
- 多条诊断合并后的顺序与级别；
- 不可变/并发只读；
- 与 `AnnotationProcessingResult.success()` 的联动。

---

## 14. XNull 伪代码

```xnull
class AnnotationDiagnostic {
    final AnnotationDiagnosticSeverity _severity
    final String _code
    final String _message
    final String _elementName

    AnnotationDiagnostic(AnnotationDiagnosticSeverity severity, String code,
                         String message, String elementName) {
        // severity 是枚举成员；枚举是值类型，不存在 null。
        if code == null || trim(code) == "" {
            throw "AnnotationDiagnostic: empty code"
        }
        if message == null || trim(message) == "" {
            throw "AnnotationDiagnostic: empty message"
        }
        if elementName == null {
            throw "AnnotationDiagnostic: null element name"
        }
        _severity = severity
        _code = trim(code)
        _message = trim(message)
        _elementName = trim(elementName)
    }

    AnnotationDiagnosticSeverity severity() {
        return _severity
    }

    String code() {
        return _code
    }

    String message() {
        return _message
    }

    String elementName() {
        return _elementName
    }

    String describe() {
        String result = severityName(_severity) + " " + _code + ": " + _message
        if _elementName != "" {
            result = result + " [" + _elementName + "]"
        }
        return result
    }

    private static String severityName(AnnotationDiagnosticSeverity severity) {
        if severity == AnnotationDiagnosticSeverity.Error {
            return "error"
        }
        if severity == AnnotationDiagnosticSeverity.Warning {
            return "warning"
        }
        return "note"
    }
}
```
