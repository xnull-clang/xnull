# `TaskSnapshot`

### 1. 定位

`dumpTasks` 使用的内部任务快照；不属于公共 API。

### 2. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_id` | `Int` | 任务 ID |
| `_state` | `String` | 状态文本 |
| `_name` | `String` | 任务名；可为空 |

### 3. 使用的技术

- 不可变诊断快照；
- 字符串拼接；
- 任务系统快照。

### 4. 需要的支撑

- 语言：class、Int、String；
- 运行时：`snapshotTasks()` 任务快照原语；
- 接口：`diagnose`（由 `dumpTasks` 使用）。

### 5. 依赖的特性/接口/类

无公共类型依赖；由 `dumpTasks` 使用，不属于公共 API。

### 6. 方法面

`id()`、`state()`、`name()`、`describe()`。

### 7. XNull 伪代码

```xnull
class TaskSnapshot {
    Int _id
    String _state
    String _name

    TaskSnapshot(Int taskId, String state, String name) {
        _id = taskId
        _state = state
        _name = name
    }

    Int id() { return _id }
    String state() { return _state }
    String name() { return _name }

    String describe() {
        return "task " + str(_id) + " state=" + _state + " name=" + _name
    }
}
```

---
