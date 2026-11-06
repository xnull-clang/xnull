# FFI 前置设计（impl/docs/ffi-design.md）

> 编制：运行时侧（C 侧，域：codegen/ffi 子模块 + S7 台账行）　日期：2026-11-06
> 任务来源：FFI 切片实施授权（2026-11-06，用户提议批准）
> 性质：**阶段 A 纯设计**。阶段 B 实现（M4.5）开工条件：codegen 核心的 M4.1a 落地且 emit 基建可用，或书面放行。
> 规范依据：S7 v1.0.0（§0—§11、附录 A/B）、S3 §18/§19/§22、S4 §7.3/附录 A、S5 §2.2/§9、S8 §7、S1 §0.6/§0.7。
> 配套协调界面：`impl/docs/runtime-contract.md`（运行时 ABI）、`impl/docs/ffi-contract.md`（codegen ↔ ffi 子模块的 Go 接口 + `.xfb` 声明格式）。

## 0. 立场

- FFI 是**合同约束的跨语言接口**，不是任意原生函数直调（S7 §0）。语言文法不新增 `extern`/`unsafe` 关键字（S7 §0、附录 B）；
- 绑定声明全部落在**绑定层声明文件**（`.xfb`，见 §3），由 ffi 子模块解析与合同校验，产物是 codegen 与运行时共同消费的**绑定注册表**；
- 跨边界只允许三形态：值传递、句柄、缓冲区（S7 §2.1）。其余类型在合同层拒绝；
- **对象引用不作跨语言地址**（INV-FFI-4）：`rt_object*` 永不跨边界。

## 1. S7 合规映射表

| S7 条款 | 要求摘要 | 设计决策 | 台账条目 | 切片 |
| --- | --- | --- | --- | --- |
| §2.1 三合同面 | 值/句柄/缓冲区之外拒绝 | 声明校验器按三形态白名单（§4 编组表）逐参数判定；违规 → `FFI-1xx` 合同诊断 | FFI-01 | M4.5a |
| §2.2 调用租约 | 每入口逐参数声明 `.borrow/.transfer/.reclaim`；缺省即违规 | `.xfb` 每入口必须带 `@lease(...)`，参数个数与签名逐一对应；缺失 → `FFI-101`；`.transfer` 无对称 `.reclaim` 且无"永不归还+理由" → `FFI-102` | FFI-01（无租约拒绝）、FFI-03 | M4.5a（校验）/ M4.5b（语义落地） |
| §2.3 能力边界 | 不虚增语言能力 | 绑定入口只能表达 S7 三形态；原生能力入 XNull 后必须适配 Result/资源/取消合同（§7 错误映射） | FFI-01 | M4.5b |
| §3.1 布局总则 | 逐类型验证，不默认兼容 | 边界编组表（§4）只列逐类型显式映射；表外类型一律拒绝 | FFI-02 | M4.5a |
| §3.2 标量映射 | 固定 64 位标量、Bool 归一、无指针宽整型 | 编组表逐行实现（§4.1）；Bool 非 0→1 归一 | FFI-02 | M4.5b |
| §3.3 `layout(c)` | 值传递 struct 必须显式标注；字段限标量/嵌套标注结构；禁引用/可选/容器/递归 | `.xfb` 内 `layout(c) struct` 声明；校验器构造 C 布局（自然对齐）并与声明字段序比对；未标注 struct 只能走句柄/封送副本 | FFI-02 | M4.5a（校验）/ M4.5c（编组） |
| §3.4 String/Text/Bytes | `ptr + byte_len`、非 NUL 合同；String 不可移交 | 借出：`const char*` + `size_t`；`Bytes` 可借出/移交；String/Text 移交 → `FFI-103` | FFI-02、FFI-03 | M4.5b |
| §3.5 数组与缓冲区 | 标量数组 `ptr + count` 借出；多维不直跨 | `T[]`（T 标量或 `layout(c)`）→ `T* + size_t`；嵌套数组 `FFI-104` | FFI-02、FFI-03 | M4.5b/c |
| §3.6 不跨边界清单 | Result/可选/引用/闭包/容器/元组/String 移交拒绝 | 白名单取反：拒绝清单编译期硬拒（`FFI-105`），不做隐式封送 | FFI-01 | M4.5a |
| §4.1—4.2 借出/移交 | 借出仅本次调用；移交后 XNull 不释放；归还路径 | 借出参数在调用点 mark-pin（§5.3），调用返回即失效；移交参数所有权转出，XNull 侧不再 release；`.reclaim` 入口把所有权收回 `Bytes` | FFI-03 | M4.5b |
| §4.3 不透明句柄 | 句柄类型、close 合同、不跨任务 | `Handle` 表示为 `xrt_handle*`（ARC 对象，载荷为 `void* native` + 关闭函数指针）；`close()` 显式、幂等；不依赖 deinit 作唯一路径 | FFI-03、FFI-06 | M4.5c |
| §4.4 缓冲区存活 | 边界期间 pin；越界写检测到即终止 | 单线程执行器下 pin = 不移动 + 不快照；借出缓冲区前后加 canary 哨兵，返回后校验，越界即 `rt_fatal`（不承诺检测全部，S7 §4.4 非承诺已留痕） | FFI-03 | M4.5c |
| §5.1—5.3 回调/trampoline | C 函数指针封装闭包；env 登记根；注销后调用违规；回调 panic 终止进程 | 生成 C trampoline（目标 ABI 签名）+ env 结构（ARC 持有闭包）；创建 `xrt_task_root_bind(env)`、销毁 `xrt_task_root_unbind`；trampoline 首行检查销毁标志，已销毁 → `rt_fatal`；闭包内 panic → `rt_fatal`（不隔离） | FFI-05 | M4.5c |
| §6.1 稳定命名 | `xrt_*` 前缀冻结为 ABI 承诺 | **公开 ABI 面 `xrt.h`**（薄封装 S7 §6.1 入口表）↔ 内部实现 `rt_*` 保持不变；编译器生成代码与原生侧只经 `xrt_*`（INV-FFI-7）。见 §5.4 与 runtime-contract P-08 | FFI-06 | M4.5b |
| §6.2 弱表 | 弱表入口只对合同层开放 | `xrt_weak_*` 标记为 bindings-only（头注释 + 构建检查：应用层源码引用即构建失败） | FFI-06 | M4.5c |
| §6.3 嵌入 | 反向嵌入非承诺；只承诺符号与最小初始化顺序 | 仅导出 `xrt_runtime_init()` 顺序合同（safepoint 可用前不得建对象）；不提供完整嵌入 API | FFI-06 | M4.5c |
| §7.1 错误码 | `Int32` 出参 `0=ok`；已知码分类映射；未知码→`Internal` | 生成包装：`int32_t code` 出参 + 返回槽；映射表（§5.2）；未知码 → `ErrorKind.Internal`（`FFI-106` 仅在映射表缺失时触发内部断言，不静默 Ok） | FFI-01、FFI-05 | M4.5b |
| §7.2 取消/超时 | 必须映射 `Cancelled`/`Timeout`，不降级 `Internal` | 保留码段 `E_CANCELLED`/`E_TIMEOUT` 优先判定，映射到分类而非 Internal | FFI-05 | M4.5b |
| §7.3 阻塞分类 | 逐入口 `.aware/.unaware`；长阻塞须专用执行器伴生 | `.xfb` 每入口必带 `@blocking`，缺失 → `FFI-107`；生成伴生 `submit*` 形态的声明校验（有 `.unaware` + `longRunning = true` 时必须存在伴生入口） | FFI-07 | M4.5a（校验）/ M4.5b（形态） |
| §8 `@unsafe` | 仅绑定层；合同文本；应用不可创建 | `.xfb` 中 `@unsafe` 入口需附 `contract = "..."` 文本，且仅允许出现在 `bindings/` 目录（工程根校验）；S8 `link.unsafe = true` 才放行，否则构建失败并记录 | FFI-04 | M4.5a |
| §9 不变量 1—9 | 见 §5.1 对照 | 逐条落到校验器/生成器/运行时三层（§5.1 表） | 全部 | 全程 |
| §10 验收矩阵 | FFI-01—07 | 台账 7 行按 §6 切片分配；设计阶段不改状态（仍为未实现） | FFI-01—07 | — |
| §11 实现边界 | 合同可机械核验；pin 属实现细节 | 校验器对 `.xfb` 做全量机械核验；不可核验即拒绝（等同无租约） | FFI-01 | M4.5a |
| 附录 B 名称落定 | 注解与 `layout(c)` 只在绑定层；`xrt_*` 冻结 | `.xfb` 方言承载全部注解；语言文法零改动（xfront/sema 不动） | FFI-04、FFI-06 | M4.5a |

## 2. 归属与接口边界（编译器侧 / 运行时侧）

| 事项 | 归属 | 说明 |
| --- | --- | --- |
| 语言文法（`.x`） | 编译器侧（xfront） | **零改动**：不加 `extern`/`unsafe`/`layout` 关键字（S7 附录 B 已定案） |
| `.xfb` 绑定声明文件解析 | 运行时侧（`internal/codegen/ffi/decl.go` + lexer/parser） | 独立小方言；复用 xfront 词法包的 token 定义（仅引用，不改其代码） |
| 合同校验（租约/编组/布局/分类/`@unsafe`） | 运行时侧（`internal/codegen/ffi/check.go`） | 诊断码段位 `FFI-101`—`FFI-110`（实现侧段位；S7 不规定码值） |
| 绑定注册表（入口→签名/租约/错误码/分类） | 运行时侧（`internal/codegen/ffi/registry.go`） | codegen 核心经接口消费（ffi-contract.md 定义） |
| codegen emit 钩子 | 编译器侧提供基建，运行时侧挂接 | 编译器侧在 `emit_stmt/emit_expr` 保留 `FFICall` 节点分支，调用 `ffi.EmitCall(...)`；**接口签名由 ffi-contract.md 冻结** |
| mangle | 复用编译器侧的 `mangle.go` | FFI 不另起命名：原生符号名用户显式给（`cName`），XNull 侧包装函数用统一 mangle（`xn_ffi_<entry>`） |
| 登记根 / 句柄 / trampoline 运行时支持 | 运行时侧（`impl/runtime/xrt*.c`） | `xrt_handle`、`xrt_task_root_bind` 等按 §5.4 增补，走 runtime-contract 评审 |
| S7 台账行维护 | 运行时侧 | FFI-01—07 状态由阶段 B 实跑结果驱动翻绿 |

若编译器侧对 `FFICall` 钩子接口有异议，以书面变更单提修订；未修订前以 ffi-contract.md 冻结版为准（避免双写）。

## 3. `extern`/绑定声明语义（`.xfb`）

### 3.1 形态（示例）

```
// bindings/sqlite.xfb —— 绑定层声明文件（S7 §2.2 示例形态）
ffi sqlite {
  layout(c) struct Stat {
    Int64 size
    Int32 mode
  }

  @ffiEntry(cName = "sqlite3_open")
  @lease(path = .borrow, db = .transfer)
  @errorCode(codeParam = .result)
  @blocking(.unaware)
  Int ffiSqliteOpen(Bytes path, Handle db);

  @ffiEntry(cName = "sqlite3_close")
  @lease(db = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int ffiSqliteClose(Handle db);
}
```

### 3.2 语义规则（校验器强制，违者诊断）

1. 每个入口必须：`@ffiEntry(cName=…)` + `@lease(...)`（逐参数全覆盖）+ `@blocking(...)`；`@errorCode` 可选（无错误码入口返回 void/标量亦合法）；
2. 参数/返回类型限于 §4 编组表左列；表外即 `FFI-105`；
3. `.transfer` 必须伴随同库内 `.reclaim` 入口或 `neverReclaim = "理由"` 文本；
4. `Handle` 必须经 `handle` 块声明其 `close` 入口（幂等性由绑定层包装保证）；
5. `@unsafe` 入口必须带 `contract = "前提/违规后果"` 文本，且文件位于 `bindings/`；工程 `link.unsafe` 未开 → 构建失败；
6. `layout(c) struct` 字段限标量或嵌套 `layout(c)`；递归包含拒绝；
7. 入口不得出现 `Result`/可选/引用对象/闭包/容器/元组/String 移交（S7 §3.6）；
8. 校验器输出确定性（DET-01）：诊断按文件内声明序、注册表按入口名排序。

### 3.3 符号命名与 mangle 对接

- **原生符号名**：用户显式 `cName`（不改写、不加前缀；链接器视角原样）；
- **XNull 侧包装符号**：`xn_ffi_<entry>`（复用 mangle 纯函数风格，DET-01 可重现）；
- **运行时 ABI**：`xrt_*`（S7 §6.1 冻结）；`xrt.h` 是唯一对外头，内部 `rt_*` 不外露；
- 包装函数职责固定三步：① 入参编组（借出加 pin/canary、移交转所有权）→ ② 调原生 → ③ 出参解编 + 错误码→`Result` + 释放/归还。

## 4. 类型编组表

### 4.1 标量（双向直映）

| XNull | C ABI | 方向 | 备注 |
| --- | --- | --- | --- |
| `Int` / `UInt` | `int64_t` / `uint64_t` | 双向 | 固定 64 位 |
| `Int8/16/32/64`、`UInt8/16/32/64` | 对应定宽类型 | 双向 | |
| `Float` / `Float64` | `double` | 双向 | |
| `Float32` | `float` | 双向 | |
| `Bool` | `uint8_t` | 双向 | 入：非 0→1；出：1→true、0→false，其余值 `rt_fatal`（合同违规可见化） |
| `Char` | `uint32_t` | 双向 | Unicode 码点 |
| 指针宽整型 | 无 | — | 不提供（S1 §0.7） |

### 4.2 引用与容器（跨界规则）

| XNull | 边界表示 | 允许形态 | 禁止 |
| --- | --- | --- | --- |
| `String` / `Text` | `const char*` + `size_t` | `.borrow` 只读 | `.transfer`（`FFI-103`）、`.reclaim` |
| `Bytes` | `void*` + `size_t` | `.borrow` / `.transfer` / `.reclaim` | 越界写（canary 检出即 fatal） |
| `T[]`（T 标量或 `layout(c)`） | `T*` + `size_t count` | `.borrow` | 嵌套数组、引用元素 |
| `layout(c) struct` | 按字段布局的值结构（按值传/指针借出） | 值传递、`.borrow` | 含引用/可选/容器字段 |
| `Handle`（绑定层声明） | `xrt_handle*`（不透明） | 双向 | 算术/排序/序列化（S7 §4.3） |
| 闭包 | 不直接跨界；经 trampoline | 回调注册入口 | 作为参数直传（`FFI-105`） |
| `Result` | 不跨界 | — | 参数/返回均拒绝（INV-FFI-2） |
| `List`/`Map`/`Set`/元组/类实例/`T?` | 不跨界 | — | (`FFI-105`) |

### 4.3 `Result` 的 C 侧表示（非跨界，本地 ABI）

`Result<T,E>` 不进 FFI 签名；但包装函数**返回**它是 XNull 侧类型，C 表示为 m4-codegen-design §2.4 的 tag+union（`struct xn_result_<T>_<E>`）。原生错误码 → 本地 Result 的构造在包装函数内完成（§5.2）。

### 4.4 `T?` 与 NULL

`T?` 不跨界（S7 §3.6）。原生侧 NULL 语义只允许出现在两种映射里：① `Handle` 参数/返回——`NULL` → XNull 侧 `Handle?(none)`，由包装层转成可选（**在绑定包装内，不暴露到 FFI 签名**）；② `Bytes`/数组指针——`NULL` + `len=0` 视为空，`NULL` + `len>0` 为合同违规（`FFI-108`）。

## 5. 安全边界

### 5.1 不变量落地对照（S7 §9）

| 不变量 | 落地层 | 机制 |
| --- | --- | --- |
| INV-FFI-1 无租约拒绝 | 校验器 | 缺 `@lease` → `FFI-101`，构建失败 |
| INV-FFI-2 Result 禁跨 + 未知码≠Ok | 校验器 + 包装生成 | 类型白名单；`code` 映射表 miss → `Internal` |
| INV-FFI-3 取消/超时不降级 | 包装生成 | 保留码优先判定 |
| INV-FFI-4 对象引用不作地址 | 校验器 + 编组 | `rt_object*` 不可入参；句柄载荷为原生指针，反向不可解引用 XNull 对象 |
| INV-FFI-5 借出存活且 pin | 生成代码 + 运行时 | 调用点 mark-pin（单线程执行器 + 无堆搬移）+ canary |
| INV-FFI-6 trampoline env 为根 | 运行时 | `xrt_task_root_bind/unbind` + 销毁标志检查 |
| INV-FFI-7 只经稳定 ABI 管内存 | 构建检查 + 头文件 | 生成代码与绑定代码只 include `xrt.h`；`rt_*` 不对外 |
| INV-FFI-8 跨界 panic 终止进程 | 运行时 | trampoline/包装入口的 panic 路径 → `rt_fatal` |
| INV-FFI-9 句柄重复关闭安全 | 绑定层 + 运行时 | `xrt_handle_close` 幂等（标志位）、不依赖 deinit |

### 5.2 错误传播（C 无 Result）

```
原生 int32_t code = 0;
T value = native_fn(args..., &code);       // 生成代码
if (code != 0) {
    xn_result = xn_err_from_code(code, "native_fn");   // 映射表：已知→分类，未知→Internal
} else {
    xn_result = xn_ok(value);
}
```

- 映射表按库声明（`errorMap { 5 = NotFound, 14 = Cancelled, ... }`，`.xfb` 内可选块），缺省表为空 → 全部未知 → `Internal`（安全默认，绝不 `Ok`）；
- `E_CANCELLED`/`E_TIMEOUT` 保留码由绑定层映射，不经未知路径；
- 复杂错误（结构体）走句柄 + getter，不进错误码通道（S7 §7.1 基准约定）。

### 5.3 内存管理豁免的明确设计

**问题**：FFI 对象由 C 侧管理还是进入 rt 管理？

**决策（三层）**：

1. **原生分配的内存（`malloc`/库内部分配）永不进入 rt 管理**：不包裹 `rt_header`、不参与 ARC/GC；其生命周期完全由绑定层合同（`close()`、`.reclaim`、`free` 入口）承担。依据：INV-FFI-4「ARC/GC 不管理另一语言中的对象」、S3 §19；
2. **XNull 侧的句柄包装对象进入 ARC**：`xrt_handle` 是普通 ARC 对象（`rt_header` + 载荷 `{ void* native; close_fn; int closed; }`），deinit 只置位并告警（不自动 close，S7 §4.3 明确 close 显式、不以 deinit 为唯一路径）；载荷中的 `native` 指针**不被 scan 钩子枚举**（非 XNull 引用）；
3. **借出缓冲区（Bytes/数组）由 XNull 运行时持有**：调用期间 pin，返回后解除；原生不得保存指针（合同文本 + canary 检测兜底）。

即：**FFI 不改变判定表**——判定表只管 XNull 对象；原生对象不参与判定（豁免边界清晰、可机械核验：跨 `xrt_*` 的对象必须是 `rt_object*` 且其描述符在注册表中，反之为原生指针）。

### 5.4 运行时 ABI 面（与现有 `rt_{retain,release,...}` 的关系）

S7 §6.1 + 附录 B 冻结 `xrt_*` 前缀为 ABI 承诺；现有运行时内部符号是 `rt_*`。设计决策：

- 新增 `impl/runtime/xrt.h` + `xrt_abi.c`：**薄封装层**，把 S7 §6.1 入口表映射到内部 `rt_*` 实现（`xrt_alloc`→`rt_alloc_*`、`xrt_retain/release`→`rt_retain/release`、`xrt_weak_bind/read/clear`→`rt_weak_*`、`xrt_register_root`→`rt_gc_add_root` 等）；**内部实现不改名**（不动 M3 已验收代码）；
- codegen 生成代码与所有 FFI 包装/绑定代码只 include `xrt.h`；`rt.h` 降级为内部头（不随 SDK 分发）；
- 该增补列为 runtime-contract **P-08**（编译器侧评审项）。

## 6. 切片建议（阶段 B = M4.5）

| 切片 | 内容 | 依赖 | 验收锚点 | 台账 |
| --- | --- | --- | --- | --- |
| **M4.5a** 声明与校验 | `.xfb` 词法/解析、注解模型、合同校验（租约/三形态/布局/分类/`@unsafe`/`Result` 拒绝）、注册表、`xrt.h` 封装层骨架 | 无（可先于 codegen 实现） | 校验器负例全拒、正例全过；诊断码 FFI-101—110 各一条用例；注册表两次运行一致（DET-01） | FFI-01 部分、FFI-02 部分、FFI-04 部分、FFI-07 部分 |
| **M4.5b** 标量/字符串/缓冲区编组 + 错误码 | 包装函数生成（§3.3 三步）、标量/String/Bytes/数组编组、错误码→Result、链接集成（S8 §7 `link.libraries`） | M4.1a（emit 基建） | 调 `libc`（`strlen`/`snprintf` 一类）+ 自建小型 C 库：标量往返、String 借出只读、Bytes 往返、未知码→Internal、取消码不降级；无 FFI 工程空路径不回归 | FFI-01、FFI-02、FFI-03 部分、FFI-06 部分 |
| **M4.5c** 句柄/trampoline/pin | `xrt_handle` 与 close 幂等、`.transfer/.reclaim`、canary pin、trampoline + root 登记、注销后调用检测、回调 panic fatal | M4.5b | 句柄生命周期（打开/关闭/重复关闭）；移交后 XNull 不释放；canary 越界终止；回调注册/注销/注销后调用终止；panic→进程终止 | FFI-03、FFI-05、FFI-06（完整）、FFI-07（伴生形态） |
| **M4.5d** 文档与分类清单 | 逐 API 阻塞分类清单发布形态（S5 §9）、`xdk.sys` 绑定层文档 | M4.5c | 清单与入口注册表逐条一致（机械核验） | FFI-07 |

阶段 B 全程红线：不改 `impl/internal/**` 中 xfront/sema；codegen 核心改动只经 ffi-contract.md 约定的钩子。

## 7. 链接故事（S8 §7）

### 7.1 有 FFI 时

- 工程清单 `link { libraries { library sqlite3 { kind = dynamic; system = true } } }`（S8 §7）——**未声明的库不得链接**，FFI 绑定引用未声明库 → 构建失败（可审计）；
- `kind = static` → `-l<name>` + `-L<搜索路径>`；`kind = dynamic` → `-l<name>`（或 `-l:lib<name>.so`）；`system = true` → 不打包、不复制到产物目录；
- 搜索路径来源：工程相对 `libs/`（S8 约定目录）优先、`XNULL_LINK_PATH` 环境变量**否决**（禁环境读取纪律，S8 §5.5 同构）——只认清单与约定目录；跨平台扩展名差异由工具链探测（`.a/.lib`、`.so/.dylib/.dll`）；
- 链接顺序：`main.o + 单元 .o + libxrt.a + -l<libraries 声明序>`；静态库环形依赖以 `--start-group/--end-group`（GNU）或两次链接收敛（macOS `ld` 需要则显式重复）；
- 运行时 ABI 符号（`xrt_*`）由工具链自动链接，不需声明、不允许改写（S8 §7 末条）；
- 构建日志记录 `link.unsafe = true` 的启用（S8 §7）。

### 7.2 无 FFI 时（空路径）

- 无 `.xfb`、无 `link` 块 → 链接命令与 M4.2 完全一致（`libxrt.a` 单一依赖）；
- 空路径必须零成本：不解析 `.xfb`、不生成包装、不引入 `xrt_abi.o` 之外的新符号；回归断言：hello.x 的构建命令与产物摘要与 M4.2 基线一致。

## 8. 风险与开放点

1. **`xrt_*` 与 `rt_*` 双面**：封装层增加一次间接调用（非热点，可接受）；若编译器侧认为应直接改名为 `xrt_*`，需评估 M3 已验收代码与测试的重命名成本——本设计倾向前者（零回归）；
2. **canary 检测的成本与误报**：只在借出 `Bytes`/数组时插入，标量与 String 借出不插；误报风险来自原生合法写入 but 超声明长度——按 S7 属合同违规，终止进程是合规行为；
3. **句柄跨任务**：v1 单线程执行器无跨任务句柄，规则先实现"禁止"（运行时检查 `owning_task`），跨任务传递挂后续切片；
4. **trampoline 与 GC**：env 为根（`xrt_task_root_bind`）在 M4.5c 依赖 M3.4 已落地的根登记 API；
5. **阻塞分类与执行器**：`.aware` 入口在 v1 单线程运行时等价于同步调用（分类声明存档，调度器切片实现后才产生语义差异）；FFI-07 完整翻绿依赖调度器切片，届时联动 SCHED-01。

## 9. 实现状态（2026-11-06 追加）

| 切片 | 状态 | 证据 |
| --- | --- | --- |
| M4.5a 声明与校验 + `xrt.h` 骨架 | 完成 | `internal/codegen/ffi`（正例/12 类负例/确定性）、`test_abi.c` |
| M4.5b 编组与错误码 | 完成 | `EmitCall`/`EmitSupport`/`LinkArgs`/`BlockingManifest`；自带原生小库端到端（标量/String/句柄/Bytes canary/未知码→Internal/布局尺寸核对） |
| M4.5c 句柄与 pin | 完成 | 句柄幂等关闭 + 关闭入口状态登记 + `.transfer` 接管 + `.reclaim` 归还登记（调用即移交，无论返回码）+ canary 越界终止；跨任务句柄规则定案（ffi-contract §5.2） |
| M4.5d 分类清单 | 部分 | `impl/docs/blocking-classification.md` 由注册表机械核验（`TestBlockingClassificationDocInSync`） |

**已知限制（不静默降级：一律报错或记入 `Problems`）**：

1. `Bytes` 的 `.transfer/.reclaim` 需绑定层分配器合同（**显式归属：随资源/调度器切片**）；
2. `layout(c)` 以镜像 + 尺寸核对函数提供，不做逐字段偏移断言（需原生头）；
3. 回调（trampoline）**接口预留**：`EmitTrampoline` 显式 `ErrTrampolineReserved`——依赖调度器栈 pin/根登记与 P-09 后续回调钩子，两者就绪前不硬做；
4. 与 `xnull build` 的端到端接线按 P-09/P-10 评审条件执行（跨包重名已由 FFI-111 覆盖、LinkArgs 已去重升序；import 闭包与同批切换属编译器侧）。

