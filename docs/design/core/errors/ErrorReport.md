# `ErrorReport`

### 1. 定位

在一个根错误上记录失败步骤；纵向调用链；不改变 kind。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_root` | `BasicError` | final | 非空 |
| `_steps` | `List<String>` | 内部 | 最多 16；根→外 |

不变量：root 非空；step 非空单行；steps ≤16；describe 单行。

### 3. 使用的技术

- 不可变对象；
- 步骤链；
- 字符串快照。

### 4. 需要的支撑

- 语言：class、List、String、Result；
- 运行时：无；
- 接口：`BasicError`、`ErrorDetail`、`isValidStep`。

### 5. 依赖的特性/接口/类

`BasicError`、`ErrorDetail`、`isValidStep`、`List`、`Result`。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ErrorReport(root)` | 构造 | root | `ErrorReport` | null → panic |
| `root/steps/stepCount` | 读取 | 无 | 对应值 | 无 |
| `kind/message/code/describe` | 错误协议 | 无 | 对应值 | 无 |
| `details/causes` | 快照 | 无 | 列表 | 无 |
| `withStep/tryWithStep` | 追加一步 | step | `ErrorReport`/`Result` | 非法/超 16 → panic/`InvalidArgument` |
| `withSteps/tryWithSteps` | 追加多步 | steps | `ErrorReport`/`Result` | 非法/超限 |
| `withoutStep/tryWithoutStep` | 删除一步 | index | `ErrorReport`/`Result` | 越界 |
| `clearSteps` | 清空 | 无 | `ErrorReport` | 无 |
| `toBasicError` | 转基础错误 | 无 | `BasicError` | 无 |
| `copy` | 复制 | 无 | `ErrorReport` | 无 |

### 7. XNull 伪代码

```xnull
class ErrorReport implements Error, DetailedError {
    BasicError _root
    List<String> _steps = []

    ErrorReport(BasicError root) {
        if root == null {
            throw "ErrorReport: null root"
        }
        _root = root
    }

    BasicError root() { return _root }
    Int stepCount() { return _steps.length() }

    List<String> steps() {
        List<String> result = []
        Int index = 0
        while index < _steps.length() {
            result.push(_steps.get(index))
            index = index + 1
        }
        return result
    }

    ErrorKind kind() { return _root.kind() }
    String message() { return _root.message() }
    String code() { return _root.code() }
    List<ErrorDetail> details() { return _root.details() }

    List<BasicError> causes() {
        List<BasicError> result = []
        result.push(_root)
        return result
    }

    String describe() {
        String result = ""
        Int index = _steps.length() - 1
        while index >= 0 {
            result = result + _steps.get(index) + " -> "
            index = index - 1
        }
        return result + _root.describe()
    }

    ErrorReport withStep(String step) {
        if !isValidStep(step) {
            throw "ErrorReport.withStep: invalid step"
        }
        if _steps.length() >= 16 {
            throw "ErrorReport.withStep: too many steps"
        }
        ErrorReport result = new ErrorReport(_root)
        result._steps = self.steps()
        result._steps.push(step)
        return result
    }

    Result<ErrorReport, Error> tryWithStep(String step) {
        if !isValidStep(step) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid step"))
        }
        if _steps.length() >= 16 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many steps"))
        }
        return Ok(self.withStep(step))
    }

    ErrorReport withSteps(List<String> steps) {
        if _steps.length() + steps.length() > 16 {
            throw "ErrorReport.withSteps: too many steps"
        }
        ErrorReport result = new ErrorReport(_root)
        result._steps = self.steps()
        Int index = 0
        while index < steps.length() {
            String step = steps.get(index)
            if !isValidStep(step) {
                throw "ErrorReport.withSteps: invalid step"
            }
            result._steps.push(step)
            index = index + 1
        }
        return result
    }

    Result<ErrorReport, Error> tryWithSteps(List<String> steps) {
        if _steps.length() + steps.length() > 16 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many steps"))
        }
        Int index = 0
        while index < steps.length() {
            if !isValidStep(steps.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid step"))
            }
            index = index + 1
        }
        return Ok(self.withSteps(steps))
    }

    ErrorReport withoutStep(Int index) {
        if index < 0 || index >= _steps.length() {
            throw "ErrorReport.withoutStep: out of range"
        }
        ErrorReport result = new ErrorReport(_root)
        Int position = 0
        while position < _steps.length() {
            if position != index {
                result._steps.push(_steps.get(position))
            }
            position = position + 1
        }
        return result
    }

    Result<ErrorReport, Error> tryWithoutStep(Int index) {
        if index < 0 || index >= _steps.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "index out of range"))
        }
        return Ok(self.withoutStep(index))
    }

    ErrorReport clearSteps() {
        return new ErrorReport(_root)
    }

    ErrorReport copy() {
        ErrorReport result = new ErrorReport(_root)
        result._steps = self.steps()
        return result
    }

    BasicError toBasicError() {
        BasicError result = new BasicError(_root.kind(), _root.message())
        result = result.withCode(_root.code())
        List<ErrorDetail> rootDetails = _root.details()
        Int detailIndex = 0
        while detailIndex < rootDetails.length() {
            ErrorDetail detail = rootDetails.get(detailIndex)
            result = result.withDetail(detail.key(), detail.value())
            detailIndex = detailIndex + 1
        }
        List<BasicError> rootCauses = _root.causes()
        Int causeIndex = 0
        while causeIndex < rootCauses.length() {
            result = result.withCause(rootCauses.get(causeIndex))
            causeIndex = causeIndex + 1
        }
        return result
    }
}

Bool isValidStep(String step) {
    if step == "" { return false }
    if step.indexOf("\n") >= 0 { return false }
    if step.indexOf("\r") >= 0 { return false }
    if step.indexOf("\t") >= 0 { return false }
    return true
}
```

---
