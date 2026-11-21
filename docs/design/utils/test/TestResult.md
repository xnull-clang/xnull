# `TestResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class TestResult` |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | `TestStatus`、`Error`、`List`、`String`、`Long`、`trim`、`str` |

---

## 1. 定位

单个测试完成后的不可变结果快照：名称、状态、耗时、错误、日志。

不做：聚合、排序、终端渲染、i18n、重试决策、结果持久化、可变进度。

`TestRunner` 创建快照；调用方只读。

---

## 2. 设计逻辑

- 字段：名称、状态、耗时毫秒、错误（可空）、日志列表。
- 构造时校验：名称去空白非空；状态非 null；耗时 `>= 0`；日志非 null 且元素非 null。
- 状态与错误的一致性：`Passed` 必须无错误；`Failed`/`Skipped` 必须有错误。
- 日志在构造时复制；`logs()` 返回副本。
- `describe` 返回单行文本：`name: Status (Nms)`，有错误时追加 ` - <error.describe()>`。
- 不可变；无 close；无全局状态。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | final；去首尾空白后非空 |
| `_status` | `TestStatus` | final；非 null |
| `_durationMillis` | `Long` | final；`>= 0` |
| `_error` | `Error?` | final；Passed 为 null，Failed/Skipped 非 null |
| `_logs` | `List<String>` | 内部快照；元素非 null |

不变量：名称非空；耗时非负；状态/错误一致；日志只读快照；`describe` 单行。

---

## 4. 生命周期

由 `TestRunner` 在测试结束后创建；不可变；无 close；无资源；可长期持有、跨任务传递。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TestResult(String name, TestStatus status, Long durationMillis, Error? error, List<String> logs)` | 全部 | name 非空；status 非 null；duration ≥ 0；logs 非 null/元素非 null；Passed → error == null；Failed/Skipped → error != null | 违反任一 → panic |

说明：

- 不提供便捷构造；`TestRunner` 是主要创建者，测试代码也可手工构造快照。
- 名称规范化后存储。
- 日志内容按原样保存，不在构造时去空白；null 元素 panic。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 测试名 | 无 | `String` | 无 |
| `status` | 状态 | 无 | `TestStatus` | 无 |
| `durationMillis` | 耗时毫秒 | 无 | `Long` | 无 |
| `error` | 错误 | 无 | `Error?` | 无 |
| `logs` | 日志快照 | 无 | `List<String>` | 无 |
| `describe` | 单行描述 | 无 | `String` | 无 |

说明：

- `error()` 在 `Passed` 时为 null；在 `Failed`/`Skipped` 时非 null，调用方需判空后读取。
- `logs()` 每次返回新列表。
- `describe` 不包含日志正文，避免多行/超长输出；日志由调用方自行读取。
- `describe` 使用固定英文状态名，不依赖 i18n。
- 不提供 `isPassed` 等便捷方法；直接比较 `status()`。

---

## 8. 使用的技术

- 不可变快照；
- 构造期一致性校验；
- 防御性复制；
- 单行文本格式化。

---

## 9. 需要的支撑

- 语言：class、final 字段、可空引用、Long、String、List、Bool；
- 运行时：无；
- 接口：`TestStatus`、`Error`、`trim`、`str`。

---

## 10. 依赖的特性/接口/类

`TestStatus`、`Error`、`List`、`String`、`Long`、`trim`、`str`。

---

## 11. 所有权与并发

引用语义但不可变；日志返回副本；可跨任务共享；线程安全；无资源。

---

## 12. 示例与反例

正确：`result.status() == TestStatus.Passed && result.error() == null`。  
反例：构造 `Passed` 同时带 error；构造 `Skipped` 不带 error；修改 `logs()` 返回值并期望结果变化；在 `describe` 中输出多行日志；依赖状态序号。

---

## 13. 测试/场景义务

名称空白/非空；三种状态与 error 组合；耗时 0/正值/负值；日志副本独立性/null 元素；describe 各状态/带错误/单行；跨任务读取；不可变性。

---

## 14. XNull 伪代码

```xnull
class TestResult {
    final String _name
    final TestStatus _status
    final Long _durationMillis
    final Error? _error
    final List<String> _logs

    TestResult(String name, TestStatus status, Long durationMillis,
               Error? error, List<String> logs) {
        if name == null || status == null || logs == null {
            throw "TestResult: null argument"
        }
        if durationMillis < 0 {
            throw "TestResult: negative duration"
        }
        String normalized = trim(name)
        if normalized == "" {
            throw "TestResult: empty name"
        }
        if status == TestStatus.Passed && error != null {
            throw "TestResult: passed with error"
        }
        if status != TestStatus.Passed && error == null {
            throw "TestResult: missing error"
        }
        Int index = 0
        while index < logs.length() {
            if logs.get(index) == null {
                throw "TestResult: null log"
            }
            index = index + 1
        }
        _name = normalized
        _status = status
        _durationMillis = durationMillis
        _error = error
        _logs = logs.copy()
    }

    String name() {
        return _name
    }

    TestStatus status() {
        return _status
    }

    Long durationMillis() {
        return _durationMillis
    }

    Error? error() {
        return _error
    }

    List<String> logs() {
        return _logs.copy()
    }

    String describe() {
        String result = _name + ": " + statusText(_status)
            + " (" + str(_durationMillis) + "ms)"
        if _error != null {
            Error failure = _error as Error
            result = result + " - " + failure.describe()
        }
        return result
    }

    private static String statusText(TestStatus status) {
        if status == TestStatus.Passed {
            return "Passed"
        }
        if status == TestStatus.Failed {
            return "Failed"
        }
        return "Skipped"
    }
}
```
