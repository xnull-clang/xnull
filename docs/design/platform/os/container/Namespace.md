# `Namespace`

| 项 | 值 |
| --- | --- |
| 类型 | `class Namespace` |
| 包 | `xdk.os.container` |
| 稳定性 | `preview` |
| 依赖 | `NamespaceKind` |

---

## 1. 定位

单个 namespace 条目的只读快照：类型与 OS 标识字符串。

不做：进入/创建 namespace、修改隔离、持有 namespace fd、列出其他进程的 namespace。

---

## 2. 设计逻辑

- 不可变快照；由 `ContainerHost.namespaces(context)` 或 `ContainerInfo.namespaces()` 返回。
- `kind` 是 `NamespaceKind` 分类；`id` 是 OS 标识字符串，可能是不透明编号，不承诺连续、可解析或跨重启稳定；
  `id` 可能敏感，日志中应截断。
- 不提供进入/创建；不持有 namespace fd；不暴露 `/proc` namespace 链接句柄。
- 容器内只反映当前进程可见的 namespace；不承诺宿主全部。
- 为什么是 class：需要同时承载分类与 OS 标识；不用 enum 因为标识是开放字符串；不用 struct 以避免与公开快照类型体系混用。
- `describe` 只用于诊断，不用于精确关联。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `NamespaceKind` | final | 非 null |
| `_namespaceId` | `String` | final | 非 null；正常非空 |

不变量：`kind` 非 null；`namespaceId` 非 null；不可变；不持有资源；列表/调用方不能修改内部状态。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Namespace(NamespaceKind kind, String namespaceId)` | kind、namespaceId | 非 null | null → panic |

构造器主要供适配器/测试使用；业务代码通过 `ContainerHost.namespaces` 或 `ContainerInfo.namespaces` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `kind` | namespace 类型 | 无 | `NamespaceKind` | 无 | O(1) |
| `id` | OS 标识字符串 | 无 | `String` | 无 | O(1)；不承诺完整/稳定 |
| `describe` | 单行摘要 | 无 | `String` | 无 | O(n)；仅诊断 |

无 equals/copy：需要比较时逐字段比较；`==` 是引用身份。

---

## 8. 使用的技术

- 不可变快照；
- 枚举分类；
- 字符串标识；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Enum；
- 运行时/适配器：namespace 快照读取；
- 接口：`NamespaceKind`、`ContainerHost`、`ContainerInfo`。

---

## 10. 依赖的特性/接口/类

`NamespaceKind`、`ContainerInfo`、`ContainerHost`。

---

## 11. 所有权与并发

引用语义；不可变；可跨任务共享；无资源；无取消点。
相等：`==` 是引用身份；本基线不提供 `equals`；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`NamespaceKind kind = entry.kind()`；用 `entry.id()` 做诊断输出。  
反例：把 namespace 标识当持久键；假设标识是数字；close 后继续使用；把容器内 namespace 当宿主全部。

---

## 13. 测试/场景义务

每种 `NamespaceKind`；null 构造参数 panic；空标识占位；长/不透明标识；`describe`；
容器内可见集合；非容器空集合；引用身份与逐字段比较的差异。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Namespace {
    final NamespaceKind _kind
    final String _namespaceId

    Namespace(NamespaceKind kind, String namespaceId) {
        if kind == null || namespaceId == null {
            throw "Namespace: null field"
        }
        _kind = kind
        _namespaceId = namespaceId
    }

    NamespaceKind kind() { return _kind }

    String id() { return _namespaceId }

    String describe() {
        return namespaceKindName(_kind) + ":" + _namespaceId
    }
}
```
