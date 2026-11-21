# `xdk.graph` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.graph` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.collections`（`List`/`Set`/`Map`） |
| 被依赖 | 应用、构建工具、调度、依赖解析 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

进程内、单线程使用的有向简单图：节点/边增删、邻接查询、BFS/DFS、环检测、拓扑排序、无权最短路径。

不做：并发安全（调用方加锁）、平行边、无向图、超图、持久化、全局图注册表、加权最短路径（Dijkstra，X）、最大流、最小生成树、A*。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 实例隔离 | 无全局注册表；图状态只在实例内 |
| 确定性 | 节点/边保持插入顺序；遍历与算法结果稳定 |
| 简单图 | 同一有序端点对至多一条边；自环允许 |
| 不可变边 | `GraphEdge` 构造后只读，可跨任务共享 |
| 显式失败 | 构造/变更合同错误 → panic；算法语义失败 → `Result` |
| 非线程安全 | 无内部锁；跨任务共享需外部同步 |
| 不复制 core | 复用 `List`/`Set`/`Map`/`Error`，不新建容器或错误类型 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `GraphEdge` | `class GraphEdge<T>` | 不可变有向加权边 | [`GraphEdge.md`](GraphEdge.md) |
| `Graph` | `class Graph<T>` | 节点/边/遍历/环/拓扑/最短路径 | [`Graph.md`](Graph.md) |

X：Dijkstra 与加权最短路、A*、最大流、最小生成树、无向图/多重图、并发图。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：邻接表、BFS 队列、迭代 DFS、Kahn 入度、父节点索引回溯、防御性复制。
- 支撑：`List`、`Set`、`Map`、`Result`、`Error`、`BasicError`、`ErrorKind`、`str`、`isNaN`、`isInf`。
- 依赖：`xdk.errors`、`xdk.collections`。
- 明确不依赖：`xdk.event`、`xdk.reflect`、`xdk.log`；不建全局图注册表；不重复 core 容器/错误类型。

---

## 6. 场景

### G1：依赖排序

构建任务先 `addNode`，再 `addEdge(new GraphEdge<String>("compile", "link", 1.0))`；`topologicalSort()` 得到确定性构建顺序；有环返回 `InvalidArgument`。

### G2：可达性

`bfs("root")` / `dfs("root")` 返回从起点可达的节点；未连通节点不出现；起点只出现一次。

### G3：环检测

`hasCycle()` 对自环和任意有向环返回 `true`；DAG 与空图返回 `false`。

### G4：无权路由

`shortestPath(a, b)` 按边数最少返回包含端点的路径；`weight` 不参与；不可达返回 `NotFound`。

### G5：生命周期

图随作用域结束被回收；`removeNode` 级联删除入射/出射边；无 `close`、无后台任务。

### G6：并发边界

图本身不加锁；跨任务访问时由调用方用 `Mutex`/`RwLock` 保护，或先取 `nodes()`/`edges()` 快照。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 加权最短路径 | X（Dijkstra）；当前 `shortestPath` 忽略 `weight` |
| 线程安全 | 不提供；外部 `Mutex`/`RwLock` |
| 平行边 | 不支持；同一有序端点对唯一 |
| 无向图/多重图 | X |
| 自环 | 允许；计为环 |
| 节点相等 | 遵循 `T` 的 `==`；class 默认引用相等，值语义由节点类型定义 |
| 重复节点/边 | `addNode` 幂等；`addEdge` 拒绝重复有序端点对 |
| 未知节点 | `removeNode`/`removeEdge` 无操作；`neighbors`/`bfs`/`dfs` panic；`hasNode`/`hasEdge` 返回 `false` |
| 全局图注册表 | 禁止 |
| 持久化/序列化 | 不做 |
| 递归 DFS | 不用；迭代实现避免深图栈溢出 |
