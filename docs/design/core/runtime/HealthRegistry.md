# `HealthRegistry`

| 项 | 值 |
| --- | --- |
| 类型 | `class HealthRegistry` |
| 包 | `xdk.runtime` |
| 稳定性 | `preview` |
| 依赖 | `HealthCheck`、`HealthReport`、`HealthState` |

---

## 1. 定位

健康检查注册与聚合：注册命名检查、单项查询、整体快照、就绪/存活判断。

不做：HTTP 端点、指标导出、告警、自动发现、后台轮询、依赖注入容器。

---

## 2. 设计逻辑

- 字段 `_checks: Map<String, HealthCheck>`。
- 注册阶段可变；启动后只读；不内建锁，调用方在冻结后不得并发修改。
- `add` 名称重复/null 是合同错误（panic）；`remove` 未知返回 false。
- `check(name)` 未知返回 null；已知调用一次 `check()`。
- `checkAll` 逐项调用，取最严重状态（`healthStateRank` 最大）；空注册表视为 `Healthy`。
- 聚合 details 使用 `<name>.state`、`<name>.message` 和 `<name>.<detailKey>` 前缀。
- 检查必须非阻塞；注册表不提供超时/重试。
- 聚合快照不可变；不持有检查的内部状态。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_checks` | `Map<String,HealthCheck>` | 名称唯一；值非 null |

不变量：名称唯一；值非 null；注册表不修改检查对象；聚合不修改注册表。

---

## 4. 生命周期

构造为空；`add/remove/clear` 配置；`check/checkAll` 读取；无 close；无 OS 资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HealthRegistry()` | 无 | 空注册表 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 注册检查 | `HealthCheck check` | `void` | null/重名/空名 → panic |
| `remove` | 移除检查 | `String name` | `Bool` | null → panic |
| `has` | 是否存在 | `String name` | `Bool` | null → panic |
| `check` | 单项快照 | `String name` | `HealthReport?` | null → panic |
| `checkAll` | 聚合快照 | 无 | `HealthReport` | 检查返回 null → panic |
| `overall` | 聚合状态 | 无 | `HealthState` | 无 |
| `names` | 名称快照 | 无 | `List<String>` | 无 |
| `length` | 检查数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

说明：

- `checkAll` 的 message：`"N checks; worst=<state>"`。
- 空注册表：`Healthy`，message `"no checks"`，无 details。
- `overall` 不构建 details；等价于 `checkAll().state()` 但可避免分配。
- `names` 返回快照，顺序不承诺。

---

## 8. 使用的技术

- 名称映射；
- 聚合取最严重；
- 快照 details；
- 非阻塞检查。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Int、Bool；
- 运行时：`nowMono`；
- 接口：`HealthCheck`、`HealthReport`、`HealthState`、`healthStateRank`、`healthStateName`。

---

## 10. 依赖的特性/接口/类

`HealthCheck`、`HealthReport`、`HealthState`、`healthStateRank`、`healthStateName`。

---

## 11. 所有权与并发

引用语义；注册阶段非线程安全；冻结后只读；检查可并发调用；无资源；无取消点。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
HealthRegistry registry = new HealthRegistry()
registry.add(new DbCheck(db))
registry.add(new CacheCheck(cache))
HealthReport report = registry.checkAll()
if !report.isReady() { rejectTraffic() }
```

反例：启动后并发 add/remove；`checkAll` 阻塞在数据库；重复名称；检查返回 null；
用健康检查替代错误处理。

---

## 13. 测试/场景义务

空注册表；单项/多项；重名；null；remove/has；单项查询；聚合状态优先级；details 前缀；
快照独立；健康→降级→不健康；就绪判断；并发读取。

---

## 14. XNull 伪代码

```xnull
class HealthRegistry {
    final Map<String, HealthCheck> _checks = [:]

    HealthRegistry() {}

    void add(HealthCheck check) {
        if check == null { throw "HealthRegistry.add: null check" }
        String name = check.name()
        if name == null || name == "" {
            throw "HealthRegistry.add: empty name"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\t") >= 0 {
            throw "HealthRegistry.add: multiline name"
        }
        if _checks.has(name) {
            throw "HealthRegistry.add: duplicate name"
        }
        _checks.put(name, check)
    }

    Bool remove(String name) {
        if name == null { throw "HealthRegistry.remove: null name" }
        return _checks.remove(name)
    }

    Bool has(String name) {
        if name == null { throw "HealthRegistry.has: null name" }
        return _checks.has(name)
    }

    HealthReport? check(String name) {
        if name == null { throw "HealthRegistry.check: null name" }
        if !_checks.has(name) { return null }
        HealthCheck source = _checks.getOr(name, null) as HealthCheck
        HealthReport report = source.check()
        if report == null { throw "HealthRegistry.check: null report" }
        return report
    }

    HealthReport checkAll() {
        List<String> names = _checks.keys()
        if names.length() == 0 {
            return HealthReport.of(HealthState.Healthy, "no checks")
        }
        HealthState worst = HealthState.Healthy
        Int worstRank = 0
        Map<String, String> details = [:]
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            HealthCheck source = _checks.getOr(name, null) as HealthCheck
            HealthReport report = source.check()
            if report == null { throw "HealthRegistry.checkAll: null report" }
            Int rank = healthStateRank(report.state())
            if rank > worstRank {
                worstRank = rank
                worst = report.state()
            }
            details.put(name + ".state", healthStateName(report.state()))
            details.put(name + ".message", report.message())
            Map<String, String> child = report.details()
            List<String> childKeys = child.keys()
            Int childIndex = 0
            while childIndex < childKeys.length() {
                String childKey = childKeys.get(childIndex)
                details.put(name + "." + childKey, child.getOr(childKey, ""))
                childIndex = childIndex + 1
            }
            index = index + 1
        }
        String message = str(names.length()) + " checks; worst=" + healthStateName(worst)
        return new HealthReport(worst, message, nowMono(), details)
    }

    HealthState overall() {
        List<String> names = _checks.keys()
        HealthState worst = HealthState.Healthy
        Int worstRank = 0
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            HealthCheck source = _checks.getOr(name, null) as HealthCheck
            HealthReport report = source.check()
            if report == null { throw "HealthRegistry.overall: null report" }
            Int rank = healthStateRank(report.state())
            if rank > worstRank {
                worstRank = rank
                worst = report.state()
            }
            index = index + 1
        }
        return worst
    }

    List<String> names() {
        return _checks.keys()
    }

    Int length() {
        return _checks.length()
    }

    Bool isEmpty() {
        return _checks.length() == 0
    }

    void clear() {
        _checks.clear()
    }
}
```
