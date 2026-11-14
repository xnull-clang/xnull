# XNull 解决方案 第 8 部分：工具链（模块 05：FFI 绑定合同与包装生成）

> **2026-11-15**：本文档是内部实现基线，不属于语言规范序列；实现细节（含 `.xfb` 等格式）可按实现需要修正。

> 本文是第 8 部分模块 05，只落实第 3 部分 §19、第 4 部分 §7、第 5 部分 §2.2/§9、第 7 部分与第 10 部分 §7 已定义的 FFI 合同；内部实现选择不构成语言语义；与第 1—8 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 8 部分（T8） |
| 模块 | 05 FFI 绑定合同与包装生成 / 10 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—8 部分约束） |
| 文档性质 | 第 8 部分模块详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 设计依据 | 第 3 部分 §19、第 4 部分 §7、第 5 部分 §2.2/§9、第 7 部分、第 10 部分 §7 |
| 组件 | `.xfb` 绑定声明解析、合同校验、绑定注册表、C 包装生成、链接参数、阻塞清单 |
| 上游输入 | `bindings/**/*.xfb`、工程链接声明 |
| 下游输出 | `Registry`、C 包装片段、LinkArgs、诊断 |
| 明确不含 | 语言文法、C 运行时核心（模块 03）、`xrt` ABI（模块 04）、工程生命周期（模块 06） |
| 配套文档 | 第 8 部分总览；模块 03、04、06 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。定义 `.xfb` 方言、校验规则、注册表、包装 ABI 与安全边界。 |

---

## 0. 定位

FFI 合同层把“能不能调用原生函数”变成可机械校验的声明与生成过程。

```
.xfb 声明
  → 词法/语法
  → 合同校验（租约/类型/布局/句柄/错误码/阻塞/unsafe）
  → Registry
  → 包装 C 片段（EmitCall/EmitSupport）
  → 编译器调用点 xn_ffi_<entry>
  → 原生符号
```

它不新增语言关键字，`.x` 文法零改动；所有 FFI 声明落在绑定层声明文件中。

---

## 1. 三合同面

跨边界只允许三种形态：

| 形态 | 表示 | 方向 |
| --- | --- | --- |
| 值 | 标量、`layout(c)` 结构、封送副本 | 双向 |
| 句柄 | `xrt_handle*`（不透明） | 双向 |
| 缓冲区 | `String`（借出）、`Bytes`、标量/布局数组 | 借出/移交/归还按租约 |

三形态之外一律拒绝：`Result`、可选、引用对象、闭包、`List`/`Map`/`Set`、元组、`String`/`Text` 移交、`rt_object*` 地址。

---

## 2. `.xfb` 方言

### 2.1 文件结构

```
ffi <region> {
  layout(c) struct <Name> {
    <ScalarType> <field>
    ...
  }

  handle <Name> {
    close = <entryName>
  }

  errorMap {
    <int> = <ErrorKind>
    ...
  }

  @ffiEntry(cName = "<symbol>")
  @lease(<param> = .borrow | .transfer)
  @errorCode(codeParam = .<param>)
  @blocking(.aware | .unaware)
  [@longRunning]
  [@unsafe(contract = "...")]
  <RetType> <entryName>(<ParamType> <name>, ...);
}
```

### 2.2 词法

- 标识符 `[A-Za-z_][A-Za-z0-9_]*`；
- 数字、字符串、标点；
- 注释 `//`、`/* */`；
- 诊断码 `FFI-100`（词法/语法）。

### 2.3 文件发现

- 从工程根递归查找 `.xfb`；
- 跳过隐藏目录与 `target/`；
- 路径字典序；
- 空注册表零成本。

---

## 3. 合同模式

### 3.1 入口必填

每个入口必须有：

1. `@ffiEntry(cName = "...")`；
2. 逐参数 `@lease(...)`，数量与签名一致；
3. `@blocking(.aware | .unaware)`。

可选：

- `@errorCode(codeParam = .<param>)`；
- `@longRunning`；
- `@unsafe(contract = "...")`。

### 3.2 租约

| 租约 | 含义 | 规则 |
| --- | --- | --- |
| `.borrow` | 所有权留在 XNull，原生仅本次调用可用 | 返回后指针失效；原生不得保留 |
| `.transfer` | 所有权交原生 | 必须有对称 `.reclaim` 或 `neverReclaim = "理由"` |
| `.reclaim` | 原生归还所有权 | 调用即移交；无论返回码 |
| 永不归还 | 进程生命周期对象 | 必须写明理由 |

### 3.3 类型白名单

| 类型 | 边界表示 |
| --- | --- |
| 标量 | 定宽 C 类型 |
| `String`/`Text` | `const char* + size_t`，仅借出 |
| `Bytes` | `void* + size_t` |
| `T[]` | `T* + count`，元素限标量/`layout(c)` |
| `layout(c)` | `xn_layout_<Name>*` |
| `Handle` | `xrt_handle*` |
| 回调 | trampoline，仅注册形态 |

### 3.4 布局

- `layout(c)` 字段限标量或嵌套 `layout(c)`；
- 按声明序、C 自然对齐；
- 递归/重名/空结构拒绝；
- 未标注 `struct` 只能封送/句柄；
- 当前以镜像结构 + 尺寸核对提供，不做逐字段偏移断言（需原生头）。

### 3.5 句柄

- 必须经 `handle` 块声明 `close`；
- close 入口签名匹配；
- close 幂等；
- 句柄不参与算术/排序/序列化；
- 跨任务共享需同步或所有权移交。

### 3.6 错误码

- `@errorCode` 形参必须是 `Int32`；
- `errorMap` 码 → `ErrorKind` 分类；
- 未知码 → `Internal`；
- 取消/超时保留码优先映射，不降级；
- 复杂错误走句柄 + getter。

### 3.7 阻塞

- `.aware`：任务感知，挂起不占线程；
- `.unaware`：占线程；
- 长阻塞 `.unaware` 必须有 `submit<Entry>` 伴生形态；
- 分类清单与注册表一致。

### 3.8 `@unsafe`

- 必须有 `contract = "前提/违规后果"`；
- 仅允许出现在 `bindings/` 下；
- 工程 `link.unsafe = true` 才放行；
- 应用代码不可创建。

---

## 4. 校验流程

```
Load(root)
  1. findXfb：递归、排序、跳过隐藏/target
  2. 逐文件 lex/parse
  3. 语法错误 → 该文件不进入合同校验
  4. 收集 region：入口/布局/句柄/errorMap
  5. 跨文件重名检测
  6. 逐入口合同校验
  7. 补源码片段、诊断排序
  8. 有诊断 → 返回 nil + 全部诊断
  9. 无诊断 → Registry 排序返回
```

诊断码：

| 码 | 语义 |
| --- | --- |
| `FFI-100` | 声明语法错误 |
| `FFI-101` | 入口合同缺失/不完整 |
| `FFI-102` | `.transfer` 缺 `.reclaim`/理由 |
| `FFI-103` | `String`/`Text` 移交/归还 |
| `FFI-104` | 嵌套数组/元素非法 |
| `FFI-105` | 类型不跨界 |
| `FFI-106` | 错误码声明非法 |
| `FFI-107` | 阻塞分类缺失/非法/长阻塞缺伴生 |
| `FFI-108` | 裸指针/指针长度合同违规 |
| `FFI-109` | `layout(c)` 违规 |
| `FFI-110` | `@unsafe` 缺合同文本/位置违规 |
| `FFI-111` | 重复声明（入口/结构/句柄，含跨文件） |

确定性：

- 文件按路径字典序；
- 诊断按文件/行/列/码排序；
- 注册表按名称排序；
- 同一输入同一输出。

---

## 5. Registry

```go
type Registry struct {
    Entries []Entry
    Layouts []Layout
    Handles []Handle
}

type Entry struct {
    Name         string
    CName        string
    Region       string
    Ret          BoundType
    Params       []Param
    Lease        []LeaseKind
    ErrorCode    string
    ErrorCodeRet bool
    ErrorMap     []ErrRule
    Blocking     Blocking
    LongRunning  bool
    Unsafe       bool
    ContractText string
    CloseOf      string
}
```

`BoundKind`：

```
KindVoid / KindScalar / KindString / KindText
KindBytes / KindArray / KindLayout / KindHandle
```

`Layout`：

```go
type Layout struct {
    Name   string
    Region string
    Fields []LayoutField
}
```

`Handle`：

```go
type Handle struct {
    Name   string
    Region string
    Close  string
}
```

Registry 是 codegen 与运行时的共同输入；空注册表表示无 FFI。

---

## 6. 包装生成

### 6.1 包装 ABI

```c
static int32_t xn_ffi_<entry>(<入参...>[, <retC> *xn_out]);
```

- 返回 0 成功；非 0 原生错误码；
- 分类经 `xn_ffi_<region>_error_kind(code)`；
- 未知码 → `Internal`；
- 生成代码只 include `xrt.h`；
- 原生声明可用 `XN_FFI_NATIVE_DECLS` 关闭。

### 6.2 编组

| 类型 | 入参 | 返回 |
| --- | --- | --- |
| 标量 | 对应 C 类型 | 出参 + 错误码 |
| `Bool` | `uint8_t` 0/1 | 出参，非 0/1 违规 fatal |
| `String` | `const char* + len` | `xrt_string*` 出参，复制接管 |
| `Bytes` | `void* + len` + canary | 当前未支持返回 |
| 数组 | `T* + n` | 当前未支持返回 |
| `layout(c)` | `xn_layout_* *` | 当前未支持返回 |
| `Handle` 借入 | `xrt_handle*`，取原生指针 | 出参 |
| `Handle` 移交 | `xrt_handle**` 出参 | 包装 `xrt_handle_new` |
| `Handle` 归还 | `xrt_handle*`，调用即登记关闭 | — |

### 6.3 错误码通道

两种模式：

1. `@errorCode(codeParam = .<param>)`：错误码作为原生形参出参，包装内局部 `int32_t`；
2. `.result`：错误码即原生返回值。

处理：

- 成功 → 写 `xn_out`；
- 失败 → 返回错误码，由调用点映射为 `Result`；
- close 入口：无论关闭返回码，句柄状态照常登记（关闭失败不等于未关闭）。

### 6.4 句柄

- 借入：已关闭/空 → fatal；
- close 入口：已关闭 → 幂等成功，不再触达原生；
- 移交：原生出参 → 包装 `xrt_handle_new`；
- 归还：调用即 `xrt_handle_mark_closed`，无论返回码；已关闭归还 fatal；
- deinit 不自动 close，只诊断泄漏。

### 6.5 canary

- `Bytes` 借出：分配 `n + 2*16`；
- 前后哨兵 `0xA5`/`0x5A`；
- 调用返回后校验；
- 越界 → `xrt_fatal`；
- 只在借出 `Bytes`/数组时插入；
- 不承诺检测全部越界写。

### 6.6 支撑代码

`EmitSupport` 生成：

- `#include "xrt.h"`；
- canary helper；
- 布局结构；
- 错误分类函数；
- 原生符号声明；
- 全部包装函数；
- 未生成入口注释占位 + `Problems`。

`Problems` 非空即构建失败，绝不静默跳过。

### 6.7 LinkArgs

```go
func LinkArgs(libs []LinkLib) []string
```

- 去重；
- 升序；
- `-l<name>`；
- 只认清单声明；
- 不读环境；
- 调用方保证排在目标文件之后；
- `-L` 由 CLI/构建层排序并放在 `-l` 前。

### 6.8 阻塞清单

`BlockingManifest`：

- 每入口：入口名、region、blocking、longRunning；
- 按入口名排序；
- 与 `blocking-classification.md` 机械核验；
- 长阻塞 `.unaware` 缺伴生 → 校验失败。

### 6.9 trampoline

- `EmitTrampoline` 当前显式 `ErrTrampolineReserved`；
- 依赖调度器栈 pin/根登记与回调钩子；
- 不做半成品回调；
- 预留 env 根登记/注销接口。

---

## 7. 安全不变量

| 编号 | 不变量 | 落地 |
| --- | --- | --- |
| INV-FFI-1 | 无租约声明拒绝 | 校验器 |
| INV-FFI-2 | `Result` 禁跨；未知码 ≠ Ok | 校验器 + 包装 |
| INV-FFI-3 | 取消/超时不降级 | 包装错误映射 |
| INV-FFI-4 | 对象引用不作地址 | 类型白名单/句柄 |
| INV-FFI-5 | 借出缓冲区存活/pin | canary + 调用期 |
| INV-FFI-6 | trampoline env 为根 | 预留/根登记 |
| INV-FFI-7 | 只经稳定 ABI 管内存 | 只 include `xrt.h` |
| INV-FFI-8 | 跨界 panic 终止 | `xrt_fatal` |
| INV-FFI-9 | 句柄重复关闭安全 | 幂等 close |

---

## 8. 与编译器/构建层接口

### 8.1 编译器

```go
func Load(root string) (*Registry, []Diagnostic, error)
func (r *Registry) EmitCall(entry string, args []ArgExpr, dst TempName) (Snippet, error)
func (r *Registry) EmitSupport() Snippet
```

- codegen 在调用点使用 `xn_ffi_<entry>`；
- `EmitCall` 当前返回整入口包装，`args/dst` 为兼容位；
- `EmitSupport` 单元级生成一次；
- `Snippet.Includes` 当前恒为 `xrt.h`。

### 8.2 编译器侧 `ffi_gen.go`（P-09 注入与调用）

`impl/internal/codegen/ffi_gen.go` 负责把绑定注册表接入编译器，而不是在 `ffi` 包内完成：

| 函数 | 作用 |
| --- | --- |
| `LoadFFI(root)` | 包装 `ffi.Load`，读取工程根 `.xfb` |
| `InjectFFI(u, reg)` | 把支持的入口注入为包级 `TopFunc` 声明，供 sema 名称/类型检查 |
| `UnsupportedFFIEntries(reg)` | 列出未纳入注入的入口及原因，构建侧输出提示 |

注入范围（当前）：

- 返回：`void`、`Int`/`Int64`、`String`；
- 参数：`Int`/`Int64` 标量、`String`（`.borrow`）；
- 编译单元内已有同名顶层声明 → 错误（入口重名防御）；
- 合成函数体只满足 sema 返回路径检查，代码生成不为它生成 C 函数；
- `@errorCode`、句柄 close、`Bytes`/数组/布局/句柄等其他形态显式跳过，调用点会以未定义标识符失败，不静默接受。

调用点 `ffiCallLines`：

- 标量实参直接生成；
- `String` 实参当前只支持变量，生成 `->bytes`/`->len` 借出视图，不 retain；
- 调 `xn_ffi_<entry>`，结果写入临时变量；
- 非零错误码 → 输出 fatal 诊断并 `exit(134)`，不隐藏、不吞错；
- 当前不把错误码映射为 `Result`，`@errorCode` 入口在注入阶段显式跳过。

构建流程：

1. `LoadUnits`；
2. `LoadFFI(filepath.Dir(srcPath))`；
3. `InjectFFI`；
4. `UnsupportedFFIEntries` 输出提示；
5. `sema.Analyze`；
6. `EmitCWithFFI`；
7. `cc` 编译链接。

边界：

- `ffi_gen.go` 只做 P-09 接线，不重新定义 FFI 合同；
- 合同校验/注册表仍归 `ffi` 包；
- 未纳入注入的入口必须显式提示，不静默降级；
- 编译器文档（模块 01）与本文必须同步。

### 8.3 构建层

- `LinkArgs` 注入链接命令；
- 只链接清单声明库；
- `rt_std_*`/`xrt_abi` 由构建清单纳入；
- 无 `.xfb` 时零成本。

---

## 9. 边界与未覆盖

| 能力 | 状态 |
| --- | --- |
| `.xfb` 解析/校验/注册表 | 完成 |
| 标量/String/Bytes/数组/布局/句柄编组 | 完成或显式 `Problems` |
| 错误码归一 | 完成 |
| 句柄 close/移交/归还 | 完成 |
| canary | 完成 |
| `Bytes` `.transfer/.reclaim` | 需绑定层分配器合同；显式归属后续切片 |
| `layout(c)` 逐字段偏移 | 当前镜像 + 尺寸核对 |
| trampoline | 接口预留 |
| 跨任务句柄并发规则 | 随调度器切片 |
| 编译器调用点注入 | 部分实现：`ffi_gen.go` 支持 void/Int/String 返回、Int/String 参数；错误码/句柄/其他类型显式跳过 |

原则：未覆盖形态必须报错或记入 `Problems`，不得静默降级。

---

## 10. 验证

| 测试 | 覆盖 |
| --- | --- |
| `ffi_test.go` | 解析、合同正例/负例、确定性 |
| `emit_test.go` | 包装生成、错误映射、句柄、canary |
| `xdk_test.go` | XDK 绑定联合编译运行 |
| `xdk_write_test.go` | 写文件绑定 |
| `test_abi.c` | 稳定 ABI/句柄 |
| `blocking-classification` 测试 | 清单与注册表一致 |

关键用例：

- 无租约拒绝；
- `String` 移交拒绝；
- 未知码 → Internal；
- `.transfer` 缺 `.reclaim` 拒绝；
- 句柄重复关闭成功；
- canary 越界 fatal；
- 注册表两次运行一致；
- 诊断排序稳定。

---

## 规范依据与实现选择

### 规范依据

| 第 1—8 部分条款 | 本模块落实 |
| --- | --- |
| 第 7 部分 §2—§9 | 三合同面、租约、布局、句柄、回调、ABI、错误码、阻塞、unsafe、安全不变量 |
| 第 3 部分 §19 | 跨语言所有权、对象引用不作地址、缓冲区存活 |
| 第 4 部分 §7 | 错误码映射、取消/超时不降级 |
| 第 5 部分 §2.2、§9 | 阻塞二分与分类清单 |
| 第 10 部分 §7 | 链接库声明与 unsafe 闸门 |

### 实现选择

- `.xfb` 方言与文件发现规则；
- 词法/语法解析器实现；
- Registry 数据结构；
- 包装 ABI v1 与 `xn_ffi_<entry>` 命名；
- canary 大小与哨兵值；
- `EmitCall`/`EmitSupport` 的片段边界；
- 编译器侧 `ffi_gen.go` 的 P-09 注入子集（void/Int/String、Int/String 参数；其余显式跳过）。

以上为实现选择，不新增语言语义；FFI 合同语义以第 3、4、5、7、8 部分为准。

## 11. 参考

- `impl/internal/codegen/ffi/`
- `impl/docs/ffi-design.md`
- `impl/docs/ffi-contract.md`
- `impl/docs/blocking-classification.md`
- `bindings/xdk/runtime.xfb`
- `bindings/xdk/sys.xfb`
- `XNull解决方案-第7部分-FFI-v1.1.0.md`
- `XNull解决方案-第3部分-内存管理-v3.1.0.md` §19
- `XNull解决方案-第4部分-错误处理-v1.1.0.md` §5
