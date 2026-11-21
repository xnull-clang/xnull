# `ServiceInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class ServiceInfo` |
| 包 | `xdk.os.service` |
| 稳定性 | `preview` |
| 依赖 | `ServiceState` |

---

## 1. 定位

单个 OS 系统服务的不可变快照：身份、显示名、运行状态、开机启用、进程号、描述。

不做：控制服务、读取日志、读取环境变量、记录命令行、写 unit/plist、依赖关系、健康检查。

---

## 2. 设计逻辑

- 由 `ServiceManager.services`/`ServiceManager.status` 返回；不自动刷新。
- `name` 是 OS 服务名和控制键；必须满足公开服务名契约。
- `displayName` 是人类可读名，可为空串；不得作为控制键。
- `state` 是粗粒度运行状态；`isEnabled` 是开机启用快照，两者独立；`isEnabled` 为 true 仅当 OS 明确报告开机启用，未知/不适用按 false。
- `pid` 用 `Long`；`0` 表示未运行或 OS 未暴露；`Running` 时也可能为 `0`。
- `description` 单行文本，可为空串；不得包含环境变量、密钥、完整命令行。
- 不可变；无 `close`；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空；满足服务名白名单；≤255 |
| `_displayName` | `String` | final | 非 null；可为空串 |
| `_state` | `ServiceState` | final | 非 null |
| `_isEnabled` | `Bool` | final | true 仅当 OS 明确报告开机启用；未知按 false |
| `_pid` | `Long` | final | ≥0；`0` = 未运行/未知 |
| `_description` | `String` | final | 非 null；适配器保证单行；可为空串 |

不变量：名称合法；`pid ≥ 0`；`state` 非 null；`isEnabled` 与 `state` 独立；不包含敏感信息；不可变；`description` 由适配器压成单行。

---

## 4. 生命周期

由适配器/`ServiceManager` 构造；构造后不可变；无 close；可共享；快照不自动更新。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ServiceInfo(String serviceName, String displayName, ServiceState state, Bool isEnabled, Long pid, String description)` | 6 个字段 | 名称合法；字符串非 null；`state` 非 null；`pid ≥ 0` | null/非法名称/负 pid → panic |

说明：

- 构造器主要供适配器/测试使用；业务代码通过 `ServiceManager` 获取。
- `displayName` 为空串时由适配器填 `name`；构造器不推断。
- `description` 中的换行由适配器压成单行；构造器只做非 null 检查。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | OS 服务名/控制键 | 无 | `String` | 无 |
| `displayName` | 人类可读名 | 无 | `String` | 无 |
| `state` | 运行状态 | 无 | `ServiceState` | 无 |
| `isEnabled` | 开机启用 | 无 | `Bool` | 无 |
| `pid` | 主进程号（0=未知/未运行） | 无 | `Long` | 无 |
| `description` | 单行描述 | 无 | `String` | 无 |
| `describe` | 单行诊断摘要 | 无 | `String` | 无 |

说明：

- 所有 getter 返回快照值；`String` 不可变。
- `describe` 只包含服务名、状态、pid；不包含描述/显示名/环境变量。
- `pid == 0` 不是错误；不得据此推断服务一定停止。

---

## 8. 使用的技术

- 不可变快照；
- final 字段；
- 名称白名单校验；
- 字符串诊断。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、ServiceState、Bool、Long、Char、Int；
- 运行时/适配器：无（由 `ServiceManager` 适配器构造）；
- 接口：`isValidServiceName`（包内辅助函数，随本文档定义）、`serviceStateName`、`ServiceManager`、`OsHost`。

---

## 10. 依赖的特性/接口/类

`ServiceState`、`ServiceManager`、`OsHost`、`isValidServiceName`、`serviceStateName`。

---

## 11. 所有权与并发

不可变；可共享；无资源；无取消点；跨任务读取安全。
相等：引用身份；需要比较时逐字段比较；不推荐作 `Map` 键；如需索引，用 `name` 字符串。

---

## 12. 示例与反例

正确：`info.state() == ServiceState.Running` 后再使用；`info.pid() == 0` 时按未知处理；控制时使用 `info.name()`；日志使用 `describe()`。  
反例：用 `displayName()` 调 `start`；`Running` 时断言 `pid() > 0`；把 `isEnabled()` 当运行状态；把 `description()` 原样写日志；用未校验名称构造。

---

## 13. 测试/场景义务

null 字段；空名称；名称 255/256 字符边界；非法字符（空格、`/`、`\`、`;`、`$`、反引号、换行、非 ASCII）；负 pid；pid 0；
`Running` + pid 0；空 `displayName`；空 `description`；多行描述归一；`describe` 不含敏感信息；
全部 `ServiceState` 成员；不可变性；名称合法字符 `[A-Za-z0-9_.@-]`。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
class ServiceInfo {
    final String _name
    final String _displayName
    final ServiceState _state
    final Bool _isEnabled
    final Long _pid
    final String _description

    ServiceInfo(String serviceName, String displayName, ServiceState state,
                Bool isEnabled, Long pid, String description) {
        if serviceName == null || displayName == null || state == null
            || description == null {
            throw "ServiceInfo: null field"
        }
        if !isValidServiceName(serviceName) {
            throw "ServiceInfo: invalid service name"
        }
        if pid < 0 { throw "ServiceInfo: negative pid" }
        _name = serviceName
        _displayName = displayName
        _state = state
        _isEnabled = isEnabled
        _pid = pid
        _description = description
    }

    String name() { return _name }
    String displayName() { return _displayName }
    ServiceState state() { return _state }
    Bool isEnabled() { return _isEnabled }
    Long pid() { return _pid }
    String description() { return _description }

    String describe() {
        return "service " + _name
            + " state=" + serviceStateName(_state)
            + " pid=" + str(_pid)
    }
}

Bool isValidServiceName(String serviceName) {
    if serviceName == null { return false }
    if serviceName.length() == 0 { return false }
    if serviceName.length() > 255 { return false }
    Int index = 0
    while index < serviceName.length() {
        Char character = serviceName.charAt(index)
        Bool isUpper = character >= 'A' && character <= 'Z'
        Bool isLower = character >= 'a' && character <= 'z'
        Bool isDigit = character >= '0' && character <= '9'
        Bool isAllowed = isUpper || isLower || isDigit
            || character == '_' || character == '.'
            || character == '@' || character == '-'
        if !isAllowed { return false }
        index = index + 1
    }
    return true
}
```
