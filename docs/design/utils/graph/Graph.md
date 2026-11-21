# `Graph`

| 项 | 值 |
| --- | --- |
| 类型 | `class Graph<T>` |
| 包 | `xdk.graph` |
| 稳定性 | `preview` |
| 依赖 | `GraphEdge`、`List`、`Set`、`Map`、`Result`、`Error`、`BasicError`、`ErrorKind` |

---

## 1. 定位

进程内、单线程使用的有向简单图：节点/边增删、邻接查询、BFS/DFS、环检测、拓扑排序、无权最短路径。

不做：线程安全、平行边、无向图、超图、持久化、全局图注册表、加权最短路径（Dijkstra，X）、最大流、最小生成树、A*。

---

## 2. 设计逻辑

- 节点集合 `_nodes` 与边集合 `_edges` 都保持插入顺序；遍历与算法结果因此确定。
- 每节点维护出边表 `_outgoing` 与入边表 `_incoming`；节点加入时两表同时建空桶。
- 节点身份遵循 `T` 的 `==`/`Map` 键语义：`String`/`Int` 按值，普通 class 默认按引用；需要值语义的节点类型应自行定义相等。
- 简单有向图：同一有序端点对 `(from, to)` 至多一条边；平行边不支持；自环允许。
- 自环是一条边，同时计入出边与入边；环检测与拓扑排序把它当作长度为 1 的环。
- `addNode` 幂等：已存在则保留原位置，不报错。
- `addEdge` 要求两个端点都已存在；未知端点或重复有序端点对是合同错误，直接 panic。
- `removeNode` 级联删除所有入射/出射边，再删除节点；未知节点是无操作。
- `removeEdge` 删除匹配的有序端点对；未知边是无操作，便于清理。
- `hasNode`/`hasEdge` 是查询谓词：null 或未知返回 `false`，不 panic。
- `neighbors` 只返回出边目标，顺序等于出边插入顺序。
- `bfs` 使用队列；`dfs` 使用显式栈并逆序压栈，保证按出边顺序前序访问。
- `hasCycle` 与 `topologicalSort` 共用 Kahn 入度计算；拓扑结果长度小于节点数即存在环。
- `topologicalSort` 在环上返回 `InvalidArgument`，不返回部分结果。
- `shortestPath` 使用无权 BFS：路径包含起点与终点，边数最少；`weight` 不参与计算。
- `shortestPath` 的未知端点是 `InvalidArgument`，不可达是 `NotFound`；`source == target` 返回单元素路径。
- 无全局注册表；所有状态在实例内；无后台任务、无定时器。
- 非线程安全：无内部锁；跨任务共享必须由调用方用 `Mutex`/`RwLock` 保护。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_nodes` | `List<T>` | 唯一节点，插入顺序 |
| `_edges` | `List<GraphEdge<T>>` | 唯一边，插入顺序 |
| `_outgoing` | `Map<T, List<GraphEdge<T>>>` | 每节点出边表 |
| `_incoming` | `Map<T, List<GraphEdge<T>>>` | 每节点入边表 |

不变量：

- `_nodes` 无 null、无重复；唯一性遵循 `T` 的 `==`/`Map` 键语义。
- `_outgoing` 与 `_incoming` 各含且仅含 `_nodes` 中的节点。
- `_edges` 中不存在两个 `from`/`to` 相同的有向边。
- 每条边的两个端点都在 `_nodes` 中。
- `_edges` 中的每个对象在 `_outgoing[edge.from()]` 与 `_incoming[edge.to()]` 中各出现一次。
- `_edges.length()` 等于所有出边表长度之和；自环只计一次。
- 每个邻接表内部顺序等于该边加入 `_edges` 的顺序。
- 邻接表只持有 `GraphEdge` 引用，不复制边。

---

## 4. 生命周期

构造得到空图；随 `addNode`/`addEdge` 增长，随 `removeNode`/`removeEdge` 收缩；无 `close`、无资源、无后台活动。图被丢弃时节点与边引用一并释放；删除节点会级联释放其关联边。遍历/算法执行期间禁止结构性修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Graph()` | 无 | 创建空图 | 无 |

不提供从列表/边集合批量构造的构造器；批量装配由调用方显式循环，保证校验路径唯一。

---

## 6. 字段表

见 §3；字段私有，不暴露内部容器。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `addNode` | 添加节点 | `T node` | `void` | null → panic |
| `addEdge` | 添加有向边 | `GraphEdge<T> edge` | `void` | null 边/未知端点/重复有序对 → panic |
| `removeNode` | 删除节点及关联边 | `T node` | `void` | null → panic；未知 → 无操作 |
| `removeEdge` | 删除有向边 | `T source, T target` | `void` | null → panic；未知 → 无操作 |
| `hasNode` | 节点是否存在 | `T node` | `Bool` | 无；null → `false` |
| `hasEdge` | 边是否存在 | `T source, T target` | `Bool` | 无；null → `false` |
| `nodes` | 节点快照 | 无 | `List<T>` | 无 |
| `edges` | 边快照 | 无 | `List<GraphEdge<T>>` | 无 |
| `nodeCount` | 节点数 | 无 | `Int` | 无 |
| `edgeCount` | 边数 | 无 | `Int` | 无 |
| `neighbors` | 出边目标 | `T node` | `List<T>` | null/未知节点 → panic |
| `bfs` | 广度优先遍历 | `T start` | `List<T>` | null/未知起点 → panic |
| `dfs` | 深度优先遍历 | `T start` | `List<T>` | null/未知起点 → panic |
| `hasCycle` | 是否存在有向环 | 无 | `Bool` | 无 |
| `topologicalSort` | 拓扑序 | 无 | `Result<List<T>, Error>` | 有环 → `InvalidArgument` |
| `shortestPath` | 无权最短路径 | `T source, T target` | `Result<List<T>, Error>` | 未知端点 → `InvalidArgument`；不可达 → `NotFound` |

说明：

- `addNode` 对已存在节点是无操作；节点位置不变。
- `addEdge` 允许自环；拒绝平行边；端点在加入前必须已 `addNode`。
- `removeNode` 先删除关联边再删节点；对自环只删除一次。
- `removeEdge` 只删除一条匹配边；不存在时无操作；参数顺序敏感。
- `hasNode`/`hasEdge` 是总查询，不因 null/未知而失败。
- `nodes`/`edges` 返回新列表；修改返回列表不影响图，列表中的节点与边仍是共享引用。
- `neighbors` 返回新列表；同一目标不会重复（无平行边）；自环会在结果中出现一次。
- `bfs` 从起点开始，按队列顺序访问；未连通节点不出现；起点只出现一次。
- `dfs` 是迭代前序；子节点按其出边插入顺序访问；不使用递归，避免深图栈溢出。
- `hasCycle` 对自环返回 `true`；空图与单节点无自环返回 `false`。
- `topologicalSort` 使用确定性的 Kahn 算法；空图返回空列表的成功结果；有环返回 `InvalidArgument`。
- `shortestPath` 按边数最少，忽略 `weight`；返回路径包含起点与终点；无路径返回 `Err(NotFound)`。
- `shortestPath` 的 `source == target` 返回只含该节点的路径，不要求图中有边。
- 所有返回 `Result` 的方法在合同错误（null 参数）时仍 panic；`Result` 只承载可恢复的图语义失败。

---

## 8. 使用的技术

- 邻接表（出边 + 入边双向索引）；
- 插入有序节点/边列表；
- BFS 队列（头指针推进，避免头部删除）；
- 迭代 DFS + 逆序压栈；
- Kahn 入度拓扑排序；
- 父节点索引回溯路径；
- 防御性列表复制；
- 确定性遍历顺序。

---

## 9. 需要的支撑

- 语言：class、泛型、`List`、`Set`、`Map`、`Int`、`Bool`、`Result`、`Error`、`void`；
- 运行时：无（无锁、无时钟、无线程）；
- 接口：`BasicError`、`ErrorKind`、`GraphEdge`。

---

## 10. 依赖的特性/接口/类

`GraphEdge`、`List`、`Set`、`Map`、`Result`、`Error`、`BasicError`、`ErrorKind`。

明确不依赖：`xdk.event`、`xdk.reflect`、`xdk.log`、`xdk.runtime`；不建全局图注册表；不复制 `xdk.collections` 的容器，也不新建错误类型。

---

## 11. 所有权与并发

- 引用语义；图拥有自己的节点/边索引，不拥有节点对象本身。
- **非线程安全**：无内部锁、无原子操作、无快照隔离。
- 单任务独占写；多任务只读时不得同时有写；跨任务共享由调用方用 `Mutex`/`RwLock` 保护。
- 遍历/算法期间修改图是合同错误；需要并发修改时先取 `nodes()`/`edges()` 快照。
- `nodes()`/`edges()`/`neighbors()`/`bfs()`/`dfs()` 返回新列表；元素引用共享。
- `GraphEdge` 不可变，可在任务间安全传递；`T` 自身可变性由调用方负责。

---

## 12. 示例与反例

正确：

```text
Graph<String> graph = new Graph<String>()
graph.addNode("compile")
graph.addNode("link")
graph.addNode("test")
graph.addEdge(new GraphEdge<String>("compile", "link", 1.0))
graph.addEdge(new GraphEdge<String>("link", "test", 1.0))
Result<List<String>, Error> order = graph.topologicalSort()
List<String> path = graph.shortestPath("compile", "test").value()
```

反例：

- 未 `addNode` 就 `addEdge`，并期望自动补节点；
- 用两个内容相同但引用不同的普通 class 实例当同一节点，并期望它们合并；
- 同一 `(from, to)` 加两条不同权重的边，并期望保留平行边；
- 期望 `shortestPath` 使用 `weight` 选择最小权重路径（当前忽略权重）；
- 修改 `nodes()` 返回的列表并期望图变化；
- 在 `bfs`/`dfs` 遍历回调期间删除节点；
- 两个任务无锁同时 `addNode`/`removeEdge`；
- 期望 `hasNode(null)` 抛错；它返回 `false`；
- 期望 `topologicalSort` 在有环时返回部分顺序。

---

## 13. 测试/场景义务

空图；重复 `addNode`；`addEdge` 未知端点；重复有序端点对；自环；平行边拒绝；`removeNode` 级联（入边、出边、自环）；`removeEdge` 幂等与方向敏感；节点/边插入顺序；`neighbors` 顺序与自环；`bfs` 单点/链/分叉/不连通；`dfs` 前序与顺序；二节点环、自环、长环；DAG 拓扑；多源 DAG 拓扑确定性；空图拓扑；环拓扑错误；`shortestPath` 直达/多跳/不可达/同点/未知端点；权重不影响结果；返回列表副本；null 参数；深链迭代 DFS 不溢出。

---

## 14. XNull 伪代码

```xnull
class Graph<T> {
    final List<T> _nodes
    final List<GraphEdge<T>> _edges
    final Map<T, List<GraphEdge<T>>> _outgoing
    final Map<T, List<GraphEdge<T>>> _incoming

    Graph() {
        _nodes = []
        _edges = []
        _outgoing = new Map<T, List<GraphEdge<T>>>()
        _incoming = new Map<T, List<GraphEdge<T>>>()
    }

    void addNode(T node) {
        if node == null { throw "Graph.addNode: null node" }
        if _outgoing.has(node) { return }
        List<GraphEdge<T>> outgoing = []
        List<GraphEdge<T>> incoming = []
        _nodes.push(node)
        _outgoing.put(node, outgoing)
        _incoming.put(node, incoming)
    }

    void addEdge(GraphEdge<T> edge) {
        if edge == null { throw "Graph.addEdge: null edge" }
        if !_outgoing.has(edge.from()) || !_outgoing.has(edge.to()) {
            throw "Graph.addEdge: unknown endpoint"
        }
        if self.hasEdge(edge.from(), edge.to()) {
            throw "Graph.addEdge: duplicate edge"
        }
        _edges.push(edge)
        _outgoing.get(edge.from()).push(edge)
        _incoming.get(edge.to()).push(edge)
    }

    void removeNode(T node) {
        if node == null { throw "Graph.removeNode: null node" }
        if !_outgoing.has(node) { return }
        List<GraphEdge<T>> outgoing = _outgoing.get(node).copy()
        List<GraphEdge<T>> incoming = _incoming.get(node).copy()
        Int index = 0
        while index < outgoing.length() {
            self.removeEdge(outgoing.get(index).from(), outgoing.get(index).to())
            index = index + 1
        }
        index = 0
        while index < incoming.length() {
            self.removeEdge(incoming.get(index).from(), incoming.get(index).to())
            index = index + 1
        }
        Int position = _nodes.indexOf(node)
        if position >= 0 { _nodes.remove(position) }
        _outgoing.remove(node)
        _incoming.remove(node)
    }

    void removeEdge(T source, T target) {
        if source == null || target == null {
            throw "Graph.removeEdge: null endpoint"
        }
        if !_outgoing.has(source) || !_outgoing.has(target) { return }
        List<GraphEdge<T>> outgoing = _outgoing.get(source)
        Int index = 0
        while index < outgoing.length() {
            GraphEdge<T> edge = outgoing.get(index)
            if edge.to() == target {
                outgoing.remove(index)
                self.removeIncoming(edge)
                Int edgeIndex = _edges.indexOf(edge)
                if edgeIndex >= 0 { _edges.remove(edgeIndex) }
                return
            }
            index = index + 1
        }
    }

    private void removeIncoming(GraphEdge<T> edge) {
        List<GraphEdge<T>> incoming = _incoming.get(edge.to())
        Int index = 0
        while index < incoming.length() {
            if incoming.get(index) == edge {
                incoming.remove(index)
                return
            }
            index = index + 1
        }
    }

    Bool hasNode(T node) {
        if node == null { return false }
        return _outgoing.has(node)
    }

    Bool hasEdge(T source, T target) {
        if source == null || target == null { return false }
        if !_outgoing.has(source) { return false }
        List<GraphEdge<T>> outgoing = _outgoing.get(source)
        Int index = 0
        while index < outgoing.length() {
            if outgoing.get(index).to() == target { return true }
            index = index + 1
        }
        return false
    }

    List<T> nodes() { return _nodes.copy() }

    List<GraphEdge<T>> edges() { return _edges.copy() }

    Int nodeCount() { return _nodes.length() }

    Int edgeCount() { return _edges.length() }

    List<T> neighbors(T node) {
        if node == null { throw "Graph.neighbors: null node" }
        if !_outgoing.has(node) { throw "Graph.neighbors: unknown node" }
        List<T> result = []
        List<GraphEdge<T>> outgoing = _outgoing.get(node)
        Int index = 0
        while index < outgoing.length() {
            result.push(outgoing.get(index).to())
            index = index + 1
        }
        return result
    }

    List<T> bfs(T start) {
        if start == null { throw "Graph.bfs: null start" }
        if !_outgoing.has(start) { throw "Graph.bfs: unknown start" }
        List<T> result = []
        Set<T> visited = new Set<T>()
        List<T> queue = []
        queue.push(start)
        visited.add(start)
        Int head = 0
        while head < queue.length() {
            T node = queue.get(head)
            head = head + 1
            result.push(node)
            List<GraphEdge<T>> outgoing = _outgoing.get(node)
            Int index = 0
            while index < outgoing.length() {
                T next = outgoing.get(index).to()
                if !visited.has(next) {
                    visited.add(next)
                    queue.push(next)
                }
                index = index + 1
            }
        }
        return result
    }

    List<T> dfs(T start) {
        if start == null { throw "Graph.dfs: null start" }
        if !_outgoing.has(start) { throw "Graph.dfs: unknown start" }
        List<T> result = []
        Set<T> visited = new Set<T>()
        List<T> stack = []
        stack.push(start)
        while stack.length() > 0 {
            T node = stack.remove(stack.length() - 1)
            if visited.has(node) { continue }
            visited.add(node)
            result.push(node)
            List<GraphEdge<T>> outgoing = _outgoing.get(node)
            Int index = outgoing.length() - 1
            while index >= 0 {
                T next = outgoing.get(index).to()
                if !visited.has(next) { stack.push(next) }
                index = index - 1
            }
        }
        return result
    }

    Bool hasCycle() {
        return self.topologicalOrder().length() != _nodes.length()
    }

    Result<List<T>, Error> topologicalSort() {
        List<T> order = self.topologicalOrder()
        if order.length() != _nodes.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Graph.topologicalSort: graph contains a cycle"))
        }
        return Ok(order)
    }

    private List<T> topologicalOrder() {
        Map<T, Int> indegree = new Map<T, Int>()
        Int index = 0
        while index < _nodes.length() {
            indegree.put(_nodes.get(index), 0)
            index = index + 1
        }
        index = 0
        while index < _edges.length() {
            GraphEdge<T> edge = _edges.get(index)
            indegree.put(edge.to(), indegree.getOr(edge.to(), 0) + 1)
            index = index + 1
        }
        List<T> queue = []
        index = 0
        while index < _nodes.length() {
            T node = _nodes.get(index)
            if indegree.getOr(node, 0) == 0 { queue.push(node) }
            index = index + 1
        }
        List<T> order = []
        Int head = 0
        while head < queue.length() {
            T node = queue.get(head)
            head = head + 1
            order.push(node)
            List<GraphEdge<T>> outgoing = _outgoing.get(node)
            Int edgeIndex = 0
            while edgeIndex < outgoing.length() {
                T next = outgoing.get(edgeIndex).to()
                Int remaining = indegree.getOr(next, 0) - 1
                indegree.put(next, remaining)
                if remaining == 0 { queue.push(next) }
                edgeIndex = edgeIndex + 1
            }
        }
        return order
    }

    Result<List<T>, Error> shortestPath(T source, T target) {
        if source == null || target == null {
            throw "Graph.shortestPath: null endpoint"
        }
        if !_outgoing.has(source) || !_outgoing.has(target) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Graph.shortestPath: unknown endpoint"))
        }
        if source == target {
            List<T> single = []
            single.push(source)
            return Ok(single)
        }
        List<T> discovered = []
        Map<T, Int> nodeIndex = new Map<T, Int>()
        Map<T, Int> parentIndex = new Map<T, Int>()
        Set<T> visited = new Set<T>()
        List<T> queue = []
        discovered.push(source)
        nodeIndex.put(source, 0)
        parentIndex.put(source, -1)
        visited.add(source)
        queue.push(source)
        Int head = 0
        Bool found = false
        while head < queue.length() && !found {
            T node = queue.get(head)
            head = head + 1
            Int currentIndex = nodeIndex.get(node)
            List<GraphEdge<T>> outgoing = _outgoing.get(node)
            Int index = 0
            while index < outgoing.length() && !found {
                T next = outgoing.get(index).to()
                if !visited.has(next) {
                    visited.add(next)
                    parentIndex.put(next, currentIndex)
                    nodeIndex.put(next, discovered.length())
                    discovered.push(next)
                    queue.push(next)
                    if next == target { found = true }
                }
                index = index + 1
            }
        }
        if !found {
            return Err(new BasicError(ErrorKind.NotFound,
                "Graph.shortestPath: no path"))
        }
        List<T> reversed = []
        T cursor = target
        Bool done = false
        while !done {
            reversed.push(cursor)
            Int parent = parentIndex.getOr(cursor, -1)
            if parent < 0 {
                done = true
            } else {
                cursor = discovered.get(parent)
            }
        }
        List<T> path = []
        Int pathIndex = reversed.length() - 1
        while pathIndex >= 0 {
            path.push(reversed.get(pathIndex))
            pathIndex = pathIndex - 1
        }
        return Ok(path)
    }
}
```
