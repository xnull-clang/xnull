# B3-09-03 K-02 容器 typedef/helper 生成器移植图（Go `containers.go` → xnullc）

> 目标：把 `wt/e2-sema/impl/lib/b3/xnullc.x` 的固定容器 prelude 换成
> “按翻译单元登记 + 动态生成”的 `xn_arr_*` / `xn_set_*` / `xn_map_*`
> typedef 与 helper，使任意 **mangle 可表达** 的 K/V 组合与 Go oracle 逐字节一致。
>
> 基线：
> - Go oracle：`impl/internal/codegen/containers.go`（695 行）与
>   `impl/internal/codegen/codegen.go` 的调用点；本文行号取自当前工作区。
> - 规范：`handoff/B3-typedef-void-spec.md` §K-02；`handoff/B3-09-baseline.md`。
> - xnullc：`wt/e2-sema@7eea22d:impl/lib/b3/xnullc.x`（K-02 WIP，工作区干净）。
> - 2026-11-09 复测（E4 现场构建 oracle）：
>   | 入口 | Go C 行数 | xnullc unified diff | 现状 |
>   |---|---:|---:|---|
>   | `examples/classes.x` | 931 | **0** | WIP 已补 `map_s_i` typedef + `arr_s/map_s_i/str_split` 块 |
>   | `difftest/anchors/cases/pkg/f2.x` | 1778 | **1412** | `Map<String,String>` 落到 `int64_t`，缺 `xn_map_s_s`/`arr_s` |
>   | `tests/b3/fixtures/bundle/app.x` | 3319 | **99**（基线表 614） | 只缺 `xn_arr_u16`（typedef + helper） |
>   | `tests/b3/fixtures/container/*.x` | — | 5/5 PASS | 依赖固定 prelude |
>   | `tests/b3/xnullc-bundle.sh` | — | 4/4 PASS | sync/tasks/collections/text |
>   | `tests/b3/xnullc-tuple.sh` | — | 5/5 PASS | 元组容器只有 `(Int,Int)` 形状 |
>
> 本文只读分析，不改 xnullc / Go oracle。E2 按 C/D 施工。

## 0. 一句话结论

Go 的容器实例化是 **每次翻译单元一份 `containers` 注册表**：`cType` 遇到容器就
`needArr/needSet/needMap` 登记；第一遍试生成把局部/表达式里的容器也带进来；
`prewarmTypeContainers` 再补签名/字段/Result 成员；随后 **typedef 一次输出、helper 一次输出**，
两处都按 C 类型名排序，`declared` 去重。

xnullc 现在是 **“一个 `cbKey` + 若干固定 prelude 常量”**：class 分支最多选
`objArr / List<Int> / List<UInt16>` 之一，再额外拼 `map_s_i`；非 class 分支整体
选择 `PRELUDE_ARR / PRELUDE_MAPSET / PRELUDE_CONT`。它无法同时输出多个数组实例
（`app.x` 的 `arr_i + arr_u16`），也无法输出任意 Map K/V（`f2.x` 的 `map_s_s`）。

施工顺序必须是：

1. **登记层**：加 `C_ARR/C_SET/C_MAP_K/C_MAP_V/C_DECL` 与 `need*`，`cType` 走通用解析；
   输出保持旧 prelude（零 diff 回归）。
2. **typedef 层**：用动态 typedef 块替换固定 typedef（class 分支先做，再做非 class）。
3. **helper 层**：用动态 helper 生成替换固定 helper 文本，最后删除旧常量。

---

# A. Go 容器模型

## A.1 数据结构与命名

`containers`（`containers.go:74-83`）：

| 字段 | 类型 | 语义 |
|---|---|---|
| `arr` | `map[string]bool` | 已登记数组实例，键 = 元素 C 类型（如 `int64_t`、`rt_string *`、`xn_Cls_Node *`、`xn_tup_int64_t_int64_t`） |
| `set` | `map[string]bool` | 已登记 Set 实例，键 = 元素 C 类型 |
| `mp` | `map[string][2]string` | 已登记 Map 实例，键 = `mangle(k)+"\|"+mangle(v)`，值 = `{kC, vC}` |
| `declared` | `map[string]bool` | 已提前输出 typedef 的容器 C 名；主 typedef 块输出前由调用方清空（`codegen.go:736-743`） |

命名（`containers.go:114-145`）：

| 容器 | 名字 | typedef |
|---|---|---|
| 数组 / List | `xn_arr_<mangle(E)>` | `typedef struct { rt_header hdr; size_t len; size_t cap; E *data; } xn_arr_<m>;` |
| Set | `xn_set_<mangle(E)>` | `typedef struct { rt_header hdr; xn_arr_<m> *a; } xn_set_<m>;` |
| Map | `xn_map_<mangle(K)>_<mangle(V)>` | `typedef struct { rt_header hdr; size_t len; size_t cap; K *keys; V *vals; } xn_map_<k>_<v>;` |

`mangle`（`containers.go:23-59`）是白名单，**不是**任意 C 类型：

| C 类型 | mangle |
|---|---|
| `int64_t` | `i` |
| `int` | `b`（Bool） |
| `uint8_t` / `uint16_t` / `uint32_t` / `uint64_t` | `u8` / `u16` / `u32` / `u64` |
| `int8_t` / `int16_t` / `int32_t` | `i8` / `i16` / `i32` |
| `double` / `float` | `f64` / `f32` |
| `rt_string *` | `s` |
| `xn_Cls_X *` | `o_X`（`TrimPrefix("xn_Cls_")` + `TrimSuffix(" *")`） |
| `xn_tup_...` | `t_...`（`t_` + `TrimPrefix("xn_tup_")`） |
| 其他（`xn_Struct_*`、`xn_Enum_*`、`xn_Any *`、`xrt_bytes_obj *`、`xrt_text *`、`xrt_sb *`、`xrt_handle *`、协议指针、嵌套容器指针） | **报错** `codegen：容器元素类型暂支持 ... got %s` |

> 关键：**容器元素/键/值只能是上表 12 种标量 + String + 类指针 + 元组**。
> `List<Bytes>`、`Map<Int,List<Int>>`、`Set<Enum>` 在 Go 侧直接构建失败，K-02 不要承诺。

`isRef`（`containers.go:69-71`）：
`rt_string *`、`xrt_bytes_obj *`、`xrt_text *`、`xrt_sb *`、`xn_Cls_*` 任一 → true。
`isGC` 是 `containers.emit` 的入参 `g.isGCTypeC`（`codegen.go:785`），决定
`arc := ref && !gc`（数组 `:234`、Set `:366`、Map `:440-441`）。
`elemZero`（`:61-66`）只在 Map 可选 `get` 用：引用 → `NULL`，否则 `0`。

## A.2 `need*` 触发条件、去重与两遍

| 函数 | 行 | 行为 |
|---|---|---|
| `needArr(elem)` | `:85-91` | `mangle(elem)` 失败即返回错误；`cs.arr[elem]=true` |
| `needSet(elem)` | `:93-99` | 先 `needArr(elem)`（**Set 必然带数组**），再 `cs.set[elem]=true` |
| `needMap(k,v)` | `:101-112` | 分别 `mangle` 校验；键 `km+"\|"+vm`，值 `{k,v}`；同键覆盖即去重 |

触发点（全部在 `cType` 或 FFI/表达式辅助里）：

| 位置 | 行 | 触发 |
|---|---|---|
| `cType` 后缀 `T[]` | `codegen.go:1694-1703` | `needArr(ec)` |
| `cType` `NamedType List<T>` | `codegen.go:1785-1795` | `needArr(ec)` |
| `cType` `NamedType Set<T>` | `codegen.go:1797-1807` | `needSet(ec)` |
| `cType` `NamedType Map<K,V>` | `codegen.go:1809-1828` | `needMap(kc,vc)` |
| `resultCType` `List<T>`（Result 值槽） | `codegen.go:1469-1488` | `needArr(ec)` |
| `exprType` 的 `Map.keys()/values()` | `types.go:371-388` | `needArr(k)` / `needArr(v)` |
| `String.split` | `containers_expr.go:87` | `needArr("rt_string *")` |
| FFI `KindArray` 编组 | `ffi_gen.go:526` | `needArr(elemC)` |

两遍发射（`codegen.go:595-648`）：

1. 第一遍 `genFuncNamed` / `genMethod` 试生成，产物丢弃；容器登记保留。
2. `expandInstances()` 展开泛型实例（可能继续登记）。
3. `g.tmp = 0` 重置临时号；第二遍正式生成函数体（局部声明会再次登记，幂等）。
4. `prewarmTypeContainers(u)`（`codegen.go:5463-5505`）在 emit 前补登记：
   `TopFunc` 参数/返回、`ClassDecl` 字段/方法参数/返回、`StructDecl` 字段、
   `SingletonDecl` 字段、`FactoryDecl` 方法；遇到 `Result<V,E>` 递归 `cType` 两个实参。
5. 主 typedef 块前清 `declared`（`codegen.go:736-743`），把 `arr/set/mp` 的全集
   转成名字集合传入 `emitTypeDecls`。

> Go 的第一遍 + prewarm 是“宁可多登记”的口径：即使某容器最终没在函数体里用，
> 只要出现在签名/字段里就会输出 typedef。xnullc 必须同样保留第一遍/预扫描的登记，
> 不能只看最终生成文本。

## A.3 `emitTypeDecls` 输出顺序

`emitTypeDecls`（`containers.go:148-199`）：

1. 数组：收集 `cs.arr` 中 `needed[arrName(e)]` 的元素，`sort.Strings`（**按元素 C 类型字节序**），
   逐个输出 typedef（`\n\n`），`declared[name]=true`。
2. Set：收集 `cs.set`，同样按元素 C 类型排序，输出 `xn_set_*`（依赖对应数组 typedef 已在前）。
3. Map：收集 `cs.mp` 的键（`km+"|"+vm`），**按 mangle 键排序**，输出 `xn_map_*`。

每个 typedef 后固定一个空行（`fmt.Fprintf(... ";\n\n")`）。
`declared` 防重：同一容器在 Set/Map 依赖里再次出现不会重复。

整份 C 的相关顺序（`codegen.go:678-790`）：

```
prelude
协议类型
函数指针 typedef
枚举 typedef
结构体 typedef
FFI 支撑
xn_fatal_oob 声明+定义
prewarmTypeContainers
emitClassTypedefs          // 类 typedef（第一批前向）
emitTupleTypes             // 元组 typedef（容器元素可能是元组）
emitTypeDecls              // 数组 → Set → Map
emitClassForwardDecls      // 类前向 + 构造器/方法原型（可能登记新容器）
emitSingletonForwards
emitExtensionProtos
Result typedefs            // 需要容器 typedef 已就位
顶层字段
ensureMapArrays
cs.emit                    // 数组 → Set → Map helper
strSplitHelper（仅 arr["rt_string *"]）
strReplaceHelper（按需）
顶层函数原型
函数定义
```

注意 `emitClassForwardDecls` 里的构造器原型可能在主 typedef 块之后才 `cType` 到新容器；
这些容器不会出现在主 typedef 块，而是在 `cs.emit` 的数组循环里以 `skipDecl=false`
就地输出 typedef。**这是合法的、也是字节 diff 的一部分**（见 A.5）。

## A.4 helper 全集与签名

`N` = `xn_arr_<m>`，`S` = `xn_set_<m>`，`M` = `xn_map_<k>_<v>`，`E/K/V` = 元素/键/值 C 类型。

数组（`containers.go:231-359`）：

| C 名 | 签名 | 条件 |
|---|---|---|
| `N_scan` | `static void N_scan(void *p, void (*visit)(void *))` | 仅 `isRef(E)`；`data==NULL` 直接 return；`for i: visit(a->data[i])` |
| `N_deinit` | `static void N_deinit(void *p)` | 恒有；ARC 元素先 `for: rt_release(data[i])`，再 `free(data)`，清零 len/cap |
| `RT_TYPE_N` | `static const rt_type RT_TYPE_N = { "List", sizeof(N), N_deinit, <scan|NULL> };` | scan 仅在 `isRef(E)` |
| `N_new` | `static N *N_new(size_t cap)` | `xn_gc_new`；cap 0→4；`malloc(sizeof(E)*cap)`；失败 `abort()` |
| `N_push` | `static void N_push(N *a, E v)` | 满则 cap*=2 + `realloc`；ARC 先 `rt_retain(v)` |
| `N_get` | `static E N_get(const N *a, int64_t i)` | `i<0 || i>=len` → `xn_fatal_oob()` |
| `N_set` | `static void N_set(N *a, int64_t i, E v)` | 越界 fatal；ARC 先 release 旧值、retain 新值 |
| `N_remove` | `static E N_remove(N *a, int64_t i)` | 越界 fatal；返回被删元素（借用；调用方按 ARC 释放） |
| `N_insert` | `static void N_insert(N *a, int64_t i, E v)` | `i<0 || i>len` fatal；扩容后后移；ARC retain |
| `N_clear` | `static void N_clear(N *a)` | ARC 先逐个 release；`len=0` |
| `N_join` | `static rt_string *N_join(N *a, rt_string *sep)` | 逐元素字符串化 + `xn_concat`；分隔符/元素按 `int64_t→xn_str_int`、`int→xn_str_bool`、`rt_string*→rt_string_new`、其他→`rt_string_from_c("")` |

Set（`containers.go:363-435`）：

| C 名 | 签名 | 条件 |
|---|---|---|
| `S_scan` | `static void S_scan(void *p, void (*visit)(void *))` | **恒有**；`if (s->a) visit(s->a);` |
| `S_deinit` | `static void S_deinit(void *p)` | 只 `s->a = NULL;`（数组是 GC 对象，由 GC 回收） |
| `RT_TYPE_S` | `{ "Set", sizeof(S), S_deinit, S_scan }` | scan 恒有 |
| `S_new` | `static S *S_new(void)` | `xn_gc_new`；`s->a = arr_new(4)` |
| `S_add` | `static int S_add(S *s, E v)` | 线性查重；已存在返回 0；否则 `arr_push`，返回 1 |
| `S_has` | `static int S_has(const S *s, E v)` | 线性查找，1/0 |
| `S_at` | `static E S_at(const S *s, int64_t i)` | 越界 fatal |
| `S_remove` | `static int S_remove(S *s, E v)` | 找到后左移；ARC 先 release 被删元素；返回 1/0 |
| `S_clear` | `static void S_clear(S *s)` | `arr_clear(s->a)` |

Set 相等（`containers.go:367-372`）：
- `isRef(E)` → `s->a->data[i]->len == v->len && memcmp(...->bytes, v->bytes, v->len) == 0`
  ——这是 **String 专用**；对类指针会生成非法 C（见 E.2）。
- 否则 → `s->a->data[i] == v`（标量、Bool 可用；元组结构体不可用）。

Map（`containers.go:438-629`）：

| C 名 | 签名 | 条件 |
|---|---|---|
| `M_scan` | `static void M_scan(void *p, void (*visit)(void *))` | **恒有**；`isRef(K)` 循环 keys，`isRef(V)` 循环 vals，各自判 `!=NULL` |
| `M_deinit` | `static void M_deinit(void *p)` | 恒有；ARC 的 K/V 先 release 循环；再 `free(keys)`、`free(vals)`；清零 |
| `RT_TYPE_M` | `{ "Map", sizeof(M), M_deinit, M_scan }` | scan 恒有 |
| `M_new` | `static M *M_new(size_t cap)` | cap 0→4；`malloc(sizeof(K)*cap)` + `malloc(sizeof(V)*cap)`；失败 abort |
| `M_find` | `static long M_find(const M *m, K key)` | 线性；String 键用字节 memcmp；否则 `keys[i]==key`；返回下标或 -1 |
| `M_put` | `static void M_put(M *m, K key, V val)` | 找到：`dropK`/`dropV`（ARC 时 release 旧 K/V；注意 Go 会 release 旧 key 但仍保留 keys 指针），然后 `vals[i]=val`；未找到：扩容、`keepK`/`keepV`、写 keys/vals、len++ |
| `M_has` | `static int M_has(const M *m, K key)` | `find >= 0` |
| `M_get_or` | `static V M_get_or(const M *m, K key, V dflt)` | 找到返回值，否则 dflt（不 retain） |
| `M_remove` | `static int M_remove(M *m, K key)` | 未找到 0；ARC release 被删 K/V；左移；len--；返回 1 |
| `M_clear` | `static void M_clear(M *m)` | ARC 的 K/V release 循环；`len=0` |
| `M_cmp_key` | `static int M_cmp_key(K a, K b)` | 仅 `rt_string *` / `int64_t` / `int` 有真实比较；其他 `return 0`（插入序） |
| `M_sort_idx` | `static void M_sort_idx(const M *m, size_t *idx)` | 插入排序，`cmp>0` 时后移；稳定 |
| `M_keys` | `static arr<K> *M_keys(const M *m)` | 新数组 len；`malloc idx`；初始化下标；排序；按 idx push keys；free idx |
| `M_values` | `static arr<V> *M_values(const M *m)` | 同上，按 key 顺序 push vals |
| `M_get` | `static xn_opt_X M_get(const M *m, K key)` | **条件生成**：`optName(V)` 成功才发；缺失 `r.has=0; r.v=elemZero(V)`；命中 `has=1; r.v=vals[i]`；ARC 值再 `rt_retain(r.v)` |

`optName`（`containers.go:120-134`）：`int64_t→xn_opt_i`、`int→xn_opt_b`、
`rt_string *→xn_opt_s`、`xrt_handle *→xrt_handle *`。由于 mangle 不接受 handle，
实际只有 `i/b/s` 三种 Map 值会有 `M_get`；类/元组值只有 `get_or`。

`M_cmp_key` 具体（`:553-570`）：

```c
/* rt_string * */
size_t n = a->len < b->len ? a->len : b->len;
int c = memcmp(a->bytes, b->bytes, n);
if (c != 0) { return c; }
return (a->len > b->len) - (a->len < b->len);

/* int64_t：按十进制字符串比较（不是数值序，负数/多位数会“字典序”） */
char ba[32], bb[32];
snprintf(ba, sizeof(ba), "%lld", (long long)a);
snprintf(bb, sizeof(bb), "%lld", (long long)b);
return strcmp(ba, bb);

/* int（Bool）：数值 */
return (a > b) - (a < b);

/* 其他：插入序 */
return 0;
```

`ensureMapArrays`（`containers.go:632-637`）在 `emitTypeDecls` **之后**、`cs.emit` **之前**
把每个 Map 的 K/V 加入 `cs.arr`。于是：
- 如果 K/V 数组没有被别处提前登记，它们的 typedef 不在主 typedef 块，而是在
  helper 发射时由 `emitArrHelpers(..., skipDecl=false)` 就地输出。
- 实测：`f2.x` 主块只有 `xn_map_s_s`，`xn_arr_s` 在 helper 段（Go C 第 401 / 431 行）；
  `examples/classes.x` 是 `arr_i:396`、`map_s_i:398`，`arr_s:485` 在 helper 段；
  `tests/b3/fixtures/container/mapset.x` 是 `arr_i:394`、`set_i:396`、`map_s_i:398`，
  `arr_s:480` 在 helper 段。E2 必须复刻这个“晚 typedef”位置，不能把所有数组都提前。

`relElemLoop`（`:640-645`）只被别处复用，K-02 不单独发射。
`strSplitHelper`（`:647-674`）不在容器注册表内，由 `codegen.go:786` 以
`cs.arr["rt_string *"]` 为条件输出；E2 的动态版也必须用同一条件。

## A.5 排序与去重规则（必须逐字节一致）

1. 数组/Set typedef 与 helper 都按 **元素 C 类型字符串** 升序；Go `sort.Strings` 是
   **字节序**：ASCII `数字 48-57 < 大写 65-90 < '_' 95 < 小写 97-122`。
2. Map 按 **`mangle(K)+"|"+mangle(V)`** 升序，不是按完整 `xn_map_...` 名。
3. 同一元素只发一份；`declared` 只防 typedef，helper 只在 `emit` 循环中每元素一次。
4. `needSet` 自动带 `needArr`；`ensureMapArrays` 自动带 K/V 数组。
5. 容器名只由 mangle 决定，因此 `int64_t`/`int` 不会撞名；类名用 `o_`、元组用 `t_`，
   与标量 mangle 空间不重叠（`o_`/`t_` 前缀不可能出现在标量 mangle 里）。

---

# B. 每类 helper 的 C 模板与语义

> 本节所有模板都直接对应 `containers.go` 的 `fmt.Fprintf`。**缩进与空行属于 oracle 的一部分**，
> E2 应照抄格式串，不要按普通 C 风格重排。

## B.1 数组（`emitArrHelpers`，`containers.go:231-359`）

格式参数（`:359`）：
`n, elem, "", "", keep, dropOld, clearRel, elemStr, scanBody, relBody, scanFn`

条件片段：

| 占位 | 条件 | 文本 |
|---|---|---|
| `%[9]s` scanBody | `isRef(E)` | `static void N_scan(...) { ... }` + 两个换行 |
| `%[11]s` scanFn | `isRef(E)` | `N_scan`；否则 `NULL` |
| `%[10]s` relBody | `arc` | `        for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n`（8 空格，位于 `free` 之前） |
| `%[5]s` keep | `arc` | `    rt_retain(v);\n` |
| `%[6]s` dropOld | `arc` | `    rt_release(a->data[i]);\n` |
| `%[7]s` clearRel | `arc` | `    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n` |
| `%[8]s` elemStr | 按 E | `int64_t→xn_str_int(a->data[i])`；`int→xn_str_bool(a->data[i])`；`rt_string *→rt_string_new(a->data[i]->bytes, a->data[i]->len)`；其他 `rt_string_from_c("")` |

骨架：

```c
[N_scan 若 isRef]

static void N_deinit(void *p) {
    N *a = (N *)p;
    if (a->data != NULL) {
[relBody 若 arc]
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_N = { "List", sizeof(N), N_deinit, [N_scan|NULL] };

static N *N_new(size_t cap) { ... a->cap = cap ? cap : 4; a->data = malloc(sizeof(E) * a->cap); ... }

static void N_push(N *a, E v) { ... [rt_retain(v) 若 arc] a->data[a->len++] = v; }

static E N_get(const N *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); } return a->data[i]; }

static void N_set(N *a, int64_t i, E v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
[dropOld 若 arc][keep 若 arc]    a->data[i] = v;
}

static E N_remove(N *a, int64_t i) { ... E old = ...; 左移; a->len--; return old; }

static void N_insert(N *a, int64_t i, E v) { if (i < 0 || (size_t)i > a->len) fatal; 扩容/后移; [rt_retain(v) 若 arc] ... }

static void N_clear(N *a) { [clearRel 若 arc]    a->len = 0; }

static rt_string *N_join(N *a, rt_string *sep) { ... xn_concat(..., elemStr); ... }
```

**依赖**：
- `isRef(E)`：决定 scan、ARC 分支、以及 `N_get` 的 `E` 返回。
- `isGC(E)`：决定 ARC 是否真正 retain/release（String/GC 类不计数）。
- 值类型（标量/Bool/元组）无 scan、无 retain/release。
- `join` 只对 Int/Bool/String 有意义；类/元组得到空串（Go 现状）。

## B.2 Set（`emitSetHelpers`，`containers.go:363-435`）

格式参数（`:434`）：`an, sn, elem, eq, "", dropRemoved`

```c
static void S_scan(void *p, void (*visit)(void *)) {
    S *s = (S *)p;
    if (s->a != NULL) { visit(s->a); }
}

static void S_deinit(void *p) {
    S *s = (S *)p;
    s->a = NULL; /* 数组是 GC 对象，由 GC 回收 */
}

static const rt_type RT_TYPE_S = { "Set", sizeof(S), S_deinit, S_scan };

static S *S_new(void) {
    S *s = (S *)xn_gc_new(&RT_TYPE_S);
    memset((char *)s + sizeof(rt_header), 0, sizeof(S) - sizeof(rt_header));
    s->a = N_new(4);
    return s;
}

static int S_add(S *s, E v) { 线性查重; 不存在则 N_push(s->a, v); return 1; }
static int S_has(const S *s, E v) { ... }
static E S_at(const S *s, int64_t i) { 越界 fatal; return s->a->data[i]; }
static int S_remove(S *s, E v) { 找到后左移; [rt_release(被删元素) 若 arc]; s->a->len--; return 1; }
static void S_clear(S *s) { N_clear(s->a); }
```

**依赖**：
- Set 内部永远是数组对象；`S_scan` 恒有（visit 数组本身），与元素是否为引用无关。
- `eq` 是唯一依赖元素类型的比较逻辑；String 用字节，其他用 `==`。
- `dropRemoved` 只在 ARC 元素时生成。

## B.3 Map（`emitMapHelpers`，`containers.go:438-629`）

格式参数（`:551`）：
`n,k,v,relK,relV,keq,keepK,dropK,dropV,keepV,scanKeys,scanVals,relK,relV`

条件片段：

| 占位 | 条件 | 文本 |
|---|---|---|
| `%[11]s` scanKeys | `isRef(K)` | `    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n` |
| `%[12]s` scanVals | `isRef(V)` | 同上，用 `m->vals` |
| `%[13]s`/`%[14]s` deinit relK/relV | `arcK`/`arcV` | `        for (...) { rt_release(...); }\n`（8 空格，在 free 前） |
| `%[8]s`/`%[9]s` put 覆盖 dropK/dropV | `arcK`/`arcV` | `    rt_release(m->keys[i]);\n` / `    rt_release(m->vals[i]);\n`（**4 空格**） |
| `%[7]s`/`%[10]s` put 新增 keepK/keepV | `arcK`/`arcV` | `    rt_retain(key);\n` / `    rt_retain(val);\n`（4 空格） |
| `%[4]s`/`%[5]s` clear relK/relV | `arcK`/`arcV` | `        for (...) { rt_release(...); }\n`（8 空格） |

骨架：

```c
static void M_scan(void *p, void (*visit)(void *)) {
    M *m = (M *)p;
[scanKeys 若 isRef(K)][scanVals 若 isRef(V)]}

static void M_deinit(void *p) {
    M *m = (M *)p;
    if (m->keys != NULL) { [relK 若 arcK]        free(m->keys); m->keys = NULL; }
    if (m->vals != NULL) { [relV 若 arcV]        free(m->vals); m->vals = NULL; }
    m->len = 0; m->cap = 0;
}

static const rt_type RT_TYPE_M = { "Map", sizeof(M), M_deinit, M_scan };

static M *M_new(size_t cap) { ... m->keys = malloc(sizeof(K)*cap); m->vals = malloc(sizeof(V)*cap); ... }

static long M_find(const M *m, K key) {
    for (size_t i = 0; i < m->len; i++) { if ([keq]) { return (long)i; } }
    return -1;
}

static void M_put(M *m, K key, V val) {
    long i = M_find(m, key);
    if (i >= 0) {
[dropK 若 arcK][dropV 若 arcV]        m->vals[i] = val;
        return;
    }
    if (m->len == m->cap) { ... realloc keys/vals ... }
[keepK 若 arcK][keepV 若 arcV]    m->keys[m->len] = key;
    m->vals[m->len] = val;
    m->len++;
}

static int M_has(const M *m, K key) { return M_find(m, key) >= 0; }

static V M_get_or(const M *m, K key, V dflt) { long i = M_find(m, key); return i >= 0 ? m->vals[i] : dflt; }

static int M_remove(M *m, K key) { ... [release 被删 K/V 若 arc] ... }

static void M_clear(M *m) { [relK 若 arcK][relV 若 arcV]    m->len = 0; }

static int M_cmp_key(K a, K b) { /* 见 A.4 */ }

static void M_sort_idx(const M *m, size_t *idx) { /* 插入排序 */ }

static arr<K> *M_keys(const M *m) { ... }
static arr<V> *M_values(const M *m) { ... }

/* 仅 optName(V) 成功时 */
static xn_opt_X M_get(const M *m, K key) { ... }
```

**依赖**：
- `keq`：String → 字节 memcmp；其他 → `==`（类指针地址比较，但见 E.2 的 isRef bug）。
- `arcK/arcV`：决定 retain/release；`isRef` 决定 scan。
- `cmp_key`：只有 String / Int64 / Bool 有顺序；类、元组、枚举（若将来支持）→ 0。
- `keys()/values()`：依赖 `arr<K>` / `arr<V>` 的 helper 已存在；由 `ensureMapArrays` 保证。
- `M_get`：只在 V ∈ {Int,Bool,String} 时输出。

## B.4 类型依赖矩阵

| helper 组 | 元素/键/值类型 | GC/ARC | key 比较 |
|---|---|---|---|
| 数组 typedef/new/push/get/set/remove/insert/clear | 任意 mangle 类型 | ARC 分支由 `isRef && !isGC` | 无 |
| 数组 scan | `isRef` | 恒 visit | 无 |
| 数组 join | Int/Bool/String 有内容；其他空串 | 无 | 无 |
| Set typedef/new/add/has/at/clear | 任意 mangle 类型 | add 走数组 push；remove/clear 走 ARC 释放 | `isRef(E)`（含 String **和类指针**）→ 字节 memcmp；类指针因此非法 C；非引用 → `==`（元组结构体非法 C） |
| Set scan | 恒有 | visit 数组对象 | 无 |
| Map typedef/new/find/put/has/getOr/remove/clear | 任意 mangle 类型 | K/V 分别 arc | `keq`：`isRef(K)`（String 或类指针）→ 字节 memcmp；类指针非法 C；非引用 → `==`（Int/Bool 可用，元组非法 C） |
| Map scan | `isRef(K)` / `isRef(V)` | 分别 visit | 无 |
| Map cmp/sort/keys/values | any | 无 | String 字典序；Int64 十进制字符串；Bool 数值；其他 0 |
| Map get | V ∈ {Int,Bool,String} | String GC 不 retain；标量零值 | 无 |

补充（题目里的“String/Int/枚举/类”四类 key）：

- **String**：`keq`/`eq` 用字节长度 + `memcmp`；`cmp_key` 用字节字典序 + 长度兜底。
- **Int / Bool**：`keq` 用 `==`；`cmp_key` 分别是十进制字符串比较 / 数值比较。
- **枚举**：`mangle` 白名单不接受 `xn_Enum_*`（简单枚举）或 `xn_Enum_* *`（数据枚举），
  因此 Go 当前 **根本无法注册枚举 key**；`cmp_key` 的 `default: return 0` 只是兜底，
  不要把“枚举 key 按插入序”当成已支持语义。
- **类**：`mangle` 接受 `xn_Cls_X *`，但 `isRef` 为真导致 `keq/eq` 走 String 的
  `->len/->bytes` 分支 → **非法 C**；不要移植成可用组合。类作为 Map **值** 是合法的
  （`get_or/put/remove/clear` 可用，`get` 不生成）。

## B.5 Go 现状明确不支持 / 会生成非法 C 的组合

`mangle` 白名单决定：

- `List<Bytes>` / `List<Text>` / `List<StringBuilder>` / `List<Any>` / `List<DataEnum>`：
  **构建期报错**。
- `Map<Int, List<Int>>`、`Map<Int, Set<Int>>`、`List<List<Int>>`：mangle 拒绝嵌套容器指针。
- `Set<Class>`、`Map<Class, V>`：mangle 接受 `o_X`，但 `eq/keq` 走 `isRef` 的
  `->len/->bytes` 分支，生成非法 C（类没有这些字段）。**不要移植成“支持”**，保持 Go 现状。
- `Set<Tuple<...>>`：mangle 接受，但 `==` 比较两个结构体，非法 C。
- `Map<Tuple<...>, V>`：`keq` 走 `==`，非法 C。
- `Map<Int, Class>`：`get_or` 可用；`get` 不生成（optName 失败）；`put/remove/clear`
  的 ARC 值管理可用。

---

# C. xnullc 映射

## C.1 现状（`wt/e2-sema@7eea22d`）

固定 prelude（`xnullc.x:22-26`）：

| 常量 | 行 | 内容 | 问题 |
|---|---|---|---|
| `PRELUDE_ARR` | 22 | 头 + `xn_arr_i` typedef/helper + `xn_main` + tail | 只有 `arr_i`；无 arr_s/set/map |
| `PRELUDE_MAPSET` | 23 | 头 + `arr_i/set_i/map_s_i` typedef + `arr_i/arr_s/set_i/map_s_i` helper + `xn_str_split` | 固定 K/V；含 `arr_s` |
| `PRELUDE_CONT` | 24 | 与 MAPSET 基本相同，只多一条抓取时残留的 `xn_sum` 原型 | 与 MAPSET 的选择逻辑无意义 |
| `PRELUDE_TARR` | 25 | 头 + **固定形状** `xn_tup_int64_t_int64_t` typedef + 该形状数组 helper | 不是通用元组容器 |
| `PRELUDE_ANY` | 26 | 头，无容器 | `usesAny` 分支会吞掉别的容器 |
| `PRELUDE_HEAD/PRE_A/B1/B2/B3/FATAL_MID/TAIL*` | 9-21 | 公共头/枚举/尾部 | 可复用 |

class 分支的“单实例”选择（`xnullc.x:5120-5162`）：

1. `cbKey` 依次尝试 `e.objArrKey`、`FLD_TYPE` 中第一个 `isObjArr`、第一个 `List<Int>/Int[]`、
   `e.usesList`、声明里任意 `List<UInt16>`、声明里任意 `hasListIn`。
2. `cbType = containerTypedef(cbKey)`（`:5151`）——**只一个**。
3. `cbHelp` 按 `objArr/u16/arr_i` 三选一（`:5153-5158`）。
4. 若 `e.hasMap` 或字段里有 `Map<String,Int>`，再拼 `arrSBlock() + mapSIBlock() + strSplitBlock()`（`:5159-5162`）——
   这解释了为什么 `classes.x` 能到 0，但 `app.x` 的 `arr_u16` 永远选不到（`cbKey` 先命中 `List<Int>`）。

固定 typedef/helper 入口：

| 函数 | 行 | 备注 |
|---|---|---|
| `cType` 固定四种 | 409-414 | `List<Int>`、`List<UInt16>`、`Set<Int>`、`Map<String,Int>`；其他容器落到 `int64_t` |
| `containerTypedef` | 4192-4199 | 只认 objArr/List<Int>/List<UInt16> |
| `mapSITypedef` | 4201 | WIP 临时补 `map_s_i` |
| `arrSBlock` | 4204 | 从 `PRELUDE_MAPSET` 截取 `arr_s` typedef+helper |
| `mapSIBlock` | 4212 | 截取 `map_s_i` helper |
| `strSplitBlock` | 4220 | 截取 `xn_str_split` |
| `u16ArrHelperText` | 4230-4256 | 内联 arr_u16 helper（join 为空串） |
| `arrIHelperText` | 4257-4261 | 从 `PRELUDE_ARR` 截取 arr_i helper（不含 typedef） |
| `classArrHelperText` | 4262-4357 | 类元素数组 helper（scan/ARC 判断用 `classPolicy`） |

非 class 分支 `xnullc.x:5456-5461`：

```xnull
} else if e.usesList || e.hasMap || e.hasSet {
    if e.hasMap {
        if e.hasGetOr { res = PRELUDE_CONT } else { res = PRELUDE_MAPSET }
    } else {
        res = PRELUDE_ARR
    }
}
```

已知缺陷：
- `Set<Int>` 单独出现（无 map/list）→ 选 `PRELUDE_ARR`，没有 set helper。
- `List<String>` / `String[]` → `cType` 落到 `int64_t`（当前无 fixture 覆盖）。
- 非 class 的 `usesAny`/`usesTArr` 优先于容器分支，会丢容器支持。
- 所有固定文本只覆盖 `i/u16/s/s_i` 等少数实例。

## C.2 新增 registry（XNull 语法，按现有全局风格）

放在 `TUPLE_KEYS` 等全局注册表附近（`xnullc.x:564-593`）。**不要**用 `EM`：
`cType(String k)` 是全局函数，拿不到 `EM e`；仓库里已有大量 `static List<String>` 全局注册表模式。

```xnull
/* K-02：容器注册表（Go containers.go 对齐） */
static List<String> C_ARR = []       /* 元素 C 类型 */
static List<String> C_SET = []       /* 元素 C 类型 */
static List<String> C_MAP_K = []     /* 与 C_MAP_V 平行 */
static List<String> C_MAP_V = []
static List<String> C_DECL = []      /* 已输出 typedef 的容器 C 名 */
```

函数签名（全部纯字符串/列表操作，**不得**触碰 `EM.tmp`）：

```xnull
static String cMangle(String c)
static String cArrName(String ec)
static String cSetName(String ec)
static String cMapName(String kc, String vc)
static String cArrTypedef(String ec)
static String cSetTypedef(String ec)
static String cMapTypedef(String kc, String vc)
static String containerTypedefsAll()
static String arrHelperText(String ec)
static String setHelperText(String ec)
static String mapHelperText(String kc, String vc)
static String containerHelpers()
static void   ensureMapArrays()
static void   needArrT(String ec)
static void   needSetT(String ec)
static void   needMapT(String kc, String vc)
static Bool   cIsRef(String c)
static Bool   cIsGC(String c)
static String cOptName(String vc)
```

实现要点：

```xnull
static String cMangle(String c) {
    if c == "int64_t" { return "i" }
    if c == "int" { return "b" }
    if c == "uint8_t" { return "u8" }
    if c == "uint16_t" { return "u16" }
    if c == "uint32_t" { return "u32" }
    if c == "uint64_t" { return "u64" }
    if c == "int8_t" { return "i8" }
    if c == "int16_t" { return "i16" }
    if c == "int32_t" { return "i32" }
    if c == "double" { return "f64" }
    if c == "float" { return "f32" }
    if c == "rt_string *" { return "s" }
    if c.indexOf("xn_Cls_") == 0 && c.length() >= 9 && c.substring(c.length() - 2, 2) == " *" {
        return "o_" + c.substring(7, c.length() - 9)   /* "xn_Cls_" 7 字符，去掉 " *" 2 字符 */
    }
    if c.indexOf("xn_tup_") == 0 { return "t_" + c.substring(7, c.length() - 7) }
    return ""
}
```

> `mangle` 已存在（`xnullc.x:3812-3819`）但它是 **泛型类实例后缀** 的 6 值映射
> （`Int/String/Bool/Char/Double/其他→x`），**不能复用**；K-02 必须新增 `cMangle`，
> 否则类/元组/数值宽度全部撞成 `x`。

```xnull
static String cArrName(String ec) { return "xn_arr_" + cMangle(ec) }
static String cSetName(String ec) { return "xn_set_" + cMangle(ec) }
static String cMapName(String kc, String vc) { return "xn_map_" + cMangle(kc) + "_" + cMangle(vc) }

static void needArrT(String ec) {
    if cMangle(ec) == "" { return }
    if !inNames(C_ARR, ec) { C_ARR.push(ec) }
}
static void needSetT(String ec) {
    needArrT(ec)
    if cMangle(ec) == "" { return }
    if !inNames(C_SET, ec) { C_SET.push(ec) }
}
static void needMapT(String kc, String vc) {
    if cMangle(kc) == "" || cMangle(vc) == "" { return }
    Int i = 0
    while i < C_MAP_K.length() {
        if C_MAP_K.get(i) == kc && C_MAP_V.get(i) == vc { return }
        i = i + 1
    }
    C_MAP_K.push(kc)
    C_MAP_V.push(vc)
}
```

`cIsRef` / `cIsGC` 严格对齐 `containers.go:69-71` 与 `classes_expr.go:72-93`：

```xnull
static Bool cIsRef(String c) {
    return c == "rt_string *" || c == "xrt_bytes_obj *" || c == "xrt_text *" || c == "xrt_sb *" || c.indexOf("xn_Cls_") == 0
}
static Bool cIsGC(String c) {
    if c == "rt_string *" || c == "xrt_bytes_obj *" || c == "xrt_text *" || c == "xrt_sb *" { return true }
    if c.indexOf("xn_Cls_") == 0 {
        return classPolicy(c.substring(7, c.length() - 9)) == "gc"
    }
    return false   /* mangle 不接受的数据枚举/Any/协议不会进入 helper */
}
```

> E2 的 `classPolicy`（`xnullc.x:529-533`）是 sema 策略的近似（`clsHasGC/clsHasCycle`），
> 与 Go `g.policy` 可能有差异；K-02 只能沿用 xnullc 现有判定，风险见 E.1。

`cOptName`：

```xnull
static String cOptName(String vc) {
    if vc == "int64_t" { return "xn_opt_i" }
    if vc == "int" { return "xn_opt_b" }
    if vc == "rt_string *" { return "xn_opt_s" }
    return ""
}
```

## C.3 `cType` 与类型收集插入点

替换 `xnullc.x:409-414` 的四条固定映射为通用分支（放在 `Result` 判断之前）：

```xnull
    if k.indexOf("List<") == 0 || (k.length() > 2 && k.substring(k.length() - 2, 2) == "[]") {
        String ec = cType(listElemKey(k))
        needArrT(ec)
        return cArrName(ec) + " *"
    }
    if k.indexOf("Set<") == 0 {
        String ec = cType(setElem(k))
        needSetT(ec)
        return cSetName(ec) + " *"
    }
    if k.indexOf("Map<") == 0 {
        String kc = cType(mapKeyOf(k))
        String vc = cType(mapValOf(k))
        needMapT(kc, vc)
        return cMapName(kc, vc) + " *"
    }
```

解析辅助（`setElem` 已有 `:849`，`mapVal` 已有 `:854`；建议把 `setElem/mapVal` 改成
`lastClose` 版，并新增 `listElemKey/mapKeyOf/mapValOf`）：

```xnull
static String listElemKey(String k) {
    Int l = k.indexOf("<")
    if l >= 0 {
        Int r = lastClose(k)
        if r > l { return k.substring(l + 1, r - l - 1).trim() }
    }
    if k.length() > 2 && k.substring(k.length() - 2, 2) == "[]" {
        return k.substring(0, k.length() - 2).trim()
    }
    return "Int"
}
static String mapKeyOf(String k) {
    Int l = k.indexOf("<")
    Int c = topComma(k)
    if l < 0 || c < 0 { return "Int" }
    return k.substring(l + 1, c - l - 1).trim()
}
static String mapValOf(String k) {
    Int c = topComma(k)
    Int r = lastClose(k)
    if c < 0 || r < 0 { return "Int" }
    return k.substring(c + 1, r - c - 1).trim()
}
```

> `topComma`（`:340`）/`lastClose`（`:352`）已存在，专门处理嵌套泛型。
> 旧 `mapVal` 用 `indexOf(">")`，遇到 `Map<Int, List<T>>` 会截错；K-02 一并换掉。

局部声明：在 `LocalDeclStmt` 顶部（`xnullc.x:2004-2010`）加一次
`String tyC = cType(ty)`，确保 `List<T>/Set<T>/Map<K,V>` 的局部声明即使走
固定 literal 分支也会登记。不要用它替换现有 `ty` 文本（避免改变 fallthrough 行为）。

`exprType` 里现有的 `isMap/isSet/isArr/isU16List/isObjArr/isTupList` 判定
（`xnullc.x:1084-1121` 等）可以保留；K-02 只改 **生成**，表达式分派放 K-02b。
但 `mapVal`（`:854`）要换成 `mapValOf`，否则 `Map<K, List<...>>` 的返回类型推断错。

## C.4 prewarm 插入点

在 `emitUnit` 里加（不产生 C、不动 `e.tmp`）：

```xnull
static void prewarmTypeKey(String k) {
    if k == "" { return }
    cType(k)
    if isResult(k) {
        prewarmTypeKey(resultVal(k))
        prewarmTypeKey(resultErr(k))
    }
}
static void prewarmContainers(N unit) {
    N ds = fld(unit, "Decls")
    Int i = 0
    while i < ds.el.length() {
        N d = ds.el.get(i)
        if d.nm == "TopFunc" {
            N ps = fld(d, "Params")
            Int j = 0
            while j < ps.el.length() { prewarmTypeKey(typeKey(fld(ps.el.get(j), "Type"))); j = j + 1 }
            prewarmTypeKey(retKey(d))
        }
        if d.nm == "ClassDecl" {
            N fs = fld(d, "Fields")
            Int j = 0
            while j < fs.el.length() { prewarmTypeKey(typeKey(fld(fs.el.get(j), "Type"))); j = j + 1 }
            N pp = fld(fld(d, "Primary"), "Params")   /* primary 参数是隐式字段 */
            j = 0
            while j < pp.el.length() { prewarmTypeKey(typeKey(fld(pp.el.get(j), "Type"))); j = j + 1 }
            N ms = fld(d, "Methods")
            j = 0
            while j < ms.el.length() {
                N m = ms.el.get(j)
                N mps = fld(m, "Params")
                Int k2 = 0
                while k2 < mps.el.length() { prewarmTypeKey(typeKey(fld(mps.el.get(k2), "Type"))); k2 = k2 + 1 }
                prewarmTypeKey(retKey(m))
                j = j + 1
            }
        }
        if d.nm == "StructDecl" || d.nm == "SingletonDecl" {
            N fs = fld(d, "Fields")
            Int j = 0
            while j < fs.el.length() { prewarmTypeKey(typeKey(fld(fs.el.get(j), "Type"))); j = j + 1 }
        }
        if d.nm == "FactoryDecl" {
            N ms = fld(d, "Methods")
            Int j = 0
            while j < ms.el.length() {
                N m = ms.el.get(j)
                N mps = fld(m, "Params")
                Int k2 = 0
                while k2 < mps.el.length() { prewarmTypeKey(typeKey(fld(mps.el.get(k2), "Type"))); k2 = k2 + 1 }
                prewarmTypeKey(retKey(m))
                j = j + 1
            }
        }
        i = i + 1
    }
}
```

调用点：`emitUnit` 里 `scanTupleTypes(unit)`（`:5062`）之后、**任何 typedef 选择之前**：

```xnull
scanTupleTypes(unit)
prewarmContainers(unit)
Int ri = 0
while ri < sc.resultTypes.length() { prewarmTypeKey(sc.resultTypes.get(ri)); ri = ri + 1 }
```

> 只按 Go `prewarmTypeContainers` 的范围（字段/方法/Result）扫；**不要**把
> `Ctors`（secondary ctor）加进去，否则会改变“只在构造器原型里出现的容器”
> 的 typedef 位置（Go 会把它留到 helper 段）。primary 参数按字段处理，与 Go
> `collectClass`（`classes.go:310-330`）一致。

`emitUnit` 开头重置（`:4855` 附近）：

```xnull
C_ARR = []
C_SET = []
C_MAP_K = []
C_MAP_V = []
C_DECL = []
```

## C.5 发射阶段插入点

### C.5.1 class 分支（`CLS_NAMES.length() > 0`，`:5040-5231`）

保持现有结构（它已与 Go 的 classes 输出 0 diff）：

```
pass0: 类 typedef → [新增] tuple typedef → [替换 cbType] containerTypedefsAll()
pass1: 类 typedef → 构造器/方法原型
rtd = resultTypedefsSorted(sc)
[新增] cth = containerHelpers()      // 内部先 ensureMapArrays
res = ... fwj + rtd + cth + tfp + ...
```

具体改动：

1. 删除 `cbKey/cbType/cbHelp/mapSI` 选择块（`:5120-5162`）。
2. 在 `String tfp = topFuncProtos(decls)`（`:5153`）**之前**计算：
   ```xnull
   String ctn = containerTypedefsAll()
   ```
   ——必须在 `fw` 循环之前，才能和 Go 一样把“构造器原型里才出现的容器”留到 helper 段。
3. `fw` pass0 的 `if pass == 0 && cbType != ""`（`:5176`）替换为：
   ```xnull
   if pass == 0 {
       if TUPLE_KEYS.length() > 0 { fw.push(tupleTypedefs().trim()); fw.push("") }
       if ctn != "" { fw.push(ctn.trim()); fw.push("") }
   }
   ```
   `ctn` 已在第 2 步算好；`containerTypedefsAll()` 会写 `C_DECL`，**不能**在这里再调一次
   （第二次会返回空串）。
   注意 `joinLines`（`:2957-2961`）会在每个 `fw` 元素后**无条件追加一个 `\n`**。
   `containerTypedefsAll()` / `tupleTypedefs()` 内部各 typedef 之间已用 `\n\n` 分隔，
   但末尾也会带 `\n\n`；直接 `fw.push` 会多出一个空行。因此必须：
   - 先 `.trim()` 去掉尾部换行，再 `fw.push(...)`；
   - 紧跟一个 `fw.push("")` 生成与 Go 相同的“typedef 块后一个空行”。
   最终以 `classes.x` 的 396/398/485 行位置逐字节校准。
4. `String rtd = resultTypedefsSorted(sc)`（`:5229`）之后、`res` 拼接之前：
   ```xnull
   String cth = containerHelpers()
   ```
   `containerHelpers()` 内部顺序：
   - `ensureMapArrays()`
   - 数组（排序）→ Set（排序）→ Map（按 mangle 键排序）
   - 若 `inNames(C_ARR, "rt_string *")`，追加 `STR_SPLIT_HELPER`（见 C.6：
     阶段 3 前把现有 `xn_str_split` 文本从 `PRELUDE_MAPSET` 提成独立常量，
     不要再依赖 prelude 截取）
5. `res` 拼接（`:5231`）把 `(cbHelp != "" ? cbHelp + "\n" : "")` 换成 `cth`。
6. 删除 class 分支里 `mapSITypedef/arrSBlock/mapSIBlock` 的使用；这些函数在阶段 3 删除。

### C.5.2 非 class 容器分支（`xnullc.x:5456-5461`）

阶段 2 可先“拆 typedef”：用 marker 把 `PRELUDE_ARR/MAPSET/CONT` 拆成
`HEAD`（到第一个容器 typedef 之前）与 `TAIL`（从 `static void xn_arr_i_deinit` 开始）：

```xnull
static String preludeHeadOf(String p, String firstTypedef) {
    Int i = p.indexOf(firstTypedef)
    if i < 0 { return p }
    return p.substring(0, i)
}
static String preludeTailOf(String p, String firstHelper) {
    Int i = p.indexOf(firstHelper)
    if i < 0 { return "" }
    return p.substring(i, p.length() - i)
}
/* 例：firstTypedef = "typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;" */
/*     firstHelper  = "static void xn_arr_i_deinit" */
```

阶段 2 组装（临时）：

```xnull
String base = preludeHeadOf(legacy, arrITypedefMarker)
String tail = preludeTailOf(legacy, "static void xn_arr_i_deinit")
res = base + containerTypedefsAll() + tail
```

> 阶段 2 的 `containerTypedefsAll()` 要临时跳过 `xn_arr_s`（`C_LEGACY_OWNED`），
> 因为 `PRELUDE_*` 的 `TAIL` 里仍带着固定 `xn_arr_s` typedef/helper；否则重复定义。
> 阶段 3 删除固定文本后去掉这个跳过。`PRELUDE_TARR`/`usesAny` 分支阶段 2 不动。

阶段 3 改成统一组装：

```xnull
res = PRELUDE_PRE_A + protoTypedefs() + PRELUDE_B1 + fnTypedefs()
    + enumTypedefs() + PRELUDE_B2 + enumNameDefs() + PRELUDE_B3
    + PRELUDE_FATAL_MID
    + [tupleTypedefs() 若有]
    + containerTypedefsAll()
    + resultTypedefsSorted(sc)
    + containerHelpers()
    + topFuncProtos(decls)
    + "static int64_t xn_main();\n"
    + PRELUDE_TAIL
```

顺序理由（对齐 `codegen.go:725-793`）：
typedef 块（类/元组/容器/Result）→ helper → 顶层原型 → `xn_main` 原型 → 函数体。
当前非 class 固定 prelude 把 helper 放在 `xn_main` 原型之前，动态版保持一致。

### C.5.3 其他分支

| 分支 | 行（约） | 插入规则 | 现有 fixture |
|---|---|---|---|
| `DATA_ENUM_NAMES` | 5232-5244 | `de.ls`（数据枚举 typedef）之后、`PRELUDE_FATAL_MID` 之后插 `containerTypedefsAll()`；`dme.ls` 之前插 `containerHelpers()` | 无 |
| `SINGLE_NAMES` | 5245-5293 | `fw` 目前把单例 typedef 与原型混排；若覆盖单例字段容器，需先拆 typedef 段再插 ctn，否则原型引用未知类型 | 无 |
| `ENUM_NAMES` | 5294-5295 | 枚举 mangle 拒绝；可暂不接 | 无 |
| `STRUCT_NAMES` | 5296-5450 | `ee.ls`（结构体 typedef）之后插 `ctn`；`me.ls`（方法）之前插 `cth` | 无 |
| `usesAny` | 5452-5453 | 直接 `PRELUDE_ANY`，会丢容器；K-02 不覆盖，列为风险 | 无 |
| `usesTArr` | 5454-5455 | 用 `tupleTypedefs() + ctn + cth` 替换固定 `PRELUDE_TARR`；保持 `(Int,Int)` fixture 0 diff | `tuple/in_list.x` |
| `usesList/hasMap/hasSet` | 5456-5461 | 见 C.5.2 | container 5 个 |
| 通用分支 | 5462-5515 | `tupleTypedefs()` 之后插 `ctn`；`resultTypedefsSorted` 之后插 `cth` | — |

> K-02 的验收入口只落在 **class 分支** 与 **usesList/hasMap/hasSet 分支**。
> 其他分支按同一原则接，但必须各自补 fixture 后才能宣称支持。

## C.6 固定文本兼容/替换策略

阶段 1（登记层）：

- 加 `C_*` + `cMangle` + `need*` + `prewarm` + `containerTypedefsAll/Helpers` 的**骨架**，
  但 `cType` 仍返回旧的四条固定名（`List<Int>→xn_arr_i *` 等）；不调用新生成函数。
- 验证：所有现有 0 diff 保持；`classes 0 / app 99 / f2 1412` 不变。

阶段 2（typedef 层）：

- `cType` 切到通用分支；class 分支用 `containerTypedefsAll` 替换 `cbType`；
  非 class 用 `HEAD + ctn + TAIL` 拆分。
- 临时跳过 `xn_arr_s`（class 的 `arrSBlock` / 非 class 的 `TAIL` 仍拥有它）。
- 验证：`classes.x` 必须仍 0；container 5 个仍 0；`app/f2` 允许仍非 0（helper 未接）。

阶段 3（helper 层）：

- `containerHelpers()` 接管全部 helper；删除：
  `containerTypedef`、`mapSITypedef`、`arrSBlock`、`mapSIBlock`、`u16ArrHelperText`、
  `arrIHelperText`、`classArrHelperText`，以及 `PRELUDE_ARR/MAPSET/CONT/TARR` 中的
  容器 typedef/helper 文本。
- 保留 `PRELUDE_PRE_A/B1/B2/B3/FATAL_MID/TAIL`、`strReplaceBlock`。
- 在删除 `PRELUDE_MAPSET` 之前，把其中 `xn_str_split` 的函数文本提成独立常量
  `STR_SPLIT_HELPER`（或直接内联到 `containerHelpers`），由 `containerHelpers`
  按 `arr_s` 条件追加；否则 `strSplitBlock()` 的 `indexOf` 会失效。
- 验证：`classes/f2/app` 全 0；container 5、bundle 4、tuple 5 全 PASS。

## C.7 去重、排序、空行

- **去重**：`C_ARR/C_SET` 用 `inNames`；Map 用 K/V 平行扫描；`C_DECL` 防 typedef 重复。
  三类 helper 生成时都要检查 `C_DECL`：若名字不在其中，先输出 typedef 再输出 helper
  （Go 的 `skipDecl` 参数同时存在于数组 `:277`、Set `:377`、Map `:472`；数组的晚 typedef
  来自 `ensureMapArrays`，Set/Map 的晚 typedef 来自 Result 等后登记路径）。
- **排序**：用 `strLess`（`:244-255`，ASCII 逐字符）而不是 `cmpName`（`:4103`，
  `chRank` 把数字排在字母后，与 Go `sort.Strings` 不同）。
  插入排序照抄 `fnTypedefs`（`:268-278`）的写法：

  ```xnull
  static void sortStrList(List<String> xs) {
      Int a = 1
      while a < xs.length() {
          String x = xs.get(a)
          Int b = a
          while b > 0 && strLess(x, xs.get(b - 1)) { xs.set(b, xs.get(b - 1)); b = b - 1 }
          xs.set(b, x)
          a = a + 1
      }
  }
  ```

- **Map 排序**：按 `cMangle(kc) + "|" + cMangle(vc)` 排平行数组；不能直接按
  `cMapName` 排（分隔符 `_` 与 Go 的 `|` 在部分前缀下序不同）。

  ```xnull
  static void sortMapPairs() {
      Int a = 1
      while a < C_MAP_K.length() {
          String kx = C_MAP_K.get(a); String vx = C_MAP_V.get(a)
          String xk = cMangle(kx) + "|" + cMangle(vx)
          Int b = a
          Bool go = true
          while b > 0 && go {
              String pk = cMangle(C_MAP_K.get(b - 1)) + "|" + cMangle(C_MAP_V.get(b - 1))
              if strLess(xk, pk) {
                  C_MAP_K.set(b, C_MAP_K.get(b - 1)); C_MAP_V.set(b, C_MAP_V.get(b - 1)); b = b - 1
              } else { go = false }
          }
          C_MAP_K.set(b, kx); C_MAP_V.set(b, vx)
          a = a + 1
      }
  }
  ```

- **空行**：每个 typedef 以 `;\n\n` 结束；每个 helper 块以 `\n\n` 结束（Map 的
  `M_get` 后面 Go 会直接接 `xn_str_split`，保持 `\n\n` 即可）；不要在块之间额外加空行。

---

# D. 一次性迁移顺序与验证 fixture

## D.0 基线快照（施工前）

```bash
cd /Users/vjs/Desktop/XNull-Lang/impl && go build -o /tmp/xnull-orc ./cmd/xnull && go build -o /tmp/xnast-orc ./cmd/xnast
X=/Users/vjs/Desktop/XNull-Lang/wt/e2-sema/impl/lib/b3/xnullc.x
# 单文件
/tmp/xnull-orc run --interp "$X" -- examples/classes.x \
  "$(/tmp/xnast-orc --ast examples/classes.x)" \
  "$(python3 tests/b3/xfb-projection.py examples)" > /tmp/xn-classes.c
# 多文件
/tmp/xnull-orc --emit-ast-bundle difftest/anchors/cases/pkg/f2.x > /tmp/f2.bundle.json
/tmp/xnull-orc run --interp "$X" -- difftest/anchors/cases/pkg/f2.x \
  "$(/tmp/xnast-orc --ast difftest/anchors/cases/pkg/f2.x)" \
  "$(python3 tests/b3/xfb-projection.py difftest/anchors/cases/pkg)" \
  "$(cat /tmp/f2.bundle.json)" > /tmp/xn-f2.c
# app.x 同理（tests/b3/fixtures/bundle）
```

记录：`classes 0`、`f2 1412`、`app 99`（本文基线）。所有后续 diff 以同一 oracle
二进制/同一 xnullc 源比较，临时号归一化只用于看“首因”，验收仍看 raw cmp。

## D.1 阶段 1：registry / need* / prewarm（零输出变化）

改动：
1. `C_*` 全局 + `cMangle/cArrName/...` + `need*`。
2. `cType` 里**仍走旧固定返回**，但在四个已知分支各调用一次 `need*`（让注册表开始有数据）。
3. `prewarmContainers` 调用放在 `scanTupleTypes` 后；`emitUnit` 开头重置 `C_*`。
4. 不接 `containerTypedefsAll/Helpers`。

验证：

- `tests/b3/xnullc-containers.sh` → 5/5 PASS。
- `tests/b3/xnullc-bundle.sh` → 4/4 PASS。
- `tests/b3/xnullc-tuple.sh` → 5/5 PASS。
- `classes` 0、`app` 99、`f2` 1412 不变。
- 任何 temp 编号变化 = FAIL（本阶段不应生成任何新文本）。

## D.2 阶段 2：动态 typedef 替换固定 typedef

改动：
1. `cType` 切到通用分支（C.3）。
2. class 分支：**保留** `cbKey/cbHelp` 选择（`:5120-5162`）作为阶段 2 的 helper 来源，
   只删除 `cbType = containerTypedef(cbKey)` 与 `mapSITypedef()` 的 typedef 输出，
   在 pass0 改插 `ctn`（C.5.1 第 2/3 步）。`cbHelp` 仍由
   `arrIHelperText/arrSBlock/mapSIBlock/...` 提供，直到阶段 3 才整体删除。
3. 非 class：`PRELUDE_ARR/MAPSET/CONT` 用 `HEAD + ctn + TAIL`（C.5.2），临时跳过 `xn_arr_s`。
4. `containerTypedefsAll` 先用固定 helper 文本配合；阶段 2 不调用 `containerHelpers()`。

验证：

- **必须仍 0**：`examples/classes.x`、`tests/b3/fixtures/container/{array,list,mapset,containers,oob}.x`。
- `tests/b3/fixtures/bundle/app.x`：应只剩 `xn_arr_u16` helper 差异（typedef 已补上）。
- `f2.x`：`xn_map_s_s` typedef 应出现，但 helper 仍缺 → diff 从 1412 下降但不要求 0。
- `tests/b3/xnullc-bundle.sh` 4/4（**显式包含 bundle_text 非 ASCII 回归**）、
  `tuple 5/5` 不回归。
- 重点看 typedef 块位置：`classes` 396/398/485、`f2` 401/431、`app` 398/400 必须逐字节对上。

## D.3 阶段 3：动态 helper

改动：
1. `containerHelpers()` 接管数组/Set/Map 全部 helper（B 节模板）。
2. `ensureMapArrays` 在 helper 生成开头调用。
3. `strSplit` 由 `inNames(C_ARR, "rt_string *")` 控制。
4. 删除旧 helper 函数与固定 prelude 容器段；去掉 `xn_arr_s` 临时跳过。
5. 非 class 分支统一组装（C.5.2 阶段 3）。

验证（K-02 验收）：

| Fixture | 期望 |
|---|---|
| `examples/classes.x` | raw diff **0**（保持） |
| `difftest/anchors/cases/pkg/f2.x` | raw diff **0**（1412 → 0） |
| `tests/b3/fixtures/bundle/app.x` | raw diff **0**（99 → 0） |
| `tests/b3/fixtures/container/*.x` | 5/5 PASS |
| `tests/b3/fixtures/tuple/in_list.x` | PASS（固定 `(Int,Int)` 形状） |
| `tests/b3/xnullc-bundle.sh` | 4/4 PASS（含 bundle_text 非 ASCII 回归） |
| `tests/b3/xnullc-ffi/err/mem/obj*.sh` | 不回归 |

全量门禁（切片并发，禁止串行）：

```bash
tests/b3/xnullc-all.sh --all-shards 4 --parallel 4
python3 tests/b3/xnullc_all.py --aggregate --baseline handoff/B3-09-baseline.tsv
```

> `xnullc_all.py` 的 `cause_of` 会把 `typedef struct { rt_header` 归到 K-02；
> 验收要求 K-02 计数下降且目标三入口 0，不是只看总 diff 行数。

## D.4 每阶段提交建议

- 阶段 1：`feat(b3): K-02 容器 registry/need*/prewarm（无输出变化）`
- 阶段 2：`feat(b3): K-02 动态容器 typedef（classes/container 保持 0）`
- 阶段 3：`feat(b3): K-02 动态容器 helper（f2/app 归零）`

每阶段附 `evidence/B3-09-03/` 的 summary + diff 行数；单卡 30 分钟规则照旧。

---

# E. 风险

## E.1 类元素：GC vs ARC（最高风险）

- Go 判定：`isRef(E)` 为真（类指针），`arc = ref && !isGCTypeC(E)`。
  `isGCTypeC` 看 `g.policy`（sema 策略），`classIsGC`（`classes_expr.go:24-31`）。
- E2 判定：`cIsGC` 用 `classPolicy`（`xnullc.x:529-533`），是
  `clsHasGC`（字段是否含 `String/容器/Any/...`）+ `clsHasCycle` 的近似。
- 后果：若 E2 把 ARC 类判成 GC，容器 `deinit/clear/remove` 不 release → 泄漏；
  反之会 double free。类含 `String` 字段时 Go 判 GC，E2 `fieldIsGC` 也判 GC；
  纯 Int 类两边都 ARC。**边界：类含 `Bytes/Text/协议/容器` 等** E2 的
  `fieldIsGC` 已覆盖；但含 GC 父类/数据枚举字段的传播可能不同。
- 验证：新增 fixture
  - `class A { Int v }`（ARC）`List<A>` push/clear/remove → 期望 `A-deinit` 立即打印；
  - `class B { String s }`（GC）`List<B>` → 期望 deinit 由 GC 回收；
  - 与 `impl/internal/codegen/container_gc_test.go` 的三个用例同口径。

## E.2 String key/相等比较

- String 的 `find`/`eq` 是 **字节相等**：`a->len == b->len && memcmp(a->bytes,b->bytes,len)==0`；
  不是 `strcmp`（可能有 NUL），不是 Unicode 规范化。
- `M_cmp_key(String)` 是字节字典序 + 长度兜底；`keys()/values()` 依赖它。
- `Set<Class>` / `Map<Class,V>` 在 Go 里会走 `isRef` 的 String 分支，生成
  `->len/->bytes`，**非法 C**。E2 不要“顺手修好”：K-02 要求 parity，修它会改变
  oracle 行为并需要 Go 侧先行。若 E2 决定拒绝这类组合，需在文档/诊断里写清楚，
  并确保不影响现有 fixture。

## E.3 元组

- 元组 C 类型是 `xn_tup_<elems>`；mangle 为 `t_<elems>`；数组/Map 值可用。
- 元组 typedef 必须先于容器 typedef：Go `emitTupleTypes` 在 `emitTypeDecls` 前
  （`codegen.go:726-743`）。xnullc 目前只在通用分支输出 tupleTypedefs（`:5454-5456`），
  class 分支没有；K-02 必须在 class 分支 pass0、`ctn` 之前补 `tupleTypedefs()`，
  否则 `List<(Int,Int)>` 在 class 程序里会引用未定义类型。
- Go 的 `isRef(tuple)` 为 false：元组元素里的 String/类引用 **不会被容器 scan/retain/release**。
  这是 Go 现状，E2 不要额外加 scan（会改变 `RT_TYPE_*` 文本与 GC 行为）。
- `Set<Tuple>` / `Map<Tuple,V>` 的 `==` 非法；`join` 元组为空串。按 Go 复刻即可。

## E.4 容量 / 越界 / fatal

- 数组/Map 的 `new(cap)`：`cap ? cap : 4`；Set 固定 `arr_new(4)`。
- `push/insert/put` 满时 `cap *= 2`，`realloc` 失败 `abort()`。
- `get/set/remove/at`：`i < 0 || (size_t)i >= len` → `xn_fatal_oob()`；
  `insert` 允许 `i == len`。
- `Map.remove` / `Set.remove` 未找到返回 0；数组 `remove` 返回被删元素。
- E2 生成文本必须保留 `exit(134)` 的 `xn_fatal_oob`（`PRELUDE_FATAL_MID` 已定义），
  不得改成 assert/返回默认值。

## E.5 GC scan 回调

- 数组：`RT_TYPE_N` 的 scan 槽 = `N_scan`（`isRef`）或 `NULL`；
  `N_scan` 必须判 `data==NULL`。
- Set：`RT_TYPE_S` 的 scan 恒为 `S_scan`，`S_scan` visit 的是内部数组对象（不是元素）。
- Map：scan 恒有；按 `isRef(K)/isRef(V)` 分别生成 keys/vals 循环；`NULL` 判空。
- 三者的 `rt_type` 首字段字符串分别是 `"List"`、`"Set"`、`"Map"`；`sizeof` 用容器类型。
- 不要给值元素容器生成 scan（会改变 `RT_TYPE_*` 文本，直接 diff）。

## E.6 helper 命名冲突

- 固定 prelude 已定义 `xn_arr_i/xn_arr_s/xn_arr_u16/xn_set_i/xn_map_s_i` 的
  `RT_TYPE_*`/helper；动态生成必须**只保留一份**。
- 阶段 2 的临时跳过 `xn_arr_s`（见 C.6）是必须的，否则 `classes.x` 会重复定义。
- `xn_str_split` 是全局固定 helper，不属于 `C_*`；只允许一处，按 `arr_s` 条件输出。
- `xn_str_replace` 由 `needStrReplace` 控制，K-02 不要重复生成。

## E.7 临时号（temp）绝对不能被影响

- 所有 registry/prewarm/typedef/helper 函数必须**不调用** `EM.nt()`、不修改 `EM.tmp`。
- 生成顺序保持在函数体/类方法体之后；`e.tmp` 只在表达式生成时变化。
- 验证：任何阶段如果 `xn_tN` 整体平移，先回退检查是否在 prewarm/拼字符串时用了 `e.add`/`e.nt`。
- `scanTupleTypes`/`prewarmContainers` 是纯遍历，不产生 C，也不分配 temp。

## E.8 Go 自身的已知 bug / 限制（不要“修”）

1. `Map.put` 覆盖时对 ARC key 执行 `rt_release(m->keys[i])`，但 keys 数组仍保留该指针
   （`containers.go:512-527` 的 `%[8]s`）——潜在悬垂；E2 复刻以保持 parity。
2. `Set<Class>` / `Map<Class,V>` 的相等比较非法 C（E.2）。
3. `mapTypes`（`containers_expr.go:259-270`）用“首字符/末字符”反解 C 名，只适配单字符
   mangle：`xn_map_u16_i` 会把 key 解成空，`xn_map_s_o_A` 会把 value 解成空。
   K-02 的生成器应维护 `C_NAME → 类型` 注册（或 `C_MAP_K/C_MAP_V` 平行数组），
   不要依赖字符串反解；表达式层（K-02b）也应改用这套注册表。
4. `Map<Int,List<T>>` 等嵌套容器被 mangle 拒绝。
5. 数据枚举/Any/协议/Bytes 作为元素被 mangle 拒绝；Go `isRef` 也没覆盖
   `xn_Enum_* *` / `xn_Any *`，即使将来放开 mangle 也需要先修 GC 扫描。

## E.9 xnullc 表达式路径仍是硬编码（K-02b）

即使 typedef/helper 生成器完成，下列仍只认 `s_i/i/u16/objArr`，任意 K/V 的
方法调用/字面量还不会走对 helper：

| 位置 | 行 | 硬编码 |
|---|---|---|
| `expr` Index | 1356 | `xn_arr_i_get` |
| Map.get/getOr/has | 1483-1514 | `xn_map_s_i_get/get_or/has` |
| Set add/has/length | 1476/1513/1520 | `xn_set_i_*` |
| 数组 get/remove | 1487-1526 | `xn_arr_i/u16_*` |
| 数组/Set/Map 字面量 | 2085-2155 | `xn_arr_u16/i`、`xn_set_i`、`xn_map_s_i` |
| 下标赋值 | 2328/2403 | `xn_arr_i_set` |
| push/clear/put/set 语句 | 2377-2403 | 同上 |
| `containerTypedef` 调用 | 4192 | 只认三种 key |

**K-02 验收不要求这些全改**（`classes/f2/app` 的调用点恰好落在已有硬编码面），
但下一步 K-02b 必须按 `cType(recvKey)` + `cArrName/cSetName/cMapName` 统一分派，
并用 `mapKeyOf/mapValOf` 取 K/V 类型，不能再按 C 名猜。

---

# 附录：可直接对照的期望片段

## F.1 `examples/classes.x`（Go C）

```
396: typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;
398: typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;
485: typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;
```

`xn_arr_s` 在 helper 段（`ensureMapArrays` 的晚 typedef），E2 不要在 398 前提前输出。

## F.2 `f2.x`（Go C）

```
401: typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; rt_string * *vals; } xn_map_s_s;
431: typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;
```

构造函数原型必须变成：

```c
static xn_Cls_Request *xn_Cls_Request_new(rt_string * xn_p_method, rt_string * xn_p_url, xn_map_s_s * xn_p_headers, xrt_bytes_obj * xn_p_body);
```

当前 E2 是 `int64_t xn_p_headers`（首条 diff）。

## F.3 `tests/b3/fixtures/bundle/app.x`（Go C）

```
398: typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;
400: typedef struct { rt_header hdr; size_t len; size_t cap; uint16_t *data; } xn_arr_u16;
```

`arr_u16` helper 与 `arr_i` 同一模板，只是 `E=uint16_t`、`mangle=u16`、`join` 空串；
E2 必须同时输出两个数组实例（当前 `cbKey` 单实例选不中）。

## F.4 `tests/b3/fixtures/container/mapset.x`（Go C）

```
394: typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;
396: typedef struct { rt_header hdr; xn_arr_i *a; } xn_set_i;
398: typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;
480: typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;
```

这是“全部容器主块 + Map 键数组晚 typedef”的最小样例；阶段 2/3 先跑它。
