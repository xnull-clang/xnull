# XNull 运行时合同（impl/docs/runtime-contract.md）

> 性质：编译器侧（Go）与运行时侧（C）的**唯一技术协调界面**（不设口头协调，一切经本文件 + 变更单 + 记录）。
> 维护规则：M3 冻结段变更由编译器侧发起；M4 提案段变更由运行时侧发起、编译器侧消费评审；
> 任何变更须记录并注明触发来源。
> 母本依据：`impl/runtime/README.md`、`impl/runtime/rt.h`、`impl/internal/sema/policy.go`（M2.5.2 冻结）。

## A. M3 冻结契约（已落地，变更须双方评审）

### A1. 值模型与生命周期（rt.h，S3 §2/§7/§14）

- 堆对象 = `rt_header`（kind / rt_type* / 原子计数 / terminated / GC 链 / weak_head）+ 载荷；字段 8 字节对齐；
- 计数从 1 起；`rt_retain` / `rt_release` 成对；release→0 触发终结链：
  **清弱槽位（§16）→ 注销扫描链（不变量 6）→ 置 terminated（防复活）→ deinit → 入隔离区（§13）→ 会合回收**；
- `rt_type` 承载 deinit 与 scan 钩子（scan 参数为完整对象指针，与 deinit 同约定）；
- `rt_fatal`：复活检测、终结链 panic、隐式 fatal、`throw fatal` 统一入口，默认 abort。

### A2. 策略判定接口（M2.5.2 冻结，M3.2 消费）

- Go 侧 `Strategy`（sema/policy.go）↔ C 侧 `rt_policy_input` 逐字段映射，见 runtime/README「策略判定接口」表；
- `escape` 字段恒为 "n/a"，**M4.1 由 codegen 回填**（对象级逃逸分类 none/return/other，§15.2）；
- `rt_decide_policy` 纯函数；Go 侧按声明名排序（DET-01）。

### A3. GC 混合图不变量（S2 §15.6 / S3 §8）

不变量 1/2/3/5/6 已在 rt_gc.c 落地并有测试；不变量 4（弱引用表）M3.4 落地。
编译器义务：全局根登记（静态/顶层/单例/数据枚举项）须在生成代码中调用登记 API；ARC 持 GC 引用的对象走扫描链登记。

## B. M4 提案契约（运行时侧起草 2026-11-06，状态：待编译器侧评审）

> 依据：impl/docs/m4-codegen-design.md §2/§3/§6。评审通过后逐项升入 A 段并落 rt.h。

| 编号 | 提案 | 状态 |
| --- | --- | --- |
| P-01 | codegen 只消费 sema 产物；引用类型统一 `rt_object*` 表示；ARC 插入规则七条（设计 §3.3） | 待评审 |
| P-02 | 新增 rt API：`rt_string_concat`、`rt_str_from_int/_double/_bool/_container`、`rt_print` | 待评审 |
| P-03 | 新增 rt API：`rt_array_new/get/set`（元素描述符进 rt_type）、`rt_closure_new` | 待评审 |
| P-04 | Result 表示：tag + union 由 codegen 生成，构造/析构内联，不进运行时 | 待评审 |
| P-05 | escape 回填：codegen 对象级逃逸分类（none/return/other）写入 `rt_policy_input.escape` | 待评审 |
| P-06 | 入口垫片：`main` → `xn_main`，Int 退出码直通（S1 ENTRY-01 / S8 §5.1 退出码合同） | 待评审 |
| P-07 | 构建缓存：libxrt.a 内容哈希键控；cc 探测 CC→cc→clang→gcc；旗标 `-std=c11 -O2 -Wall` | 待评审 |
| P-08 | 新增 `impl/runtime/xrt.h` + `xrt_abi.c` 薄封装层：S7 §6.1 冻结的 `xrt_*` 前缀映射到内部 `rt_*`（内部实现不改名，零回归）；`xrt.h` 为唯一对外 ABI 头，`rt.h` 降级为内部头；含 FFI 增补 `xrt_handle`、`xrt_task_root_bind/unbind`（见 ffi-design.md §5.4） | 待评审 |

## C. 交互记录（追加式，倒序）

- 2026-11-06 运行时侧：新增 P-08（`xrt_*` ABI 封装层），来源 ffi-design.md §5.4——S7 附录 B 冻结 `xrt_*` 为 ABI 承诺，而运行时内部符号为 `rt_*`；封装层方案保 M3 零回归。
- 2026-11-06 运行时侧：本文件建立；A 段摘自 M3 已落地合同（无改动）；B 段 P-01—P-07 随 m4-codegen-design.md 提交评审。
