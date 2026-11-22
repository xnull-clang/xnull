# `xdk.collections` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.collections` |
| 层 | `xdk.core` / L2 |
| 依赖 | `xdk.errors` |
| 被依赖 | `text`、`config`、`cli`、`codec`、`net` |
| 稳定性 | 基础容器 `stable`；专用容器 `preview` |
| 文档原则 | 包级说明在本 README；每个类一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.collections` 提供序列、映射、集合、专用容器和算法：

- `List/Map/Set` 语言容器；
- `Deque/Stack/Queue/PriorityQueue/RingBuffer`；
- `OrderedMap/BTreeMap/MultiMap/BiMap/LRUCache`；
- `Pair/Triple/Iterator/IntRange`；
- 排序/查找/变换/分组/组合算法。

不做：并发容器、持久化容器、数据库索引、无锁结构、惰性流。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 引用语义 | 容器是引用类型；`==` 是身份 |
| 快照 | `keys/values/entries/toList` 返回快照 |
| 结构修改 | 遍历期间禁止 push/insert/remove/clear |
| 越界 | unchecked panic；checked 返回 `Result` |
| 缺失 | 用 `tryGet`/`nullable`，不用 0/空串哨兵 |
| 稳定性 | 排序稳定；相等优先级顺序不承诺 |
| 非线程安全 | 并发容器属于 `xdk.execution` |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `List<T>` | 语言容器 | 有序、可重复、索引 | [`List.md`](List.md) |
| `Map<K,V>` | 语言容器 | 键唯一、查找/替换/删除 | [`Map.md`](Map.md) |
| `Set<T>` | 语言容器 | 元素唯一 | [`Set.md`](Set.md) |
| `Deque<T>` | class | 双端队列 | [`Deque.md`](Deque.md) |
| `Stack<T>` | class | 栈 | [`Stack.md`](Stack.md) |
| `Queue<T>` | class | 队列 | [`Queue.md`](Queue.md) |
| `PriorityQueue<T>` | class | 最小堆 | [`PriorityQueue.md`](PriorityQueue.md) |
| `RingBuffer<T>` | class | 固定容量环形缓冲 | [`RingBuffer.md`](RingBuffer.md) |
| `OrderedMap<V>` | class | Int 键插入序 | [`OrderedMap.md`](OrderedMap.md) |
| `BTreeMap<V>` | class | Int 键有序 | [`BTreeMap.md`](BTreeMap.md) |
| `MultiMap<K,V>` | class | 一键多值 | [`MultiMap.md`](MultiMap.md) |
| `BiMap<K,V>` | class | 双向映射 | [`BiMap.md`](BiMap.md) |
| `LRUCache<K,V>` | class | 容量淘汰 | [`LRUCache.md`](LRUCache.md) |
| `Pair` | class | 两元组 | [`Pair.md`](Pair.md) |
| `Entry<K,V>` | class | 通用 Map 条目 | [`Entry.md`](Entry.md) |
| `Triple` | class | 三元组 | [`Triple.md`](Triple.md) |
| `Iterator<T>` | class | 迭代器 | [`Iterator.md`](Iterator.md) |
| `IntRange` | class | 整数区间 | [`IntRange.md`](IntRange.md) |

---

## 4. 算法

### 4.1 排序/查找

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `sort` | 原地排序 | `List<T> items, Int(T,T) compare` | `List<T>` | 无 |
| `stableSort` | 稳定原地排序 | 同上 | `List<T>` | 无 |
| `sortBy` | 比较器排序 | `List<T> items, Bool(T,T) lessThan` | `List<T>` | 无 |
| `sortedBy` | 返回新列表 | 同上 | `List<T>` | 无 |
| `isSortedBy` | 是否已排序 | 同上 | `Bool` | 无 |
| `reverse` | 原地反转 | `List<T> items` | `List<T>` | 无 |
| `shuffle` | 原地洗牌 | `List<T> items, Random random` | `List<T>` | null → panic |
| `binarySearch` | 二分查找 | `List<T> items, T target, Int(T,T) compare` | `Int` | 无 |
| `binarySearchBy` | 比较器二分 | 同上 | `Int` | 无 |
| `lowerBound` | 下界 | `List<T> items, T target, Int(T,T) compare` | `Int` | 无 |
| `upperBound` | 上界 | 同上 | `Int` | 无 |

### 4.2 查询/聚合

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `find` | 首个满足 | `List<T> items, Bool(T) predicate` | `T?` | 无 |
| `findIndex` | 首个下标 | 同上 | `Int?` | 无 |
| `findAll` | 全部满足 | 同上 | `List<T>` | 无 |
| `any` | 任一满足 | 同上 | `Bool` | 无 |
| `all` | 全部满足 | 同上 | `Bool` | 无 |
| `none` | 全部不满足 | 同上 | `Bool` | 无 |
| `countIf` | 满足个数 | 同上 | `Int` | 无 |
| `min` | 最小 | `List<T> items, Int(T,T) compare` | `T?` | 无 |
| `max` | 最大 | 同上 | `T?` | 无 |
| `minBy` | 键最小 | `List<T> items, K(T) keySelector, Int(K,K) compare` | `T?` | 无 |
| `maxBy` | 键最大 | 同上 | `T?` | 无 |

### 4.3 变换

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `map` | 映射 | `List<T> items, U(T) transform` | `List<U>` | 无 |
| `flatMap` | 映射展平 | `List<T> items, List<U>(T) transform` | `List<U>` | 无 |
| `filter` | 过滤 | `List<T> items, Bool(T) predicate` | `List<T>` | 无 |
| `reject` | 反向过滤 | 同上 | `List<T>` | 无 |
| `reduce` | 左折叠 | `List<T> items, T initialValue, T(T,T) combine` | `T` | 无 |
| `fold` | 左折叠（异类型） | `List<T> items, U initialValue, U(U,T) combine` | `U` | 无 |
| `scan` | 前缀折叠 | `List<T> items, T initialValue, T(T,T) combine` | `List<T>` | 无 |
| `dedup` | 比较器去重 | `List<T> items, Bool(T,T) equals` | `List<T>` | 无 |
| `distinct` | 键去重 | `List<T> items, K(T) keySelector` | `List<T>` | 无 |
| `partition` | 分组 | `List<T> items, Bool(T) predicate` | `Pair<List<T>,List<T>>` | 无 |
| `chunk` | 分块 | `List<T> items, Int chunkSize` | `List<List<T>>` | ≤0 → panic |
| `window` | 滑动窗口 | `List<T> items, Int windowSize` | `List<List<T>>` | ≤0 → panic |
| `zip` | 拉链 | `List<A> left, List<B> right` | `List<Pair<A,B>>` | 无 |
| `unzip` | 解拉链 | `List<Pair<A,B>> pairs` | `Pair<List<A>,List<B>>` | 无 |
| `flattenList` | 展平一层 | `List<List<T>> nestedItems` | `List<T>` | 无 |
| `join` | 字符串拼接 | `List<String> items, String separator` | `String` | 无 |
| `joinWith` | 泛型格式化拼接 | `List<T> items, String separator, String(T) format` | `String` | null → panic |

### 4.4 集合/分组/组合

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `union` | 并集 | `List<T> left, List<T> right, Bool(T,T) equals` | `List<T>` | 无 |
| `intersection` | 交集 | 同上 | `List<T>` | 无 |
| `difference` | 差集 | 同上 | `List<T>` | 无 |
| `frequency` | 频次 | `List<T> items, K(T) keySelector` | `Map<K,Int>` | 无 |
| `topK` | 前 K | `List<T> items, Int k, Int(T,T) compare` | `List<T>` | k<0 → panic |
| `groupBy` | 分组 | `List<T> items, K(T) keySelector` | `Map<K,List<T>>` | 无 |
| `groupByInt` | Int 键分组 | `List<T> items, Int(T) keySelector` | `Map<Int,List<T>>` | 无 |
| `permutations` | 排列 | `List<T> items` | `List<List<T>>` | 无 |
| `combinations` | 组合 | `List<T> items, Int k` | `List<List<T>>` | k<0 → panic |
| `cartesianProduct` | 笛卡尔积 | `List<List<T>> groups` | `List<List<T>>` | 无 |

---

## 5. 关键算法伪代码

### 5.1 `sortBy`

```xnull
List<T> sortBy<T>(List<T> items, Bool(T, T) lessThan) {
    Int index = 1
    while index < items.length() {
        T value = items.get(index)
        Int previous = index - 1
        while previous >= 0 {
            if lessThan(value, items.get(previous)) {
                items.set(previous + 1, items.get(previous))
                previous = previous - 1
            } else {
                break
            }
        }
        items.set(previous + 1, value)
        index = index + 1
    }
    return items
}
```

### 5.2 `binarySearchBy`

```xnull
Int binarySearchBy<T>(List<T> items, T target, Int(T, T) compare) {
    Int low = 0
    Int high = items.length() - 1
    while low <= high {
        Int middle = low + (high - low) / 2
        Int order = compare(items.get(middle), target)
        if order < 0 {
            low = middle + 1
        } else if order > 0 {
            high = middle - 1
        } else {
            return middle
        }
    }
    return 0 - (low + 1)
}
```

### 5.3 `groupBy`

```xnull
Map<K, List<T>> groupBy<T, K>(List<T> items, K(T) keySelector) {
    Map<K, List<T>> result = [:]
    Int index = 0
    while index < items.length() {
        T item = items.get(index)
        K key = keySelector(item)
        if !result.has(key) {
            result.put(key, [])
        }
        result.getOr(key, []).push(item)
        index = index + 1
    }
    return result
}
```

### 5.4 `chunk`

```xnull
List<List<T>> chunk<T>(List<T> items, Int chunkSize) {
    if chunkSize <= 0 {
        throw "chunk: non-positive size"
    }
    List<List<T>> result = []
    Int index = 0
    while index < items.length() {
        List<T> part = []
        Int end = index + chunkSize
        if end > items.length() { end = items.length() }
        while index < end {
            part.push(items.get(index))
            index = index + 1
        }
        result.push(part)
    }
    return result
}
```

---

## 6. 场景

### C1：数据清洗/聚合

`filter`/`map`/`dedup`/`groupBy`/`topK`；空列表/边界；不修改入参（除原地排序明确标注）。

### C2：路由/配置表

`Map<String,String>`、`keys/values/entries` 快照；缺失用 `tryGet`，不用空串哨兵。

### C3：优先级任务

`PriorityQueue<Job>`；比较器严格弱序；空堆 peek/pop 返回 null。

### C4：环形日志缓冲

`RingBuffer<String>`；满时 push false，不覆盖；drain 取快照。

### C5：LRU 缓存

`LRUCache<K,V>`；命中/淘汰/容量；stats。

### C6：协议字段列表

`List<Bytes>`/`IntRange`/`Iterator`；按索引/迭代；结构修改禁止。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 通用 `Map.entries` 值对象 | `Map<String,Int>` → `Pair<String,Int>`；`Map<Int,Int>` → `IntPair`；其余受支持 K/V → `Entry<K,V>`；三者都是值对象 |
| `groupBy` 泛型 Map 值 | X； 先 `groupByInt`/专用 |
| 并发容器 | `xdk.execution`；本包非线程安全 |
| 持久化/B 树复杂度 | `BTreeMap` 首版有序数组，O(n) 插入 |
| 迭代器协议 | `Iterator<T>` 是 class；不是泛型 protocol |
| 排序复杂度 | 首版稳定插入排序 O(n²)；后续可替换 |
| `Pair/Triple` 值语义 | class + 访问器方法（`first()/second()`）；按约定值语义 |
| 空值 | 用 nullable；不支持“存 null”作为合法值 |

## 9. 1.x 兼容合同（C7）

1.x 已实现、2.x 必须保留的集合面：

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `joinWith<T>(List<T> items, String separator, String(T) format)` | 顶层 `joinWith`；空列表 → `""`；`format` 为 null → panic | 不修改入参；O(n) |
| `Entry<K,V>`（公共 `key`/`value` 字段） | [`Entry.md`](Entry.md)；`key()`/`value()` 访问器；通用 `Map.entries()` 返回 `List<Entry<K,V>>` | 1.x 字段访问迁移到访问器；`Map<String,Int>`/`Map<Int,Int>` 仍返回 `Pair`/`IntPair` |
| 1.x 固定 `Pair`（`String first`/`Int second` 公共字段） | [`Pair.md`](Pair.md) 的 `Pair<A,B>` 泛型值对象；`Map<String,Int>.entries()` 返回 `Pair<String,Int>` | 公共字段迁移到 `first()`/`second()`；不保留同名第二类 |
| `Map.put` 1.x 旧值返回 | 2.x `Map.put` 冻结返回 `Bool`（替换 true、插入 false）；删除旧值用 `removeOr`，缺失读用 `tryGet`/`getOr` | 1.x t0 同时存在 `Bool put` 与 `Int? put` 证据；以 2.x `Bool` 为准；`OrderedMap/BTreeMap` 保持 `V?` 旧值返回 |

示例：

```xnull
String joined = joinWith(names, ",", (String name) -> name.toUpper())
Entry<String, Bool> entry = flags.entries().get(0)
String key = entry.key()
```

测试义务：`joinWith` 空/单元素/多元素/null formatter；`Entry` 构造/访问器/with*/equals；三种 `entries()` 返回形状；`Map.put` 的 true/false 与旧值迁移路径；`Pair` 固定字段迁移示例。
