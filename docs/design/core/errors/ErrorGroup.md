# `ErrorGroup`

### 1. 定位

一次操作产生多个错误时聚合；横向多错误；Cancelled 优先。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_errors` | `List<BasicError>` | 可变 | 子错误；加入顺序 |

不变量：子错误非 null、非 self；空组合法；details 前缀 `<index>.`；describe 最多 3 条。

### 3. 使用的技术

- 可变构建器；
- 聚合规则（Cancelled 优先）；
- 索引前缀；
- 快照列表。

### 4. 需要的支撑

- 语言：class、List、String、ErrorKind、Int、Bool；
- 运行时：无；
- 接口：`BasicError`、`ErrorDetail`、`Result`。

### 5. 依赖的特性/接口/类

`BasicError`、`ErrorDetail`、`ErrorKind`、`List`、`Result`。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ErrorGroup()` | 构造空组 | 无 | `ErrorGroup` | 无 |
| `add` | 追加 | error | `void` | null/self → panic |
| `addAll` | 追加多个 | errors | `void` | 非法 → panic |
| `addResult` | 追加 Err | Result | `void` | null → panic |
| `length/isEmpty` | 数量/空 | 无 | `Int`/`Bool` | 无 |
| `first/last` | 首/尾 | 无 | `BasicError?` | 无 |
| `contains` | 是否包含 | error | `Bool` | 无 |
| `kind` | 聚合分类 | 无 | `ErrorKind` | 无 |
| `message/code/describe` | 错误协议 | 无 | 对应值 | 无 |
| `details` | 聚合细节 | 无 | `List<ErrorDetail>` | 无 |
| `causes/toList` | 子错误快照 | 无 | `List<BasicError>` | 无 |
| `toBasicError` | 转基础错误 | 无 | `BasicError` | 无 |
| `remove` | 删除 | index | `BasicError` | 越界 → panic |
| `clear` | 清空 | 无 | `void` | 无 |

> `toBasicError()` 的 cause 最多 8 条；超过 8 条时 details 保留全部，causes 只保留前 8 条。这是 BasicError 的原因链上限，不是 ErrorGroup 的聚合上限。

### 7. XNull 伪代码

```xnull
class ErrorGroup implements Error, DetailedError {
    List<BasicError> _errors = []

    ErrorGroup() {
    }

    void add(BasicError error) {
        if error == null {
            throw "ErrorGroup.add: null"
        }
        if error == self {
            throw "ErrorGroup.add: self"
        }
        _errors.push(error)
    }

    void addAll(List<BasicError> errors) {
        Int index = 0
        while index < errors.length() {
            self.add(errors.get(index))
            index = index + 1
        }
    }

    void addResult<T>(Result<T, BasicError> result) {
        if result.isErr() {
            self.add(result.error())
        }
    }

    Int length() { return _errors.length() }
    Bool isEmpty() { return _errors.length() == 0 }

    BasicError? first() {
        if self.isEmpty() { return null }
        return _errors.get(0)
    }

    BasicError? last() {
        if self.isEmpty() { return null }
        return _errors.get(_errors.length() - 1)
    }

    Bool contains(BasicError error) {
        Int index = 0
        while index < _errors.length() {
            if _errors.get(index) == error {
                return true
            }
            index = index + 1
        }
        return false
    }

    ErrorKind kind() {
        if self.isEmpty() {
            return ErrorKind.InvalidArgument
        }
        Bool sawCancelled = false
        ErrorKind firstKind = ErrorKind.InvalidArgument
        Bool hasFirst = false
        Int index = 0
        while index < _errors.length() {
            ErrorKind current = _errors.get(index).kind()
            if current == ErrorKind.Cancelled {
                sawCancelled = true
            } else if !hasFirst {
                firstKind = current
                hasFirst = true
            }
            index = index + 1
        }
        if sawCancelled { return ErrorKind.Cancelled }
        if hasFirst { return firstKind }
        return ErrorKind.InvalidArgument
    }

    String message() {
        if self.isEmpty() {
            return "empty error group"
        }
        return $"{_errors.length()} errors; first: {_errors.get(0).describe()}"
    }

    String code() { return "" }

    String describe() {
        if self.isEmpty() {
            return "empty error group"
        }
        String result = ""
        Int limit = _errors.length()
        if limit > 3 { limit = 3 }
        Int index = 0
        while index < limit {
            if index > 0 { result = result + "; " }
            result = result + _errors.get(index).describe()
            index = index + 1
        }
        if _errors.length() > limit {
            result = result + " ..."
        }
        return result
    }

    List<ErrorDetail> details() {
        List<ErrorDetail> result = []
        Int index = 0
        while index < _errors.length() {
            List<ErrorDetail> childDetails = _errors.get(index).details()
            Int childIndex = 0
            while childIndex < childDetails.length() {
                ErrorDetail detail = childDetails.get(childIndex)
                String key = $"{index}." + detail.key()
                result.push(new ErrorDetail(key, detail.value()))
                childIndex = childIndex + 1
            }
            index = index + 1
        }
        return result
    }

    List<BasicError> causes() {
        List<BasicError> result = []
        Int index = 0
        while index < _errors.length() {
            result.push(_errors.get(index))
            index = index + 1
        }
        return result
    }

    List<BasicError> toList() {
        return self.causes()
    }

    BasicError toBasicError() {
        BasicError result = new BasicError(self.kind(), self.message())
        List<ErrorDetail> allDetails = self.details()
        Int detailIndex = 0
        while detailIndex < allDetails.length() {
            ErrorDetail detail = allDetails.get(detailIndex)
            result = result.withDetail(detail.key(), detail.value())
            detailIndex = detailIndex + 1
        }
        Int causeIndex = 0
        while causeIndex < _errors.length() && causeIndex < 8 {
            result = result.withCause(_errors.get(causeIndex))
            causeIndex = causeIndex + 1
        }
        return result
    }

    BasicError remove(Int index) {
        if index < 0 || index >= _errors.length() {
            throw "ErrorGroup.remove: out of range"
        }
        return _errors.remove(index)
    }

    void clear() {
        _errors.clear()
    }
}
```

---
