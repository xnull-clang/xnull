# B3-09 类规范：K-01/02/03/05/07

> 只描述 Go codegen 现行发射规则，供 xnullc 对齐；不改代码。
> 基线：`handoff/B3-09-baseline.tsv`（241 文件；83 个 0 diff、59 个有 diff）。

## K-01 `void` 返回签名/定义

### 规则

1. `void` 的权威标志是 `TopFunc.Void` / `MethodDecl.Void`，不是 `Ret == nil`：
   ```go
   retC, _ := g.cType(fn.Ret) // cType(nil) 也返回 "void"
   if fn.Void { retC = "void" }
   ```
2. 原型与定义必须使用同一个 `retC`：
   - 顶层函数原型：`static <retC> xn_<name>(<params>);`
   - 函数定义：`<retC> xn_<name>(<params>) { ... }`
   - 方法原型/定义、构造器（恒 `void`）、实例/单态化同样走 `fn.Void`。
3. `void` 函数不生成 `xn_ret`（`hasResult = strings.HasPrefix(retC,"xn_Result_")`，
   void 非 Result），也不生成末尾返回槽。
4. `void` 方法在 `methodCall`/`protoDispatch` 中作为语句调用（返回 `void`），
   不得包成 `int64_t`。

### 代表入口与首条 diff

`examples/parser-seed.x`（1365 行 diff）：

```diff
-static void xn_show(rt_string * xn_p_s);
+static int64_t xn_show(rt_string * xn_p_s);
```

xnullc 把 `Void=true` 的函数按 `Ret` 缺失推导成了 `int64_t`；同一文件的定义也会
跟着错。`tests/b2/corpus/examples/parser-seed.x` 同。

## K-02 容器 typedef（`xn_arr_*` / `xn_set_*` / `xn_map_*`）

### 生成条件

- 任何 `cType(t)` 遇到 `T[]`/`List<T>` → `needArr(elemC)`；
  `Set<T>` → `needSet`（同时 needArr）；`Map<K,V>` → `needMap(kC,vC)`。
- 触发点包括：函数参数/返回、类/结构体字段、局部声明、`Result` 成员、
  `new T[n]`、容器字面量、容器方法接收者。
- **两遍发射**：第一遍试生成登记的类型集合保留到第二遍；第二遍开头统一输出
  “所有已登记容器”的 typedef（即使只在第一遍出现、最终未使用也会输出）。
- `cs.declared` 防重复；每遍正式输出前重置 `declared`，再统一 emit。

### 命名与顺序

1. 命名：
   - 数组：`xn_arr_<mangle(elem)>`
   - Set：`xn_set_<mangle(elem)>`
   - Map：`xn_map_<mangle(k)>_<mangle(v)>`
   - `mangle`：`int64_t→i`、`int→b`、`uint16_t→u16`、`rt_string*→s`、
     类引用 `xn_Cls_X*→o_X`、元组 `xn_tup_*→t_*`。
2. 输出顺序（`emitTypeDecls`）：
   - 先按元素类型名排序输出所有**数组** typedef；
   - 再按元素类型排序输出所有 **Set** typedef；
   - 最后按 `mapName` 排序输出所有 **Map** typedef。
3. 依赖顺序（整份 C）：
   - `prewarmTypeContainers` 先登记所有签名/字段/Result 成员里的容器；
   - **类/单例 struct 前向 typedef**；
   - **元组 typedef**（容器元素可能是元组）；
   - **容器 typedef**；
   - 类/函数原型；
   - `Result` typedef；
   - 容器 helper（`cs.emit`）在全局变量之后。
4. 容器 typedef 形式固定：
   ```c
   typedef struct { rt_header hdr; size_t len; size_t cap; <elem> *data; } xn_arr_<m>;
   typedef struct { rt_header hdr; <elem> *a; } xn_set_<m>;
   typedef struct { rt_header hdr; size_t len; size_t cap; <k> *keys; <v> *vals; } xn_map_<k>_<v>;
   ```

### 代表入口与首条 diff

`examples/classes.x`（264）：

```diff
 typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;
-
-typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;
```

`difftest/anchors/cases/pkg/f2.x`（1414）缺 `xn_map_s_s`；
`tests/b3/fixtures/bundle/app.x`（614）缺 `xn_arr_u16`。
xnullc 当前只输出部分容器 typedef，且未按“类前向 → 元组 → 容器”顺序。

## K-03 函数指针 typedef（`xn_fn_*`）

### 生成条件

- `cType` 遇到 `*xfront.FuncTypeRef`（函数类型字段、参数、返回）→
  `funcTypeC(ft)`。
- 闭包（Lambda）实参：`lambdaFuncType` 先按参数/返回推断签名，再 `funcTypeC`；
  无捕获闭包本体另生成 `xn_fn_lit_<taskID>` 函数（不是 typedef）。
- XDK-07 的 `keysArray/valuesArray` 等返回函数指针字段走同一路径。

### 命名与去重

```go
ret := cType(ft.Ret)
params := cType(each)
name := "xn_fn_" + sanitizeCName(ret + "_" + strings.Join(params, "_"))
```

- `sanitizeCName` 只保留 ASCII 字母/数字，其他字符→`_`；因此签名相同才同名，
  但不同签名清洗后可能碰撞（xnullc 应保持同一算法）。
- `fnTypes[name]=true`、`fnTypeSig[name]=ret+"|"+join(params,", ")` 去重。
- 发射：在协议/vtable 之后、枚举 typedef 之前，**按 typedef 名排序**：
  ```c
  typedef <ret> (*<name>)(<params>);
  ```
- 顺序依赖：`ret`/参数类型必须已可命名（类前向 typedef 已输出）。

### 代表入口与首条 diff

`tests/s6/xdk07/collections_basic.x`（1483）：

```diff
 typedef void *xn_proto_Error;
 typedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;
-
-typedef int (*xn_fn_int_int64_t_int64_t)(int64_t, int64_t);
```

xnullc 完全没有输出该 typedef（同类：`collections_nonnull.x` 1461）。

## K-05 Result 错误类型 typedef

### 命名

- 只接受两个 `NamedType` 实参：`Result<V,E>`；禁止嵌套 Result。
- 名：`xn_Result_<Vtag>_<Etag>`；`E=String` 保持 `xn_Result_<V>_String`。
- `resultArgs[name] = [V,E]` 供成员类型解析。

### 成员类型（`resultInfo`）

- `V`：`resultCType(V)`（标量/枚举/类指针/struct 值/协议指针/容器指针/Bytes/Text/
  ErrorKind/void 占位）。
- `E`：
  - `Error` 特例：资源工程（`import xdk.sys`）→ `xrt_error_kind`；否则协议
    `xn_proto_Error`；
  - `TaskError` / `CancelledError` → `xrt_error_kind`；
  - 其他走 `resultCType(E)`（String→`rt_string*`；类→`xn_Cls_X*`；结构体值；
    简单枚举→`xn_Enum_*`；`ErrorKind`→`xn_Enum_ErrorKind`）。
- typedef 形式（`cDecl` 对指针把 `*` 贴变量名）：
  ```c
  typedef struct { int ok; <V> v; <E> err; } xn_Result_<V>_<E>;
  ```

### 登记与发射顺序

- 登记来源：
  1. 顶层函数返回：`collectResult`；
  2. 函数体/类/结构体/枚举/单例/工厂字段与方法的 Result：`collectAllResults` +
     `collectStmt(LocalDeclStmt)`；
  3. FFI 入口：`fnRet` 注册（`g.results[c]=""`）；
  4. S6-09 net/HTTP 内建：`net609Result` 注册；
  5. S5/S6 内置 Result 构造点（sync/task/sys）在生成时注册。
- 发射：类/结构体/枚举前向 typedef 与容器 typedef 之后，按 **Result 名排序**；
  每个实例先 `resultInfo` 求成员类型再输出一行。
- 若 Result 成员是容器，容器 typedef 必须已提前输出（K-02 顺序）。

### 代表入口与首条 diff

`tests/s6/xdk05/sync_basic.x`（176）：

```diff
-typedef struct { int ok; int64_t v; xrt_error_kind err; } xn_Result_Int_CancelledError;
```

xnullc 未登记/未输出该实例（同类：`tests/b2/corpus/tests/s6/xdk05/sync_basic.x`）。

## K-07 bundle argv 上限：可行方案

### 现状

- B3-08b 的 `--emit-ast-bundle` 输出 JSON；xnullc 第 4 参数接收整段 JSON，
  AST 也作为第 2 参数；两者都在 **argv**。
- 大入口（`impl/lib/b2/xparser.x`）直接：
  `Errno 7 Argument list too long`；xlex.x 虽未触发但已 6.8k 行 diff。
- 这不是语义问题，是输入通道限制；不解决则 B3-09 无法覆盖大工程。

### 方案 A（推荐）：文件通道 + xnullc 自读

- 新 CLI 形态：
  ```bash
  xnullc --ast-file <entry.ast> --bundle-file <entry.bundle.json> \
         --project <xnull.projection> <entry.x>
  ```
- xnullc（XNull 源）读取文件：`readFileText(path)`（`xdk.sys`）→ String；
  bundle/AST 不含 NUL，UTF-8 String 可承载。
- 需要的 runtime/XDK 能力：
  1. `xdk.sys.readFileText(String) -> String` 的**解释器实现**（当前 interp 无
     sys 桥；C 侧已有 `xdkc_read_file_text`）；
  2. 文件大小上限声明（建议 ≥16 MiB；bundle_text 当前 ~150 KiB，
     xnfmt/xparser 会更大）；
  3. 失败路径（文件缺失/读失败）→ 明确诊断/退出码，不静默空 bundle；
- 优点：彻底绕开 argv；xnullc 自举后同样可用；无需拆分 AST 结构。

### 方案 B（过渡）：xnull 落盘 + 路径参数

- 给 `xnull --emit-ast-bundle` 增加 `-o <file>`（当前只 stdout；B3-08b 已可
  stdout 重定向），脚本把 AST/bundle 写到临时文件，再传路径给 xnullc。
- xnullc 仍需方案 A 的 `readFileText` 能力；只是 CLI 不需要改造 xnull 之外的
  管道。

### 方案 C（无新 runtime 的临时办法）：分片 argv

- 把 bundle 按 `<64 KiB` 切片，重复 `--bundle-part <chunk>`；xnullc 拼接后解析。
- 仍受总 argv 限制（只是提高上限）；不推荐作为 B3-09 基线方案。

### 建议

B3-09 采用 **A**：xnullc 增加 `--ast-file/--bundle-file/--project`，
`import xdk.sys` 并实现 interp 的 `readFileText`；同时保留现有 argv 形态做小样例
兼容。xnullc 最终产物（原生）也走文件通道，B4 自举不依赖 argv 长度。

## 附：五类与基线文件对应

| 类 | 基线中代表 | 当前 xnullc 缺/多 |
|---|---|---|
| K-01 | `examples/parser-seed.x` | `void` → `int64_t` |
| K-02 | `examples/classes.x`、`f2.x`、`bundle/app.x` | 容器 typedef 缺失/顺序 |
| K-03 | `collections_basic.x` | `xn_fn_*` typedef 完全缺失 |
| K-05 | `sync_basic.x` | `xn_Result_Int_CancelledError` 缺失 |
| K-07 | `impl/lib/b2/xparser.x` | bundle/AST argv 超限 |
