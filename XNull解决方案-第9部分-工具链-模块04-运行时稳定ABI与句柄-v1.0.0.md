# XNull 解决方案 第 9 部分：工具链（模块 04：运行时稳定 ABI 与句柄）

> 本文是第 9 部分模块 04，只落实第 3 部分 §22 与第 7 部分 §6 已定义的运行时 ABI 合同；内部实现选择不构成语言语义；与第 1—8 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 9 部分（T9） |
| 模块 | 04 运行时稳定 ABI 与句柄 / 10 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—8 部分约束） |
| 文档性质 | 第 9 部分模块详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 设计依据 | 第 3 部分 §22、第 7 部分 §6 |
| 组件 | `xrt.h` / `xrt_abi.c`：运行时对外稳定 ABI、句柄、字符串、Bytes、根/安全点、fatal |
| 上游输入 | 编译器生成代码、FFI 包装、绑定层、原生侧 |
| 下游输出 | 稳定符号、对象管理入口、句柄生命周期、fatal |
| 明确不含 | 运行时内部实现（模块 03）、FFI 合同校验（模块 05）、C 编译/链接（模块 06） |
| 配套文档 | 第 9 部分总览；模块 03、05 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。冻结稳定 ABI 面、初始化顺序、句柄/字符串/根/弱表合同。 |

---

## 0. 定位

`xrt.h` 是 XNull 运行时对外的**唯一稳定 ABI 头**：

- 编译器生成代码、FFI 包装、绑定层、原生侧只经 `xrt_*` 管理内存；
- 内部实现头 `rt.h` 不随 SDK 分发；
- 符号与签名一经定稿冻结，变更走主版本；
- 本层是薄封装，语义不重写：终结链、计数、根登记仍由内部运行时承担。

```
生成代码 / 绑定层 / 原生侧
        │  只 include xrt.h
        ▼
   xrt_* 稳定 ABI
        │  薄封装
        ▼
   rt_* 内部运行时
```

---

## 1. ABI 类型

### 1.1 对象种类

```c
typedef enum {
    XRT_KIND_ARC = 1,
    XRT_KIND_GC  = 2
} xrt_kind;
```

数值是 ABI 面的一部分，不得随意改变。

### 1.2 类型描述符

```c
typedef struct xrt_type {
    const char *name;
    size_t      payload_size;
    void      (*deinit)(void *payload);
    void      (*scan)(void *payload, void (*visit)(void *ref));
} xrt_type;
```

- 字段布局与内部 `rt_type` 同构；
- 调用方只应使用编译生成的描述符，不手工解释字段；
- GC 描述符必须有 `scan`；
- `scan` 参数为完整对象指针，与 `deinit` 同约定。

### 1.3 不透明类型

```c
typedef struct xrt_string    xrt_string;
typedef struct xrt_weak_slot xrt_weak_slot;
typedef struct xrt_handle    xrt_handle; /* 定义见句柄 */
```

- 字符串长度/字节经访问器获取；
- 弱槽位仅合同层使用；
- 句柄是不透明对象。

### 1.4 Bytes

```c
typedef struct xrt_bytes {
    void  *data;
    size_t len;
} xrt_bytes;
```

- 边界缓冲区表示；
- 长度显式，不以 NUL 为合同；
- 数据所有权按租约声明。

---

## 2. 初始化

```c
void xrt_runtime_init(void);
```

合同：

- 幂等；
- 在创建任何对象之前调用；
- `xrt_safepoint` 可用前不得创建对象；
- 完整嵌入 API 非承诺；只承诺符号与最小初始化顺序。

初始化顺序：

```
xrt_runtime_init
  → 可分配对象
  → 可调用 safepoint
  → 可登记根/任务根
```

违反顺序属调用方违约。

---

## 3. 分配与计数

| 函数 | 合同 |
| --- | --- |
| `void *xrt_alloc(xrt_kind kind, const xrt_type *type)` | 分配对象；GC 必须有 scan；计数从 1 起 |
| `void *xrt_retain(void *obj)` | 原子 +1；NULL 返回 NULL；已终结 → fatal |
| `void xrt_release(void *obj)` | 原子 -1；到 0 触发终结链；NULL/已终结安全返回 |
| `int64_t xrt_refcount(void *obj)` | 诊断用；NULL 返回 0 |

约束：

- 不得绕过分配头直接操作计数/标记；
- ARC/GC 均经此分配；
- 终结链语义由 03 定义；
- 分配失败/复活检测 → `xrt_fatal`。

---

## 4. 弱表

| 函数 | 合同 |
| --- | --- |
| `xrt_weak_slot *xrt_weak_bind(void *target)` | 建立弱槽位，不持强引用 |
| `void *xrt_weak_read(xrt_weak_slot *slot)` | 目标终结后返回 NULL |
| `void xrt_weak_clear(xrt_weak_slot *slot)` | 摘除/清除槽位 |

限制：

- 弱表是运行时内部机制；
- 入口只对 FFI 合同层开放，原生代码不得直接调用；
- 源码与 XDK 公共 API 不暴露弱引用；
- 槽位不阻止回收；
- 读不到已终结目标。

---

## 5. 写屏障、根、安全点

| 函数 | 合同 |
| --- | --- |
| `void xrt_write_barrier(void *obj)` | 存活校验；并发期扩展为增量屏障 |
| `void xrt_register_root(void *obj)` | 全局根登记（静态/顶层/单例/枚举项） |
| `void xrt_unregister_root(void *obj)` | 根注销；未登记 no-op |
| `void xrt_safepoint(void)` | 回收会合点；刷新隔离区 |

约束：

- 编译器在生成代码中登记全局根；
- ARC 持 GC 引用的对象走扫描链；
- 安全点覆盖挂起点/分配点/调用边界；
- 根登记幂等；
- 不得在根表中保留已终结对象。

---

## 6. 任务根

| 函数 | 合同 |
| --- | --- |
| `void xrt_task_root_bind(void *obj)` | 任务/回调 env 登记为根 |
| `void xrt_task_root_unbind(void *obj)` | 注销根 |

用途：

- 任务闭包 env 在任务存活期间可达；
- trampoline env 在回调注册期间可达；
- 注销后原生再调用属合同违规（由 FFI 层检测）。

---

## 7. 字符串

| 函数 | 合同 |
| --- | --- |
| `xrt_string *xrt_string_new(const char *utf8, size_t len)` | 复制构造 UTF-8 字符串 |
| `xrt_string *xrt_string_from_c(const char *cstr)` | 以 NUL 结尾 C 串构造 |
| `xrt_string *xrt_string_alloc(size_t len)` | 定长、内容未初始化、NUL 结尾；`len` 权威 |
| `size_t xrt_string_len(const xrt_string *s)` | 字节长度 |
| `const char *xrt_string_bytes(const xrt_string *s)` | 字节指针 |
| `const xrt_type *xrt_type_string_descriptor(void)` | String 类型描述符 |

合同：

- UTF-8；
- `len` 为权威长度；
- NUL 仅为 C 便利；
- 字符串 ARC 管理；
- 字节区免扫描；
- 返回所有权按构造/借用规则。

---

## 8. 句柄

### 8.1 类型

```c
typedef struct xrt_handle xrt_handle;
```

句柄是普通 ARC 对象，载荷：

```c
typedef struct {
    void  *native;
    void (*close_fn)(void *native);
    int    closed;
} handle_payload;
```

- 原生对象不进入 ARC/GC；
- 原生指针不被 scan 枚举；
- 句柄不参与算术/排序/序列化。

### 8.2 函数

| 函数 | 合同 |
| --- | --- |
| `xrt_handle_new(native, close_fn, what)` | 创建句柄；`native == NULL` 视为已关闭 |
| `xrt_handle_native(h)` | 已关闭/空 → NULL |
| `xrt_handle_close(h)` | 幂等；重复关闭成功；不重复触达原生 |
| `xrt_handle_mark_closed(h)` | 原生已关闭，只登记状态 |
| `xrt_handle_is_closed(h)` | 是否已关闭 |

### 8.3 生命周期

- `close` 显式；
- `deinit` 不自动 close，只诊断泄漏；
- 已关闭句柄再取原生指针返回 NULL；
- 关闭失败不等于未关闭（状态照常登记，错误由调用方处理）；
- 跨任务共享需同步或所有权移交；
- 句柄泄漏诊断输出到 stderr。

---

## 9. fatal

```c
void xrt_fatal(const char *reason);
```

用于：

- 跨界违约；
- 复活检测；
- 终结链 panic；
- 分配失败/越界检测；
- 调用方合同违规。

默认打印后 `abort`；宿主可安装处理器（测试/嵌入）；处理器需自行终止。

---

## 10. 内部映射

| 稳定 ABI | 内部实现 |
| --- | --- |
| `xrt_alloc` | `rt_arc_new`/`rt_gc_new` |
| `xrt_retain/release/refcount` | `rt_*` |
| `xrt_weak_bind/read/clear` | `rt_weak_*` |
| `xrt_write_barrier` | 存活校验（并发期扩展） |
| `xrt_register_root/unregister_root` | `rt_gc_root_*` |
| `xrt_safepoint` | `rt_quarantine_flush` |
| `xrt_task_root_bind/unbind` | 根登记/注销 |
| `xrt_string_*` | `rt_string_*` |
| `xrt_type_string_descriptor` | `RT_TYPE_STRING` |
| `xrt_fatal` | `rt_fatal` |

原则：

- 薄封装，不复制结构定义；
- 内部实现不改名；
- 迁移后生成代码只 include `xrt.h`；
- `rt.h` 降级为内部头。

---

## 11. 兼容性

### 11.1 版本规则

- 符号与签名冻结为 ABI 承诺；
- 破坏性变更走主版本；
- 只追加不改变既有语义；
- 内部 `rt_*` 不是 ABI。

### 11.2 平台

- C11；
- 原子类型使用 C11 atomics；
- POSIX 优先；
- Windows 后端保留接口，实现分支后置。

### 11.3 线程

- 计数原子；
- 弱表接口按原子语义设计；
- 单线程骨架期不做并发清除/读取；
- 并发期接入安全点/写屏障。

---

## 12. 验证

| 测试 | 覆盖 |
| --- | --- |
| `test_abi.c` | 分配/计数、弱表、根、字符串访问器、句柄幂等关闭、Bytes |
| `test_rt.c` | 底层计数/终结 |
| `test_gc.c` | 根/扫描链 |
| `test_hard.c` | 弱引用/复活 |
| `build_rt.sh` | `-O2 -Werror` 构建全部套件 |

关键断言：

- `xrt_alloc` GC 缺 scan → fatal；
- `xrt_handle_close` 幂等；
- 已关闭句柄 `xrt_handle_native` 返回 NULL；
- 弱表目标终结后读取 NULL；
- 根登记幂等；
- `xrt_safepoint` 释放隔离区；
- `xrt_string_len` 以 len 为准。

---

## 13. 边界

| 能力 | 说明 |
| --- | --- |
| 完整嵌入 API | 非承诺；只承诺符号与初始化顺序 |
| 反向嵌入 | 非承诺 |
| 弱表公共使用 | 仅 FFI 合同层 |
| 内部布局 | `rt.h` 不对外 |
| 直接操作计数/标记 | 禁止 |
| 跨语言对象地址 | 禁止 |
| ABI 兼容 | 主版本变更 |

---

## 规范依据与实现选择

### 规范依据

| 第 1—8 部分条款 | 本模块落实 |
| --- | --- |
| 第 3 部分 §22 | 运行时最小入口集 |
| 第 3 部分 §18 | 句柄显式 close、不依赖 deinit |
| 第 7 部分 §6.1 | `xrt_*` 稳定命名与符号冻结 |
| 第 4 部分 §7.3 | 跨边界错误/取消/超时的 ABI 前提 |

### 实现选择

- 薄封装映射表；
- 不透明句柄载荷布局；
- `xrt_bytes` 形态；
- 初始化幂等标志；
- 弱表入口的合同层限制。

以上为实现选择，不新增语言语义；稳定 ABI 承诺以第 3 部分 §22 与第 7 部分 §6 为准。

## 14. 参考

- `impl/runtime/xrt.h`
- `impl/runtime/xrt_abi.c`
- `impl/runtime/rt.h`
- `impl/runtime/rt_gc.h`
- `impl/runtime/test_abi.c`
- `XNull解决方案-第7部分-FFI-v1.0.0.md` §6
- `XNull解决方案-第3部分-内存管理-v3.1.0.md` §20
