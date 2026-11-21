# xdk.collections —— T0 核心包详细设计 v1.5

> 本版把“迭代器协议”继续排除在 T0-K 外：S2 禁止泛型协议，S1 的 `for-in`
> 由编译器按容器展开。mini 运行时保留 `Map<String,Int>`、`Map<Int,Int>`、
> `Set<Int>`、`Set<String>` 四个快速路径，同时提供通用 `Map<K,V>`/`Set<T>`
> 核心运行时。`Map.entries` 对任意受支持 K/V 返回 `Entry<K,V>` 值对象。
> 设计只承诺现在能验收的能力，不用空实现冒充。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.collections` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`（T0-K）；扩展 `preview`（T0-X） |
| 依赖 | `xdk.errors` |
| 被依赖 | 业务包、text/codec/config/cli |
| 对应源码 | `src/xdk/core/collections/*.x` |
| 阶段 | T0-06（一个包一个验收门；批内条目不单独提交） |
| 当前状态 | Verified：T0-K、通用 Map/Set 核心、任意 K/V entries、groupBy/groupByInt、OrderedMap/BTreeMap、joinWith 均已实现并通过门禁 |

---

## 1. 能力声明

| 能力 | 说明 | 承载 | 层级 |
| --- | --- | --- | --- |
| CAP-1 序列 | 有序、可重复、按索引访问 | `List<T>` | K |
| CAP-2 映射 | 键唯一、查找/替换/删除/快照 | 四个实例 + 通用 `Map<K,V>` 核心 | K |
| CAP-3 集合 | 元素唯一、成员判断 | 四个实例 + 通用 `Set<T>` 核心 | K |
| CAP-4 排序/查找 | 比较器驱动的排序、二分查找 | `sortBy`、`binarySearchBy` | K |
| CAP-5 聚合 | 查找、去重、分组、切块、窗口 | 算法族 | K |
| CAP-6 专用容器 | 堆、环形缓冲、插入序映射、有序映射 | `PriorityQueue`、`RingBuffer`、`OrderedMap`、`BTreeMap` | K |
| CAP-7 迭代 | `for-in` 遍历数组、List、Set | 编译器展开 | K |

**非目标**：

- 不提供通用 `Iterator<T>` / `Iterable<T>` 抽象，不提供 `map/filter/take/drop` 等惰性适配器；
- 不做并发容器（属于 `xdk.sync`）；
- 不做持久化容器、数据库索引、无锁结构。

---

## 2. 容器分层

### 2.1 语言容器

`List<T>`、`Map<K,V>`、`Set<T>` 是第 6 部分的库类型，不是编译器内建成员表；
编译器只识别字面量与 `for-in` 的形状（S1 §2.3、§6.7、§7.9）。

| 类型 | 字面量 | 语义 | T0-K 可用实例 |
| --- | --- | --- | --- |
| `List<T>` | `[a, b]` | 有序、可重复、可变 | `List<Int>`、`List<String>` |
| `Map<K,V>` | `[key: value]` | 键唯一；`getOr` 不插入 | 四个快速路径 + 通用核心 |
| `Set<T>` | `Set.of(...)` | 元素唯一 | 四个快速路径 + 通用核心 |

**运行时边界（冻结）**：

- `Map<String,Int>`、`Map<Int,Int>` 保留专用运行时；其他 K/V 组合走通用
  `xn_map_g`，支持标量、`String`、`Double`、`Bytes`、class、协议、data enum
  以及 `List/Map/Set` 容器值（按引用身份）。不支持的键/值类型（`Int128`、
  `Result` 等）由编译器明确拒绝。
- `Set<Int>`、`Set<String>` 保留专用运行时；其他元素类型走通用 `xn_set_g`，
  支持的类型同上（不含容器元素）。
- `Map.entries` 对 `Map<String,Int>` 返回 `List<Pair>`，对 `Map<Int,Int>` 返回
  `List<IntPair>`，其余受支持 K/V 返回 `List<Entry<K,V>>`；快照语义一致。
- `List<T>` 在 T0-K 覆盖 `Int`、`String`；其他元素类型由编译器和运行时能力决定，
  未验证前不得宣称。

### 2.2 XDK 容器

| 类型 | 语义 | 复杂度目标 | 层级 |
| --- | --- | --- | --- |
| `PriorityQueue<T>` | 最小堆 | push/pop O(log n) | K |
| `RingBuffer<T>` | 固定容量环形缓冲 | 两端 O(1) | K |
| `OrderedMap<V>` | `Int` 键、插入序映射 | 查找 O(n)，插入 O(n) | K |
| `BTreeMap<V>` | `Int` 键、键升序映射 | 查找 O(log n)，插入 O(n) | K |

**命名冻结**：T0 不使用 `HashMap`、`TreeMap`、`LinkedHashMap`、`Deque`、`BitSet`
这些名字。它们要么需要泛型 Map/Set 运行时，要么没有场景；归入 T1/backlog，
不在本包承诺。

---

## 3. 迭代（T0 范围）

### 3.1 决策

- `for item in source` 只遍历 `T[]`、`List<T>`、`Set<T>`；
  `Map` 不直接可迭代，先取 `keys()` 或 `values()`（S1 §6.7）。
- `for-in` 由编译器按容器类型展开，不调用库的 `iterator()`。
- T0 **不提供** `Iterator<T>`、`Iterable<T>` 协议/类，也不提供惰性适配器。
  这是为了避免依赖 S2 禁止的泛型协议，并保持与 mini 当前实现一致。
- 用户自定义可迭代类型、通用迭代器和适配器属于后续语言扩展，不在本包设计范围。

### 3.2 手写循环

需要下标时使用 `List.length()` + `List.get(Int index)`；需要提前结束时使用
`break`/`continue`。遍历期间对容器做结构性修改是合同错误：

| 操作 | 规则 |
| --- | --- |
| 遍历期间 `push/insert/remove/clear` | 禁止；结果不保证，不承诺检测 |
| 遍历期间 `set` 替换元素 | 允许；当前轮已取出的值不受影响 |
| `Map` 遍历 | 不支持；先取 `keys()` 或 `values()` 快照 |

---

## 4. `List<T>`（语言容器，T0-K）

### 4.1 不变量

- 元素有序、可重复；索引合法域 `[0, length-1]`。
- 结构性修改使既有遍历失效；失效后继续遍历是合同错误。
- 容器持有元素引用；`remove` 返回被移除元素（所有权转移）。
- `List<T>` 是引用类型；`==` 是引用身份，不是逐元素相等。

### 4.2 成员契约

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 元素数 | 无 | O(1) |
| `get` | `T get(Int index)` | `0 <= index < length` | 返回元素借用 | 越界为合同错误（panic） | O(1) |
| `tryGet` | `Result<T, Error> tryGet(Int index)` | 无 | 合法返回 `Ok`；越界 `InvalidArgument` | `InvalidArgument` | O(1) |
| `set` | `Void set(Int index, T value)` | `0 <= index < length` | 替换元素 | 越界为合同错误（panic） | O(1) |
| `trySet` | `Result<Unit, Error> trySet(Int index, T value)` | 无 | 合法写入；越界 `InvalidArgument` | `InvalidArgument` | O(1) |
| `push` | `Void push(T value)` | 无 | 末尾追加；长度 +1 | 无 | 摊还 O(1) |
| `insert` | `Void insert(Int index, T value)` | `0 <= index <= length` | 插入；后续右移 | 越界为合同错误（panic） | O(n) |
| `tryInsert` | `Result<Unit, Error> tryInsert(Int index, T value)` | 无 | 合法插入；越界 `InvalidArgument` | `InvalidArgument` | O(n) |
| `remove` | `T remove(Int index)` | `0 <= index < length` | 删除并返回元素；长度 -1 | 越界为合同错误（panic） | O(n) |
| `tryRemove` | `Result<T, Error> tryRemove(Int index)` | 无 | 合法删除；越界 `InvalidArgument` | `InvalidArgument` | O(n) |
| `clear` | `Void clear()` | 无 | 长度 0；容量可保留 | 无 | O(n) |
| `join` | `String join(List<String> items, String separator)` | 元素为 `String` | 用分隔符拼接 | 无 | O(n) |

> `join` 是 `xdk.collections` 顶层函数，不是 `List` 成员；放在本节是因为它只对
> `List<String>` 提供。泛型元素用 `joinWith`。

**失败策略（冻结）**：

- 下标越界属于调用方 bug，`get/set/insert/remove` 直接 panic；
- 输入来自外部或不可信数据时，必须使用 `tryGet/trySet/tryInsert/tryRemove`；
- `insert` 允许 `index == length`，即追加到末尾；
- `join` 只接受 `List<String>`；泛型元素的格式化用 `joinWith`。

### 4.3 示例

```text
List<Int> values = [3, 1, 2]
values.push(4)
Int first = values.get(0)
Result<Int, Error> maybeValue = values.tryGet(10)
print(values.length())          // 4
print(maybeValue.isErr())       // true

List<String> names = ["a", "b"]
String joined = join(names, ",")
print(joined)                   // a,b
```

反例：

- 用 `get` 读取外部输入给出的下标，而不先检查 `length`；
- 遍历 `List` 时 `remove` 当前元素；
- 把 `List` 当值类型，期望赋值后互不影响。

---

## 5. `Map<String,Int>`（语言容器，T0-K）

### 5.1 不变量

- 键唯一；键类型固定为 `String`，值类型固定为 `Int`。
- 迭代顺序不承诺；需要顺序时使用 `keys()`/`values()` 快照后自行排序。
- `getOr` 只读，不插入；`put` 对已存在键替换值并返回旧值。
- `Map` 是引用类型；`==` 是引用身份。

### 5.2 成员契约

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 键数 | 无 | O(1) |
| `has` | `Bool has(String key)` | 无 | 是否存在 | 无 | 均摊 O(1) |
| `getOr` | `Int getOr(String key, Int fallback)` | 无 | 存在 → 值；否则 fallback；不插入 | 无 | 均摊 O(1) |
| `tryGet` | `Result<Int, Error> tryGet(String key)` | 无 | 缺失 → `NotFound` | `NotFound` | 均摊 O(1) |
| `put` | `Bool put(String key, Int value)` | 无 | 替换返回 `true`，插入返回 `false` | 无 | 均摊 O(1) |
| `remove` | `Bool remove(String key)` | 无 | 删除返回 `true`，不存在返回 `false` | 无 | 均摊 O(1) |
| `removeOr` | `Int removeOr(String key, Int fallback)` | 无 | 删除并返回旧值；无则 fallback | 无 | 均摊 O(1) |
| `keys` | `List<String> keys()` | 无 | 快照；顺序不承诺 | 无 | O(n) |
| `values` | `List<Int> values()` | 无 | 快照 | 无 | O(n) |
| `entries` | `List<Pair> entries()` | 无 | 快照；`Pair.first`/`second` | 无 | O(n) |
| `clear` | `Void clear()` | 无 | 清空 | 无 | O(n) |

**冻结说明**：

- `put/remove` 返回 `Int?`。T0-K 的值类型是 `Int`，`null` 只表示“键不存在”，
  不存在“存了 null”的歧义。
- 通用 `Map<K,V>` 的契约同样冻结：`K` 必须是受支持的不可变值，`V` 必须是
  非空类型；`put/remove` 返回 `V?`，`null` 只表示“键不存在”。可空 `V`
  不支持，避免双重含义。

### 5.3 键规则

- T0-K 允许 `String` 与 `Int` 键。
- 通用 `Map<K,V>` 还允许 `Long`/`Bool`/`Char`/简单枚举、`Double`、`Bytes`、
  class、协议、data enum 作为键。
- 键必须是不可变值；禁止用可变对象作键。

### 5.4 示例

```text
Map<String,Int> counts = [:]
Int? previous = counts.put("a", 1)
print(previous == null)          // true
print(counts.getOr("a", 0))      // 1
print(counts.has("b"))           // false
Result<Int, Error> missing = counts.tryGet("b")
print(missing.isErr())           // true
```


### 5.5 `Map<Int,Int>`

与 §5.2 相同的成员面，差异只在类型：

| 成员 | 签名 |
| --- | --- |
| `has` | `Bool has(Int key)` |
| `getOr` | `Int getOr(Int key, Int fallback)` |
| `tryGet` | `Result<Int, Error> tryGet(Int key)` |
| `put` | `Bool put(Int key, Int value)` |
| `remove` / `removeOr` | `Bool remove(Int key)` / `Int removeOr(Int key, Int fallback)` |
| `keys` / `values` | `List<Int> keys()` / `List<Int> values()` |
| `entries` | `List<IntPair> entries()`，元素为 `Int first` / `Int second` |

- 顺序不承诺；`entries` 是快照。
- 与 `Map<String,Int>` 一样是引用类型；`clear` 清空全部键值。


### 5.6 通用 `Map<K,V>` 运行时

四个快速路径之外，核心成员 `length/has/put/remove/removeOr/getOr/tryGet/keys/values/clear`
由通用运行时承载：

| 键/值类别 | 支持类型 | 相等/身份规则 |
| --- | --- | --- |
| 整数槽 | `Int`、`Long`、`Bool`、`Char`、简单枚举 | 按整数值 |
| 文本 | `String` | 按内容 |
| 浮点 | `Double` | 按 64 位位模式 |
| 引用 | `Bytes`、class、协议、data enum、`List`/`Map`/`Set` 值 | 按引用身份 |

- `keys()`/`values()` 返回对应 `List<K>`/`List<V>` 快照。
- `entries()` 对 `Map<String,Int>`/`Map<Int,Int>` 返回 `Pair`/`IntPair`，
  其余受支持组合返回 `Entry<K,V>`（`key`/`value` 字段）。
- `Int128`、`Result` 以及可空类型作为键/值仍被编译器拒绝。
- 可空键不承诺；`Map` 是引用类型，`clear` 清空全部键值。

---

## 6. `Set<Int>` 与 `Set<String>`（语言容器，T0-K）

### 6.1 成员契约

| 方法 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 元素数 | 无 | O(1) |
| `has` | `Bool has(Int value)` | 无 | 是否存在 | 无 | 均摊 O(1) |
| `add` | `Bool add(Int value)` | 无 | 新增 → true；已存在 → false | 无 | 均摊 O(1) |
| `remove` | `Bool remove(Int value)` | 无 | 删除 → true；不存在 → false | 无 | 均摊 O(1) |
| `clear` | `Void clear()` | 无 | 清空 | 无 | O(n) |

- `Set.of(...)` 是编译器对字面量的脱糖；`Set.of(1,2)` 生成 `Set<Int>`，
  `Set.of("a","b")` 生成 `Set<String>`。
- `Set<String>` 的 `has/add/remove` 接收 `String`，其余语义与 `Set<Int>` 相同。
- 重复元素语义固定为“后者忽略”，`add` 返回 `false`。
- 迭代顺序不承诺；需要顺序时先转 `List` 并排序。
- 其他元素类型走通用 `Set<T>`；容器元素不承诺（运行时按引用身份，但类型面
  未列为 T0 验收项）。


### 6.2 通用 `Set<T>` 运行时

- 支持元素类型：`Int`、`Long`、`Bool`、`Char`、简单枚举、`String`、`Double`、
  `Bytes`、class、协议、data enum。
- `String` 按内容相等；`Double` 按 64 位位模式；`Bytes`/class/协议按引用身份。
- `length/has/add/remove/clear` 语义与 §6.1 一致；重复 `add` 返回 `false`。
- `Int128`、`Result` 元素仍是 T0-X。

---

## 7. 算法（T0-K）

### 7.1 排序

| 函数 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `sortBy` | `List<T> sortBy<T>(List<T> items, Bool(T,T) lessThan)` | `lessThan` 为严格弱序 | **原地排序并返回同一列表**；稳定 | 无 | 首版 O(n²) |
| `sortedBy` | `List<T> sortedBy<T>(List<T> items, Bool(T,T) lessThan)` | 同上 | 返回新列表；稳定 | 无 | 首版 O(n²) |
| `isSortedBy` | `Bool isSortedBy<T>(List<T> items, Bool(T,T) lessThan)` | 同上 | 是否已排序 | 无 | O(n) |
| `binarySearchBy` | `Int binarySearchBy<T>(List<T> items, T target, Int(T,T) compare)` | 列表已按 `compare` 排序 | 找到返回索引；否则返回 `-(插入点+1)` | 无 | O(log n) |

**冻结说明**：

- `sortBy` 原地排序，与 mini 现有实现一致；需要保留原列表时使用 `sortedBy`。
- 首版使用稳定插入排序，复杂度 O(n²)；T0-X 可以替换为归并排序，但稳定性不变。
- 比较器必须满足严格弱序；违反导致顺序未定义，属于调用方合同错误。
- `String` 没有 `<`/`>` 运算符（S1 §2.8）。字符串排序必须用
  `xdk.text.compareText` 构造比较器：比较器写成 `compareText(left, right) < 0`，
  对 `["gamma", "alpha", "beta"]` 排序得到 `["alpha", "beta", "gamma"]`。

### 7.2 查找/去重/聚合

| 函数 | 签名 | 语义 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `find` | `T? find<T>(List<T> items, Bool(T) predicate)` | 首个满足；无则 `null` | 无 | O(n) |
| `findIndex` | `Int? findIndex<T>(List<T> items, Bool(T) predicate)` | 首个下标；无则 `null` | 无 | O(n) |
| `dedup` | `List<T> dedup<T>(List<T> items, Bool(T,T) equals)` | 保序去重 | 无 | O(n²) |
| `any` | `Bool any<T>(List<T> items, Bool(T) predicate)` | 任一满足 | 无 | O(n) |
| `all` | `Bool all<T>(List<T> items, Bool(T) predicate)` | 全部满足 | 无 | O(n) |
| `count` | `Int count<T>(List<T> items, Bool(T) predicate)` | 满足个数 | 无 | O(n) |
| `reduce` | `T reduce<T>(List<T> items, T initialValue, T(T,T) combine)` | 左折叠 | 无 | O(n) |
| `partition` | `Pair<List<T>,List<T>> partition<T>(List<T> items, Bool(T) predicate)` | 满足/不满足两组，保序 | 无 | O(n) |
| `chunks` | `List<List<T>> chunks<T>(List<T> items, Int chunkSize)` | 每块 `chunkSize`；末块可短 | `chunkSize <= 0` → 合同错误（panic） | O(n) |
| `windows` | `List<List<T>> windows<T>(List<T> items, Int windowSize)` | 滑动窗口 | `windowSize <= 0` → 合同错误（panic） | O(n) |
| `zip` | `List<Pair<A,B>> zip<A,B>(List<A> left, List<B> right)` | 取较短长度 | 无 | O(min) |
| `flatten` | `List<T> flatten<T>(List<List<T>> nestedItems)` | 展平一层 | 无 | O(n) |
| `joinWith` | `String joinWith<T>(List<T> items, String separator, String(T) format)` | 用 `format` 转文本后拼接；空列表为空串 | 无 | O(n) |
| `groupByInt` | `Map<Int,List<T>> groupByInt<T>(List<T> items, Int(T) keyOf)` | 按 `Int` 键分组，保序 | 无 | O(n²) |
| `groupBy` | `Map<K,List<T>> groupBy<T,K>(List<T> items, K(T) keyOf)` | 按任意受支持 `K` 分组，保序 | 无 | O(n²) |

**冻结说明**：

- `chunks/windows` 的非法尺寸是调用方 bug，直接 panic；需要可恢复错误时，
  由调用方先校验 `chunkSize/windowSize`。
- `groupByInt`/`groupBy` 的组间与组内顺序均为首次出现顺序；分组用通用
  `Map<K,List<T>>` 承载，查找为线性扫描，首版复杂度 O(n²)。
- `Pair`/`IntPair`/`Entry` 是值对象；引用字段按 S2 浅复制规则共享句柄。

### 7.3 `Pair` / `IntPair` / `Entry`（值对象）

```text
class Pair {
    String first
    Int second
}

class IntPair {
    Int first
    Int second
}

class Entry<K, V> {
    K key
    V value
}
```

- `Pair` 是 `Map<String,Int>.entries()` 的元素；`IntPair` 是
  `Map<Int,Int>.entries()` 的元素。
- `Entry<K,V>` 是其余受支持 `Map<K,V>.entries()` 的元素，`key`/`value`
  字段类型分别为 `K`/`V`。
- 值语义；复制时字段槽复制，引用字段浅复制。
- 不持有资源，无 `close()`。

---

## 8. 专用容器

### 8.1 `PriorityQueue<T>`（T0-K）

```text
class PriorityQueue<T> {
    PriorityQueue(Bool(T,T) lessThan)
    Int length()
    Bool isEmpty()
    Void push(T value)
    T? peek()
    T? pop()
    Void clear()
}
```

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `PriorityQueue(lessThan)` | `lessThan` 非空且满足严格弱序 | 创建空堆 | null 或非严格弱序为合同错误 | O(1) |
| `push(value)` | 无 | 插入并上浮 | 无 | O(log n) |
| `peek()` | 无 | 返回堆顶借用；空 → `null` | 无 | O(1) |
| `pop()` | 无 | 移除并返回堆顶；空 → `null` | 无 | O(log n) |
| `clear()` | 无 | 清空 | 无 | O(n) |

- 不稳定；相等优先级顺序不承诺。
- `lessThan` 由调用方持有；队列生命周期内不得改变语义。

### 8.2 `RingBuffer<T>`（T0-K）

```text
class RingBuffer<T> {
    RingBuffer(Int capacity)
    Int length()
    Int capacity()
    Bool isEmpty()
    Bool isFull()
    Bool push(T value)
    T? pop()
    T? peek()
    Void clear()
}
```

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `RingBuffer(capacity)` | `capacity > 0` | 创建空缓冲 | `capacity <= 0` 为合同错误（panic） | O(1) |
| `push(value)` | 无 | 未满写入并返回 `true`；满返回 `false` 且不写入 | 无 | O(1) |
| `pop()` | 无 | 非空取出最旧；空 → `null` | 无 | O(1) |
| `peek()` | 无 | 非空返回最旧；空 → `null` | 无 | O(1) |
| `clear()` | 无 | 清空 | 无 | O(n) |

- **满时行为冻结为“返回 false，不覆盖”**；不提供覆盖模式。
- 容量在构造后不变。

### 8.3 `OrderedMap<V>`（T0-K）

- `Int` 键、插入序映射；`length/has/get/getOr/put/remove/keys/values/clear`。
- 查找 O(n)，插入 O(n)；不承诺哈希复杂度。
- `put(Int key, V value)` 返回 `V?`：替换返回旧值，插入返回 `null`。
- `keys()` 按插入序返回 `List<Int>`，`values()` 返回对应的 `List<V>`。
- `V` 是不可空类型，不支持 `V?` 作为值类型，避免 `null` 同时表示“无旧值”
  和“存了 null”。

### 8.4 `BTreeMap<V>`（T0-K）

- `Int` 键、键升序映射；`length/has/get/getOr/put/remove/keys/values/clear`。
- 查找 O(log n)，插入/删除 O(n)（首版为有序数组）；不宣称真正的 B 树复杂度。
- `put` 返回 `V?`，规则同 `OrderedMap`；`keys()`/`values()` 按键升序返回快照。

### 8.5 不在 T0 的容器

以下能力没有场景，且需要泛型 Map/Set 运行时或新语言特性，归入 T1/backlog：

- `HashMap<K,V>`、`TreeMap<K,V>`、`LinkedHashMap<K,V>`；
- `Deque<T>`、`BitSet`；
- 并发容器、持久化容器、无锁结构。

---

## 9. 所有权、并发、错误

| 项 | 契约 |
| --- | --- |
| 容器所有权 | 容器持有元素引用；`remove/pop` 转移所有权 |
| 迭代 | `for-in` 借用容器；遍历期间禁止结构性修改 |
| 线程安全 | 全部非线程安全；并发容器属于 `xdk.sync` |
| 错误分类 | checked 方法越界/缺失 → `InvalidArgument`/`NotFound`；unchecked 合同错误 → panic |
| 取消 | 算法是纯内存操作，不接受 `Context`；长循环由调用方检查 |
| 键限制 | T0 Map 只接受 `String` 键；Set 只接受 `Int` 元素 |

---

## 10. 示例、反例与测试义务

### 10.1 示例

```text
List<Int> values = [3, 1, 2]
List<Int> sorted = sortBy(values, (Int left, Int right) -> left < right)
print(sorted.get(0))                 // 1
print(values.get(0))                 // 1（原地排序，values 与 sorted 是同一列表）

Map<String,Int> counts = [:]
Int? oldValue = counts.put("a", 1)
print(oldValue == null)              // true
print(counts.getOr("a", 0))          // 1

Set<Int> seen = Set.of(1, 2, 2, 3)
print(seen.length())                 // 3

List<Int> firstChunk = chunks(values, 2).get(0)
print(firstChunk.length())           // 2
```

### 10.2 反例

- 用可变对象作 `Map` 键；
- `lessThan` 使用 `<=`，不满足严格弱序；
- 遍历 `List` 时 `push/remove`；
- 依赖 `Map` 的迭代顺序；
- `chunks(values, 0)` 未校验；
- 在 T0-K 场景使用未支持的组合（如 `Map<String,Int128>`、`Set<Result<...>>`），或对其他 K/V 调用 `entries`。

### 10.3 测试义务

| 类别 | 断言 |
| --- | --- |
| 序列 | 空/单元素/重复/越界 checked/unchecked/插入删除 |
| 映射 | put 旧值、缺失 getOr/tryGet、删除、键唯一 |
| 集合 | 重复 add、remove、空集 |
| 排序 | 稳定性、空列表、单元素、比较器边界 |
| 容器 | 堆序、环形满/空、容量边界 |
| 迭代 | for-in 对 List/Set 展开；Map 不直接遍历 |
| 差分 | mini base/full；不支持的 Map/Set 实例记录缺口 |

---

## 11. 阶段交付与验收（T0-06）

本包是一个验收门，不是一次提交。批内条目不单独提交，但只有满足以下条件
才能标记 `xdk.collections` 为 `complete`：

- `List<T>`（Int/String）、四个 Map/Set 快速路径与通用核心契约一致；
- `sortBy/sortedBy/isSortedBy/binarySearchBy` 与查找/去重/聚合算法可用；
- `PriorityQueue<T>`、`RingBuffer<T>` 契约与实现一致；
- `for-in` 对 List/Set 的场景通过；
- 场景、回归、mini base/full 通过；
- 文档、场景、回归、实现同批交付；批内条目不单独提交、不宣称包完成。

本包现已 `Verified`，并通过 mini base/full：

- `sortBy`（原地、稳定插入排序）、`sortedBy`（副本）、`dedup`、`find`、`join`、
  `joinWith`；
- `groupByInt`/`groupBy`，通用 `Map<K,List<T>>` 值类型；
- `PriorityQueue<T>`、`RingBuffer<T>`、`OrderedMap<V>`、`BTreeMap<V>`；
  场景 `xdk_containers.x`；
- `List.clear/tryGet/trySet/tryInsert/tryRemove`、`Map.clear/put/remove/removeOr/tryGet/keys/values/entries`、`Set.remove/clear`；场景 `xdk_members.x`；
- 通用 `Map<K,V>`/`Set<T>` 核心：标量、`String`、`Double`、`Bytes`、class、协议、data enum，容器值；
- 任意受支持 K/V 的 `entries`：`Pair`/`IntPair`/`Entry<K,V>`。

批末门禁：`src/mini/build.sh`、`src/mini/tests/xdk.sh`、`src/mini/tests/xdk_core.sh` 全绿。

---

## 12. 后续能力（T1/backlog）

以下不是开放问题，而是明确移出本包的能力：

- `HashMap`/`TreeMap`/`LinkedHashMap`/`Deque`/`BitSet`；
- 并发容器、持久化容器、无锁结构。

### 12.1 迭代扩展（T1，不引入泛型协议）

T0 不提供 `Iterator<T>` 公开抽象，是为了不把“泛型协议”当成库功能偷偷实现。
扩展路径是把 `Iterator<T>` 做成**泛型 class**，不是泛型 protocol：

```text
class Iterator<T> {
    Iterator(Bool() hasNext, T() next)

    Bool hasNext()
    T next()
}
```

- 这是普通泛型 class，S2 允许；行为通过两个函数值注入。
- 容器返回 `Iterator<T>`：`List.iterator()`、`Set.iterator()`；自定义容器也可以
  用自己的闭包/游标构造 `Iterator<T>`，不需要 `implements`。
- `for-in` 对用户类型的扩展方式是编译期识别 `iterator(): Iterator<T>` 形状，
  展开为 `hasNext()/next()` 调用。`Iterator<T>` 是具体 class，调用是静态派发，
  不需要泛型协议 vtable。
- 惰性 `map/filter/take/drop/chain/zip/enumerate` 可以做成返回
  `Iterator<U>` 的顶层函数，用闭包组合；类型安全，不使用 `Any`/强制转换。
- 性能：内建容器的 `for-in` 仍走编译器索引展开，不分配迭代器；用户自定义
  迭代器每次 `next` 有一次间接调用，属于 T1 可接受成本，后续可由编译器
  对内联/单态化优化。

如果将来确实需要“运行期用 `Iterator<Int>` 协议变量动态替换不同实现”，
那才需要把泛型协议作为**语言特性**立项：语法、类型参数替换、协议 vtable
单态化、运行时类型描述、`Any`/可空/FFI 交互、方差/约束都要一起设计。
那是语言版本变更，不是 XDK 包能单独完成的。当前 T0 不需要它，也不假装
它已经存在。

---

## 13. 评审结论（本包）

- 去掉了 S2 禁止的泛型协议 `Iterator<T>`/`Iterable<T>`；
- 把 T0-K 收紧到 mini 运行时真实支持的 `List`、`Map<String,Int>`、`Set<Int>`；
- 冻结了 `sortBy` 原地语义、`Map.put` 返回 `Int?`、`RingBuffer` 满时 false；
- 明确了 unchecked 合同错误 panic、checked 方法返回 `Result`；
- 不再把 `HashMap/TreeMap/Deque/BitSet` 写成 T0 承诺；
- 满足 v1.2 的“无待定、无同名换义、无不可表达类型”要求。

下一阶段：按 `CORE-CLOSURE.md` 的固定顺序进入 `05-text.md`。
