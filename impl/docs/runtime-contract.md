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
| P-01 | codegen 只消费 sema 产物；引用类型统一 `rt_object*` 表示；ARC 插入规则七条（设计 §3.3） | 采纳（附澄清，见 C 段 2026-11-06 编译器侧） |
| P-02 | 新增 rt API：`rt_string_concat`、`rt_str_from_int/_double/_bool/_container`、`rt_print` | 采纳（带格式一致性硬要求） |
| P-03 | 新增 rt API：`rt_array_new/get/set`（元素描述符进 rt_type）、`rt_closure_new` | 采纳（描述符形态要求见 C 段） |
| P-04 | Result 表示：tag + union 由 codegen 生成，构造/析构内联，不进运行时 | 修改后采纳（结构体形态，原则不变） |
| P-05 | escape 回填：codegen 对象级逃逸分类（none/return/other）写入 `rt_policy_input.escape` | 条件采纳（需 A 段增补 + 挂 M4.4b） |
| P-06 | 入口垫片：`main` → `xn_main`，Int 退出码直通（S1 ENTRY-01 / S8 §5.1 退出码合同） | 采纳（已落地，冻结为事实） |
| P-07 | 构建缓存：libxrt.a 内容哈希键控；cc 探测 CC→cc→clang→gcc；旗标 `-std=c11 -O2 -Wall` | 部分采纳（键与旗标要求见 C 段） |
| P-08 | 新增 `impl/runtime/xrt.h` + `xrt_abi.c` 薄封装层：S7 §6.1 冻结的 `xrt_*` 前缀映射到内部 `rt_*`（内部实现不改名，零回归）；`xrt.h` 为唯一对外 ABI 头，`rt.h` 降级为内部头；含 FFI 增补 `xrt_handle`、`xrt_task_root_bind/unbind`（见 ffi-design.md §5.4） | 采纳（codegen 迁移挂 M4.4a，清单见 C 段） |
| P-09 | codegen 把 `.xfb` 入口作为包级可调用声明注入，调用点使用 `xn_ffi_<entry>`（包装 ABI v1，ffi-contract §5.1） | 采纳（附三条条件，见 C 段 2026-11-06 编译器侧·P-09/P-10） |
| P-10 | `xnull build` 的 C 编译清单纳入 `xrt_abi.c` 与 `rt_std_*.c`，并注入 `link.libraries`（LinkArgs） | 采纳（附四条条件，见 C 段 2026-11-06 编译器侧·P-09/P-10） |

## C. 交互记录（追加式，倒序）

- 2026-11-06 运行时侧（回应 P-09/P-10 评审，条件落地状态）：P-09 条件 1——跨包入口重名已由 `FFI-111` 跨声明块检测覆盖（入口/结构/句柄），包装名维持 `xn_ffi_<entry>` 无包段；条件 2——错误映射为 Result 属包装层调用点，实现等放行单；条件 3——所有权句已入 ffi-contract §5.2（入参借用/返回归调用方/`.reclaim` 调用即移交）。P-10 条件 3——`LinkArgs` 已去重 + 升序（用例更新）；条件 1（import 闭包）与条件 2（同批切换）、条件 4（缓存键哈希）属构建侧，资源表生成器已按"确定性升序"对齐。另：M4.5c 收尾完成（`.reclaim` 归还登记、跨任务句柄规则定案 ffi-contract §5.2、trampoline 接口预留 `ErrTrampolineReserved`）；XDK C 层续建完成（目录/存在性/子进程、资源表生成器 + 样例验证、Regex ERE 子集 + Format 追加族）。

- 2026-11-06 编译器侧：**P-09/P-10 评审结论**（逐条；运行时侧可据此接 XNull 包装层）：
  - **P-09 采纳（附三条条件）**：
    1. **入口符号全局唯一性必须在合同层兜底**：包装符号为 `xn_ffi_<entry>`（无包段），两个 `.xfb` 存在同名入口即 C 重定义。要求 `Load` 增加**跨包入口重名校验**（FFI-1xx 新码），或在包装签名加包段（`xn_ffi_<pkg>_<entry>`）并同步 ffi-contract §5.1。编译器侧倾向前者（改动最小，现有两文件入口不重叠）。校验落地前，编译器侧注入时也会做编译单元内重名防御性检查（显式报错，红线 2）。
    2. **调用点错误呈现**：`xn_ffi_<entry>` 返回错误码 + `xn_out`，codegen 侧将映射为 `Result`（错误分支携带 `xn_ffi_<region>_error_kind(code)` 归类），不隐藏错误、不静默吞非零码（红线 2）；错误码归一的「未知码 → Internal，绝不当 Ok」要求与解释器错误面在对照用例中覆盖。
    3. **编组所有权与 §3.3 一致**：入参 `String` 借用（不 retain，调用期有效）；返回 `String` 所有权归调用方（包装内 `xrt_string_alloc` 产物按 move 语义接管）；`Bytes` canary 拷贝进出无异议。要求 ffi-design §5.4 补一句「返回值所有权归调用方」入合同文本。
  - **P-10 采纳（附四条条件）**：
    1. **`rt_std_*.c` 按 import 闭包纳入**：产物只链接实际 import 的 XDK 对应 `rt_std_*.c`（不携带全量），纳入清单按 import 书写序排序（DET-01 延伸，确定性）。
    2. **`xrt_abi.c` 纳入与 P-08 codegen 迁移同批**：迁移前产物全部走内部 `rt_*`，先纳入 `xrt_abi.c` 无害但属死代码；建议两件事一批切换，避免中间态双面链接。
    3. **`link.libraries` 注入确定性**：收集自所纳 `.xfb` 的 LinkArgs，**去重 + 升序排序**后注入；`-l/-L` 顺序须在全部目标文件之后（链接顺序敏感）；缺库由 cc 失败显式报错，编译器侧不做库探测回退。
    4. **缓存键扩展**：P-07 已采纳的 libxrt.a 缓存键须追加「链接清单哈希」（`xrt_abi.c`/`rt_std_*.c` 集合 + LinkArgs），否则清单变化误命中。
- 2026-11-06 运行时侧（回应 P-01—P-08 评审）：P-08 ①逐符号迁移清单已交付并全部实现、覆盖于 `runtime/test_abi.c`——
  `rt_string_new`→`xrt_string_new`、`rt_string_from_c`→`xrt_string_from_c`、`rt_release`→`xrt_release`、
  `rt_retain`→`xrt_retain`、`rt_refcount`→`xrt_refcount`、`xn_alloc_str`（手写分配头）→`xrt_string_alloc`、
  `rt_fatal`→`xrt_fatal`、`rt_quarantine_flush`→`xrt_safepoint`、`RT_TYPE_STRING`→`xrt_type_string_descriptor()`；
  `xrt_handle`/`xrt_bytes` 为 FFI 增补面（P-09 消费）。P-02 接受（`rt_print_int/_str/_bool`、`rt_str_from_double`
  须与解释器 `str()` 逐字节一致）：该组不在本轮交付，作为 M4.5e 切片，迁移前先建对照用例。P-05/P-06/P-07 无异议。
  另提 P-09/P-10（FFI 钩子与构建清单接入）。

- 2026-11-06 编译器侧：**P-01—P-08 评审结论**（逐条，含落地要求）：
  - **P-01 采纳（附澄清）**：消费边界澄清为「AST + sema 模块（符号表/类型/策略表）」，sema 诊断不是 codegen 输入。§3.3 实为八条（第 8 条 GC 字段不 retain），建议文案改「八条」或标注 7+1。另注：M4.1 已交付的字符串实现为 move/消耗语义（`xn_concat` 接管两侧），与规则 3（传参 retain）不同——M4.4b 起按 §3.3 统一，迁移时既有示例双路径一致性为回归锚点。
  - **P-02 采纳（带硬要求）**：现状 prelude 已在每个翻译单元重复定义 `xn_print_int/str/bool`、`xn_str_int`、`xn_concat`，下沉运行时可消除重复；**硬要求**：`rt_str_from_double` 等格式化必须与解释器 `str()` 逐字节一致（-0、Inf、NaN、科学计数阈值、整值浮点形态），并在 `test_rt.c` 建立格式对照用例——否则双路径完成定义失效。`rt_print` 接口形态由运行时侧定（建议分型 `rt_print_int/_str/_bool`，避免变参）。
  - **P-03 采纳（附形态要求）**：**不用运行期元素描述符注册表**（全局状态，确定性风险）；改由 codegen 为每个元素类型生成静态描述符实例，API 为 `rt_array_new(const rt_type *elem, size_t n)`，元素读写经描述符取 size/scan。`rt_closure_new` 采纳；闭包捕获盒布局由 codegen 生成，运行时只提供分配 + scan 枚举。
  - **P-04 修改后采纳**：原则（表示由 codegen 生成、构造/析构内联、不进运行时）不变；形态改为**按实例化的普通结构体**（`int ok; T v; rt_string *err;`），不用 tag+union。理由：①M4.1 已按此实现且双路径一致；②union 在 C 严格别名规则下有隐患；③表示对运行时不可见，后续性能切片可换 union 而不动 ABI。要求：Result 布局不对外暴露，成员访问一律 codegen 内联。
  - **P-05 条件采纳**：①`rt_policy_input` 现为 6 字段、**无 escape**，本提案须 A 段增补（运行时侧改 `rt_policy.h` + `test_rt.c` 补「escape 恒 n/a」断言，保 M3 行为零变化）；②codegen 侧逃逸分类挂 **M4.4b**（对象级 ARC 插入需要栈/ARC 决策），M4.1 值面不产生对象级逃逸；③顺序：运行时先加字段（默认值保持现状）→ codegen 后回填。
  - **P-06 采纳（已落地，冻结为事实）**：已生成 `int main(void){ int64_t xn_r = xn_main(); rt_quarantine_flush(); return (int)xn_r; }`；补充两点：void main 形态返回 0；fatal（`xn_throw`）exit(134) 直通不经 main 返回。要求 `rt_quarantine_flush` 幂等（现状满足）。
  - **P-07 部分采纳**：①cc 探测链采纳，另需显式 `--cc` 覆盖与探测失败诊断（现状硬编码 `cc`）；②旗标：产物构建 `-std=c11 -O2 -Wall -Wextra`，测试/CI 加 `-Werror`（现状运行时测试已 -Werror，codegen 产物仅 -O2，建议统一到产物侧 -Wall -Wextra）；③libxrt.a 缓存键必须含「运行时源文件内容哈希 + 编译旗标 + cc 版本串」，否则跨机器/跨工具链误命中；④缓存只落目标目录（`target/`/输出目录），不写全局状态（PROJ-09 可复现精神）。
  - **P-08 采纳（开工无异议）**：两个落地要求——①`xrt.h` 必须覆盖 codegen 现有消费面：`rt_string_from_c`（或等价构造）、`rt_release`、`rt_string_new`、`rt_quarantine_flush`、`RT_TYPE_STRING`、`rt_fatal`、分配头初始化面（`RT_KIND_ARC`/atomic），并给出**逐符号迁移清单**；②迁移由编译器侧在 **M4.4a** 一次性执行（避免两端同时改），迁移前 `rt.h` 保持可用；③`xrt_task_root_bind/unbind` 无异议，编译器侧暂不消费（无并发域）。
- 2026-11-06 运行时侧：新增 P-08（`xrt_*` ABI 封装层），来源 ffi-design.md §5.4——S7 附录 B 冻结 `xrt_*` 为 ABI 承诺，而运行时内部符号为 `rt_*`；封装层方案保 M3 零回归。
- 2026-11-06 运行时侧：本文件建立；A 段摘自 M3 已落地合同（无改动）；B 段 P-01—P-07 随 m4-codegen-design.md 提交评审。
