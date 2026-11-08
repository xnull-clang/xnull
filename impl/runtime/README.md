# XNull C 运行时（impl/runtime，M3）

> 规范依据：S3 内存管理 v3.0.0、S5 错误处理 v1.0.0。**运行时语义必须用 C 落地**
> （S3/S5 强制语义无法由 Go GC 承载——impl/README 风险点 3）。

## 子切片划分

| 子切片 | 范围 | 规范 | 状态 |
| --- | --- | --- | --- |
| **M3.1 ARC 基础** | 分配头（S3 §2）、原子计数、retain/release、终结链（§14 时序：置终结标志→deinit→释放、防复活/双释放） | S3 §2/§7/§14 | **完成**（rt.h/rt.c/test_rt.c） |
| **M3.2 判定表执行器** | §15.1 判定表的运行时执行：输入结构自 M2.5.2 冻结（见下"策略判定接口"） | S2 §15.1、S3 §4—§6 | **完成**（rt_policy.h/c + test） |
| **M3.3 GC 交互** | 标记—清扫内核（rt_gc.h/c）、混合图不变量 1/2/3/5/6、全局根登记、ARC 扫描链 | S3 §5/§8、S2 §15.6 | **完成**（不变量 4 弱引用表挂 M3.4） |
| **M3.4 硬语义** | 复活检测终止进程（rt_fatal）、终结/回收分离（隔离区 §13）、弱引用表（§16，不变量 4）、errdefer/throw fatal 交互（S1 §10.3–10.4，interp 收敛测试） | S3 §13/§14/§15/§16、S1 §10 | **完成**（字符串与容器堆表示挂 M4.1 代码生成消费面） |

## 构建

```
cc -std=c11 -Wall -Wextra -Werror -o /tmp/test_rt test_rt.c rt.c && /tmp/test_rt
```

无外部依赖；C11 atomics（S3 §7 原子计数合同，唯一计数格式）。

> 环境备注：本机（clang 17/macOS）ASan 运行时对任意程序（含 hello world）SIGILL，
> 属环境故障非代码问题；验收基线为 `-O2 -Werror` 全警示零缺陷，ASan 留作可选。

## 合同要点（实现已锚定）

1. **分配头**（§2）：种类 + 类型描述符 + 原子计数 + 终结标志；字段 8 字节对齐。
2. **计数从 1 起**；retain/release 成对；原子操作（§7）。
3. **终结链时序**（§14）：release→0 先置 terminated（防复活/双重释放）→ deinit（内部引用在此释放）→ free。该时序是 S3 强制语义，任何优化不得重排可见效果。
4. **类型描述符**承载 deinit 分派与动态类型检查基础（is/as 完整面随类型系统子切片扩展）。

## 策略判定接口（M2.5.2 冻结，M3.2 消费）

判定表输入结构在 `impl/internal/sema/policy.go`（Strategy）定型并冻结；
C 侧对应 `rt_policy.h` 的 `rt_policy_input`，字段一一映射：

| Strategy (JSON)    | rt_policy_input        | 说明（S2 §15.1） |
| ------------------ | ---------------------- | ---------------- |
| `kind`             | `kind`（rt_type_kind） | class/struct/enum/protocol |
| `data`             | `data_enum`            | 数据枚举（行 4 GC） |
| `policy`           | `rt_decide_policy` 返回 | value/arc/gc/na-gc |
| `rule`             | `rule_out` 输出参数    | 命中的判定行（1–9；struct 为 0） |
| `deinit`           | `has_deinit`           | 行 7 |
| `selfCaptured`     | `self_captured`        | 行 7 |
| `refCycle`         | `ref_cycle`            | 行 6 |
| （字段图归纳）      | `gc_field` / `has_ref_field` | 行 5 / 行 9 前提；Go 侧由字段类型图归纳（§15.1 行 5/6 已在 sema 完成，C 侧执行器只做行序表驱动） |
| `stackEligible`    | Go 侧计算              | 行 8；对象级还需逃逸分类 none（§15.2，M4.1 填充 `escape`） |
| `escape`           | （预留）               | 对象级逃逸分类 none/return/other；M2.5.2 恒为 "n/a" |

确定性（DET-01）：`rt_decide_policy` 是纯函数，同一输入恒产生同一输出；
Go 侧 `ComputeStrategies` 按声明名排序输出，不依赖声明顺序与文件枚举顺序。

## 文件地图（中文对照）

命名约定：`rt_` = 运行时内部实现；`xrt_` = 对外稳定 ABI；`rt_std_` = 标准库的 C 实现。

| 文件 | 全称/含义 | 作用 | 可见性 |
|---|---|---|---|
| `rt.h` / `rt.c` | Runtime core | 分配头、ARC retain/release、隔离区、fatal | 内部 |
| `rt_gc.h` / `rt_gc.c` | Garbage Collector | 标记—清扫、全局根、扫描链 | 内部 |
| `rt_weak.c` | Weak references | 弱槽位、目标死亡清除、复用池 | 内部 |
| `rt_policy.h` / `rt_policy.c` | Policy executor | 策略判定表执行 | 内部 |
| `rt_task.c` | Task runtime | 任务/组/Context/载体线程/伴生执行器 | 内部 |
| `rt_sync.c` | Synchronization | Mutex/Channel/Atomic | 内部 |
| `rt_std_runtime.c` | Stdlib runtime | 时钟/env/diagnose/exit | 内部（XDK 实现） |
| `rt_std_text.c` | Stdlib text | UTF/parse/format/regex | 内部（XDK 实现） |
| `rt_std_sys.c` | Stdlib system | 文件/目录/进程/路径 | 内部（XDK 实现） |
| `rt_std_bytes.c` | Stdlib bytes | 可变字节缓冲 | 内部（XDK 实现） |
| `rt_std_net.c` | Stdlib network | socket/http | 内部（XDK 实现） |
| `rt_std_res.c` / `_empty.c` | Stdlib resources | 资源表 5 API / 空表回退 | 内部（XDK 实现） |
| `xrt.h` | XNull Runtime ABI v1 | 对外唯一稳定 ABI：alloc/retain/release、弱表、根、任务根、String/Handle/Bytes、fatal | **公开** |
| `xrt_abi.c` | ABI implementation | `xrt_*` 入口的薄封装 | 公开 ABI 的实现 |
| `build_rt.sh` | Build & test | 全量编译 + 跑 rt/gc/hard/abi/std/res/net 套件 | 工具 |
| `test_*.c` | Test suites | 各子切片验收用例 | 测试 |

## 谁能调用运行时

| 调用方 | 允许的接口 | 说明 |
|---|---|---|
| 编译器生成代码 | 仅 `xrt.h` 的 `xrt_*` | 稳定 ABI v1；不直接碰 `rt_*` |
| FFI 绑定层 | 仅 `xrt.h` | 跨语言边界合同（INV-FFI-7） |
| 应用开发者 | XNull 语言 + `xdk.*` | **不直接调用 C 运行时**；绕过 ARC/GC 合同会破坏不变量 |
| 运行时/绑定开发者 | `rt.h` 内部接口 | 仅限 runtime 子切片开发与测试 |

结论：内部文件名是缩写，但分层是清楚的——应用只看 XDK，生成代码只看 `xrt.h`，`rt_*` 是内部实现，不随 SDK 分发。
