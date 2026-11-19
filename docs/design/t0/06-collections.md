# xdk.collections —— T0 核心包详细设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.collections` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`（T0-K）；扩展 `preview`（T0-X） |
| 依赖 | `xdk.errors` |
| 被依赖 | 所有业务包、text/codec/config/cli |
| 对应源码 | `src/xdk/core/collections/*.x` |
| 阶段 | T0-06（C1–C4） |

---

## 1. 能力声明

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| C1 序列 | 有序、可重复、按索引访问 | `List<T>` |
| C2 映射 | 键唯一、按键查找 | `Map<K,V>` |
| C3 集合 | 元素唯一、成员判断 | `Set<T>` |
| C4 迭代 | 统一遍历协议与适配器 | `Iterator<T>`、`Iterable<T>` |
| C5 排序/查找 | 比较器驱动的排序、二分查找 | `sortBy`、`binarySearch` |
| C6 聚合 | dedup/find/group/partition/chunks/windows | 算法族 |
| C7 专用容器 | 堆、双端队列、环形缓冲、位集、有序映射 | `PriorityQueue`、`Deque`、`RingBuffer`、`BitSet`、`TreeMap` |

**非目标**：并发容器（sync）、持久化容器、数据库索引、无锁结构承诺。

---

## 2. 内建容器 vs 库容器

### 2.1 内建容器（语言/运行时）

`List<T>`、`Map<K,V>`、`Set<T>` 是语言字面量与 `for-in` 的脱糖目标；
编译器只识别形状，不维护成员表。库负责成员语义与算法。

| 类型 | 字面量 | 语义 | T0-K 成员 |
| --- | --- | --- | --- |
| `List<T>` | `[a, b]` | 有序、可重复、可变 | `length/get/set/push/insert/remove/clear/join` |
| `Map<K,V>` | `[k: v]` | 键唯一；`getOr` 不插入 | `length/has/get/getOr/put/remove/keys/values/entries/clear` |
| `Set<T>` | `Set.of(...)` | 元素唯一 | `length/has/add/remove/clear` |

**硬前置**：当前运行时只支持 `Map<String,Int>`；`Map<K,V>` 泛型化是 T0-06 的
第一阻塞项。未完成前，`groupBy`、`TreeMap<K,V>`、`HashMap<K,V>` 只能设计、
不能宣称可用。

### 2.2 库容器

| 类型 | 语义 | 复杂度目标 | 层级 |
| --- | --- | --- | --- |
| `HashMap<K,V>` | 哈希映射；迭代序不保证 | 均摊 O(1) 查找/插入 | X |
| `TreeMap<K,V>` | 比较器有序映射 | O(log n) | X |
| `LinkedHashMap<K,V>` | 插入序映射 | 均摊 O(1) | X |
| `Deque<T>` | 双端队列/栈 | 摊还 O(1) 两端 | X |
| `PriorityQueue<T>` | 最小堆 | O(log n) push/pop | K（已有源码） |
| `RingBuffer<T>` | 固定容量环形缓冲 | O(1) | K（已有源码） |
| `BitSet` | 位集合 | O(n/64) 集合运算 | X |

---

## 3. `Iterator<T>` / `Iterable<T>`（protocol，T0-K）

### 3.1 能力

把“遍历”从具体容器中解耦；`for-in` 的脱糖目标。

```text
protocol Iterator<T> {
    Bool hasNext()
    T next()
}

protocol Iterable<T> {
    Iterator<T> iterator()
}
```

### 3.2 契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `hasNext` | 迭代器未耗尽 | 不改变状态；返回是否还有元素 | 无 | O(1) |
| `next` | `hasNext() == true` | 返回当前元素并前进；**不得**在 false 时调用 | 合同错误（fatal 或 `Unavailable`，固定） | O(1) 摊还 |
| `iterator` | 无 | 返回新迭代器；不修改容器 | 无 | O(1) |

### 3.3 适配器（T0-X）

| 适配器 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `map` | `Iterator<U> map<T,U>(Iterator<T>, U(T))` | 惰性映射 | f 抛错由语言边界处理 |
| `filter` | `Iterator<T> filter<T>(Iterator<T>, Bool(T))` | 惰性过滤 | 无 |
| `take` | `Iterator<T> take<T>(Iterator<T>, Int n)` | 最多 n 个；n<0 → 空 | 无 |
| `drop` | `Iterator<T> drop<T>(Iterator<T>, Int n)` | 跳过 n 个 | 无 |
| `chain` | `Iterator<T> chain<T>(Iterator<T>, Iterator<T>)` | 顺序连接 | 无 |
| `zip` | `Iterator<Pair<A,B>> zip<A,B>(Iterator<A>, Iterator<B>)` | 取到较短者结束 | 无 |
| `enumerate` | `Iterator<Indexed<T>> enumerate<T>(Iterator<T>)` | 附带下标 | 无 |

- 适配器不缓存整个序列；`take/drop` 只消费必要元素。
- 适配器返回的迭代器持有上游引用；上游生命周期由调用方保证。
- `Pair<A,B>`/`Indexed<T>` 是值 struct；不持有资源。

### 3.4 示例

```text
List<Int> xs = [1, 2, 3]
Iterator<Int> it = xs.iterator()
while it.hasNext() {
    print(it.next())
}
```

反例：`hasNext()` 为 false 时继续 `next()`；在迭代过程中修改 `List`
（结构性修改）而未重新获取迭代器。

---

## 4. `List<T>`（内建，T0-K 契约）

### 4.1 不变量

- 元素有序、可重复；索引 `[0, length-1]`。
- 结构性修改（push/insert/remove/clear）使既有迭代器失效；失效后使用是合同错误。
- 元素所有权：容器持有元素引用；`remove` 返回被移除元素（所有权转移）。

### 4.2 成员契约

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 元素数 | 无 | O(1) |
| `get` | `T get(Int i)` | `0<=i<len` | 返回元素借用 | 越界合同错误 | O(1) |
| `tryGet` | `Result<T, Error> tryGet(Int i)` | 无 | 越界 `InvalidArgument` | `InvalidArgument` | O(1) |
| `set` | `Void set(Int i, T v)` | `0<=i<len` | 替换；旧值引用释放 | 越界合同错误 | O(1) |
| `push` | `Void push(T v)` | 无 | 末尾追加；长度 +1 | 无 | 摊还 O(1) |
| `insert` | `Void insert(Int i, T v)` | `0<=i<=len` | 插入；后续右移 | 越界 `InvalidArgument` | O(n) |
| `remove` | `T remove(Int i)` | `0<=i<len` | 删除并返回元素；长度 -1 | 越界合同错误 | O(n) |
| `clear` | `Void clear()` | 无 | 长度 0；容量可保留 | 无 | O(n) |
| `join` | `String join(String sep)` | 元素可转文本 | 拼接 | 无 | O(n) |

> `List<T>` 是引用语义；`==` 不定义值相等。需要比较时用 `equals` 算法
> （逐元素 eq）。

---

## 5. `Map<K,V>`（内建，T0-K 契约）

### 5.1 不变量

- 一个键至多一个值；键相等由 `K` 的相等语义决定（首版 `String`/`Int` 等标量）。
- 迭代顺序：内建 Map 不承诺；需要顺序用 `LinkedHashMap`/`TreeMap`。
- `put` 对已存在键替换值；返回旧值（所有权转移）或 `Void`（固定为返回旧值？见下）。

### 5.2 成员契约

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 键数 | 无 | O(1) |
| `has` | `Bool has(K)` | K 可哈希/相等 | 是否存在 | 无 | 均摊 O(1) |
| `getOr` | `V getOr(K, V fallback)` | 同上 | 存在 → 值；否则 fallback；**不插入** | 无 | 均摊 O(1) |
| `tryGet` | `Result<V, Error> tryGet(K)` | 同上 | 缺失 → `NotFound` | `NotFound` | 均摊 O(1) |
| `put` | `V? put(K, V)` | 同上 | 插入/替换；返回旧值（无则 null） | 无 | 均摊 O(1) |
| `remove` | `V? remove(K)` | 同上 | 删除并返回旧值 | 无 | 均摊 O(1) |
| `keys` | `List<K> keys()` | 无 | 快照；顺序不承诺 | 无 | O(n) |
| `values` | `List<V> values()` | 无 | 快照 | 无 | O(n) |
| `entries` | `List<Pair<K,V>> entries()` | 无 | 快照 | 无 | O(n) |
| `clear` | `Void clear()` | 无 | 清空 | 无 | O(n) |

> `put/remove` 返回 `V?` 使用可选引用；若 legacy/目标引擎对可选引用支持不足，
> T0-K 改为 `Result<V, Error>`（缺失 `NotFound`）或 `Void` + `has` 先查。
> 该决策在 C1 阶段冻结，不允许两套语义并存。

### 5.3 键的要求

- 键必须支持相等比较；哈希容器还要求哈希一致（相等键同哈希）。
- 禁止使用可变对象作键（修改后哈希变化会破坏容器）。
- 浮点 `NaN` 不得作键（不满足自反相等）。

---

## 6. `Set<T>`（内建，T0-K 契约）

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 元素数 | 无 | O(1) |
| `has` | `Bool has(T)` | T 可哈希/相等 | 是否存在 | 无 | 均摊 O(1) |
| `add` | `Bool add(T)` | 同上 | 新增 → true；已存在 → false | 无 | 均摊 O(1) |
| `remove` | `Bool remove(T)` | 同上 | 删除 → true；不存在 → false | 无 | 均摊 O(1) |
| `clear` | `Void clear()` | 无 | 清空 | 无 | O(n) |

- 迭代顺序不承诺；需要顺序用有序结构或先排序。
- `Set.of(a,b)` 由编译器脱糖；重复元素语义固定为“后者忽略”。

---

## 7. 算法（T0-K / T0-X）

### 7.1 排序

| 函数 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `sortBy` | `List<T> sortBy<T>(List<T>, Bool(T,T) less)` | less 为严格弱序 | 返回新列表；稳定 | 无 | O(n²) 首版 |
| `sortInPlaceBy` | `List<T> sortInPlaceBy<T>(List<T>, Bool(T,T) less)` | 同上 | 原地排序；返回同一列表 | 无 | O(n²) 首版 |
| `isSortedBy` | `Bool isSortedBy<T>(List<T>, Bool(T,T) less)` | 同上 | 是否已排序 | 无 | O(n) |
| `binarySearchBy` | `Int binarySearchBy<T>(List<T>, T value, Int(T,T) cmp)` | 列表已按 cmp 排序 | 找到返回索引；否则返回 `-(插入点+1)` | 无 | O(log n) |

- 比较器必须是纯函数且满足严格弱序；违反导致未定义顺序（文档警告）。
- 稳定性：`sortBy` 稳定；`sortInPlaceBy` 也稳定（首版插入排序天然稳定）。

### 7.2 查找/去重/聚合

| 函数 | 签名 | 语义 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `find` | `T? find<T>(List<T>, Bool(T))` | 首个满足；无则 null | 无 | O(n) |
| `findIndex` | `Int? findIndex<T>(List<T>, Bool(T))` | 首个下标；无则 null | 无 | O(n) |
| `dedup` | `List<T> dedup<T>(List<T>, Bool(T,T) eq)` | 保序去重 | 无 | O(n²) |
| `any` | `Bool any<T>(List<T>, Bool(T))` | 任一满足 | 无 | O(n) |
| `all` | `Bool all<T>(List<T>, Bool(T))` | 全部满足 | 无 | O(n) |
| `count` | `Int count<T>(List<T>, Bool(T))` | 满足个数 | 无 | O(n) |
| `reduce` | `T reduce<T>(List<T>, T init, T(T,T) f)` | 左折叠 | f 抛错由语言边界 | O(n) |
| `partition` | `Pair<List<T>,List<T>> partition<T>(List<T>, Bool(T))` | 满足/不满足两组，保序 | 无 | O(n) |
| `chunks` | `List<List<T>> chunks<T>(List<T>, Int size)` | 每块 size；末块可短 | size<=0 → `InvalidArgument` | O(n) |
| `windows` | `List<List<T>> windows<T>(List<T>, Int size)` | 滑动窗口 | size<=0 → `InvalidArgument` | O(n) |
| `zip` | `List<Pair<A,B>> zip<A,B>(List<A>, List<B>)` | 取较短长度 | 无 | O(min) |
| `flatten` | `List<T> flatten<T>(List<List<T>>)` | 展平一层 | 无 | O(n) |
| `groupByInt` | `Map<Int,List<T>> groupByInt<T>(List<T>, Int(T))` | 按 Int 键分组，保序 | 依赖 Map<Int,...> | O(n) |
| `groupBy` | `Map<K,List<T>> groupBy<T,K>(List<T>, K(T) key)` | 泛型键分组 | 依赖 Map<K,...> | O(n) |

### 7.3 `Pair` / `Indexed`

```text
struct Pair<A, B> { A first; B second }
struct Indexed<T> { Int index; T value }
```

- 值语义；可比较字段；不持有资源。
- `Pair` 作为 `zip` 返回；`Indexed` 作为 `enumerate` 返回。

---

## 8. 专用容器

### 8.1 `PriorityQueue<T>`（T0-K，已有源码）

```text
class PriorityQueue<T> {
    PriorityQueue(Bool(T,T) less)
    Int length()
    Bool isEmpty()
    Void push(T)
    T? peek()
    T? pop()
    Void clear()
}
```

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `push` | less 严格弱序 | 插入并上浮 | 无 | O(log n) |
| `peek` | 无 | 返回堆顶借用；空 → null | 无 | O(1) |
| `pop` | 无 | 移除并返回堆顶；空 → null | 无 | O(log n) |
| `clear` | 无 | 清空 | 无 | O(n) |

- 不稳定；相等优先级顺序不承诺。
- `less` 由调用方持有；不得在队列生命周期内改变语义。

### 8.2 `RingBuffer<T>`（T0-K，已有源码）

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `push` | `Bool push(T)` | 无 | 未满 → 写入 true；满 → 覆盖最旧并 true？**固定：满返回 false 不写入** | 无 | O(1) |
| `pop` | `T? pop()` | 无 | 非空 → 取出；空 → null | 无 | O(1) |
| `peek` | `T? peek()` | 无 | 非空 → 返回最旧；空 → null | 无 | O(1) |
| `isFull`/`isEmpty` | `Bool` | 无 | 状态 | 无 | O(1) |
| `capacity`/`length` | `Int` | 无 | 容量/元素数 | 无 | O(1) |
| `clear` | `Void` | 无 | 清空 | 无 | O(n) |

> 满时行为必须固定；当前设计选择“返回 false 不覆盖”，需要改实现/文档一致。

### 8.3 `Deque<T>`（T0-X）

```text
class Deque<T> {
    Deque()
    Int length()
    Bool isEmpty()
    Void pushFront(T) / pushBack(T)
    T? popFront() / popBack()
    T? peekFront() / peekBack()
    Void clear()
}
```

- 两端 O(1) 摊还；空 pop/peek → null。
- 可作为栈（pushBack/popBack）或队列（pushBack/popFront）。

### 8.4 `HashMap<K,V>` / `TreeMap<K,V>`（T0-X）

```text
class HashMap<K,V> {
    HashMap(Int(K) hash, Bool(K,K) eq)
    Int length()
    Bool has(K)
    V? get(K)
    V? put(K, V)
    V? remove(K)
    List<K> keys()
    void clear()
}

class TreeMap<K,V> {
    TreeMap(Int(K,K) compare)
    ... 同 HashMap + firstKey/lastKey/range ...
}
```

- `HashMap` 的 hash/eq 必须一致；`TreeMap` 的 compare 必须严格弱序。
- 迭代顺序：HashMap 不承诺；TreeMap 按 compare 升序。
- 复杂度：HashMap 均摊 O(1)；TreeMap O(log n)。

### 8.5 `BitSet`（T0-X）

| 方法 | 签名 | 语义 | 复杂度 |
| --- | --- | --- | --- |
| `set` | `Void set(Int i)` | 置位；自动扩容 | O(1) 摊还 |
| `clearBit` | `Void clearBit(Int i)` | 清位 | O(1) |
| `get` | `Bool get(Int i)` | 越界 false | O(1) |
| `length` | `Int length()` | 最高置位+1 | O(1) |
| `count` | `Int count()` | 置位数 | O(n/64) |
| `and/or/xor` | `BitSet op(BitSet)` | 位集合运算 | O(n/64) |

- 负索引是合同错误；越界读取返回 false，越界写自动扩容。

---

## 9. 所有权、并发、错误

| 项 | 契约 |
| --- | --- |
| 容器所有权 | 容器持有元素引用；`remove/pop` 转移所有权 |
| 迭代器 | 借用容器；结构性修改使其失效 |
| 线程安全 | 全部非线程安全；并发容器属于 `xdk.sync` |
| 错误分类 | 越界/非法 size → `InvalidArgument`；缺失键严格读取 → `NotFound` |
| 取消 | 算法是纯内存操作，不接受 `Context`；长循环由调用方检查 |

---

## 10. 示例、反例与测试义务

### 10.1 示例

```text
List<Int> xs = [3, 1, 2]
List<Int> sorted = sortBy(xs, (Int a, Int b) -> a < b)
Int idx = binarySearchBy(sorted, 2, (Int a, Int b) -> a - b)

Map<String, Int> m = [:]
m.put("a", 1)
Int v = m.getOr("a", 0)

List<Int> part = chunks(xs, 2).get(0)
```

### 10.2 反例

- 用可变对象作 Map 键；
- `less` 不满足严格弱序（如 `<=`）导致排序不稳定/越界；
- 迭代 List 时 `push/remove`；
- 依赖 Map 的迭代顺序；
- `chunks(xs, 0)` 未校验。

### 10.3 测试义务

| 类别 | 断言 |
| --- | --- |
| 序列 | 空/单元素/重复/越界/插入删除 |
| 映射 | 覆盖 put、缺失 getOr/tryGet、删除、键唯一 |
| 集合 | 重复 add、remove、空集 |
| 迭代 | hasNext/next 边界、适配器惰性 |
| 算法 | 稳定性、空列表、单元素、比较器异常 |
| 容器 | 堆序、环形满/空、Deque 两端、BitSet 边界 |
| 差分 | mini + legacy；Map<K,V> 未完成前记录缺口 |

---

## 11. 阶段切片（T0-06）

| 切片 | 交付 | 出口 |
| --- | --- | --- |
| C1 | `List/Map/Set` 成员契约 + `Map<K,V>` 运行时决策 | 现有 Map 字面量不回归 |
| C2 | `Iterator/Iterable` + `for-in` 脱糖对齐 | 迭代场景 |
| C3 | 算法族（sort/search/reduce/group/partition/chunks） | 算法场景 |
| C4 | HashMap/Deque/BitSet/TreeMap | T0-X 完成 |

---

## 12. 开放问题

1. `Map<K,V>` 泛型运行时是最大阻塞；C1 必须先决策（哈希表 vs 特化）。
2. `put/remove` 返回 `V?` 与可选引用支持冲突；备选 `Result<V,Error>`。
3. `for-in` 脱糖是否固定为 `iterator()/hasNext()/next()`；需编译器确认。
4. `sortBy` 首版 O(n²)；是否在 T0-X 换归并排序（稳定性保持）。
5. 容器相等/哈希协议是否进入语言层；否则 HashMap 只能注入 hash/eq。
6. `chunks/windows` 返回 `List<List<T>>` 会复制；是否需要惰性视图。
