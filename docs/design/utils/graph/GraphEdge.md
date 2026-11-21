# `GraphEdge`

| 项 | 值 |
| --- | --- |
| 类型 | `class GraphEdge<T>` |
| 包 | `xdk.graph` |
| 稳定性 | `preview` |
| 依赖 | `Double`、`Bool`、`String`、`isNaN`、`isInf`、`str` |

---

## 1. 定位

不可变有向加权边对象：起点 `from`、终点 `to`、权重 `weight`；只描述一条边，不知道所属图。

不做：无向边、平行边标识、超边、节点对象、图成员校验、排序、序列化、权重归一化。

---

## 2. 设计逻辑

- 三个字段全部 `final`：构造后只读，可安全跨任务共享。
- 构造即校验：`from`/`to` 非 null；`weight` 必须是有限 `Double`（拒绝 `NaN`、`+Inf`、`-Inf`）。
- 允许负权重与 `0.0`：边只保证“有限”；加权算法（Dijkstra，X）自行拒绝负权重。
- 允许自环：`from == to` 是合法边；是否有环由 `Graph.hasCycle` 判断。
- 端点按引用保存；相等语义由 `T` 决定（`String` 按内容，普通 class 按引用）。
- `describe` 生成稳定、可读、不可反解析的单行文本；不承诺转义与本地化。
- 不缓存 `describe` 结果；不实现值相等；不持有图或节点所有权。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_from` | `T` | 起点，非 null |
| `_to` | `T` | 终点，非 null |
| `_weight` | `Double` | 有限权重 |

不变量：`_from != null`；`_to != null`；`isNaN(_weight) == false` 且 `isInf(_weight) == false`；三字段构造后不变；`isSelfLoop()` 当且仅当 `_from == _to`；边不拥有节点，也不保证端点存在于任何图。

---

## 4. 生命周期

构造后长期有效；无 `close`；无资源；可被多个图引用；图删除边不会使已取出的 `GraphEdge` 失效。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GraphEdge(T source, T target, Double weight)` | 全部 | `source`/`target` 非 null；`weight` 有限 | 非法 → panic |

说明：构造参数名 `source`/`target` 与访问器 `from()`/`to()` 对应；调用方不应传 null 端点。

---

## 6. 字段表

见 §3；字段私有，仅通过 `from()`/`to()`/`weight()` 读取。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `from` | 起点 | 无 | `T` | 无 |
| `to` | 终点 | 无 | `T` | 无 |
| `weight` | 权重 | 无 | `Double` | 无 |
| `isSelfLoop` | 是否自环 | 无 | `Bool` | 无 |
| `describe` | 文本描述 | 无 | `String` | 无 |

说明：

- `from`/`to` 返回构造时保存的引用，不做复制；端点本身的可变性由 `T` 决定。
- `isSelfLoop` 使用 `==`；对 `String` 是内容相等，对普通 class 是引用相等。
- `describe` 形如 `"a -> b (weight=1.0)"`；使用 `str` 输出端点与权重，不加引号、不转义、不本地化。
- `describe` 只用于诊断与日志；不要用文本反解析重建边。

---

## 8. 使用的技术

- 不可变对象；
- 构造期参数校验；
- 泛型端点；
- 有限浮点判定；
- 稳定文本格式化。

---

## 9. 需要的支撑

- 语言：class、泛型、`Double`、`Bool`、`String`、`final` 字段；
- 运行时：`isNaN`、`isInf`、`str`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`Double`、`Bool`、`String`、`isNaN`、`isInf`、`str`。不依赖 `Graph`、`xdk.event`、`xdk.reflect`、`xdk.log`，也不注册到任何全局结构。

---

## 11. 所有权与并发

引用语义但不可变；构造完成后可跨任务并发读取；端点引用共享，端点自身可变性由调用方负责；无锁、无资源、无 `close`。

---

## 12. 示例与反例

正确：

```text
GraphEdge<String> edge = new GraphEdge<String>("compile", "link", 1.0)
String text = edge.describe()
```

反例：

- 用 `NaN` 或 `Inf` 作权重；
- 传 null 端点；
- 期望修改 `weight()` 返回值改变边；
- 期望 `GraphEdge` 自己判断端点是否已加入图；
- 用 `describe` 文本作为持久化格式；
- 把自环当作非法边；自环合法，是否成环由图判断。

---

## 13. 测试/场景义务

null 起点/终点；`NaN`/`+Inf`/`-Inf`；`0.0`、负数、最小/最大有限值；自环；普通边；`String` 与 `Int` 端点；`from`/`to`/`weight` 读取；`describe` 格式；同一 `GraphEdge` 加入两个图；构造失败不产生半初始化对象。

---

## 14. XNull 伪代码

```xnull
class GraphEdge<T> {
    final T _from
    final T _to
    final Double _weight

    GraphEdge(T source, T target, Double weight) {
        if source == null || target == null {
            throw "GraphEdge: null endpoint"
        }
        if isNaN(weight) || isInf(weight) {
            throw "GraphEdge: weight must be finite"
        }
        _from = source
        _to = target
        _weight = weight
    }

    T from() { return _from }

    T to() { return _to }

    Double weight() { return _weight }

    Bool isSelfLoop() { return _from == _to }

    String describe() {
        return str(_from) + " -> " + str(_to) + " (weight=" + str(_weight) + ")"
    }
}
```
