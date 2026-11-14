# XNull 解决方案 第 9 部分：工具链（模块 03：运行时内存与标准原语）

> 本文是第 9 部分模块 03，只落实第 3—6 部分已定义的内存、错误、任务与 XDK 语义；内部实现选择不构成语言语义；与第 1—8 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 9 部分（T9） |
| 模块 | 03 运行时内存与标准原语 / 10 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—8 部分约束） |
| 文档性质 | 第 9 部分模块详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 设计依据 | 第 3、4、5、6 部分 |
| 组件 | 运行时内存与标准原语：分配头、ARC、GC、策略执行器、弱表、隔离区、runtime/text/sys C 原语 |
| 上游输入 | 编译器生成代码、`xrt` 稳定 ABI、XDK C 原语调用 |
| 下游输出 | 对象生命周期、GC 行为、策略结果、系统原语结果 |
| 明确不含 | 稳定的 `xrt_*` 对外 ABI（模块 04）、FFI 合同校验（模块 05）、工程构建（模块 06）、诊断渲染（模块 07） |
| 配套文档 | 第 9 部分总览；模块 04、05、06 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。定义运行时对象模型、ARC/GC、策略执行、弱表、隔离区与标准原语。 |

---

## 0. 范围与边界

### 0.1 组件定位

C 运行时是 XNull 语言内存与系统原语的执行层。它不决定源码语义（由编译器/规范决定），只执行编译器插入的 `retain`/`release`/分配/根登记等动作，并提供标准库 C 原语。

```
编译器生成 C
   │  rt_* / xrt_* 调用
   ▼
C 运行时
   ├─ 分配头 / ARC / GC
   ├─ 策略执行器
   ├─ 弱表 / 隔离区
   ├─ 字符串 / 对象
   └─ rt_std_*.c（runtime/text/sys 原语）
```

### 0.2 边界

| 属于本组件 | 不属于本组件 |
| --- | --- |
| 分配头、对象布局、ARC/GC、弱表 | 稳定的对外符号命名（04） |
| 策略判定表执行 | 策略判定的编译期输入（编译器/语义） |
| 隔离区、终结链 | `.xfb` 合同校验（05） |
| 字符串对象 | FFI 包装生成（05） |
| 标准原语 C 实现 | XDK 公共 API（XDK 文档） |
| fatal 运行时行为 | 诊断格式渲染（07） |

### 0.3 语义来源

- S3 内存管理：分配头、策略、ARC/GC、弱表、终结、容器内存、任务共享、清理责任；
- S4 错误处理：`Result` 值语义、资源关闭、fatal 边界；
- S5 运行时任务与并发：env external root、安全点、跨任务共享；
- S6 XDK：runtime/text/sys 的 C 原语合同。

---

## 1. 对象模型

### 1.1 分配头

```c
typedef enum {
    RT_KIND_ARC = 1,
    RT_KIND_GC  = 2
} rt_kind;

typedef struct rt_header {
    rt_kind             kind;
    const rt_type      *type;
    atomic_int_fast64_t refcount;
    int                 terminated;
    int                 marked;
    struct rt_object   *gc_next;
    struct rt_object   *scan_next;
    int                 in_scan_list;
    struct rt_weak_slot *weak_head;
} rt_header;
```

| 字段 | 作用 |
| --- | --- |
| `kind` | ARC/GC 种类 |
| `type` | 类型描述符 |
| `refcount` | 原子计数（ARC） |
| `terminated` | 终结标志，防复活/双释放 |
| `marked` | GC 标记位 |
| `gc_next` | 全 GC 对象链 / 隔离区链复用 |
| `scan_next` | ARC 扫描链 |
| `in_scan_list` | 是否在扫描链 |
| `weak_head` | 弱槽位侧链 |

### 1.2 类型描述符

```c
typedef struct rt_type {
    const char *name;
    size_t      payload_size;
    void      (*deinit)(void *payload);
    void      (*scan)(void *payload, void (*visit)(void *ref));
} rt_type;
```

- `deinit`：终结时释放引用字段；
- `scan`：枚举强引用字段，GC 标记与 ARC 扫描链使用；
- GC 对象必须有 `scan`；
- ARC 对象持有 GC 引用时必须登记扫描链（不变量 2）；
- 类型描述符支持 `is`/`as`、协议检查、`Any` 拆箱检查（完整面随类型系统扩展）。

### 1.3 对象布局

```
rt_object
  ├─ rt_header
  └─ payload（按类型）
```

- 载荷按 8 字节对齐；
- 栈对象没有分配头；
- 协议实现类的载荷起始位置是协议 vtable 指针；
- 字段槽是运行时布局，不是跨 FFI 的默认承诺。

### 1.4 字符串对象

```c
typedef struct rt_string {
    rt_header hdr;
    size_t    len;
    char      bytes[];
} rt_string;
```

- `len` 是 UTF-8 字节数，权威长度；
- 末尾 NUL 只为 C 互操作便利，不作为长度合同；
- 字符串是 ARC 对象；
- 字节区免扫描。

---

## 2. 分配与 ARC

### 2.1 分配

- `rt_alloc(kind, type, payload)`：分配头 + 载荷；计数从 1 起；
- `rt_arc_new(type)`：ARC 对象；若 `type->scan != NULL`，登记扫描链；
- `rt_gc_new(type)`：GC 对象；GC 类型必须有 `scan`（`xrt_alloc` 在 ABI 入口处校验），加入全 GC 对象链；
- 分配失败：`abort`/fatal（运行期不可恢复）。

### 2.2 retain

```
rt_retain(obj)
  ├─ NULL → 返回 NULL
  ├─ terminated → rt_fatal("复活检测")
  └─ 原子 +1
```

### 2.3 release

```
rt_release(obj)
  ├─ NULL → 返回
  ├─ terminated → 返回（防双释放）
  ├─ 原子 -1
  └─ 到 0：
       1. terminated = 1
       2. 清弱槽位
       3. 从 GC 扫描链注销
       4. type->deinit
       5. 入隔离区
```

### 2.4 隔离区

- 终结与回收分离；
- 终结后的对象先入隔离区，内存保持有效，复活检测可确定性观察；
- `rt_quarantine_flush()` 释放隔离区；
- `main` 返回前调用；
- GC 收集前也先 flush 上一次隔离区。

### 2.5 计数合同

- `retain`/`release` 成对；
- 原子操作；
- 可在证明无并发的编译单元使用非原子计数（设计扩展点），但不得跨编译单元混用；
- 不得绕过分配头直接修改计数。

---

## 3. GC

### 3.1 数据结构

| 结构 | 作用 |
| --- | --- |
| `g_gc_list` | 全 GC 对象侵入式单链 |
| `g_scan_list` | ARC 扫描链（持 GC 引用的 ARC 对象） |
| `g_roots` | 全局根动态数组（静态/顶层、单例、数据枚举项等） |

### 3.2 根集合

- 栈槽位（设计上由编译器登记/安全点扫描）；
- 顶层/静态字段；
- 单例；
- 数据枚举项；
- 可达闭包环境；
- 任务 external root；
- ARC 扫描链。

### 3.3 标记

```
mark_all:
  for root in g_roots: mark_ref(root)
  for o in g_scan_list: mark_ref(o)

mark_ref(ref):
  if NULL or terminated: return
  if GC: 若未标记则标记
  if type->scan: scan(ref, mark_ref)
```

- ARC 对象不被标记，也不阻止其按计数终结；
- GC 沿 ARC 对象中的引用字段继续追踪；
- ARC 扫描对象本身作为根。

### 3.4 清扫

```
sweep:
  遍历 g_gc_list：
    标记 → 复位 marked，保留
    未标记 →
      通过 scan 释放其 ARC 引用
      terminated = 1
      清弱槽位
      调用 deinit
      从链中摘除并 free
```

- 死亡 GC 对象释放 ARC 引用（不变量 3）；
- 不释放 GC 引用（随对象一起消亡）；
- 同一周期多个 `deinit` 顺序是实现细节；
- 清扫期间不得复活死亡对象。

### 3.5 回收触发

- 分配点或安全点；
- `rt_gc_collect()`：先 flush 隔离区，再标记、清扫；
- 回收时机不确定，不承诺硬实时；
- 进程退出不保证 `deinit`。

### 3.6 写屏障与安全点

- 写屏障必须覆盖 GC 字段写入与 ARC 扫描链维护；
- 安全点覆盖分配点、调用边界、循环回边（实现可选）；
- 单线程骨架期收集点即安全点；并发扩展由任务运行时接入；
- 不得假设 mutator 主动到达安全点以外位置。

---

## 4. 弱引用

### 4.1 结构

```c
struct rt_weak_slot {
    rt_object           *target;
    struct rt_weak_slot *next;
    int                  cleared;
};
```

- 槽位挂在目标对象 `weak_head` 侧链；
- 槽位不持强引用，不阻止回收；
- 目标终结前清除全部槽位；
- `rt_weak_get` 对已清除/已终结目标返回 `NULL`；
- 槽位可复用；
- 弱表入口只对 FFI 合同层/运行时内部开放，源码与 XDK 公共 API 不暴露。

### 4.2 操作

| 函数 | 行为 |
| --- | --- |
| `rt_weak_create(target)` | 建槽，不增计数 |
| `rt_weak_get(slot)` | 目标已清除/终结 → NULL |
| `rt_weak_destroy(slot)` | 从目标侧链摘除并释放 |
| `rt_weak_clear_slots(target)` | 终结链第 1 步清除全部槽位 |

### 4.3 并发

- 接口按原子语义设计；
- 单线程骨架期不做并发清除/读取竞争；
- 并发子切片接入原子化；
- 清除后读取不得观察到已终结目标。

---

## 5. 策略判定执行器

### 5.1 输入

```c
typedef struct {
    rt_type_kind kind;
    int has_deinit;
    int self_captured;
    int ref_cycle;
    int gc_field;
    int has_ref_field;
} rt_policy_input;
```

### 5.2 输出

```c
typedef enum {
    RT_POLICY_VALUE,
    RT_POLICY_ARC,
    RT_POLICY_GC,
    RT_POLICY_NA_GC
} rt_policy;
```

### 5.3 判定顺序

| 行 | 条件 | 输出 |
| --- | --- | --- |
| 0 | struct | value |
| 2 | protocol | na-gc |
| 3 | 简单枚举 | value |
| 4 | 数据枚举 | gc |
| 5 | `gc_field` | gc |
| 6 | `ref_cycle` | gc |
| 7 | `has_deinit`/`self_captured` | arc |
| 8 | 只有值字段 | arc（栈候选） |
| 9 | 其余 | arc |

- 纯函数，同一输入同一输出；
- 命中即返回；
- 行 1（单例）保留；
- 判定行号可读名用于诊断/测试。

### 5.4 栈候选

- 行 8 只表示类型级栈候选；
- 对象级还需逃逸分类 `none`；
- 栈分配不改变身份/引用语义；
- 逃逸对象提升为 ARC/GC。

---

## 6. 标准原语

### 6.1 runtime

| 函数 | 合同 |
| --- | --- |
| `xdkc_diagnose` | 单行、无分配、stderr；换行折叠为空格 |
| `xdkc_exit` | `_Exit`，不执行 defer/atexit |
| `xdkc_now_mono_ms` | `CLOCK_MONOTONIC`，单调 |
| `xdkc_now_wall_ms` | UTC 毫秒，可回拨 |
| `xdkc_env_get` | 首次读取即快照；不可变；容量上限 |

### 6.2 text

| 函数 | 合同 |
| --- | --- |
| `xdkc_parse_int` | 全串消费；0 成功、1 语法无效、2 溢出 |
| `xdkc_parse_float` | 同上 |
| `xdkc_format_int` | 调用方缓冲；不足返回 -1 |
| `xdkc_fmt_append_raw/int` | 调用方缓冲 + 游标；不 realloc |
| `xdkc_regex_match` | POSIX ERE 子集；0 匹配、1 不匹配、2 模式错误 |
| `xdkc_utf8_to_utf16` | 逐码点校验；非法/不足返回 -1 |
| `xdkc_utf16_to_utf8` | 处理代理对；非法/不足返回 -1 |

### 6.3 sys

| 函数 | 合同 |
| --- | --- |
| `xdkc_file_open_read/write` | 非法路径/打开失败返回 NULL |
| `xdkc_file_read` | 返回读取数；错误码出参 0/1/2 |
| `xdkc_file_write` | 0 成功、1 句柄无效、2 IO 失败 |
| `xdkc_file_close` | 幂等；NULL 返回 0 |
| `xdkc_dir_open/read/close` | `read` 返回内部缓冲，下次调用前有效 |
| `xdkc_path_exists` | 文件/目录同真；无权限按不存在 |
| `xdkc_proc_status` | 退出码 0—255；信号/失败 -1 |
| `xdkc_read_file_text` | 整文件读；失败 NULL；复用缓冲 |

### 6.4 资源表

- 构建期生成只读 C 常量表；
- 资源名 = 相对路径，`/` 分隔；
- 按名升序；
- 只读，无句柄；
- 运行时查询不回退文件系统。

---

## 7. fatal 与错误

### 7.1 fatal 入口

`rt_fatal(reason)`：

- 可安装处理器（测试/嵌入）；
- 默认打印 `xnull runtime fatal: ...` 后 `abort`；
- 用于：分配失败、复活、终结链 panic、隐式 fatal、越界等。

### 7.2 错误码

C 原语以错误码/`Result` 语义返回，不 panic：

| 场景 | 行为 |
| --- | --- |
| 文件/目录/解析失败 | 返回错误码/NULL |
| 字典/通道/协议错误 | 返回错误码 |
| 越界写检测 | fatal |
| 分配失败 | fatal |
| 复活/双释放防御 | fatal/忽略 |

### 7.3 可观测性

- `xdk.runtime` 可提供分配统计、GC 指标、存活对象转储；
- 这些是工具能力，不是语言语义；
- 诊断输出不得静默丢失。

---

## 8. 并发扩展点

| 扩展点 | 设计 |
| --- | --- |
| 原子计数 | 已使用 C11 atomics |
| 弱表并发 | 接口按原子语义设计，单线程骨架期未实现 |
| 写屏障 | 单线程骨架期只做存活校验；并发期补增量屏障 |
| 安全点 | 收集点即安全点；并发期接入挂起点 |
| 任务根 | `xrt_task_root_bind/unbind` 供 trampoline/env |
| 线程载体 | 由任务运行时/调度器提供，不在内存核心内 |

约束：

- 数据竞争是程序错误，运行时不检测；
- 并发扩展不得改变 ARC/GC 可观察顺序；
- 不得引入第二套计数格式。

---

## 9. 验证

### 9.1 C 套件

| 套件 | 覆盖 |
| --- | --- |
| `test_rt.c` | 分配头、计数、终结链、字符串、策略表 |
| `test_gc.c` | 环回收、根、ARC 持 GC、清扫 release、双路可达 |
| `test_hard.c` | 弱引用、复活检测、硬语义 |
| `test_abi.c` | `xrt_*` 迁移、句柄、弱表、根（04） |
| `test_std.c` | runtime/text/sys 原语 |
| `test_res.c` | 资源表 |

### 9.2 关键断言

- 计数从 1 起；
- 终结链顺序；
- 弱引用不可见已终结目标；
- ARC↔GC 混合无悬挂/泄漏/重复释放；
- 隔离区会合；
- 策略表行序与确定性；
- 解析/格式化边界；
- 文件关闭幂等。

### 9.3 构建

```
cc -std=c11 -Wall -Wextra -Werror -O2 ...
```

`build_rt.sh` 统一构建/运行全部套件。

---

## 10. 边界

| 能力 | 说明 |
| --- | --- |
| 硬实时 | 不承诺；GC 会合/ARC 原子/终结无最坏耗时 |
| 自定义分配器 | 不提供 |
| 手动释放 | 不提供 |
| 源码级寻址 | 不提供 |
| 任意 C 布局 | 不默认兼容 |
| 动态插件 | 首发不包含 |
| GPU 内存 | 不覆盖 |
| 进程退出 deinit | 不保证 |
| 完整嵌入 API | 非承诺；只承诺 ABI 符号与最小初始化 |

---

## 规范依据与实现选择

### 规范依据

| 第 1—8 部分条款 | 本模块落实 |
| --- | --- |
| 第 3 部分 §2、§4—§16、§22 | 分配头、策略、ARC/GC、弱表、终结、容器内存、ABI 入口 |
| 第 4 部分 §7、§8 | 错误边界、资源关闭、清理责任 |
| 第 5 部分 §2.2、§9 | 任务根、安全点、阻塞分类的内存侧前提 |
| 第 6 部分 §4.4—§4.7 | runtime/text/sys C 原语合同 |

### 实现选择

- 分配头字段与对象布局；
- 全 GC 链/ARC 扫描链/全局根数组；
- C11 atomics；
- 隔离区实现；
- `xdkc_*` 内部符号命名；
- 单线程骨架与并发扩展点。

以上为实现选择，不新增语言语义；与第 3—6 部分冲突时以母本为准。

## 11. 参考

- `impl/runtime/rt.h`
- `impl/runtime/rt.c`
- `impl/runtime/rt_gc.h`
- `impl/runtime/rt_gc.c`
- `impl/runtime/rt_policy.h`
- `impl/runtime/rt_policy.c`
- `impl/runtime/rt_weak.c`
- `impl/runtime/rt_std_runtime.c`
- `impl/runtime/rt_std_text.c`
- `impl/runtime/rt_std_sys.c`
- `impl/runtime/build_rt.sh`
- `XNull解决方案-第3部分-内存管理-v3.1.0.md`
- `XNull解决方案-第4部分-错误处理-v1.0.0.md`
- `XNull解决方案-第5部分-运行时任务与并发-v1.0.0.md`
