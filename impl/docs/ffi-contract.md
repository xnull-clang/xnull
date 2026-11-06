# FFI 子模块合同（impl/docs/ffi-contract.md）

> 性质：`internal/codegen` 核心（编译器侧）↔ `internal/codegen/ffi` 子模块（运行时侧）的**接口冻结界面**，
> 与 `runtime-contract.md`（运行时 ABI）并列。设计依据：`impl/docs/ffi-design.md`。
> 维护规则：接口变更由提出方（消费侧与提供侧各自提出）以书面变更单发起，双方确认后改本文件；不得口头变更。
> 状态：**提案冻结（2026-11-06，M4.5a 起生效；编译器侧可在 M4.1a 落地时提修订）**。

## 1. 分包与依赖方向

```
internal/codegen           （编译器侧：AST→C 生成核心）
        │  只依赖 ffi 包的公开接口
        ▼
internal/codegen/ffi       （运行时侧：声明解析、合同校验、注册表、包装/trampoline 生成）
        │  生成文本只 include xrt.h
        ▼
impl/runtime/xrt.h         （S7 §6.1 冻结 ABI；内部映射 rt_*）
```

- 依赖单向：codegen → ffi，ffi 不反向依赖 codegen（避免循环）；
- ffi 包对外**只暴露** §2 的三个入口；其余类型 internal 化（`decl`/`check`/`mangle` 细节不导出）。

## 2. 对外接口（冻结）

```go
package ffi

// Registry 是绑定声明的机器可读产物（确定性：按入口名排序）。
type Registry struct { /* 见 §3 */ }

// Load 解析并校验工程内全部 .xfb 文件（确定性顺序：路径字典序）。
// 无 .xfb 时返回空 Registry 与 nil error（空路径零成本）。
func Load(root string) (*Registry, []Diagnostic, error)

// EmitCall 生成一次 FFI 调用包装的 C 代码片段。
// 由 codegen 在遇到 FFICall 节点时调用；返回的片段含入参编组、调用、出参解编与错误映射。
func (r *Registry) EmitCall(entry string, args []ArgExpr, dst TempName) (Snippet, error)

// EmitSupport 生成注册表所需的支撑代码（句柄 close 包装、trampoline、映射表）。
// codegen 在单元级生成末尾调用一次；空注册表返回空片段。
func (r *Registry) EmitSupport() Snippet

// DeclareDiagnostics 返回 ffi 段位诊断码全集（codegen 诊断渲染复用 cli/diag）。
func DeclareDiagnostics() []DiagSpec
```

- `Diagnostic`/`Snippet`/`TempName`/`ArgExpr` 为朴素值类型（字符串 + 位置 + 已生成表达式文本），定义在 ffi 包内并由 codegen 引用；
- 所有生成文本**不含内部角色/工程治理字样**，只含 C 代码与必要注释（公开仓库纪律）；
- 片段确定性：同一 Registry + 同一实参序列 → 逐字节相同文本（DET-01）。

## 3. 注册表模型（`.xfb` 语义投影）

```go
type Entry struct {
    Name        string      // XNull 侧入口名（ffiXxx）
    CName       string      // 原生符号名（原样，不改写）
    Region      string      // 所属 ffi 块（库逻辑名，对应 link.libraries 的 library 名）
    Ret         BoundType   // 边界返回类型（void 合法）
    Params      []Param     // 边界参数（有序）
    Lease       []LeaseKind // 逐参数：Borrow / Transfer / Claim（.reclaim 入口为 Claim）
    ErrorCode   string      // 错误码出参形参名（空 = 无错误码通道）
    ErrorMap    []ErrRule   // 码 → ErrorKind 分类（有序，确定性）
    Blocking    Blocking    // Aware / Unaware
    LongRunning bool        // 需专用执行器伴生形态
    Unsafe      bool        // @unsafe 受控入口（须有 ContractText）
    ContractText string
    CloseOf     string      // 非空：该入口是某句柄的 close（幂等包装）
}
```

- `BoundType`：标量种类 / `String` / `Bytes` / `Array(elem)` / `LayoutStruct(name)` / `Handle(name)`；表外类型在校验期拒绝，永不进入注册表；
- 校验失败 → `Load` 返回全部诊断（不中断，可一次报多条，与前端风格一致）。

## 4. `.xfb` 方言（与 ffi-design.md §3 一致，摘录）

```
ffi <region> {
  layout(c) struct <Name> { <ScalarType> <field> ... }
  handle <Name> { close = <entryName> }
  errorMap { <int> = <ErrorKind> ... }
  @ffiEntry(cName = "<symbol>") @lease(<param> = .borrow|.transfer) ...
  @errorCode(codeParam = .<param>) @blocking(.aware|.unaware) [@longRunning]
  [@unsafe(contract = "...")]
  <RetType> <entryName>(<ParamType> <name>, ...);
}
```

- 注释 `//` 与 `/* */`；标识符与 xfront 词法一致（复用语汇规则，独立实现解析）；
- 诊断段位（M4.5a 实现锚定，`DeclareDiagnostics()` 返回全集并按此排序）：

| 码 | 语义 |
| --- | --- |
| `FFI-100` | 声明语法错误（词法/语法层） |
| `FFI-101` | 入口合同声明缺失或不完整：缺 `@ffiEntry`/`cName`、缺 `@lease`、租约与参数不匹配、未知注解 |
| `FFI-102` | `.transfer` 无对称 `.reclaim`（句柄类型以 close 合同替代、或 `neverReclaim = "理由"`） |
| `FFI-103` | `String`/`Text` 声明移交或归还（S7 §3.4） |
| `FFI-104` | 嵌套数组或数组元素类型非法（S7 §3.5） |
| `FFI-105` | 类型不跨边界（未知类型、可选、容器/闭包/Result、未声明句柄或结构、close 签名不符） |
| `FFI-106` | 错误码声明非法（`@errorCode` 形参缺失/非 `Int32`、`errorMap` 分类名非法） |
| `FFI-107` | 缺阻塞分类/分类值非法/长阻塞缺 `submit<Entry>` 伴生入口（S7 §7.3） |
| `FFI-108` | 裸指针类型或指针/长度合同违规（S7 §3.2） |
| `FFI-109` | `layout(c)` 违规（字段类型、递归包含、重名、空结构） |
| `FFI-110` | `@unsafe` 缺 `contract` 文本或不在 `bindings/` 下（S7 §8） |
| `FFI-111` | 重复声明（入口/结构/句柄同名，含跨声明块） |

## 5. 实现状态

| 项 | 状态 |
| --- | --- |
| `Load` / 解析 / 合同校验 / 注册表 | **完成**（M4.5a：`impl/internal/codegen/ffi/`，正例 + 12 类负例 + 确定性用例） |
| `EmitCall` / `EmitSupport` | **完成**（M4.5b：包装生成、标量/String/Bytes/数组/`layout(c)`/句柄编组、错误码归一、原生符号声明；未覆盖形态记入 `Snippet.Problems` 并附注释占位——构建侧必须视为失败） |
| `xrt.h` / `xrt_abi.c` 稳定 ABI 封装 | **完成**（分配/计数/弱表/根/安全点/任务根/字符串访问器/`xrt_bytes`/`xrt_handle`/`xrt_fatal`；`test_abi.c` 覆盖） |
| 句柄与借出 pin | **完成**（M4.5b/c：句柄幂等关闭、关闭入口状态登记、`.transfer` 接管、`.reclaim` 归还登记、canary 越界终止、跨任务规则定案 §5.2） |
| trampoline / 回调根登记 | **接口预留**（`EmitTrampoline` 显式 `ErrTrampolineReserved`；依赖调度器栈 pin/根登记语义，随调度器切片） |
| codegen 侧 `FFICall` 钩子 | 待编译器侧接入（提案 P-09 声明注入 + 包装调用；P-10 编译清单纳入 `xrt_abi.c`/`rt_std_*`） |

### 5.1 包装 ABI（v1，codegen 调用点消费）

```c
static int32_t xn_ffi_<entry>(<入参...>[, <retC> *xn_out]);
```

- 返回 0 = 成功（`xn_out` 有效）；非 0 = 原生错误码，分类经 `xn_ffi_<region>_error_kind(code)` 取得（未知码 → `"Internal"`，绝不当 `Ok`）；
- 编组约定：`String` → `(const char *bytes, size_t len)`；`Bytes` → `(void *data, size_t len)` 且调用期 canary 拷贝进出；数组 → `(T *items, size_t n)`；`layout(c)` → `xn_layout_<Name> *`；句柄借入 → `xrt_handle *`（已关闭即 fatal），句柄移交 → `xrt_handle **out`；
- 错误码出参（`@errorCode(codeParam = .<param>)`）：该形参不出现在包装签名中，由包装内部以局部码传递；
- 生成代码只 include `xrt.h`（INV-FFI-7）；原生符号声明以 `#ifndef XN_FFI_NATIVE_DECLS` 包裹，绑定层自带原生头时可关闭。

### 5.2 所有权与跨任务规则（P-09 条件 3 / M4.5c 收尾，2026-11-06 回签落地）

**编组所有权**（评审回签，与 §3.3 ARC 规则一致）：

- 入参 `String` 借用：包装内不 retain，指针/长度仅在调用期有效；
- 返回 `String` 所有权归调用方：包装内 `xrt_string_from_c` 复制产物按 move 语义接管；
- `Bytes` 借出：canary 拷贝进出，缓冲区所有权不跨界；
- 句柄 `.transfer`：原生经出参交出的对象由包装层 `xrt_handle_new` 接管；
- 句柄 `.reclaim`：调用即把所有权移交回原生，包装对象登记关闭（无论返回码）——已关闭句柄归还即合同违约（fatal）。

**跨任务句柄规则**：

- 句柄是普通 ARC 对象：可被任务捕获、共享、存入容器；原生指针字段创建后不可变；
- close 显式且幂等；"谁 open 谁 close" 的结构化约束由源码层（defer/withLock）表达，运行时不强制；
- 已关闭句柄重用：取原生指针返回 NULL，除 close 外的一切入口 fatal（用例：`test_abi.c`）；
- 运行时当前为单线程顺序执行（M3/M4），close 与使用的并发竞争不存在；真正的跨线程句柄规则（原子 close、双检）**显式归属：随调度器切片**。

**跨包入口重名（P-09 条件 1）**：`Load` 对全部 `.xfb` 声明块做跨块重名检测（`FFI-111`，覆盖入口/结构/句柄）——两文件同名入口即构建失败；包装名保持 `xn_ffi_<entry>` 无包段。

**链接参数确定性（P-10 条件 3）**：`LinkArgs` 去重 + 升序；注入位置（目标文件之后）由构建侧保证。

## 6. 交互记录（追加式，倒序）

- 2026-11-06 运行时侧：M4.5a 落地——诊断码扩至 `FFI-100`—`FFI-111` 并按实现锚定；`Load` 全量校验完成，生成函数保持冻结签名待 M4.5b。
- 2026-11-06 运行时侧：本文件建立，随 ffi-design.md 阶段 A 交付；接口为**提案冻结**，M4.5a 实现按此进行；编译器侧在 M4.1a emit 基建落地时可提修订（书面变更单）。
